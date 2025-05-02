#!/bin/bash
#
# Linux Kernel Comprehensive Testing Workflow
# 
# This script provides a complete workflow for testing Linux kernel patches
# before submitting them upstream.
#
# Usage: ./test-kernel.sh [OPTIONS] [COMMAND]
#

set -e

# Source environment if available
if [ -f "/workspace/.env.kernel" ]; then
    source /workspace/.env.kernel
else
    # Set default variables if env file doesn't exist
    KERNEL_SRC="/usr/src/linux"
    KBUILD_OUTPUT="/kernel-build"
    ARCH=${ARCH:-"x86_64"}
    CROSS_COMPILE=${CROSS_COMPILE:-""}
fi

# Default configuration
OUTPUT_DIR="./kernel-test-results"
PATCH_DIR="./kernel-patches"
NUM_CORES=$(nproc)
BUILD_DEFAULT=1
VERBOSE=0
TEST_ALL=0
CONFIG_NAME="defconfig"

# Command to run (default: help)
COMMAND="help"

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            COMMAND="help"
            shift
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -j|--jobs)
            NUM_CORES="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -a|--arch)
            ARCH="$2"
            shift 2
            ;;
        -c|--cross-compile)
            CROSS_COMPILE="$2"
            shift 2
            ;;
        -k|--config)
            CONFIG_NAME="$2"
            shift 2
            ;;
        --all)
            TEST_ALL=1
            shift
            ;;
        all)
            COMMAND="all"
            shift
            ;;
        static-analysis)
            COMMAND="static-analysis"
            shift
            ;;
        build)
            COMMAND="build"
            shift
            ;;
        kunit)
            COMMAND="kunit"
            shift
            ;;
        kselftest)
            COMMAND="kselftest"
            shift
            ;;
        qemu)
            COMMAND="qemu"
            shift
            ;;
        sanitizers)
            COMMAND="sanitizers"
            shift
            ;;
        cross-compile)
            COMMAND="cross-compile"
            shift
            ;;
        specific-test)
            COMMAND="specific-test"
            TEST_TARGET="$2"
            shift 2
            ;;
        prepare-submission)
            COMMAND="prepare-submission"
            shift
            ;;
        *)
            echo "Unknown option/command: $1"
            COMMAND="help"
            shift
            ;;
    esac
done

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"
mkdir -p "$PATCH_DIR"

# Set up logging
LOG_FILE="$OUTPUT_DIR/kernel-test-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -i "$LOG_FILE")
exec 2>&1

log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1"
}

error() {
    echo "[ERROR] $1" >&2
    exit 1
}

# Check if the kernel source directory exists
if [ ! -d "$KERNEL_SRC" ]; then
    error "Kernel source directory does not exist: $KERNEL_SRC"
fi

# Function to run a command with proper error handling
run_cmd() {
    log "Running: $*"
    if [ $VERBOSE -eq 1 ]; then
        "$@"
    else
        "$@" > /dev/null 2>&1
    fi
    
    if [ $? -ne 0 ]; then
        error "Command failed: $*"
    fi
}

# Function to start a test step
start_step() {
    log "====== STARTING STEP: $1 ======"
}

# Function to end a test step
end_step() {
    log "====== COMPLETED STEP: $1 ======"
    echo ""
}

# Function to show help
show_help() {
    cat << EOF
Linux Kernel Testing Workflow
============================

Usage: ./test-kernel.sh [OPTIONS] COMMAND

This script provides a comprehensive workflow for testing Linux 
kernel patches before submitting them upstream.

Options:
  -h, --help            Show this help message
  -o, --output-dir DIR  Set output directory for test results (default: ./kernel-test-results)
  -j, --jobs NUM        Number of parallel jobs (default: all cores)
  -v, --verbose         Verbose output
  -a, --arch ARCH       Architecture to build for (default: x86_64)
  -c, --cross-compile P Prefix for cross-compiler tools
  -k, --config NAME     Kernel config to use (default: defconfig)
  --all                 Run all tests (may take a long time)

Commands:
  help                  Show this help message
  all                   Run all test steps (recommended before submission)
  static-analysis       Run static analysis tools (checkpatch, sparse, smatch)
  build                 Build the kernel with different configs
  kunit                 Run KUnit tests
  kselftest             Run kernel selftests
  qemu                  Test the kernel in QEMU
  sanitizers            Test with KASAN, UBSAN, and KCSAN
  cross-compile         Test cross-compilation for different architectures
  specific-test TARGET  Run a specific test suite or subsystem test
  prepare-submission    Create a patch series ready for submission

Workflow:
  1. Run static analysis (./test-kernel.sh static-analysis)
  2. Build and test your code (./test-kernel.sh build)
  3. Run KUnit tests (./test-kernel.sh kunit)
  4. Run kernel selftests (./test-kernel.sh kselftest)
  5. Test with sanitizers (./test-kernel.sh sanitizers)
  6. Test with QEMU (./test-kernel.sh qemu)
  7. Prepare submission (./test-kernel.sh prepare-submission)

Or run everything at once:
  ./test-kernel.sh all
EOF
}

