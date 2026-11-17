import { test } from 'node:test'
import assert from 'node:assert/strict'
import { EventEmitter } from 'node:events'
import { PassThrough } from 'node:stream'
import { getObjectFor } from './s3Stream.js'

function fakeRes() {
  const res = new EventEmitter()
  res.destroyed = false
  res.leave = () => { res.destroyed = true; res.emit('close') }
  return res
}

// Resolves only when `release` is called, like a slow MinIO answer.
function slowS3(body) {
  let release
  const s3 = {
    signal: null,
    send(_cmd, opts) {
      s3.signal = opts?.abortSignal
      return new Promise((resolve) => { release = () => resolve({ Body: body }) })
    },
  }
  return { s3, release: () => release() }
}

test('a client that leaves before S3 answers aborts the request and frees the body', async () => {
  const body = new PassThrough()
  const { s3, release } = slowS3(body)
  const res = fakeRes()
  const pending = getObjectFor(s3, {}, res)
  res.leave()
  assert.equal(s3.signal.aborted, true)
  release()
  assert.equal(await pending, null)
  assert.equal(body.destroyed, true)
})

test('a client that leaves mid-stream destroys the body', async () => {
  const body = new PassThrough()
  const { s3, release } = slowS3(body)
  const res = fakeRes()
  const pending = getObjectFor(s3, {}, res)
  release()
  const out = await pending
  assert.equal(out.Body, body)
  res.leave()
  assert.equal(body.destroyed, true)
})
