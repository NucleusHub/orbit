<script setup>
import { ref, computed, watch, nextTick, onMounted } from 'vue'
import { getFileTypeInfo, formatSize, formatRelativeDate, formatEta, canConvertMedia } from '../utils/fileType.js'
import ContextMenu from '@core/ContextMenu.vue'
import { useDnd } from '../composables/useDnd.js'
import { useI18n } from '@core/useI18n.js'

const { t } = useI18n()

const props = defineProps({
  file: { type: Object, required: true },
  viewMode: { type: String, default: 'grid' },
  selected: { type: Boolean, default: false },
  selectionSize: { type: Number, default: 0 },
  selectActive: { type: Boolean, default: false },
  highlightId: { type: String, default: null },
})

// Deep-link highlight: when this card is the targeted file, flash it and
// scroll it into view once mounted (see FilesView's ?highlight= handling).
const rootEl = ref(null)
const isHighlighted = computed(() => props.highlightId && props.file._id === props.highlightId)
onMounted(() => {
  if (isHighlighted.value) {
    nextTick(() => rootEl.value?.scrollIntoView({ behavior: 'smooth', block: 'center' }))
  }
})
const emit = defineEmits(['rename', 'delete', 'preview', 'unlock', 'set-password', 'move', 'rename-request', 'transcode', 'toggle-select', 'open-selection-ctx'])

// Only owner-editable files can be multi-selected (bulk actions are owner-only).
const canSelect = computed(() => props.file.canEdit !== false)

// A tap opens/previews normally, but toggles selection while in select mode.
function onOpen() {
  if (editing.value) return
  if (props.selectActive && canSelect.value) { emit('toggle-select'); return }
  isLocked.value ? emit('unlock', props.file) : emit('preview', props.file)
}

const editing = ref(false)
const editName = ref('')
const editInput = ref(null)
const imgError = ref(false)
// The card instance is reused across refreshes (keyed by _id), so clear a prior
// load failure when the URL changes — e.g. a HEIC that just became a JPEG.
watch(() => props.file.url, () => { imgError.value = false })

const { startDrag, endDrag } = useDnd()
function onDragStart(e) {
  startDrag({ type: 'file', id: props.file._id, name: props.file.filename }, e)
}

const ctxOpen = ref(false)
const ctxX = ref(0)
const ctxY = ref(0)

const typeInfo = computed(() => getFileTypeInfo(props.file.mimeType))
const isImage = computed(() => props.file.mimeType?.startsWith('image/'))
const showThumb = computed(() => isImage.value && !imgError.value && props.file.url)

// Background media normalisation (see server transcodeQueue.js).
const converting = computed(() => ['pending', 'processing'].includes(props.file.transcodeStatus))
// Offer manual conversion for videos / unsupported images not already done.
const canConvert = computed(() => canConvertMedia(props.file))
// "Queued" / "42% · 30s" / "Converting" depending on what the server reports.
const badgeText = computed(() => {
  if (props.file.transcodeStatus === 'pending') return t('orbit.transcode.queued')
  const p = props.file.transcodeProgress
  const base = (p == null) ? t('orbit.transcode.badge') : `${p}%`
  const eta = formatEta(props.file.transcodeEta)
  return eta ? `${base} · ${eta}` : base
})

const ICONS = {
  preview: 'M2.036 12.322a1.012 1.012 0 0 1 0-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178z M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0z',
  download: 'M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3',
  rename: 'm16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931zm0 0L19.5 7.125',
  delete: 'm14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0',
  lock: 'M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25z',
  move: 'M7.5 21 3 16.5m0 0L7.5 12M3 16.5h13.5m0-13.5L21 7.5m0 0L16.5 12M21 7.5H7.5',
  convert: 'M15.75 15.75V18m-7.5-6.75h.008v.008H8.25v-.008zM12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zm-1.5-12.75 3 3m0 0-3 3m3-3H8.25',
}

const isLocked = computed(() => props.file.protected && !props.file.url)

