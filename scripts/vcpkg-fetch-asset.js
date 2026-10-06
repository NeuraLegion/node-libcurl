// this should not use any third party dependencies! Only native Node.js modules!
//
// vcpkg x-script asset fetcher.
//
// Why this exists: the Windows source build pulls some dependencies (e.g.
// vcpkg's `gsasl` port -> gsasl-<ver>.tar.gz) exclusively from the GNU FTP
// network (ftpmirror.gnu.org / ftp.gnu.org). That network is intermittently
// unreachable and, when it times out, the whole native build fails. The same
// files are mirrored verbatim across the GNU mirror network, so we redirect
// GNU-FTP asset URLs to a reachable mirror and fall back to the original URL
// for every other asset. vcpkg verifies the SHA512 of whatever is produced,
// so swapping to a mirror cannot substitute a different file.
//
// Wired in from vcpkg-setup.js via:
//   X_VCPKG_ASSET_SOURCES="x-script,node <this> {url} {sha512} {dst}"
// vcpkg substitutes {url}/{sha512}/{dst} when it invokes the command.

const fs = require('fs')
const path = require('path')
const https = require('https')

const [, , url, , dst] = process.argv

if (!url || !dst) {
  console.error('vcpkg-fetch-asset: usage: <url> <sha512> <dst>')
  process.exit(2)
}

// A reachable GNU mirror that serves the identical files under the same
// /gnu/ layout. Overridable so consumers behind a proxy can point elsewhere.
const GNU_MIRROR =
  process.env.NODE_LIBCURL_GNU_MIRROR || 'https://mirrors.kernel.org'
const DEAD_GNU_HOSTS = ['ftpmirror.gnu.org', 'ftp.gnu.org']

function mirrorFor(originalUrl) {
  try {
    const u = new URL(originalUrl)
    if (DEAD_GNU_HOSTS.includes(u.hostname) && u.pathname.startsWith('/gnu/')) {
      return `${GNU_MIRROR}${u.pathname}`
    }
  } catch {
    // fall through to the original URL
  }

  return null
}

function download(fromUrl, toPath, redirects = 0) {
  return new Promise((resolve, reject) => {
    if (redirects > 5) {
      return reject(new Error('too many redirects'))
    }

    fs.mkdirSync(path.dirname(toPath), { recursive: true })

    https
      .get(fromUrl, (res) => {
        if (
          res.statusCode >= 300 &&
          res.statusCode < 400 &&
          res.headers.location
        ) {
          res.resume()
          const next = new URL(res.headers.location, fromUrl).toString()

          return resolve(download(next, toPath, redirects + 1))
        }

        if (res.statusCode !== 200) {
          res.resume()

          return reject(new Error(`HTTP ${res.statusCode} for ${fromUrl}`))
        }

        const file = fs.createWriteStream(toPath)
        res.pipe(file)
        file.on('finish', () => file.close(() => resolve()))
        file.on('error', reject)
      })
      .on('error', reject)
  })
}

async function fetchAsset() {
  const candidates = []
  const mirror = mirrorFor(url)
  if (mirror) {
    candidates.push(mirror)
  }
  candidates.push(url)

  for (const candidate of candidates) {
    try {
      console.log(`vcpkg-fetch-asset: downloading ${candidate}`)
      await download(candidate, dst)

      // success; vcpkg verifies the SHA512 of the result afterwards
      return
    } catch (error) {
      console.error(`vcpkg-fetch-asset: ${candidate} failed: ${error.message}`)
    }
  }

  console.error(`vcpkg-fetch-asset: all sources failed for ${url}`)
  process.exit(1)
}

fetchAsset()
