<script setup>
import { useI18n } from '@core/useI18n.js'
import { Icon, Spinner } from '@core/icons'

const { t } = useI18n()
defineProps({ uploads: { type: Array, default: () => [] } })
defineEmits(['dismiss'])

function fmtEta(s) {
  if (s == null || !isFinite(s)) return ''
  s = Math.round(s)
  if (s < 1) return 'less than a second left'
  if (s < 60) return `${s}s left`
  const m = Math.floor(s / 60)
  const sec = s % 60
  if (m < 60) return sec ? `${m}m ${sec}s left` : `${m}m left`
  const h = Math.floor(m / 60)
  return `${h}h ${m % 60}m left`
}

function fmtSpeed(bps) {
  if (!bps || !isFinite(bps)) return ''
  const units = ['B/s', 'KB/s', 'MB/s', 'GB/s']
  let i = 0
  while (bps >= 1024 && i < units.length - 1) { bps /= 1024; i++ }
  return `${bps.toFixed(bps < 10 && i > 0 ? 1 : 0)} ${units[i]}`
}
</script>

<template>
  <Teleport to="body">
    <Transition name="slide-up">
      <div
        v-if="uploads.length"
        class="fixed bottom-4 right-3 left-3 sm:left-auto sm:right-6 sm:bottom-6 z-50 flex flex-col gap-2 sm:w-72"
      >
        <div
          v-for="u in uploads"
          :key="u.id"
          class="flex items-center gap-3 px-4 py-3 bg-white/90 dark:bg-slate-800/90 backdrop-blur-xl border border-slate-200/80 dark:border-white/10 rounded-xl shadow-lg shadow-black/10"
        >
          <!-- Status icon -->
          <div class="shrink-0">
            <Icon name="check" v-if="u.status === 'done'" class="w-4 h-4 text-emerald-500" :sw="2.5" />
            <Icon name="infoDot" v-else-if="u.status === 'error'" class="w-4 h-4 text-red-500" :sw="2.5" />
            <Spinner v-else class="w-4 h-4 text-indigo-500 animate-spin" />
          </div>

          <!-- File name + progress -->
          <div class="flex-1 min-w-0">
            <p class="text-xs font-medium text-slate-900 dark:text-white truncate">{{ u.filename }}</p>
            <div v-if="u.status === 'uploading'" class="mt-1.5">
              <div class="h-1 bg-slate-100 dark:bg-white/10 rounded-full overflow-hidden">
                <div
                  class="h-full bg-indigo-500 rounded-full transition-all duration-300"
                  :style="{ width: `${u.progress}%` }"
                />
              </div>
              <div class="mt-1 flex items-center justify-between gap-2 text-[10px] text-slate-400 dark:text-slate-500">
                <span class="font-medium tabular-nums">{{ u.progress }}%</span>
                <span v-if="u.eta != null" class="truncate">{{ fmtEta(u.eta) }}<template v-if="fmtSpeed(u.speed)"> · {{ fmtSpeed(u.speed) }}</template></span>
              </div>
            </div>
            <p v-else-if="u.status === 'error'" class="mt-0.5 text-xs text-red-500 truncate">{{ u.error }}</p>
            <p v-else class="mt-0.5 text-xs text-emerald-500">{{ t('orbit.upload.complete') }}</p>
          </div>

          <!-- Dismiss -->
          <button
            v-if="u.status !== 'uploading'"
            @click="$emit('dismiss', u.id)"
            class="cursor-pointer shrink-0 text-slate-400 hover:text-slate-600 dark:hover:text-slate-300"
          >
            <Icon name="close" class="w-3.5 h-3.5" :sw="2.5" />
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
