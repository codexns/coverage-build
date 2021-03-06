#!/bin/bash

OPENSSL_VERSION=1.0.2d
PYTHON_VERSION=3.3.5
LIBFFI_VERSION=3.2.1
SQLITE3_VERSION=3081101

CLEAN_SSL=$1

set -e

# Figure out what directory this script is in
SCRIPT="$0"
if [[ $(readlink $SCRIPT) != "" ]]; then
    SCRIPT=$(dirname $SCRIPT)/$(readlink $SCRIPT)
fi
if [[ $0 = ${0%/*} ]]; then
    SCRIPT=$(pwd)/$0
fi
OSX_DIR=$(cd ${SCRIPT%/*} && pwd -P)

DEPS_DIR="${OSX_DIR}/deps"
BUILD_DIR="${OSX_DIR}/py33-x86_64"
STAGING_DIR="$BUILD_DIR/staging"
BIN_DIR="$STAGING_DIR/bin"
TMP_DIR="$BUILD_DIR/tmp"
OUT_DIR="$BUILD_DIR/../../out/py33_osx_x64"

export CPPFLAGS="-I${STAGING_DIR}/include -I${STAGING_DIR}/include/openssl -I$(xcrun --show-sdk-path)/usr/include -I${STAGING_DIR}/lib/libffi-${LIBFFI_VERSION}/include/"
export CFLAGS="-arch x86_64 -mmacosx-version-min=10.7"
export LDFLAGS="-arch x86_64 -mmacosx-version-min=10.7 -L${STAGING_DIR}/lib"

mkdir -p $DEPS_DIR
mkdir -p $BUILD_DIR
mkdir -p $STAGING_DIR

LIBFFI_DIR="${DEPS_DIR}/libffi-$LIBFFI_VERSION"
LIBFFI_BUILD_DIR="${BUILD_DIR}/libffi-$LIBFFI_VERSION"

OPENSSL_DIR="${DEPS_DIR}/openssl-$OPENSSL_VERSION"
OPENSSL_BUILD_DIR="${BUILD_DIR}/openssl-$OPENSSL_VERSION"

SQLITE3_DIR="${DEPS_DIR}/sqlite-amalgamation-$SQLITE3_VERSION"
SQLITE3_BUILD_DIR="${BUILD_DIR}/sqlite-amalgamation-$SQLITE3_VERSION"

PYTHON_DIR="${DEPS_DIR}/Python-$PYTHON_VERSION"
PYTHON_BUILD_DIR="${BUILD_DIR}/Python-$PYTHON_VERSION"


if [[ ! -e $SQLITE3_DIR ]]; then
    cd $DEPS_DIR
    curl -O --location "https://www.sqlite.org/2015/sqlite-amalgamation-$SQLITE3_VERSION.zip"
    unzip sqlite-amalgamation-$SQLITE3_VERSION.zip
    rm sqlite-amalgamation-$SQLITE3_VERSION.zip
    cd $OSX_DIR
fi

if [[ -e $SQLITE3_BUILD_DIR ]]; then
    rm -R $SQLITE3_BUILD_DIR
fi
cp -R $SQLITE3_DIR $BUILD_DIR

cd $SQLITE3_BUILD_DIR

gcc sqlite3.c -c -o sqlite3.o
gcc shell.c -c -o shell.o
ar rcs sqlite3.a sqlite3.o shell.o

cd $OSX_DIR


if [[ ! -e $OPENSSL_BUILD_DIR ]] || [[ $CLEAN_SSL != "" ]]; then
    if [[ ! -e $OPENSSL_DIR ]]; then
        cd $DEPS_DIR
        curl -O --location "http://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz"
        tar xvfz openssl-$OPENSSL_VERSION.tar.gz
        rm openssl-$OPENSSL_VERSION.tar.gz
        cd $OSX_DIR
    fi

    if [[ -e $OPENSSL_BUILD_DIR ]]; then
        rm -R $OPENSSL_BUILD_DIR
    fi
    cp -R $OPENSSL_DIR $BUILD_DIR

    cd $OPENSSL_BUILD_DIR

    CC=gcc ./Configure darwin64-x86_64-cc enable-static-engine no-md2 no-rc5 no-ssl2 --prefix=$STAGING_DIR
    make depend
    make
    make install

    cd $OSX_DIR
fi


if [[ ! -e $LIBFFI_DIR ]]; then
    cd $DEPS_DIR
    curl -O --location "ftp://sourceware.org/pub/libffi/libffi-$LIBFFI_VERSION.tar.gz"
    tar xvfz libffi-$LIBFFI_VERSION.tar.gz
    rm libffi-$LIBFFI_VERSION.tar.gz
    cd $OSX_DIR
fi

if [[ -e $LIBFFI_BUILD_DIR ]]; then
    rm -R $LIBFFI_BUILD_DIR
fi
cp -R $LIBFFI_DIR $BUILD_DIR

cd $LIBFFI_BUILD_DIR
./configure --disable-shared --prefix=${STAGING_DIR} CFLAGS=-fPIC
make
make install

cd $OSX_DIR


export PKG_CONFIG_PATH="$STAGING_DIR/lib/pkgconfig:$PKG_CONFIG_PATH"


if [[ ! -e $PYTHON_DIR ]]; then
    cd $DEPS_DIR
    curl -O --location "https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION.tgz"
    tar xvfz Python-$PYTHON_VERSION.tgz
    rm Python-$PYTHON_VERSION.tgz
    cd ..
fi

if [[ -e $PYTHON_BUILD_DIR ]]; then
    rm -R $PYTHON_BUILD_DIR
fi
cp -R $PYTHON_DIR $BUILD_DIR

cd $PYTHON_BUILD_DIR

echo "*shared*
_sqlite3 _sqlite/module.c _sqlite/cache.c _sqlite/connection.c _sqlite/cursor.c _sqlite/microprotocols.c _sqlite/prepare_protocol.c _sqlite/row.c _sqlite/statement.c _sqlite/util.c -I$SQLITE3_BUILD_DIR -I$PYTHON_BUILD_DIR -I$PYTHON_BUILD_DIR/Include -I$PYTHON_BUILD_DIR/Modules/_sqlite $SQLITE3_BUILD_DIR/sqlite3.a
" > Modules/Setup.local

patch -p1 <<EOF
--- a/Modules/_sqlite/module.c  2014-01-21 22:00:03.000000000 -0500
+++ b/Modules/_sqlite/module.c  2014-01-21 22:00:21.000000000 -0500
@@ -28,6 +28,9 @@
 #include "prepare_protocol.h"
 #include "microprotocols.h"
 #include "row.h"
+#ifndef MODULE_NAME
+#define MODULE_NAME "_sqlite3"
+#endif
 
 #if SQLITE_VERSION_NUMBER >= 3003003
 #define HAVE_SHARED_CACHE
EOF
patch -p1 <<EOF
--- a/Modules/_sqlite/sqlitecompat.h    2014-01-21 22:00:34.000000000 -0500
+++ b/Modules/_sqlite/sqlitecompat.h    2014-01-21 22:00:54.000000000 -0500
@@ -26,6 +26,10 @@
 #ifndef PYSQLITE_COMPAT_H
 #define PYSQLITE_COMPAT_H
 
+#ifndef MODULE_NAME
+#define MODULE_NAME "_sqlite3"
+#endif
+
 /* define Py_ssize_t for pre-2.5 versions of Python */
 
 #if PY_VERSION_HEX < 0x02050000
EOF
patch -p1 < $OSX_DIR/makesetup.diff

./configure --prefix=$STAGING_DIR
make
make install
cp Modules/_sqlite3module.so $STAGING_DIR/lib/python3.3/lib-dynload/_sqlite3.so

cd $OSX_DIR


cd $DEPS_DIR

if [[ ! -e ./get-pip.py ]]; then
    curl -O --location "https://bootstrap.pypa.io/get-pip.py"
fi

$BIN_DIR/python3.3 ./get-pip.py
if [[ $($BIN_DIR/pip3.3 list | grep coverage) != "" ]]; then
    $BIN_DIR/pip3.3 uninstall -y coverage
fi

rm -Rf $TMP_DIR
$BIN_DIR/pip3.3 install --build $TMP_DIR --no-use-wheel --pre coverage

COVERAGE_VERSION=$($BIN_DIR/pip3.3 show coverage | grep Version | grep -v Metadata-Version | sed 's/Version: //')

rm -Rf $OUT_DIR
mkdir -p $OUT_DIR

cp -R $STAGING_DIR/lib/python3.3/site-packages/coverage $OUT_DIR/

cd $OUT_DIR
zip -r ../coverage-${COVERAGE_VERSION}_py33_osx-x64.zip *
