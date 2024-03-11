#!/bin/bash

set -ex


CMAKE_FLAGS="${CMAKE_ARGS} -DCMAKE_INSTALL_PREFIX=${PREFIX} -DCMAKE_BUILD_TYPE=Release"
if [[ "$with_test_suite" == "true" ]]; then
    CMAKE_FLAGS+=" -DBUILD_TESTING=ON -DOPENMM_BUILD_OPENCL_TESTS=ON"
else
    CMAKE_FLAGS+=" -DBUILD_TESTING=OFF"
fi


if [[ "$target_platform" == linux* ]]; then
    # CFLAGS
    # JRG: Had to add -ldl to prevent linking errors (dlopen, etc)
    MINIMAL_CFLAGS+=" -O3 -ldl"
    CFLAGS+=" $MINIMAL_CFLAGS"
    CXXFLAGS+=" $MINIMAL_CFLAGS"

    # CUDA is enabled in these platforms
    if [[ "$target_platform" == linux-64 || "$target_platform" == linux-ppc64le ]]; then
        # # CUDA_HOME is defined by nvcc metapackage
        CMAKE_FLAGS+=" -DCUDA_TOOLKIT_ROOT_DIR=${CUDA_HOME}"
        # CUDA tests won't build, disable for now
        # See https://github.com/openmm/openmm/issues/2258#issuecomment-462223634
        CMAKE_FLAGS+=" -DOPENMM_BUILD_CUDA_TESTS=OFF"
        # shadow some CMAKE_ARGS bits that interfere with CUDA detection
        CMAKE_FLAGS+=" -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH"
    fi

    # OpenCL ICD
    CMAKE_FLAGS+=" -DOPENCL_INCLUDE_DIR=${PREFIX}/include"
    CMAKE_FLAGS+=" -DOPENCL_LIBRARY=${PREFIX}/lib/libOpenCL${SHLIB_EXT}"

elif [[ "$target_platform" == osx* ]]; then
    if [[ "$opencl_impl" == khronos ]]; then
        CMAKE_FLAGS+=" -DOPENCL_INCLUDE_DIR=${PREFIX}/include"
        CMAKE_FLAGS+=" -DOPENCL_LIBRARY=${PREFIX}/lib/libOpenCL${SHLIB_EXT}"
    fi
    # When using opencl_impl == apple, CMake will auto-locate it, so no need to provide the flags
    # On Conda Forge, this will result in:
    #   /Applications/Xcode_12.app/Contents/Developer/Platforms/MacOSX.platform/Developer/...
    #   ...SDKs/MacOSX10.9.sdk/System/Library/Frameworks/OpenCL.framework
    # On local builds, it might be:
    #   /System/Library/Frameworks/OpenCL.framework/OpenCL
fi

# Disambiguate swig location
CMAKE_FLAGS+=" -DSWIG_EXECUTABLE=$(which swig)"

if [[ "$target_platform" == linux-* ]]; then
    export LDFLAGS="$LDFLAGS -static-libstdc++ -Wl,--exclude-libs,ALL -Wl,-rpath,$ORIGIN/../OpenMM.libs/lib"
fi

# Build in subdirectory and install.
mkdir -p build
cd build
cmake ${CMAKE_FLAGS} ${SRC_DIR}
make -j$CPU_COUNT
make install

cd python
rm -rf dist
rm -rf fixed_wheels
export OPENMM_LIB_PATH=$PREFIX/lib
export OPENMM_INCLUDE_PATH=$PREFIX/include
$PYTHON -m pip wheel . --wheel-dir=dist

# vendor include directories and libraries
for whl in $PWD/dist/*.whl; do
  pushd $PREFIX
    plugins=""
    for plugin in lib/plugins/*.so; do
      if [[ "$plugin" != *CUDA.so ]]; then
        plugins="$plugins $plugin"
      fi
    done
    $BUILD_PREFIX/bin/python $RECIPE_DIR/vendor_wheel.py $whl include/openmm include/lepton lib/libOpenMM.so lib/libOpenMM.so.8.1 lib/libOpenMMRPMD.so lib/libOpenMMAmoeba.so lib/libOpenMMDrude.so $plugins
  popd
done

function repair() {
  # Repair the wheels in dist
  if [[ "$target_platform" == linux-64 ]]; then
    rm -rf $PREFIX/lib/libstdc++.*
    rm -rf $PREFIX/lib/libgcc*
    auditwheel repair dist/*.whl -w $PWD/fixed_wheels --plat manylinux2014_x86_64 --exclude libOpenMM.so.8.1 --exclude libOpenMMOpenCL.so --exclude libOpenMMDrude.so --exclude libOpenMMAmoeba.so --exclude libOpenMMRPMD.so --exclude libOpenCL.so.1 --exclude libcuda.so.1 --exclude libcufft.so.11 --exclude libnvrtc.so.12 --exclude libcufft.so.10 --exclude libnvrtc.so.11.2 --lib-sdir=$LIB_SDIR
  elif [[ "$target_platform" == linux-* ]]; then
    rm -rf $PREFIX/lib/libstdc++.*
    rm -rf $PREFIX/lib/libgcc*
    auditwheel repair dist/*.whl -w $PWD/fixed_wheels --plat manylinux2014_$ARCH
  else
    python -m pip install "https://github.com/isuruf/delocate/archive/sanitize_rpaths2.tar.gz#egg=delocate"
    python $(which delocate-wheel) -w fixed_wheels --sanitize-rpaths -v dist/*.whl
  fi
}

LIB_SDIR=".libs/lib" repair
rm -rf dist
mkdir dist
for whl in fixed_wheels/*.whl; do
  whl_tag="${whl##*-}"
done

pushd openmm-cuda
  $PYTHON -m pip wheel .
  for whl in $PWD/*.whl; do
    whl_name=$(basename $whl)
    whl_name="${whl_name::${#whl_name}-7}$whl_tag"
    pushd $PREFIX
        $BUILD_PREFIX/bin/python $RECIPE_DIR/vendor_wheel.py $whl lib/plugins/libOpenMMCUDA.so lib/plugins/libOpenMMDrudeCUDA.so lib/plugins/libOpenMMAmoebaCUDA.so lib/plugins/libOpenMMRPMDCUDA.so
    popd
    cp $whl ../dist/$whl_name
  done
popd
LIB_SDIR=".libs" repair

# Copy the wheel to destination
for whl in fixed_wheels/*.whl; do
  if [[ "$build_platform" == "osx-"* ]]; then
    WHL_DEST=$RECIPE_DIR/../build_artifacts/pypi_wheels
  elif [[ "$build_platform" == "linux-"* ]]; then
    WHL_DEST=/home/conda/feedstock_root/build_artifacts/pypi_wheels
  fi
  mkdir -p $WHL_DEST
  cp $whl $WHL_DEST
done

# Install the wheel
for whl in fixed_wheels/*.whl; do
  $PYTHON -m pip install $whl
done
