// Thin wrappers around the ffmpeg/ffprobe binaries (installed in the Docker
// image via `apk add ffmpeg`). We shell out rather than depend on a bindings
// package — fewer native build headaches, and the CLI is stable. Paths are
// overridable via env for non-container dev.
import { execFile } from 'node:child_process'

const FFPROBE = process.env.FFPROBE_PATH || 'ffprobe'
const FFMPEG = process.env.FFMPEG_PATH || 'ffmpeg'

function run(bin, args, { timeout = 60_000 } = {}) {
  return new Promise((resolve, reject) => {
    execFile(bin, args, { timeout, maxBuffer: 16 * 1024 * 1024 }, (err, stdout, stderr) => {
      if (err) {
        err.stderr = stderr
        return reject(err)
      }
      resolve(stdout)
    })
  })
}

export function ffprobe(args, opts) {
  return run(FFPROBE, args, opts)
}

export function ffmpeg(args, opts) {
  return run(FFMPEG, args, opts)
}
