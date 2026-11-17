// Fetches an object for streaming to `res`. If the client leaves first, the S3 request is aborted
// and the body destroyed; otherwise its pooled socket leaks and the pool eventually jams.
export async function getObjectFor(s3, command, res) {
  const ac = new AbortController()
  let body
  res.on('close', () => {
    ac.abort()
    body?.destroy?.()
  })
  const out = await s3.send(command, { abortSignal: ac.signal })
  body = out.Body
  if (res.destroyed) {
    body?.destroy?.()
    return null
  }
  return out
}
