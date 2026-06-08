const BASE = '/api/orbit'

async function req(method, path, body) {
  const opts = { method, headers: {} }
  if (body !== undefined) {
    opts.headers['Content-Type'] = 'application/json'
    opts.body = JSON.stringify(body)
  }
  const res = await fetch(`${BASE}${path}`, opts)
  if (!res.ok) {
    const text = await res.text()
    throw new Error(text || `HTTP ${res.status}`)
  }
  return res.json()
}

export const api = {
  browse: (parentId) =>
    req('GET', `/folders/browse${parentId ? `?parentId=${parentId}` : ''}`),
  createFolder: (name, parentId) =>
    req('POST', '/folders', { name, parentId }),
  renameFolder: (id, name) =>
    req('PATCH', `/folders/${id}/rename`, { name }),
  deleteFolder: (id) =>
    req('DELETE', `/folders/${id}`),
  upload: (file, folderId, onProgress) =>
    new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest()
      xhr.upload.onprogress = e => {
        if (e.lengthComputable && onProgress) onProgress(Math.round(e.loaded / e.total * 100))
      }
      xhr.onload = () => {
        if (xhr.status >= 200 && xhr.status < 300) resolve(JSON.parse(xhr.responseText))
        else reject(new Error(`Upload failed: ${xhr.status} ${xhr.responseText}`))
      }
      xhr.onerror = () => reject(new Error('Network error during upload'))
      xhr.open('POST', `${BASE}/files/upload`)
      const fd = new FormData()
      fd.append('file', file)
      if (folderId) fd.append('folderId', folderId)
      xhr.send(fd)
    }),
  renameFile: (id, filename) =>
    req('PATCH', `/files/${id}/rename`, { filename }),
  deleteFile: (id) =>
    req('DELETE', `/files/${id}`),
}
