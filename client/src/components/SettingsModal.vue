<script setup>
import { ref, watch } from 'vue'
import TemplateModal from '@core/TemplateModal.vue'
import { useI18n } from '@core/useI18n.js'
import { api } from '../api/orbit.js'
import { Icon } from '@core/icons'
import VideoCameraIcon from '@/assets/icons/video-camera.svg?component'

const { t } = useI18n()

const props = defineProps({ show: { type: Boolean, default: false } })
const emit = defineEmits(['close', 'queued'])

const loading = ref(true)
const saving = ref(false)
const saved = ref(false)
const error = ref('')

const transcodeVideos = ref(true)
const convertImages = ref(true)

const convertingAll = ref(false)
const bulkMsg = ref('')

// Queue every existing video / unsupported image for conversion (server decides
// what actually needs work). Independent of the toggles above — an explicit
// "convert my whole library" action.
async function convertAll() {
  bulkMsg.value = ''
  convertingAll.value = true
  try {
    const { queued } = await api.convertAll()
    bulkMsg.value = queued > 0
      ? t('orbit.settings.convertAllQueued', { count: queued })
      : t('orbit.settings.convertAllNone')
    emit('queued', queued)
  } catch (e) {
    bulkMsg.value = e.message || t('orbit.settings.saveError')
  } finally {
    convertingAll.value = false
  }
}

async function load() {
  loading.value = true
  saved.value = false
  error.value = ''
  bulkMsg.value = ''
  try {
    const s = await api.getSettings()
    transcodeVideos.value = s.transcodeVideos !== false
    convertImages.value = s.convertImages !== false
  } catch (e) {
    error.value = e.message || ''
  } finally {
    loading.value = false
  }
}

// (Re)load each time the modal opens.
watch(() => props.show, (v) => { if (v) load() }, { immediate: true })

async function save() {
  error.value = ''
  saved.value = false
  saving.value = true
  try {
    const s = await api.saveSettings({ transcodeVideos: transcodeVideos.value, convertImages: convertImages.value })
    transcodeVideos.value = s.transcodeVideos !== false
    convertImages.value = s.convertImages !== false
    saved.value = true
  } catch (e) {
    error.value = e.message || t('orbit.settings.saveError')
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <TemplateModal
    :show="show"
    header
    :title="t('orbit.settings.title')"
    size="lg"
    body-class="px-5 pb-5 pt-5"
    @cancel="emit('close')"
  >
    <div v-if="loading" class="min-h-[160px] grid place-items-center text-slate-400 text-sm">
      {{ t('orbit.settings.loading') }}
    </div>

    <div v-else class="flex flex-col gap-4">
      <p class="text-sm text-slate-500 dark:text-slate-400">{{ t('orbit.settings.subtitle') }}</p>

      <!-- Transcode videos toggle -->
      <button
        type="button"
        role="switch"
        :aria-checked="transcodeVideos"
        @click="transcodeVideos = !transcodeVideos"
        class="text-left w-full rounded-xl border border-black/10 dark:border-white/10 bg-white/40 dark:bg-white/[0.04] hover:bg-white/70 dark:hover:bg-white/[0.07] p-4 transition-all"
      >
        <div class="flex items-start gap-3">
          <span class="mt-0.5 grid place-items-center w-9 h-9 rounded-xl bg-indigo-600 text-white shrink-0">
            <VideoCameraIcon class="w-[18px] h-[18px]" />
          </span>
          <div class="min-w-0 flex-1">
            <span class="font-semibold text-slate-900 dark:text-white">{{ t('orbit.settings.transcodeTitle') }}</span>
            <p class="mt-0.5 text-sm text-slate-500 dark:text-slate-400">{{ t('orbit.settings.transcodeDesc') }}</p>
          </div>
          <!-- Switch -->
          <span
            :class="['relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors mt-0.5',
              transcodeVideos ? 'bg-indigo-600' : 'bg-slate-300 dark:bg-slate-600']"
          >
            <span
              :class="['inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform',
                transcodeVideos ? 'translate-x-5' : 'translate-x-0.5']"
            />
          </span>
        </div>
      </button>

      <!-- Convert images toggle -->
      <button
        type="button"
        role="switch"
        :aria-checked="convertImages"
        @click="convertImages = !convertImages"
        class="text-left w-full rounded-xl border border-black/10 dark:border-white/10 bg-white/40 dark:bg-white/[0.04] hover:bg-white/70 dark:hover:bg-white/[0.07] p-4 transition-all"
      >
        <div class="flex items-start gap-3">
          <span class="mt-0.5 grid place-items-center w-9 h-9 rounded-xl bg-emerald-600 text-white shrink-0">
            <Icon name="image" :sw="1.8" />
          </span>
          <div class="min-w-0 flex-1">
            <span class="font-semibold text-slate-900 dark:text-white">{{ t('orbit.settings.convertImagesTitle') }}</span>
            <p class="mt-0.5 text-sm text-slate-500 dark:text-slate-400">{{ t('orbit.settings.convertImagesDesc') }}</p>
          </div>
          <!-- Switch -->
          <span
            :class="['relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors mt-0.5',
              convertImages ? 'bg-indigo-600' : 'bg-slate-300 dark:bg-slate-600']"
          >
            <span
              :class="['inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform',
                convertImages ? 'translate-x-5' : 'translate-x-0.5']"
            />
          </span>
        </div>
      </button>

      <!-- Convert existing library -->
      <div class="rounded-xl border border-black/10 dark:border-white/10 bg-white/40 dark:bg-white/[0.04] p-4 flex items-start gap-3">
        <div class="min-w-0 flex-1">
          <span class="font-semibold text-slate-900 dark:text-white">{{ t('orbit.settings.convertAllTitle') }}</span>
          <p class="mt-0.5 text-sm text-slate-500 dark:text-slate-400">{{ t('orbit.settings.convertAllDesc') }}</p>
          <p v-if="bulkMsg" class="mt-2 text-sm text-emerald-600 dark:text-emerald-400">{{ bulkMsg }}</p>
        </div>
        <button
          @click="convertAll"
          :disabled="convertingAll"
          class="cursor-pointer shrink-0 px-4 py-2 rounded-lg text-sm font-medium text-slate-700 dark:text-slate-200 bg-black/5 dark:bg-white/10 hover:bg-black/10 dark:hover:bg-white/15 transition-colors disabled:opacity-50"
        >
          {{ convertingAll ? t('orbit.settings.convertAllRunning') : t('orbit.settings.convertAllButton') }}
        </button>
      </div>

      <!-- Actions -->
      <div class="flex items-center gap-3 pt-1">
        <button
          @click="save"
          :disabled="saving"
          class="cursor-pointer px-5 py-2.5 rounded-lg text-sm font-semibold text-white bg-indigo-600 hover:bg-indigo-500 transition-colors disabled:opacity-50"
        >
          {{ saving ? t('orbit.settings.saving') : t('orbit.settings.save') }}
        </button>
        <button
          @click="emit('close')"
          class="cursor-pointer px-4 py-2.5 rounded-lg text-sm font-medium text-slate-600 dark:text-slate-300 hover:bg-black/5 dark:hover:bg-white/10 transition-colors"
        >
          {{ t('orbit.settings.done') }}
        </button>
        <span v-if="error" class="text-sm text-rose-500">{{ error }}</span>
        <span v-else-if="saved" class="text-sm text-emerald-600 dark:text-emerald-400">{{ t('orbit.settings.saved') }}</span>
      </div>
    </div>
  </TemplateModal>
</template>
