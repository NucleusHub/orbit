<script setup>
import { ref, computed, nextTick } from 'vue'
import ContextMenu from './ContextMenu.vue'

const props = defineProps({
  folder: { type: Object, required: true },
  viewMode: { type: String, default: 'grid' },
})
const emit = defineEmits(['open', 'rename', 'delete', 'set-password', 'move'])

const editing = ref(false)
const editName = ref('')
const editInput = ref(null)

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

const ctxItems = computed(() => [
  { label: 'Open', icon: ICONS.open, action: () => emit('open', props.folder._id) },
  { divider: true },
  { label: 'Move', icon: ICONS.move, action: () => emit('move', props.folder) },
  { label: 'Rename', icon: ICONS.rename, action: startEdit },
  { label: props.folder.protected ? 'Change password' : 'Set password', icon: ICONS.lock, action: () => emit('set-password', props.folder) },
  { label: 'Delete', icon: ICONS.delete, action: () => emit('delete', props.folder), danger: true },
])

function openCtx(e) {
  e.preventDefault()
  e.stopPropagation()
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
    class="group flex items-center gap-3 px-4 py-2.5 rounded-xl hover:bg-white/60 dark:hover:bg-white/6 transition-colors cursor-pointer"
    @click="!editing && $emit('open', folder._id)"
    @contextmenu="openCtx"
  >
    <div class="relative w-8 h-8 rounded-lg bg-indigo-500/10 dark:bg-indigo-500/20 flex items-center justify-center shrink-0">
      <svg class="w-4 h-4 text-indigo-500" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 12.75V12A2.25 2.25 0 0 1 4.5 9.75h15A2.25 2.25 0 0 1 21.75 12v.75m-8.69-6.44-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44z" />
      </svg>
      <svg v-if="folder.protected" class="absolute -bottom-1 -right-1 w-3.5 h-3.5 text-amber-500 bg-white dark:bg-slate-900 rounded-full p-0.5" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25z" />
      </svg>
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
        <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
          <path d="M12 6.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5zM12 12.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5zM12 18.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5z" />
        </svg>
      </button>
    </div>
  </div>

  <!-- Grid mode -->
  <div
    v-else
    class="group relative flex flex-col items-center gap-2.5 p-4 rounded-2xl border border-transparent hover:border-slate-200 dark:hover:border-white/10 hover:bg-white/70 dark:hover:bg-white/6 transition-all cursor-pointer select-none"
    @click="!editing && $emit('open', folder._id)"
    @dblclick="!editing && $emit('open', folder._id)"
    @contextmenu="openCtx"
  >
    <!-- Actions -->
    <div class="absolute top-2.5 right-2.5 transition-opacity sm:opacity-0 sm:group-hover:opacity-100" @click.stop>
      <button
        @click="openCtxFromBtn"
        class="cursor-pointer p-1 rounded-lg text-slate-900 dark:text-white hover:bg-black/8 dark:hover:bg-white/10 transition-colors"
      >
        <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
          <path d="M12 6.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5zM12 12.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5zM12 18.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5z" />
        </svg>
      </button>
    </div>

    <!-- Folder icon -->
    <div class="relative w-14 h-14 rounded-2xl bg-indigo-500/10 dark:bg-indigo-500/20 flex items-center justify-center">
      <svg class="w-7 h-7 text-indigo-500" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 12.75V12A2.25 2.25 0 0 1 4.5 9.75h15A2.25 2.25 0 0 1 21.75 12v.75m-8.69-6.44-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44z" />
      </svg>
      <svg v-if="folder.protected" class="absolute -bottom-1 -right-1 w-4.5 h-4.5 text-amber-500 bg-white dark:bg-slate-900 rounded-full p-0.5" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25z" />
      </svg>
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
