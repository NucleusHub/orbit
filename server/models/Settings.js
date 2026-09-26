import mongoose from 'mongoose'

const settingsSchema = new mongoose.Schema(
  {
    profileId: { type: String, required: true, unique: true, index: true },

    transcodeVideos: { type: Boolean, default: true },

    convertImages: { type: Boolean, default: true },
  },
  { timestamps: true }
)

export default mongoose.model('OrbitSettings', settingsSchema)
