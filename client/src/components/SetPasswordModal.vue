<script setup>
import { ref, watch } from 'vue'

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
  <Teleport to="body">
    <Transition name="modal-fade">
      <div v-if="show" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm" @click.self="$emit('cancel')">
        <div class="bg-white/80 dark:bg-white/8 border border-slate-200/80 dark:border-white/10 rounded-2xl shadow-2xl w-full max-w-sm p-6 flex flex-col gap-5 backdrop-blur-xl" @click.stop>
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-xl bg-indigo-500/10 dark:bg-indigo-500/20 flex items-center justify-center shrink-0">
              <svg class="w-5 h-5 text-indigo-500" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25z" />
              </svg>
            </div>
            <div>
              <h2 class="text-sm font-semibold text-slate-900 dark:text-white">
                {{ isProtected ? 'Change password' : 'Set password' }}
              </h2>
              <p class="text-xs text-slate-500 dark:text-slate-400 mt-0.5 truncate max-w-[180px]">{{ name }}</p>
            </div>
          </div>

          <div class="flex flex-col gap-2">
            <input
              v-model="password"
              type="password"
              :placeholder="isProtected ? 'New password' : 'Password'"
              autofocus
              class="w-full px-3 py-2 text-sm bg-white dark:bg-white/8 border border-slate-200 dark:border-white/10 rounded-xl text-slate-900 dark:text-white placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/50 transition-colors"
              @keydown.escape="$emit('cancel')"
            />
            <input
              v-model="confirm"
              type="password"
              placeholder="Confirm password"
              class="w-full px-3 py-2 text-sm bg-white dark:bg-white/8 border rounded-xl text-slate-900 dark:text-white placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500/50 transition-colors"
              :class="mismatch ? 'border-red-400 dark:border-red-500' : 'border-slate-200 dark:border-white/10'"
              @keydown.enter="save"
              @keydown.escape="$emit('cancel')"
              @input="mismatch = false"
            />
            <p v-if="mismatch" class="text-xs text-red-500">Passwords don't match</p>
          </div>

          <div class="flex gap-2">
            <button
              v-if="isProtected"
              @click="remove"
              class="cursor-pointer px-4 py-2 text-sm font-medium text-red-600 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-500/10 rounded-xl transition-colors"
            >Remove</button>
            <div class="flex-1" />
            <button
              @click="$emit('cancel')"
              class="cursor-pointer px-4 py-2 text-sm font-medium text-slate-600 dark:text-slate-400 hover:text-slate-900 dark:hover:text-white transition-colors"
            >Cancel</button>
            <button
              @click="save"
              :disabled="!password"
              class="cursor-pointer px-4 py-2 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-500 disabled:opacity-40 disabled:cursor-not-allowed rounded-xl transition-colors"
            >Save</button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.modal-fade-enter-active, .modal-fade-leave-active { transition: opacity 0.15s ease; }
.modal-fade-enter-from, .modal-fade-leave-to { opacity: 0; }
</style>
