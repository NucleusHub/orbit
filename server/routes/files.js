import express from 'express'
import { randomUUID } from 'crypto'
import crypto from 'crypto'
import path from 'path'
import fs from 'node:fs'
import multer from 'multer'
import {
  S3Client,
  CreateBucketCommand,
  HeadBucketCommand,
  DeleteObjectCommand,
  PutObjectCommand,
  CopyObjectCommand,
  GetObjectCommand,
  DeleteBucketPolicyCommand,
} from '@aws-sdk/client-s3'
import jwt from 'jsonwebtoken'
import File from '../models/File.js'
import Folder from '../models/Folder.js'
import { hashPassword, verifyPassword } from '../utils/password.js'
import { requireAuth } from '../middleware/auth.js'
import { myGroups, groupIdSet, canView, canEdit, childScope, childOwnership } from '../utils/scope.js'
import { mimeFor } from '../utils/mime.js'
import { getUserSettings } from '../settings.js'
import { planVideo } from '../utils/transcode.js'
import { planImage } from '../utils/image.js'
import { enqueue, getProgress } from '../transcodeQueue.js'

const router = express.Router()
router.use(requireAuth)

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

const AUTH_SECRET = process.env.JWT_SECRET || 'nucleus-jwt-secret'
export function signFileToken(id) {
  return jwt.sign({ fid: String(id) }, AUTH_SECRET, { expiresIn: '6h' })
}
export const rawUrl = (id, token) => `/api/orbit/files/${id}/raw${token ? `?t=${token}` : ''}`

export async function resolveLock(file) {
  if (file.passwordHash) return { hash: file.passwordHash }
  if (file.folderId) {
    const folder = await Folder.findById(file.folderId).select('passwordHash').lean()
    if (folder?.passwordHash) return { hash: folder.passwordHash }
  }
  return null
}

function serializeFile(f, req) {
  const obj = f.toObject ? f.toObject() : { ...f }
  const { passwordHash, ...rest } = obj
  const prog = getProgress(obj._id)
  const base = {
    ...rest,
    shared: !!obj.groupId,
    canEdit: canEdit(obj, req.profile.profileId, req.gset),
    transcodeStatus: obj.transcodeStatus || 'none',
    ...(prog ? { transcodeProgress: prog.percent, transcodeEta: prog.eta } : {}),
  }
  if (passwordHash) return { ...base, protected: true }
  return { ...base, url: rawUrl(obj._id) }
}

const MAX_UPLOAD_BYTES = parseInt(process.env.ORBIT_MAX_UPLOAD_BYTES, 10) || 5 * 1024 * 1024 * 1024
const upload = multer({ dest: '/tmp/orbit-uploads', limits: { fileSize: MAX_UPLOAD_BYTES } })

function uploadSingle(field) {
  return (req, res, next) => upload.single(field)(req, res, err => {
    if (err) {
      const tooBig = err.code === 'LIMIT_FILE_SIZE'
      return res.status(tooBig ? 413 : 400).json({
        error: tooBig ? `File exceeds the ${Math.round(MAX_UPLOAD_BYTES / 1024 / 1024)} MB limit` : err.message,
      })
    }
    next()
  })
}

export function md5Base64(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('md5')
    const stream = fs.createReadStream(filePath)
    stream.on('error', reject)
    stream.on('data', chunk => hash.update(chunk))
    stream.on('end', () => resolve(hash.digest('base64')))
  })
}

