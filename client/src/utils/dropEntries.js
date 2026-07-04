// Extract dropped items as `{ file, relativePath }`, preserving any folder
// structure so a whole directory can be dragged in. `webkitGetAsEntry()` must
// be called synchronously inside the drop handler (the DataTransferItemList is
// cleared once the event returns), so this grabs the entry list up-front before
// awaiting anything.
export function readDataTransferEntries(dataTransfer) {
  const items = Array.from(dataTransfer?.items || [])
  const roots = items
    .map(it => (it.webkitGetAsEntry ? it.webkitGetAsEntry() : null))
    .filter(Boolean)

  // Browser without the entries API (or a paste of plain files) — fall back to
  // the flat file list, keeping just the filename as the relative path.
  if (!roots.length) {
    return Promise.resolve(
      Array.from(dataTransfer?.files || []).map(f => ({ file: f, relativePath: f.name }))
    )
  }

  const out = []
  return Promise.all(roots.map(entry => walkEntry(entry, '', out))).then(() => out)
}

function walkEntry(entry, prefix, out) {
  return new Promise(resolve => {
    if (entry.isFile) {
      entry.file(
        file => { out.push({ file, relativePath: prefix + entry.name }); resolve() },
        () => resolve(), // unreadable entry — skip rather than abort the whole drop
      )
    } else if (entry.isDirectory) {
      const reader = entry.createReader()
      const dirPrefix = `${prefix}${entry.name}/`
      // readEntries returns at most ~100 entries per call, so keep reading until
      // it yields an empty batch.
      const readBatch = () => {
        reader.readEntries(async batch => {
          if (!batch.length) { resolve(); return }
          for (const child of batch) await walkEntry(child, dirPrefix, out)
          readBatch()
        }, () => resolve())
      }
      readBatch()
    } else {
      resolve()
    }
  })
}
