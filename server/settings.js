import Settings from './models/Settings.js'

export const DEFAULTS = { transcodeVideos: true, convertImages: true }

const fromDoc = (doc) => ({ transcodeVideos: doc.transcodeVideos, convertImages: doc.convertImages })

export async function getUserSettings(profileId) {
  const doc = await Settings.findOne({ profileId })
  return doc ? fromDoc(doc) : { ...DEFAULTS }
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
