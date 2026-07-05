import mongoose from 'mongoose'

// Per-user Orbit configuration. One document per profile (keyed by profileId),
// created lazily on first read/write. Holds the preferences a user can change
// from the in-app Settings modal — currently just video transcoding.
const settingsSchema = new mongoose.Schema(
  {
    profileId: { type: String, required: true, unique: true, index: true },

    // Re-encode incompatible videos to a browser-friendly H.264/AAC MP4 on
    // upload, so files play everywhere — notably mobile browsers, which decode
    // in hardware and reject HEVC/High-profile files that desktops play fine.
    // Files that are already broadly playable are stored untouched.
    transcodeVideos: { type: Boolean, default: true },

    // Convert images browsers can't display inline (HEIC/HEIF from iPhones,
    // TIFF) to JPEG on upload. Already-displayable images are stored untouched.
    convertImages: { type: Boolean, default: true },
  },
  { timestamps: true }
)

export default mongoose.model('OrbitSettings', settingsSchema)
