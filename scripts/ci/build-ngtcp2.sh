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

# On some distros (e.g. Rocky Linux 8), pkg-config may still resolve system OpenSSL 1.1.1
# even with PKG_CONFIG_PATH set, because the system paths are appended by pkg-config wrappers.
# Pass OPENSSL_CFLAGS and OPENSSL_LIBS explicitly to bypass pkg-config for OpenSSL detection.
if [ -n "${OPENSSL_BUILD_FOLDER:-}" ]; then
  export OPENSSL_CFLAGS="-I$OPENSSL_BUILD_FOLDER/include"
  export OPENSSL_LIBS="-L$OPENSSL_BUILD_FOLDER/lib -lssl -lcrypto"
  export LDFLAGS="-Wl,-rpath,$OPENSSL_BUILD_FOLDER/lib"
fi

# Similarly bypass pkg-config for nghttp3 if available
if [ -n "${NGHTTP3_BUILD_FOLDER:-}" ]; then
  export LIBNGHTTP3_CFLAGS="-I$NGHTTP3_BUILD_FOLDER/include"
  export LIBNGHTTP3_LIBS="-L$NGHTTP3_BUILD_FOLDER/lib -lnghttp3"
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
