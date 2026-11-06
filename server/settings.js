import Settings from './models/Settings.js'

export const DEFAULTS = { transcodeVideos: true, convertImages: true, faceIdLocks: {} }

const ITEM_ID = /^[a-f0-9]{24}$/

const locksFrom = (locks) => {
  const out = {}
  const entries = locks instanceof Map ? locks.entries() : Object.entries(locks || {})
  for (const [id, lock] of entries) out[id] = { strict: !!lock?.strict }
  return out
}

export const fromDoc = (doc) => ({
  transcodeVideos: doc.transcodeVideos,
  convertImages: doc.convertImages,
  faceIdLocks: locksFrom(doc.faceIdLocks),
})

// One lock per call, so two devices changing different locks never overwrite each other.
export function faceIdLockUpdate(itemId, lock) {
  if (typeof itemId !== 'string' || !ITEM_ID.test(itemId)) throw new Error('Invalid item id')
  const path = `faceIdLocks.${itemId}`
  return lock ? { $set: { [path]: { strict: !!lock.strict } } } : { $unset: { [path]: '' } }
}

export async function saveFaceIdLock(profileId, itemId, lock) {
  const doc = await Settings.findOneAndUpdate(
    { profileId },
    { ...faceIdLockUpdate(itemId, lock), $setOnInsert: { profileId } },
    { new: true, upsert: true, setDefaultsOnInsert: true },
  )
  return fromDoc(doc)
}

export async function getUserSettings(profileId) {
  const doc = await Settings.findOne({ profileId })
  return doc ? fromDoc(doc) : { ...DEFAULTS, faceIdLocks: {} }
}

export async function saveUserSettings(profileId, patch = {}) {
  const update = {}
  if (patch.transcodeVideos !== undefined) update.transcodeVideos = !!patch.transcodeVideos
  if (patch.convertImages !== undefined) update.convertImages = !!patch.convertImages

  const doc = await Settings.findOneAndUpdate(
    { profileId },
    { $set: update, $setOnInsert: { profileId } },
    { new: true, upsert: true, setDefaultsOnInsert: true },
  )
  return fromDoc(doc)
}
