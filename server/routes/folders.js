import express from 'express'
import Folder from '../models/Folder.js'
import File from '../models/File.js'

const router = express.Router()

function fileUrl(objectKey) {
  const base = (process.env.MINIO_PUBLIC_URL || 'http://localhost').replace(/\/$/, '')
  const bucket = process.env.MINIO_BUCKET || 'orbit-uploads'
  return `${base}/${bucket}/${objectKey}`
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

// GET /api/orbit/folders/browse?parentId= — list folder contents
router.get('/browse', async (req, res) => {
  try {
    const { parentId } = req.query
    const folderId = parentId || null

    const [folders, rawFiles, breadcrumbs] = await Promise.all([
      Folder.find({ userId: 'default', parentId: folderId }).sort({ name: 1 }),
      File.find({ userId: 'default', folderId }).sort({ createdAt: -1 }),
      buildBreadcrumbs(parentId),
    ])

    const files = rawFiles.map(f => ({ ...f.toObject(), url: fileUrl(f.objectKey) }))
    res.json({ folders, files, breadcrumbs })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// POST /api/orbit/folders — create a folder
router.post('/', async (req, res) => {
  try {
    const { name, parentId } = req.body
    const folder = await Folder.create({ name, parentId: parentId || null, userId: 'default' })
    res.status(201).json(folder)
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// PATCH /api/orbit/folders/:id/rename
router.patch('/:id/rename', async (req, res) => {
  try {
    const folder = await Folder.findByIdAndUpdate(
      req.params.id,
      { name: req.body.name },
      { new: true }
    )
    if (!folder) return res.status(404).json({ error: 'Not found' })
    res.json(folder)
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// DELETE /api/orbit/folders/:id — deletes recursively
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
