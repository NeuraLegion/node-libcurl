#!/bin/bash
# <release> <dest_folder>
set -euo pipefail

build_folder=$2/build/$1
curr_dirname=$(dirname "$0")

mkdir -p $build_folder
mkdir -p $2/source

FORCE_REBUILD=${FORCE_REBUILD:-}

# @TODO We are explicitly checking the static lib
if [[ -f $build_folder/lib/libz.a ]] && [[ -z $FORCE_REBUILD || $FORCE_REBUILD != "true" ]]; then
  echo "Skipping rebuild of zlib because lib file already exists"
  exit 0
fi

if [ ! -d $2/source/$1 ]; then
  # zlib version may be in the format 1.2.13.1-motley or 1.3.0.1-motley-788cb3c
  # Strip to: full 4-part (1.3.0.1), then 3-part (1.3.0), then major.minor (1.3)
  git_version_4part=$(echo $1 | sed -E 's/([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+).*/\1/')
  git_version_full=$(echo $1 | sed -E 's/([0-9]+\.[0-9]+\.[0-9]+)[.-].*/\1/')
  git_version_major_minor=$(echo $git_version_full | sed -E 's/([0-9]+\.[0-9]+).*/\1/')

  # If 4-part equals full (i.e. no 4th component), skip the redundant attempt
  if [ "$git_version_4part" = "$git_version_full" ] || [ "$git_version_4part" = "$1" ]; then
    $curr_dirname/download-and-unpack.sh https://github.com/madler/zlib/archive/v$1.tar.gz $2 || \
      $curr_dirname/download-and-unpack.sh https://github.com/madler/zlib/archive/v${git_version_full}.tar.gz $2 || \
      $curr_dirname/download-and-unpack.sh https://github.com/madler/zlib/archive/v${git_version_major_minor}.tar.gz $2
  else
    $curr_dirname/download-and-unpack.sh https://github.com/madler/zlib/archive/v$1.tar.gz $2 || \
      $curr_dirname/download-and-unpack.sh https://github.com/madler/zlib/archive/v${git_version_4part}.tar.gz $2 || \
      $curr_dirname/download-and-unpack.sh https://github.com/madler/zlib/archive/v${git_version_full}.tar.gz $2 || \
      $curr_dirname/download-and-unpack.sh https://github.com/madler/zlib/archive/v${git_version_major_minor}.tar.gz $2
  fi

  ls -al $2/

  if [ -d "$2/zlib-$git_version_4part" ]; then
    mv $2/zlib-$git_version_4part $2/source/$1
  elif [ -d "$2/zlib-$git_version_full" ]; then
    mv $2/zlib-$git_version_full $2/source/$1
  elif [ -d "$2/zlib-$git_version_major_minor" ]; then
    mv $2/zlib-$git_version_major_minor $2/source/$1
  elif [ -d "$2/zlib-$1" ]; then
    mv $2/zlib-$1 $2/source/$1
  else
    echo "Could not find source folder for zlib"
    exit 1
  fi

  cd $2/source/$1
else
  cd $2/source/$1
  make distclean || true;
fi

CFLAGS=${CFLAGS:-}

# Debug
# CFLAGS="$CFLAGS -fPIC" ./configure --prefix=$build_folder --static --debug

# Release - Static
CFLAGS="$CFLAGS -fPIC" ./configure --prefix=$build_folder --static

# Release - Both
# CFLAGS="$CFLAGS -fPIC" ./configure --prefix=$build_folder

make && make install
