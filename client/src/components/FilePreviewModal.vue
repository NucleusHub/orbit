<script setup>
import { ref, computed, watch, onMounted, onUnmounted } from 'vue'
import { getFileTypeInfo, canConvertMedia, formatEta } from '../utils/fileType.js'
import { useI18n } from '@core/useI18n.js'

const { t } = useI18n()

const props = defineProps({ file: { type: Object, default: null } })
const emit = defineEmits(['close', 'transcode'])

// Background media normalisation state (see server transcodeQueue.js).
const converting = computed(() => ['pending', 'processing'].includes(props.file?.transcodeStatus))
const canConvert = computed(() => canConvertMedia(props.file))
const convertText = computed(() => {
  if (props.file?.transcodeStatus === 'pending') return t('orbit.transcode.queued')
  const p = props.file?.transcodeProgress
  const eta = formatEta(props.file?.transcodeEta)
  if (p == null) return t('orbit.transcode.converting')
  const base = `${t('orbit.transcode.converting')} ${p}%`
  return eta ? `${base} · ${eta}` : base
})

const textContent = ref(null)
const textLoading = ref(false)
const textError = ref(false)
// Set when an <img>/<video>/<audio> element fails to load or decode the file
// (e.g. a phone/Messenger video the browser can't play even though the type is
// correct). When true we fall back to the download view instead of a broken player.
const mediaError = ref(false)

const previewType = computed(() => {
  const mime = props.file?.mimeType || ''
  if (mime.startsWith('image/')) return 'image'
  if (mime.startsWith('video/')) return 'video'
  if (mime.startsWith('audio/')) return 'audio'
  if (mime === 'application/pdf') return 'pdf'
  if (
    mime.startsWith('text/') ||
    mime.includes('json') ||
    mime.includes('javascript') ||
    mime.includes('typescript') ||
    mime.includes('xml') ||
    mime.includes('yaml')
  ) return 'text'
  return 'other'
})

// What we actually render: a failed media load collapses to the download view.
const view = computed(() => (mediaError.value ? 'other' : previewType.value))

const typeInfo = computed(() => getFileTypeInfo(props.file?.mimeType))

watch(() => props.file, async (file) => {
  textContent.value = null
  textError.value = false
  mediaError.value = false
  if (file && previewType.value === 'text') {
    textLoading.value = true
    try {
      const r = await fetch(file.url)
      textContent.value = await r.text()
    } catch {
      textError.value = true
    } finally {
      textLoading.value = false
    }
  }
}, { immediate: true })

function onKey(e) {
  if (e.key === 'Escape') emit('close')
}
onMounted(() => document.addEventListener('keydown', onKey))
onUnmounted(() => document.removeEventListener('keydown', onKey))
</script>

