<script setup>
import { useI18n } from '@core/useI18n.js'

const { t } = useI18n()
const model = defineModel({ type: String, default: '' })
</script>

<template>
  <div class="relative">
    <svg class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 dark:text-slate-500 pointer-events-none" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" d="m21 21-5.197-5.197m0 0A7.5 7.5 0 1 0 5.196 5.196a7.5 7.5 0 0 0 10.607 10.607z" />
    </svg>
    <input
      :value="model"
      @input="model = $event.target.value"
      type="text"
      :placeholder="t('orbit.search.placeholder')"
      class="w-32 sm:w-56 pl-9 pr-3 py-1.5 text-sm bg-black/5 dark:bg-white/8 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-slate-500 rounded-lg border border-transparent focus:border-indigo-500/50 focus:outline-none focus:bg-white dark:focus:bg-white/12 transition-all duration-200"
    />
    <button
      v-if="model"
      @click="model = ''"
      class="cursor-pointer absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600 dark:hover:text-slate-300"
    >
      <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
      </svg>
    </button>
  </div>
</template>
