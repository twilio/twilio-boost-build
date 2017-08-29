#!/bin/bash
#===============================================================================
# Filename:  boost.sh
# Author:    Pete Goodliffe
# Copyright: (c) Copyright 2009 Pete Goodliffe
# Licence:   Please feel free to use this, with attribution
# Modified version
#===============================================================================
#
# Builds a Boost framework for iOS, iOS Simulator, tvOS, tvOS Simulator, and OSX.
# Creates a set of universal libraries that can be used on an iOS and in the
# iOS simulator. Then creates a pseudo-framework to make using boost in Xcode
# less painful.
#
# To configure the script, define:
#    BOOST_VERSION:   Which version of Boost to build (e.g. 1.61.0)
#    BOOST_VERSION2:  Same as BOOST_VERSION, but with _ instead of . (e.g. 1_61_0)
#    BOOST_LIBS:      Which Boost libraries to build
#    IOS_SDK_VERSION: iOS SDK version (e.g. 9.0)
#    MIN_IOS_VERSION: Minimum iOS Target Version (e.g. 8.0)
#    OSX_SDK_VERSION: OSX SDK version (e.g. 10.11)
#    MIN_OSX_VERSION: Minimum OS X Target Version (e.g. 10.10)
#
# If a boost tarball (a file named “boost_$BOOST_VERSION2.tar.bz2”) does not
# exist in the current directory, this script will attempt to download the
# version specified by BOOST_VERSION2. You may also manually place a matching 
# tarball in the current directory and the script will use that.
#
#===============================================================================

BOOST_LIBS="atomic chrono container date_time exception filesystem iostreams metaparse program_options random regex serialization system test thread timer"

BUILD_ANDROID=
BUILD_IOS=
BUILD_TVOS=
BUILD_OSX=
BUILD_LINUX=
BUILD_HEADERS=
UNPACK=
CLEAN=
NO_CLEAN=
NO_FRAMEWORK=

BOOST_VERSION=1.64.0
BOOST_VERSION2=1_64_0

BEAST_VERSION=109
BEAST_COMMIT=526ecc5

TWILIO_SUFFIX=

MIN_IOS_VERSION=8.0
IOS_SDK_VERSION=`xcrun --sdk iphoneos --show-sdk-version`

MIN_TVOS_VERSION=9.2
TVOS_SDK_VERSION=`xcrun --sdk appletvos --show-sdk-version`

MIN_OSX_VERSION=10.10
OSX_SDK_VERSION=`xcrun --sdk macosx --show-sdk-version`

OSX_ARCHS="x86_64 i386"
OSX_ARCH_COUNT=0
OSX_ARCH_FLAGS=""
for ARCH in $OSX_ARCHS; do
    OSX_ARCH_FLAGS="$OSX_ARCH_FLAGS -arch $ARCH"
    ((OSX_ARCH_COUNT++))
done

# Applied to all platforms
CXX_FLAGS=""

XCODE_ROOT=`xcode-select -print-path`
COMPILER="$XCODE_ROOT/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++" 

THREADS="-j$(getconf _NPROCESSORS_ONLN)"

CURRENT_DIR=`pwd`
SRCDIR="$CURRENT_DIR/src"
BEAST_DIR="$CURRENT_DIR/src/beast"

IOS_ARM_DEV_CMD="xcrun --sdk iphoneos"
IOS_SIM_DEV_CMD="xcrun --sdk iphonesimulator"
TVOS_ARM_DEV_CMD="xcrun --sdk appletvos"
TVOS_SIM_DEV_CMD="xcrun --sdk appletvsimulator"
OSX_DEV_CMD="xcrun --sdk macosx"

#===============================================================================
# Functions
#===============================================================================

usage()
{
cat << EOF
usage: $0 [{-android,-ios,-tvos,-osx,-linux} ...] options
Build Boost for Android, iOS, iOS Simulator, tvOS, tvOS Simulator, OS X, and Linux
The -ios, -tvos, and -osx options may be specified together.

Examples:
    ./boost.sh -ios -tvos --boost-version 1.56.0
    ./boost.sh -osx --no-framework
    ./boost.sh --clean

OPTIONS:
    -h | --help
        Display these options and exit.

    -android
        Build for the Android platform.

    -ios
        Build for the iOS platform.

    -osx
        Build for the OS X platform.

    -tvos
        Build for the tvOS platform.

    -linux
        Build for the Linux platform.

    -headers
        Package headers.

    --unpack
        Only unpack sources, dont build.

    --boost-version [num]
        Specify which version of Boost to build. Defaults to $BOOST_VERSION.

    --twilio-suffix [sfx]
        Set suffix for the maven package. Defaults to no suffix.

    --boost-libs [libs]
        Specify which libraries to build. Space-separate list.
        Defaults to:
            $BOOST_LIBS
        Boost libraries requiring separate building are:
            - atomic
            - chrono
            - container
            - context
            - coroutine
            - coroutine2
            - date_time
            - exception
            - filesystem
            - graph
            - graph_parallel
            - iostreams
            - locale
            - log
            - math
            - metaparse
            - mpi
            - program_options
            - python
            - random
            - regex
            - serialization
            - signals
            - system
            - test
            - thread
            - timer
            - type_erasure
            - wave

    --ios-sdk [num]
        Specify the iOS SDK version to build with. Defaults to $IOS_SDK_VERSION.

    --min-ios-version [num]
        Specify the minimum iOS version to target.  Defaults to $MIN_IOS_VERSION.

    --tvos-sdk [num]
        Specify the tvOS SDK version to build with. Defaults to $TVOS_SDK_VERSION.

    --min-tvos_version [num]
        Specify the minimum tvOS version to target. Defaults to $MIN_TVOS_VERSION.

    --osx-sdk [num]
        Specify the OS X SDK version to build with. Defaults to $OSX_SDK_VERSION.

    --min-osx-version [num]
        Specify the minimum OS X version to target.  Defaults to $MIN_OSX_VERSION.

    --no-framework
        Do not create the framework.

    --clean
        Just clean up build artifacts, but dont actually build anything.
        (all other parameters are ignored)

    --no-clean
        Do not clean up existing build artifacts before building.

EOF
}

#===============================================================================