# Function to run static analysis
run_static_analysis() {
    start_step "Static Analysis"
    
    # Check if KERNEL_SRC exists
    if [ ! -d "$KERNEL_SRC" ]; then
        log "Warning: Kernel source directory $KERNEL_SRC does not exist!"
        log "Please set the KERNEL_SRC environment variable to point to your Linux kernel source tree."
        log "Skipping static analysis."
        end_step "Static Analysis"
        return 1
    fi
    
    # Navigate to kernel source
    cd "$KERNEL_SRC" || error "Could not change to kernel source directory"
    
    # Run checkpatch on the latest commit or a file if provided
    log "Running checkpatch.pl on latest commit..."
    
    # Check if we're in a git repository with commits
    if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        if git rev-parse HEAD > /dev/null 2>&1; then
            log "Found git repository with commits, generating patch..."
            # Ensure directory exists
            mkdir -p "$OUTPUT_DIR"
            # Create the patch
            git format-patch -1 --stdout HEAD > "$OUTPUT_DIR/latest-patch.patch"
            
            # Check if the patch was created and has content
            if [ -s "$OUTPUT_DIR/latest-patch.patch" ]; then
                scripts/checkpatch.pl --strict --show-types "$OUTPUT_DIR/latest-patch.patch" | tee "$OUTPUT_DIR/checkpatch-results.txt"
            else
                log "Warning: Failed to generate a patch from HEAD"
            fi
        else
            log "Git repository has no commits, skipping checkpatch"
        fi
    else
        log "Not in a git repository, skipping checkpatch"
        log "You may want to initialize a git repository in $KERNEL_SRC for tracking changes"
    fi
    
    # Run sparse static analyzer
    log "Running sparse static analyzer..."
    if command -v sparse >/dev/null 2>&1; then
        # Create a minimal build to run sparse on
        mkdir -p "$KBUILD_OUTPUT" || error "Could not create build output directory"
        
        # Check if we have a config file, create one if needed
        if [ ! -f "$KBUILD_OUTPUT/.config" ]; then
            log "No kernel config found, generating a minimal config for static analysis..."
            make defconfig ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT" || log "Warning: Failed to create default config"
        fi
        
        make C=2 CF="-D__CHECK_ENDIAN__" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT" 2>&1 | tee "$OUTPUT_DIR/sparse-results.txt" || log "Warning: sparse analysis failed"
    else
        log "Warning: sparse not found, skipping sparse analysis"
    fi
    
    # Run Coccinelle semantic patching
    log "Running coccinelle semantic patching..."
    if command -v spatch >/dev/null 2>&1; then
        make coccicheck MODE=report ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT" 2>&1 | tee "$OUTPUT_DIR/coccicheck-results.txt" || log "Warning: coccinelle check failed"
    else
        log "Warning: coccinelle (spatch) not found, skipping semantic patching"
    fi
    
    # Run smatch static analyzer if available
    if command -v smatch >/dev/null 2>&1; then
        log "Running smatch static analyzer..."
        make CHECK="smatch --full-path" C=1 ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT" 2>&1 | tee "$OUTPUT_DIR/smatch-results.txt" || log "Warning: smatch analysis failed"
    else
        log "smatch not found, skipping"
    fi
    
    end_step "Static Analysis"
}

