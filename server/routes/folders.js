import express from 'express'
import { DeleteObjectsCommand } from '@aws-sdk/client-s3'
import Folder from '../models/Folder.js'
import File from '../models/File.js'
import { s3, BUCKET, signFileToken, rawUrl } from './files.js'
import { getProgress } from '../transcodeQueue.js'
import { hashPassword, verifyPassword } from '../utils/password.js'
import { requireAuth } from '../middleware/auth.js'
import {
  myGroups, groupIdSet, canView, canEdit,
  childScope, childOwnership, ensureGroupRoot,
} from '../utils/scope.js'

const router = express.Router()
router.use(requireAuth)

// Propagate a scope change (groupId / ownerId / profileId) to every descendant
// of a moved folder, keeping the whole subtree consistent with its new home.
async function rescopeTree(folderId, own) {
  await File.updateMany({ folderId }, { $set: own })
  const subfolders = await Folder.find({ parentId: folderId }).select('_id')
  if (subfolders.length) {
    await Folder.updateMany({ parentId: folderId }, { $set: own })
    for (const sf of subfolders) await rescopeTree(sf._id, own)
  }
}

// Load the caller's group membership once per request (req.groups / req.gset).
router.use(async (req, _res, next) => {
  try {
    req.groups = await myGroups(req.profile.profileId)
    req.gset = groupIdSet(req.groups)
    next()
  } catch (err) {
    next(err)
  }
})

function serializeFolder(f, req) {
  const obj = f.toObject ? f.toObject() : { ...f }
  const { passwordHash, ...rest } = obj
  return {
    ...rest,
    protected: !!passwordHash,
    shared: !!obj.groupId,
    locked: !!obj.isGroupRoot,                 // immutable shared root
    canEdit: canEdit(obj, req.profile.profileId, req.gset),
  }
}

