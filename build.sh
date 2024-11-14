#!/bin/bash

set -eux

# BUILD_TIME=$(TZ='Asia/Shanghai' date +'%Y%m%d-%H%M%S')

export WORK="$(pwd)/workspace"
export HOST_ARCH=$(dpkg --print-architecture)

KERNEL_SOURCE="https://github.com/LineageOS/android_kernel_xiaomi_sdm845"
KERNEL_BRANCH="lineage-21"
KERNEL_CONFIG="sdm845_defconfig"
KERNEL_CONFIG_2="vendor/xiaomi/dipper.config"
KERNEL_IMAGE="Image.gz-dtb"
ARCH="arm64"
DEVICE="dipper"
KERNEL_DIR="android-kernel"

BUILD_BOOT_IMG="false"
BOOT_SOURCE="https://mirrorbits.lineageos.org/full/dipper/20241109/boot.img"

CLANG_AOSP="false"
AOSP_BRANCH="main"
AOSP_VERSION="r487747c"
OTHER_CLANG="https://gitlab.com/LeCmnGend/clang.git"
OTHER_BRANCH="clang-19"
CLANG_BIN="$WORK/clang/bin"

# Clang-AOSP：https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+refs
# GCC-AARCH64：https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+refs
# GCC-ARM：https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/+refs
AARCH64="true"
GCC_64_SOURCE="https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+archive/refs/tags/android-12.1.0_r27.tar.gz"
GCC_64_BRANCH="main"
GCC_AARCH64_DIR="$WORK/clang/aarch64-linux-gnu/bin"

ARM="true"
GCC_32_SOURCE="https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/+archive/refs/tags/android-12.1.0_r27.tar.gz"
GCC_32_BRANCH="gcc-master"
GCC_ARM_DIR="$WORK/gcc-32/bin"

KERNELSU="true"
KERNELSU_TAG="v0.9.5"
APPLY_KSU_PATCH="true"
OVERLAYFS_CONFIG="true"
KPROBES_CONFIG="true"
DISABLELTO="true"             # 禁用优化
DISABLE_CC_WERROR="true"    # 防止警告当作错误处理

ENABLE_CCACHE="false"

args="O=out \
ARCH=arm64 \
LD=ld.lld \
NM=llvm-nm \
AR=llvm-ar \
LLVM=1 \
LLVM_IAS=1 \
CLANG_TRIPLE=aarch64-linux-gnu- \
CROSS_COMPILE=aarch64-linux-gnu- \
CROSS_COMPILE_ARM32=arm-linux-androideabi- 
"

# C="AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip LLVM_IAS=1 LLVM=1 LD=ld.lld"

BUILD_LOG="$WORK/$KERNEL_DIR/build.log"

LXC="true"      # 测试
CONFIG_KVM="true"

msg() {
  local message="$1"
  local message_type="${2:-}"
  case "$message_type" in
    warning)
      echo -e "\033[0;33m${message}\033[0m"
      ;;
    error)
      echo -e "\033[0;31m${message}\033[0m"
      ;;
    success)
      echo -e "\033[0;32m${message}\033[0m"
      ;;
    *)
      echo -e "\033[0;36m${message}\033[0m"
      ;;
  esac
}

prepare_ccache() {
    if [ $ENABLE_CCACHE = "true" ]; then
        # export CCACHE_DIR="$WORK/.ccache"
        ccache -M 2G
        ccache -s
    fi
}

