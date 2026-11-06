import express from 'express'
import { requireAuth } from '../middleware/auth.js'
import { getUserSettings, saveUserSettings, saveFaceIdLock } from '../settings.js'

const router = express.Router()
router.use(requireAuth)

router.get('/', async (req, res) => {
  try {
    res.json(await getUserSettings(req.profile.profileId))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

router.put('/', async (req, res) => {
  try {
    const saved = await saveUserSettings(req.profile.profileId, req.body || {})
    res.json(saved)
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// Face ID locks (iOS app): PUT { strict } sets one, DELETE removes it.
router.put('/face-id/:itemId', async (req, res) => {
  try {
    res.json(await saveFaceIdLock(req.profile.profileId, req.params.itemId, { strict: !!req.body?.strict }))
  } catch (err) {
    res.status(err.message === 'Invalid item id' ? 400 : 500).json({ error: err.message })
  }
})

router.delete('/face-id/:itemId', async (req, res) => {
  try {
    res.json(await saveFaceIdLock(req.profile.profileId, req.params.itemId, null))
  } catch (err) {
    res.status(err.message === 'Invalid item id' ? 400 : 500).json({ error: err.message })
  }
})

export default router