// `folderUnlocked` = the containing folder's password was satisfied for this
// request, so folder-locked files get a streaming token.
function serializeFile(f, req, folderUnlocked = false) {
  const obj = f.toObject ? f.toObject() : { ...f }
  const { passwordHash, ...rest } = obj
  const prog = getProgress(obj._id)
  const base = {
    ...rest,
    shared: !!obj.groupId,
    canEdit: canEdit(obj, req.profile.profileId, req.gset),
    transcodeStatus: obj.transcodeStatus || 'none',
    ...(prog ? { transcodeProgress: prog.percent, transcodeEta: prog.eta } : {}),
  }
  if (passwordHash) return { ...base, protected: true } // own password → separate unlock
  if (folderUnlocked) return { ...base, url: rawUrl(obj._id, signFileToken(obj._id)) }
  return { ...base, url: rawUrl(obj._id) }
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

// Mongo filter matching everything the user is allowed to see (personal + groups).
function visibleFilter(req) {
  const ids = req.groups.map(g => g._id)
  return { $or: [{ profileId: req.profile.profileId, groupId: null }, { groupId: { $in: ids } }] }
}

router.post('/:id/verify', async (req, res) => {
  try {
    const folder = await Folder.findById(req.params.id)
    if (!canView(folder, req.profile.profileId, req.gset)) return res.status(404).json({ error: 'Not found' })
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
    const pid = req.profile.profileId
    const { parentId } = req.query
    const folderId = parentId || null

    let parent = null
    if (folderId) {
      parent = await Folder.findById(folderId)
      if (!canView(parent, pid, req.gset)) return res.status(404).json({ error: 'Not found' })
      if (parent.passwordHash) {
        const pwd = req.headers['x-folder-password']
        if (!pwd || !verifyPassword(pwd, parent.passwordHash)) {
          return res.status(401).json({ locked: true })
        }
      }
    }

    // Children scope: a group folder shows every member's items; the personal
    // root shows only the caller's personal items.
    const scope = parent ? childScope(parent, pid) : { profileId: pid, groupId: null }
    const [folders, rawFiles, breadcrumbs] = await Promise.all([
      Folder.find({ parentId: folderId, ...scope }).sort({ name: 1 }),
      File.find({ folderId, ...scope }).sort({ createdAt: -1 }),
      buildBreadcrumbs(parentId),
    ])

    let folderList = folders
    if (!parent) {
      // Top level: surface an immutable "Group - {name}" folder per shared group.
      const roots = await Promise.all(req.groups.filter(g => g.sharedOrbit).map(ensureGroupRoot))
      folderList = [...roots, ...folders]
    }

    res.json({
      folders: folderList.map(f => serializeFolder(f, req)),
      // The folder's password (if any) was verified above, so its files may stream.
      files: rawFiles.map(f => serializeFile(f, req, !!parent?.passwordHash)),
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
    const vis = visibleFilter(req)
    const [folders, files] = await Promise.all([
      Folder.find({ ...vis, name: regex }),
      File.find({ ...vis, filename: regex }),
    ])
    res.json({ folders: folders.map(f => serializeFolder(f, req)), files: files.map(f => serializeFile(f, req)) })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.get('/all', async (req, res) => {
  try {
    const folders = await Folder.find(visibleFilter(req)).sort({ name: 1 })
    res.json(folders.map(f => serializeFolder(f, req)))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.post('/', async (req, res) => {
  try {
    const pid = req.profile.profileId
    const { name, parentId } = req.body
    let parent = null
    if (parentId) {
      parent = await Folder.findById(parentId)
      // Any member can add inside a group folder; canView covers membership.
      if (!canView(parent, pid, req.gset)) return res.status(404).json({ error: 'Not found' })
    }
    const folder = await Folder.create({
      name,
      parentId: parentId || null,
      ...childOwnership(parent, pid),
    })
    res.status(201).json(serializeFolder(folder, req))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// Resolve a folder and enforce view/edit permission. Returns the doc, or null
// after sending the appropriate error response.
async function loadEditable(req, res) {
  const pid = req.profile.profileId
  const folder = await Folder.findById(req.params.id)
  if (!canView(folder, pid, req.gset)) { res.status(404).json({ error: 'Not found' }); return null }
  if (!canEdit(folder, pid, req.gset)) {
    res.status(403).json({ error: folder.isGroupRoot ? 'Shared folder is locked' : 'Only the owner can change this' })
    return null
  }
  return folder
}

router.patch('/:id/rename', async (req, res) => {
  try {
    const folder = await loadEditable(req, res)
    if (!folder) return
    folder.name = req.body.name
    await folder.save()
    res.json(serializeFolder(folder, req))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.patch('/:id/password', async (req, res) => {
  try {
    const folder = await loadEditable(req, res)
    if (!folder) return
    folder.passwordHash = req.body.password ? hashPassword(req.body.password) : null
    await folder.save()
    res.json(serializeFolder(folder, req))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.patch('/:id/move', async (req, res) => {
  try {
    const pid = req.profile.profileId
    const folder = await loadEditable(req, res)
    if (!folder) return

    const target = req.body.parentId || null
    if (target === req.params.id) return res.status(400).json({ error: 'Cannot move folder into itself' })

    let targetFolder = null
    if (target) {
      targetFolder = await Folder.findById(target)
      if (!canView(targetFolder, pid, req.gset)) return res.status(404).json({ error: 'Not found' })
      let cur = targetFolder
      while (cur) {
        if (String(cur._id) === req.params.id) return res.status(400).json({ error: 'Cannot move folder into its own descendant' })
        if (!cur.parentId) break
        cur = await Folder.findById(cur.parentId)
      }
    }

    // Adopt the destination's storage scope, so the folder can cross between
    // personal storage and a group's shared directory (and vice-versa).
    const oldGroup = folder.groupId ? String(folder.groupId) : null
    const own = childOwnership(targetFolder, pid)
    const newGroup = own.groupId ? String(own.groupId) : null

    folder.parentId = target
    folder.groupId = own.groupId
    folder.ownerId = own.ownerId
    folder.profileId = own.profileId
    await folder.save()

    // When the group scope changes the whole subtree must follow it, otherwise
    // its contents would no longer match the destination's listing query.
    if (oldGroup !== newGroup) await rescopeTree(folder._id, own)

    res.json(serializeFolder(folder, req))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.delete('/:id', async (req, res) => {
  try {
    const folder = await loadEditable(req, res)
    if (!folder) return
    await deleteFolderRecursive(folder)
    res.json({ ok: true })
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// Best-effort removal of stored objects in batches of up to 1000 (the S3
// DeleteObjects limit). Failures are logged but don't abort the delete — a
// stranded object is a storage leak, not data loss, and shouldn't leave the
// folder tree half-removed.
async function deleteObjects(keys) {
  for (let i = 0; i < keys.length; i += 1000) {
    const chunk = keys.slice(i, i + 1000)
    try {
      await s3.send(new DeleteObjectsCommand({
        Bucket: BUCKET,
        Delete: { Objects: chunk.map(Key => ({ Key })), Quiet: true },
      }))
    } catch (err) {
      console.error(`Folder delete: failed to remove ${chunk.length} objects: ${err.message}`)
    }
  }
}

// Removes a folder and everything beneath it. For group folders the subtree is
// scoped by groupId (so it clears every member's items inside); for personal
// folders by profileId. Stored objects are removed alongside the DB records so
// MinIO doesn't accumulate orphans.
async function deleteFolderRecursive(folder) {
  const scope = folder.groupId ? { groupId: folder.groupId } : { profileId: folder.profileId }
  const subfolders = await Folder.find({ parentId: folder._id, ...scope })
  await Promise.all(subfolders.map(deleteFolderRecursive))

  const files = await File.find({ folderId: folder._id, ...scope }).select('objectKey')
  const keys = files.map(f => f.objectKey).filter(Boolean)
  if (keys.length) await deleteObjects(keys)

  await File.deleteMany({ folderId: folder._id, ...scope })
  await Folder.findByIdAndDelete(folder._id)
}

export default router
