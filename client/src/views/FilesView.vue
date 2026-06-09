<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import AppSidebar from '@core/AppSidebar.vue'
import ConfirmModal from '@core/ConfirmModal.vue'
import FileBrowser from '../components/FileBrowser.vue'
import Breadcrumbs from '../components/Breadcrumbs.vue'
import SearchBar from '../components/SearchBar.vue'
import UploadZone from '../components/UploadZone.vue'
import UploadProgress from '../components/UploadProgress.vue'
import CreateFolderModal from '../components/CreateFolderModal.vue'
import FilePreviewModal from '../components/FilePreviewModal.vue'
import PasswordPromptModal from '../components/PasswordPromptModal.vue'
import SetPasswordModal from '../components/SetPasswordModal.vue'
import MoveModal from '../components/MoveModal.vue'
import ContextMenu from '../components/ContextMenu.vue'
import { useFiles } from '../composables/useFiles.js'
import { useUpload } from '../composables/useUpload.js'
import { api } from '../api/orbit.js'

const sidebarOpen = ref(false)
const viewMode = ref(localStorage.getItem('orbit:viewMode') || 'grid')
watch(viewMode, v => localStorage.setItem('orbit:viewMode', v))
const search = ref('')
const dragOver = ref(false)
const showCreateFolder = ref(false)
const confirmTarget = ref(null) // { type, id, name } or { bulk: true, count, items }
const previewFile = ref(null)
const fileInput = ref(null)

// Multi-select
const selection = ref([]) // [{ type: 'file'|'folder', item }]

function toggleSelect(type, item) {
  const idx = selection.value.findIndex(s => s.type === type && s.item._id === item._id)
  if (idx === -1) selection.value = [...selection.value, { type, item }]
  else selection.value = selection.value.filter((_, i) => i !== idx)
}

function clearSelection() {
  selection.value = []
}

// Selection context menu (right-click on selected item when 2+ selected)
const selCtxOpen = ref(false)
const selCtxX = ref(0)
const selCtxY = ref(0)

const ICONS_SEL = {
  move: 'M7.5 21 3 16.5m0 0L7.5 12M3 16.5h13.5m0-13.5L21 7.5m0 0L16.5 12M21 7.5H7.5',
  delete: 'm14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0',
  lock: 'M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25z',
}

const selCtxItems = computed(() => {
  const n = selection.value.length
  return [
    { label: `Move ${n} items`, icon: ICONS_SEL.move, action: () => { movingSelection.value = true } },
    { label: `Set password`, icon: ICONS_SEL.lock, action: () => { settingPasswordForSelection.value = true } },
    { divider: true },
    { label: `Delete ${n} items`, icon: ICONS_SEL.delete, action: promptDeleteSelection, danger: true },
  ]
})

function openSelCtx(x, y) {
  selCtxX.value = x
  selCtxY.value = y
  selCtxOpen.value = true
}

// Bulk move
const movingSelection = ref(false)
async function handleMoveSelection(targetFolderId) {
  try {
    await Promise.all(selection.value.map(({ type, item }) =>
      type === 'file' ? api.moveFile(item._id, targetFolderId) : api.moveFolder(item._id, targetFolderId)
    ))
    clearSelection()
    browse(currentFolderId.value)
  } catch (e) {
    console.error('Bulk move failed:', e)
  } finally {
    movingSelection.value = false
  }
}

// Bulk password
const settingPasswordForSelection = ref(false)
async function onSetPasswordForSelection(password) {
  try {
    await Promise.all(selection.value.map(({ type, item }) =>
      type === 'folder' ? api.setFolderPassword(item._id, password) : api.setFilePassword(item._id, password)
    ))
    selection.value.filter(s => s.type === 'file').forEach(s => sessionStorage.removeItem(`orbit:url:file:${s.item._id}`))
    clearSelection()
    browse(currentFolderId.value)
  } catch (e) {
    console.error('Bulk set password failed:', e)
  } finally {
    settingPasswordForSelection.value = false
  }
}