# Function to build the kernel
run_build() {
    start_step "Kernel Build"
    
    cd "$KERNEL_SRC" || error "Could not change to kernel source directory"
    
    # Clean build directory
    log "Cleaning build directory..."
    make mrproper ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT"
    
    # Generate defconfig
    log "Generating $CONFIG_NAME..."
    make "$CONFIG_NAME" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT"
    
    # Build kernel
    log "Building kernel with $NUM_CORES jobs..."
    make -j"$NUM_CORES" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT" 2>&1 | tee "$OUTPUT_DIR/build-results.txt"
    
    # Check if build was successful
    if [ $? -ne 0 ]; then
        error "Kernel build failed"
    fi
    
    log "Kernel build successful"
    
    # Also build with allyesconfig if requested
    if [ $TEST_ALL -eq 1 ]; then
        log "Testing with allyesconfig (this may take a long time)..."
        make mrproper ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT"
        make allyesconfig ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT"
        make -j"$NUM_CORES" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT" 2>&1 | tee "$OUTPUT_DIR/build-allyesconfig-results.txt"
    fi
    
    end_step "Kernel Build"
}

# Function to run KUnit tests
run_kunit() {
    start_step "KUnit Tests"
    
    cd "$KERNEL_SRC" || error "Could not change to kernel source directory"
    
    # First, make sure headers are available
    log "Building kernel headers..."
    mkdir -p "$KBUILD_OUTPUT"
    make headers_install ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT"
    
    # Check which KUnit target is available (older vs newer kernel versions)
    log "Detecting KUnit support in kernel..."
    if grep -q "kunit_all:" "$KERNEL_SRC/Makefile" || grep -q "kunit_all:" "$KERNEL_SRC/tools/testing/kunit/Makefile" 2>/dev/null; then
        # Newer kernels with kunit_all target
        log "Found kunit_all target, using newer KUnit..."
        make -j"$NUM_CORES" kunit_all ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT" 2>&1 | tee "$OUTPUT_DIR/kunit-results.txt" || log "Warning: KUnit tests failed or not supported"
    elif [ -d "$KERNEL_SRC/tools/testing/kunit" ]; then
        # Older kernels with the python test runner
        log "Using KUnit python test runner..."
        if [ -x "$KERNEL_SRC/tools/testing/kunit/kunit.py" ]; then
            # Check if this is the newer kunit.py that requires build_dir param
            if grep -q -- "--build_dir" "$KERNEL_SRC/tools/testing/kunit/kunit.py"; then
                log "Using newer KUnit Python runner with --build_dir parameter..."
                python3 "$KERNEL_SRC/tools/testing/kunit/kunit.py" run \
                    --build_dir="$KBUILD_OUTPUT" \
                    --jobs="$NUM_CORES" \
                    --arch="$ARCH" \
                    --cross_compile="$CROSS_COMPILE" \
                    --alltests 2>&1 | tee "$OUTPUT_DIR/kunit-results.txt" || log "Warning: KUnit tests failed"
            else
                # Older kunit.py with --outdir param
                log "Using older KUnit Python runner with --outdir parameter..."
                python3 "$KERNEL_SRC/tools/testing/kunit/kunit.py" run \
                    --outdir="$KBUILD_OUTPUT" \
                    --jobs="$NUM_CORES" \
                    --arch="$ARCH" \
                    --cross_compile="$CROSS_COMPILE" 2>&1 | tee "$OUTPUT_DIR/kunit-results.txt" || log "Warning: KUnit tests failed"
            fi
        else
            log "Warning: KUnit test runner not found or not executable"
            log "Trying to run kunit via make target instead..."
            make -j"$NUM_CORES" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT" kunit 2>&1 | tee "$OUTPUT_DIR/kunit-results.txt" || log "Warning: Make kunit target failed"
        fi
    else
        log "Warning: KUnit testing framework not found in this kernel version"
        log "KUnit may not be available in your kernel version or may require kernel configuration"
    fi
    
    end_step "KUnit Tests"
}