get_system_info() {
    echo "--------------------------CPU信息--------------------------"
    echo "CPU物理数量: $(cat /proc/cpuinfo | grep 'physical id' | sort | uniq | wc -l)"
    echo "CPU核心数量: $(nproc)"
    echo -e "CPU型号信息:$(cat /proc/cpuinfo | grep -m1 'model name' | awk -F: '{print $2}')"
    echo "CPU频率: $(cat /proc/cpuinfo | grep -m1 'cpu MHz' | awk -F: '{print $2}') MHz"
    echo "缓存大小: $(cat /proc/cpuinfo | grep -m1 'cache size' | awk -F: '{print $2}')"
    echo "CPU架构: $(lscpu | grep 'Architecture' | awk '{print $2}')"
    echo "线程数: $(lscpu | grep '^Thread(s) per core:' | awk '{print $4}')"
    echo "每核核心数: $(lscpu | grep '^Core(s) per socket:' | awk '{print $4}')"
    echo "插槽数: $(lscpu | grep '^Socket(s):' | awk '{print $2}')"
    echo "--------------------------内存信息--------------------------"
    echo -e "$(sudo lshw -short -C memory | grep GiB)"
    echo "--------------------------硬盘信息--------------------------"
    echo "硬盘数量: $(ls /dev/sd* | grep -v [1-9] | wc -l)"
    df -hT
}

install_tools() {
    get_system_info
    sudo apt update && sudo apt -y install bc bison build-essential ccache curl flex g++-multilib gcc-multilib git gnupg gperf imagemagick libc6 lib32ncurses5-dev lib32readline-dev lib32z1-dev liblz4-tool libncurses5-dev libncurses5 libsdl1.2-dev libssl-dev libelf-dev libwxgtk3.0-gtk3-dev libxml2 libxml2-utils libncurses-dev lzop pngcrush rsync schedtool squashfs-tools xsltproc zip zlib1g-dev make unzip python-is-python3 aria2

    # sudo rm /bin/python && sudo ln -s /bin/python2.7 /bin/python
    mkdir -p $WORK
}

download_clang_compiler() {
    cd $WORK
    if [[ $CLANG_AOSP == "true" ]]; then
        mkdir -p clang
        aria2c -s16 -x16 -k1M https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/$AOSP_BRANCH/clang-$AOSP_VERSION.tar.gz
            tar -xzf clang-$AOSP_VERSION.tar.gz -C clang
        rm -f clang-$AOSP_VERSION.tar.gz
    else
        case $OTHER_CLANG in
            *.git)
                rm -rf clang
                git clone --depth=1 -b $OTHER_BRANCH $OTHER_CLANG clang
                ;;
            *.tar.gz)
                mkdir -p clang
                aria2c -s16 -x16 -k1M -o clang.tar.gz $OTHER_CLANG
                    tar -xzf clang.tar.gz -C clang
                rm -f clang.tar.gz
                ;;
            *)
                exit 1
                ;;
        esac
    fi
}

download_gcc() {
  local source=$1
  local branch=$2
  local target_dir=$3
  case $source in
    *.git)
      rm -rf $target_dir
      git clone --depth=1 -b $branch $source $target_dir
      ;;
    *.tar.gz)
      mkdir -p $target_dir
      curl -o $target_dir.tar.gz $source
        tar -xzf $target_dir.tar.gz -C $target_dir
      rm -f $target_dir.tar.gz
      ;;
    *)
      exit 1
      ;;
  esac
}

download_appropriate_gcc() {
  cd $WORK
  if [ $AARCH64 == "true" ]; then
    download_gcc $GCC_64_SOURCE $GCC_64_BRANCH gcc-64
  fi
  if [ $ARM == "true" ]; then
    download_gcc $GCC_32_SOURCE $GCC_32_BRANCH gcc-32
  fi
}

clone_kernel() {
    git clone --depth=1 -b $KERNEL_BRANCH --recursive $KERNEL_SOURCE $KERNEL_DIR
}