parseArgs()
{
    while [ "$1" != "" ]; do
        case $1 in
            -h | --help)
                usage
                exit
                ;;

            -android)
                BUILD_ANDROID=1
                ;;

            -ios)
                BUILD_IOS=1
                ;;

            -tvos)
                BUILD_TVOS=1
                ;;

            -osx)
                BUILD_OSX=1
                ;;

            -linux)
                BUILD_LINUX=1
                ;;

            -headers)
                BUILD_HEADERS=1
                ;;

            --boost-version)
                if [ -n $2 ]; then
                    BOOST_VERSION=$2
                    BOOST_VERSION2="${BOOST_VERSION//./_}"
                    BOOST_TARBALL="$CURRENT_DIR/src/boost_$BOOST_VERSION2.tar.bz2"
                    BOOST_SRC="$SRCDIR/boost/${BOOST_VERSION}"
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --twilio-suffix)
                if [ -n $2 ]; then
                    TWILIO_SUFFIX="$2"
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --boost-libs)
                if [ -n "$2" ]; then
                    BOOST_LIBS="$2"
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --ios-sdk)
                if [ -n $2 ]; then
                    IOS_SDK_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --min-ios-version)
                if [ -n $2 ]; then
                    MIN_IOS_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --tvos-sdk)
                if [ -n $2]; then
                    TVOS_SDK_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --min-tvos-version)
                if [ -n $2]; then
                    MIN_TVOS_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --osx-sdk)
                 if [ -n $2 ]; then
                    OSX_SDK_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --min-osx-version)
                if [ -n $2 ]; then
                    MIN_OSX_VERSION=$2
                    shift
                else
                    missingParameter $1
                fi
                ;;

            --clean)
                CLEAN=1
                ;;

            --no-clean)
                NO_CLEAN=1
                ;;

            --unpack)
                UNPACK=1
                NO_CLEAN=1
                NO_FRAMEWORK=1
                ;;

            --no-framework)
                NO_FRAMEWORK=1
                ;;

            *)
                unknownParameter $1
                ;;
        esac

        shift
    done
}

#===============================================================================

abort()
{
    echo
    echo "Aborted: $@"
    exit 1
}

#===============================================================================

die()
{
    usage
    exit 1
}

#===============================================================================

missingParameter()
{
    echo $1 requires a parameter
    die
}

#===============================================================================

unknownParameter()
{
    if [[ -n $2 &&  $2 != "" ]]; then
        echo Unknown argument \"$2\" for parameter $1.
    else
        echo Unknown argument $1
    fi
    die
}

#===============================================================================

doneSection()
{
    echo
    echo "Done"
    echo "================================================================="
    echo
}

#===============================================================================

cleanup()
{
    echo Cleaning everything

    if [[ -n $BUILD_IOS ]]; then
        rm -r "$BOOST_SRC/iphone-build"
        rm -r "$BOOST_SRC/iphonesim-build"
        rm -r "$IOSOUTPUTDIR"
    fi
    if [[ -n $BUILD_TVOS ]]; then
        rm -r "$BOOST_SRC/appletv-build"
        rm -r "$BOOST_SRC/appletvsim-build"
        rm -r "$TVOSOUTPUTDIR"
    fi
    if [[ -n $BUILD_OSX ]]; then
        rm -r "$BOOST_SRC/osx-build"
        rm -r "$OSXOUTPUTDIR"
    fi

    doneSection
}

#===============================================================================

downloadBoost()
{
    mkdir -p "$(dirname $BOOST_TARBALL)"

    if [ ! -s $BOOST_TARBALL ]; then
        echo "Downloading boost ${BOOST_VERSION}"
        curl -L -o "$BOOST_TARBALL" \
            http://sourceforge.net/projects/boost/files/boost/${BOOST_VERSION}/boost_${BOOST_VERSION2}.tar.bz2/download
        doneSection
    fi
}

#===============================================================================

unpackBoost()
{
    [ -f "$BOOST_TARBALL" ] || abort "Source tarball missing."

    echo Unpacking boost into "$SRCDIR"...

    [ -d $SRCDIR ]    || mkdir -p "$SRCDIR"
    [ -d $BOOST_SRC ] || (
        mkdir -p "$BOOST_SRC"
        tar xfj "$BOOST_TARBALL" --strip-components 1 -C "$BOOST_SRC"

        curl -L -o boost_1_65_0.patch http://www.boost.org/patches/1_65_0/boost_1_65_0.patch || exit 1
        cur_dir=$(pwd)

        cd "$BOOST_SRC"
        patch -p1 < "$cur_dir/boost_1_65_0.patch" || exit 1
    ) || exit 1

    echo "    ...unpacked as $BOOST_SRC"

    doneSection
}

unpackBeast()
{
    [ -d "$BEAST_DIR" ] && return

    echo Cloning Beast into "$BEAST_DIR"...

    git clone git@github.com:boostorg/beast.git "$BEAST_DIR"
    (cd "$BEAST_DIR"; git checkout $BEAST_COMMIT)

    doneSection
}

#===============================================================================

inventMissingHeaders()
{
    # These files are missing in the ARM iPhoneOS SDK, but they are in the simulator.
    # They are supported on the device, so we copy them from x86 SDK to a staging area
    # to use them on ARM, too.
    echo Invent missing headers

    cp "$XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator${IOS_SDK_VERSION}.sdk/usr/include/"{crt_externs,bzlib}.h "$BOOST_SRC"
}

#===============================================================================

