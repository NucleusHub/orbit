<script setup>
import { ref, watch } from 'vue'
import TemplateModal from '@core/TemplateModal.vue'
import { useI18n } from '@core/useI18n.js'
import { Icon } from '@core/icons'

const { t } = useI18n()

const props = defineProps({
  show: { type: Boolean, default: false },
  name: { type: String, default: '' },
  isProtected: { type: Boolean, default: false },
})
const emit = defineEmits(['save', 'cancel'])

const password = ref('')
const confirm = ref('')
const mismatch = ref(false)

watch(() => props.show, (val) => {
  if (val) { password.value = ''; confirm.value = ''; mismatch.value = false }
})

function save() {
  if (password.value !== confirm.value) { mismatch.value = true; return }
  emit('save', password.value || null)
}

function remove() {
  emit('save', null)
}
</script>

<template>
  <TemplateModal
    :show="show"
    header
    footer
    size="sm"
    :confirm-label="t('core.button.save')"
    :cancel-label="t('core.button.cancel')"
    :confirm-disabled="!password"
    body-class="px-6 py-4"
    @confirm="save"
    @cancel="$emit('cancel')"
  >
    <template #header>
      <div class="flex items-center gap-3 min-w-0">
        <div class="w-10 h-10 rounded-xl bg-indigo-500/10 dark:bg-indigo-500/20 flex items-center justify-center shrink-0">
          <Icon name="lock" class="w-5 h-5 text-indigo-500" />
        </div>
        <div class="min-w-0">
          <h2 class="text-sm font-semibold text-slate-900 dark:text-white">
            {{ isProtected ? t('orbit.password.changeTitle') : t('orbit.password.setTitle') }}
          </h2>
          <p class="text-xs text-slate-500 dark:text-slate-400 mt-0.5 truncate">{{ name }}</p>
        </div>
      </div>
    </template>

    <div class="flex flex-col gap-2">
      <input
        v-model="password"
        type="password"
        :placeholder="isProtected ? t('orbit.password.newPlaceholder') : t('orbit.password.placeholder')"
        autofocus
        class="w-full px-3 py-2 text-sm bg-black/5 dark:bg-white/8 border border-slate-200 dark:border-white/10 rounded-xl text-slate-900 dark:text-white placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/50 transition-colors"
      />
      <input
        v-model="confirm"
        type="password"
        :placeholder="t('orbit.password.confirmPlaceholder')"
        class="w-full px-3 py-2 text-sm bg-black/5 dark:bg-white/8 border rounded-xl text-slate-900 dark:text-white placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/50 transition-colors"
        :class="mismatch ? 'border-red-400 dark:border-red-500' : 'border-slate-200 dark:border-white/10'"
        @keydown.enter="save"
        @input="mismatch = false"
      />
      <p v-if="mismatch" class="text-xs text-red-500">{{ t('orbit.password.mismatch') }}</p>
    </div>

    <template v-if="isProtected" #footer-start>
      <button
        @click="remove"
        class="cursor-pointer px-4 py-2 text-sm font-medium text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-500/10 rounded-lg transition-colors"
      >{{ t('orbit.password.remove') }}</button>
    </template>
  </TemplateModal>
</template>