merge_kernel_configs() {
    cd $WORK/$KERNEL_DIR/arch/$ARCH/configs
    if [[ -z $KERNEL_CONFIG_2 || ! -f $KERNEL_CONFIG_2 ]]; then
        msg "KERNEL_CONFIG_2 is either empty or the file does not exist. Exiting" warning
        return 0
    fi
    while IFS= read -r line; do
        if [[ -z $line || $line == \#* ]]; then
            continue
        fi
        local config_name=$(echo $line | cut -d '=' -f 1)
        sed -i "s/^# $config_name is not set/$line/" $KERNEL_CONFIG
        sed -i "s/^$config_name=.*/$line/" $KERNEL_CONFIG
        if ! grep -q "^$config_name=" $KERNEL_CONFIG && ! grep -q "^# $config_name is not set" $KERNEL_CONFIG; then
            echo $line >> $KERNEL_CONFIG
        fi
    done < $KERNEL_CONFIG_2
}

get_kernel_version() {
    cd $WORK/$KERNEL_DIR
    KERNEL_VERSION=$(cat Makefile | grep -w "VERSION =" | cut -d '=' -f 2 | cut -b 2-)\
    .$(cat Makefile | grep -w "PATCHLEVEL =" | cut -d '=' -f 2 | cut -b 2-)\
    .$(cat Makefile | grep -w "SUBLEVEL =" | cut -d '=' -f 2 | cut -b 2-)\
    .$(cat Makefile | grep -w "EXTRAVERSION =" | cut -d '=' -f 2 | cut -b 2-)
    [ ${KERNEL_VERSION: -1} = "." ] && KERNEL_VERSION=${KERNEL_VERSION::-1}
    msg "Kernel Version: $KERNEL_VERSION" warning
}

setup_kernelsu() {
    if [ $KERNELSU = "true" ]; then
        cd $WORK/$KERNEL_DIR
        rm -rf KernelSU drivers/kernelsu
        curl -LSs https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh | bash -s $KERNELSU_TAG
    fi
}

lxc_docker() {
    if [ $LXC = "true" ]; then
        cd $WORK/$KERNEL_DIR
        aria2c https://github.com/dabao1955/kernel_build_action/raw/main/lxc/config.sh && bash config.sh arch/$ARCH/configs/$KERNEL_CONFIG -w
        echo "CONFIG_DOCKER=y" >> arch/$ARCH/configs/$KERNEL_CONFIG
        grep -q "CONFIG_ANDROID_PARANOID_NETWORK" arch/$ARCH/configs/$KERNEL_CONFIG && sed -i 's/CONFIG_ANDROID_PARANOID_NETWORK=y/# CONFIG_ANDROID_PARANOID_NETWORK is not set/' arch/$ARCH/configs/$KERNEL_CONFIG
        aria2c https://github.com/dabao1955/kernel_build_action/raw/main/lxc/cgroup.patch
        # patch kernel/cgroup.c < cgroup.patch
        patch $WORK/$KERNEL_DIR/kernel/cgroup.c < cgroup.patch
        # aria2c https://github.com/dabao1955/kernel_build_action/raw/main/lxc/xt_qtaguid.patch
        # patch net/netfilter/xt_qtaguid.c < xt_qtaguid.patch
    fi
    if [ $CONFIG_KVM = "true" ]; then
        echo "CONFIG_VIRTUALIZATION=y" | tee -a arch/$ARCH/configs/$KERNEL_CONFIG >/dev/null
        echo "CONFIG_KVM=y" >> arch/$ARCH/configs/$KERNEL_CONFIG
        # echo "CONFIG_KVM_MMIO=y" >> arch/$ARCH/configs/$KERNEL_CONFIG
        # echo "CONFIG_KVM_ARM_HOST=y" >> arch/$ARCH/configs/$KERNEL_CONFIG
        echo "CONFIG_VHOST_NET=y" >> arch/$ARCH/configs/$KERNEL_CONFIG
        echo "CONFIG_VHOST_CROSS_ENDIAN_LEGACY=y" >> arch/$ARCH/configs/$KERNEL_CONFIG
    fi
}


apply_patches_and_configurations() {
    cd $WORK/$KERNEL_DIR
    if [ $APPLY_KSU_PATCH = "true" ]; then
        if aria2c -s16 -x16 -k1M https://raw.githubusercontent.com/dabao1955/kernel_build_action/main/kernelsu/patch.sh &&
           aria2c -s16 -x16 -k1M https://raw.githubusercontent.com/bin456789/KernelSU-Action/main/patches/allow-init-exec-ksud-under-nosuid.patch; then
            bash patch.sh
            find . -name '*.patch' -print0 | xargs -0 -I{} git apply {}
        else
            return 1
        fi
        if grep -q "CONFIG_KSU" arch/$ARCH/configs/$KERNEL_CONFIG; then
            sed -i 's/# CONFIG_KSU is not set/CONFIG_KSU=y/g' arch/$ARCH/configs/$KERNEL_CONFIG
            sed -i 's/CONFIG_KSU=n/CONFIG_KSU=y/g' arch/$ARCH/configs/$KERNEL_CONFIG
        else
            echo "CONFIG_KSU=y" >> arch/$ARCH/configs/$KERNEL_CONFIG
        fi
    fi
    if [ $KPROBES_CONFIG = "true" ] && [ $APPLY_KSU_PATCH != "true" ]; then
        echo "CONFIG_MODULES=y" >> arch/$ARCH/configs/$KERNEL_CONFIG
        echo "CONFIG_KPROBES=y" >> arch/$ARCH/configs/$KERNEL_CONFIG
        echo "CONFIG_HAVE_KPROBES=y" >> arch/$ARCH/configs/$KERNEL_CONFIG
        echo "CONFIG_KPROBE_EVENTS=y" >> arch/$ARCH/configs/$KERNEL_CONFIG
    fi
    if [ $OVERLAYFS_CONFIG = "true" ]; then
        echo "CONFIG_OVERLAY_FS=y" >> arch/$ARCH/configs/$KERNEL_CONFIG
    fi

    if [ $DISABLELTO = "true" ]; then
        sed -i 's/CONFIG_LTO=y/CONFIG_LTO=n/' arch/$ARCH/configs/$KERNEL_CONFIG
        sed -i 's/CONFIG_LTO_CLANG=y/CONFIG_LTO_CLANG=n/' arch/$ARCH/configs/$KERNEL_CONFIG
        sed -i 's/CONFIG_THINLTO=y/CONFIG_THINLTO=n/' arch/$ARCH/configs/$KERNEL_CONFIG
        echo "CONFIG_LTO_NONE=y" >> arch/$ARCH/configs/$KERNEL_CONFIG
    fi

    if [ $DISABLE_CC_WERROR = "true" ]; then
        echo "CONFIG_CC_WERROR=n" >> arch/$ARCH/configs/$KERNEL_CONFIG
    fi
}

set_path() {
    [ -d $CLANG_BIN ] && export PATH=$CLANG_BIN:$PATH || { msg "$CLANG_BIN does not exist, please check the compiler's bin path" error; exit 1; }

    if [ $AARCH64 = "true" ]; then
        [ -d $GCC_AARCH64_DIR ] && export PATH=$GCC_AARCH64_DIR:$PATH || { msg "$GCC_AARCH64_DIR does not exist, please check the compiler's bin path" error; exit 1; }
    fi

    if [ $ARM = "true" ]; then
        [ -d $GCC_ARM_DIR ] && export PATH=$GCC_ARM_DIR:$PATH || { msg "$GCC_ARM_DIR does not exist, please check the compiler's bin path" error; exit 1; }
    fi
    clang --version
}

build_kernel() {
    cd $WORK/$KERNEL_DIR
    make clean && make mrproper && rm -rf out
    : > $BUILD_LOG
    prepare_ccache
    make -j$(nproc --all) CC=clang $args $KERNEL_CONFIG
    if [ $ENABLE_CCACHE = "true" ]; then
        CC="ccache clang"
    else
        CC="clang"
    fi
    make -j$(nproc --all) CC="$CC" $args 2>&1 | tee -a $BUILD_LOG
    if [ -f out/arch/$ARCH/boot/$KERNEL_IMAGE ]; then
        BUILD_SUCCESS="true"
    else
        msg "Kernel output file is empty" error
        exit 1
    fi
}

package_anykernel3() {
    cd $WORK
    git clone --depth=1 https://github.com/osm0sis/AnyKernel3 AnyKernel3
    sed -i "s/kernel.string=ExampleKernel by osm0sis @ xda-developers/kernel.string=By Lin with ${BUILD_TIME}/g" AnyKernel3/anykernel.sh
    sed -i 's/do.devicecheck=1/do.devicecheck=0/g' AnyKernel3/anykernel.sh
    sed -i "s/device.name1=maguro/device.name1=${DEVICE}/g" AnyKernel3/anykernel.sh
    sed -i 's/device.name2=toro/device.name2=/g' AnyKernel3/anykernel.sh
    sed -i 's/device.name3=toroplus/device.name3=/g' AnyKernel3/anykernel.sh
    sed -i 's/device.name4=tuna/device.name4=/g' AnyKernel3/anykernel.sh
    sed -i 's|BLOCK=/dev/block/platform/omap/omap_hsmmc.0/by-name/boot|BLOCK=auto|g' AnyKernel3/anykernel.sh
    sed -i 's/IS_SLOT_DEVICE=0;/IS_SLOT_DEVICE=auto;/g' AnyKernel3/anykernel.sh
    rm -rf AnyKernel3/.git AnyKernel3/README.md AnyKernel3/modules AnyKernel3/patch AnyKernel3/ramdisk AnyKernel3/.github
    cp $KERNEL_DIR/out/arch/$ARCH/boot/$KERNEL_IMAGE AnyKernel3/
    cd AnyKernel3
    zip -r9 ../AnyKernel3-$BUILD_TIME.zip *

}

download_magiskboot() {
    case $HOST_ARCH in
        armv7* | armv8l | arm64 | armhf | arm) aria2c https://raw.githubusercontent.com/magojohnji/magiskboot-linux/main/arm64-v8a/magiskboot && chmod +x magiskboot ;;
        i*86 | x86 | amd64 | x86_64) aria2c https://raw.githubusercontent.com/magojohnji/magiskboot-linux/main/x86_64/magiskboot && chmod +x magiskboot  ;;
        *) echo "Unknow cpu architecture for this device !" && exit 1 ;;
    esac
}

