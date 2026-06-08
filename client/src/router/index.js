import { createRouter, createWebHistory } from 'vue-router'
import FilesView from '@/views/FilesView.vue'

export default createRouter({
  history: createWebHistory('/orbit/'),
  routes: [
    { path: '/', component: FilesView },
  ],
})
