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
import { hashPassword, verifyPassword } from '../utils/password.js'
import { requireAuth } from '../middleware/auth.js'

const router = express.Router()
router.use(requireAuth)

const BUCKET = process.env.MINIO_BUCKET || 'orbit-uploads'
const MINIO_INTERNAL = `http://${process.env.MINIO_ENDPOINT || 'minio'}:${process.env.MINIO_PORT || '9000'}`

const s3 = new S3Client({
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

function serializeFile(f) {
  const obj = f.toObject ? f.toObject() : { ...f }
  const { passwordHash, ...rest } = obj
  if (passwordHash) return { ...rest, protected: true }
  return { ...rest, url: fileUrl(obj.objectKey) }
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
    const { folderId, search } = req.query
    const query = { profileId: req.profile.profileId, folderId: folderId || null }
    if (search) query.filename = { $regex: search, $options: 'i' }
    const files = await File.find(query).sort({ createdAt: -1 })
    res.json(files.map(serializeFile))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.post('/upload', upload.single('file'), async (req, res) => {
  const tmpPath = req.file?.path
  try {
    const { folderId } = req.body
    const ext = path.extname(req.file.originalname)
    const profileId = String(req.profile.profileId)
    const objectKey = `uploads/${profileId}/${randomUUID()}${ext}`

    await s3.send(new PutObjectCommand({
      Bucket: BUCKET,
      Key: objectKey,
      Body: fs.createReadStream(tmpPath),
      ContentType: req.file.mimetype,
      ContentLength: req.file.size,
    }))

    const doc = await File.create({
      profileId: req.profile.profileId,
      filename: req.file.originalname,
      objectKey,
      mimeType: req.file.mimetype,
      size: req.file.size,
      folderId: folderId || null,
    })

    res.status(201).json(serializeFile(doc))
  } catch (err) {
    res.status(500).json({ error: err.message })
  } finally {
    if (tmpPath) fs.unlink(tmpPath, () => {})
  }
})

router.patch('/:id/rename', async (req, res) => {
  try {
    const file = await File.findOneAndUpdate(
      { _id: req.params.id, profileId: req.profile.profileId },
      { filename: req.body.filename },
      { new: true }
    )
    if (!file) return res.status(404).json({ error: 'Not found' })
    res.json(serializeFile(file))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.patch('/:id/move', async (req, res) => {
  try {
    const file = await File.findOneAndUpdate(
      { _id: req.params.id, profileId: req.profile.profileId },
      { folderId: req.body.folderId || null },
      { new: true }
    )
    if (!file) return res.status(404).json({ error: 'Not found' })
    res.json(serializeFile(file))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.patch('/:id/password', async (req, res) => {
  try {
    const { password } = req.body
    const hash = password ? hashPassword(password) : null
    const file = await File.findOneAndUpdate(
      { _id: req.params.id, profileId: req.profile.profileId },
      { passwordHash: hash },
      { new: true }
    )
    if (!file) return res.status(404).json({ error: 'Not found' })
    res.json(serializeFile(file))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.post('/:id/unlock', async (req, res) => {
  try {
    const file = await File.findOne({ _id: req.params.id, profileId: req.profile.profileId })
    if (!file) return res.status(404).json({ error: 'Not found' })
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
    const file = await File.findOneAndDelete({ _id: req.params.id, profileId: req.profile.profileId })
    if (!file) return res.status(404).json({ error: 'Not found' })
    await s3.send(new DeleteObjectCommand({ Bucket: BUCKET, Key: file.objectKey }))
    res.json({ ok: true })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

export default router
