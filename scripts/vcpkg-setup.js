// this should not use any third party dependencies! Only native Node.js modules!
const { execSync: exec } = require('child_process')
const fs = require('fs')
const path = require('path')

const { triplet, moduleRoot, vcpkgRoot } = require('./vcpkg-common')
const {
  getAvailableVersions,
  findBestVersion,
} = require('./vcpkg-openssl-version')

const modulePackageJson = require('../package.json')

async function setupVcpkg() {
  try {
    let vcpkgExe

    // Check for global vcpkg
    if (process.env.VCPKG_ROOT) {
      vcpkgExe = path.join(process.env.VCPKG_ROOT, 'vcpkg.exe')
      if (!fs.existsSync(vcpkgExe)) {
        console.error('VCPKG_ROOT set but vcpkg.exe not found')
        process.exit(1)
      }
      console.log(`Using global vcpkg at ${process.env.VCPKG_ROOT}`)
    } else {
      // Bootstrap local vcpkg
      if (!fs.existsSync(vcpkgRoot)) {
        console.log('Cloning vcpkg locally...')
        exec(
          `git clone https://github.com/microsoft/vcpkg.git "${vcpkgRoot}"`,
          {
            cwd: path.dirname(vcpkgRoot),
            maxBuffer: 10 * 1024 * 1024,
            stdio: 'inherit',
          },
        )
      } else {
        console.log(`Using local vcpkg at ${vcpkgRoot}`)
      }

      vcpkgExe = path.join(vcpkgRoot, 'vcpkg.exe')
      if (!fs.existsSync(vcpkgExe)) {
        console.log('Bootstrapping vcpkg...')
        exec(`"${path.join(vcpkgRoot, 'bootstrap-vcpkg.bat')}"`, {
          cwd: vcpkgRoot,
          maxBuffer: 10 * 1024 * 1024,
          stdio: 'inherit',
        })
      }
    }

    await createVcpkgJson()

    // Install dependencies
    console.log(`Installing curl with ${triplet}...`)
    const installCmd = `"${vcpkgExe}" install --triplet ${triplet}`
    exec(installCmd, {
      cwd: moduleRoot,
      maxBuffer: 20 * 1024 * 1024,
      stdio: 'inherit',
    })

    const installedRoot = path.join(moduleRoot, 'vcpkg_installed', triplet)

    console.log(`✓ vcpkg setup complete`)
    console.log(`  Installed to: ${installedRoot}`)
  } catch (error) {
    console.error('vcpkg setup failed:', error.message)
    if (error.stdout) console.error('stdout:', error.stdout)
    if (error.stderr) console.error('stderr:', error.stderr)
    process.exit(1)
  }
}

async function createVcpkgJson() {
  const vcpkgJsonTemplate = fs.readFileSync(
    path.join(moduleRoot, 'vcpkg.template.json'),
    'utf8',
  )
  const nodeOpenSSLVersion = process.versions.openssl.replace('+quic', '')

  // Resolve OpenSSL version against what's available in vcpkg
  let opensslVersion = nodeOpenSSLVersion
  const availableVersions = getAvailableVersions(vcpkgRoot)

  if (availableVersions) {
    const result = findBestVersion(nodeOpenSSLVersion, availableVersions)
    opensslVersion = result.version

    if (!result.isExact) {
      console.warn(
        `WARNING: OpenSSL ${nodeOpenSSLVersion} is not available in vcpkg.`,
      )
      console.warn(`         Using ${opensslVersion} instead.`)
      if (result.message) {
        console.warn(`         ${result.message}`)
      }
    } else {
      console.log(`Using OpenSSL ${opensslVersion} from vcpkg`)
    }
  } else {
    console.warn('WARNING: Could not read vcpkg versions database.')
    console.warn(
      '         Attempting to use exact OpenSSL version from Node.js.',
    )
  }

  let vcpkgJson = vcpkgJsonTemplate
    .replace('$$OPENSSL_VERSION$$', opensslVersion)
    .replace('$$NODE_LIBCURL_VERSION$$', modulePackageJson.version)

  const parsed = JSON.parse(vcpkgJson)
  const curlDep = parsed.dependencies.find((d) => d.name === 'curl')

  // The http3 feature depends on ngtcp2, which requires a QUIC-capable
  // OpenSSL (>= 3.5.0 with enable-quic). Older Node.js versions bundle
  // OpenSSL < 3.5, so building http3 with them would fail at vcpkg compile
  // time (ngtcp2's OpenSSL backend requires SSL_set_quic_tls_cbs, only
  // available in 3.5+). Remove the feature when the resolved OpenSSL version
  // doesn't meet the requirement.
  const [oMajor, oMinor] = opensslVersion.split('.').map(Number)
  const opensslGe350 = oMajor > 3 || (oMajor === 3 && oMinor >= 5)
  if (!opensslGe350 && curlDep) {
    const idx = curlDep.features.indexOf('http3')
    if (idx !== -1) {
      curlDep.features.splice(idx, 1)
      console.log(
        `OpenSSL ${opensslVersion} < 3.5.0: removing http3 feature from vcpkg.json (ngtcp2 requires QUIC-capable OpenSSL)`,
      )
    }
  }

  // Add GSSAPI feature on non-Windows platforms for Kerberos/SPNEGO support.
  // On Windows, SSPI (already included) handles Negotiate authentication.
  if (process.platform !== 'win32') {
    if (curlDep && !curlDep.features.includes('gssapi')) {
      curlDep.features.push('gssapi')
    }
  }

  vcpkgJson = JSON.stringify(parsed, null, 2)

  fs.writeFileSync(path.join(moduleRoot, 'vcpkg.json'), vcpkgJson)
}

setupVcpkg()