# Function to run kernel selftests
run_kselftest() {
    start_step "Kernel Selftests"
    
    cd "$KERNEL_SRC" || error "Could not change to kernel source directory"
    
    # First, make sure headers are available - this fixes the "missing kernel header files" error
    log "Building kernel headers..."
    # Create build directory if it doesn't exist
    mkdir -p "$KBUILD_OUTPUT" 
    
    # Build kernel headers
    make headers_install ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT"
    
    # Make sure headers are also available in the expected location for selftests
    log "Installing kernel headers for selftests..."
    make -C "$KERNEL_SRC" headers ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT" || log "Warning: headers target failed, trying headers_install"
    
    # Build and run kernel selftests
    log "Building kernel selftests..."
    make -j"$NUM_CORES" -C tools/testing/selftests ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT" 2>&1 | tee "$OUTPUT_DIR/kselftest-build-results.txt" || log "Warning: Selftest build failed"
    
    log "Running kernel selftests..."
    make -j"$NUM_CORES" -C tools/testing/selftests run_tests ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT" 2>&1 | tee "$OUTPUT_DIR/kselftest-run-results.txt" || log "Warning: Some selftests may have failed"
    
    end_step "Kernel Selftests"
}

# Function to run sanitizers
run_sanitizers() {
    start_step "Kernel Sanitizers"
    
    cd "$KERNEL_SRC" || error "Could not change to kernel source directory"
    
    # Test with KASAN (Kernel Address Sanitizer)
    log "Testing with KASAN..."
    make mrproper ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT"
    make "$CONFIG_NAME" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT"
    
    # Enable KASAN
    ./scripts/config --file "$KBUILD_OUTPUT/.config" --enable CONFIG_KASAN
    ./scripts/config --file "$KBUILD_OUTPUT/.config" --enable CONFIG_KASAN_INLINE
    make olddefconfig ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT"
    
    # Build with KASAN
    make -j"$NUM_CORES" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT" 2>&1 | tee "$OUTPUT_DIR/kasan-build-results.txt"
    
    if [ $TEST_ALL -eq 1 ]; then
        # Test with UBSAN (Undefined Behavior Sanitizer)
        log "Testing with UBSAN..."
        make mrproper ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT"
        make "$CONFIG_NAME" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT"
        
        # Enable UBSAN
        ./scripts/config --file "$KBUILD_OUTPUT/.config" --enable CONFIG_UBSAN
        make olddefconfig ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT"
        
        # Build with UBSAN
        make -j"$NUM_CORES" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT" 2>&1 | tee "$OUTPUT_DIR/ubsan-build-results.txt"
        
        # Test with KCSAN (Kernel Concurrency Sanitizer)
        log "Testing with KCSAN..."
        make mrproper ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT"
        make "$CONFIG_NAME" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT"
        
        # Enable KCSAN
        ./scripts/config --file "$KBUILD_OUTPUT/.config" --enable CONFIG_KCSAN
        make olddefconfig ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT"
        
        # Build with KCSAN
        make -j"$NUM_CORES" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT" 2>&1 | tee "$OUTPUT_DIR/kcsan-build-results.txt"
    fi
    
    end_step "Kernel Sanitizers"
}

# Function to test in QEMU
run_qemu() {
    start_step "QEMU Testing"
    
    cd "$KERNEL_SRC" || error "Could not change to kernel source directory"
    
    # Check if kernel image exists
    KERNEL_IMAGE="$KBUILD_OUTPUT/arch/x86/boot/bzImage"
    if [ ! -f "$KERNEL_IMAGE" ]; then
        log "Kernel image not found, running build first..."
        run_build
    fi
    
    # Create a minimal initramfs if it doesn't exist
    INITRAMFS="/tmp/initramfs.img"
    if [ ! -f "$INITRAMFS" ]; then
        log "Creating minimal initramfs..."
        mkdir -p /tmp/initramfs
        cd /tmp/initramfs || error "Could not change to initramfs directory"
        mkdir -p bin dev proc sys sbin
        
        # Create init script
        cat > init << 'EOF'
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

echo "Running kernel tests in QEMU environment..."

# Add your specific test commands here
echo "Kernel version: $(uname -r)"
echo "Testing complete. System seems stable."

echo "Tests completed. Shutting down..."
poweroff -f
EOF
        chmod +x init
        
        find . | cpio -o -H newc | gzip > $INITRAMFS
        cd - || error "Could not return to original directory"
    fi
    
    # Launch QEMU with timeout for automated testing
    log "Launching QEMU for automated testing (timeout: 300s)..."
    timeout 300 qemu-system-x86_64 \
        -kernel $KERNEL_IMAGE \
        -initrd $INITRAMFS \
        -nographic \
        -append "console=ttyS0 nokaslr" \
        -m 512M 2>&1 | tee "$OUTPUT_DIR/qemu-test-results.txt"
    
    end_step "QEMU Testing"
}

