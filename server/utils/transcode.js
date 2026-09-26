import path from 'path'
import { ffprobe, ffmpeg, ffmpegProgress } from './ffmpeg.js'

const SAFE_VIDEO = new Set(['h264'])
const SAFE_AUDIO = new Set(['aac', 'mp3', ''])
const SAFE_CONTAINER = new Set(['.mp4', '.m4v'])

const PROBE_TIMEOUT = 30_000
const REMUX_TIMEOUT = 5 * 60_000
const TRANSCODE_TIMEOUT = 30 * 60_000

async function probe(localPath) {
  const out = await ffprobe([
    '-v', 'error',
    '-print_format', 'json',
    '-show_streams',
    localPath,
  ], { timeout: PROBE_TIMEOUT })
  const json = JSON.parse(out)
  const v = (json.streams || []).find((s) => s.codec_type === 'video')
  const a = (json.streams || []).find((s) => s.codec_type === 'audio')
  return { vcodec: v?.codec_name || '', acodec: a?.codec_name || '' }
}

export async function planVideo(localPath, filename) {
  const ext = path.extname(filename || '').toLowerCase()
  if (ext === '.webm') return 'skip'

  let info
  try {
    info = await probe(localPath)
  } catch {
    return 'transcode'
  }

  const codecsOk = SAFE_VIDEO.has(info.vcodec) && SAFE_AUDIO.has(info.acodec)
  if (!codecsOk) return 'transcode'
  return SAFE_CONTAINER.has(ext) ? 'skip' : 'remux'
}

export async function probeDuration(localPath) {
  try {
    const out = await ffprobe([
      '-v', 'error',
      '-show_entries', 'format=duration',
      '-of', 'default=nw=1:nk=1',
      localPath,
    ], { timeout: PROBE_TIMEOUT })
    const d = parseFloat(String(out).trim())
    return Number.isFinite(d) && d > 0 ? d : 0
  } catch {
    return 0
  }
}

function parseClock(s) {
  const m = /^(\d+):(\d+):(\d+(?:\.\d+)?)$/.exec(String(s).trim())
  if (!m) return null
  return Number(m[1]) * 3600 + Number(m[2]) * 60 + parseFloat(m[3])
}

export async function transcodeToMp4(inPath, outPath, { onProgress } = {}) {
  const duration = await probeDuration(inPath)
  let outTime = 0
  let speed = 0

  await ffmpegProgress([
    '-nostdin', '-v', 'error',
    '-i', inPath,
    // yuv420p: mobile hardware decoders reject 10-bit / 4:2:2.
    '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23', '-pix_fmt', 'yuv420p',
    '-c:a', 'aac', '-b:a', '160k',
    '-movflags', '+faststart',
    '-progress', 'pipe:1', '-nostats',
    '-y', outPath,
  ], {
    timeout: TRANSCODE_TIMEOUT,
    onLine: (line) => {
      if (!onProgress) return
      const i = line.indexOf('=')
      if (i < 0) return
      const key = line.slice(0, i).trim()
      const val = line.slice(i + 1).trim()
      if (key === 'out_time') {
        const t = parseClock(val)
        if (t != null) outTime = t
      } else if (key === 'speed') {
        const s = parseFloat(val)
        if (Number.isFinite(s)) speed = s
      } else if (key === 'progress') {
        const percent = duration > 0 ? Math.max(0, Math.min(99, Math.round((outTime / duration) * 100))) : null
        const eta = duration > 0 && speed > 0 ? Math.max(0, Math.round((duration - outTime) / speed)) : null
        onProgress({ percent, eta })
      }
    },
  })
}

export async function remuxToMp4(inPath, outPath) {
  await ffmpeg([
    '-v', 'error',
    '-i', inPath,
    '-c', 'copy',
    '-movflags', '+faststart',
    '-y', outPath,
  ], { timeout: REMUX_TIMEOUT })
}