updateBoost()
{
    echo Updating boost into $BOOST_SRC...

    if [[ "$1" == "iOS" ]]; then
        cat > "$BOOST_SRC/tools/build/src/user-config.jam" <<EOF
using darwin : ${IOS_SDK_VERSION}~iphone
: $COMPILER -arch armv7 -arch arm64 $EXTRA_IOS_FLAGS
: <striper> <root>$XCODE_ROOT/Platforms/iPhoneOS.platform/Developer
: <architecture>arm <target-os>iphone
;
using darwin : ${IOS_SDK_VERSION}~iphonesim
: $COMPILER -arch i386 -arch x86_64 $EXTRA_IOS_FLAGS
: <striper> <root>$XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer
: <architecture>x86 <target-os>iphone
;
EOF
    fi

    if [[ "$1" == "tvOS" ]]; then
        cat > "$BOOST_SRC/tools/build/src/user-config.jam" <<EOF
using darwin : ${TVOS_SDK_VERSION}~appletv
: $COMPILER -arch arm64 $EXTRA_TVOS_FLAGS -I${XCODE_ROOT}/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS${TVOS_SDK_VERSION}.sdk/usr/include
: <striper> <root>$XCODE_ROOT/Platforms/AppleTVOS.platform/Developer
: <architecture>arm <target-os>iphone
;
using darwin : ${TVOS_SDK_VERSION}~appletvsim
: $COMPILER -arch x86_64 $EXTRA_TVOS_FLAGS -I${XCODE_ROOT}/Platforms/AppleTVSimulator.platform/Developer/SDKs/AppleTVSimulator${TVOS_SDK_VERSION}.sdk/usr/include
: <striper> <root>$XCODE_ROOT/Platforms/AppleTVSimulator.platform/Developer
: <architecture>x86 <target-os>iphone
;
EOF
    fi

    if [[ "$1" == "OSX" ]]; then
        cat > "$BOOST_SRC/tools/build/src/user-config.jam" <<EOF
using darwin : ${OSX_SDK_VERSION}
: $COMPILER $OSX_ARCH_FLAGS $EXTRA_OSX_FLAGS
: <striper> <root>$XCODE_ROOT/Platforms/MacOSX.platform/Developer
: <architecture>x86 <target-os>darwin
;
EOF
    fi

    if [[ "$1" == "Android" ]]; then
        HOSTOS="$(uname | awk '{ print $1}' | tr [:upper:] [:lower:])-" # darwin or linux
        OSARCH="$(uname -m)"

        cat > "$BOOST_SRC/tools/build/src/user-config.jam" <<EOF
using gcc : 4.9~x86
: $ANDROID_NDK_ROOT/toolchains/x86-4.9/prebuilt/$HOSTOS$OSARCH/bin/i686-linux-android-g++ $EXTRA_ANDROID_FLAGS
:
<architecture>x86 <target-os>android
<compileflags>-std=c++11
<compileflags>-DANDROID
<compileflags>-D__ANDROID__
<compileflags>-I$ANDROID_NDK_ROOT/platforms/android-21/arch-x86/usr/include
<compileflags>-I$ANDROID_NDK_ROOT/sources/cxx-stl/llvm-libc++/libcxx/include
<compileflags>-I$ANDROID_NDK_ROOT/sources/cxx-stl/llvm-libc++abi/libcxxabi/include
<compileflags>-I$ANDROID_NDK_ROOT/sources/cxx-stl/../android/support/include
;
using gcc : 4.9~x86_64
: $ANDROID_NDK_ROOT/toolchains/x86_64-4.9/prebuilt/$HOSTOS$OSARCH/bin/x86_64-linux-android-g++ $EXTRA_ANDROID_FLAGS
:
<architecture>x86 <target-os>android
<compileflags>-std=c++11
<compileflags>-DANDROID
<compileflags>-D__ANDROID__
<compileflags>-I$ANDROID_NDK_ROOT/platforms/android-21/arch-x86_64/usr/include
<compileflags>-I$ANDROID_NDK_ROOT/sources/cxx-stl/llvm-libc++/libcxx/include
<compileflags>-I$ANDROID_NDK_ROOT/sources/cxx-stl/llvm-libc++abi/libcxxabi/include
<compileflags>-I$ANDROID_NDK_ROOT/sources/cxx-stl/../android/support/include
;
using gcc : 4.9~arm
: $ANDROID_NDK_ROOT/toolchains/arm-linux-androideabi-4.9/prebuilt/$HOSTOS$OSARCH/bin/arm-linux-androideabi-g++ $EXTRA_ANDROID_FLAGS
:
<architecture>arm <target-os>android
<compileflags>-std=c++11
<compileflags>-fexceptions
<compileflags>-frtti
<compileflags>-fpic
<compileflags>-ffunction-sections
<compileflags>-funwind-tables
<compileflags>-D__ARM_ARCH_5__
<compileflags>-D__ARM_ARCH_5T__
<compileflags>-D__ARM_ARCH_5E__
<compileflags>-D__ARM_ARCH_5TE__
<compileflags>-Wno-psabi
<compileflags>-march=armv5te
<compileflags>-mtune=xscale
<compileflags>-msoft-float
<compileflags>-mthumb
<compileflags>-fomit-frame-pointer
<compileflags>-fno-strict-aliasing
<compileflags>-finline-limit=64
<compileflags>-Wa,--noexecstack
<compileflags>-DANDROID
<compileflags>-D__ANDROID__
<compileflags>-I$ANDROID_NDK_ROOT/platforms/android-21/arch-arm/usr/include
<compileflags>-I$ANDROID_NDK_ROOT/sources/cxx-stl/llvm-libc++/libcxx/include
<compileflags>-I$ANDROID_NDK_ROOT/sources/cxx-stl/llvm-libc++abi/libcxxabi/include
<compileflags>-I$ANDROID_NDK_ROOT/sources/cxx-stl/../android/support/include
# @Moss - Above are the 'oficial' android flags
<compileflags>-fdata-sections
<cxxflags>-D__arm__
<cxxflags>-D_REENTRANT
<cxxflags>-D_GLIBCXX__PTHREADS
;
using gcc : 4.9~arm64
: $ANDROID_NDK_ROOT/toolchains/aarch64-linux-android-4.9/prebuilt/$HOSTOS$OSARCH/bin/aarch64-linux-android-g++ $EXTRA_ANDROID_FLAGS
:
<architecture>arm <target-os>android
<compileflags>-std=c++11
<compileflags>-fpic
<compileflags>-ffunction-sections
<compileflags>-funwind-tables
<compileflags>-fstack-protector-strong
<compileflags>-no-canonical-prefixes
<compileflags>-fomit-frame-pointer
<compileflags>-fstrict-aliasing
<compileflags>-funswitch-loops
<compileflags>-finline-limit=300
<compileflags>-Wa,--noexecstack
<compileflags>-DANDROID
<compileflags>-D__ANDROID__
<compileflags>-I$ANDROID_NDK_ROOT/platforms/android-21/arch-arm64/usr/include
<compileflags>-I$ANDROID_NDK_ROOT/sources/cxx-stl/llvm-libc++/libcxx/include
<compileflags>-I$ANDROID_NDK_ROOT/sources/cxx-stl/llvm-libc++abi/libcxxabi/include
<compileflags>-I$ANDROID_NDK_ROOT/sources/cxx-stl/../android/support/include
# @Moss - Above are the 'oficial' android flags
<compileflags>-fdata-sections
<cxxflags>-D__arm__
<cxxflags>-D_REENTRANT
<cxxflags>-D_GLIBCXX__PTHREADS
;
EOF
    fi

    if [[ "$1" == "Linux" ]]; then
        cat > "$BOOST_SRC/tools/build/src/user-config.jam" <<EOF
using gcc : : g++ $LINUX_ARCH_FLAGS $EXTRA_LINUX_FLAGS
:
<architecture>x86 <target-os>linux
;
EOF
    fi

    doneSection
}

#===============================================================================

bootstrapBoost()
{
    cd $BOOST_SRC
    BOOTSTRAP_LIBS=$BOOST_LIBS
    if [[ "$1" == "tvOS" ]]; then
        # Boost Test makes a call that is not available on tvOS (as of 1.61.0)
        # If we're bootstraping for tvOS, just remove the test library
        BOOTSTRAP_LIBS=$(echo $BOOTSTRAP_LIBS | sed -e "s/test//g")
    fi

    BOOST_LIBS_COMMA=$(echo $BOOTSTRAP_LIBS | sed -e "s/ /,/g")
    echo "Bootstrapping for $1 (with libs $BOOST_LIBS_COMMA)"
    ./bootstrap.sh --with-libraries=$BOOST_LIBS_COMMA

    doneSection
}

