<script setup>
defineProps({ crumbs: { type: Array, default: () => [] } })
defineEmits(['navigate'])
</script>

<template>
  <div class="flex items-center gap-1 px-4 md:px-6 py-3 text-sm overflow-x-auto border-b border-slate-200 dark:border-white/8">
    <button
      @click="$emit('navigate', null)"
      class="cursor-pointer flex items-center gap-1.5 shrink-0 font-medium text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white transition-colors"
    >
      <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" d="m2.25 12 8.954-8.955c.44-.439 1.152-.439 1.591 0L21.75 12M4.5 9.75v10.125c0 .621.504 1.125 1.125 1.125H9.75v-4.875c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125V21h4.125c.621 0 1.125-.504 1.125-1.125V9.75M8.25 21h8.25" />
      </svg>
      Home
    </button>

    <template v-for="(crumb, i) in crumbs" :key="crumb._id">
      <svg class="w-4 h-4 shrink-0 text-slate-300 dark:text-slate-600" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
      </svg>
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
</template>
