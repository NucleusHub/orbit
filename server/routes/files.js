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
    res.json(files.map(f => ({ ...f.toObject(), url: fileUrl(f.objectKey) })))
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

    res.status(201).json({ ...doc.toObject(), url: fileUrl(objectKey) })
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
    res.json({ ...file.toObject(), url: fileUrl(file.objectKey) })
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