async function ensureBucket() {
  try {
    await s3.send(new HeadBucketCommand({ Bucket: BUCKET }))
  } catch {
    await s3.send(new CreateBucketCommand({ Bucket: BUCKET }))
    console.log(`Created MinIO bucket: ${BUCKET}`)
  }
  try {
    await s3.send(new DeleteBucketPolicyCommand({ Bucket: BUCKET }))
  } catch {}
  console.log('MinIO bucket ready (private)')
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

router.post('/upload', uploadSingle('file'), async (req, res) => {
  const tmpPath = req.file?.path
  let objectKey = null
  let stored = false
  try {
    if (!req.file) return res.status(400).json({ error: 'No file provided' })
    if (!req.file.size) return res.status(400).json({ error: 'File is empty' })

    const actualSize = fs.statSync(tmpPath).size
    if (actualSize !== req.file.size) {
      return res.status(400).json({ error: 'Upload was incomplete; please retry' })
    }

    // Multer decodes multipart filenames as latin1.
    const originalName = Buffer.from(req.file.originalname, 'latin1').toString('utf8')

    const pid = req.profile.profileId
    const { folderId } = req.body
    let parent = null
    if (folderId) {
      parent = await Folder.findById(folderId)
      if (!canView(parent, pid, req.gset)) return res.status(404).json({ error: 'Not found' })
    }
    const own = childOwnership(parent, pid)
    const ext = path.extname(originalName)
    const keyPrefix = own.groupId ? `uploads/group/${own.groupId}` : `uploads/${pid}`
    objectKey = `${keyPrefix}/${randomUUID()}${ext}`

    const contentType = mimeFor(originalName, req.file.mimetype)

    const contentMD5 = await md5Base64(tmpPath)

    await s3.send(new PutObjectCommand({
      Bucket: BUCKET,
      Key: objectKey,
      Body: fs.createReadStream(tmpPath),
      ContentType: contentType,
      ContentLength: actualSize,
      ContentMD5: contentMD5,
    }))
    stored = true

    const doc = await File.create({
      filename: originalName,
      objectKey,
      mimeType: contentType,
      size: actualSize,
      folderId: folderId || null,
      ...own,
    })

    if (contentType.startsWith('video/') || contentType.startsWith('image/')) {
      try {
        const settings = await getUserSettings(pid)
        const needs = contentType.startsWith('video/')
          ? settings.transcodeVideos && (await planVideo(tmpPath, originalName)) !== 'skip'
          : settings.convertImages && planImage(originalName, contentType) !== 'skip'
        if (needs) {
          doc.transcodeStatus = 'pending'
          await doc.save()
          enqueue(doc._id)
        }
      } catch (err) {
        console.error('[orbit] media convert enqueue check failed:', err.message)
      }
    }

    res.status(201).json(serializeFile(doc, req))
  } catch (err) {
    if (stored && objectKey) {
      await s3.send(new DeleteObjectCommand({ Bucket: BUCKET, Key: objectKey })).catch(() => {})
    }
    res.status(500).json({ error: err.message })
  } finally {
    if (tmpPath) fs.unlink(tmpPath, () => {})
  }
})

const CONVERTIBLE_IMAGE_MIMES = ['image/heic', 'image/heif', 'image/tiff']
router.post('/convert-all', async (req, res) => {
  try {
    const pid = req.profile.profileId
    const files = await File.find({
      transcodeStatus: { $nin: ['done', 'pending', 'processing'] },
      $and: [
        { $or: [{ profileId: pid }, { ownerId: pid }] },
        { $or: [{ mimeType: { $regex: '^video/' } }, { mimeType: { $in: CONVERTIBLE_IMAGE_MIMES } }] },
      ],
    }).select('_id')

    const ids = files.map(f => f._id)
    if (ids.length) {
      await File.updateMany({ _id: { $in: ids } }, { transcodeStatus: 'pending' })
      ids.forEach(id => enqueue(id))
    }
    res.json({ queued: ids.length })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// No canView gate: the recipient of a shared file must be able to save it.
router.post('/:id/save', async (req, res) => {
  try {
    const pid = req.profile.profileId
    const src = await File.findById(req.params.id)
    if (!src) return res.status(404).json({ error: 'Not found' })

    const ext = path.extname(src.filename) || ''
    const objectKey = `uploads/${pid}/${randomUUID()}${ext}`
    const contentType = mimeFor(src.filename, src.mimeType)
    const copySource = `${BUCKET}/${src.objectKey}`.split('/').map(encodeURIComponent).join('/')
    await s3.send(new CopyObjectCommand({
      Bucket: BUCKET,
      CopySource: copySource,
      Key: objectKey,
      // CopyObject doesn't reliably carry Content-Type over.
      MetadataDirective: 'REPLACE',
      ContentType: contentType,
    }))

    const doc = await File.create({
      filename: src.filename,
      objectKey,
      mimeType: contentType,
      size: src.size,
      folderId: null,
      profileId: pid,
    })
    res.status(201).json(serializeFile(doc, req))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

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
    const own = childOwnership(targetFolder, pid)
    file.folderId = target
    file.groupId = own.groupId
    file.ownerId = own.ownerId
    file.profileId = own.profileId
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

router.post('/:id/transcode', async (req, res) => {
  try {
    const file = await loadEditable(req, res)
    if (!file) return
    const isMedia = file.mimeType?.startsWith('video/') || file.mimeType?.startsWith('image/')
    if (!isMedia) {
      return res.status(400).json({ error: 'Only videos and images can be converted' })
    }
    if (file.transcodeStatus === 'pending' || file.transcodeStatus === 'processing') {
      return res.json(serializeFile(file, req))
    }
    file.transcodeStatus = 'pending'
    await file.save()
    enqueue(file._id)
    res.json(serializeFile(file, req))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.post('/:id/unlock', async (req, res) => {
  try {
    const file = await File.findById(req.params.id)
    if (!canView(file, req.profile.profileId, req.gset)) return res.status(404).json({ error: 'Not found' })
    const lock = await resolveLock(file)
    if (!lock) return res.json({ url: rawUrl(file._id) })
    if (!verifyPassword(req.body.password || '', lock.hash)) {
      return res.status(401).json({ error: 'Wrong password' })
    }
    res.json({ url: rawUrl(file._id, signFileToken(file._id)) })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.get('/:id/raw', async (req, res) => {
  try {
    const file = await File.findById(req.params.id)
    if (!file || !canView(file, req.profile.profileId, req.gset)) return res.status(404).end()

    const lock = await resolveLock(file)
    if (lock) {
      let ok = false
      try { ok = jwt.verify(String(req.query.t || ''), AUTH_SECRET)?.fid === String(file._id) } catch {}
      if (!ok) return res.status(403).json({ error: 'Locked' })
    }

    const range = req.headers.range
    const out = await s3.send(new GetObjectCommand({ Bucket: BUCKET, Key: file.objectKey, ...(range ? { Range: range } : {}) }))
    res.set('Accept-Ranges', 'bytes')
    if (file.mimeType) res.type(file.mimeType)
    if (out.ContentLength != null) res.set('Content-Length', String(out.ContentLength))
    if (out.ContentRange) { res.status(206); res.set('Content-Range', out.ContentRange) }
    const body = out.Body
    body.on('error', () => (res.headersSent ? res.destroy() : res.status(502).end()))
    res.on('close', () => body.destroy?.())
    body.pipe(res)
  } catch (err) {
    const code = err?.$metadata?.httpStatusCode
    if (code === 416) return res.status(416).set('Content-Range', 'bytes */*').end()
    if (code === 404 || err?.name === 'NoSuchKey') return res.status(404).end()
    if (!res.headersSent) res.status(500).end()
  }
})

router.delete('/:id', async (req, res) => {
  try {
    const file = await loadEditable(req, res)
    if (!file) return
    // Delete the object before the record so a failed delete stays retryable.
    await s3.send(new DeleteObjectCommand({ Bucket: BUCKET, Key: file.objectKey }))
    await File.findByIdAndDelete(file._id)
    res.json({ ok: true })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

export default router
