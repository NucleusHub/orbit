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
  // Shared group storage — see Folder.js. groupId scopes the file to a group's
  // shared directory; ownerId (the uploader) is the only one who may edit/delete it.
  groupId: { type: mongoose.Schema.Types.ObjectId, ref: 'Group', default: null, index: true },
  ownerId: { type: mongoose.Schema.Types.ObjectId, ref: 'Profile', default: null },
  // Background video normalisation (see transcodeQueue.js). 'none' = not a
  // video, or nothing to do; 'pending'/'processing' = queued/running; 'done' =
  // stored as a browser-friendly MP4; 'failed' = the encode errored (original
  // is kept). Surfaced to the client so it can show a "converting" indicator.
  transcodeStatus: {
    type: String,
    enum: ['none', 'pending', 'processing', 'done', 'failed'],
    default: 'none',
  },
}, { timestamps: true })

fileSchema.index({ profileId: 1, folderId: 1 })
fileSchema.index({ groupId: 1, folderId: 1 })

export default mongoose.model('OrbitFile', fileSchema)
