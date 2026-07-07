<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { useRoute } from 'vue-router'
import AppSidebar from '@core/AppSidebar.vue'
import AppHeader from '@core/AppHeader.vue'
import TemplateModal from '@core/TemplateModal.vue'
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
import SelectionToolbar from '@core/SelectionToolbar.vue'
import ContextMenu from '@core/ContextMenu.vue'
import SettingsModal from '../components/SettingsModal.vue'
import { useSettingsModal } from '@core/useSettingsModal.js'
import { useFiles } from '../composables/useFiles.js'
import { useUpload } from '../composables/useUpload.js'
import { useDnd } from '../composables/useDnd.js'
import { api } from '../api/orbit.js'
import { readDataTransferEntries } from '../utils/dropEntries.js'
import { useI18n } from '@core/useI18n.js'

const { t } = useI18n()
const { isDragging } = useDnd()
const { open: settingsOpen, openSettings, closeSettings } = useSettingsModal()

const sidebarOpen = ref(false)
const viewMode = ref(localStorage.getItem('orbit:viewMode') || 'grid')
watch(viewMode, v => localStorage.setItem('orbit:viewMode', v))
const search = ref('')
const dragOver = ref(false)
const showCreateFolder = ref(false)
const confirmTarget = ref(null) // { type, id, name } or { bulk: true, count, items }
const previewFile = ref(null)
const fileInput = ref(null)
const folderInput = ref(null)

// Multi-select. `selectMode` is an explicit, touch-friendly selection mode
// entered via the toolbar's Select button — it reveals the checkboxes and makes
// a tap on a card toggle it (rather than open it), without ever hiding previews.
const selection = ref([]) // [{ type: 'file'|'folder', item }]
const selectMode = ref(false)

function toggleSelectMode() {
  if (selectMode.value) clearSelection()
  else selectMode.value = true
}

function toggleSelect(type, item) {
  // Only selectable if the caller may act on it — the bulk toolbar's actions
  // (move / password / delete) are all owner-only, so shared items you don't own
  // (and locked group roots) can never enter the selection. Mirrors the per-item
  // menu, which hides those actions, and the server, which enforces canEdit.
  if (item?.canEdit === false) return
  const idx = selection.value.findIndex(s => s.type === type && s.item._id === item._id)
  if (idx === -1) selection.value = [...selection.value, { type, item }]
  else selection.value = selection.value.filter((_, i) => i !== idx)
}

function clearSelection() {
  selection.value = []
  selectMode.value = false
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
    { label: t('orbit.selection.moveItems', { count: n }), icon: ICONS_SEL.move, action: () => { movingSelection.value = true } },
    { label: t('orbit.selection.setPassword'), icon: ICONS_SEL.lock, action: () => { settingPasswordForSelection.value = true } },
    { divider: true },
    { label: t('orbit.selection.deleteItems', { count: n }), icon: ICONS_SEL.delete, action: promptDeleteSelection, danger: true },
  ]
})

// Actions for the shared @core/SelectionToolbar.
const selectionActions = computed(() => [
  { key: 'move', label: t('orbit.selection.move'), icon: ICONS_SEL.move },
  { key: 'password', label: t('orbit.selection.password'), icon: ICONS_SEL.lock },
  { key: 'delete', label: t('orbit.selection.delete'), icon: ICONS_SEL.delete, danger: true },
])
function onSelectionAction(key) {
  if (key === 'move') movingSelection.value = true
  else if (key === 'password') settingPasswordForSelection.value = true
  else if (key === 'delete') promptDeleteSelection()
}

