import express from 'express'
import { requireAuth } from '../middleware/auth.js'
import { getUserSettings, saveUserSettings } from '../settings.js'

const router = express.Router()
router.use(requireAuth)

// GET /api/orbit/settings — the caller's own settings (defaults if never saved).
router.get('/', async (req, res) => {
  try {
    res.json(await getUserSettings(req.profile.profileId))
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

// PUT /api/orbit/settings — update the caller's settings; returns the saved view.
router.put('/', async (req, res) => {
  try {
    const saved = await saveUserSettings(req.profile.profileId, req.body || {})
    res.json(saved)
  } catch (err) {
    res.status(500).json({ error: err.message })
  }
})

export default router
