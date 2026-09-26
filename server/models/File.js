import mongoose from 'mongoose'

const fileSchema = new mongoose.Schema({
  profileId: { type: mongoose.Schema.Types.ObjectId, ref: 'Profile', index: true },
  filename: { type: String, required: true },
  objectKey: { type: String, required: true, unique: true },
  mimeType: { type: String, required: true },
  size: { type: Number, required: true },
  folderId: { type: mongoose.Schema.Types.ObjectId, ref: 'OrbitFolder', default: null },
  userId: { type: String, default: 'default' },
  passwordHash: { type: String, default: null },
  groupId: { type: mongoose.Schema.Types.ObjectId, ref: 'Group', default: null, index: true },
  ownerId: { type: mongoose.Schema.Types.ObjectId, ref: 'Profile', default: null },
  transcodeStatus: {
    type: String,
    enum: ['none', 'pending', 'processing', 'done', 'failed'],
    default: 'none',
  },
}, { timestamps: true })

fileSchema.index({ profileId: 1, folderId: 1 })
fileSchema.index({ groupId: 1, folderId: 1 })

export default mongoose.model('OrbitFile', fileSchema)
