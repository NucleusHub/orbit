import mongoose from 'mongoose'

const settingsSchema = new mongoose.Schema(
  {
    profileId: { type: String, required: true, unique: true, index: true },

    transcodeVideos: { type: Boolean, default: true },

    convertImages: { type: Boolean, default: true },

    // iOS app only: item id -> { strict }. The web ignores it; strict means no passcode/password fallback.
    faceIdLocks: { type: Map, of: new mongoose.Schema({ strict: { type: Boolean, default: false } }, { _id: false }), default: () => new Map() },
  },
  { timestamps: true }
)

export default mongoose.model('OrbitSettings', settingsSchema)
