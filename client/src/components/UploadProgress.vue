<script setup>
defineProps({ uploads: { type: Array, default: () => [] } })
defineEmits(['dismiss'])
</script>

<template>
  <Teleport to="body">
    <Transition name="slide-up">
      <div
        v-if="uploads.length"
        class="fixed bottom-6 right-6 z-50 flex flex-col gap-2 w-72"
      >
        <div
          v-for="u in uploads"
          :key="u.id"
          class="flex items-center gap-3 px-4 py-3 bg-white/90 dark:bg-slate-800/90 backdrop-blur-xl border border-slate-200/80 dark:border-white/10 rounded-xl shadow-lg shadow-black/10"
        >
          <!-- Status icon -->
          <div class="shrink-0">
            <svg v-if="u.status === 'done'" class="w-4 h-4 text-emerald-500" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" d="m4.5 12.75 6 6 9-13.5" />
            </svg>
            <svg v-else-if="u.status === 'error'" class="w-4 h-4 text-red-500" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m9-.75a9 9 0 1 1-18 0 9 9 0 0 1 18 0zm-9 3.75h.008v.008H12v-.008z" />
            </svg>
            <svg v-else class="w-4 h-4 text-indigo-500 animate-spin" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 0 1 8-8V0C5.373 0 0 5.373 0 12h4z" />
            </svg>
          </div>

          <!-- File name + progress -->
          <div class="flex-1 min-w-0">
            <p class="text-xs font-medium text-slate-900 dark:text-white truncate">{{ u.filename }}</p>
            <div v-if="u.status === 'uploading'" class="mt-1.5 h-1 bg-slate-100 dark:bg-white/10 rounded-full overflow-hidden">
              <div
                class="h-full bg-indigo-500 rounded-full transition-all duration-300"
                :style="{ width: `${u.progress}%` }"
              />
            </div>
            <p v-else-if="u.status === 'error'" class="mt-0.5 text-xs text-red-500 truncate">{{ u.error }}</p>
            <p v-else class="mt-0.5 text-xs text-emerald-500">Upload complete</p>
          </div>

          <!-- Dismiss -->
          <button
            v-if="u.status !== 'uploading'"
            @click="$emit('dismiss', u.id)"
            class="cursor-pointer shrink-0 text-slate-400 hover:text-slate-600 dark:hover:text-slate-300"
          >
            <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.slide-up-enter-active, .slide-up-leave-active { transition: all 0.2s ease; }
.slide-up-enter-from, .slide-up-leave-to { opacity: 0; transform: translateY(8px); }
</style>
