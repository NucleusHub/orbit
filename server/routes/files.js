import express from 'express'
import { randomUUID } from 'crypto'
import path from 'path'
import fs from 'node:fs'
import multer from 'multer'
import {
  S3Client,
  CreateBucketCommand,
  HeadBucketCommand,
  DeleteObjectCommand,
  PutObjectCommand,
  PutBucketPolicyCommand,
} from '@aws-sdk/client-s3'
import File from '../models/File.js'
import Folder from '../models/Folder.js'
import { hashPassword, verifyPassword } from '../utils/password.js'
import { requireAuth } from '../middleware/auth.js'
import { myGroups, groupIdSet, canView, canEdit, childScope, childOwnership } from '../utils/scope.js'

const router = express.Router()
router.use(requireAuth)

// Load the caller's group membership once per request (req.groups / req.gset).
router.use(async (req, _res, next) => {
  try {
    req.groups = await myGroups(req.profile.profileId)
    req.gset = groupIdSet(req.groups)
    next()
  } catch (err) {
    next(err)
  }
})

export const BUCKET = process.env.MINIO_BUCKET || 'orbit-uploads'
const MINIO_INTERNAL = `http://${process.env.MINIO_ENDPOINT || 'minio'}:${process.env.MINIO_PORT || '9000'}`

export const s3 = new S3Client({
  region: 'us-east-1',
  endpoint: MINIO_INTERNAL,
  credentials: {
    accessKeyId: process.env.MINIO_ACCESS_KEY,
    secretAccessKey: process.env.MINIO_SECRET_KEY,
  },
  forcePathStyle: true,
  requestChecksumCalculation: 'WHEN_REQUIRED',
  responseChecksumValidation: 'WHEN_REQUIRED',
})

function fileUrl(objectKey) {
  return `/${BUCKET}/${objectKey}`
}

function serializeFile(f, req) {
  const obj = f.toObject ? f.toObject() : { ...f }
  const { passwordHash, ...rest } = obj
  const base = { ...rest, shared: !!obj.groupId, canEdit: canEdit(obj, req.profile.profileId, req.gset) }
  if (passwordHash) return { ...base, protected: true }
  return { ...base, url: fileUrl(obj.objectKey) }
}

const upload = multer({ dest: '/tmp/orbit-uploads' })

async function ensureBucket() {
  try {
    await s3.send(new HeadBucketCommand({ Bucket: BUCKET }))
  } catch {
    await s3.send(new CreateBucketCommand({ Bucket: BUCKET }))
    console.log(`Created MinIO bucket: ${BUCKET}`)
  }
  await s3.send(new PutBucketPolicyCommand({
    Bucket: BUCKET,
    Policy: JSON.stringify({
      Version: '2012-10-17',
      Statement: [{
        Effect: 'Allow',
        Principal: { AWS: ['*'] },
        Action: ['s3:GetObject'],
        Resource: [`arn:aws:s3:::${BUCKET}/*`],
      }],
    }),
  }))
  console.log('MinIO bucket ready')
}

ensureBucket().catch(err => console.error('MinIO init error:', err.message))