// Bulk delete
function promptDeleteSelection() {
  confirmTarget.value = { bulk: true, count: selection.value.length, items: [...selection.value] }
}

// Background context menu
const bgCtxOpen = ref(false)
const bgCtxX = ref(0)
const bgCtxY = ref(0)
const bgCtxItems = computed(() => [
  {
    label: 'New Folder',
    icon: 'M12 10.5v6m3-3H9m4.06-7.19-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44z',
    action: () => { showCreateFolder.value = true },
  },
  {
    label: 'Upload Files',
    icon: 'M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5m-13.5-9L12 3m0 0 4.5 4.5M12 3v13.5',
    action: () => { fileInput.value?.click() },
  },
  { divider: true },
  {
    label: viewMode.value === 'grid' ? 'List View' : 'Grid View',
    icon: viewMode.value === 'grid'
      ? 'M8.25 6.75h12M8.25 12h12m-12 5.25h12M3.75 6.75h.007v.008H3.75V6.75zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0zM3.75 12h.007v.008H3.75V12zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0zm-.375 5.25h.007v.008H3.75v-.008zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0z'
      : 'M3.75 6A2.25 2.25 0 0 1 6 3.75h2.25A2.25 2.25 0 0 1 10.5 6v2.25a2.25 2.25 0 0 1-2.25 2.25H6a2.25 2.25 0 0 1-2.25-2.25V6zM3.75 15.75A2.25 2.25 0 0 1 6 13.5h2.25a2.25 2.25 0 0 1 2.25 2.25V18a2.25 2.25 0 0 1-2.25 2.25H6A2.25 2.25 0 0 1 3.75 18v-2.25zM13.5 6a2.25 2.25 0 0 1 2.25-2.25H18A2.25 2.25 0 0 1 20.25 6v2.25A2.25 2.25 0 0 1 18 10.5h-2.25a2.25 2.25 0 0 1-2.25-2.25V6zM13.5 15.75a2.25 2.25 0 0 1 2.25-2.25H18a2.25 2.25 0 0 1 2.25 2.25V18A2.25 2.25 0 0 1 18 20.25h-2.25A2.25 2.25 0 0 1 13.5 18v-2.25z',
    action: () => { viewMode.value = viewMode.value === 'grid' ? 'list' : 'grid' },
  },
  { divider: true },
  {
    label: 'Refresh',
    icon: 'M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0 3.181 3.183a8.25 8.25 0 0 0 13.803-3.7M4.031 9.865a8.25 8.25 0 0 1 13.803-3.7l3.181 3.182m0-4.991v4.99',
    action: () => { browse(currentFolderId.value) },
  },
])

function onBgContextMenu(e) {
  e.preventDefault()
  bgCtxX.value = e.clientX
  bgCtxY.value = e.clientY
  bgCtxOpen.value = true
}

const {
  folders, files, breadcrumbs, loading, error, currentFolderId, lockedFolderId,
  browse, unlockFolder, cancelFolderUnlock, unlockFileInList, updateItem,
  createFolder, renameFolder, deleteFolder, renameFile, deleteFile,
} = useFiles()

// Password prompt for locked folders
const folderPwdError = ref(null)
async function onFolderUnlock(password) {
  folderPwdError.value = null
  try {
    unlockFolder(lockedFolderId.value, password)
  } catch {
    folderPwdError.value = 'Wrong password'
  }
}

// File unlock
const unlockingFile = ref(null)
const filePwdError = ref(null)
async function onFileUnlock(password) {
  filePwdError.value = null
  try {
    const { url } = await api.unlockFile(unlockingFile.value._id, password)
    unlockFileInList(unlockingFile.value._id, url)
    unlockingFile.value = null
  } catch {
    filePwdError.value = 'Wrong password'
  }
}

