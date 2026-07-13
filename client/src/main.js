import './assets/main.css'
import { createApp } from 'vue'
import App from './App.vue'
import router from './router/index.js'
import { registerFallback } from '@core/useI18n.js'
// Manifest default locale (nucleus.app.json → localization.defaultLanguage),
// bundled for static single-language mode when the localization plugin is
// disabled or not installed. The ./locales symlink → ../locales (this app's dir).
import fallbackLocale from '../locales/en-US.json'
registerFallback(fallbackLocale)
createApp(App).use(router).mount('#app')
