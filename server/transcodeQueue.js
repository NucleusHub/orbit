// In-process background queue for media normalisation (video AND images).
// Orbit has no external job runner, so the File document itself is the durable
// job record: a file with transcodeStatus 'pending'/'processing' is work to be
// done. The in-memory queue below just schedules that work; resumePending()
// re-arms it on boot so a restart mid-encode doesn't strand a file.
//
// A job: download the object from MinIO → decide (planVideo/planImage) →
// produce a browser-friendly output (H.264/AAC MP4 for video, JPEG for HEIC/
// HEIF/TIFF images) → upload the new object, repoint the File doc, delete the
// old object. On failure the original is left untouched.
import fs from 'node:fs'
import path from 'node:path'
import { randomUUID } from 'node:crypto'
import { pipeline } from 'node:stream/promises'
import { GetObjectCommand, PutObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3'
import File from './models/File.js'
import { s3, BUCKET, md5Base64 } from './routes/files.js'
import { planVideo, transcodeToMp4, remuxToMp4 } from './utils/transcode.js'
import { planImage, convertToJpeg } from './utils/image.js'

// Transcoding is CPU-heavy; default to one job at a time so it doesn't starve
// the request handlers on a shared host. Tunable via env.
const MAX_CONCURRENT = Number(process.env.ORBIT_TRANSCODE_CONCURRENCY) || 1
const WORK_DIR = '/tmp/orbit-transcode'

const queued = []          // fileIds waiting for a slot
const inFlight = new Set() // fileIds currently downloading/encoding
let active = 0

// Schedule a file for (re)processing. Idempotent — a file already queued or in
// flight is ignored.
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
  // Only act on files still awaiting work (guards against double-enqueue and
  // against a file that was deleted/replaced between enqueue and run).
  if (file.transcodeStatus !== 'pending' && file.transcodeStatus !== 'processing') return

  await markStatus(fileId, 'processing')

  fs.mkdirSync(WORK_DIR, { recursive: true })
  const srcPath = path.join(WORK_DIR, `${randomUUID()}${path.extname(file.filename) || ''}`)
  let outPath = null
  try {
    // Pull the current object down to disk.
    const obj = await s3.send(new GetObjectCommand({ Bucket: BUCKET, Key: file.objectKey }))
    await pipeline(obj.Body, fs.createWriteStream(srcPath))

    const isVideo = file.mimeType?.startsWith('video/')
    const isImage = file.mimeType?.startsWith('image/')

    // Decide + produce the normalised output. `outExt`/`outMime` describe it.
    let outExt, outMime
    if (isVideo) {
      const plan = await planVideo(srcPath, file.filename)
      if (plan === 'skip') { await markStatus(fileId, 'done'); return } // already playable
      outExt = '.mp4'; outMime = 'video/mp4'
      outPath = `${srcPath}.mp4`
      if (plan === 'remux') await remuxToMp4(srcPath, outPath)
      else await transcodeToMp4(srcPath, outPath)
    } else if (isImage) {
      const plan = planImage(file.filename, file.mimeType)
      if (plan === 'skip') { await markStatus(fileId, 'done'); return } // already displayable
      outExt = '.jpg'; outMime = 'image/jpeg'
      outPath = `${srcPath}.jpg`
      await convertToJpeg(srcPath, outPath)
    } else {
      await markStatus(fileId, 'done') // not a media type we handle
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

    // Repoint the doc atomically-ish: re-load to avoid clobbering a concurrent
    // rename/move, then swap in the new object.
    const fresh = await File.findById(fileId)
    if (!fresh) {
      // File was deleted while we encoded — drop the object we just made.
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
    fs.unlink(srcPath, () => {})
    if (outPath) fs.unlink(outPath, () => {})
  }
}

// Re-arm jobs left behind by a restart: anything still 'pending', plus
// 'processing' files whose worker died (reset them to pending first).
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
