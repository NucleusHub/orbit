import { ref, computed } from 'vue'

const dragging = ref(null)

export function useDnd() {
  function startDrag(payload, e) {
    dragging.value = payload
    if (e?.dataTransfer) {
      e.dataTransfer.effectAllowed = 'move'
      // Firefox won't start a drag unless some data is set.
      try { e.dataTransfer.setData('text/plain', payload.id) } catch {}
    }
  }
  function endDrag() {
    dragging.value = null
  }
  return { dragging, isDragging: computed(() => !!dragging.value), startDrag, endDrag }
}
