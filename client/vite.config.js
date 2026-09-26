import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import vueDevTools from 'vite-plugin-vue-devtools'
import tailwindcss from '@tailwindcss/vite'
import svgLoader from 'vite-svg-loader'

export default defineConfig(({ mode }) => ({
  base: '/orbit/',
  plugins: [vue(), mode !== 'production' && vueDevTools(), tailwindcss(), svgLoader({
    defaultImport: 'url',
    svgo: true,
    svgoConfig: {
      plugins: [{ name: 'preset-default', params: { overrides: { removeViewBox: false, convertColors: false } } }],
    },
  })].filter(Boolean),
  css: {
    transformer: 'lightningcss',
    lightningcss: {
      // Concrete versions: open-ended ranges resolve to no targets and silently disable prefixing.
      targets: {
        safari: (15 << 16) | (4 << 8),
        ios_saf: (15 << 16) | (4 << 8),
        firefox: 103 << 16,
        chrome: 90 << 16,
        edge: 90 << 16,
      },
    },
  },
  build: { cssMinify: 'lightningcss' },
  resolve: {
    preserveSymlinks: true,
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
      '@core': fileURLToPath(new URL('./core', import.meta.url)),
      '@widgets-core': fileURLToPath(new URL('./widgets/core', import.meta.url)),
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
      '/api/pulse': {
        target: process.env.PULSE_TARGET || 'http://localhost:3004',
        changeOrigin: true,
      },
    },
    allowedHosts: [process.env.NUCLEUS_HOST || 'nucleus.olm-altair.ts.net'],
  },
}))
