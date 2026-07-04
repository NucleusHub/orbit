<script setup>
import { ref } from 'vue'
import { readDataTransferEntries } from '../utils/dropEntries.js'
import { useI18n } from '@core/useI18n.js'

const { t } = useI18n()
const emit = defineEmits(['files'])
const isDragging = ref(false)
const fileInput = ref(null)
const folderInput = ref(null)

function onDragover() { isDragging.value = true }
function onDragleave() { isDragging.value = false }
async function onDrop(e) {
  isDragging.value = false
  const entries = await readDataTransferEntries(e.dataTransfer)
  if (entries.length) emit('files', entries)
}
function onInput(e) {
  if (e.target.files.length) emit('files', e.target.files)
  e.target.value = ''
}
</script>

<template>
  <div
    data-upload-zone
    class="flex flex-col items-center justify-center gap-4 py-16 px-8 rounded-2xl border-2 border-dashed transition-colors"
    :class="isDragging
      ? 'border-indigo-500 bg-indigo-500/5 dark:bg-indigo-500/10'
      : 'border-slate-200 dark:border-white/10 hover:border-slate-300 dark:hover:border-white/20'"
    @dragover.prevent="onDragover"
    @dragleave="onDragleave"
    @drop.prevent="onDrop"
  >
    <div class="w-16 h-16 rounded-2xl bg-indigo-500/10 dark:bg-indigo-500/15 flex items-center justify-center">
      <svg class="w-8 h-8 text-indigo-500" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" d="M12 16.5V9.75m0 0 3 3m-3-3-3 3M6.75 19.5a4.5 4.5 0 0 1-1.41-8.775 5.25 5.25 0 0 1 10.233-2.33 3 3 0 0 1 3.758 3.848A3.752 3.752 0 0 1 18 19.5H6.75z" />
      </svg>
    </div>
    <div class="text-center">
      <p class="text-sm font-medium text-slate-700 dark:text-slate-300">{{ t('orbit.upload.dropHere') }}</p>
      <p class="mt-1 text-xs text-slate-400 dark:text-slate-500">{{ t('orbit.upload.orChooseBelow') }}</p>
    </div>
    <div class="flex items-center gap-2">
      <button
        @click="fileInput.click()"
        class="cursor-pointer px-5 py-2 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-500 rounded-xl transition-colors"
      >
        {{ t('orbit.upload.chooseFiles') }}
      </button>
      <button
        @click="folderInput.click()"
        class="cursor-pointer px-5 py-2 text-sm font-medium text-slate-700 dark:text-slate-300 bg-black/5 dark:bg-white/8 hover:bg-black/8 dark:hover:bg-white/12 rounded-xl transition-colors"
      >
        {{ t('orbit.upload.chooseFolder') }}
      </button>
    </div>
    <input ref="fileInput" type="file" multiple class="hidden" @change="onInput" />
    <input ref="folderInput" type="file" webkitdirectory multiple class="hidden" @change="onInput" />
  </div>
</template>