<template>
  <Teleport to="body">
    <Transition name="preview-fade">
      <div v-if="file" class="fixed inset-0 z-50 flex flex-col bg-black/85 backdrop-blur-sm">

        <!-- Top bar -->
        <div class="flex items-center gap-3 px-4 h-14 bg-black/40 border-b border-white/10 shrink-0">
          <button
            @click="$emit('close')"
            class="cursor-pointer p-2 rounded-xl text-white/60 hover:text-white hover:bg-white/10 transition-colors shrink-0"
            :title="t('orbit.preview.close')"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
            </svg>
          </button>

          <span class="flex-1 text-sm font-medium text-white truncate">{{ file.filename }}</span>

          <!-- Transcode status / trigger (videos only) -->
          <span
            v-if="converting"
            class="flex items-center gap-1.5 px-3 py-1.5 text-sm text-white/80 bg-white/10 rounded-xl shrink-0"
            :title="t('orbit.transcode.tooltip')"
          >
            <svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 0 1 8-8V0C5.373 0 0 5.373 0 12h4z" />
            </svg>
            <span class="hidden sm:inline">{{ convertText }}</span>
          </span>
          <button
            v-else-if="canConvert"
            @click.stop="$emit('transcode', file)"
            class="cursor-pointer flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-white/80 hover:text-white bg-white/10 hover:bg-white/20 rounded-xl transition-colors shrink-0"
            :title="t('orbit.transcode.tooltip')"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 15.75V18m-7.5-6.75h.008v.008H8.25v-.008zM12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zm-1.5-12.75 3 3m0 0-3 3m3-3H8.25" />
            </svg>
            <span class="hidden sm:inline">{{ t('orbit.transcode.convert') }}</span>
          </button>

          <a
            :href="file.url"
            :download="file.filename"
            class="cursor-pointer flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-white/80 hover:text-white bg-white/10 hover:bg-white/20 rounded-xl transition-colors shrink-0"
            @click.stop
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3" />
            </svg>
            {{ t('orbit.action.download') }}
          </a>
        </div>

        <!-- Content -->
        <div class="flex-1 overflow-hidden flex items-center justify-center p-4" @click.self="$emit('close')">

          <!-- Image -->
          <img
            v-if="view === 'image'"
            :src="file.url"
            :alt="file.filename"
            class="max-h-full max-w-full object-contain rounded-lg shadow-2xl select-none"
            @error="mediaError = true"
            @click.stop
          />

          <!-- Video -->
          <video
            v-else-if="view === 'video'"
            :src="file.url"
            controls
            autoplay
            class="max-h-full max-w-full rounded-lg shadow-2xl"
            @error="mediaError = true"
            @click.stop
          />

          <!-- Audio -->
          <div v-else-if="view === 'audio'" class="flex flex-col items-center gap-6 w-full max-w-md" @click.stop>
            <div class="w-24 h-24 rounded-2xl flex items-center justify-center" :class="typeInfo.bg">
              <svg class="w-12 h-12" :class="typeInfo.color" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" :d="typeInfo.icon" />
              </svg>
            </div>
            <p class="text-white font-medium text-center truncate w-full px-4">{{ file.filename }}</p>
            <audio :src="file.url" controls autoplay class="w-full" @error="mediaError = true" />
          </div>

          <!-- PDF -->
          <iframe
            v-else-if="view === 'pdf'"
            :src="file.url"
            class="w-full h-full rounded-lg shadow-2xl bg-white"
            @click.stop
          />

          <!-- Text / Code -->
          <div v-else-if="view === 'text'" class="w-full h-full flex flex-col rounded-lg overflow-hidden shadow-2xl" @click.stop>
            <div class="flex items-center gap-2 px-4 py-2.5 bg-slate-800 border-b border-white/10 shrink-0">
              <span class="text-xs font-mono text-slate-400">{{ file.filename }}</span>
            </div>
            <div class="flex-1 overflow-auto bg-slate-900">
              <div v-if="textLoading" class="flex items-center justify-center h-full">
                <svg class="w-6 h-6 text-indigo-400 animate-spin" fill="none" viewBox="0 0 24 24">
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" />
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 0 1 8-8V0C5.373 0 0 5.373 0 12h4z" />
                </svg>
              </div>
              <p v-else-if="textError" class="p-6 text-sm text-red-400">{{ t('orbit.preview.loadError') }}</p>
              <pre v-else class="p-6 text-xs text-slate-300 font-mono leading-relaxed whitespace-pre-wrap break-words">{{ textContent }}</pre>
            </div>
          </div>

          <!-- Other / unsupported -->
          <div v-else class="flex flex-col items-center gap-5 text-center" @click.stop>
            <div class="w-24 h-24 rounded-2xl flex items-center justify-center" :class="typeInfo.bg">
              <svg class="w-12 h-12" :class="typeInfo.color" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" :d="typeInfo.icon" />
              </svg>
            </div>
            <div>
              <p class="text-white font-medium">{{ file.filename }}</p>
              <p v-if="mediaError" class="mt-1 text-sm text-white/50">
                {{ t('orbit.preview.notPlayable') }}<br>{{ t('orbit.preview.downloadToOpen') }}
              </p>
              <p v-else class="mt-1 text-sm text-white/50">{{ t('orbit.preview.noPreview') }}</p>
            </div>
            <a
              :href="file.url"
              :download="file.filename"
              class="cursor-pointer flex items-center gap-2 px-5 py-2.5 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-500 rounded-xl transition-colors"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3" />
              </svg>
              {{ t('orbit.preview.downloadFile') }}
            </a>
          </div>

        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.preview-fade-enter-active, .preview-fade-leave-active { transition: opacity 0.15s ease; }
.preview-fade-enter-from, .preview-fade-leave-to { opacity: 0; }
</style>
