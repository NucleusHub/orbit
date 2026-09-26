import './assets/main.css'
import { createApp } from 'vue'
import App from './App.vue'
import router from './router/index.js'
import { registerFallback } from '@core/useI18n.js'
import fallbackLocale from '../locales/en-US.json'
registerFallback(fallbackLocale)
createApp(App).use(router).mount('#app')