// Overflow (⋮) menu — view mode + settings, kept out of the main toolbar so it
// stays uncluttered (only sidebar · search · select · new folder · upload show).
const TOOLBAR_ICONS = {
  grid: 'M3.75 6A2.25 2.25 0 0 1 6 3.75h2.25A2.25 2.25 0 0 1 10.5 6v2.25a2.25 2.25 0 0 1-2.25 2.25H6a2.25 2.25 0 0 1-2.25-2.25V6zM3.75 15.75A2.25 2.25 0 0 1 6 13.5h2.25a2.25 2.25 0 0 1 2.25 2.25V18a2.25 2.25 0 0 1-2.25 2.25H6A2.25 2.25 0 0 1 3.75 18v-2.25zM13.5 6a2.25 2.25 0 0 1 2.25-2.25H18A2.25 2.25 0 0 1 20.25 6v2.25A2.25 2.25 0 0 1 18 10.5h-2.25a2.25 2.25 0 0 1-2.25-2.25V6zM13.5 15.75a2.25 2.25 0 0 1 2.25-2.25H18a2.25 2.25 0 0 1 2.25 2.25V18A2.25 2.25 0 0 1 18 20.25h-2.25A2.25 2.25 0 0 1 13.5 18v-2.25z',
  list: 'M8.25 6.75h12M8.25 12h12m-12 5.25h12M3.75 6.75h.007v.008H3.75V6.75zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0zM3.75 12h.007v.008H3.75V12zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0zm-.375 5.25h.007v.008H3.75v-.008zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0z',
  settings: 'M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 0 1 1.37.49l1.296 2.247a1.125 1.125 0 0 1-.26 1.431l-1.003.827c-.293.241-.438.613-.43.992a7.723 7.723 0 0 1 0 .255c-.008.378.137.75.43.991l1.004.827c.424.35.534.955.26 1.431l-1.298 2.247a1.125 1.125 0 0 1-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.47 6.47 0 0 1-.22.128c-.331.183-.581.495-.644.869l-.213 1.281c-.09.543-.56.94-1.11.94h-2.594c-.55 0-1.019-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 0 1-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 0 1-1.369-.49l-1.297-2.247a1.125 1.125 0 0 1 .26-1.431l1.004-.827c.292-.24.437-.613.43-.991a6.932 6.932 0 0 1 0-.255c.007-.38-.138-.751-.43-.992l-1.004-.827a1.125 1.125 0 0 1-.26-1.43l1.297-2.248a1.125 1.125 0 0 1 1.37-.49l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.086.22-.128.332-.183.582-.495.644-.869l.214-1.28Z',
}
const overflowOpen = ref(false)
const overflowX = ref(0)
const overflowY = ref(0)
function openOverflow(e) {
  const r = e.currentTarget.getBoundingClientRect()
  overflowX.value = r.right
  overflowY.value = r.bottom + 4
  overflowOpen.value = true
}
const overflowItems = computed(() => [
  { label: t('orbit.toolbar.gridView'), icon: TOOLBAR_ICONS.grid, action: () => { viewMode.value = 'grid' } },
  { label: t('orbit.toolbar.listView'), icon: TOOLBAR_ICONS.list, action: () => { viewMode.value = 'list' } },
  { divider: true },
  { label: t('orbit.toolbar.settings'), icon: TOOLBAR_ICONS.settings, action: openSettings },
])

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
    label: t('orbit.menu.newFolder'),
    icon: 'M12 10.5v6m3-3H9m4.06-7.19-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44z',
    action: () => { showCreateFolder.value = true },
  },
  {
    label: t('orbit.menu.uploadFiles'),
    icon: 'M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5m-13.5-9L12 3m0 0 4.5 4.5M12 3v13.5',
    action: () => { fileInput.value?.click() },
  },
  {
    label: t('orbit.menu.uploadFolder'),
    icon: 'M3.75 9.776c.112-.017.227-.026.344-.026h15.812c.117 0 .232.009.344.026m-16.5 0a2.25 2.25 0 0 0-1.883 2.542l.857 6a2.25 2.25 0 0 0 2.227 1.932H19.05a2.25 2.25 0 0 0 2.227-1.932l.857-6a2.25 2.25 0 0 0-1.883-2.542m-16.5 0V6A2.25 2.25 0 0 1 6 3.75h3.879a1.5 1.5 0 0 1 1.06.44l2.122 2.12a1.5 1.5 0 0 0 1.06.44H18A2.25 2.25 0 0 1 20.25 9v.776',
    action: () => { folderInput.value?.click() },
  },
  { divider: true },
  {
    label: viewMode.value === 'grid' ? t('orbit.menu.listView') : t('orbit.menu.gridView'),
    icon: viewMode.value === 'grid'
      ? 'M8.25 6.75h12M8.25 12h12m-12 5.25h12M3.75 6.75h.007v.008H3.75V6.75zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0zM3.75 12h.007v.008H3.75V12zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0zm-.375 5.25h.007v.008H3.75v-.008zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0z'
      : 'M3.75 6A2.25 2.25 0 0 1 6 3.75h2.25A2.25 2.25 0 0 1 10.5 6v2.25a2.25 2.25 0 0 1-2.25 2.25H6a2.25 2.25 0 0 1-2.25-2.25V6zM3.75 15.75A2.25 2.25 0 0 1 6 13.5h2.25a2.25 2.25 0 0 1 2.25 2.25V18a2.25 2.25 0 0 1-2.25 2.25H6A2.25 2.25 0 0 1 3.75 18v-2.25zM13.5 6a2.25 2.25 0 0 1 2.25-2.25H18A2.25 2.25 0 0 1 20.25 6v2.25A2.25 2.25 0 0 1 18 10.5h-2.25a2.25 2.25 0 0 1-2.25-2.25V6zM13.5 15.75a2.25 2.25 0 0 1 2.25-2.25H18a2.25 2.25 0 0 1 2.25 2.25V18A2.25 2.25 0 0 1 18 20.25h-2.25A2.25 2.25 0 0 1 13.5 18v-2.25z',
    action: () => { viewMode.value = viewMode.value === 'grid' ? 'list' : 'grid' },
  },
  { divider: true },
  {
    label: t('orbit.menu.refresh'),
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
  browse, silentRefresh, unlockFolder, cancelFolderUnlock, unlockFileInList, updateItem,
  createFolder, renameFolder, deleteFolder, renameFile, deleteFile,
} = useFiles()

