<script setup>
import { ref, watch, onUnmounted } from 'vue'
import { useI18n } from '@core/useI18n.js'

const { t } = useI18n()

const props = defineProps({
  show: { type: Boolean, default: false },
  title: { type: String, default: '' },
  error: { type: String, default: null },
})
const emit = defineEmits(['submit', 'cancel'])

const password = ref('')

function onKeydown(e) { if (e.key === 'Escape') emit('cancel') }
watch(() => props.show, (val) => {
  if (val) {
    password.value = ''
    window.addEventListener('keydown', onKeydown)
  } else {
    window.removeEventListener('keydown', onKeydown)
  }
})
onUnmounted(() => window.removeEventListener('keydown', onKeydown))

function submit() {
  if (password.value) emit('submit', password.value)
}
</script>

<template>
  <Teleport to="body">
    <Transition name="fade">
      <div v-if="show" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/20 backdrop-blur-xl" @click="$emit('cancel')" />
        <div class="relative bg-white/25 dark:bg-white/8 border border-white/50 dark:border-white/10 rounded-2xl shadow-2xl w-full max-w-sm p-6 flex flex-col gap-5">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-xl bg-indigo-500/10 dark:bg-indigo-500/20 flex items-center justify-center shrink-0">
              <svg class="w-5 h-5 text-indigo-500" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25z" />
              </svg>
            </div>
            <div>
              <h2 class="text-sm font-semibold text-slate-900 dark:text-white">{{ title || t('orbit.password.required') }}</h2>
              <p class="text-xs text-slate-500 dark:text-slate-400 mt-0.5">{{ t('orbit.password.enterToContinue') }}</p>
            </div>
          </div>

          <div class="flex flex-col gap-2">
            <input
              v-model="password"
              type="password"
              :placeholder="t('orbit.password.placeholder')"
              autofocus
              class="w-full px-3 py-2 text-sm bg-black/5 dark:bg-white/8 border rounded-xl text-slate-900 dark:text-white placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/50 transition-colors"
              :class="error ? 'border-red-400 dark:border-red-500' : 'border-slate-200 dark:border-white/10'"
              @keydown.enter="submit"
            />
            <p v-if="error" class="text-xs text-red-500">{{ error }}</p>
          </div>

          <div class="flex gap-3 justify-end">
            <button
              @click="$emit('cancel')"
              class="cursor-pointer px-4 py-2 text-sm font-medium text-slate-600 dark:text-slate-300 hover:text-slate-900 dark:hover:text-white bg-slate-100 dark:bg-slate-700 hover:bg-slate-200 dark:hover:bg-slate-600 rounded-lg transition-colors"
            >{{ t('core.button.cancel') }}</button>
            <button
              @click="submit"
              :disabled="!password"
              class="cursor-pointer px-4 py-2 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-500 disabled:opacity-40 disabled:cursor-not-allowed rounded-lg transition-colors"
            >{{ t('orbit.password.unlock') }}</button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.fade-enter-active, .fade-leave-active { transition: opacity 0.15s ease; }
.fade-enter-from, .fade-leave-to { opacity: 0; }
</style>
