import mongoose from 'mongoose'

const folderSchema = new mongoose.Schema({
  name: { type: String, required: true },
  parentId: { type: mongoose.Schema.Types.ObjectId, ref: 'OrbitFolder', default: null },
  userId: { type: String, default: 'default' },
  passwordHash: { type: String, default: null },
}, { timestamps: true })

folderSchema.index({ userId: 1, parentId: 1 })

export default mongoose.model('OrbitFolder', folderSchema)
