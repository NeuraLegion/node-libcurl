#!/bin/bash
# <release> <dest_folder>
set -euo pipefail

build_folder=$2/build/$1
curr_dirname=$(dirname "$0")

mkdir -p $build_folder
mkdir -p $2/source

FORCE_REBUILD=${FORCE_REBUILD:-}

# @TODO We are explicitly checking the static lib
if [[ -f $build_folder/lib/libngtcp2.a ]] && [[ -z $FORCE_REBUILD || $FORCE_REBUILD != "true" ]]; then
  echo "Skipping rebuild of ngtcp2 because lib file already exists"
  exit 0
fi

if [ ! -d $2/source/$1 ]; then
  $curr_dirname/download-and-unpack.sh https://github.com/ngtcp2/ngtcp2/releases/download/v$1/ngtcp2-$1.tar.gz $2

  mv $2/ngtcp2-$1 $2/source/$1
  cd $2/source/$1
else
  cd $2/source/$1
  make distclean || true;
fi

CFLAGS=${CFLAGS:-}
export CFLAGS="$CFLAGS -fPIC"

# Build PKG_CONFIG_PATH for dependencies
PKG_CONFIG_PATH_PARTS=()

if [ -n "${OPENSSL_BUILD_FOLDER:-}" ]; then
  PKG_CONFIG_PATH_PARTS+=("$OPENSSL_BUILD_FOLDER/lib/pkgconfig")
fi

if [ -n "${NGHTTP3_BUILD_FOLDER:-}" ]; then
  PKG_CONFIG_PATH_PARTS+=("$NGHTTP3_BUILD_FOLDER/lib/pkgconfig")
fi

# Join array with colons
PKG_CONFIG_PATH_VALUE=$(IFS=:; echo "${PKG_CONFIG_PATH_PARTS[*]}")

# Export PKG_CONFIG_PATH so sub-invocations inside ./configure pick up our custom deps.
export PKG_CONFIG_PATH="$PKG_CONFIG_PATH_VALUE"

# On Rocky Linux 8 (and other distros with pkgconf), PKG_CONFIG_PATH only prepends to the
# default search path — system openssl 1.1.1 from /usr/lib64/pkgconfig still wins.
# PKG_CONFIG_LIBDIR *replaces* the default search path entirely, preventing system packages
# from being found. We include the system path explicitly so other deps still resolve.
SYSTEM_PKG_CONFIG_LIBDIR="${PKG_CONFIG_LIBDIR:-/usr/lib64/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig}"
export PKG_CONFIG_LIBDIR="${PKG_CONFIG_PATH_VALUE}:${SYSTEM_PKG_CONFIG_LIBDIR}"

if [ -n "${OPENSSL_BUILD_FOLDER:-}" ]; then
  export LDFLAGS="-Wl,-rpath,$OPENSSL_BUILD_FOLDER/lib"
  # Force pkg-config to use our static libs directly so the AC_LINK_IFELSE
  # in ngtcp2's configure does not accidentally pick up the system's shared
  # libssl (e.g. OpenSSL 1.1.1 on Rocky Linux 8) via the linker search path.
  # When OPENSSL_LIBS / OPENSSL_CFLAGS are already set in the environment,
  # PKG_CHECK_MODULES honours them and skips the pkg-config query entirely.
  export OPENSSL_LIBS="$OPENSSL_BUILD_FOLDER/lib/libssl.a $OPENSSL_BUILD_FOLDER/lib/libcrypto.a -ldl -pthread"
  export OPENSSL_CFLAGS="-I$OPENSSL_BUILD_FOLDER/include"
fi

# Release - Static
./configure \
  --prefix=$build_folder \
  --enable-lib-only \
  --enable-static \
  --disable-shared \
  --with-openssl \
  --with-libnghttp3

make && make install