#===============================================================================

buildBoost_Android()
{
    cd "$BOOST_SRC"
    mkdir -p $ANDROIDOUTPUTDIR

    if [[ -z "$ANDROID_NDK_ROOT" ]]; then
        echo "Must specify ANDROID_NDK_ROOT"
        exit 1
    fi

    export NO_BZIP2=1

    # build libicu if locale requested but not provided
    # if echo $LIBRARIES | grep locale; then
    #   if [ -e libiconv-libicu-android ]; then
    #     echo "ICONV and ICU already compiled"
    #   else
    #     echo "boost_locale selected - compiling ICONV and ICU"
    #     git clone https://github.com/pelya/libiconv-libicu-android.git
    #     cd libiconv-libicu-android
    #     ./build.sh || exit 1
    #     cd ..
    #   fi
    # fi

    echo Building Boost for Android Emulator

    for VARIANT in debug release; do
        ./b2 $THREADS --build-dir=android-build --stagedir=android-build/stage \
            --prefix="$OUTPUT_DIR" \
            --libdir="$ANDROIDOUTPUTDIR/lib/$VARIANT/x86" toolset=gcc-4.9~x86 \
            architecture=x86 target-os=android define=_LITTLE_ENDIAN \
            address-model=32 variant=$VARIANT \
            link=static threading=multi install >> "${ANDROIDOUTPUTDIR}/android-build.log" 2>&1
        if [ $? != 0 ]; then echo "Error staging Android. Check log."; exit 1; fi
    done

    doneSection

    for VARIANT in debug release; do
        ./b2 $THREADS --build-dir=android-build --stagedir=android-build/stage \
            --prefix="$OUTPUT_DIR" \
            --libdir="$ANDROIDOUTPUTDIR/lib/$VARIANT/x86_64" toolset=gcc-4.9~x86_64 \
            architecture=x86 target-os=android define=_LITTLE_ENDIAN \
            address-model=64 variant=$VARIANT \
            link=static threading=multi install >> "${ANDROIDOUTPUTDIR}/android-build.log" 2>&1
        if [ $? != 0 ]; then echo "Error staging Android. Check log."; exit 1; fi
    done

    doneSection

    echo Building Boost for Android

    for VARIANT in debug release; do
        ./b2 $THREADS --build-dir=android-build --stagedir=android-build/stage \
            --prefix="$OUTPUT_DIR" \
            --libdir="$ANDROIDOUTPUTDIR/lib/$VARIANT/armeabi-v7a" toolset=gcc-4.9~arm \
            architecture=arm target-os=android \
            address-model=32 variant=$VARIANT \
            link=static threading=multi install >> "${ANDROIDOUTPUTDIR}/android-build.log" 2>&1
        if [ $? != 0 ]; then echo "Error installing Android. Check log."; exit 1; fi
    done

    doneSection

    for VARIANT in debug release; do
        ./b2 $THREADS --build-dir=android-build --stagedir=android-build/stage \
            --prefix="$OUTPUT_DIR" \
            --libdir="$ANDROIDOUTPUTDIR/lib/$VARIANT/arm64-v8a" toolset=gcc-4.9~arm64 \
            architecture=arm target-os=android \
            address-model=64 variant=$VARIANT \
            link=static threading=multi install >> "${ANDROIDOUTPUTDIR}/android-build.log" 2>&1
        if [ $? != 0 ]; then echo "Error installing Android. Check log."; exit 1; fi
    done

    doneSection
}

#===============================================================================

buildBoost_iOS()
{
    cd "$BOOST_SRC"
    mkdir -p $IOSOUTPUTDIR

    echo Building Boost for iPhone

    for VARIANT in debug release; do
        ./b2 $THREADS --build-dir=iphone-build --stagedir=iphone-build/stage \
            --prefix="$OUTPUT_DIR" \
            --libdir="$IOSOUTPUTDIR/lib/$VARIANT/fat-arm" \
            variant=$VARIANT \
            toolset=darwin cxxflags="${CXX_FLAGS} -std=c++11 -stdlib=libc++" architecture=arm \
            target-os=iphone macosx-version=iphone-${IOS_SDK_VERSION} define=_LITTLE_ENDIAN \
            link=static threading=multi install >> "${IOSOUTPUTDIR}/iphone-build.log" 2>&1
        if [ $? != 0 ]; then echo "Error staging iPhone. Check log."; exit 1; fi
    done

    doneSection

    echo Building Boost for iPhoneSimulator

    for VARIANT in debug release; do
        ./b2 $THREADS --build-dir=iphonesim-build --stagedir=iphonesim-build/stage \
            --prefix="$OUTPUT_DIR" \
            --libdir="$IOSOUTPUTDIR/lib/$VARIANT/fat-x86" \
            variant=$VARIANT \
            toolset=darwin-${IOS_SDK_VERSION}~iphonesim cxxflags="${CXX_FLAGS} -std=c++11 -stdlib=libc++" architecture=x86 \
            target-os=iphone macosx-version=iphonesim-${IOS_SDK_VERSION} \
            link=static threading=multi install >> "${IOSOUTPUTDIR}/iphone-build.log" 2>&1
        if [ $? != 0 ]; then echo "Error staging iPhoneSimulator. Check log."; exit 1; fi
    done

    doneSection
}

#===============================================================================

buildBoost_tvOS()
{
    cd "$BOOST_SRC"
    mkdir -p $TVOSOUTPUTDIR

    for VARIANT in debug release; do
        echo Building $VARIANT Boost for AppleTV
        ./b2 $THREADS --build-dir=appletv-build --stagedir=appletv-build/stage \
            --prefix="$OUTPUT_DIR" \
            --libdir="$TVOSOUTPUTDIR/lib/$VARIANT/fat-arm" \
            variant=$VARIANT \
            toolset=darwin-${TVOS_SDK_VERSION}~appletv \
            cxxflags="${CXX_FLAGS} -std=c++11 -stdlib=libc++" architecture=arm target-os=iphone define=_LITTLE_ENDIAN \
            link=static threading=multi install >> "${TVOSOUTPUTDIR}/tvos-build.log" 2>&1
        if [ $? != 0 ]; then echo "Error staging AppleTV. Check log."; exit 1; fi
    done

    doneSection

    for VARIANT in debug release; do
        echo Building $VARIANT Boost for AppleTVSimulator
        ./b2 $THREADS --build-dir=appletv-build --stagedir=appletvsim-build/stage \
            --prefix="$OUTPUT_DIR" \
            --libdir="$TVOSOUTPUTDIR/lib/$VARIANT/fat-x86" \
            variant=$VARIANT \
            toolset=darwin-${TVOS_SDK_VERSION}~appletvsim architecture=x86 \
            cxxflags="${CXX_FLAGS} -std=c++11 -stdlib=libc++" target-os=iphone \
            link=static threading=multi install >> "${TVOSOUTPUTDIR}/tvos-build.log" 2>&1
        if [ $? != 0 ]; then echo "Error staging AppleTVSimulator. Check log."; exit 1; fi
    done

    doneSection
}

