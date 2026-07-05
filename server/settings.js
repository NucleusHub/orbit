// Per-user, DB-backed Orbit settings. Unlike Prism's global singleton, these
// are keyed by profileId and loaded lazily per request (no boot-time seed), so
// there's no in-memory cache — the docs are tiny and read infrequently.
import Settings from './models/Settings.js'

// Defaults returned when a user has no settings doc yet. Must match the schema
// defaults in models/Settings.js.
export const DEFAULTS = { transcodeVideos: true, convertImages: true }

const fromDoc = (doc) => ({ transcodeVideos: doc.transcodeVideos, convertImages: doc.convertImages })

// The caller's settings, falling back to defaults if they've never saved any.
export async function getUserSettings(profileId) {
  const doc = await Settings.findOne({ profileId })
  return doc ? fromDoc(doc) : { ...DEFAULTS }
}

// Upsert the caller's settings, applying only the fields present in `patch`.
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
