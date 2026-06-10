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

# Export PKG_CONFIG_PATH so sub-invocations inside ./configure pick up our custom deps
# (e.g. nghttp3). OpenSSL is handled via OPENSSL_LIBS/OPENSSL_CFLAGS below, which causes
# ngtcp2's PKG_CHECK_MODULES to skip the pkg-config query for OpenSSL entirely — so
# PKG_CONFIG_LIBDIR manipulation is not needed to prevent system OpenSSL from winning.
export PKG_CONFIG_PATH="$PKG_CONFIG_PATH_VALUE"

if [ -n "${OPENSSL_BUILD_FOLDER:-}" ]; then
  export LDFLAGS="-Wl,-rpath,$OPENSSL_BUILD_FOLDER/lib"
  export OPENSSL_CFLAGS="-I$OPENSSL_BUILD_FOLDER/include"
  # When OPENSSL_LIBS / OPENSSL_CFLAGS are set, PKG_CHECK_MODULES honours them and skips
  # the pkg-config query entirely, so the system's OpenSSL (e.g. 1.1.1 on Rocky Linux 8)
  # cannot interfere via the linker search path.
  # On macOS, OpenSSL is a fat (universal) binary; embedding it into a shared library via
  # OPENSSL_LIBS causes ranlib to fail with "bad magic number".
  if [[ "$(uname)" != "Darwin" ]]; then
    export OPENSSL_LIBS="$OPENSSL_BUILD_FOLDER/lib/libssl.a $OPENSSL_BUILD_FOLDER/lib/libcrypto.a -ldl -pthread"
  fi
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
