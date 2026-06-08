import { ref } from 'vue'
import { api } from '../api/orbit.js'

export function useFiles() {
  const folders = ref([])
  const files = ref([])
  const breadcrumbs = ref([])
  const loading = ref(false)
  const error = ref(null)
  const currentFolderId = ref(null)

  async function browse(folderId = null) {
    loading.value = true
    error.value = null
    currentFolderId.value = folderId
    try {
      const data = await api.browse(folderId)
      folders.value = data.folders
      files.value = data.files
      breadcrumbs.value = data.breadcrumbs
    } catch (e) {
      error.value = e.message
    } finally {
      loading.value = false
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
    if (idx !== -1) files.value[idx] = updated
  }

  async function deleteFile(id) {
    await api.deleteFile(id)
    files.value = files.value.filter(f => f._id !== id)
  }

  return {
    folders, files, breadcrumbs, loading, error, currentFolderId,
    browse, createFolder, renameFolder, deleteFolder, renameFile, deleteFile,
  }
}
