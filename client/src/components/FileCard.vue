<script setup>
import { ref, computed, nextTick } from 'vue'
import { getFileTypeInfo, formatSize, formatRelativeDate } from '../utils/fileType.js'
import ContextMenu from './ContextMenu.vue'

const props = defineProps({
  file: { type: Object, required: true },
  viewMode: { type: String, default: 'grid' },
  selected: { type: Boolean, default: false },
  selectionSize: { type: Number, default: 0 },
})
const emit = defineEmits(['rename', 'delete', 'preview', 'unlock', 'set-password', 'move', 'rename-request', 'toggle-select', 'open-selection-ctx'])

const editing = ref(false)
const editName = ref('')
const editInput = ref(null)
const imgError = ref(false)

const ctxOpen = ref(false)
const ctxX = ref(0)
const ctxY = ref(0)

const typeInfo = computed(() => getFileTypeInfo(props.file.mimeType))
const isImage = computed(() => props.file.mimeType?.startsWith('image/'))
const showThumb = computed(() => isImage.value && !imgError.value && props.file.url)

const ICONS = {
  preview: 'M2.036 12.322a1.012 1.012 0 0 1 0-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178z M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0z',
  download: 'M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3',
  rename: 'm16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931zm0 0L19.5 7.125',
  delete: 'm14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0',
  lock: 'M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25z',
  move: 'M7.5 21 3 16.5m0 0L7.5 12M3 16.5h13.5m0-13.5L21 7.5m0 0L16.5 12M21 7.5H7.5',
}

const isLocked = computed(() => props.file.protected && !props.file.url)

const ctxItems = computed(() => [
  isLocked.value
    ? { label: 'Unlock', icon: ICONS.lock, action: () => emit('unlock', props.file) }
    : { label: 'Preview', icon: ICONS.preview, action: () => emit('preview', props.file) },
  ...(!isLocked.value ? [{ label: 'Download', icon: ICONS.download, href: props.file.url, download: props.file.filename }] : []),
  { divider: true },
  { label: 'Move', icon: ICONS.move, action: () => emit('move', props.file) },
  { label: 'Rename', icon: ICONS.rename, action: props.file.protected ? () => emit('rename-request', props.file) : startEdit },
  { label: props.file.protected ? 'Change password' : 'Set password', icon: ICONS.lock, action: () => emit('set-password', props.file) },
  { label: 'Delete', icon: ICONS.delete, action: () => emit('delete', props.file), danger: true },
])

function openCtx(e) {
  e.preventDefault()
  e.stopPropagation()
  if (props.selected && props.selectionSize > 1) {
    emit('open-selection-ctx', e.clientX, e.clientY)
    return
  }
  ctxX.value = e.clientX
  ctxY.value = e.clientY
  ctxOpen.value = true
}

function openCtxFromBtn(e) {
  const rect = e.currentTarget.getBoundingClientRect()
  ctxX.value = rect.left
  ctxY.value = rect.bottom + 4
  ctxOpen.value = true
}

function startEdit() {
  ctxOpen.value = false
  editing.value = true
  editName.value = props.file.filename
  nextTick(() => {
    editInput.value?.focus()
    editInput.value?.select()
  })
}

function commitEdit() {
  const name = editName.value.trim()
  if (name && name !== props.file.filename) emit('rename', props.file._id, name)
  editing.value = false
}

function cancelEdit() {
  editing.value = false
}
</script>

