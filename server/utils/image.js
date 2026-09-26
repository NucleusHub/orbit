import path from 'path'
import sharp from 'sharp'

const NEEDS_CONVERT_EXT = new Set(['.heic', '.heif', '.tif', '.tiff'])
const NEEDS_CONVERT_MIME = new Set(['image/heic', 'image/heif', 'image/tiff'])

export function planImage(filename, mime) {
  const ext = path.extname(filename || '').toLowerCase()
  if (NEEDS_CONVERT_EXT.has(ext) || NEEDS_CONVERT_MIME.has(mime)) return 'convert'
  return 'skip'
}

export async function convertToJpeg(inPath, outPath) {
  await sharp(inPath, { failOn: 'none' })
    // Bake in EXIF orientation before the tag is dropped.
    .rotate()
    .jpeg({ quality: 82 })
    .toFile(outPath)
}
