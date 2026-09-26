import fs from 'node:fs'
import path from 'node:path'
import { randomUUID } from 'node:crypto'
import { pipeline } from 'node:stream/promises'
import { GetObjectCommand, PutObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3'
import File from './models/File.js'
import { s3, BUCKET, md5Base64 } from './routes/files.js'
import { planVideo, transcodeToMp4, remuxToMp4 } from './utils/transcode.js'
import { planImage, convertToJpeg } from './utils/image.js'

const MAX_CONCURRENT = Number(process.env.ORBIT_TRANSCODE_CONCURRENCY) || 1
const WORK_DIR = '/tmp/orbit-transcode'

const queued = []
const inFlight = new Set()
let active = 0

const progress = new Map()
export function getProgress(fileId) {
  return progress.get(String(fileId)) || null
}

export function enqueue(fileId) {
  const id = String(fileId)
  if (inFlight.has(id) || queued.includes(id)) return
  queued.push(id)
  pump()
}

function pump() {
  while (active < MAX_CONCURRENT && queued.length) {
    const id = queued.shift()
    inFlight.add(id)
    active++
    processFile(id)
      .catch((err) => console.error('[orbit] transcode job crashed:', err?.message))
      .finally(() => {
        inFlight.delete(id)
        active--
        pump()
      })
  }
}

async function markStatus(fileId, status) {
  try {
    await File.findByIdAndUpdate(fileId, { transcodeStatus: status })
  } catch (err) {
    console.error('[orbit] failed to set transcodeStatus:', err.message)
  }
}

async function processFile(fileId) {
  const file = await File.findById(fileId)
  if (!file) return
  if (file.transcodeStatus !== 'pending' && file.transcodeStatus !== 'processing') return

  await markStatus(fileId, 'processing')

  fs.mkdirSync(WORK_DIR, { recursive: true })
  const srcPath = path.join(WORK_DIR, `${randomUUID()}${path.extname(file.filename) || ''}`)
  let outPath = null
  try {
    const obj = await s3.send(new GetObjectCommand({ Bucket: BUCKET, Key: file.objectKey }))
    await pipeline(obj.Body, fs.createWriteStream(srcPath))

    const isVideo = file.mimeType?.startsWith('video/')
    const isImage = file.mimeType?.startsWith('image/')

    let outExt, outMime
    if (isVideo) {
      const plan = await planVideo(srcPath, file.filename)
      if (plan === 'skip') { await markStatus(fileId, 'done'); return }
      outExt = '.mp4'; outMime = 'video/mp4'
      outPath = `${srcPath}.mp4`
      if (plan === 'remux') await remuxToMp4(srcPath, outPath)
      else await transcodeToMp4(srcPath, outPath, { onProgress: (p) => progress.set(String(fileId), p) })
    } else if (isImage) {
      const plan = planImage(file.filename, file.mimeType)
      if (plan === 'skip') { await markStatus(fileId, 'done'); return }
      outExt = '.jpg'; outMime = 'image/jpeg'
      outPath = `${srcPath}.jpg`
      await convertToJpeg(srcPath, outPath)
    } else {
      await markStatus(fileId, 'done')
      return
    }

    const size = fs.statSync(outPath).size
    const newName = file.filename.replace(/\.[^.]*$/, '') + outExt
    const keyPrefix = file.groupId ? `uploads/group/${file.groupId}` : `uploads/${file.profileId}`
    const newKey = `${keyPrefix}/${randomUUID()}${outExt}`
    const contentMD5 = await md5Base64(outPath)

    await s3.send(new PutObjectCommand({
      Bucket: BUCKET,
      Key: newKey,
      Body: fs.createReadStream(outPath),
      ContentType: outMime,
      ContentLength: size,
      ContentMD5: contentMD5,
    }))

    const fresh = await File.findById(fileId)
    if (!fresh) {
      await s3.send(new DeleteObjectCommand({ Bucket: BUCKET, Key: newKey })).catch(() => {})
      return
    }
    const oldKey = fresh.objectKey
    fresh.objectKey = newKey
    fresh.filename = newName
    fresh.mimeType = outMime
    fresh.size = size
    fresh.transcodeStatus = 'done'
    await fresh.save()

    if (oldKey && oldKey !== newKey) {
      await s3.send(new DeleteObjectCommand({ Bucket: BUCKET, Key: oldKey })).catch(() => {})
    }
  } catch (err) {
    console.error('[orbit] transcode failed for', fileId, '-', err.message)
    await markStatus(fileId, 'failed')
  } finally {
    progress.delete(String(fileId))
    fs.unlink(srcPath, () => {})
    if (outPath) fs.unlink(outPath, () => {})
  }
}

export async function resumePending() {
  try {
    await File.updateMany({ transcodeStatus: 'processing' }, { transcodeStatus: 'pending' })
    const pending = await File.find({ transcodeStatus: 'pending' }).select('_id')
    pending.forEach((f) => enqueue(f._id))
    if (pending.length) console.log(`[orbit] resumed ${pending.length} transcode job(s)`)
  } catch (err) {
    console.error('[orbit] resumePending failed:', err.message)
  }
}
