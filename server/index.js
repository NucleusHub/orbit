import 'dotenv/config'
import express from 'express'
import cors from 'cors'
import cookieParser from 'cookie-parser'
import mongoose from 'mongoose'
import filesRouter from './routes/files.js'
import foldersRouter from './routes/folders.js'
import groupsRouter from './routes/groups.js'

const app = express()
const PORT = process.env.PORT || 3003

app.use(cors({ origin: true, credentials: true }))
app.use(express.json())
app.use(cookieParser())

app.get('/api/orbit/health', (req, res) => res.json({ status: 'ok' }))
app.use('/api/orbit/files', filesRouter)
app.use('/api/orbit/folders', foldersRouter)
app.use('/api/orbit/groups', groupsRouter)

mongoose
  .connect(process.env.MONGODB_URI)
  .then(() => {
    console.log('Connected to MongoDB')
    app.listen(PORT, () => console.log(`Orbit server on port ${PORT}`))
  })
  .catch(err => {
    console.error('MongoDB connection error:', err)
    process.exit(1)
  })
