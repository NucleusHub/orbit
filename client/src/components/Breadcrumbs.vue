<script setup>
import { Icon } from '@core/icons'
defineProps({ crumbs: { type: Array, default: () => [] } })
defineEmits(['navigate'])
</script>

<template>
  <div class="flex items-center gap-2 px-4 md:px-6 py-3 text-sm border-b border-slate-200 dark:border-white/8">
    <!-- Crumbs scroll on their own; the actions slot stays pinned to the right. -->
    <div class="flex items-center gap-1 min-w-0 flex-1 overflow-x-auto">
      <button
        @click="$emit('navigate', null)"
        class="cursor-pointer flex items-center gap-1.5 shrink-0 font-medium text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white transition-colors"
      >
        <Icon name="home" class="w-4 h-4" />
        Home
      </button>

      <template v-for="(crumb, i) in crumbs" :key="crumb._id">
        <Icon name="chevronRight" class="w-4 h-4 shrink-0 text-slate-300 dark:text-slate-600" />
        <button
          v-if="i < crumbs.length - 1"
          @click="$emit('navigate', crumb._id)"
          class="cursor-pointer shrink-0 text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white transition-colors"
        >
          {{ crumb.name }}
        </button>
        <span v-else class="shrink-0 font-medium text-slate-900 dark:text-white">{{ crumb.name }}</span>
      </template>
    </div>

    <div v-if="$slots.actions" class="shrink-0"><slot name="actions" /></div>
  </div>
</template>
