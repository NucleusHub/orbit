<script setup>
import { ref, computed, nextTick } from 'vue'
import { getFileTypeInfo, formatSize, formatRelativeDate } from '../utils/fileType.js'

const props = defineProps({
  file: { type: Object, required: true },
  viewMode: { type: String, default: 'grid' },
})
const emit = defineEmits(['rename', 'delete', 'preview'])

const menuOpen = ref(false)
const editing = ref(false)
const editName = ref('')
const editInput = ref(null)
const imgError = ref(false)

const typeInfo = computed(() => getFileTypeInfo(props.file.mimeType))
const isImage = computed(() => props.file.mimeType?.startsWith('image/'))
const showThumb = computed(() => isImage.value && !imgError.value && props.file.url)

function startEdit() {
  menuOpen.value = false
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
    class="group flex items-center gap-3 px-4 py-2.5 rounded-xl hover:bg-white/60 dark:hover:bg-white/6 transition-colors cursor-pointer"
    @click="!editing && $emit('preview', file)"
  >
    <!-- Icon or thumb -->
    <div class="w-8 h-8 rounded-lg overflow-hidden shrink-0 flex items-center justify-center" :class="!showThumb ? typeInfo.bg : ''">
      <img v-if="showThumb" :src="file.url" :alt="file.filename" class="w-full h-full object-cover" @error="imgError = true" />
      <svg v-else class="w-4 h-4" :class="typeInfo.color" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" :d="typeInfo.icon" />
      </svg>
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
    <div class="relative shrink-0" @click.stop>
      <button
        @click="menuOpen = !menuOpen"
        class="cursor-pointer p-1 rounded-lg text-slate-900 dark:text-slate-400 hover:text-black dark:hover:text-slate-300 dark:hover:bg-white/10 transition-all sm:opacity-0 sm:group-hover:opacity-100"
      >
        <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
          <path d="M12 6.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5zM12 12.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5zM12 18.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5z" />
        </svg>
      </button>
      <div v-if="menuOpen" class="fixed inset-0 z-10" @click="menuOpen = false" />
      <div v-if="menuOpen" class="absolute right-0 top-full mt-1 z-20 w-40 bg-white dark:bg-slate-800 border border-slate-200 dark:border-white/10 rounded-xl shadow-lg shadow-black/10 overflow-hidden">
        <a :href="file.url" download :filename="file.filename" @click="menuOpen = false" class="flex items-center gap-2 px-3 py-2 text-sm text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-white/8 transition-colors">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3" /></svg>
          Download
        </a>
        <button @click="startEdit" class="cursor-pointer w-full flex items-center gap-2 px-3 py-2 text-sm text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-white/8 transition-colors">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931zm0 0L19.5 7.125" /></svg>
          Rename
        </button>
        <button @click="menuOpen = false; $emit('delete', file)" class="cursor-pointer w-full flex items-center gap-2 px-3 py-2 text-sm text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-500/10 transition-colors">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0" /></svg>
          Delete
        </button>
      </div>
    </div>
  </div>

  <!-- Grid mode -->
  <div
    v-else
    class="group relative flex flex-col rounded-2xl border border-transparent hover:border-slate-200 dark:hover:border-white/10 hover:bg-white/70 dark:hover:bg-white/6 transition-all cursor-pointer select-none"
    @click="!editing && $emit('preview', file)"
  >
    <!-- Thumbnail / icon area -->
    <div class="aspect-square w-full overflow-hidden flex items-center justify-center" :class="!showThumb ? `${typeInfo.bg} rounded-t-2xl` : ''">
      <img
        v-if="showThumb"
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

    <!-- Actions button -->
    <div class="absolute top-2 right-2 transition-opacity sm:opacity-0 sm:group-hover:opacity-100" @click.stop>
      <div v-if="menuOpen" class="fixed inset-0 z-10" @click.stop="menuOpen = false" />
      <button
        @click="menuOpen = !menuOpen"
        class="cursor-pointer p-1 rounded-lg bg-black/20 dark:bg-black/40 backdrop-blur-sm text-white hover:bg-black/30 dark:hover:bg-black/50 transition-colors"
      >
        <svg class="w-3.5 h-3.5" fill="currentColor" viewBox="0 0 24 24">
          <path d="M12 6.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5zM12 12.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5zM12 18.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5z" />
        </svg>
      </button>
      <div v-if="menuOpen" class="absolute right-0 top-full mt-1 z-20 w-40 bg-white dark:bg-slate-800 border border-slate-200 dark:border-white/10 rounded-xl shadow-lg shadow-black/10 overflow-hidden">
        <a :href="file.url" download :filename="file.filename" @click="menuOpen = false" class="flex items-center gap-2 px-3 py-2 text-sm text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-white/8 transition-colors">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3" /></svg>
          Download
        </a>
        <button @click="startEdit" class="cursor-pointer w-full flex items-center gap-2 px-3 py-2 text-sm text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-white/8 transition-colors">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931zm0 0L19.5 7.125" /></svg>
          Rename
        </button>
        <button @click="menuOpen = false; $emit('delete', file)" class="cursor-pointer w-full flex items-center gap-2 px-3 py-2 text-sm text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-500/10 transition-colors">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0" /></svg>
          Delete
        </button>
      </div>
    </div>
  </div>
</template>
