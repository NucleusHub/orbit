<script setup>
import { ref, watch } from 'vue'
import TemplateModal from '@core/TemplateModal.vue'
import { useI18n } from '@core/useI18n.js'
import { Icon } from '@core/icons'

const { t } = useI18n()

const props = defineProps({
  show: { type: Boolean, default: false },
  title: { type: String, default: '' },
  error: { type: String, default: null },
})
const emit = defineEmits(['submit', 'cancel'])

const password = ref('')

watch(() => props.show, (val) => {
  if (val) password.value = ''
})

function submit() {
  if (password.value) emit('submit', password.value)
}
</script>

<template>
  <TemplateModal
    :show="show"
    header
    footer
    size="sm"
    :confirm-label="t('orbit.password.unlock')"
    :cancel-label="t('core.button.cancel')"
    :confirm-disabled="!password"
    body-class="px-6 py-4"
    @confirm="submit"
    @cancel="$emit('cancel')"
  >
    <template #header>
      <div class="flex items-center gap-3 min-w-0">
        <div class="w-10 h-10 rounded-xl bg-indigo-500/10 dark:bg-indigo-500/20 flex items-center justify-center shrink-0">
          <Icon name="lock" class="w-5 h-5 text-indigo-500" />
        </div>
        <div class="min-w-0">
          <h2 class="text-sm font-semibold text-slate-900 dark:text-white">{{ title || t('orbit.password.required') }}</h2>
          <p class="text-xs text-slate-500 dark:text-slate-400 mt-0.5">{{ t('orbit.password.enterToContinue') }}</p>
        </div>
      </div>
    </template>

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
  </TemplateModal>
</template>
