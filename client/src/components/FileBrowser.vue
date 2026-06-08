<script setup>
import FolderCard from './FolderCard.vue'
import FileCard from './FileCard.vue'

defineProps({
  folders: { type: Array, default: () => [] },
  files: { type: Array, default: () => [] },
  viewMode: { type: String, default: 'grid' },
})

defineEmits(['open-folder', 'rename-folder', 'delete-folder', 'rename-file', 'delete-file', 'preview-file'])
</script>

<template>
  <div class="flex flex-col gap-8">
    <!-- Folders section -->
    <section v-if="folders.length">
      <h2 class="mb-3 text-xs font-semibold uppercase tracking-wider text-slate-400 dark:text-slate-500">Folders</h2>
      <!-- Grid -->
      <div
        v-if="viewMode === 'grid'"
        class="grid gap-2"
        style="grid-template-columns: repeat(auto-fill, minmax(120px, 1fr))"
      >
        <FolderCard
          v-for="folder in folders"
          :key="folder._id"
          :folder="folder"
          view-mode="grid"
          @open="$emit('open-folder', $event)"
          @rename="(id, name) => $emit('rename-folder', id, name)"
          @delete="$emit('delete-folder', $event)"
        />
      </div>
      <!-- List -->
      <div v-else class="flex flex-col">
        <FolderCard
          v-for="folder in folders"
          :key="folder._id"
          :folder="folder"
          view-mode="list"
          @open="$emit('open-folder', $event)"
          @rename="(id, name) => $emit('rename-folder', id, name)"
          @delete="$emit('delete-folder', $event)"
        />
      </div>
    </section>

    <!-- Files section -->
    <section v-if="files.length">
      <h2 class="mb-3 text-xs font-semibold uppercase tracking-wider text-slate-400 dark:text-slate-500">Files</h2>
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
          @rename="(id, name) => $emit('rename-file', id, name)"
          @delete="$emit('delete-file', $event)"
          @preview="$emit('preview-file', $event)"
        />
      </div>
      <!-- List -->
      <div v-else class="flex flex-col">
        <!-- Header row -->
        <div class="flex items-center gap-3 px-4 py-2 text-xs font-medium text-slate-400 dark:text-slate-500 border-b border-slate-100 dark:border-white/8 mb-1">
          <div class="w-8 shrink-0" />
          <span class="flex-1">Name</span>
          <span class="hidden sm:block w-16 text-right">Size</span>
          <span class="hidden md:block w-20 text-right">Modified</span>
          <div class="w-8 shrink-0" />
        </div>
        <FileCard
          v-for="file in files"
          :key="file._id"
          :file="file"
          view-mode="list"
          @rename="(id, name) => $emit('rename-file', id, name)"
          @delete="$emit('delete-file', $event)"
          @preview="$emit('preview-file', $event)"
        />
      </div>
    </section>
  </div>
</template>
