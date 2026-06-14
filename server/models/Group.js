import mongoose from 'mongoose'

// Read-only mirror of the auth-server `groups` collection (same Mongo db).
// Orbit only needs membership + the sharedOrbit flag to decide which
// "Group - {name}" directories to surface and who may access them.
const groupSchema = new mongoose.Schema({
  name:        { type: String },
  memberIds:   { type: [String], default: [] },
  sharedOrbit: { type: Boolean, default: false },
}, { timestamps: true, strict: false })

export default mongoose.model('Group', groupSchema)
