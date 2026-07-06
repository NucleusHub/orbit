// Thin re-export of the shared @core server auth (core/server/auth.js), reached
// via the committed `server/core` symlink + the `/app/core` container mount.
// Kept as a stable local path so existing `../middleware/auth.js` imports across
// this app's routes (and Echo's Socket.IO handshake) keep working unchanged.
export { requireAuth, verifyToken, verifyProfile } from '../core/server/auth.js'