// Move
const movingItem = ref(null) // { type: 'file'|'folder', item }
async function handleMove(targetFolderId) {
  const { type, item } = movingItem.value
  try {
    if (type === 'file') await api.moveFile(item._id, targetFolderId)
    else await api.moveFolder(item._id, targetFolderId)
    browse(currentFolderId.value)
  } catch (e) {
    console.error('Move failed:', e)
  } finally {
    movingItem.value = null
  }
}

// Set password
const settingPasswordFor = ref(null) // { type: 'file'|'folder', item }
async function onSetPassword(password) {
  const { type, item } = settingPasswordFor.value
  try {
    if (type === 'folder') await api.setFolderPassword(item._id, password)
    else {
      await api.setFilePassword(item._id, password)
      sessionStorage.removeItem(`orbit:url:file:${item._id}`)
    }
    browse(currentFolderId.value)
  } catch (e) {
    console.error('Set password failed:', e)
  } finally {
    settingPasswordFor.value = null
  }
}

// Action auth gate — verifies password before executing sensitive actions on protected items
const pendingAuth = ref(null) // { type: 'file'|'folder', item, action }
const pendingAuthError = ref(null)
const renamingItem = ref(null) // { type, item } — rename modal shown after auth

function withAuth(type, item, action) {
  const verified = type === 'file'
    ? (!item.protected || !!item.url)
    : (!item.protected || !!sessionStorage.getItem(`orbit:verified:folder:${item._id}`))
  if (verified) { action(); return }
  pendingAuth.value = { type, item, action }
  pendingAuthError.value = null
}

async function onPendingAuth(password) {
  const { type, item, action } = pendingAuth.value
  pendingAuthError.value = null
  try {
    if (type === 'file') {
      const { url } = await api.unlockFile(item._id, password)
      unlockFileInList(item._id, url)
    } else {
      await api.verifyFolder(item._id, password)
      sessionStorage.setItem(`orbit:verified:folder:${item._id}`, '1')
    }
    pendingAuth.value = null
    action()
  } catch (e) {
    pendingAuthError.value = e.status === 401 ? 'Wrong password' : 'Verification failed'
  }
}

async function onRenameSubmit(newName) {
  if (!renamingItem.value) return
  const { type, item } = renamingItem.value
  renamingItem.value = null
  if (type === 'file') await renameFile(item._id, newName)
  else await renameFolder(item._id, newName)
}

const { uploads, uploadFiles, dismiss } = useUpload(onUploadDone)

onMounted(() => browse(null))

function onUploadDone() {
  browse(currentFolderId.value)
}

const searchResults = ref({ folders: [], files: [] })
const searchLoading = ref(false)
let searchTimer = null
watch(search, (val) => {
  clearTimeout(searchTimer)
  if (!val.trim()) { searchResults.value = { folders: [], files: [] }; return }
  searchTimer = setTimeout(async () => {
    try {
      searchLoading.value = true
      searchResults.value = await api.search(val.trim())
    } catch (e) {
      console.error('Search failed:', e)
    } finally {
      searchLoading.value = false
    }
  }, 300)
})

const filteredFolders = computed(() => search.value ? searchResults.value.folders : folders.value)
const filteredFiles = computed(() => search.value ? searchResults.value.files : files.value)
const isEmpty = computed(() => !filteredFolders.value.length && !filteredFiles.value.length)
const parentFolderId = computed(() => {
  if (search.value) return undefined
  if (currentFolderId.value === null) return undefined
  return breadcrumbs.value.length >= 2
    ? (breadcrumbs.value[breadcrumbs.value.length - 2]._id ?? null)
    : null
})

function navigate(folderId) {
  search.value = ''
  clearSelection()
  browse(folderId)
}

watch(search, () => { if (selection.value.length) clearSelection() })

function onDragover(e) {
  e.preventDefault()
  dragOver.value = true
}
function onDragleave(e) {
  if (!e.currentTarget.contains(e.relatedTarget)) dragOver.value = false
}
function onDrop(e) {
  e.preventDefault()
  dragOver.value = false
  if (e.target.closest('[data-upload-zone]')) return
  if (e.dataTransfer.files.length) uploadFiles(e.dataTransfer.files, currentFolderId.value)
}

