import OrbitFileCard from './OrbitFileCard.vue'
import OrbitFilePicker from './OrbitFilePicker.vue'

// Orbit's Echo client integration — the single file Echo auto-discovers for this
// app (see apps/echo/client/src/echo-integrations.js). It owns everything Orbit
// contributes to the Echo UI: the renderer for its message type and the composer
// action(s). The matching server-side declaration is manifest.echo.json in this
// same folder. Echo core names no app; drop this file in and it just works.
export default {
  app: 'orbit',

  // message type -> renderer component
  renderers: {
    'orbit.file': OrbitFileCard,
  },

  // composer action id (must match a composer_actions[].id in manifest.echo.json)
  // -> how the action produces a message. Orbit uses its own drive-tree picker;
  // `toMessage` turns the picked file into the orbit.file message Echo sends.
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
