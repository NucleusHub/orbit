import { Router } from 'express'
import { GetObjectCommand } from '@aws-sdk/client-s3'
import { timingSafeEqual } from 'node:crypto'
import File from '../models/File.js'
import Folder from '../models/Folder.js'
import { s3, BUCKET } from './files.js'
import { verifyProfile } from '../middleware/auth.js'
import { myGroups } from '../utils/scope.js'

const router = Router()

const PRISM_KEY = process.env.JWT_SECRET || 'nucleus-jwt-secret'

const MEDIA_EXT = /\.(jpe?g|png|webp|gif|heic|heif|avif|mp4|mov|mkv|webm|avi|m4v)$/i

function requirePrismKey(req, res, next) {
  const got = Buffer.from(req.get('X-Prism-Key') || '')
  const want = Buffer.from(PRISM_KEY)
  if (got.length === want.length && timingSafeEqual(got, want)) return next()
  res.status(401).json({ error: 'Invalid or missing X-Prism-Key' })
}
router.use(requirePrismKey)

// The shared secret only identifies Prism; results are scoped to the forwarded user token.
router.get('/media', async (req, res, next) => {
  try {
    const profile = verifyProfile(req)
    if (!profile) return res.status(401).json({ error: 'A user token is required' })
    const pid = profile.profileId

    const groups = await myGroups(pid)
    const sharedGroupIds = groups.filter((g) => g.sharedOrbit).map((g) => String(g._id))

    const filter = {
      filename: MEDIA_EXT,
      $or: [
        { profileId: pid, groupId: null },
        { groupId: { $in: sharedGroupIds } },
      ],
    }

    const files = await File.find(filter)
      .select('_id objectKey filename mimeType size folderId groupId ownerId profileId passwordHash updatedAt')
      .lean()

    const folderDocs = await Folder.find({
      $or: [
        { profileId: pid, groupId: null },
        { groupId: { $in: sharedGroupIds } },
      ],
    }).select('_id parentId passwordHash name isGroupRoot').lean()
    const folders = new Map(
      folderDocs.map((f) => [String(f._id), {
        parentId: f.parentId ? String(f.parentId) : null,
        locked: f.passwordHash != null,
        name: f.name,
        isGroupRoot: !!f.isGroupRoot,
      }])
    )
    const chainLocked = (folderId) => {
      let id = folderId ? String(folderId) : null
      for (let guard = 0; id && guard < 100; guard++) {
        const f = folders.get(id)
        if (!f) break
        if (f.locked) return true
        id = f.parentId
      }
      return false
    }
    const shareFolder = (folderId) => {
      let id = folderId ? String(folderId) : null
      let top = null
      for (let guard = 0; id && guard < 100; guard++) {
        const f = folders.get(id)
        if (!f || f.isGroupRoot) break
        top = { id, name: f.name }
        id = f.parentId
      }
      return top
    }

    res.json(
      files.map((f) => {
        const share = f.groupId ? shareFolder(f.folderId) : null
        return {
          id: String(f._id),
          path: f.objectKey,
          filename: f.filename,
          mimeType: f.mimeType,
          size: f.size,
          mtimeMs: f.updatedAt ? new Date(f.updatedAt).getTime() : 0,
          folderId: f.folderId ? String(f.folderId) : null,
          groupId: f.groupId ? String(f.groupId) : null,
          ownerId: String(f.ownerId || f.profileId || ''),
          protected: !!f.passwordHash || chainLocked(f.folderId),
          shareId: share?.id || null,
          shareName: share?.name || null,
        }
      })
    )
  } catch (err) {
    next(err)
  }
})

async function isLocked(file) {
  if (file.passwordHash) return true
  let id = file.folderId ? String(file.folderId) : null
  for (let guard = 0; id && guard < 100; guard++) {
    const f = await Folder.findById(id).select('parentId passwordHash').lean()
    if (!f) break
    if (f.passwordHash) return true
    id = f.parentId ? String(f.parentId) : null
  }
  return false
}

router.get('/stream', async (req, res) => {
  const key = String(req.query.path || '')
  if (!key) return res.status(400).json({ error: 'path required' })

  const file = await File.findOne({ objectKey: key }).select('mimeType passwordHash folderId').lean()
  if (!file) return res.status(404).end()
  if (await isLocked(file)) return res.status(403).end()

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

    const body = out.Body
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