function handleFileInput(e) {
  if (e.target.files.length) uploadFiles(e.target.files, currentFolderId.value)
  e.target.value = ''
}

async function handleCreateFolder(name) {
  await createFolder(name)
  showCreateFolder.value = false
}

function promptDelete(type, item) {
  confirmTarget.value = {
    type,
    id: item._id,
    name: type === 'file' ? item.filename : item.name,
  }
}

async function executeDelete() {
  if (!confirmTarget.value) return
  if (confirmTarget.value.bulk) {
    const { items } = confirmTarget.value
    try {
      await Promise.all(items.map(({ type, item }) =>
        type === 'file' ? api.deleteFile(item._id) : api.deleteFolder(item._id)
      ))
      items.filter(s => s.type === 'file').forEach(s => sessionStorage.removeItem(`orbit:url:file:${s.item._id}`))
      clearSelection()
      browse(currentFolderId.value)
    } catch (e) {
      console.error('Bulk delete failed:', e)
    }
  } else {
    const { type, id } = confirmTarget.value
    if (type === 'file') await deleteFile(id)
    else await deleteFolder(id)
  }
  confirmTarget.value = null
}
</script>

<template>
  <div
    class="min-h-screen"
    @dragover="onDragover"
    @dragleave="onDragleave"
    @drop="onDrop"
    @contextmenu="onBgContextMenu"
  >
    <AppSidebar :open="sidebarOpen" @close="sidebarOpen = false" />
    <input ref="fileInput" type="file" multiple class="hidden" @change="handleFileInput" />

    <!-- Header -->
    <header class="sticky top-0 z-30 flex items-center gap-2 sm:gap-3 px-4 h-14 bg-white/60 dark:bg-slate-900/60 backdrop-blur-2xl border-b border-slate-200/80 dark:border-white/8" @contextmenu.stop>
      <!-- Sidebar toggle -->
      <button
        @click="sidebarOpen = true"
        class="cursor-pointer p-2 -ml-1 rounded-xl text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-slate-200 hover:bg-black/5 dark:hover:bg-white/8 transition-colors shrink-0"
        aria-label="Open navigation"
      >
        <svg class="w-5 h-5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5" />
        </svg>
      </button>

      <div class="flex-1" />

      <!-- Search -->
      <SearchBar v-model="search" />

      <!-- View toggle -->
      <div class="flex gap-0.5 bg-black/5 dark:bg-white/8 rounded-lg p-0.5 shrink-0">
        <button
          @click="viewMode = 'grid'"
          :class="['cursor-pointer p-1.5 rounded-md transition-colors', viewMode === 'grid' ? 'bg-white dark:bg-white/20 text-slate-900 dark:text-white shadow-sm' : 'text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-slate-300']"
          title="Grid view"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 6A2.25 2.25 0 0 1 6 3.75h2.25A2.25 2.25 0 0 1 10.5 6v2.25a2.25 2.25 0 0 1-2.25 2.25H6a2.25 2.25 0 0 1-2.25-2.25V6zM3.75 15.75A2.25 2.25 0 0 1 6 13.5h2.25a2.25 2.25 0 0 1 2.25 2.25V18a2.25 2.25 0 0 1-2.25 2.25H6A2.25 2.25 0 0 1 3.75 18v-2.25zM13.5 6a2.25 2.25 0 0 1 2.25-2.25H18A2.25 2.25 0 0 1 20.25 6v2.25A2.25 2.25 0 0 1 18 10.5h-2.25a2.25 2.25 0 0 1-2.25-2.25V6zM13.5 15.75a2.25 2.25 0 0 1 2.25-2.25H18a2.25 2.25 0 0 1 2.25 2.25V18A2.25 2.25 0 0 1 18 20.25h-2.25A2.25 2.25 0 0 1 13.5 18v-2.25z" />
          </svg>
        </button>
        <button
          @click="viewMode = 'list'"
          :class="['cursor-pointer p-1.5 rounded-md transition-colors', viewMode === 'list' ? 'bg-white dark:bg-white/20 text-slate-900 dark:text-white shadow-sm' : 'text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-slate-300']"
          title="List view"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M8.25 6.75h12M8.25 12h12m-12 5.25h12M3.75 6.75h.007v.008H3.75V6.75zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0zM3.75 12h.007v.008H3.75V12zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0zm-.375 5.25h.007v.008H3.75v-.008zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0z" />
          </svg>
        </button>
      </div>

      <!-- New folder -->
      <button
        @click="showCreateFolder = true"
        class="cursor-pointer flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-slate-700 dark:text-slate-300 bg-black/5 dark:bg-white/8 hover:bg-black/8 dark:hover:bg-white/12 rounded-xl transition-colors shrink-0"
      >
        <svg class="w-4 h-4 shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 10.5v6m3-3H9m4.06-7.19-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44z" />
        </svg>
        <span class="hidden sm:inline">New folder</span>
      </button>

      <!-- Upload -->
      <button
        @click="fileInput.click()"
        class="cursor-pointer flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-500 rounded-xl transition-colors shrink-0"
      >
        <svg class="w-4 h-4 shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5m-13.5-9L12 3m0 0 4.5 4.5M12 3v13.5" />
        </svg>
        <span class="hidden sm:inline">Upload</span>
      </button>
    </header>

    <!-- Breadcrumbs -->
    <Breadcrumbs :crumbs="breadcrumbs" @navigate="navigate" @contextmenu.stop />

    <!-- Main content -->
    <main class="px-4 md:px-6 pt-6 pb-24">
      <!-- Loading -->
      <div v-if="loading || searchLoading" class="flex items-center justify-center py-20">
        <svg class="w-8 h-8 text-indigo-500 animate-spin" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 0 1 8-8V0C5.373 0 0 5.373 0 12h4z" />
        </svg>
      </div>

      <!-- Error -->
      <div v-else-if="error" class="flex flex-col items-center justify-center py-20 gap-3 text-center">
        <svg class="w-12 h-12 text-red-400" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m9-.75a9 9 0 1 1-18 0 9 9 0 0 1 18 0zm-9 3.75h.008v.008H12v-.008z" />
        </svg>
        <p class="text-sm text-slate-500 dark:text-slate-400">{{ error }}</p>
        <button @click="browse(currentFolderId)" class="cursor-pointer text-sm text-indigo-600 dark:text-indigo-400 hover:underline">Try again</button>
      </div>

      <!-- Empty state + upload zone -->
      <div v-else-if="isEmpty && !search">
        <div class="max-w-lg mx-auto pt-12">
          <UploadZone @files="files => uploadFiles(files, currentFolderId)" />
          <div class="mt-6 text-center">
            <button
              @click="showCreateFolder = true"
              class="cursor-pointer text-sm text-slate-400 dark:text-slate-500 hover:text-slate-600 dark:hover:text-slate-300 transition-colors"
            >
              or create a new folder
            </button>
          </div>
        </div>
      </div>

      <!-- Search empty state -->
      <div v-else-if="isEmpty && search" class="flex flex-col items-center justify-center py-20 gap-3 text-center">
        <svg class="w-12 h-12 text-slate-300 dark:text-slate-600" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="m21 21-5.197-5.197m0 0A7.5 7.5 0 1 0 5.196 5.196a7.5 7.5 0 0 0 10.607 10.607z" />
        </svg>
        <p class="text-sm text-slate-500 dark:text-slate-400">No results for "<strong>{{ search }}</strong>"</p>
        <button @click="search = ''" class="cursor-pointer text-sm text-indigo-600 dark:text-indigo-400 hover:underline">Clear search</button>
      </div>

      <!-- File browser -->
      <FileBrowser
        v-else
        :folders="filteredFolders"
        :files="filteredFiles"
        :view-mode="viewMode"
        :parent-folder-id="parentFolderId"
        :uploadable="!search"
        :selection="selection"
        @open-folder="navigate"
        @rename-folder="renameFolder"
        @rename-folder-request="f => withAuth('folder', f, () => { renamingItem = { type: 'folder', item: f } })"
        @delete-folder="f => withAuth('folder', f, () => promptDelete('folder', f))"
        @set-password-folder="f => withAuth('folder', f, () => { settingPasswordFor = { type: 'folder', item: f } })"
        @move-folder="f => withAuth('folder', f, () => { movingItem = { type: 'folder', item: f } })"
        @rename-file="renameFile"
        @rename-file-request="f => withAuth('file', f, () => { renamingItem = { type: 'file', item: f } })"
        @delete-file="f => withAuth('file', f, () => promptDelete('file', f))"
        @preview-file="previewFile = $event"
        @unlock-file="f => { unlockingFile = f; filePwdError = null }"
        @set-password-file="f => withAuth('file', f, () => { settingPasswordFor = { type: 'file', item: f } })"
        @move-file="f => withAuth('file', f, () => { movingItem = { type: 'file', item: f } })"
        @upload="files => uploadFiles(files, currentFolderId)"
        @toggle-select="toggleSelect"
        @open-selection-ctx="openSelCtx"
      />
    </main>

    <!-- Drop overlay -->
    <Transition name="fade">
      <div v-if="dragOver" class="fixed inset-0 z-40 pointer-events-none">
        <div class="absolute inset-4 rounded-2xl border-2 border-dashed border-indigo-500 bg-indigo-500/8 dark:bg-indigo-500/12 backdrop-blur-sm flex flex-col items-center justify-center gap-3">
          <svg class="w-12 h-12 text-indigo-500" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 16.5V9.75m0 0 3 3m-3-3-3 3M6.75 19.5a4.5 4.5 0 0 1-1.41-8.775 5.25 5.25 0 0 1 10.233-2.33 3 3 0 0 1 3.758 3.848A3.752 3.752 0 0 1 18 19.5H6.75z" />
          </svg>
          <p class="text-lg font-semibold text-indigo-600 dark:text-indigo-400">Drop to upload</p>
        </div>
      </div>
    </Transition>

    <!-- Selection toolbar -->
    <Transition name="fade">
      <div
        v-if="selection.length > 0"
        class="fixed bottom-6 left-1/2 -translate-x-1/2 z-30 flex items-center gap-1 px-2 py-1.5 bg-slate-900 dark:bg-slate-800 rounded-2xl shadow-2xl border border-white/10"
        @contextmenu.stop
      >
        <span class="pl-2 pr-3 text-sm font-medium text-slate-200 whitespace-nowrap">{{ selection.length }} selected</span>
        <button
          @click="movingSelection = true"
          class="cursor-pointer flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-slate-200 hover:text-white hover:bg-white/10 rounded-xl transition-colors"
        >
          <svg class="w-4 h-4 shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M7.5 21 3 16.5m0 0L7.5 12M3 16.5h13.5m0-13.5L21 7.5m0 0L16.5 12M21 7.5H7.5" />
          </svg>
          Move
        </button>
        <button
          @click="settingPasswordForSelection = true"
          class="cursor-pointer flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-slate-200 hover:text-white hover:bg-white/10 rounded-xl transition-colors"
        >
          <svg class="w-4 h-4 shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25z" />
          </svg>
          Password
        </button>
        <button
          @click="promptDeleteSelection"
          class="cursor-pointer flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-red-400 hover:text-red-300 hover:bg-white/10 rounded-xl transition-colors"
        >
          <svg class="w-4 h-4 shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0" />
          </svg>
          Delete
        </button>
        <div class="w-px h-5 bg-white/20 mx-1" />
        <button
          @click="clearSelection"
          title="Clear selection"
          class="cursor-pointer p-1.5 text-slate-400 hover:text-white hover:bg-white/10 rounded-xl transition-colors"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
    </Transition>

    <!-- Upload progress -->
    <UploadProgress :uploads="uploads" @dismiss="dismiss" />

    <!-- Modals -->
    <CreateFolderModal
      :show="showCreateFolder"
      @create="handleCreateFolder"
      @cancel="showCreateFolder = false"
    />
    <CreateFolderModal
      :show="!!renamingItem"
      :title="`Rename &quot;${renamingItem?.type === 'file' ? renamingItem?.item?.filename : renamingItem?.item?.name}&quot;`"
      :initial-value="renamingItem?.type === 'file' ? renamingItem?.item?.filename : renamingItem?.item?.name"
      confirm-label="Rename"
      @create="onRenameSubmit"
      @cancel="renamingItem = null"
    />
    <PasswordPromptModal
      :show="!!pendingAuth"
      :title="`&quot;${pendingAuth?.type === 'file' ? pendingAuth?.item?.filename : pendingAuth?.item?.name}&quot; is protected`"
      :error="pendingAuthError"
      @submit="onPendingAuth"
      @cancel="pendingAuth = null"
    />
    <ConfirmModal
      :show="!!confirmTarget"
      :title="confirmTarget?.bulk ? `Delete ${confirmTarget.count} items?` : `Delete ${confirmTarget?.type === 'file' ? 'file' : 'folder'}?`"
      :message="confirmTarget?.bulk
        ? `Permanently delete ${confirmTarget.count} selected items? This cannot be undone.`
        : (confirmTarget ? `Permanently delete &quot;${confirmTarget.name}&quot;? This cannot be undone.` : '')"
      confirm-label="Delete"
      @confirm="executeDelete"
      @cancel="confirmTarget = null"
    />
    <FilePreviewModal :file="previewFile" @close="previewFile = null" />
    <PasswordPromptModal
      :show="!!lockedFolderId"
      title="Folder is protected"
      :error="folderPwdError"
      @submit="onFolderUnlock"
      @cancel="cancelFolderUnlock"
    />
    <PasswordPromptModal
      :show="!!unlockingFile"
      :title="`&quot;${unlockingFile?.filename}&quot; is protected`"
      :error="filePwdError"
      @submit="onFileUnlock"
      @cancel="unlockingFile = null"
    />
    <MoveModal
      :show="!!movingItem"
      :item="movingItem ? { ...movingItem.item, type: movingItem.type } : null"
      :current-folder-id="currentFolderId"
      @move="handleMove"
      @cancel="movingItem = null"
    />
    <MoveModal
      :show="movingSelection"
      :item="{ name: `${selection.length} items`, type: 'selection' }"
      :current-folder-id="currentFolderId"
      @move="handleMoveSelection"
      @cancel="movingSelection = false"
    />
    <SetPasswordModal
      :show="!!settingPasswordFor"
      :name="settingPasswordFor?.item?.filename || settingPasswordFor?.item?.name || ''"
      :is-protected="!!settingPasswordFor?.item?.protected"
      @save="onSetPassword"
      @cancel="settingPasswordFor = null"
    />
    <SetPasswordModal
      :show="settingPasswordForSelection"
      :name="`${selection.length} items`"
      :is-protected="false"
      @save="onSetPasswordForSelection"
      @cancel="settingPasswordForSelection = false"
    />
    <ContextMenu :show="bgCtxOpen" :x="bgCtxX" :y="bgCtxY" :items="bgCtxItems" @close="bgCtxOpen = false" />
    <ContextMenu :show="selCtxOpen" :x="selCtxX" :y="selCtxY" :items="selCtxItems" @close="selCtxOpen = false" />
  </div>
</template>

<style scoped>
.fade-enter-active, .fade-leave-active { transition: opacity 0.15s ease; }
.fade-enter-from, .fade-leave-to { opacity: 0; }
</style>
