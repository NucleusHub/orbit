<script setup>
import BackgroundBlobs from '@core/BackgroundBlobs.vue'
import AuthGuard from '@core/auth/AuthGuard.vue'
</script>

<template>
  <BackgroundBlobs />
  <AuthGuard>
    <RouterView />
  </AuthGuard>
</template>
