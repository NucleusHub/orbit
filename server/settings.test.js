import { test } from 'node:test'
import assert from 'node:assert/strict'
import { faceIdLockUpdate, fromDoc } from './settings.js'

test('a lock is stored under the item id with its strict flag', () => {
  assert.deepEqual(faceIdLockUpdate('6730a1b2c3d4e5f6a7b8c9d0', { strict: true }), {
    $set: { 'faceIdLocks.6730a1b2c3d4e5f6a7b8c9d0': { strict: true } },
  })
  assert.deepEqual(faceIdLockUpdate('6730a1b2c3d4e5f6a7b8c9d0', { strict: 'yes' }), {
    $set: { 'faceIdLocks.6730a1b2c3d4e5f6a7b8c9d0': { strict: true } },
  })
})

test('removing a lock unsets it', () => {
  assert.deepEqual(faceIdLockUpdate('6730a1b2c3d4e5f6a7b8c9d0', null), {
    $unset: { 'faceIdLocks.6730a1b2c3d4e5f6a7b8c9d0': '' },
  })
})

test('ids that could reach other fields are refused', () => {
  for (const id of ['transcodeVideos', 'a.b', '$where', '', '6730a1b2c3d4e5f6a7b8c9d0.strict']) {
    assert.throws(() => faceIdLockUpdate(id, { strict: false }), /Invalid item id/)
  }
})

test('settings always carry a lock map', () => {
  assert.deepEqual(fromDoc({ transcodeVideos: true, convertImages: false }).faceIdLocks, {})
  const doc = { transcodeVideos: true, convertImages: true, faceIdLocks: new Map([['6730a1b2c3d4e5f6a7b8c9d0', { strict: false }]]) }
  assert.deepEqual(fromDoc(doc).faceIdLocks, { '6730a1b2c3d4e5f6a7b8c9d0': { strict: false } })
})