<template>
  <!-- List mode -->
  <div
    v-if="viewMode === 'list'"
    class="group flex items-center gap-3 px-4 py-2.5 rounded-xl transition-colors cursor-pointer"
    :class="selected ? 'bg-indigo-50/60 dark:bg-indigo-500/10' : 'hover:bg-white/60 dark:hover:bg-white/6'"
    @click="!editing && (isLocked ? $emit('unlock', file) : $emit('preview', file))"
    @contextmenu="openCtx"
  >
    <!-- Icon / Checkbox -->
    <div class="relative w-8 h-8 shrink-0" @click.stop="$emit('toggle-select')">
      <!-- Icon layer -->
      <div
        class="absolute inset-0 rounded-lg overflow-hidden flex items-center justify-center transition-opacity"
        :class="[
          isLocked ? 'bg-slate-100 dark:bg-white/8' : (!showThumb ? typeInfo.bg : ''),
          selectionSize > 0 ? 'opacity-0' : 'group-hover:opacity-0'
        ]"
      >
        <svg v-if="isLocked" class="w-4 h-4 text-slate-400 dark:text-slate-500" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25z" />
        </svg>
        <img v-else-if="showThumb" :src="file.url" :alt="file.filename" class="w-full h-full object-cover" @error="imgError = true" />
        <svg v-else class="w-4 h-4" :class="typeInfo.color" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" :d="typeInfo.icon" />
        </svg>
      </div>
      <!-- Checkbox layer -->
      <div
        class="absolute inset-0 flex items-center justify-center transition-opacity"
        :class="selectionSize > 0 || selected ? 'opacity-100' : 'opacity-0 group-hover:opacity-100'"
      >
        <div
          class="w-5 h-5 rounded-[4px] border-2 flex items-center justify-center transition-colors cursor-pointer"
          :class="selected ? 'bg-indigo-600 border-indigo-600' : 'bg-white/80 dark:bg-slate-800/80 border-slate-300 dark:border-white/30'"
        >
          <svg v-if="selected" class="w-3 h-3 text-white" fill="none" stroke="currentColor" stroke-width="3" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" d="m4.5 12.75 6 6 9-13.5" />
          </svg>
        </div>
      </div>
    </div>

    <!-- Name -->
    <input
      v-if="editing"
      ref="editInput"
      v-model="editName"
      class="flex-1 text-sm font-medium bg-white dark:bg-white/10 text-slate-900 dark:text-white border border-indigo-500 rounded px-2 py-0.5 focus:outline-none"
      @keydown.enter="commitEdit"
      @keydown.escape="cancelEdit"
      @blur="commitEdit"
      @click.stop
    />
    <span v-else class="flex-1 text-sm font-medium text-slate-900 dark:text-white truncate">{{ file.filename }}</span>

    <!-- Meta -->
    <span class="hidden sm:block text-xs text-slate-400 dark:text-slate-500 shrink-0 w-16 text-right">{{ formatSize(file.size) }}</span>
    <span class="hidden md:block text-xs text-slate-400 dark:text-slate-500 shrink-0 w-20 text-right">{{ formatRelativeDate(file.createdAt) }}</span>

    <!-- Actions -->
    <div class="shrink-0" @click.stop>
      <button
        @click="openCtxFromBtn"
        class="cursor-pointer p-1 rounded-lg text-slate-900 dark:text-white hover:bg-black/8 dark:hover:bg-white/10 transition-all sm:opacity-0 sm:group-hover:opacity-100"
      >
        <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
          <path d="M12 6.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5zM12 12.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5zM12 18.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5z" />
        </svg>
      </button>
    </div>
  </div>

  <!-- Grid mode -->
  <div
    v-else
    class="group relative flex flex-col rounded-2xl border transition-all cursor-pointer select-none"
    :class="selected
      ? 'border-indigo-300 dark:border-indigo-500/40 bg-indigo-50/50 dark:bg-indigo-500/10'
      : 'border-transparent hover:border-slate-200 dark:hover:border-white/10 hover:bg-white/70 dark:hover:bg-white/6'"
    @click="!editing && (isLocked ? $emit('unlock', file) : $emit('preview', file))"
    @contextmenu="openCtx"
  >
    <!-- Checkbox top-left -->
    <div
      class="absolute top-2 left-2 z-10 transition-opacity"
      :class="selectionSize > 0 || selected ? 'opacity-100' : 'opacity-0 group-hover:opacity-100'"
      @click.stop="$emit('toggle-select')"
    >
      <div
        class="w-5 h-5 rounded-[5px] border-2 flex items-center justify-center cursor-pointer transition-colors"
        :class="selected ? 'bg-indigo-600 border-indigo-600' : 'bg-white/80 dark:bg-slate-800/80 border-slate-300 dark:border-white/30'"
      >
        <svg v-if="selected" class="w-3 h-3 text-white" fill="none" stroke="currentColor" stroke-width="3" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="m4.5 12.75 6 6 9-13.5" />
        </svg>
      </div>
    </div>

    <!-- Thumbnail / icon area -->
    <div class="aspect-square w-full overflow-hidden flex items-center justify-center rounded-t-2xl" :class="isLocked ? 'bg-slate-100 dark:bg-white/6' : (!showThumb ? typeInfo.bg : '')">
      <svg v-if="isLocked" class="w-10 h-10 text-slate-300 dark:text-slate-600" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25z" />
      </svg>
      <img
        v-else-if="showThumb"
        :src="file.url"
        :alt="file.filename"
        class="w-full h-full object-cover"
        @error="imgError = true"
      />
      <svg v-else class="w-10 h-10" :class="typeInfo.color" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" :d="typeInfo.icon" />
      </svg>
    </div>

    <!-- Footer -->
    <div class="px-3 pt-2 pb-3 flex flex-col gap-0.5">
      <input
        v-if="editing"
        ref="editInput"
        v-model="editName"
        class="w-full text-xs font-medium bg-white dark:bg-white/10 text-slate-900 dark:text-white border border-indigo-500 rounded px-1.5 py-0.5 focus:outline-none"
        @keydown.enter="commitEdit"
        @keydown.escape="cancelEdit"
        @blur="commitEdit"
      />
      <span v-else class="text-xs font-medium text-slate-800 dark:text-slate-200 truncate">{{ file.filename }}</span>
      <span class="text-xs text-slate-400 dark:text-slate-500">{{ formatSize(file.size) }}</span>
    </div>

    <!-- Actions button top-right -->
    <div class="absolute top-2 right-2 transition-opacity sm:opacity-0 sm:group-hover:opacity-100" @click.stop>
      <button
        @click="openCtxFromBtn"
        class="cursor-pointer p-1 rounded-lg text-slate-900 dark:text-white hover:bg-black/8 dark:hover:bg-white/10 transition-colors"
      >
        <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 24 24">
          <path d="M12 6.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5zM12 12.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5zM12 18.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5z" />
        </svg>
      </button>
    </div>
  </div>

  <ContextMenu :show="ctxOpen" :x="ctxX" :y="ctxY" :items="ctxItems" @close="ctxOpen = false" />
</template>
