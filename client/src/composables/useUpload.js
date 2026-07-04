import { ref } from 'vue'
import { api } from '../api/orbit.js'

// Upload at most this many files at once. A dropped folder can contain hundreds
// of files; firing every request in parallel would swamp the browser's per-host
// connection limit and the server's temp storage, so they run through a pool.
const MAX_CONCURRENT = 4

export function useUpload(onComplete) {
  const uploads = ref([])

  function patch(id, changes) {
    uploads.value = uploads.value.map(u => (u.id === id ? { ...u, ...changes } : u))
  }

  async function uploadOne(file, folderId) {
    const id = Math.random().toString(36).slice(2)
    uploads.value = [...uploads.value, {
      id, filename: file.name, progress: 0, status: 'uploading',
      error: null, loaded: 0, total: file.size || 0, speed: 0, eta: null,
    }]

    // Track a smoothed transfer speed to estimate the time remaining. A plain
    // overall average lags badly when the connection speed shifts, so blend the
    // instantaneous rate into an exponential moving average.
    const start = Date.now()
    let lastTime = start
    let lastLoaded = 0
    let speed = 0

    try {
      const saved = await api.upload(file, folderId, (loaded, total) => {
        const now = Date.now()
        const dt = (now - lastTime) / 1000
        if (dt >= 0.25) {
          const inst = (loaded - lastLoaded) / dt
          speed = speed ? speed * 0.6 + inst * 0.4 : inst
          lastTime = now
          lastLoaded = loaded
        }
        const pct = total ? Math.round((loaded / total) * 100) : 0
        const eta = speed > 0 ? (total - loaded) / speed : null
        patch(id, { progress: pct, loaded, total, speed, eta })
      })

      patch(id, { progress: 100, status: 'done', eta: 0, speed: 0 })
      onComplete?.(saved)
      setTimeout(() => { uploads.value = uploads.value.filter(u => u.id !== id) }, 2500)
    } catch (e) {
      patch(id, { status: 'error', error: e.message })
    }
  }

  // Ensure every folder named in `segments` exists under `baseFolderId`,
  // creating what's missing. `cache` maps a "a/b/c" path key to its folder id so
  // ancestors shared by many files are only created once. Returns the deepest
  // folder's id.
  async function ensureFolderPath(segments, baseFolderId, cache) {
    let parentId = baseFolderId || null
    let key = ''
    for (const name of segments) {
      key = key ? `${key}/${name}` : name
      if (!cache.has(key)) {
        const folder = await api.createFolder(name, parentId)
        cache.set(key, folder._id)
      }
      parentId = cache.get(key)
    }
    return parentId
  }

  // Normalise a FileList/File/{file,relativePath} item into a common shape. A
  // plain File keeps its webkitRelativePath (set when a folder is chosen via the
  // picker) or falls back to its bare name.
  function toEntry(item) {
    if (item && item.file && typeof item.relativePath === 'string') {
      return { file: item.file, relativePath: item.relativePath }
    }
    return { file: item, relativePath: item.webkitRelativePath || item.name }
  }

  const dirOf = relativePath => relativePath.split('/').slice(0, -1).join('/')

  // Accepts a FileList, a File[], or a [{ file, relativePath }] and uploads
  // everything, first recreating any folder structure encoded in the relative
  // paths so a dropped/picked folder lands as a folder in Orbit.
  async function uploadFiles(input, folderId) {
    const entries = Array.from(input || []).map(toEntry).filter(e => e.file)
    if (!entries.length) return

    // Create folders before any file so all files can be dispatched at once.
    // Sort by depth so parents exist before their children.
    const cache = new Map()
    const dirs = [...new Set(entries.map(e => dirOf(e.relativePath)).filter(Boolean))]
      .sort((a, b) => a.split('/').length - b.split('/').length)

    for (const dir of dirs) {
      try {
        await ensureFolderPath(dir.split('/'), folderId, cache)
      } catch (e) {
        console.error('Failed to create folder during upload:', dir, e)
      }
    }

    const tasks = entries.map(e => () => {
      const dir = dirOf(e.relativePath)
      // If the folder couldn't be created, drop the file into the base folder
      // rather than losing it.
      const target = dir ? (cache.get(dir) ?? folderId) : folderId
      return uploadOne(e.file, target)
    })

    await runPool(tasks, MAX_CONCURRENT)
  }

  async function runPool(tasks, limit) {
    let next = 0
    const worker = async () => {
      while (next < tasks.length) {
        const idx = next++
        await tasks[idx]()
      }
    }
    await Promise.all(Array.from({ length: Math.min(limit, tasks.length) }, worker))
  }

  function dismiss(id) {
    uploads.value = uploads.value.filter(u => u.id !== id)
  }

  return { uploads, uploadFiles, dismiss }
}
