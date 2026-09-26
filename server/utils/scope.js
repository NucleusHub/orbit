import Group from '../models/Group.js'
import Folder from '../models/Folder.js'

const sid = (v) => (v == null ? '' : String(v))

export async function myGroups(profileId) {
  return Group.find({ memberIds: sid(profileId) }).lean()
}

export function groupIdSet(groups) {
  return new Set(groups.map(g => sid(g._id)))
}

export function canView(doc, profileId, gset) {
  if (!doc) return false
  if (doc.groupId) return gset.has(sid(doc.groupId))
  return sid(doc.profileId) === sid(profileId)
}

export function canEdit(doc, profileId, gset) {
  if (!doc) return false
  if (doc.isGroupRoot) return false
  if (doc.groupId) return gset.has(sid(doc.groupId)) && sid(doc.ownerId) === sid(profileId)
  return sid(doc.profileId) === sid(profileId)
}

export function childScope(parent, profileId) {
  if (parent?.groupId) return { groupId: parent.groupId }
  return { profileId, groupId: null }
}

export function childOwnership(parent, profileId) {
  if (parent?.groupId) return { groupId: parent.groupId, ownerId: profileId, profileId }
  return { groupId: null, ownerId: profileId, profileId }
}

export async function ensureGroupRoot(group) {
  const name = `Group - ${group.name}`
  let root = await Folder.findOne({ groupId: group._id, isGroupRoot: true })
  if (!root) {
    root = await Folder.create({
      groupId: group._id, isGroupRoot: true, name,
      parentId: null, profileId: null, ownerId: null,
    })
  } else if (root.name !== name) {
    root.name = name
    await root.save()
  }
  return root
}
