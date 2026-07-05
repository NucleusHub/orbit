import path from 'path'

// Dependency-free extension -> MIME map. Covers the types Orbit actually
// previews (video/audio/image/pdf/text) plus common office/archive formats.
// The browser decides whether it can play/render a file from the HTTP
// Content-Type, so getting this right is what makes in-app preview work.
const BY_EXT = {
  // video
  '.mp4': 'video/mp4',
  '.m4v': 'video/mp4',
  '.mov': 'video/quicktime',
  '.webm': 'video/webm',
  '.mkv': 'video/x-matroska',
  '.avi': 'video/x-msvideo',
  '.ogv': 'video/ogg',
  // audio
  '.mp3': 'audio/mpeg',
  '.m4a': 'audio/mp4',
  '.aac': 'audio/aac',
  '.wav': 'audio/wav',
  '.flac': 'audio/flac',
  '.oga': 'audio/ogg',
  '.ogg': 'audio/ogg',
  '.opus': 'audio/opus',
  // image
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.svg': 'image/svg+xml',
  '.bmp': 'image/bmp',
  '.ico': 'image/x-icon',
  '.avif': 'image/avif',
  '.heic': 'image/heic',
  '.heif': 'image/heif',
  '.tif': 'image/tiff',
  '.tiff': 'image/tiff',
  // documents / text
  '.pdf': 'application/pdf',
  '.txt': 'text/plain',
  '.md': 'text/markdown',
  '.csv': 'text/csv',
  '.json': 'application/json',
  '.xml': 'application/xml',
  '.html': 'text/html',
  '.htm': 'text/html',
  '.css': 'text/css',
  '.js': 'text/javascript',
  '.doc': 'application/msword',
  '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  '.xls': 'application/vnd.ms-excel',
  '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  '.ppt': 'application/vnd.ms-powerpoint',
  '.pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  // archives
  '.zip': 'application/zip',
  '.gz': 'application/gzip',
  '.tar': 'application/x-tar',
  '.7z': 'application/x-7z-compressed',
  '.rar': 'application/vnd.rar',
}

// A MIME type is "useless" for preview if it's missing or the generic binary
// catch-all that browsers refuse to render.
function isGeneric(type) {
  return !type || type === 'application/octet-stream' || type === 'binary/octet-stream'
}

// Best Content-Type for a file: trust the extension when we recognise it,
// otherwise fall back to the supplied type (e.g. multer's guess), and finally
// to the binary catch-all. Recognised extensions win over a generic supplied
// type so files that arrived as application/octet-stream still preview.
export function mimeFor(filename, fallback) {
  const ext = path.extname(filename || '').toLowerCase()
  const known = BY_EXT[ext]
  if (known) return known
  if (!isGeneric(fallback)) return fallback
  return 'application/octet-stream'
}