// In a shared group folder only the file's owner may modify it; the server
// reports this via `canEdit`. Everyone keeps preview/download.
const ctxItems = computed(() => {
  const items = [
    isLocked.value
      ? { label: t('orbit.action.unlock'), icon: ICONS.lock, action: () => emit('unlock', props.file) }
      : { label: t('orbit.action.preview'), icon: ICONS.preview, action: () => emit('preview', props.file) },
    ...(!isLocked.value ? [{ label: t('orbit.action.download'), icon: ICONS.download, href: props.file.url, download: props.file.filename }] : []),
  ]
  if (props.file.canEdit !== false) {
    items.push(
      { divider: true },
      { label: t('orbit.action.move'), icon: ICONS.move, action: () => emit('move', props.file) },
      { label: t('orbit.action.rename'), icon: ICONS.rename, action: props.file.protected ? () => emit('rename-request', props.file) : startEdit },
      { label: props.file.protected ? t('orbit.action.changePassword') : t('orbit.action.setPassword'), icon: ICONS.lock, action: () => emit('set-password', props.file) },
    )
    if (canConvert.value) {
      items.push({ label: t('orbit.action.convert'), icon: ICONS.convert, action: () => emit('transcode', props.file) })
    }
    items.push({ label: t('orbit.action.delete'), iconTrash: true, action: () => emit('delete', props.file), danger: true })
  }
  return items
})

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
    ref="rootEl"
    :draggable="!editing"
    class="group flex items-center gap-3 px-4 py-2.5 rounded-xl transition-colors cursor-pointer"
    :class="[selected ? 'bg-indigo-50/60 dark:bg-indigo-500/10' : 'hover:bg-white/60 dark:hover:bg-white/6', isHighlighted && 'orbit-highlight']"
    @click="onOpen"
    @contextmenu="openCtx"
    @dragstart="onDragStart"
    @dragend="endDrag"
  >
    <!-- Icon / Checkbox -->
    <div class="relative w-8 h-8 shrink-0" @click.stop="canSelect && $emit('toggle-select')">
      <!-- Icon layer -->
      <div
        class="absolute inset-0 rounded-lg overflow-hidden flex items-center justify-center transition-opacity"
        :class="[
          isLocked ? 'bg-slate-100 dark:bg-white/8' : (!showThumb ? typeInfo.bg : ''),
          canSelect ? ((selectActive || selectionSize > 0) ? 'opacity-0' : 'group-hover:opacity-0') : ''
        ]"
      >
        <svg v-if="isLocked" class="w-4 h-4 text-slate-400 dark:text-slate-500" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25z" />
        </svg>
        <img v-else-if="showThumb" :src="file.url" :alt="file.filename" draggable="false" class="w-full h-full object-cover" @error="imgError = true" />
        <svg v-else class="w-4 h-4" :class="typeInfo.color" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" :d="typeInfo.icon" />
        </svg>
      </div>
      <!-- Checkbox layer -->
      <div
        v-if="canSelect"
        class="absolute inset-0 flex items-center justify-center transition-opacity"
        :class="selectActive || selectionSize > 0 || selected ? 'opacity-100' : 'opacity-0 group-hover:opacity-100'"
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

    <!-- Converting indicator -->
    <span v-if="converting" class="flex items-center gap-1 shrink-0 text-[11px] font-medium text-indigo-500 dark:text-indigo-400" :title="t('orbit.transcode.tooltip')">
      <svg class="w-3 h-3 animate-spin" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 0 1 8-8V0C5.373 0 0 5.373 0 12h4z" />
      </svg>
      <span class="hidden sm:inline">{{ badgeText }}</span>
    </span>

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
    ref="rootEl"
    :draggable="!editing"
    class="group relative flex flex-col rounded-2xl border transition-all cursor-pointer select-none"
    :class="[selected
      ? 'border-indigo-300 dark:border-indigo-500/40 bg-indigo-50/50 dark:bg-indigo-500/10'
      : 'border-transparent hover:border-slate-200 dark:hover:border-white/10 hover:bg-white/70 dark:hover:bg-white/6', isHighlighted && 'orbit-highlight']"
    @click="onOpen"
    @contextmenu="openCtx"
    @dragstart="onDragStart"
    @dragend="endDrag"
  >
    <!-- Checkbox top-left. Shown in select mode / when selecting, else on hover. -->
    <div
      v-if="canSelect"
      class="absolute top-2 left-2 z-10 transition-opacity"
      :class="selectActive || selectionSize > 0 || selected ? 'opacity-100' : 'opacity-0 group-hover:opacity-100'"
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
    <div class="relative aspect-square w-full overflow-hidden flex items-center justify-center rounded-t-2xl" :class="isLocked ? 'bg-slate-100 dark:bg-white/6' : (!showThumb ? typeInfo.bg : '')">
      <svg v-if="isLocked" class="w-10 h-10 text-slate-300 dark:text-slate-600" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25z" />
      </svg>
      <img
        v-else-if="showThumb"
        :src="file.url"
        :alt="file.filename"
        draggable="false"
        class="w-full h-full object-cover"
        @error="imgError = true"
      />
      <svg v-else class="w-10 h-10" :class="typeInfo.color" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" :d="typeInfo.icon" />
      </svg>

      <!-- Converting badge -->
      <div v-if="converting" class="absolute bottom-1.5 left-1.5 right-1.5 flex items-center gap-1.5 px-1.5 py-1 rounded-lg bg-black/65 text-white text-[10px] font-medium backdrop-blur-sm" :title="t('orbit.transcode.tooltip')">
        <svg class="w-3 h-3 animate-spin shrink-0" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 0 1 8-8V0C5.373 0 0 5.373 0 12h4z" />
        </svg>
        <span class="truncate">{{ badgeText }}</span>
      </div>
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

<style scoped>
/* Deep-link highlight: a one-shot indigo ring + tint that fades out. */
.orbit-highlight {
  animation: orbit-hl 2.6s ease-out 1;
}
@keyframes orbit-hl {
  0%, 35% {
    box-shadow: 0 0 0 2px rgba(99, 102, 241, 0.9), 0 0 0 7px rgba(99, 102, 241, 0.22);
    background-color: rgba(99, 102, 241, 0.12);
  }
  100% {
    box-shadow: 0 0 0 0 rgba(99, 102, 241, 0);
    background-color: transparent;
  }
}
</style>
