<script setup>
import { ref, inject } from 'vue'
import { Icon } from '@core/icons'

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
      <Icon name="chevronRight" class="w-3 h-3 shrink-0 text-slate-400 transition-transform" :class="expanded ? 'rotate-90' : ''" :sw="2.5" />
      <Icon name="folder" class="w-4 h-4 shrink-0 text-indigo-400" :sw="1.6" />
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
    <Icon name="image" v-if="isImage()" class="w-4 h-4 shrink-0 text-emerald-400" :sw="1.6" />
    <!-- generic file -->
    <Icon name="document" v-else class="w-4 h-4 shrink-0 text-slate-400 dark:text-slate-500" :sw="1.6" />
    <span class="truncate flex-1">{{ node.name }}</span>
    <span class="shrink-0 text-xs text-slate-400 dark:text-slate-500">{{ prettySize(node.size) }}</span>
  </button>
</template>
