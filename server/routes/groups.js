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

// Called by the admin panel when a group is deleted, to decide what happens to
// its shared "Group - {name}" directory. No-op (404-safe) if the group never
// had shared files.
//   POST /api/orbit/groups/:groupId/teardown
//   body: { action: 'delete' } | { action: 'transfer', targetProfileId }
router.post('/:groupId/teardown', requireAdmin, async (req, res) => {
  try {
    const { groupId } = req.params
    const { action, targetProfileId } = req.body

    const [files, folders] = await Promise.all([
      File.find({ groupId }),
      Folder.find({ groupId }),
    ])
    if (!files.length && !folders.length) return res.json({ ok: true, empty: true })

    if (action === 'transfer') {
      if (!targetProfileId) return res.status(400).json({ error: 'targetProfileId required' })
      const root = folders.find(f => f.isGroupRoot)

      // Lift the shared root's direct children to the target's personal root…
      if (root) {
        await Promise.all([
          Folder.updateMany({ groupId, parentId: root._id }, { $set: { parentId: null } }),
          File.updateMany({ groupId, folderId: root._id }, { $set: { folderId: null } }),
        ])
      }
      // …then reassign every (non-root) item to the target as personal storage.
      await Promise.all([
        Folder.updateMany(
          { groupId, isGroupRoot: { $ne: true } },
          { $set: { profileId: targetProfileId, ownerId: targetProfileId, groupId: null } },
        ),
        File.updateMany(
          { groupId },
          { $set: { profileId: targetProfileId, ownerId: targetProfileId, groupId: null } },
        ),
      ])
      if (root) await Folder.findByIdAndDelete(root._id)
      return res.json({ ok: true, transferred: files.length })
    }

    // Default: permanently delete the shared directory and its objects.
    await Promise.all(files.map(f =>
      s3.send(new DeleteObjectCommand({ Bucket: BUCKET, Key: f.objectKey })).catch(() => {}),
    ))
    await Promise.all([
      File.deleteMany({ groupId }),
      Folder.deleteMany({ groupId }),
    ])
    res.json({ ok: true, deleted: { files: files.length, folders: folders.length } })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

export default router
