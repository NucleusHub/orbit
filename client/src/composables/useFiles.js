import { ref } from 'vue'
import { api } from '../api/orbit.js'

export function useFiles() {
  const folders = ref([])
  const files = ref([])
  const breadcrumbs = ref([])
  const loading = ref(false)
  const error = ref(null)
  const currentFolderId = ref(null)
  const lockedFolderId = ref(null)

  async function browse(folderId = null) {
    loading.value = true
    error.value = null
    lockedFolderId.value = null
    currentFolderId.value = folderId
    try {
      const password = folderId ? sessionStorage.getItem(`orbit:pwd:folder:${folderId}`) : null
      const data = await api.browse(folderId, password)
      folders.value = data.folders
      files.value = data.files.map(f => {
        if (f.protected && !f.url) {
          const cached = sessionStorage.getItem(`orbit:url:file:${f._id}`)
          if (cached) return { ...f, url: cached }
        }
        return f
      })
      breadcrumbs.value = data.breadcrumbs
    } catch (e) {
      if (e.status === 401 && e.data?.locked) {
        lockedFolderId.value = folderId
        return
      }
      error.value = e.message
    } finally {
      loading.value = false
    }
  }

  // Re-fetch the current folder without toggling `loading` (no spinner flicker).
  // Used by the transcode poller to pick up files as they finish converting;
  // preserves in-session unlocked URLs the same way browse() does.
  async function silentRefresh() {
    try {
      const fid = currentFolderId.value
      const password = fid ? sessionStorage.getItem(`orbit:pwd:folder:${fid}`) : null
      const data = await api.browse(fid, password)
      folders.value = data.folders
      files.value = data.files.map(f => {
        if (f.protected && !f.url) {
          const cached = sessionStorage.getItem(`orbit:url:file:${f._id}`)
          if (cached) return { ...f, url: cached }
        }
        return f
      })
    } catch {
      // Best-effort background refresh — ignore transient failures.
    }
  }

  function unlockFolder(folderId, password) {
    sessionStorage.setItem(`orbit:pwd:folder:${folderId}`, password)
    lockedFolderId.value = null
    browse(folderId)
  }

  function cancelFolderUnlock() {
    // Revert to the parent — breadcrumbs still reflect the last successful browse
    const parentId = breadcrumbs.value[breadcrumbs.value.length - 1]?._id ?? null
    lockedFolderId.value = null
    currentFolderId.value = parentId
  }

  function unlockFileInList(fileId, url) {
    sessionStorage.setItem(`orbit:url:file:${fileId}`, url)
    files.value = files.value.map(f => f._id === fileId ? { ...f, url } : f)
  }

  function updateItem(type, updated) {
    if (type === 'folder') {
      const idx = folders.value.findIndex(f => f._id === updated._id)
      if (idx !== -1) folders.value[idx] = updated
    } else {
      const idx = files.value.findIndex(f => f._id === updated._id)
      if (idx !== -1) files.value[idx] = updated
    }
  }

  async function createFolder(name) {
    const folder = await api.createFolder(name, currentFolderId.value)
    folders.value = [...folders.value, folder].sort((a, b) => a.name.localeCompare(b.name))
  }

  async function renameFolder(id, name) {
    const updated = await api.renameFolder(id, name)
    const idx = folders.value.findIndex(f => f._id === id)
    if (idx !== -1) folders.value[idx] = updated
  }

  async function deleteFolder(id) {
    await api.deleteFolder(id)
    folders.value = folders.value.filter(f => f._id !== id)
  }

  async function renameFile(id, filename) {
    const updated = await api.renameFile(id, filename)
    const idx = files.value.findIndex(f => f._id === id)
    if (idx !== -1) files.value[idx] = { ...updated, url: files.value[idx].url }
  }

  async function deleteFile(id) {
    await api.deleteFile(id)
    files.value = files.value.filter(f => f._id !== id)
    sessionStorage.removeItem(`orbit:url:file:${id}`)
  }

  return {
    folders, files, breadcrumbs, loading, error, currentFolderId, lockedFolderId,
    browse, silentRefresh, unlockFolder, cancelFolderUnlock, unlockFileInList, updateItem,
    createFolder, renameFolder, deleteFolder, renameFile, deleteFile,
  }
}
