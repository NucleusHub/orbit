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

const router = express.Router()

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

// GET /api/orbit/files
router.get('/', async (req, res) => {
  try {
    const { folderId, search } = req.query
    const query = { userId: 'default', folderId: folderId || null }
    if (search) query.filename = { $regex: search, $options: 'i' }
    const files = await File.find(query).sort({ createdAt: -1 })
    res.json(files.map(serializeFile))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// POST /api/orbit/files/upload — multipart upload, streamed to MinIO
router.post('/upload', upload.single('file'), async (req, res) => {
  const tmpPath = req.file?.path
  try {
    const { folderId } = req.body
    const ext = path.extname(req.file.originalname)
    const objectKey = `uploads/default/${randomUUID()}${ext}`

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
      userId: 'default',
    })

    res.status(201).json(serializeFile(doc))
  } catch (err) {
    res.status(500).json({ error: err.message })
  } finally {
    if (tmpPath) fs.unlink(tmpPath, () => {})
  }
})

// PATCH /api/orbit/files/:id/rename
router.patch('/:id/rename', async (req, res) => {
  try {
    const file = await File.findByIdAndUpdate(
      req.params.id,
      { filename: req.body.filename },
      { new: true }
    )
    if (!file) return res.status(404).json({ error: 'Not found' })
    res.json(serializeFile(file))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// PATCH /api/orbit/files/:id/move
router.patch('/:id/move', async (req, res) => {
  try {
    const file = await File.findByIdAndUpdate(
      req.params.id,
      { folderId: req.body.folderId || null },
      { new: true }
    )
    if (!file) return res.status(404).json({ error: 'Not found' })
    res.json(serializeFile(file))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// PATCH /api/orbit/files/:id/password — set or remove password
router.patch('/:id/password', async (req, res) => {
  try {
    const { password } = req.body
    const hash = password ? hashPassword(password) : null
    const file = await File.findByIdAndUpdate(req.params.id, { passwordHash: hash }, { new: true })
    if (!file) return res.status(404).json({ error: 'Not found' })
    res.json(serializeFile(file))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// POST /api/orbit/files/:id/unlock — verify password, return URL
router.post('/:id/unlock', async (req, res) => {
  try {
    const file = await File.findById(req.params.id)
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

// DELETE /api/orbit/files/:id
router.delete('/:id', async (req, res) => {
  try {
    const file = await File.findByIdAndDelete(req.params.id)
    if (!file) return res.status(404).json({ error: 'Not found' })
    await s3.send(new DeleteObjectCommand({ Bucket: BUCKET, Key: file.objectKey }))
    res.json({ ok: true })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

export default router
