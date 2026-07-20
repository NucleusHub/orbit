<script setup>
import { ref, computed, nextTick } from 'vue'
import ContextMenu from '@core/ContextMenu.vue'
import { useDnd } from '../composables/useDnd.js'
import { useI18n } from '@core/useI18n.js'
import { Icon } from '@core/icons'

const { t } = useI18n()

const props = defineProps({
  folder: { type: Object, required: true },
  viewMode: { type: String, default: 'grid' },
  selected: { type: Boolean, default: false },
  selectionSize: { type: Number, default: 0 },
  selectActive: { type: Boolean, default: false },
})
const emit = defineEmits(['open', 'rename', 'delete', 'set-password', 'move', 'move-to', 'rename-request', 'toggle-select', 'open-selection-ctx'])

// Only owner-editable folders can be multi-selected — locked group roots and
// others' shared folders can't (their bulk actions are owner-only anyway).
const canSelect = computed(() => props.folder.canEdit !== false)

// A tap opens the folder normally, but toggles selection while in select mode.
function onOpen() {
  if (editing.value) return
  if (props.selectActive && canSelect.value) { emit('toggle-select'); return }
  emit('open', props.folder._id)
}

const editing = ref(false)
const editName = ref('')
const editInput = ref(null)

// ── Drag & drop ───────────────────────────────────────────────────────────────
// A folder can be dragged (unless it's an immutable group root) and is always a
// drop target — drop a file/folder onto it to move the item inside.
const { dragging, startDrag, endDrag } = useDnd()
const dropActive = ref(false)
const canDrag = computed(() => props.folder.canEdit !== false && !props.folder.isGroupRoot)
const isValidDrop = computed(() => {
  const d = dragging.value
  if (!d) return false
  return !(d.type === 'folder' && d.id === props.folder._id) // not onto itself
})
function onDragStart(e) {
  if (!canDrag.value) { e.preventDefault(); return }
  startDrag({ type: 'folder', id: props.folder._id, name: props.folder.name }, e)
}
function onDragOver(e) {
  if (!isValidDrop.value) return
  e.preventDefault()
  e.dataTransfer.dropEffect = 'move'
  dropActive.value = true
}
function onDrop(e) {
  dropActive.value = false
  if (!isValidDrop.value) return
  e.preventDefault()
  e.stopPropagation()
  emit('move-to', { type: dragging.value.type, id: dragging.value.id, targetId: props.folder._id })
  endDrag()
}

const ctxOpen = ref(false)
const ctxX = ref(0)
const ctxY = ref(0)

const ICONS = {
  open: 'M2.25 12.75V12A2.25 2.25 0 0 1 4.5 9.75h15A2.25 2.25 0 0 1 21.75 12v.75m-8.69-6.44-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44z',
  rename: 'm16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931zm0 0L19.5 7.125',
  delete: 'm14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0',
  lock: 'M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25z',
  move: 'M7.5 21 3 16.5m0 0L7.5 12M3 16.5h13.5m0-13.5L21 7.5m0 0L16.5 12M21 7.5H7.5',
}

