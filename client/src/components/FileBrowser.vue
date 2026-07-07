<script setup>
import { computed, ref } from 'vue'
import FolderCard from './FolderCard.vue'
import FileCard from './FileCard.vue'
import UploadZone from './UploadZone.vue'
import { useDnd } from '../composables/useDnd.js'
import { useI18n } from '@core/useI18n.js'

const { t } = useI18n()

const props = defineProps({
  folders: { type: Array, default: () => [] },
  files: { type: Array, default: () => [] },
  viewMode: { type: String, default: 'grid' },
  parentFolderId: { type: [String, null], default: undefined },
  uploadable: { type: Boolean, default: true },
  selection: { type: Array, default: () => [] },
  selectActive: { type: Boolean, default: false },
  highlightId: { type: String, default: null },
})

const emit = defineEmits(['open-folder', 'rename-folder', 'rename-folder-request', 'delete-folder', 'set-password-folder', 'move-folder', 'rename-file', 'rename-file-request', 'delete-file', 'preview-file', 'unlock-file', 'set-password-file', 'move-file', 'transcode-file', 'move-to', 'upload', 'toggle-select', 'open-selection-ctx'])

const selectionKeys = computed(() => new Set(props.selection.map(s => `${s.type}:${s.item._id}`)))
const selectionSize = computed(() => props.selection.length)
const isSelected = (type, id) => selectionKeys.value.has(`${type}:${id}`)

// Drag onto the ".." tile to move an item up to the parent folder.
const { dragging } = useDnd()
const upDropActive = ref(false)
function onUpDragOver(e) {
  if (!dragging.value) return
  e.preventDefault()
  e.dataTransfer.dropEffect = 'move'
  upDropActive.value = true
}
function onUpDrop(e) {
  upDropActive.value = false
  if (!dragging.value) return
  e.preventDefault()
  e.stopPropagation()
  emit('move-to', { type: dragging.value.type, id: dragging.value.id, targetId: props.parentFolderId ?? null })
}
</script>

