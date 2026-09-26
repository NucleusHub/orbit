import OrbitFileCard from './OrbitFileCard.vue'
import OrbitFilePicker from './OrbitFilePicker.vue'

export default {
  app: 'orbit',

  renderers: {
    'orbit.file': OrbitFileCard,
  },

  composerActions: {
    upload_file: {
      picker: OrbitFilePicker,
      toMessage: file => ({
        type: 'orbit.file',
        payload: { fileId: file.id, name: file.name, mimeType: file.mimeType, size: file.size, url: file.url },
      }),
    },
  },
}