// Group roots are immutable and shared items are owner-only, so the server
// flags what the caller may change via `canEdit`. Show only Open otherwise.
const ctxItems = computed(() => {
  const items = [{ label: t('orbit.action.open'), icon: ICONS.open, action: () => emit('open', props.folder._id) }]
  if (props.folder.canEdit !== false) {
    items.push(
      { divider: true },
      { label: t('orbit.action.move'), icon: ICONS.move, action: () => emit('move', props.folder) },
      { label: t('orbit.action.rename'), icon: ICONS.rename, action: props.folder.protected ? () => emit('rename-request', props.folder) : startEdit },
      { label: props.folder.protected ? t('orbit.action.changePassword') : t('orbit.action.setPassword'), icon: ICONS.lock, action: () => emit('set-password', props.folder) },
      { label: t('orbit.action.delete'), iconTrash: true, action: () => emit('delete', props.folder), danger: true },
    )
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
  editName.value = props.folder.name
  nextTick(() => {
    editInput.value?.focus()
    editInput.value?.select()
  })
}

function commitEdit() {
  const name = editName.value.trim()
  if (name && name !== props.folder.name) emit('rename', props.folder._id, name)
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
    :draggable="canDrag && !editing"
    class="group flex items-center gap-3 px-4 py-2.5 rounded-xl transition-colors cursor-pointer"
    :class="[
      selected ? 'bg-indigo-50/60 dark:bg-indigo-500/10' : 'hover:bg-white/60 dark:hover:bg-white/6',
      dropActive && 'ring-2 ring-violet-400 dark:ring-violet-500 bg-violet-50/70 dark:bg-violet-500/10',
    ]"
    @click="onOpen"
    @contextmenu="openCtx"
    @dragstart="onDragStart"
    @dragend="endDrag"
    @dragover="onDragOver"
    @dragenter="onDragOver"
    @dragleave="dropActive = false"
    @drop="onDrop"
  >
    <!-- Icon / Checkbox -->
    <div class="relative w-8 h-8 shrink-0" @click.stop="canSelect && $emit('toggle-select')">
      <!-- Icon layer -->
      <div
        class="absolute inset-0 rounded-lg flex items-center justify-center transition-opacity"
        :class="[canSelect ? ((selectActive || selectionSize > 0) ? 'opacity-0' : 'group-hover:opacity-0') : '', folder.shared ? 'bg-violet-500/10 dark:bg-violet-500/20' : 'bg-indigo-500/10 dark:bg-indigo-500/20']"
      >
        <Icon name="folder" class="w-4 h-4" :class="folder.shared ? 'text-violet-500' : 'text-indigo-500'" />
        <Icon name="users" v-if="folder.shared" class="absolute -bottom-1 -left-1 w-3.5 h-3.5 text-violet-600 dark:text-violet-300 bg-white dark:bg-slate-900 rounded-full p-0.5" fill />
        <Icon name="lock" v-if="folder.protected" class="absolute -bottom-1 -right-1 w-3.5 h-3.5 text-amber-500 bg-white dark:bg-slate-900 rounded-full p-0.5" :sw="2.5" />
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
          <Icon name="check" v-if="selected" class="w-3 h-3 text-white" :sw="3" />
        </div>
      </div>
    </div>

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
    <span v-else class="flex-1 text-sm font-medium text-slate-900 dark:text-white truncate">{{ folder.name }}</span>
    <div class="shrink-0" @click.stop>
      <button
        @click="openCtxFromBtn"
        class="cursor-pointer p-1 rounded-lg text-slate-900 dark:text-white hover:bg-black/8 dark:hover:bg-white/10 transition-all sm:opacity-0 sm:group-hover:opacity-100"
      >
        <Icon name="kebab" class="w-4 h-4" />
      </button>
    </div>
  </div>

  <!-- Grid mode -->
  <div
    v-else
    :draggable="canDrag && !editing"
    class="group relative flex flex-col items-center gap-2.5 p-4 rounded-2xl border transition-all cursor-pointer select-none"
    :class="dropActive
      ? 'border-violet-400 dark:border-violet-500 ring-2 ring-violet-400 dark:ring-violet-500 bg-violet-50/70 dark:bg-violet-500/10'
      : (selected
        ? 'border-indigo-300 dark:border-indigo-500/40 bg-indigo-50/50 dark:bg-indigo-500/10'
        : 'border-transparent hover:border-slate-200 dark:hover:border-white/10 hover:bg-white/70 dark:hover:bg-white/6')"
    @click="onOpen"
    @dblclick="!editing && $emit('open', folder._id)"
    @contextmenu="openCtx"
    @dragstart="onDragStart"
    @dragend="endDrag"
    @dragover="onDragOver"
    @dragenter="onDragOver"
    @dragleave="dropActive = false"
    @drop="onDrop"
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
        <Icon name="check" v-if="selected" class="w-3 h-3 text-white" :sw="3" />
      </div>
    </div>

    <!-- Actions -->
    <div class="absolute top-2.5 right-2.5 transition-opacity sm:opacity-0 sm:group-hover:opacity-100" @click.stop>
      <button
        @click="openCtxFromBtn"
        class="cursor-pointer p-1 rounded-lg text-slate-900 dark:text-white hover:bg-black/8 dark:hover:bg-white/10 transition-colors"
      >
        <Icon name="kebab" class="w-4 h-4" />
      </button>
    </div>

    <!-- Folder icon (shared group folders are tinted violet + carry a group badge) -->
    <div class="relative w-14 h-14 rounded-2xl flex items-center justify-center" :class="folder.shared ? 'bg-violet-500/10 dark:bg-violet-500/20' : 'bg-indigo-500/10 dark:bg-indigo-500/20'">
      <Icon name="folder" class="w-7 h-7" :class="folder.shared ? 'text-violet-500' : 'text-indigo-500'" :sw="1.5" />
      <Icon name="users" v-if="folder.shared" class="absolute -bottom-1 -left-1 w-4.5 h-4.5 text-violet-600 dark:text-violet-300 bg-white dark:bg-slate-900 rounded-full p-0.5" fill />
      <Icon name="lock" v-if="folder.protected" class="absolute -bottom-1 -right-1 w-4.5 h-4.5 text-amber-500 bg-white dark:bg-slate-900 rounded-full p-0.5" :sw="2.5" />
    </div>

    <!-- Name -->
    <input
      v-if="editing"
      ref="editInput"
      v-model="editName"
      class="w-full text-center text-xs font-medium bg-white dark:bg-white/10 text-slate-900 dark:text-white border border-indigo-500 rounded px-2 py-0.5 focus:outline-none"
      @keydown.enter="commitEdit"
      @keydown.escape="cancelEdit"
      @blur="commitEdit"
      @click.stop
    />
    <span v-else class="text-xs font-medium text-slate-700 dark:text-slate-300 text-center leading-tight line-clamp-2 px-1">{{ folder.name }}</span>
  </div>

  <ContextMenu :show="ctxOpen" :x="ctxX" :y="ctxY" :items="ctxItems" @close="ctxOpen = false" />
</template>