// Video conversion: kick off a background transcode, then let the poller below
// pick up the result. Works for any already-uploaded video — no re-upload.
async function onTranscode(file) {
  try {
    const updated = await api.transcodeFile(file._id)
    updateItem('file', { ...updated, url: file.url })
    if (previewFile.value?._id === file._id) {
      previewFile.value = { ...previewFile.value, transcodeStatus: updated.transcodeStatus }
    }
  } catch (e) {
    console.error('Convert failed:', e)
  }
}

// While any file is converting, quietly re-poll the listing so the "converting"
// indicator clears and the swapped-in MP4 (new url/filename) appears on its own.
const anyConverting = computed(() => files.value.some(f => f.transcodeStatus === 'pending' || f.transcodeStatus === 'processing'))
let transcodePoll = null
watch(anyConverting, (v) => {
  if (v && !transcodePoll) {
    transcodePoll = setInterval(() => silentRefresh(), 3000)
  } else if (!v && transcodePoll) {
    clearInterval(transcodePoll)
    transcodePoll = null
  }
})
onUnmounted(() => { if (transcodePoll) clearInterval(transcodePoll) })

// Keep an open preview in sync as its file changes underneath us (e.g. it just
// finished converting: new url/filename/status). Preserve the in-session URL for
// protected files, which don't carry a url in the listing.
watch(files, (list) => {
  if (!previewFile.value) return
  const fresh = list.find(f => f._id === previewFile.value._id)
  if (!fresh) return
  if (
    fresh.transcodeStatus !== previewFile.value.transcodeStatus ||
    fresh.transcodeProgress !== previewFile.value.transcodeProgress ||
    fresh.transcodeEta !== previewFile.value.transcodeEta ||
    fresh.url !== previewFile.value.url ||
    fresh.filename !== previewFile.value.filename
  ) {
    previewFile.value = { ...previewFile.value, ...fresh, url: fresh.url ?? previewFile.value.url }
  }
})

