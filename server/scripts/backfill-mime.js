// One-off backfill: fix Content-Type on existing objects so already-uploaded
// files (esp. MP4s stored as application/octet-stream) start previewing.
//
// It checks the ACTUAL Content-Type stored on the MinIO object (HeadObject),
// not just the Mongo mimeType field — the two can disagree, and it's MinIO's
// value the browser sees. When either is wrong it rewrites the object metadata
// in place via an in-bucket CopyObject (MetadataDirective: REPLACE) and syncs
// the Mongo record.
//
//   node scripts/backfill-mime.js          # apply changes
//   node scripts/backfill-mime.js --dry    # report only, change nothing
//
// Run from apps/orbit/server with the same env the server uses (MONGODB_URI,
// MINIO_* vars). Re-runnable and idempotent.
import 'dotenv/config'
import mongoose from 'mongoose'
import { CopyObjectCommand, HeadObjectCommand } from '@aws-sdk/client-s3'
import File from '../models/File.js'
import { s3, BUCKET } from '../routes/files.js'
import { mimeFor } from '../utils/mime.js'

const DRY = process.argv.includes('--dry')

// Encode a key for the CopySource header while keeping path separators.
const encodeKey = (key) => `${BUCKET}/${key}`.split('/').map(encodeURIComponent).join('/')

async function main() {
  await mongoose.connect(process.env.MONGODB_URI)
  const files = await File.find({})
  let changed = 0, skipped = 0, failed = 0, missing = 0

  for (const f of files) {
    let real
    try {
      real = (await s3.send(new HeadObjectCommand({ Bucket: BUCKET, Key: f.objectKey }))).ContentType
    } catch (err) {
      missing++
      console.error(`  ? object missing for ${f.filename} (${f.objectKey}): ${err.name}`)
      continue
    }

    const want = mimeFor(f.filename, real || f.mimeType)
    const minioOk = real === want
    const mongoOk = f.mimeType === want
    if (minioOk && mongoOk) { skipped++; continue }

    console.log(`${DRY ? '[dry] ' : ''}${f.filename}: minio=${real || '(none)'} mongo=${f.mimeType || '(none)'} -> ${want}`)
    if (DRY) { changed++; continue }

    try {
      if (!minioOk) {
        await s3.send(new CopyObjectCommand({
          Bucket: BUCKET,
          CopySource: encodeKey(f.objectKey),
          Key: f.objectKey,
          MetadataDirective: 'REPLACE',
          ContentType: want,
        }))
      }
      if (!mongoOk) { f.mimeType = want; await f.save() }
      changed++
    } catch (err) {
      failed++
      console.error(`  ! failed for ${f.objectKey}: ${err.message}`)
    }
  }

  console.log(`\nDone. ${changed} ${DRY ? 'would change' : 'updated'}, ${skipped} already correct, ${missing} missing objects, ${failed} failed.`)
  await mongoose.disconnect()
  process.exit(failed ? 1 : 0)
}

main().catch(err => { console.error(err); process.exit(1) })
