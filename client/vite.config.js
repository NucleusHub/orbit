import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import vueDevTools from 'vite-plugin-vue-devtools'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig(({ mode }) => ({
  base: '/orbit/',
  plugins: [vue(), mode !== 'production' && vueDevTools(), tailwindcss()].filter(Boolean),
  resolve: {
    preserveSymlinks: true,
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
      '@core': fileURLToPath(new URL('./core', import.meta.url)),
    },
  },
  server: {
    host: '0.0.0.0',
    port: 5177,
    proxy: {
      '/api/orbit': {
        target: process.env.API_TARGET || 'http://localhost:3003',
        changeOrigin: true,
      },
    },
    allowedHosts: ['nucleus.home', 'server.tail874d1f.ts.net'],
  },
}))