router.get('/', async (req, res) => {
  try {
    const pid = req.profile.profileId
    const { folderId, search } = req.query
    const fid = folderId || null

    let scope = { profileId: pid, groupId: null }
    if (fid) {
      const parent = await Folder.findById(fid)
      if (!canView(parent, pid, req.gset)) return res.status(404).json({ error: 'Not found' })
      scope = childScope(parent, pid)
    }
    const query = { folderId: fid, ...scope }
    if (search) query.filename = { $regex: search, $options: 'i' }
    const files = await File.find(query).sort({ createdAt: -1 })
    res.json(files.map(f => serializeFile(f, req)))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// Most-recent PERSONAL files across every folder (used by the Orbit dashboard
// widget). Shared-group files are excluded — their folder paths live outside
// the user's personal tree.
router.get('/recent', async (req, res) => {
  try {
    const pid = req.profile.profileId
    const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 8, 1), 50)
    const [files, folders] = await Promise.all([
      File.find({ profileId: pid, groupId: null }).sort({ createdAt: -1 }).limit(limit),
      Folder.find({ profileId: pid, groupId: null }).select('name parentId'),
    ])
    const byId = new Map(folders.map(f => [String(f._id), f]))
    const pathOf = (fid) => {
      const parts = []
      let cur = fid ? byId.get(String(fid)) : null
      let guard = 0
      while (cur && guard++ < 50) {
        parts.unshift(cur.name)
        cur = cur.parentId ? byId.get(String(cur.parentId)) : null
      }
      return parts
    }
    res.json(files.map(f => ({
      ...serializeFile(f, req),
      folderId: f.folderId ? String(f.folderId) : null,
      path: pathOf(f.folderId),
    })))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.post('/upload', upload.single('file'), async (req, res) => {
  const tmpPath = req.file?.path
  try {
    const pid = req.profile.profileId
    const { folderId } = req.body
    let parent = null
    if (folderId) {
      parent = await Folder.findById(folderId)
      if (!canView(parent, pid, req.gset)) return res.status(404).json({ error: 'Not found' })
    }
    const own = childOwnership(parent, pid) // { groupId, ownerId, profileId }
    const ext = path.extname(req.file.originalname)
    const keyPrefix = own.groupId ? `uploads/group/${own.groupId}` : `uploads/${pid}`
    const objectKey = `${keyPrefix}/${randomUUID()}${ext}`

    await s3.send(new PutObjectCommand({
      Bucket: BUCKET,
      Key: objectKey,
      Body: fs.createReadStream(tmpPath),
      ContentType: req.file.mimetype,
      ContentLength: req.file.size,
    }))

    const doc = await File.create({
      filename: req.file.originalname,
      objectKey,
      mimeType: req.file.mimetype,
      size: req.file.size,
      folderId: folderId || null,
      ...own,
    })

    res.status(201).json(serializeFile(doc, req))
  } catch (err) {
    res.status(500).json({ error: err.message })
  } finally {
    if (tmpPath) fs.unlink(tmpPath, () => {})
  }
})

// Resolve a file and enforce view/edit permission. Returns the doc, or null
// after sending the appropriate error response.
async function loadEditable(req, res) {
  const pid = req.profile.profileId
  const file = await File.findById(req.params.id)
  if (!canView(file, pid, req.gset)) { res.status(404).json({ error: 'Not found' }); return null }
  if (!canEdit(file, pid, req.gset)) { res.status(403).json({ error: 'Only the owner can change this' }); return null }
  return file
}

router.patch('/:id/rename', async (req, res) => {
  try {
    const file = await loadEditable(req, res)
    if (!file) return
    file.filename = req.body.filename
    await file.save()
    res.json(serializeFile(file, req))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.patch('/:id/move', async (req, res) => {
  try {
    const pid = req.profile.profileId
    const file = await loadEditable(req, res)
    if (!file) return

    const target = req.body.folderId || null
    let targetFolder = null
    if (target) {
      targetFolder = await Folder.findById(target)
      if (!canView(targetFolder, pid, req.gset)) return res.status(404).json({ error: 'Not found' })
    }
    const itemGroup = file.groupId ? String(file.groupId) : null
    const destGroup = target ? (targetFolder.groupId ? String(targetFolder.groupId) : null) : null
    if (itemGroup !== destGroup) return res.status(400).json({ error: 'Cannot move between personal and shared storage' })

    file.folderId = target
    await file.save()
    res.json(serializeFile(file, req))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.patch('/:id/password', async (req, res) => {
  try {
    const file = await loadEditable(req, res)
    if (!file) return
    file.passwordHash = req.body.password ? hashPassword(req.body.password) : null
    await file.save()
    res.json(serializeFile(file, req))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.post('/:id/unlock', async (req, res) => {
  try {
    const file = await File.findById(req.params.id)
    if (!canView(file, req.profile.profileId, req.gset)) return res.status(404).json({ error: 'Not found' })
    if (!file.passwordHash) return res.json({ url: fileUrl(file.objectKey) })
    if (!verifyPassword(req.body.password || '', file.passwordHash)) {
      return res.status(401).json({ error: 'Wrong password' })
    }
    res.json({ url: fileUrl(file.objectKey) })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.delete('/:id', async (req, res) => {
  try {
    const file = await loadEditable(req, res)
    if (!file) return
    await File.findByIdAndDelete(file._id)
    await s3.send(new DeleteObjectCommand({ Bucket: BUCKET, Key: file.objectKey }))
    res.json({ ok: true })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

export default router
