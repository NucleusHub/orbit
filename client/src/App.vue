<script setup>
import BackgroundBlobs from '@core/BackgroundBlobs.vue'
import AuthGuard from '@core/auth/AuthGuard.vue'
</script>

<template>
  <BackgroundBlobs />
  <div class="relative z-10">
    <AuthGuard>
      <RouterView />
    </AuthGuard>
  </div>
</template>
