import mongoose from 'mongoose'

const groupSchema = new mongoose.Schema({
  name:        { type: String },
  memberIds:   { type: [String], default: [] },
  sharedOrbit: { type: Boolean, default: false },
}, { timestamps: true, strict: false })

export default mongoose.model('Group', groupSchema)
