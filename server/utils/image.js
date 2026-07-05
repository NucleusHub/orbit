// Normalise uploaded images the same way transcode.js normalises video: some
// formats decode fine on desktop (or in Safari) but show nothing in Chrome /
// Firefox / most phones. The worst offenders are HEIC/HEIF (the default iPhone
// photo format) — displayable basically only in Safari — and TIFF. We convert
// those to a universally-supported JPEG; everything else is left untouched.
import path from 'path'
import sharp from 'sharp'

const NEEDS_CONVERT_EXT = new Set(['.heic', '.heif', '.tif', '.tiff'])
const NEEDS_CONVERT_MIME = new Set(['image/heic', 'image/heif', 'image/tiff'])

// 'skip' | 'convert'. Extension- and mime-based (no decode needed to decide).
export function planImage(filename, mime) {
  const ext = path.extname(filename || '').toLowerCase()
  if (NEEDS_CONVERT_EXT.has(ext) || NEEDS_CONVERT_MIME.has(mime)) return 'convert'
  return 'skip'
}

// Decode (HEIC/HEIF via libheif, bundled in sharp's prebuilt binary) and
// re-encode to JPEG. `.rotate()` bakes in EXIF orientation so portrait phone
// photos don't come out sideways once the orientation tag is dropped.
export async function convertToJpeg(inPath, outPath) {
  await sharp(inPath, { failOn: 'none' })
    .rotate()
    .jpeg({ quality: 82 })
    .toFile(outPath)
}