#===============================================================================

buildBoost_OSX()
{
    cd "$BOOST_SRC"
    mkdir -p $OSXOUTPUTDIR

    for VARIANT in debug release; do
        echo Building $VARIANT Boost for OSX
        ./b2 $THREADS --build-dir=osx-build --stagedir=osx-build/stage toolset=clang \
            --prefix="$OUTPUT_DIR" \
            --libdir="$OSXOUTPUTDIR/lib/$VARIANT/x86_64" \
            variant=$VARIANT \
            cxxflags="${CXX_FLAGS} -std=c++11 -stdlib=libc++ ${OSX_ARCH_FLAGS}" \
            linkflags="-stdlib=libc++" link=static threading=multi \
            macosx-version=${OSX_SDK_VERSION} install >> "${OSXOUTPUTDIR}/osx-build.log" 2>&1
        if [ $? != 0 ]; then echo "Error staging OSX. Check log."; exit 1; fi
    done

    doneSection
}

#===============================================================================

buildBoost_Linux()
{
    cd "$BOOST_SRC"
    mkdir -p $LINUXOUTPUTDIR

    for VARIANT in debug release; do
        echo Building $VARIANT 64-bit Boost for Linux
        ./b2 $THREADS --build-dir=linux-build --stagedir=linux-build/stage toolset=gcc \
            --prefix="$OUTPUT_DIR" \
            --libdir="$LINUXOUTPUTDIR/lib/$VARIANT/x86_64" \
            variant=$VARIANT address-model=64 \
            cxxflags="${CXX_FLAGS} -std=c++11" \
            link=static threading=multi \
            install >> "${LINUXOUTPUTDIR}/linux-build.log" 2>&1
        if [ $? != 0 ]; then echo "Error staging Linux. Check log."; exit 1; fi
    done

    for VARIANT in debug release; do
        echo Building $VARIANT 32-bit Boost for Linux
        ./b2 $THREADS --build-dir=linux-build --stagedir=linux-build/stage toolset=clang \
            --prefix="$OUTPUT_DIR" \
            --libdir="$LINUXOUTPUTDIR/lib/$VARIANT/x86" \
            variant=$VARIANT address-model=32 \
            cxxflags="${CXX_FLAGS} -std=c++11" \
            link=static threading=multi \
            install >> "${LINUXOUTPUTDIR}/linux-build.log" 2>&1
        if [ $? != 0 ]; then echo "Error staging Linux. Check log."; exit 1; fi
    done

    doneSection
}

#===============================================================================

