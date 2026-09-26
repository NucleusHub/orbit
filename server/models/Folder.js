import mongoose from 'mongoose'

const folderSchema = new mongoose.Schema({
  profileId: { type: mongoose.Schema.Types.ObjectId, ref: 'Profile', index: true },
  name: { type: String, required: true },
  parentId: { type: mongoose.Schema.Types.ObjectId, ref: 'OrbitFolder', default: null },
  userId: { type: String, default: 'default' },
  passwordHash: { type: String, default: null },
  groupId: { type: mongoose.Schema.Types.ObjectId, ref: 'Group', default: null, index: true },
  ownerId: { type: mongoose.Schema.Types.ObjectId, ref: 'Profile', default: null },
  isGroupRoot: { type: Boolean, default: false },
}, { timestamps: true })

folderSchema.index({ profileId: 1, parentId: 1 })
folderSchema.index({ groupId: 1, parentId: 1 })

export default mongoose.model('OrbitFolder', folderSchema)
