// Normalise uploaded videos to a broadly-playable form. The problem this
// solves: desktop browsers decode video in software / via OS codecs and happily
// play HEVC (H.265), High-profile H.264, .mov/.mkv, etc. Mobile browsers lean
// on the phone's hardware decoders and reject much of that — so a clip that
// plays on desktop Firefox shows a black frame on the same phone's Firefox.
//
// The fix is a tiered plan based on what ffprobe finds:
//   skip      — already fine (H.264/AAC in .mp4, or a .webm) → store as-is
//   remux     — right codecs, wrong container (e.g. H.264/AAC in .mov) →
//               repackage into .mp4 with `-c copy` (fast, no re-encode)
//   transcode — anything else (HEVC, ProRes, exotic audio, probe failure) →
//               full re-encode to H.264/AAC .mp4
import path from 'path'
import { ffprobe, ffmpeg } from './ffmpeg.js'

// H.264 is the one video codec every mainstream mobile browser decodes in
// hardware. VP8/VP9 also play (in Firefox/Chrome) but only ship in .webm, which
// we leave untouched entirely (see planVideo).
const SAFE_VIDEO = new Set(['h264'])
// Audio codecs that ride along fine in an MP4 for the browser. Empty string =
// a video with no audio track.
const SAFE_AUDIO = new Set(['aac', 'mp3', ''])
// Containers browsers reliably play when the codecs are already compatible.
const SAFE_CONTAINER = new Set(['.mp4', '.m4v'])

// Full transcodes can take a while; keep upload latency sane with `veryfast`
// but still allow a long ceiling for big files. Remux/probe are quick.
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

// Decide what to do to make `filename` broadly playable.
// Returns 'skip' | 'remux' | 'transcode'. Best-effort: a probe failure returns
// 'transcode' (safest for an unknown/odd file).
export async function planVideo(localPath, filename) {
  const ext = path.extname(filename || '').toLowerCase()
  if (ext === '.webm') return 'skip' // VP8/VP9/Opus — already fine on mobile

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

// Re-encode to H.264 (yuv420p, so no 10-bit/4:2:2 the decoder chokes on) + AAC
// in a faststart MP4 — the most broadly playable combination. `+faststart`
// moves the moov atom to the front so playback can begin before the full file
// is fetched.
export async function transcodeToMp4(inPath, outPath) {
  await ffmpeg([
    '-v', 'error',
    '-i', inPath,
    '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '23', '-pix_fmt', 'yuv420p',
    '-c:a', 'aac', '-b:a', '160k',
    '-movflags', '+faststart',
    '-y', outPath,
  ], { timeout: TRANSCODE_TIMEOUT })
}

// Repackage already-compatible streams into an MP4 without re-encoding — fast,
// lossless, just a container swap.
export async function remuxToMp4(inPath, outPath) {
  await ffmpeg([
    '-v', 'error',
    '-i', inPath,
    '-c', 'copy',
    '-movflags', '+faststart',
    '-y', outPath,
  ], { timeout: REMUX_TIMEOUT })
}
