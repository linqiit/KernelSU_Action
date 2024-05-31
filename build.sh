#!/bin/bash

set -e
# set -e -x

# BUILD_TIME=$(TZ='Asia/Shanghai' date +'%Y%m%d-%H%M%S')

export WORK="$(pwd)/workspace"
export HOST_ARCH=$(dpkg --print-architecture)

# 内核仓库分支及其他配置
KERNEL_SOURCE="https://github.com/PainKiller3/kernel_xiaomi_sdm845"
KERNEL_BRANCH="thirteen"
KERNEL_CONFIG="vendor/xiaomi/mi845_defconfig"
KERNEL_CONFIG_2="vendor/xiaomi/dipper.config"
KERNEL_IMAGE="Image.gz-dtb"
ARCH="arm64"
DEVICE="dipper"
KERNEL_DIR="android-kernel"

BUILD_BOOT_IMG="true"
BOOT_SOURCE="https://raw.githubusercontent.com/linqiit/Filee/master/Boot/dipper-crDroid-13.0-boot.img"

# Clang默认true启用谷歌 自定义暂时只支持tar.gz压缩包
CLANG_AOSP="false"
AOSP_BRANCH="main"
AOSP_VERSION="r487747c"
OTHER_CLANG="https://gitlab.com/LeCmnGend/clang.git"
OTHER_BRANCH="clang-17"
CLANG_BIN="$WORK/clang/bin"

# Clang-AOSP：https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+refs
# GCC-AARCH64：https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+refs
# GCC-ARM：https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/+refs
AARCH64="true"
GCC_64_SOURCE="https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/+archive/refs/tags/android-12.1.0_r27.tar.gz"
GCC_64_BRANCH="main"
GCC_AARCH64_DIR="$WORK/gcc-64/bin"

ARM="true"
GCC_32_SOURCE="https://github.com/mvaisakh/gcc-arm.git"
GCC_32_BRANCH="gcc-master"
GCC_ARM_DIR="$WORK/gcc-32/bin"

KERNELSU="true"
KERNELSU_TAG="main"
KPROBES_CONFIG="true"
OVERLAYFS_CONFIG="true"
APPLY_KSU_PATCH="true"
DISABLELTO="false"
DISABLE_CC_WERROR="true"

ENABLE_CCACHE="true"
CONFIG_KVM="false"
LXC="false"
LXC_PATCH="false"
KALI_NETHUNTER="false"
KALI_NETHUNTER_PATCH="false"

args="O=out \
ARCH=arm64 \
CLANG_TRIPLE=aarch64-linux-gnu- \
CROSS_COMPILE=aarch64-linux-android- \
CROSS_COMPILE_ARM32=arm-linux-androideabi- \
LLVM=1 \
LLVM_IAS=1"
# C="AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip LLVM_IAS=1 LLVM=1 LD=ld.lld"

BUILD_LOG="$WORK/$KERNEL_DIR/build.log"

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
        ccache -M 4G
        ccache -s
    fi
}

install_tools() {
    sudo apt update && sudo apt -y install bc bison build-essential ccache curl flex g++-multilib gcc-multilib git gnupg gperf imagemagick lib32ncurses5-dev lib32readline-dev lib32z1-dev liblz4-tool libncurses5-dev libncurses5 libsdl1.2-dev libssl-dev libelf-dev libwxgtk3.0-gtk3-dev libxml2 libxml2-utils lzop pngcrush rsync schedtool squashfs-tools xsltproc zip zlib1g-dev make unzip python-is-python3 aria2

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
        KSU_VERSION=$(cd KernelSU && expr $(/usr/bin/git rev-list --count HEAD) + 10200)
        msg " 🌸 KSU_VERSION=$KSU_VERSION 🌸 "
    fi
}

lxc_kali() {
    if [ $LXC = "true" ]; then
        cd $WORK/$KERNEL_DIR
        aria2c https://github.com/wu17481748/lxc-docker/raw/main/LXC-DOCKER-OPEN-CONFIG.sh
        echo "CONFIG_DOCKER=y" >> arch/$ARCH/configs/$KERNEL_CONFIG
        bash LXC-DOCKER-OPEN-CONFIG.sh $KERNEL_CONFIG -w
    fi
    if [ $KALI_NETHUNTER = "true" ]; then
        aria2c https://github.com/Biohazardousrom/Kali-defconfig-checker/raw/master/check-kernel-config
        bash check-kernel-config $KERNEL_CONFIG -w
    fi
}

