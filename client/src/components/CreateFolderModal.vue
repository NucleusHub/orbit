<script setup>
import { ref, watch, nextTick } from 'vue'

const props = defineProps({ show: { type: Boolean, default: false } })
const emit = defineEmits(['create', 'cancel'])

const name = ref('')
const input = ref(null)

watch(() => props.show, val => {
  if (val) {
    name.value = ''
    nextTick(() => input.value?.focus())
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
  <Teleport to="body">
    <Transition name="fade">
      <div v-if="show" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/20 backdrop-blur-xl" @click="$emit('cancel')" />
        <div class="relative bg-white/25 dark:bg-white/8 border border-white/50 dark:border-white/10 rounded-2xl shadow-2xl w-full max-w-sm p-6 flex flex-col gap-5">
          <h2 class="text-base font-semibold text-slate-900 dark:text-white">New folder</h2>
          <input
            ref="input"
            v-model="name"
            type="text"
            placeholder="Folder name"
            maxlength="255"
            class="w-full px-3.5 py-2.5 text-sm bg-black/5 dark:bg-white/8 text-slate-900 dark:text-white placeholder:text-slate-400 dark:placeholder:text-slate-500 rounded-xl border border-slate-200 dark:border-white/10 focus:border-indigo-500 focus:outline-none transition-colors"
            @keydown.enter="submit"
            @keydown.escape="$emit('cancel')"
          />
          <div class="flex gap-3 justify-end">
            <button
              @click="$emit('cancel')"
              class="cursor-pointer px-4 py-2 text-sm font-medium text-slate-600 dark:text-slate-300 hover:text-slate-900 dark:hover:text-white bg-slate-100 dark:bg-slate-700 hover:bg-slate-200 dark:hover:bg-slate-600 rounded-lg transition-colors"
            >
              Cancel
            </button>
            <button
              @click="submit"
              :disabled="!name.trim()"
              class="cursor-pointer px-4 py-2 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-500 disabled:opacity-40 disabled:cursor-not-allowed rounded-lg transition-colors"
            >
              Create
            </button>
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