// Password prompt for locked folders
const folderPwdError = ref(null)
async function onFolderUnlock(password) {
  folderPwdError.value = null
  try {
    unlockFolder(lockedFolderId.value, password)
  } catch {
    folderPwdError.value = t('orbit.error.wrongPassword')
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
    filePwdError.value = t('orbit.error.wrongPassword')
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

// Drag & drop move: dropping a file/folder onto another folder (or the ".." tile)
// moves it there. The server adopts the destination's scope (personal ⇆ group).
async function handleDrop({ type, id, targetId }) {
  try {
    if (type === 'file') await api.moveFile(id, targetId)
    else await api.moveFolder(id, targetId)
  } catch (e) {
    console.error('Move failed:', e)
  } finally {
    browse(currentFolderId.value)
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
    pendingAuthError.value = e.status === 401 ? t('orbit.error.wrongPassword') : t('orbit.error.verificationFailed')
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

// Deep-link support (e.g. from the Orbit dashboard widget):
// /orbit/?folder=<id>&highlight=<fileId> opens that folder and flags the file
// so its card flashes + scrolls into view once the listing loads.
const route = useRoute()
const highlightId = ref(route.query.highlight ? String(route.query.highlight) : null)

onMounted(() => browse(route.query.folder ? String(route.query.folder) : null))

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
  highlightId.value = null // stop highlighting once the user navigates
  browse(folderId)
}

watch(search, () => { if (selection.value.length) clearSelection() })

function onDragover(e) {
  if (isDragging.value) return // internal item move, not an external file upload
  e.preventDefault()
  dragOver.value = true
}
function onDragleave(e) {
  if (!e.currentTarget.contains(e.relatedTarget)) dragOver.value = false
}
async function onDrop(e) {
  if (isDragging.value) return // handled by the folder / ".." drop targets
  e.preventDefault()
  dragOver.value = false
  if (e.target.closest('[data-upload-zone]')) return
  // Read the dropped entries synchronously (readDataTransferEntries grabs the
  // entry list before awaiting) so folders are recursed, not dropped as 0-byte
  // stubs the way dataTransfer.files would give them.
  const entries = await readDataTransferEntries(e.dataTransfer)
  if (entries.length) uploadFiles(entries, currentFolderId.value)
}

function handleFileInput(e) {
  if (e.target.files.length) uploadFiles(e.target.files, currentFolderId.value)
  e.target.value = ''
}

function handleFolderInput(e) {
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
    <input ref="folderInput" type="file" webkitdirectory multiple class="hidden" @change="handleFolderInput" />

    <!-- Header -->
    <AppHeader @contextmenu.stop>
      <template #left>
        <button
          @click="sidebarOpen = true"
          class="cursor-pointer p-2 -ml-1 rounded-xl text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-slate-200 hover:bg-black/5 dark:hover:bg-white/8 transition-colors"
          :aria-label="t('orbit.toolbar.openNav')"
        >
          <svg class="w-5 h-5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5" />
          </svg>
        </button>
      </template>
      <template #right>
        <!-- Search -->
        <SearchBar v-model="search" />

        <!-- View toggle (desktop; on phone it lives in the ⋮ menu) -->
        <div class="hidden sm:flex gap-0.5 bg-black/5 dark:bg-white/8 rounded-lg p-0.5">
          <button
            @click="viewMode = 'grid'"
            :class="['cursor-pointer p-1.5 rounded-md transition-colors', viewMode === 'grid' ? 'bg-white dark:bg-white/20 text-slate-900 dark:text-white shadow-sm' : 'text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-slate-300']"
            :title="t('orbit.toolbar.gridView')"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" :d="TOOLBAR_ICONS.grid" />
            </svg>
          </button>
          <button
            @click="viewMode = 'list'"
            :class="['cursor-pointer p-1.5 rounded-md transition-colors', viewMode === 'list' ? 'bg-white dark:bg-white/20 text-slate-900 dark:text-white shadow-sm' : 'text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-slate-300']"
            :title="t('orbit.toolbar.listView')"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" :d="TOOLBAR_ICONS.list" />
            </svg>
          </button>
        </div>

        <!-- New folder -->
        <button
          @click="showCreateFolder = true"
          class="cursor-pointer flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-slate-700 dark:text-slate-300 bg-black/5 dark:bg-white/8 hover:bg-black/8 dark:hover:bg-white/12 rounded-xl transition-colors"
        >
          <svg class="w-4 h-4 shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 10.5v6m3-3H9m4.06-7.19-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44z" />
          </svg>
          <span class="hidden sm:inline">{{ t('orbit.toolbar.newFolder') }}</span>
        </button>

        <!-- Upload -->
        <button
          @click="fileInput.click()"
          class="cursor-pointer flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-500 rounded-xl transition-colors"
        >
          <svg class="w-4 h-4 shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5m-13.5-9L12 3m0 0 4.5 4.5M12 3v13.5" />
          </svg>
          <span class="hidden sm:inline">{{ t('orbit.toolbar.upload') }}</span>
        </button>

        <!-- View mode (phone only; desktop shows the toggle inline) -->
        <button
          @click="openOverflow"
          class="sm:hidden cursor-pointer p-2 rounded-xl text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-slate-200 hover:bg-black/5 dark:hover:bg-white/8 transition-colors"
          :title="t('orbit.toolbar.more')"
          :aria-label="t('orbit.toolbar.more')"
        >
          <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
            <path d="M12 6.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5zM12 12.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5zM12 18.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5z" />
          </svg>
        </button>

        <!-- Settings — last in the header on desktop; on phone it's in the ⋮ menu -->
        <button
          @click="openSettings"
          class="hidden sm:inline-flex cursor-pointer p-2 rounded-xl text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-slate-200 hover:bg-black/5 dark:hover:bg-white/8 transition-colors"
          :title="t('orbit.toolbar.settings')"
          :aria-label="t('orbit.toolbar.settings')"
        >
          <svg class="w-5 h-5" fill="none" stroke="currentColor" stroke-width="1.8" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" :d="TOOLBAR_ICONS.settings" />
            <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z" />
          </svg>
        </button>
      </template>
    </AppHeader>

    <!-- Breadcrumbs (+ Select toggle, kept out of the crowded header) -->
    <Breadcrumbs :crumbs="breadcrumbs" @navigate="navigate" @contextmenu.stop>
      <template #actions>
        <button
          @click="toggleSelectMode"
          :class="['cursor-pointer flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-lg transition-colors',
            selectMode ? 'bg-indigo-600 text-white hover:bg-indigo-500' : 'text-slate-600 dark:text-slate-300 bg-black/5 dark:bg-white/8 hover:bg-black/8 dark:hover:bg-white/12']"
          :title="t('orbit.toolbar.select')"
        >
          <svg class="w-4 h-4 shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="M9 11l3 3L22 4" />
            <path stroke-linecap="round" stroke-linejoin="round" d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11" />
          </svg>
          <span>{{ selectMode ? t('orbit.selection.done') : t('orbit.toolbar.select') }}</span>
        </button>
      </template>
    </Breadcrumbs>

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
        <button @click="browse(currentFolderId)" class="cursor-pointer text-sm text-indigo-600 dark:text-indigo-400 hover:underline">{{ t('orbit.error.tryAgain') }}</button>
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
              {{ t('orbit.empty.orCreateFolder') }}
            </button>
          </div>
        </div>
      </div>

      <!-- Search empty state -->
      <div v-else-if="isEmpty && search" class="flex flex-col items-center justify-center py-20 gap-3 text-center">
        <svg class="w-12 h-12 text-slate-300 dark:text-slate-600" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="m21 21-5.197-5.197m0 0A7.5 7.5 0 1 0 5.196 5.196a7.5 7.5 0 0 0 10.607 10.607z" />
        </svg>
        <p class="text-sm text-slate-500 dark:text-slate-400">{{ t('orbit.search.noResultsFor') }} "<strong>{{ search }}</strong>"</p>
        <button @click="search = ''" class="cursor-pointer text-sm text-indigo-600 dark:text-indigo-400 hover:underline">{{ t('orbit.search.clear') }}</button>
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
        :select-active="selectMode"
        :highlight-id="highlightId"
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
        @transcode-file="f => withAuth('file', f, () => onTranscode(f))"
        @move-to="handleDrop"
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
          <p class="text-lg font-semibold text-indigo-600 dark:text-indigo-400">{{ t('orbit.upload.dropToUpload') }}</p>
        </div>
      </div>
    </Transition>

    <!-- Selection toolbar (shared @core component) -->
    <SelectionToolbar
      :show="selection.length > 0"
      :count="selection.length"
      :label="t('orbit.selection.count', { count: selection.length })"
      :actions="selectionActions"
      :clear-title="t('orbit.selection.clear')"
      @action="onSelectionAction"
      @clear="clearSelection"
    />

    <!-- Toolbar overflow (⋮): view mode + settings -->
    <ContextMenu :show="overflowOpen" :x="overflowX" :y="overflowY" :items="overflowItems" @close="overflowOpen = false" />

    <!-- Upload progress -->
    <UploadProgress :uploads="uploads" @dismiss="dismiss" />

    <!-- Modals -->
    <CreateFolderModal
      :show="showCreateFolder"
      :title="t('orbit.folder.newTitle')"
      :confirm-label="t('orbit.folder.create')"
      @create="handleCreateFolder"
      @cancel="showCreateFolder = false"
    />
    <CreateFolderModal
      :show="!!renamingItem"
      :title="t('orbit.rename.title', { name: renamingItem?.type === 'file' ? renamingItem?.item?.filename : renamingItem?.item?.name })"
      :initial-value="renamingItem?.type === 'file' ? renamingItem?.item?.filename : renamingItem?.item?.name"
      :confirm-label="t('orbit.action.rename')"
      @create="onRenameSubmit"
      @cancel="renamingItem = null"
    />
    <PasswordPromptModal
      :show="!!pendingAuth"
      :title="t('orbit.protected.itemTitle', { name: pendingAuth?.type === 'file' ? pendingAuth?.item?.filename : pendingAuth?.item?.name })"
      :error="pendingAuthError"
      @submit="onPendingAuth"
      @cancel="pendingAuth = null"
    />
    <TemplateModal
      :show="!!confirmTarget"
      :title="confirmTarget?.bulk ? t('orbit.delete.bulkTitle', { count: confirmTarget.count }) : (confirmTarget?.type === 'file' ? t('orbit.delete.fileTitle') : t('orbit.delete.folderTitle'))"
      :message="confirmTarget?.bulk
        ? t('orbit.delete.bulkMsg', { count: confirmTarget.count })
        : (confirmTarget ? t('orbit.delete.fileMsg', { name: confirmTarget.name }) : '')"
      :confirm-label="t('core.button.delete')"
      @confirm="executeDelete"
      @cancel="confirmTarget = null"
    />
    <FilePreviewModal :file="previewFile" @close="previewFile = null" @transcode="onTranscode" />
    <PasswordPromptModal
      :show="!!lockedFolderId"
      :title="t('orbit.protected.folderTitle')"
      :error="folderPwdError"
      @submit="onFolderUnlock"
      @cancel="cancelFolderUnlock"
    />
    <PasswordPromptModal
      :show="!!unlockingFile"
      :title="t('orbit.protected.itemTitle', { name: unlockingFile?.filename })"
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
    <SettingsModal :show="settingsOpen" @close="closeSettings" @queued="silentRefresh" />
    <ContextMenu :show="bgCtxOpen" :x="bgCtxX" :y="bgCtxY" :items="bgCtxItems" @close="bgCtxOpen = false" />
    <ContextMenu :show="selCtxOpen" :x="selCtxX" :y="selCtxY" :items="selCtxItems" @close="selCtxOpen = false" />
  </div>
</template>

<style scoped>
.fade-enter-active, .fade-leave-active { transition: opacity 0.15s ease; }
.fade-enter-from, .fade-leave-to { opacity: 0; }
</style>
