// Thin wrappers around the ffmpeg/ffprobe binaries (installed in the Docker
// image via `apk add ffmpeg`). We shell out rather than depend on a bindings
// package — fewer native build headaches, and the CLI is stable. Paths are
// overridable via env for non-container dev.
import { execFile, spawn } from 'node:child_process'

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

// Streaming ffmpeg for long encodes: spawn (not execFile, so stdout isn't
// buffered) and hand each stdout line to `onLine`. Pair with `-progress pipe:1
// -nostats` so ffmpeg emits key=value progress blocks we can parse for % + ETA.
export function ffmpegProgress(args, { timeout, onLine } = {}) {
  return new Promise((resolve, reject) => {
    const proc = spawn(FFMPEG, args, { stdio: ['ignore', 'pipe', 'pipe'] })
    let stderr = ''
    let buf = ''
    const timer = timeout
      ? setTimeout(() => { proc.kill('SIGKILL'); reject(new Error('ffmpeg timed out')) }, timeout)
      : null

    proc.stdout.on('data', (d) => {
      buf += d.toString()
      let nl
      while ((nl = buf.indexOf('\n')) !== -1) {
        const line = buf.slice(0, nl)
        buf = buf.slice(nl + 1)
        try { onLine?.(line) } catch { /* progress parsing must never kill the encode */ }
      }
    })
    proc.stderr.on('data', (d) => { stderr += d.toString() })
    proc.on('error', (err) => { if (timer) clearTimeout(timer); reject(err) })
    proc.on('close', (code) => {
      if (timer) clearTimeout(timer)
      if (code === 0) resolve()
      else reject(Object.assign(new Error(`ffmpeg exited ${code}`), { stderr }))
    })
  })
}
