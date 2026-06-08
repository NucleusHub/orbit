import express from 'express'
import Folder from '../models/Folder.js'
import File from '../models/File.js'
import { hashPassword, verifyPassword } from '../utils/password.js'

const router = express.Router()

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

// POST /api/orbit/folders/:id/verify — verify password without side effects
router.post('/:id/verify', async (req, res) => {
  try {
    const folder = await Folder.findById(req.params.id)
    if (!folder) return res.status(404).json({ error: 'Not found' })
    if (!folder.passwordHash) return res.json({ ok: true })
    if (!verifyPassword(req.body.password, folder.passwordHash))
      return res.status(401).json({ error: 'Wrong password' })
    res.json({ ok: true })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// GET /api/orbit/folders/browse?parentId=
router.get('/browse', async (req, res) => {
  try {
    const { parentId } = req.query
    const folderId = parentId || null

    if (folderId) {
      const target = await Folder.findById(folderId)
      if (target?.passwordHash) {
        const pwd = req.headers['x-folder-password']
        if (!pwd || !verifyPassword(pwd, target.passwordHash)) {
          return res.status(401).json({ locked: true })
        }
      }
    }

    const [folders, rawFiles, breadcrumbs] = await Promise.all([
      Folder.find({ userId: 'default', parentId: folderId }).sort({ name: 1 }),
      File.find({ userId: 'default', folderId }).sort({ createdAt: -1 }),
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

// GET /api/orbit/folders/search?q= — global search across all folders and files
router.get('/search', async (req, res) => {
  try {
    const q = (req.query.q || '').trim()
    if (!q) return res.json({ folders: [], files: [] })
    const regex = new RegExp(q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i')
    const [folders, files] = await Promise.all([
      Folder.find({ userId: 'default', name: regex }),
      File.find({ userId: 'default', filename: regex }),
    ])
    res.json({ folders: folders.map(serializeFolder), files: files.map(serializeFile) })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// GET /api/orbit/folders/all — flat list of every folder (for folder picker)
router.get('/all', async (req, res) => {
  try {
    const folders = await Folder.find({ userId: 'default' }).sort({ name: 1 })
    res.json(folders.map(serializeFolder))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// POST /api/orbit/folders
router.post('/', async (req, res) => {
  try {
    const { name, parentId } = req.body
    const folder = await Folder.create({ name, parentId: parentId || null, userId: 'default' })
    res.status(201).json(serializeFolder(folder))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// PATCH /api/orbit/folders/:id/rename
router.patch('/:id/rename', async (req, res) => {
  try {
    const folder = await Folder.findByIdAndUpdate(req.params.id, { name: req.body.name }, { new: true })
    if (!folder) return res.status(404).json({ error: 'Not found' })
    res.json(serializeFolder(folder))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// PATCH /api/orbit/folders/:id/password — set or remove password
router.patch('/:id/password', async (req, res) => {
  try {
    const { password } = req.body
    const hash = password ? hashPassword(password) : null
    const folder = await Folder.findByIdAndUpdate(req.params.id, { passwordHash: hash }, { new: true })
    if (!folder) return res.status(404).json({ error: 'Not found' })
    res.json(serializeFolder(folder))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// PATCH /api/orbit/folders/:id/move
router.patch('/:id/move', async (req, res) => {
  try {
    const { parentId } = req.body
    const target = parentId || null
    if (target === req.params.id) return res.status(400).json({ error: 'Cannot move folder into itself' })
    if (target) {
      // Walk up from target to make sure we're not moving into a descendant
      let cur = await Folder.findById(target)
      while (cur) {
        if (String(cur._id) === req.params.id) return res.status(400).json({ error: 'Cannot move folder into its own descendant' })
        if (!cur.parentId) break
        cur = await Folder.findById(cur.parentId)
      }
    }
    const folder = await Folder.findByIdAndUpdate(req.params.id, { parentId: target }, { new: true })
    if (!folder) return res.status(404).json({ error: 'Not found' })
    res.json(serializeFolder(folder))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// DELETE /api/orbit/folders/:id
router.delete('/:id', async (req, res) => {
  try {
    await deleteFolderRecursive(req.params.id)
    res.json({ ok: true })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

async function deleteFolderRecursive(folderId) {
  const subfolders = await Folder.find({ parentId: folderId })
  await Promise.all(subfolders.map(sf => deleteFolderRecursive(sf._id.toString())))
  await File.deleteMany({ folderId })
  await Folder.findByIdAndDelete(folderId)
}

export default router
