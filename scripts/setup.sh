#!/bin/bash
set -e

echo "Setting up Linux kernel development environment..."

# Update package list and install necessary packages for kernel development
echo "Installing development packages..."
apt-get update
apt-get install -y \
    build-essential libncurses-dev bison flex libssl-dev libelf-dev \
    git fakeroot ncurses-dev xz-utils libssl-dev bc \
    qemu-system-x86 qemu-utils \
    gdb cscope exuberant-ctags \
    sparse coccinelle \
    gcc-multilib rsync curl wget \
    clang llvm lld

# Set up directories for kernel development
KERNEL_SRC="/usr/src/linux"
KBUILD_OUTPUT="/kernel-build"
KERNEL_VERSION="6.6" # Latest stable as of May 2025, adjust as needed

# Create necessary directories
echo "Setting up directories..."
mkdir -p $KBUILD_OUTPUT
mkdir -p $KERNEL_SRC

# Clone the Linux kernel source if not already present
if [ ! -d "$KERNEL_SRC/.git" ]; then
    echo "Cloning Linux kernel source..."
    git clone --depth=1 --branch=v$KERNEL_VERSION https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git $KERNEL_SRC
    
    # Alternatively, download a tarball for faster setup
    # cd /usr/src
    # wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KERNEL_VERSION.tar.xz
    # tar xf linux-$KERNEL_VERSION.tar.xz
    # ln -sf linux-$KERNEL_VERSION linux
else
    echo "Kernel source already exists, updating..."
    cd $KERNEL_SRC
    git fetch --tags
    git checkout v$KERNEL_VERSION
fi

# Create a minimal kernel config for fast builds during development
if [ ! -f "$KERNEL_SRC/.config" ]; then
    echo "Creating minimal kernel config..."
    cd $KERNEL_SRC
    make defconfig
    
    # Enable debugging options
    scripts/config --enable DEBUG_KERNEL
    scripts/config --enable DEBUG_INFO
    scripts/config --enable KGDB
    scripts/config --enable KGDB_SERIAL_CONSOLE
    scripts/config --enable DEBUG_INFO_REDUCED
    scripts/config --disable DEBUG_INFO_SPLIT
    scripts/config --enable GDB_SCRIPTS
    
    # Enable modules support
    scripts/config --enable MODULES
    scripts/config --enable MODULE_UNLOAD
    
    # Enable QEMU-friendly options
    scripts/config --enable 9P_FS
    scripts/config --enable NET_9P
    scripts/config --enable NET_9P_VIRTIO
    scripts/config --enable VIRTIO_PCI
    scripts/config --enable VIRTIO_BLK
    scripts/config --enable VIRTIO_NET
    scripts/config --enable VIRTIO_CONSOLE
fi

# Setup environment variables
cat > /workspace/.env.kernel <<EOF
# Kernel development environment variables
export KERNEL_SRC=$KERNEL_SRC
export KBUILD_OUTPUT=$KBUILD_OUTPUT
export ARCH=x86_64
export CROSS_COMPILE=
export PATH=\$PATH:\$KERNEL_SRC/scripts:\$KERNEL_SRC/tools/perf/scripts
EOF

echo "Source environment variables with 'source /workspace/.env.kernel'"
echo "Development environment setup complete."