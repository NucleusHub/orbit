import jwt from 'jsonwebtoken'

const secret = () => process.env.JWT_SECRET || 'nucleus-jwt-secret'

export function requireAuth(req, res, next) {
  const token = req.cookies?.nucleus_token
  if (!token) return res.status(401).json({ error: 'Unauthenticated' })
  try {
    req.profile = jwt.verify(token, secret())
    next()
  } catch {
    res.status(401).json({ error: 'Invalid or expired token' })
  }
}