bootimage() {
    if [ $BUILD_BOOT_IMG = "true" ] && [ "${BUILD_SUCCESS:-false}" = "true" ]; then
        cd $WORK
        mkdir img && cd img
        aria2c -o boot.img $BOOT_SOURCE
        download_magiskboot
        ./magiskboot unpack boot.img
        cp $WORK/$KERNEL_DIR/out/arch/$ARCH/boot/$KERNEL_IMAGE kernel
        ./magiskboot repack boot.img && rm -rf boot.img && mv new-boot.img boot.img
    fi
}

main() {
    if [ "$#" -eq 0 ]; then
        steps=("install_tools" "download_clang_compiler" "download_appropriate_gcc" "set_path" "clone_kernel" "merge_kernel_configs" "setup_kernelsu" "lxc_docker" "apply_patches_and_configurations" "build_kernel" "package_anykernel3" "bootimage")
    else
        steps=("$@")
    fi

    for step in "${steps[@]}"; do
        case $step in
            install_tools|i )
                install_tools
                ;;
            download_clang_compiler|clang )
                download_clang_compiler
                ;;
            download_appropriate_gcc|gcc )
                download_appropriate_gcc
                ;;
            set_path|path )
                set_path
                ;;
            clone_kernel|kernel )
                clone_kernel
                ;;
            merge_kernel_configs|c )
                merge_kernel_configs
                ;;
            setup_kernelsu|kernelsu )
                setup_kernelsu
                ;;
            lxc_docker|lxc )
                lxc_docker
                ;;
            apply_patches_and_configurations|patch )
                apply_patches_and_configurations
                ;;
            build_kernel|build )
                build_kernel
                ;;
            package_anykernel3|anykernel3 )
                package_anykernel3
                ;;
            bootimage|image )
                bootimage
                ;;
            * )
                echo "Invalid option: $step"
                exit 1
                ;;
        esac
    done
}

main "$@"
