import { ref, computed } from 'vue'

// Module-level so every card shares the one payload that's "in flight" during an
// HTML5 drag — the drop target reads it to know what was dropped on it.
const dragging = ref(null) // { type: 'file' | 'folder', id, name }

export function useDnd() {
  function startDrag(payload, e) {
    dragging.value = payload
    if (e?.dataTransfer) {
      e.dataTransfer.effectAllowed = 'move'
      // Firefox won't initiate a drag unless some data is set.
      try { e.dataTransfer.setData('text/plain', payload.id) } catch {}
    }
  }
  function endDrag() {
    dragging.value = null
  }
  return { dragging, isDragging: computed(() => !!dragging.value), startDrag, endDrag }
}
