export function readDataTransferEntries(dataTransfer) {
  // Entries must be read synchronously; the item list is cleared once the drop event returns.
  const items = Array.from(dataTransfer?.items || [])
  const roots = items
    .map(it => (it.webkitGetAsEntry ? it.webkitGetAsEntry() : null))
    .filter(Boolean)

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
        () => resolve(),
      )
    } else if (entry.isDirectory) {
      const reader = entry.createReader()
      const dirPrefix = `${prefix}${entry.name}/`
      const readBatch = () => {
        // readEntries returns at most ~100 entries per call; read until an empty batch.
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
