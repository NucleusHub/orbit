import { ref } from 'vue'
import { api } from '../api/orbit.js'

export function useUpload(onComplete) {
  const uploads = ref([])

  async function uploadFile(file, folderId) {
    const id = Math.random().toString(36).slice(2)
    uploads.value = [...uploads.value, { id, filename: file.name, progress: 0, status: 'uploading', error: null }]

    try {
      const saved = await api.upload(file, folderId, pct => {
        uploads.value = uploads.value.map(u => u.id === id ? { ...u, progress: pct } : u)
      })

      uploads.value = uploads.value.map(u => u.id === id ? { ...u, progress: 100, status: 'done' } : u)
      onComplete?.(saved)
      setTimeout(() => { uploads.value = uploads.value.filter(u => u.id !== id) }, 2500)
    } catch (e) {
      uploads.value = uploads.value.map(u => u.id === id ? { ...u, status: 'error', error: e.message } : u)
    }
  }

  function uploadFiles(fileList, folderId) {
    Array.from(fileList).forEach(f => uploadFile(f, folderId))
  }

  function dismiss(id) {
    uploads.value = uploads.value.filter(u => u.id !== id)
  }

  return { uploads, uploadFiles, dismiss }
}
