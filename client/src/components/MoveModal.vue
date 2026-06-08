<script setup>
import { ref, computed, watch, onUnmounted } from 'vue'
import { api } from '../api/orbit.js'

const props = defineProps({
  show: { type: Boolean, default: false },
  item: { type: Object, default: null }, // { _id, filename|name, type: 'file'|'folder' }
  currentFolderId: { type: String, default: null },
})
const emit = defineEmits(['move', 'cancel'])

const folders = ref([])
const selected = ref(undefined) // undefined = not yet chosen; null = root
const collapsed = ref(new Set())
const loading = ref(false)
const error = ref(null)

const itemName = computed(() => props.item?.filename || props.item?.name || '')

function onKeydown(e) { if (e.key === 'Escape') emit('cancel') }
watch(() => props.show, async (val) => {
  if (!val) {
    window.removeEventListener('keydown', onKeydown)
    return
  }
  window.addEventListener('keydown', onKeydown)
  selected.value = undefined
  collapsed.value = new Set()
  error.value = null
  loading.value = true
  try {
    folders.value = await api.getAllFolders()
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
})
onUnmounted(() => window.removeEventListener('keydown', onKeydown))

// Flat list with depth, excluding the moving folder and its descendants
const flatTree = computed(() => {
  const excludeId = props.item?.type === 'folder' ? String(props.item._id) : null
  const excluded = new Set()
  if (excludeId) {
    // Collect all descendants to exclude
    const collect = (id) => {
      excluded.add(id)
      folders.value.filter(f => String(f.parentId || null) === id).forEach(f => collect(String(f._id)))
    }
    collect(excludeId)
  }

  const result = []
  function walk(parentId, depth) {
    folders.value
      .filter(f => String(f.parentId || null) === String(parentId || null))
      .forEach(f => {
        const id = String(f._id)
        if (excluded.has(id)) return
        const hasChildren = folders.value.some(c => !excluded.has(String(c._id)) && String(c.parentId || null) === id)
        result.push({ ...f, depth, hasChildren, isCollapsed: collapsed.value.has(id) })
        if (!collapsed.value.has(id)) walk(f._id, depth + 1)
      })
  }
  walk(null, 0)
  return result
})

function toggle(id) {
  const s = new Set(collapsed.value)
  if (s.has(id)) s.delete(id)
  else s.add(id)
  collapsed.value = s
}

const isSameLocation = computed(() => {
  const sel = selected.value === undefined ? undefined : (selected.value === null ? null : String(selected.value))
  const cur = props.currentFolderId === null ? null : String(props.currentFolderId)
  return sel === cur || sel === undefined
})

function submit() {
  emit('move', selected.value === undefined ? null : selected.value)
}
</script>

<template>
  <Teleport to="body">
    <Transition name="modal-fade">
      <div v-if="show" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/20 backdrop-blur-xl" @click="$emit('cancel')" />
        <div class="relative bg-white/25 dark:bg-white/8 border border-white/50 dark:border-white/10 rounded-2xl shadow-2xl w-full max-w-sm flex flex-col overflow-hidden" style="max-height: 80vh">

          <!-- Header -->
          <div class="px-5 pt-5 pb-4 border-b border-white/30 dark:border-white/8 shrink-0">
            <h2 class="text-sm font-semibold text-slate-900 dark:text-white">Move</h2>
            <p class="text-xs text-slate-500 dark:text-slate-400 mt-0.5 truncate">"{{ itemName }}"</p>
          </div>

          <!-- Tree -->
          <div class="flex-1 overflow-y-auto py-2 min-h-0">
            <div v-if="loading" class="flex items-center justify-center py-10">
              <svg class="w-5 h-5 text-indigo-500 animate-spin" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 0 1 8-8V0C5.373 0 0 5.373 0 12h4z" />
              </svg>
            </div>

            <div v-else-if="error" class="px-5 py-4 text-sm text-red-500">Failed to load folders: {{ error }}</div>

            <template v-else>
              <!-- Root option -->
              <button
                class="w-full flex items-center gap-2 px-4 py-2 text-sm transition-colors cursor-pointer"
                :class="selected === null
                  ? 'bg-indigo-50 dark:bg-indigo-500/20 text-indigo-700 dark:text-indigo-300'
                  : 'text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-white/6'"
                @click="selected = null"
              >
                <svg class="w-4 h-4 shrink-0 text-slate-400 dark:text-slate-500" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" d="m2.25 12 8.954-8.955c.44-.439 1.152-.439 1.591 0L21.75 12M4.5 9.75v10.125c0 .621.504 1.125 1.125 1.125H9.75v-4.875c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125V21h4.125c.621 0 1.125-.504 1.125-1.125V9.75M8.25 21h8.25" />
                </svg>
                <span class="font-medium">Home</span>
                <span v-if="currentFolderId === null" class="ml-auto text-xs text-slate-400 dark:text-slate-500">current</span>
              </button>

              <!-- Folder rows -->
              <div
                v-for="folder in flatTree"
                :key="folder._id"
                class="flex items-center gap-1 pr-4 py-0.5"
                :style="{ paddingLeft: `${(folder.depth + 1) * 16 + 4}px` }"
              >
                <!-- Collapse toggle -->
                <button
                  v-if="folder.hasChildren"
                  class="cursor-pointer p-0.5 rounded text-slate-400 hover:text-slate-600 dark:hover:text-slate-300 shrink-0"
                  @click.stop="toggle(String(folder._id))"
                >
                  <svg class="w-3 h-3 transition-transform" :class="folder.isCollapsed ? '' : 'rotate-90'" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
                  </svg>
                </button>
                <span v-else class="w-4 shrink-0" />

                <!-- Folder row button -->
                <button
                  class="flex-1 flex items-center gap-2 px-2 py-1.5 rounded-lg text-sm transition-colors cursor-pointer text-left"
                  :class="String(selected) === String(folder._id)
                    ? 'bg-indigo-50 dark:bg-indigo-500/20 text-indigo-700 dark:text-indigo-300'
                    : 'text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-white/6'"
                  @click="selected = folder._id"
                >
                  <svg class="w-4 h-4 shrink-0 text-indigo-400" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 12.75V12A2.25 2.25 0 0 1 4.5 9.75h15A2.25 2.25 0 0 1 21.75 12v.75m-8.69-6.44-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44z" />
                  </svg>
                  <span class="truncate">{{ folder.name }}</span>
                  <span v-if="String(folder._id) === String(currentFolderId)" class="ml-auto text-xs text-slate-400 dark:text-slate-500 shrink-0">current</span>
                </button>
              </div>

              <p v-if="!flatTree.length && !loading" class="px-5 py-4 text-sm text-slate-400 dark:text-slate-500">No folders yet</p>
            </template>
          </div>

          <!-- Footer -->
          <div class="px-5 py-4 border-t border-white/30 dark:border-white/8 flex gap-2 justify-end shrink-0">
            <button
              @click="$emit('cancel')"
              class="cursor-pointer px-4 py-2 text-sm font-medium text-slate-600 dark:text-slate-300 hover:text-slate-900 dark:hover:text-white bg-slate-100 dark:bg-slate-700 hover:bg-slate-200 dark:hover:bg-slate-600 rounded-lg transition-colors"
            >Cancel</button>
            <button
              @click="submit"
              :disabled="isSameLocation"
              class="cursor-pointer px-4 py-2 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-500 disabled:opacity-40 disabled:cursor-not-allowed rounded-lg transition-colors"
            >Move here</button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.modal-fade-enter-active, .modal-fade-leave-active { transition: opacity 0.15s ease; }
.modal-fade-enter-from, .modal-fade-leave-to { opacity: 0; }
</style>
