import mongoose from 'mongoose'

const fileSchema = new mongoose.Schema({
  filename: { type: String, required: true },
  objectKey: { type: String, required: true, unique: true },
  mimeType: { type: String, required: true },
  size: { type: Number, required: true },
  folderId: { type: mongoose.Schema.Types.ObjectId, ref: 'OrbitFolder', default: null },
  userId: { type: String, default: 'default' },
}, { timestamps: true })

fileSchema.index({ userId: 1, folderId: 1 })

export default mongoose.model('OrbitFile', fileSchema)
