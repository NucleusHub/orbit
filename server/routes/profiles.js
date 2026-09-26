import express from 'express'
import { DeleteObjectCommand } from '@aws-sdk/client-s3'
import File from '../models/File.js'
import Folder from '../models/Folder.js'
import { requireAuth } from '../middleware/auth.js'
import { s3, BUCKET } from './files.js'

const router = express.Router()
router.use(requireAuth)

function requireAdmin(req, res, next) {
  if (req.profile?.role !== 'admin') return res.status(403).json({ error: 'Admin required' })
  next()
}

router.post('/:profileId/teardown', requireAdmin, async (req, res) => {
  try {
    const { profileId } = req.params

    const scope = { profileId, groupId: null }
    const files = await File.find(scope).select('objectKey')

    await Promise.all(files.map(f =>
      f.objectKey
        ? s3.send(new DeleteObjectCommand({ Bucket: BUCKET, Key: f.objectKey })).catch(() => {})
        : Promise.resolve(),
    ))
    await Promise.all([
      File.deleteMany(scope),
      Folder.deleteMany(scope),
    ])

    res.json({ ok: true, deleted: { files: files.length } })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

export default router
