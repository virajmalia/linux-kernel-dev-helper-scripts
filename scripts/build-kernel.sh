#!/bin/bash

# This script builds the Linux kernel with various options
# for development, debugging and testing purposes

# Source environment if available
if [ -f "/workspace/.env.kernel" ]; then
    source /workspace/.env.kernel
else
    # Set default variables if env file doesn't exist
    KERNEL_SRC="/usr/src/linux"
    KBUILD_OUTPUT="/kernel-build"
fi

# Parse command-line arguments
BUILD_TYPE="full"
CLEAN_BUILD=0
NUM_CORES=$(nproc)
MENUCONFIG=0
TEST_QEMU=0
KERNEL_VERSION=""

function show_help {
    echo "Usage: $0 [OPTIONS]"
    echo "Build the Linux kernel with various options"
    echo
    echo "Options:"
    echo "  -h, --help        Show this help message"
    echo "  -c, --clean       Perform a clean build"
    echo "  -j NUM            Number of parallel jobs (default: use all cores)"
    echo "  -m, --menuconfig  Run menuconfig before building"
    echo "  -t, --type TYPE   Build type (full, modules, bzImage, headers)"
    echo "  -q, --qemu        Test the kernel with QEMU after building"
    echo "  -v, --version     Specific kernel version to build (e.g., v6.1, v5.15.1)"
    echo "                    If specified, will clone that version from kernel.org"
    echo
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -c|--clean)
            CLEAN_BUILD=1
            shift
            ;;
        -j)
            NUM_CORES=$2
            shift 2
            ;;
        -m|--menuconfig)
            MENUCONFIG=1
            shift
            ;;
        -t|--type)
            BUILD_TYPE=$2
            shift 2
            ;;
        -q|--qemu)
            TEST_QEMU=1
            shift
            ;;
        -v|--version)
            KERNEL_VERSION=$2
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
    shift
done

# If kernel version is specified, clone and prepare the specific version
if [ -n "$KERNEL_VERSION" ]; then
    echo "Setting up Linux kernel version: $KERNEL_VERSION"
    
    # Create a temp directory for the kernel source if not exists
    if [ ! -d "/tmp/kernel-source" ]; then
        mkdir -p /tmp/kernel-source
    fi
    
    # Clone the kernel if not already cloned
    if [ ! -d "/tmp/kernel-source/linux" ]; then
        echo "Cloning Linux kernel repository..."
        git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git /tmp/kernel-source/linux
    fi
    
    # Navigate to the kernel source directory
    cd /tmp/kernel-source/linux || exit 1
    
    # Fetch the specific tag/branch
    echo "Fetching kernel version $KERNEL_VERSION..."
    git fetch --depth 1 origin tag "$KERNEL_VERSION" || git fetch --depth 1 origin "$KERNEL_VERSION"
    
    # Checkout the specific version
    echo "Checking out kernel version $KERNEL_VERSION..."
    git checkout "$KERNEL_VERSION"
    
    # Update the kernel source path
    KERNEL_SRC="/tmp/kernel-source/linux"
    echo "Using kernel source from: $KERNEL_SRC"
fi

# Check if the kernel source directory exists
if [ ! -d "$KERNEL_SRC" ]; then
    echo "Kernel source directory does not exist: $KERNEL_SRC"
    echo "Please run setup.sh first"
    exit 1
fi

# Ensure the kernel source tree is clean first
echo "Ensuring kernel source tree is clean..."
# Navigate to kernel source, run mrproper, and return to original directory
CURRENT_DIR=$(pwd)
cd "$KERNEL_SRC" || exit 1
make mrproper
cd "$CURRENT_DIR" || exit 1

# Create build output directory if it doesn't exist
mkdir -p $KBUILD_OUTPUT

# Clean previous builds if requested
if [ $CLEAN_BUILD -eq 1 ]; then
    echo "Cleaning previous build..."
    make -C "$KERNEL_SRC" O=$KBUILD_OUTPUT clean
    make -C "$KERNEL_SRC" O=$KBUILD_OUTPUT mrproper
fi

# Run menuconfig if requested
if [ $MENUCONFIG -eq 1 ]; then
    echo "Running menuconfig..."
    make -C "$KERNEL_SRC" O=$KBUILD_OUTPUT menuconfig
else
    # Check if .config exists, if not create a default one
    if [ ! -f "$KBUILD_OUTPUT/.config" ]; then
        echo "No .config found, creating default configuration..."
        make -C "$KERNEL_SRC" O=$KBUILD_OUTPUT defconfig
    fi
fi

# Build kernel based on selected type
echo "Building kernel ($BUILD_TYPE) with $NUM_CORES parallel jobs..."

case $BUILD_TYPE in
    full)
        # Build the full kernel
        make -C "$KERNEL_SRC" O=$KBUILD_OUTPUT -j$NUM_CORES
        ;;
    modules)
        # Build only the modules
        make -C "$KERNEL_SRC" O=$KBUILD_OUTPUT modules -j$NUM_CORES
        ;;
    bzImage)
        # Build only the kernel image
        make -C "$KERNEL_SRC" O=$KBUILD_OUTPUT bzImage -j$NUM_CORES
        ;;
    headers)
        # Install kernel headers
        make -C "$KERNEL_SRC" O=$KBUILD_OUTPUT headers_install -j$NUM_CORES
        ;;
    *)
        echo "Unknown build type: $BUILD_TYPE"
        exit 1
        ;;
esac

if [ $? -ne 0 ]; then
    echo "Kernel build failed!"
    exit 1
fi

echo "Kernel build completed successfully."

# Run the kernel in QEMU if requested
if [ $TEST_QEMU -eq 1 ]; then
    echo "Testing kernel in QEMU..."
    
    # Check if kernel image exists
    KERNEL_IMAGE="$KBUILD_OUTPUT/arch/x86/boot/bzImage"
    if [ ! -f "$KERNEL_IMAGE" ]; then
        echo "Kernel image not found: $KERNEL_IMAGE"
        exit 1
    fi
    
    # Create a minimal initramfs if it doesn't exist
    INITRAMFS="/tmp/initramfs.img"
    if [ ! -f "$INITRAMFS" ]; then
        echo "Creating minimal initramfs..."
        mkdir -p /tmp/initramfs
        cd /tmp/initramfs
        mkdir -p bin dev proc sys
        cat > init << 'EOF'
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
echo "Hello from minimal initramfs!"
echo "Kernel development environment ready."
echo "Type 'poweroff -f' to exit QEMU"
exec /bin/sh
EOF
        chmod +x init
        find . | cpio -o -H newc | gzip > $INITRAMFS
        cd -
    fi
    
    # Launch QEMU
    echo "Launching QEMU..."
    qemu-system-x86_64 \
        -kernel $KERNEL_IMAGE \
        -initrd $INITRAMFS \
        -nographic \
        -append "console=ttyS0 nokaslr" \
        -enable-kvm \
        -m 512M
fi