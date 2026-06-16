<script setup>
import { ref, inject } from 'vue'

// One row in the Orbit file tree. Folders expand/collapse and lazy-load their
// children via /api/orbit/folders/browse; files are clickable leaves that get
// shared. Recurses into itself for nested folders.
const props = defineProps({
  node: { type: Object, required: true }, // { type:'folder'|'file', id, name, mimeType, size, url }
  depth: { type: Number, default: 0 },
})

const pickFile = inject('pickFile')

const expanded = ref(false)
const loaded = ref(false)
const loading = ref(false)
const children = ref([])

const isImage = () => /^image\//.test(props.node.mimeType || '')

function prettySize(b) {
  b = Number(b || 0)
  if (!b) return ''
  const u = ['B', 'KB', 'MB', 'GB']
  let i = 0
  while (b >= 1024 && i < u.length - 1) { b /= 1024; i++ }
  return `${b.toFixed(b < 10 && i ? 1 : 0)} ${u[i]}`
}

async function toggle() {
  expanded.value = !expanded.value
  if (!expanded.value || loaded.value) return
  loading.value = true
  try {
    const res = await fetch(`/api/orbit/folders/browse?parentId=${props.node.id}`, { credentials: 'include' })
    if (res.ok) {
      const d = await res.json()
      children.value = [
        ...d.folders.map(f => ({ type: 'folder', id: f._id, name: f.name })),
        ...d.files.map(f => ({ type: 'file', id: f._id, name: f.filename, mimeType: f.mimeType, size: f.size, url: f.url })),
      ]
    }
  } catch { /* leave empty */ } finally {
    loading.value = false
    loaded.value = true
  }
}
</script>

<template>
  <!-- Folder -->
  <template v-if="node.type === 'folder'">
    <button
      class="cursor-pointer w-full flex items-center gap-2 py-1.5 pr-2 rounded-lg text-sm text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-white/6 transition-colors text-left"
      :style="{ paddingLeft: depth * 16 + 6 + 'px' }"
      @click="toggle"
    >
      <svg class="w-3 h-3 shrink-0 text-slate-400 transition-transform" :class="expanded ? 'rotate-90' : ''" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
      </svg>
      <svg class="w-4 h-4 shrink-0 text-indigo-400" fill="none" stroke="currentColor" stroke-width="1.6" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 12.75V12A2.25 2.25 0 0 1 4.5 9.75h15A2.25 2.25 0 0 1 21.75 12v.75m-8.69-6.44-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44z" />
      </svg>
      <span class="truncate">{{ node.name }}</span>
    </button>
    <template v-if="expanded">
      <div v-if="loading" class="py-1.5 text-xs text-slate-400 dark:text-slate-500" :style="{ paddingLeft: (depth + 1) * 16 + 22 + 'px' }">Loading…</div>
      <FileTreeNode v-for="c in children" :key="c.type + c.id" :node="c" :depth="depth + 1" />
      <p v-if="loaded && !loading && !children.length" class="py-1.5 text-xs text-slate-400 dark:text-slate-500" :style="{ paddingLeft: (depth + 1) * 16 + 22 + 'px' }">Empty</p>
    </template>
  </template>

  <!-- File -->
  <button
    v-else
    class="cursor-pointer w-full flex items-center gap-2 py-1.5 pr-2 rounded-lg text-sm text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-white/6 transition-colors text-left"
    :style="{ paddingLeft: depth * 16 + 24 + 'px' }"
    :title="node.name"
    @click="pickFile(node)"
  >
    <!-- image file -->
    <svg v-if="isImage()" class="w-4 h-4 shrink-0 text-emerald-400" fill="none" stroke="currentColor" stroke-width="1.6" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" d="m2.25 15.75 5.159-5.159a2.25 2.25 0 0 1 3.182 0l5.159 5.159m-1.5-1.5 1.409-1.409a2.25 2.25 0 0 1 3.182 0l2.909 2.909m-18 3.75h16.5a1.5 1.5 0 0 0 1.5-1.5V6a1.5 1.5 0 0 0-1.5-1.5H3.75A1.5 1.5 0 0 0 2.25 6v12a1.5 1.5 0 0 0 1.5 1.5Zm10.5-11.25h.008v.008h-.008V8.25Zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Z" />
    </svg>
    <!-- generic file -->
    <svg v-else class="w-4 h-4 shrink-0 text-slate-400 dark:text-slate-500" fill="none" stroke="currentColor" stroke-width="1.6" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9z" />
    </svg>
    <span class="truncate flex-1">{{ node.name }}</span>
    <span class="shrink-0 text-xs text-slate-400 dark:text-slate-500">{{ prettySize(node.size) }}</span>
  </button>
</template>
