<script setup>
import { ref, watch, nextTick } from 'vue'
import TemplateModal from '@core/TemplateModal.vue'
import { useI18n } from '@core/useI18n.js'

const { t } = useI18n()

const props = defineProps({
  show:         { type: Boolean, default: false },
  title:        { type: String, default: 'New folder' },
  initialValue: { type: String, default: '' },
  confirmLabel: { type: String, default: 'Create' },
})
const emit = defineEmits(['create', 'cancel'])

const name = ref('')
const input = ref(null)

watch(() => props.show, val => {
  if (val) {
    name.value = props.initialValue
    nextTick(() => { input.value?.focus(); input.value?.select() })
  }
})

function submit() {
  const trimmed = name.value.trim()
  if (!trimmed) return
  emit('create', trimmed)
  name.value = ''
}
</script>

<template>
  <TemplateModal
    :show="show"
    header
    footer
    size="sm"
    :title="title"
    :confirm-label="confirmLabel"
    :cancel-label="t('core.button.cancel')"
    :confirm-disabled="!name.trim()"
    body-class="px-6 py-4"
    @confirm="submit"
    @cancel="$emit('cancel')"
  >
    <input
      ref="input"
      v-model="name"
      type="text"
      :placeholder="t('orbit.folder.namePlaceholder')"
      maxlength="255"
      class="w-full px-3.5 py-2.5 text-sm bg-black/5 dark:bg-white/8 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-slate-500 rounded-xl border border-slate-200 dark:border-white/10 focus:border-indigo-500 focus:outline-none transition-colors"
      @keydown.enter="submit"
    />
  </TemplateModal>
</template>