packageHeaders()
{
    BUILDDIR="$CURRENT_DIR/target/distributions"
    mkdir -p "${BUILDDIR}"
    mkdir -p "${OUTPUT_DIR}/include/boost/"
    mkdir -p "${OUTPUT_DIR}/include/beast/"

    echo Packaging Boost headers

    cp -rf $SRCDIR/boost/$BOOST_VERSION/boost/* $OUTPUT_DIR/include/boost/ || exit 1

    (cd $OUTPUT_DIR; tar cvjf "$BUILDDIR/boost-headers-${BOOST_VERSION}${TWILIO_SUFFIX}-all.tar.bz2" include/boost/*)

    echo Packaging Beast headers

    cp -rf $SRCDIR/beast/include/beast/* $OUTPUT_DIR/include/beast/ || exit 1
    cp -rf $SRCDIR/beast/extras/beast/* $OUTPUT_DIR/include/beast/ || exit 1

    (cd $OUTPUT_DIR; tar cvjf "$BUILDDIR/beast-headers-${BEAST_VERSION}${TWILIO_SUFFIX}-all.tar.bz2" include/beast/*)
}

#===============================================================================

packageLibEntry()
{
    BUILDDIR="$CURRENT_DIR/target/distributions"
    mkdir -p "${BUILDDIR}"

    DIR="$1"
    NAME="$2"

    echo Packaging boost-$NAME...

    if [[ -z "$3" ]]; then
        PATTERN="-name *libboost_${NAME}*"
    else
        PATTERN="-name NOTMATCHED"
        for PAT in $3; do
            PATTERN="$PATTERN -o -name *libboost_${PAT}*"
        done
    fi

    (cd $OUTPUT_DIR/$DIR; find lib -type f $PATTERN | tar cvjf "${BUILDDIR}/boost-${NAME}-${BOOST_VERSION}${TWILIO_SUFFIX}-${DIR}.tar.bz2" -T -)
}

packageLibSet()
{
    echo Packaging Boost libraries...
    DIR=$1
    packageLibEntry $DIR atomic
    packageLibEntry $DIR chrono
    packageLibEntry $DIR container
    packageLibEntry $DIR date_time
    packageLibEntry $DIR exception
    packageLibEntry $DIR filesystem
    packageLibEntry $DIR iostreams
    packageLibEntry $DIR metaparse
    packageLibEntry $DIR program_options
    packageLibEntry $DIR random
    packageLibEntry $DIR regex
    packageLibEntry $DIR serialization "serialization wserialization"
    packageLibEntry $DIR system
    packageLibEntry $DIR test "prg_exec_monitor test_exec_monitor unit_test_framework"
    packageLibEntry $DIR thread
    packageLibEntry $DIR timer
}


packageLibs()
{
    if [[ -n "$BUILD_ANDROID" ]]; then
        packageLibSet "android"
    fi

    if [[ -n "$BUILD_IOS" ]]; then
        packageLibSet "ios"
    fi

    if [[ -n "$BUILD_TVOS" ]]; then
        packageLibSet "tvos"
    fi

    if [[ -n "$BUILD_OSX" ]]; then
        packageLibSet "osx"
    fi

    if [[ -n "$BUILD_LINUX" ]]; then
        packageLibSet "linux"
    fi
}

#===============================================================================

# Uses maven, but see
# http://stackoverflow.com/questions/4029532/upload-artifacts-to-nexus-without-maven
# for how to do it using plain curl...
# 
deployFile()
{
    ARTIFACT=$1
    FILE=$2
    CLASSIFIER=$3
    VERSION=$4

    mvn deploy:deploy-file \
        -Durl=$REPO_URL \
        -DrepositoryId=$REPO_ID \
        -DgroupId=org.boost \
        -DartifactId=$ARTIFACT \
        -Dclassifier=$CLASSIFIER \
        -Dversion=$VERSION \
        -DgeneratePom=true \
        -Dpackaging=tar.bz2 \
        -Dfile=$FILE
}

deployToNexus()
{
    BUILDDIR="$CURRENT_DIR/target/distributions"

    if [[ -n "$BUILD_HEADERS" ]]; then
        deployFile boost-headers "${BUILDDIR}/boost-headers-${BOOST_VERSION}${TWILIO_SUFFIX}-all.tar.bz2" all ${BOOST_VERSION}${TWILIO_SUFFIX}
        deployFile beast-headers "${BUILDDIR}/beast-headers-${BEAST_VERSION}${TWILIO_SUFFIX}-all.tar.bz2" all ${BEAST_VERSION}${TWILIO_SUFFIX}
    fi

    if [[ -n "$BUILD_ANDROID" ]]; then
        PLAT="android"
    fi
    if [[ -n "$BUILD_IOS" ]]; then
        PLAT="ios"
    fi
    if [[ -n "$BUILD_OSX" ]]; then
        PLAT="osx"
    fi
    if [[ -n "$BUILD_LINUX" ]]; then
        PLAT="linux"
    fi

    for lib in $BOOST_LIBS; do
        deployFile boost-${lib} "${BUILDDIR}/boost-${lib}-${BOOST_VERSION}${TWILIO_SUFFIX}-${PLAT}.tar.bz2" ${PLAT} ${BOOST_VERSION}${TWILIO_SUFFIX}
    done
}

#===============================================================================

unpackArchive()
{
    BUILDDIR="$1"
    LIBNAME="$2"

    echo "Unpacking $BUILDDIR/$LIBNAME"

    if [[ -d "$BUILDDIR/$LIBNAME" ]]; then 
        cd "$BUILDDIR/$LIBNAME"
        rm *.o
        rm *.SYMDEF*
    else
        mkdir -p "$BUILDDIR/$LIBNAME"
    fi

    (
        cd "$BUILDDIR/$NAME"; ar -x "../../libboost_$NAME.a";
        for FILE in *.o; do
            NEW_FILE="${NAME}_${FILE}"
            mv "$FILE" "$NEW_FILE"
        done
    )
}

#===============================================================================

scrunchAllLibsTogetherInOneLibPerPlatform()
{
    cd "$BOOST_SRC"

    if [[ -n $BUILD_IOS ]]; then
        # iOS Device
        mkdir -p "$IOSBUILDDIR/armv7/obj"
        mkdir -p "$IOSBUILDDIR/arm64/obj"

        # iOS Simulator
        mkdir -p "$IOSBUILDDIR/i386/obj"
        mkdir -p "$IOSBUILDDIR/x86_64/obj"
    fi

    if [[ -n $BUILD_TVOS ]]; then
        # tvOS Device
        mkdir -p "$TVOSBUILDDIR/arm64/obj"

        # tvOS Simulator
        mkdir -p "$TVOSBUILDDIR/x86_64/obj"
    fi

    if [[ -n $BUILD_OSX ]]; then
        # OSX
        for ARCH in $OSX_ARCHS; do
            mkdir -p "$OSXBUILDDIR/$ARCH/obj"
        done
    fi

    ALL_LIBS=""

    echo Splitting all existing fat binaries...

    for NAME in $BOOST_LIBS; do
        if [ "$NAME" == "test" ]; then
            NAME="unit_test_framework"
        fi

        ALL_LIBS="$ALL_LIBS libboost_$NAME.a"

        if [[ -n $BUILD_IOS ]]; then
            $IOS_ARM_DEV_CMD lipo "iphone-build/stage/lib/libboost_$NAME.a" \
                -thin armv7 -o "$IOSBUILDDIR/armv7/libboost_$NAME.a"
            $IOS_ARM_DEV_CMD lipo "iphone-build/stage/lib/libboost_$NAME.a" \
                -thin arm64 -o "$IOSBUILDDIR/arm64/libboost_$NAME.a"

            $IOS_SIM_DEV_CMD lipo "iphonesim-build/stage/lib/libboost_$NAME.a" \
                -thin i386 -o "$IOSBUILDDIR/i386/libboost_$NAME.a"
            $IOS_SIM_DEV_CMD lipo "iphonesim-build/stage/lib/libboost_$NAME.a" \
                -thin x86_64 -o "$IOSBUILDDIR/x86_64/libboost_$NAME.a"
        fi

        if [[ -n $BUILD_TVOS ]]; then
            $TVOS_ARM_DEV_CMD lipo "appletv-build/stage/lib/libboost_$NAME.a" \
                -thin arm64 -o "$TVOSBUILDDIR/arm64/libboost_$NAME.a"

            $TVOS_SIM_DEV_CMD lipo "appletvsim-build/stage/lib/libboost_$NAME.a" \
                -thin x86_64 -o "$TVOSBUILDDIR/x86_64/libboost_$NAME.a"
        fi

        if [[ -n $BUILD_OSX ]]; then
            if (( $OSX_ARCH_COUNT == 1 )); then
                cp "osx-build/stage/lib/libboost_$NAME.a" \
                    "$OSXBUILDDIR/$ARCH/libboost_$NAME.a"
            else
                for ARCH in $OSX_ARCHS; do
                    $OSX_DEV_CMD lipo "osx-build/stage/lib/libboost_$NAME.a" \
                        -thin $ARCH -o "$OSXBUILDDIR/$ARCH/libboost_$NAME.a"
                done
            fi
        fi
    done

    echo "Decomposing each architecture's .a files"

    for NAME in $BOOST_LIBS; do
        if [ "$NAME" == "test" ]; then
            NAME="unit_test_framework"
        fi

        echo "Decomposing libboost_${NAME}.a"
        if [[ -n $BUILD_IOS ]]; then
            unpackArchive "$IOSBUILDDIR/armv7/obj" $NAME
            unpackArchive "$IOSBUILDDIR/arm64/obj" $NAME
            unpackArchive "$IOSBUILDDIR/i386/obj" $NAME
            unpackArchive "$IOSBUILDDIR/x86_64/obj" $NAME
        fi

        if [[ -n $BUILD_TVOS ]]; then
            unpackArchive "$TVOSBUILDDIR/arm64/obj" $NAME
            unpackArchive "$TVOSBUILDDIR/x86_64/obj" $NAME
        fi

        if [[ -n $BUILD_OSX ]]; then
            for ARCH in $OSX_ARCHS; do
                unpackArchive "$OSXBUILDDIR/$ARCH/obj" $NAME
            done
        fi
    done

    echo "Linking each architecture into an uberlib ($ALL_LIBS => libboost.a )"
    if [[ -n $BUILD_IOS ]]; then
        cd "$IOSBUILDDIR"
        rm */libboost.a
    fi
    if [[ -n $BUILD_TVOS ]]; then
        cd "$TVOSBUILDDIR"
        rm */libboost.a
    fi
    if [[ -n $BUILD_OSX ]]; then
        for ARCH in $OSX_ARCHS; do
            rm "$OSXBUILDDIR/$ARCH/libboost.a"
        done
    fi

    for NAME in $BOOST_LIBS; do
        if [ "$NAME" == "test" ]; then
            NAME="unit_test_framework"
        fi

        echo "Archiving $NAME"

        # The obj/$NAME/*.o below should all be quotet, but I couldn't figure out how to do that elegantly.
        # Boost lib names probably won't contain non-word characters any time soon, though. ;) - Jan

        if [[ -n $BUILD_IOS ]]; then
            echo ...armv7
            (cd "$IOSBUILDDIR/armv7"; $IOS_ARM_DEV_CMD ar crus libboost.a obj/$NAME/*.o; )
            echo ...arm64
            (cd "$IOSBUILDDIR/arm64"; $IOS_ARM_DEV_CMD ar crus libboost.a obj/$NAME/*.o; )

            echo ...i386
            (cd "$IOSBUILDDIR/i386";  $IOS_SIM_DEV_CMD ar crus libboost.a obj/$NAME/*.o; )
            echo ...x86_64
            (cd "$IOSBUILDDIR/x86_64";  $IOS_SIM_DEV_CMD ar crus libboost.a obj/$NAME/*.o; )
        fi

        if [[ -n $BUILD_TVOS ]]; then
            echo ...tvOS-arm64
            (cd "$TVOSBUILDDIR/arm64"; $TVOS_ARM_DEV_CMD ar crus libboost.a obj/$NAME/*.o; )
            echo ...tvOS-x86_64
            (cd "$TVOSBUILDDIR/x86_64";  $TVOS_SIM_DEV_CMD ar crus libboost.a obj/$NAME/*.o; )
        fi

        if [[ -n $BUILD_OSX ]]; then
            for ARCH in $OSX_ARCHS; do
                echo ...osx-$ARCH
                (cd "$OSXBUILDDIR/$ARCH";  $OSX_DEV_CMD ar crus libboost.a obj/$NAME/*.o; )
            done
        fi
    done
}

#===============================================================================

buildFramework()
{
    : ${1:?}
    FRAMEWORKDIR="$1"
    BUILDDIR="$2/build"
    PREFIXDIR="$2/prefix"

    VERSION_TYPE=Alpha
    FRAMEWORK_NAME=boost
    FRAMEWORK_VERSION=A

    FRAMEWORK_CURRENT_VERSION="$BOOST_VERSION"
    FRAMEWORK_COMPATIBILITY_VERSION="$BOOST_VERSION"

    FRAMEWORK_BUNDLE="$FRAMEWORKDIR/$FRAMEWORK_NAME.framework"
    echo "Framework: Building $FRAMEWORK_BUNDLE from $BUILDDIR..."

    rm -rf "$FRAMEWORK_BUNDLE"

    echo "Framework: Setting up directories..."
    mkdir -p "$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Resources"
    mkdir -p "$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Headers"
    mkdir -p "$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Documentation"

    echo "Framework: Creating symlinks..."
    ln -s "$FRAMEWORK_VERSION"               "$FRAMEWORK_BUNDLE/Versions/Current"
    ln -s "Versions/Current/Headers"         "$FRAMEWORK_BUNDLE/Headers"
    ln -s "Versions/Current/Resources"       "$FRAMEWORK_BUNDLE/Resources"
    ln -s "Versions/Current/Documentation"   "$FRAMEWORK_BUNDLE/Documentation"
    ln -s "Versions/Current/$FRAMEWORK_NAME" "$FRAMEWORK_BUNDLE/$FRAMEWORK_NAME"

    FRAMEWORK_INSTALL_NAME="$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/$FRAMEWORK_NAME"

    echo "Lipoing library into $FRAMEWORK_INSTALL_NAME..."
    cd "$BUILDDIR"
    if [[ -n $BUILD_IOS ]]; then
        $IOS_ARM_DEV_CMD lipo -create */libboost.a -o "$FRAMEWORK_INSTALL_NAME" || abort "Lipo $1 failed"
    fi
    if [[ -n $BUILD_TVOS ]]; then
        $TVOS_ARM_DEV_CMD lipo -create */libboost.a -o "$FRAMEWORK_INSTALL_NAME" || abort "Lipo $1 failed"
    fi
    if [[ -n $BUILD_OSX ]]; then
        $OSX_DEV_CMD lipo -create */libboost.a -o "$FRAMEWORK_INSTALL_NAME" || abort "Lipo $1 failed"
    fi

    echo "Framework: Copying includes..."
    cd "$PREFIXDIR/include/boost"
    cp -r * "$FRAMEWORK_BUNDLE/Headers/"

    echo "Framework: Creating plist..."
    cat > "$FRAMEWORK_BUNDLE/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>CFBundleExecutable</key>
<string>${FRAMEWORK_NAME}</string>
<key>CFBundleIdentifier</key>
<string>org.boost</string>
<key>CFBundleInfoDictionaryVersion</key>
<string>6.0</string>
<key>CFBundlePackageType</key>
<string>FMWK</string>
<key>CFBundleSignature</key>
<string>????</string>
<key>CFBundleVersion</key>
<string>${FRAMEWORK_CURRENT_VERSION}</string>
</dict>
</plist>
EOF

    doneSection
}

#===============================================================================
# Execution starts here
#===============================================================================

parseArgs "$@"

if [[ -z $UNPACK && -z $BUILD_IOS && -z $BUILD_TVOS && -z $BUILD_OSX && -z $BUILD_ANDROID && -z $BUILD_LINUX && -z $BUILD_HEADERS ]]; then
    BUILD_ANDROID=1
    BUILD_IOS=1
    BUILD_TVOS=1
    BUILD_OSX=1
    BUILD_LINUX=1
    BUILD_HEADERS=1
fi

if [[ -n $UNPACK ]]; then
    BUILD_ANDROID=
    BUILD_IOS=
    BUILD_TVOS=
    BUILD_OSX=
    BUILD_LINUX=
    BUILD_HEADERS=
fi

# The EXTRA_FLAGS definition works around a thread race issue in
# shared_ptr. I encountered this historically and have not verified that
# the fix is no longer required. Without using the posix thread primitives
# an invalid compare-and-swap ARM instruction (non-thread-safe) was used for the
# shared_ptr use count causing nasty and subtle bugs.
#
# Should perhaps also consider/use instead: -BOOST_SP_USE_PTHREADS

# Todo: perhaps add these
# -DBOOST_SP_USE_SPINLOCK
# -stdlib=libc++

# Must set these after parseArgs to fill in overriden values
# Todo: -g -DNDEBUG are for debug builds only...
EXTRA_FLAGS="-DBOOST_AC_USE_PTHREADS -DBOOST_SP_USE_PTHREADS \
    -fvisibility=hidden -fvisibility-inlines-hidden -Wno-unused-local-typedef"
EXTRA_IOS_FLAGS="$EXTRA_FLAGS -fembed-bitcode -mios-version-min=$MIN_IOS_VERSION"
EXTRA_TVOS_FLAGS="$EXTRA_FLAGS -fembed-bitcode -mtvos-version-min=$MIN_TVOS_VERSION"
EXTRA_OSX_FLAGS="$EXTRA_FLAGS -mmacosx-version-min=$MIN_OSX_VERSION"
EXTRA_ANDROID_FLAGS="$EXTRA_FLAGS"
# These linux flags are adopted from RTD BuildScripts/CMake/Toolchain-Linux.cmake
# See there for details.
EXTRA_LINUX_FLAGS="$EXTRA_FLAGS -D_GLIBCXX_USE_CXX11_ABI=0"

BOOST_TARBALL="$CURRENT_DIR/src/boost_$BOOST_VERSION2.tar.bz2"
BOOST_SRC="$SRCDIR/boost/${BOOST_VERSION}"
OUTPUT_DIR="$CURRENT_DIR/target/outputs/boost/$BOOST_VERSION"
IOSOUTPUTDIR="$OUTPUT_DIR/ios"
TVOSOUTPUTDIR="$OUTPUT_DIR/tvos"
OSXOUTPUTDIR="$OUTPUT_DIR/osx"
ANDROIDOUTPUTDIR="$OUTPUT_DIR/android"
LINUXOUTPUTDIR="$OUTPUT_DIR/linux"
IOSBUILDDIR="$IOSOUTPUTDIR/build"
TVOSBUILDDIR="$TVOSOUTPUTDIR/build"
OSXBUILDDIR="$OSXOUTPUTDIR/build"
ANDROIDBUILDDIR="$ANDROIDOUTPUTDIR/build"
LINUXBUILDDIR="$LINUXOUTPUTDIR/build"
IOSLOG="> $IOSOUTPUTDIR/iphone.log 2>&1"
IOSFRAMEWORKDIR="$IOSOUTPUTDIR/framework"
TVOSFRAMEWORKDIR="$TVOSOUTPUTDIR/framework"
OSXFRAMEWORKDIR="$OSXOUTPUTDIR/framework"

format="%-20s %s\n"
format2="%-20s %s (%u)\n"
printf "$format" "BUILD_ANDROID:" $( [[ -n $BUILD_ANDROID ]] && echo "YES" || echo "NO")
printf "$format" "BUILD_IOS:" $( [[ -n $BUILD_IOS ]] && echo "YES" || echo "NO")
printf "$format" "BUILD_TVOS:" $( [[ -n $BUILD_TVOS ]] && echo "YES" || echo "NO")
printf "$format" "BUILD_OSX:" $( [[ -n $BUILD_OSX ]] && echo "YES" || echo "NO")
printf "$format" "BUILD_LINUX:" $( [[ -n $BUILD_LINUX ]] && echo "YES" || echo "NO")
printf "$format" "BOOST_VERSION:" "$BOOST_VERSION"
printf "$format" "IOS_SDK_VERSION:" "$IOS_SDK_VERSION"
printf "$format" "MIN_IOS_VERSION:" "$MIN_IOS_VERSION"
printf "$format" "TVOS_SDK_VERSION:" "$TVOS_SDK_VERSION"
printf "$format" "MIN_TVOS_VERSION:" "$MIN_TVOS_VERSION"
printf "$format" "OSX_SDK_VERSION:" "$OSX_SDK_VERSION"
printf "$format" "MIN_OSX_VERSION:" "$MIN_OSX_VERSION"
printf "$format2" "OSX_ARCHS:" "$OSX_ARCHS" $OSX_ARCH_COUNT
printf "$format" "BOOST_LIBS:" "$BOOST_LIBS"
printf "$format" "BOOST_SRC:" "$BOOST_SRC"
printf "$format" "ANDROIDBUILDDIR:" "$ANDROIDBUILDDIR"
printf "$format" "LINUXBUILDDIR:" "$LINUXBUILDDIR"
printf "$format" "IOSBUILDDIR:" "$IOSBUILDDIR"
printf "$format" "OSXBUILDDIR:" "$OSXBUILDDIR"
printf "$format" "IOSFRAMEWORKDIR:" "$IOSFRAMEWORKDIR"
printf "$format" "OSXFRAMEWORKDIR:" "$OSXFRAMEWORKDIR"
printf "$format" "XCODE_ROOT:" "$XCODE_ROOT"
echo

if [ -n "$CLEAN" ]; then
    cleanup
    exit
fi

if [ -z $NO_CLEAN ]; then
    cleanup
fi

downloadBoost
unpackBoost
unpackBeast
inventMissingHeaders

if [ -n "$UNPACK" ]; then
    exit
fi

if [[ -n $BUILD_ANDROID ]]; then
    updateBoost "Android"
    bootstrapBoost "Android"
    buildBoost_Android
fi
if [[ -n $BUILD_IOS ]]; then
    updateBoost "iOS"
    bootstrapBoost "iOS"
    buildBoost_iOS
fi
if [[ -n $BUILD_TVOS ]]; then
    updateBoost "tvOS"
    bootstrapBoost "tvOS"
    buildBoost_tvOS
fi
if [[ -n $BUILD_OSX ]]; then
    updateBoost "OSX"
    bootstrapBoost "OSX"
    buildBoost_OSX
fi
if [[ -n $BUILD_LINUX ]]; then
    updateBoost "Linux"
    bootstrapBoost "Linux"
    buildBoost_Linux
fi

if [ -z $NO_FRAMEWORK ]; then

    scrunchAllLibsTogetherInOneLibPerPlatform

    if [[ -n $BUILD_IOS ]]; then
        buildFramework "$IOSFRAMEWORKDIR" "$IOSOUTPUTDIR"
    fi

    if [[ -n $BUILD_TVOS ]]; then
        buildFramework "$TVOSFRAMEWORKDIR" "$TVOSOUTPUTDIR"
    fi

    if [[ -n $BUILD_OSX ]]; then
        buildFramework "$OSXFRAMEWORKDIR" "$OSXOUTPUTDIR"
    fi
fi

if [[ -n "$BUILD_HEADERS" ]]; then
    packageHeaders
fi
packageLibs

deployToNexus

echo "Completed successfully"