apply_patches_and_configurations() {
    cd $WORK/$KERNEL_DIR
    if [ $APPLY_KSU_PATCH = "true" ]; then
        if aria2c -s16 -x16 -k1M https://raw.githubusercontent.com/dabao1955/kernel_build_action/main/kernelsu/ksupatch.sh &&
           aria2c -s16 -x16 -k1M https://raw.githubusercontent.com/bin456789/KernelSU-Action/main/patches/backport-path-umount.patch &&
           aria2c -s16 -x16 -k1M https://raw.githubusercontent.com/bin456789/KernelSU-Action/main/patches/allow-init-exec-ksud-under-nosuid.patch; then
            bash patches.sh
            # find . -name '*.patch' -print0 | xargs -0 -I{} git apply {}
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

    if [ $KVM = "true" ]; then
        echo "CONFIG_VIRTUALIZATION=y" | tee -a arch/$ARCH/configs/$KERNEL_CONFIG >/dev/null
        echo "CONFIG_KVM=y" | tee -a arch/$ARCH/configs/$KERNEL_CONFIG >/dev/null
        echo "CONFIG_KVM_MMIO=y" | tee -a arch/$ARCH/configs/$KERNEL_CONFIG >/dev/null
        echo "CONFIG_KVM_ARM_HOST=y" | tee -a arch/$ARCH/configs/$KERNEL_CONFIG >/dev/null
    fi

    if [ $LXC_PATCH = "true" ]; then
        grep -q "CONFIG_ANDROID_PARANOID_NETWORK" arch/$ARCH/configs/$KERNEL_CONFIG && sed -i 's/CONFIG_ANDROID_PARANOID_NETWORK=y/# CONFIG_ANDROID_PARANOID_NETWORK is not set/' arch/$ARCH/configs/$KERNEL_CONFIG
        aria2c https://github.com/wu17481748/lxc-docker/raw/main/cgroup.patch
            patch -p0 < cgroup.patch
        aria2c https://github.com/wu17481748/lxc-docker/raw/main/xt_qtaguid.patch
            patch -p0 < xt_qtaguid.patch
    fi

    if [ $KALI_NETHUNTER_PATCH }} = true ]; then
        git clone https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-kernel.git
        patch -p2 < kali-nethunter-kernel/4.14/add-rtl88xxau-5.6.4.2-drivers.patch
        patch -p2 < kali-nethunter-kernel/4.14/add-wifi-injection-4.14.patch
        patch -p2 < kali-nethunter-kernel/4.14/fix-ath9k-naming-conflict.patch
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
        BUILD_FILE_OK="true"
    else
        msg "Kernel output file is empty" error
        exit 1
    fi
}

package_anykernel3() {
    if [ $BUILD_FILE_OK = "true" ]; then
        cd $WORK
        git clone --depth=1 https://github.com/osm0sis/AnyKernel3 AnyKernel3
        sed -i "s/kernel.string=ExampleKernel by osm0sis @ xda-developers/kernel.string=By Lin with ${BUILD_TIME}/g" AnyKernel3/anykernel.sh
        sed -i 's/do.devicecheck=1/do.devicecheck=0/g' AnyKernel3/anykernel.sh
        sed -i "s/device.name1=maguro/device.name1=${DEVICE}/g" AnyKernel3/anykernel.sh
        sed -i 's/device.name2=toro/device.name2=/g' AnyKernel3/anykernel.sh
        sed -i 's/device.name3=toroplus/device.name3=/g' AnyKernel3/anykernel.sh
        sed -i 's/device.name4=tuna/device.name4=/g' AnyKernel3/anykernel.sh
        sed -i 's|BLOCK=/dev/block/platform/omap/omap_hsmmc.0/by-name/boot|BLOCK=auto|g' AnyKernel3/anykernel.sh
        sed -i 's/is_slot_device=0;/is_slot_device=auto;/g' AnyKernel3/anykernel.sh
        cp android-kernel/out/arch/$ARCH/boot/$KERNEL_IMAGE AnyKernel3/
        rm -rf AnyKernel3/.git AnyKernel3/README.md AnyKernel3/modules AnyKernel3/patch AnyKernel3/ramdisk AnyKernel3/.github
        cd AnyKernel3
        zip -r9 ../AnyKernel3-$BUILD_TIME.zip *
    fi
}

bootimage() {
    if [ $BUILD_BOOT_IMG = "true" ] && [ $BUILD_FILE_OK = "true" ]; then
        cd $WORK
        mkdir magiskboot && cd magiskboot
        aria2c $BOOT_SOURCE boot.img
        case $HOST_ARCH in
            armv7* | armv8l | arm64 | armhf | arm) aria2c https://raw.githubusercontent.com/magojohnji/magiskboot-linux/main/arm64-v8a/magiskboot && chmod +x magiskboot ;;
            i*86 | x86 | amd64 | x86_64) aria2c https://raw.githubusercontent.com/magojohnji/magiskboot-linux/main/x86_64/magiskboot && chmod +x magiskboot  ;;
            *) echo "Unknow cpu architecture for this device !" && exit 1 ;;
        esac
        ./magiskboot unpack boot.img
        cp $WORK/android-kernel/out/arch/$ARCH/boot/$KERNEL_IMAGE kernel
        ./magiskboot repack boot.img && rm -rf boot.img && mv new-boot.img boot.img
    fi
}

main() {
    if [ "$#" -eq 0 ]; then
        steps=("install_tools" "download_clang_compiler" "download_appropriate_gcc" "set_path" "clone_kernel" "merge_kernel_configs" "setup_kernelsu" "lxc_kali" "apply_patches_and_configurations" "build_kernel" "bootimage" "package_anykernel3")
    else
        steps=("$@")
    fi

    for step in "${steps[@]}"; do
        case $step in
            install_tools )                   install_tools
                                              ;;
            download_clang_compiler )         download_clang_compiler
                                              ;;
            download_appropriate_gcc )        download_appropriate_gcc
                                              ;;
            set_path )                        set_path
                                              ;;
            clone_kernel )                    clone_kernel
                                              ;;
            merge_kernel_configs )            merge_kernel_configs
                                              ;;
            setup_kernelsu )                  setup_kernelsu
                                              ;;
            lxc_kali)                         lxc_kali
                                              ;;
            apply_patches_and_configurations ) apply_patches_and_configurations
                                              ;;
            build_kernel )                    build_kernel
                                              ;;
            bootimage )                       bootimage
                                              ;;
            package_anykernel3 )              package_anykernel3
                                              ;;
            * )                               echo "Invalid option: $step"
                                              exit 1
                                              ;;
        esac
    done
}

main "$@"