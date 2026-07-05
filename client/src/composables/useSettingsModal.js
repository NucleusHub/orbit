import { ref } from 'vue'

// Shared open/close state for the Settings modal (module-level ref = the
// app-wide "store"), so any component can open it without prop/event threading.
const open = ref(false)

export function useSettingsModal() {
  return {
    open,
    openSettings: () => { open.value = true },
    closeSettings: () => { open.value = false },
  }
}
