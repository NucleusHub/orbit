import express from 'express'
import Folder from '../models/Folder.js'
import File from '../models/File.js'
import { hashPassword, verifyPassword } from '../utils/password.js'
import { requireAuth } from '../middleware/auth.js'

const router = express.Router()
router.use(requireAuth)

function fileUrl(objectKey) {
  const bucket = process.env.MINIO_BUCKET || 'orbit-uploads'
  return `/${bucket}/${objectKey}`
}

function serializeFolder(f) {
  const obj = f.toObject ? f.toObject() : { ...f }
  const { passwordHash, ...rest } = obj
  return { ...rest, protected: !!passwordHash }
}

function serializeFile(f) {
  const obj = f.toObject ? f.toObject() : { ...f }
  const { passwordHash, ...rest } = obj
  if (passwordHash) return { ...rest, protected: true }
  return { ...rest, url: fileUrl(obj.objectKey) }
}

async function buildBreadcrumbs(folderId) {
  if (!folderId) return []
  const crumbs = []
  let current = await Folder.findById(folderId)
  while (current) {
    crumbs.unshift({ _id: current._id, name: current.name })
    if (!current.parentId) break
    current = await Folder.findById(current.parentId)
  }
  return crumbs
}

router.post('/:id/verify', async (req, res) => {
  try {
    const folder = await Folder.findOne({ _id: req.params.id, profileId: req.profile.profileId })
    if (!folder) return res.status(404).json({ error: 'Not found' })
    if (!folder.passwordHash) return res.json({ ok: true })
    if (!verifyPassword(req.body.password, folder.passwordHash))
      return res.status(401).json({ error: 'Wrong password' })
    res.json({ ok: true })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.get('/browse', async (req, res) => {
  try {
    const { parentId } = req.query
    const folderId = parentId || null
    const pid = req.profile.profileId

    if (folderId) {
      const target = await Folder.findOne({ _id: folderId, profileId: pid })
      if (target?.passwordHash) {
        const pwd = req.headers['x-folder-password']
        if (!pwd || !verifyPassword(pwd, target.passwordHash)) {
          return res.status(401).json({ locked: true })
        }
      }
    }

    const [folders, rawFiles, breadcrumbs] = await Promise.all([
      Folder.find({ profileId: pid, parentId: folderId }).sort({ name: 1 }),
      File.find({ profileId: pid, folderId }).sort({ createdAt: -1 }),
      buildBreadcrumbs(parentId),
    ])

    res.json({
      folders: folders.map(serializeFolder),
      files: rawFiles.map(serializeFile),
      breadcrumbs,
    })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.get('/search', async (req, res) => {
  try {
    const q = (req.query.q || '').trim()
    if (!q) return res.json({ folders: [], files: [] })
    const regex = new RegExp(q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i')
    const pid = req.profile.profileId
    const [folders, files] = await Promise.all([
      Folder.find({ profileId: pid, name: regex }),
      File.find({ profileId: pid, filename: regex }),
    ])
    res.json({ folders: folders.map(serializeFolder), files: files.map(serializeFile) })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.get('/all', async (req, res) => {
  try {
    const folders = await Folder.find({ profileId: req.profile.profileId }).sort({ name: 1 })
    res.json(folders.map(serializeFolder))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.post('/', async (req, res) => {
  try {
    const { name, parentId } = req.body
    const folder = await Folder.create({
      profileId: req.profile.profileId,
      name,
      parentId: parentId || null,
    })
    res.status(201).json(serializeFolder(folder))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.patch('/:id/rename', async (req, res) => {
  try {
    const folder = await Folder.findOneAndUpdate(
      { _id: req.params.id, profileId: req.profile.profileId },
      { name: req.body.name },
      { new: true }
    )
    if (!folder) return res.status(404).json({ error: 'Not found' })
    res.json(serializeFolder(folder))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.patch('/:id/password', async (req, res) => {
  try {
    const { password } = req.body
    const hash = password ? hashPassword(password) : null
    const folder = await Folder.findOneAndUpdate(
      { _id: req.params.id, profileId: req.profile.profileId },
      { passwordHash: hash },
      { new: true }
    )
    if (!folder) return res.status(404).json({ error: 'Not found' })
    res.json(serializeFolder(folder))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.patch('/:id/move', async (req, res) => {
  try {
    const { parentId } = req.body
    const target = parentId || null
    if (target === req.params.id) return res.status(400).json({ error: 'Cannot move folder into itself' })
    if (target) {
      let cur = await Folder.findById(target)
      while (cur) {
        if (String(cur._id) === req.params.id) return res.status(400).json({ error: 'Cannot move folder into its own descendant' })
        if (!cur.parentId) break
        cur = await Folder.findById(cur.parentId)
      }
    }
    const folder = await Folder.findOneAndUpdate(
      { _id: req.params.id, profileId: req.profile.profileId },
      { parentId: target },
      { new: true }
    )
    if (!folder) return res.status(404).json({ error: 'Not found' })
    res.json(serializeFolder(folder))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.delete('/:id', async (req, res) => {
  try {
    await deleteFolderRecursive(req.params.id, req.profile.profileId)
    res.json({ ok: true })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

async function deleteFolderRecursive(folderId, profileId) {
  const subfolders = await Folder.find({ parentId: folderId, profileId })
  await Promise.all(subfolders.map(sf => deleteFolderRecursive(sf._id.toString(), profileId)))
  await File.deleteMany({ folderId, profileId })
  await Folder.findOneAndDelete({ _id: folderId, profileId })
}

export default router