<template>
  <div class="flex flex-col gap-8">
    <!-- Folders section -->
    <section v-if="folders.length || parentFolderId !== undefined">
      <h2 class="mb-3 text-xs font-semibold uppercase tracking-wider text-slate-400 dark:text-slate-500">{{ t('orbit.browser.folders') }}</h2>
      <!-- Grid -->
      <div
        v-if="viewMode === 'grid'"
        class="grid gap-2"
        style="grid-template-columns: repeat(auto-fill, minmax(120px, 1fr))"
      >
        <!-- .. up one level -->
        <div
          v-if="parentFolderId !== undefined"
          class="group flex flex-col items-center gap-2.5 p-4 rounded-2xl border transition-all cursor-pointer select-none"
          :class="upDropActive
            ? 'border-violet-400 dark:border-violet-500 ring-2 ring-violet-400 dark:ring-violet-500 bg-violet-50/70 dark:bg-violet-500/10'
            : 'border-transparent hover:border-slate-200 dark:hover:border-white/10 hover:bg-white/70 dark:hover:bg-white/6'"
          @click="$emit('open-folder', parentFolderId)"
          @dragover="onUpDragOver"
          @dragenter="onUpDragOver"
          @dragleave="upDropActive = false"
          @drop="onUpDrop"
          :title="t('orbit.browser.goUp')"
        >
          <div class="w-14 h-14 rounded-2xl bg-slate-200/60 dark:bg-white/8 flex items-center justify-center">
            <svg class="w-7 h-7 text-slate-400 dark:text-slate-500" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" d="M10.5 19.5 3 12m0 0 7.5-7.5M3 12h18" />
            </svg>
          </div>
          <span class="text-xs font-medium text-slate-400 dark:text-slate-500">..</span>
        </div>
        <FolderCard
          v-for="folder in folders"
          :key="folder._id"
          :folder="folder"
          view-mode="grid"
          :selected="isSelected('folder', folder._id)"
          :selection-size="selectionSize"
          :select-active="selectActive"
          @open="$emit('open-folder', $event)"
          @rename="(id, name) => $emit('rename-folder', id, name)"
          @rename-request="$emit('rename-folder-request', $event)"
          @delete="$emit('delete-folder', $event)"
          @set-password="$emit('set-password-folder', $event)"
          @move="$emit('move-folder', $event)"
          @move-to="$emit('move-to', $event)"
          @toggle-select="$emit('toggle-select', 'folder', folder)"
          @open-selection-ctx="(x, y) => $emit('open-selection-ctx', x, y)"
        />
      </div>
      <!-- List -->
      <div v-else class="flex flex-col">
        <!-- .. up one level -->
        <div
          v-if="parentFolderId !== undefined"
          class="flex items-center gap-3 px-4 py-2.5 rounded-xl transition-colors cursor-pointer select-none"
          :class="upDropActive
            ? 'ring-2 ring-violet-400 dark:ring-violet-500 bg-violet-50/70 dark:bg-violet-500/10'
            : 'hover:bg-white/60 dark:hover:bg-white/6'"
          @click="$emit('open-folder', parentFolderId)"
          @dragover="onUpDragOver"
          @dragenter="onUpDragOver"
          @dragleave="upDropActive = false"
          @drop="onUpDrop"
          :title="t('orbit.browser.goUp')"
        >
          <div class="w-8 h-8 rounded-lg bg-slate-200/60 dark:bg-white/8 flex items-center justify-center shrink-0">
            <svg class="w-4 h-4 text-slate-400 dark:text-slate-500" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" d="M10.5 19.5 3 12m0 0 7.5-7.5M3 12h18" />
            </svg>
          </div>
          <span class="text-sm font-medium text-slate-400 dark:text-slate-500">..</span>
        </div>
        <FolderCard
          v-for="folder in folders"
          :key="folder._id"
          :folder="folder"
          view-mode="list"
          :selected="isSelected('folder', folder._id)"
          :selection-size="selectionSize"
          :select-active="selectActive"
          @open="$emit('open-folder', $event)"
          @rename="(id, name) => $emit('rename-folder', id, name)"
          @rename-request="$emit('rename-folder-request', $event)"
          @delete="$emit('delete-folder', $event)"
          @set-password="$emit('set-password-folder', $event)"
          @move="$emit('move-folder', $event)"
          @move-to="$emit('move-to', $event)"
          @toggle-select="$emit('toggle-select', 'folder', folder)"
          @open-selection-ctx="(x, y) => $emit('open-selection-ctx', x, y)"
        />
      </div>
    </section>

    <!-- Files section -->
    <section v-if="files.length || uploadable">
      <h2 class="mb-3 text-xs font-semibold uppercase tracking-wider text-slate-400 dark:text-slate-500">{{ t('orbit.browser.files') }}</h2>

      <!-- Upload zone when no files -->
      <UploadZone
        v-if="!files.length && uploadable"
        @files="$emit('upload', $event)"
      />

      <template v-else-if="files.length">
        <!-- Grid -->
        <div
          v-if="viewMode === 'grid'"
          class="grid gap-3"
          style="grid-template-columns: repeat(auto-fill, minmax(140px, 1fr))"
        >
          <FileCard
            v-for="file in files"
            :key="file._id"
            :file="file"
            view-mode="grid"
            :selected="isSelected('file', file._id)"
            :selection-size="selectionSize"
            :select-active="selectActive"
            :highlight-id="highlightId"
            @rename="(id, name) => $emit('rename-file', id, name)"
            @rename-request="$emit('rename-file-request', $event)"
            @delete="$emit('delete-file', $event)"
            @preview="$emit('preview-file', $event)"
            @unlock="$emit('unlock-file', $event)"
            @set-password="$emit('set-password-file', $event)"
            @move="$emit('move-file', $event)"
            @transcode="$emit('transcode-file', $event)"
            @toggle-select="$emit('toggle-select', 'file', file)"
            @open-selection-ctx="(x, y) => $emit('open-selection-ctx', x, y)"
          />
        </div>
        <!-- List -->
        <div v-else class="flex flex-col">
          <!-- Header row -->
          <div class="flex items-center gap-3 px-4 py-2 text-xs font-medium text-slate-400 dark:text-slate-500 border-b border-slate-100 dark:border-white/8 mb-1">
            <div class="w-8 shrink-0" />
            <span class="flex-1">{{ t('orbit.browser.name') }}</span>
            <span class="hidden sm:block w-16 text-right">{{ t('orbit.browser.size') }}</span>
            <span class="hidden md:block w-20 text-right">{{ t('orbit.browser.modified') }}</span>
            <div class="w-8 shrink-0" />
          </div>
          <FileCard
            v-for="file in files"
            :key="file._id"
            :file="file"
            view-mode="list"
            :selected="isSelected('file', file._id)"
            :selection-size="selectionSize"
            :select-active="selectActive"
            :highlight-id="highlightId"
            @rename="(id, name) => $emit('rename-file', id, name)"
            @rename-request="$emit('rename-file-request', $event)"
            @delete="$emit('delete-file', $event)"
            @preview="$emit('preview-file', $event)"
            @unlock="$emit('unlock-file', $event)"
            @set-password="$emit('set-password-file', $event)"
            @move="$emit('move-file', $event)"
            @transcode="$emit('transcode-file', $event)"
            @toggle-select="$emit('toggle-select', 'file', file)"
            @open-selection-ctx="(x, y) => $emit('open-selection-ctx', x, y)"
          />
        </div>
      </template>
    </section>
  </div>
</template>
