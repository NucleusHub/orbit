<script setup>
import { ref, watch, provide, onUnmounted } from 'vue'
import TemplateModal from '@core/TemplateModal.vue'
import FileTreeNode from './FileTreeNode.vue'

// Orbit's own composer picker, contributed to Echo via integration.echo.js.
// Built on the core TemplateModal; the body is a full Orbit drive tree (folders
// lazy-load their children). Typing in the search box switches to flat results
// from /api/orbit/folders/search; clearing it returns to the tree. Emits
// `select` with the chosen file node — Echo turns it into the message to send.
const props = defineProps({
  show: { type: Boolean, default: false },
})
const emit = defineEmits(['select', 'close'])

const roots = ref([])
const results = ref([])
const loading = ref(false)
const search = ref('')

// Provided down the recursive tree so any file leaf can trigger the share.
provide('pickFile', file => emit('select', file))

const mapFile = f => ({ type: 'file', id: f._id, name: f.filename, mimeType: f.mimeType, size: f.size, url: f.url })

async function loadRoot() {
  loading.value = true
  try {
    const res = await fetch('/api/orbit/folders/browse', { credentials: 'include' })
    const d = res.ok ? await res.json() : { folders: [], files: [] }
    roots.value = [...d.folders.map(f => ({ type: 'folder', id: f._id, name: f.name })), ...d.files.map(mapFile)]
  } catch {
    roots.value = []
  } finally {
    loading.value = false
  }
}

let searchTimer = null
async function runSearch(q) {
  loading.value = true
  try {
    const res = await fetch(`/api/orbit/folders/search?q=${encodeURIComponent(q)}`, { credentials: 'include' })
    const d = res.ok ? await res.json() : { files: [] }
    results.value = (d.files || []).map(mapFile)
  } catch {
    results.value = []
  } finally {
    loading.value = false
  }
}

watch(search, q => {
  clearTimeout(searchTimer)
  const term = q.trim()
  if (!term) { results.value = []; loading.value = false; return }
  searchTimer = setTimeout(() => runSearch(term), 250)
})

// `immediate` so the tree loads even when the picker is mounted already-open
// (Echo renders it on demand with :show=true), not only on a false→true toggle.
watch(() => props.show, val => {
  if (val) { search.value = ''; results.value = []; loadRoot() }
}, { immediate: true })
onUnmounted(() => clearTimeout(searchTimer))
</script>

<template>
  <TemplateModal
    :show="show"
    title="Share a file"
    header
    searchable
    v-model:search="search"
    search-placeholder="Search files…"
    panel-class="max-w-md"
    body-class="px-2 pb-2 pt-1"
    @cancel="emit('close')"
  >
    <div v-if="loading" class="flex items-center justify-center py-12">
      <svg class="w-6 h-6 text-indigo-500 animate-spin" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z" />
      </svg>
    </div>

    <!-- Search results (flat) -->
    <template v-else-if="search.trim()">
      <FileTreeNode v-for="n in results" :key="n.id" :node="n" :depth="0" />
      <p v-if="!results.length" class="py-12 text-center text-sm text-slate-400 dark:text-slate-500">No matching files</p>
    </template>

    <!-- Full drive tree -->
    <template v-else>
      <FileTreeNode v-for="n in roots" :key="n.type + n.id" :node="n" :depth="0" />
      <p v-if="!roots.length" class="py-12 text-center text-sm text-slate-400 dark:text-slate-500">No files yet</p>
    </template>
  </TemplateModal>
</template>
