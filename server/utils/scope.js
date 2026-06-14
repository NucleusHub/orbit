import Group from '../models/Group.js'
import Folder from '../models/Folder.js'

// Helpers for the personal-vs-shared-group access model.
//
// An item (folder/file) is either PERSONAL (groupId null, owned by profileId)
// or GROUP (groupId set, visible to every member, editable only by its ownerId).
// The top-level "Group - {name}" folder is immutable (isGroupRoot).

const sid = (v) => (v == null ? '' : String(v))

// Groups the user belongs to (lean docs). One query per request.
export async function myGroups(profileId) {
  return Group.find({ memberIds: sid(profileId) }).lean()
}

export function groupIdSet(groups) {
  return new Set(groups.map(g => sid(g._id)))
}

// Can the user see this folder/file?
export function canView(doc, profileId, gset) {
  if (!doc) return false
  if (doc.groupId) return gset.has(sid(doc.groupId))
  return sid(doc.profileId) === sid(profileId)
}

// Can the user rename/move/delete/password this folder/file?
// Group roots are immutable; other group items are owner-only; personal items
// belong to their profile.
export function canEdit(doc, profileId, gset) {
  if (!doc) return false
  if (doc.isGroupRoot) return false
  if (doc.groupId) return gset.has(sid(doc.groupId)) && sid(doc.ownerId) === sid(profileId)
  return sid(doc.profileId) === sid(profileId)
}

// Mongo filter selecting the children that live directly under `parent`.
// For group folders we scope by groupId (all members' items); for personal
// folders (or the root) by profileId. `null`/missing groupId both match for
// legacy personal items.
export function childScope(parent, profileId) {
  if (parent?.groupId) return { groupId: parent.groupId }
  return { profileId, groupId: null }
}

// Fields stamped onto a new child created under `parent`.
export function childOwnership(parent, profileId) {
  if (parent?.groupId) return { groupId: parent.groupId, ownerId: profileId, profileId }
  return { groupId: null, ownerId: profileId, profileId }
}

// Find (or lazily create / rename) the immutable root folder for a shared group.
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
