// Stable, service-to-service "public" API that sibling Nucleus apps consume to
// read Orbit's media WITHOUT importing Orbit's code or touching its database.
// Prism's OrbitSource (apps/prism/server/sources/OrbitSource.js) is the first
// (and today only) consumer: it lists media here and streams bytes here to build
// its own photo index.
//
// Auth is a shared-secret header, NOT the per-user `nucleus_token` cookie: these
// calls originate from another *service* (prism-server), not a browser session.
// The secret is the platform-wide JWT_SECRET both containers already share, sent
// as `X-Prism-Key`. Because it's service-scoped, this router is mounted BEFORE
// the per-user requireAppEnabled gate in index.js.
//
// Contract (must stay stable — Prism is coded against it):
//   GET /api/orbit/public/media?shared=0|1
//     -> [{ id, path, filename, mimeType, size, mtimeMs, folderId }]
//     shared=1 restricts to files in shared-group storage; shared=0 = everything.
//     `path` is the S3 object key — feed it back to /stream.
//   GET /api/orbit/public/stream?path=<objectKey>   (Range-capable)
//     -> the raw object bytes.
import { Router } from 'express'
import { GetObjectCommand } from '@aws-sdk/client-s3'
import { timingSafeEqual } from 'node:crypto'
import File from '../models/File.js'
import { s3, BUCKET } from './files.js'

const router = Router()

const PRISM_KEY = process.env.JWT_SECRET || 'nucleus-jwt-secret'

// Media Prism understands — mirrors apps/prism/server/utils/formats.js. Kept as a
// filename-extension test (reliable) rather than trusting the stored mimeType,
// which can be a generic application/octet-stream for some uploads.
const MEDIA_EXT = /\.(jpe?g|png|webp|gif|heic|heif|avif|mp4|mov|mkv|webm|avi|m4v)$/i

// Shared-secret gate. Constant-time compare so the endpoint can't be probed for
// the key by timing; any request without the exact key is a flat 401.
function requirePrismKey(req, res, next) {
  const got = Buffer.from(req.get('X-Prism-Key') || '')
  const want = Buffer.from(PRISM_KEY)
  if (got.length === want.length && timingSafeEqual(got, want)) return next()
  res.status(401).json({ error: 'Invalid or missing X-Prism-Key' })
}
router.use(requirePrismKey)

// ── List media ───────────────────────────────────────────────────────────────
// Note: password-protected files are never listed — even though MinIO objects are
// public-read, exposing them through Prism would leak content the owner gated.
router.get('/media', async (req, res, next) => {
  try {
    const filter = { filename: MEDIA_EXT, passwordHash: null }
    if (req.query.shared === '1') filter.groupId = { $ne: null }

    const files = await File.find(filter)
      .select('_id objectKey filename mimeType size folderId updatedAt')
      .lean()

    res.json(
      files.map((f) => ({
        id: String(f._id),
        path: f.objectKey,
        filename: f.filename,
        mimeType: f.mimeType,
        size: f.size,
        mtimeMs: f.updatedAt ? new Date(f.updatedAt).getTime() : 0,
        folderId: f.folderId ? String(f.folderId) : null,
      }))
    )
  } catch (err) {
    next(err)
  }
})

// ── Stream one object (Range-capable) ────────────────────────────────────────
router.get('/stream', async (req, res) => {
  const key = String(req.query.path || '')
  if (!key) return res.status(400).json({ error: 'path required' })

  // Only stream keys that map to a real, non-protected Orbit file — this scopes
  // access to known objects and gives us the authoritative Content-Type.
  const file = await File.findOne({ objectKey: key }).select('mimeType passwordHash').lean()
  if (!file) return res.status(404).end()
  if (file.passwordHash) return res.status(403).end()

  const range = req.headers.range
  try {
    const out = await s3.send(
      new GetObjectCommand({ Bucket: BUCKET, Key: key, ...(range ? { Range: range } : {}) })
    )

    res.set('Accept-Ranges', 'bytes')
    res.type(file.mimeType || out.ContentType || 'application/octet-stream')
    if (out.ContentLength != null) res.set('Content-Length', String(out.ContentLength))
    if (out.ContentRange) {
      res.status(206)
      res.set('Content-Range', out.ContentRange)
    }

    const body = out.Body // Node Readable in a Node runtime
    body.on('error', () => (res.headersSent ? res.destroy() : res.status(502).end()))
    res.on('close', () => body.destroy?.())
    body.pipe(res)
  } catch (err) {
    const code = err?.$metadata?.httpStatusCode
    if (code === 416) return res.status(416).set('Content-Range', 'bytes */*').end()
    if (code === 404 || err?.name === 'NoSuchKey') return res.status(404).end()
    console.error('[orbit] public stream error:', err.message)
    if (!res.headersSent) res.status(502).end()
  }
})

export default router