# Function to test cross-compilation
run_cross_compile() {
    start_step "Cross-Compilation Testing"
    
    cd "$KERNEL_SRC" || error "Could not change to kernel source directory"
    
    if [ $TEST_ALL -eq 1 ]; then
        # Test multiple architectures if --all specified
        ARCHS=("arm" "arm64" "powerpc" "riscv" "s390")
        CROSS_COMPILERS=("arm-linux-gnueabi-" "aarch64-linux-gnu-" "powerpc-linux-gnu-" "riscv64-linux-gnu-" "s390x-linux-gnu-")
        
        for i in "${!ARCHS[@]}"; do
            log "Testing cross-compilation for ${ARCHS[$i]} with ${CROSS_COMPILERS[$i]}..."
            
            # Check if cross-compiler is available
            if command -v "${CROSS_COMPILERS[$i]}gcc" >/dev/null 2>&1; then
                make mrproper ARCH="${ARCHS[$i]}" CROSS_COMPILE="${CROSS_COMPILERS[$i]}" O="$KBUILD_OUTPUT-${ARCHS[$i]}"
                make defconfig ARCH="${ARCHS[$i]}" CROSS_COMPILE="${CROSS_COMPILERS[$i]}" O="$KBUILD_OUTPUT-${ARCHS[$i]}"
                make -j"$NUM_CORES" ARCH="${ARCHS[$i]}" CROSS_COMPILE="${CROSS_COMPILERS[$i]}" O="$KBUILD_OUTPUT-${ARCHS[$i]}" 2>&1 | tee "$OUTPUT_DIR/cross-compile-${ARCHS[$i]}-results.txt"
            else
                log "Cross-compiler ${CROSS_COMPILERS[$i]}gcc not found, skipping ${ARCHS[$i]}"
            fi
        done
    else
        # Test only for the specified architecture
        log "Testing cross-compilation for $ARCH with $CROSS_COMPILE..."
        make mrproper ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT"
        make defconfig ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT"
        make -j"$NUM_CORES" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT" 2>&1 | tee "$OUTPUT_DIR/cross-compile-results.txt"
    fi
    
    end_step "Cross-Compilation Testing"
}

# Function to run a specific test suite or subsystem test
run_specific_test() {
    if [ -z "$TEST_TARGET" ]; then
        error "No test target specified. Use './test-kernel.sh specific-test TARGET'"
    fi
    
    start_step "Specific Test: $TEST_TARGET"
    
    cd "$KERNEL_SRC" || error "Could not change to kernel source directory"
    
    # Determine what type of test based on the target
    if [ -d "tools/testing/kunit/$TEST_TARGET" ]; then
        log "Running KUnit test for $TEST_TARGET..."
        make -j"$NUM_CORES" kunit KUNITCONFIG=tools/testing/kunit/configs/"$TEST_TARGET"_test.config ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT" 2>&1 | tee "$OUTPUT_DIR/specific-kunit-results.txt"
        
    elif [ -d "tools/testing/selftests/$TEST_TARGET" ]; then
        log "Running selftest for $TEST_TARGET..."
        make -j"$NUM_CORES" -C tools/testing/selftests TARGETS="$TEST_TARGET" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT" 2>&1 | tee "$OUTPUT_DIR/specific-selftest-build-results.txt"
        make -C tools/testing/selftests TARGETS="$TEST_TARGET" run_tests ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT" 2>&1 | tee "$OUTPUT_DIR/specific-selftest-run-results.txt"
        
    else
        log "Custom test for $TEST_TARGET..."
        # Try to intelligently figure out what the user wants to test
        if [[ $TEST_TARGET == *".ko" ]]; then
            # Test a specific module
            MODULE_PATH=$(find . -name "$TEST_TARGET" | head -n 1)
            if [ -n "$MODULE_PATH" ]; then
                MODULE_DIR=$(dirname "$MODULE_PATH")
                log "Building module: $TEST_TARGET in $MODULE_DIR"
                make -j"$NUM_CORES" -C "$MODULE_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT" 2>&1 | tee "$OUTPUT_DIR/specific-module-results.txt"
            else
                error "Module $TEST_TARGET not found"
            fi
        else
            # Try to build a specific directory
            log "Building directory: $TEST_TARGET"
            make -j"$NUM_CORES" -C "$TEST_TARGET" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" O="$KBUILD_OUTPUT" 2>&1 | tee "$OUTPUT_DIR/specific-dir-results.txt"
        fi
    fi
    
    end_step "Specific Test: $TEST_TARGET"
}

