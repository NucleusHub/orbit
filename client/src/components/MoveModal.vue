<script setup>
import { ref, computed, watch } from 'vue'
import { api } from '../api/orbit.js'
import TemplateModal from '@core/TemplateModal.vue'
import { useI18n } from '@core/useI18n.js'
import { Icon, Spinner } from '@core/icons'

const { t } = useI18n()

const props = defineProps({
  show: { type: Boolean, default: false },
  item: { type: Object, default: null }, // { _id, filename|name, type: 'file'|'folder' }
  currentFolderId: { type: String, default: null },
})
const emit = defineEmits(['move', 'cancel'])

const folders = ref([])
const selected = ref(undefined) // undefined = not yet chosen; null = root
const collapsed = ref(new Set())
const loading = ref(false)
const error = ref(null)

const itemName = computed(() => props.item?.filename || props.item?.name || '')
const descLabel = computed(() => `“${itemName.value}”`)

watch(() => props.show, async (val) => {
  if (!val) return
  selected.value = undefined
  collapsed.value = new Set()
  error.value = null
  loading.value = true
  try {
    folders.value = await api.getAllFolders()
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
})

// Flat list with depth, excluding the moving folder and its descendants
const flatTree = computed(() => {
  const excludeId = props.item?.type === 'folder' ? String(props.item._id) : null
  const excluded = new Set()
  if (excludeId) {
    // Collect all descendants to exclude
    const collect = (id) => {
      excluded.add(id)
      folders.value.filter(f => String(f.parentId || null) === id).forEach(f => collect(String(f._id)))
    }
    collect(excludeId)
  }

  const result = []
  function walk(parentId, depth) {
    folders.value
      .filter(f => String(f.parentId || null) === String(parentId || null))
      .forEach(f => {
        const id = String(f._id)
        if (excluded.has(id)) return
        const hasChildren = folders.value.some(c => !excluded.has(String(c._id)) && String(c.parentId || null) === id)
        result.push({ ...f, depth, hasChildren, isCollapsed: collapsed.value.has(id) })
        if (!collapsed.value.has(id)) walk(f._id, depth + 1)
      })
  }
  walk(null, 0)
  return result
})

function toggle(id) {
  const s = new Set(collapsed.value)
  if (s.has(id)) s.delete(id)
  else s.add(id)
  collapsed.value = s
}

const isSameLocation = computed(() => {
  const sel = selected.value === undefined ? undefined : (selected.value === null ? null : String(selected.value))
  const cur = props.currentFolderId === null ? null : String(props.currentFolderId)
  return sel === cur || sel === undefined
})

function submit() {
  emit('move', selected.value === undefined ? null : selected.value)
}
</script>

<template>
  <TemplateModal
    :show="show"
    header
    footer
    size="sm"
    :title="t('orbit.move.title')"
    :description="descLabel"
    :confirm-label="t('orbit.move.here')"
    :cancel-label="t('core.button.cancel')"
    :confirm-disabled="isSameLocation"
    body-class="py-2"
    @confirm="submit"
    @cancel="$emit('cancel')"
  >
    <div v-if="loading" class="flex items-center justify-center py-10">
      <Spinner class="w-5 h-5 text-indigo-500 animate-spin" />
    </div>

    <div v-else-if="error" class="px-5 py-4 text-sm text-red-500">{{ t('orbit.move.loadError') }} {{ error }}</div>

    <template v-else>
      <!-- Root option -->
      <button
        class="w-full flex items-center gap-2 px-4 py-2 text-sm transition-colors cursor-pointer"
        :class="selected === null
          ? 'bg-indigo-50 dark:bg-indigo-500/20 text-indigo-700 dark:text-indigo-300'
          : 'text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-white/6'"
        @click="selected = null"
      >
        <Icon name="home" class="w-4 h-4 shrink-0 text-slate-400 dark:text-slate-500" />
        <span class="font-medium">{{ t('orbit.move.home') }}</span>
        <span v-if="currentFolderId === null" class="ml-auto text-xs text-slate-400 dark:text-slate-500">{{ t('orbit.move.current') }}</span>
      </button>

      <!-- Folder rows -->
      <div
        v-for="folder in flatTree"
        :key="folder._id"
        class="flex items-center gap-1 pr-4 py-0.5"
        :style="{ paddingLeft: `${(folder.depth + 1) * 16 + 4}px` }"
      >
        <!-- Collapse toggle -->
        <button
          v-if="folder.hasChildren"
          class="cursor-pointer p-0.5 rounded text-slate-400 hover:text-slate-600 dark:hover:text-slate-300 shrink-0"
          @click.stop="toggle(String(folder._id))"
        >
          <Icon name="chevronRight" class="w-3 h-3 transition-transform" :class="folder.isCollapsed ? '' : 'rotate-90'" :sw="2.5" />
        </button>
        <span v-else class="w-4 shrink-0" />

        <!-- Folder row button -->
        <button
          class="flex-1 flex items-center gap-2 px-2 py-1.5 rounded-lg text-sm transition-colors cursor-pointer text-left"
          :class="String(selected) === String(folder._id)
            ? 'bg-indigo-50 dark:bg-indigo-500/20 text-indigo-700 dark:text-indigo-300'
            : 'text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-white/6'"
          @click="selected = folder._id"
        >
          <Icon name="folder" class="w-4 h-4 shrink-0 text-indigo-400" :sw="1.5" />
          <span class="truncate">{{ folder.name }}</span>
          <span v-if="String(folder._id) === String(currentFolderId)" class="ml-auto text-xs text-slate-400 dark:text-slate-500 shrink-0">{{ t('orbit.move.current') }}</span>
        </button>
      </div>

      <p v-if="!flatTree.length && !loading" class="px-5 py-4 text-sm text-slate-400 dark:text-slate-500">{{ t('orbit.move.noFolders') }}</p>
    </template>
  </TemplateModal>
</template>
