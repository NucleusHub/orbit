import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import vueDevTools from 'vite-plugin-vue-devtools'
import tailwindcss from '@tailwindcss/vite'
import svgLoader from 'vite-svg-loader'

export default defineConfig(({ mode }) => ({
  base: '/orbit/',
  // svgLoader with defaultImport 'url' so only `import Foo from './x.svg?component'`
  // yields a themeable Vue component; plain .svg imports stay URLs. Icons keep
  // currentColor, so we tell svgo not to touch colours or drop the viewBox.
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
      // Concrete versions so Lightning CSS actually vendor-prefixes (e.g. adds
      // -webkit-backdrop-filter for Safari while keeping the standard property
      // for Firefox/Chrome). Open-ended "safari >= 15" ranges resolve to an
      // empty target set, which silently disables prefixing.
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
      // Shared widget package (via the ./widgets symlink → repo /widgets), so
      // this app can render Pulse widgets that opt in to showing here.
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
      // Pulse state, so widgets that opt in to showing here can load in dev.
      // (Prod nginx routes /api/pulse centrally; this is dev-only.)
      '/api/pulse': {
        target: process.env.PULSE_TARGET || 'http://localhost:3004',
        changeOrigin: true,
      },
    },
    allowedHosts: [process.env.NUCLEUS_HOST || 'nucleus.olm-altair.ts.net'],
  },
}))