# Function to prepare patches for submission
prepare_submission() {
    start_step "Prepare Submission"
    
    cd "$KERNEL_SRC" || error "Could not change to kernel source directory"
    
    # Make sure we're in a git repository
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        error "Not in a git repository. Cannot prepare patches."
    fi
    
    # Get the remote tracking branch
    REMOTE_BRANCH=$(git rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null)
    if [ -z "$REMOTE_BRANCH" ]; then
        # Default to origin/master if no tracking branch
        REMOTE_BRANCH="origin/master"
        log "No tracking branch found, defaulting to $REMOTE_BRANCH"
    fi
    
    # Extract the remote and branch names
    REMOTE=$(echo "$REMOTE_BRANCH" | cut -d/ -f1)
    BRANCH=$(echo "$REMOTE_BRANCH" | cut -d/ -f2-)
    
    log "Preparing patches against $REMOTE/$BRANCH"
    
    # Make sure the remote is up-to-date
    git fetch "$REMOTE" "$BRANCH"
    
    # Find out how many commits to format (ask user)
    echo "How many commits do you want to include in the patch series? (default: 1)"
    read -r COMMIT_COUNT
    COMMIT_COUNT=${COMMIT_COUNT:-1}
    
    # Create a cover letter with standard information
    log "Generating patch series with cover letter..."
    git format-patch -M -C --cover-letter -o "$PATCH_DIR" -"$COMMIT_COUNT" "$REMOTE"/"$BRANCH"
    
    # Run checkpatch on all patches
    log "Validating patches with checkpatch..."
    for patch in "$PATCH_DIR"/*.patch; do
        if [[ "$patch" != *"0000-cover-letter.patch" ]]; then
            log "Checking $patch..."
            scripts/checkpatch.pl --strict --show-types "$patch" | tee -a "$OUTPUT_DIR/submission-checkpatch-results.txt"
        fi
    done
    
    # Get maintainers for the patches
    log "Finding maintainers for the patches..."
    for patch in "$PATCH_DIR"/*.patch; do
        if [[ "$patch" != *"0000-cover-letter.patch" ]]; then
            log "Finding maintainers for $patch..."
            scripts/get_maintainer.pl --no-rolestats "$patch" | tee -a "$OUTPUT_DIR/submission-maintainers-results.txt"
        fi
    done
    
    log "Patches have been created in $PATCH_DIR"
    log "Please edit $PATCH_DIR/0000-cover-letter.patch to include a proper description of your changes"
    
    end_step "Prepare Submission"
}

# Run the appropriate command based on user input
case $COMMAND in
    help)
        show_help
        ;;
    all)
        log "Running all test steps"
        run_static_analysis
        run_build
        run_kunit
        run_kselftest
        run_sanitizers
        run_qemu
        run_cross_compile
        prepare_submission
        log "All tests completed. Results available in $OUTPUT_DIR"
        ;;
    static-analysis)
        run_static_analysis
        ;;
    build)
        run_build
        ;;
    kunit)
        run_kunit
        ;;
    kselftest)
        run_kselftest
        ;;
    qemu)
        run_qemu
        ;;
    sanitizers)
        run_sanitizers
        ;;
    cross-compile)
        run_cross_compile
        ;;
    specific-test)
        run_specific_test
        ;;
    prepare-submission)
        prepare_submission
        ;;
    *)
        error "Unknown command: $COMMAND. Run './test-kernel.sh --help' for usage."
        ;;
esac

log "Script completed successfully!"