# Linux Kernel Development Environment

A comprehensive development environment for Linux kernel development, testing, and patch submission. This project provides a structured approach to kernel development with scripts to automate common tasks.

## Features

- **Automated kernel building**: Scripts for building the Linux kernel with various configurations
- **Comprehensive testing suite**: Run various kernel tests including KUnit, selftests, and static analysis
- **QEMU integration**: Test your kernel changes in a virtual environment
- **Multiple sanitizers support**: Test with KASAN, UBSAN, and KCSAN
- **Cross-compilation testing**: Verify your code works across multiple architectures
- **Patch preparation**: Tools to prepare and validate patches for submission upstream

## Prerequisites

- Linux-based operating system
- Build essentials (gcc, make, etc.)
- QEMU for virtual testing
- Git for version control
- Various development tools (installed by setup.sh)

## Getting Started

1. Clone this repository:
   ```
   git clone https://github.com/virajmalia/linux-kernel-dev-helper-scripts.git
   cd linux-kernel-dev-helper-scripts
   ```

2. Run the setup script to install necessary dependencies and download the Linux kernel:
   ```
   sudo ./scripts/setup.sh
   ```

3. Source the environment variables:
   ```
   source /workspace/.env.kernel
   ```

## Usage

### Building the Kernel

```bash
./scripts/build-kernel.sh             # Build with default options
./scripts/build-kernel.sh --clean     # Perform a clean build
./scripts/build-kernel.sh --type modules  # Build only kernel modules
./scripts/build-kernel.sh -j 8        # Build using 8 cores
./scripts/build-kernel.sh --menuconfig  # Run menuconfig before building
./scripts/build-kernel.sh --version v6.6  # Build specific kernel version
```

### Testing the Kernel

```bash
./scripts/test-kernel.sh static-analysis  # Run static analysis tools
./scripts/test-kernel.sh build            # Just build the kernel
./scripts/test-kernel.sh kunit            # Run KUnit tests
./scripts/test-kernel.sh kselftest        # Run kernel selftests
./scripts/test-kernel.sh sanitizers       # Test with sanitizers (KASAN, etc.)
./scripts/test-kernel.sh qemu             # Test in QEMU
./scripts/test-kernel.sh all              # Run all tests (comprehensive)
```

### Preparing Patches for Submission

```bash
./scripts/test-kernel.sh prepare-submission
```

## Project Structure

- `scripts/` - Contains automation scripts for building and testing
- `kernel-patches/` - Directory for storing patches
- `kernel-test-results/` - Contains test results and logs
- `src/` - Example source code (e.g., kernel module examples)

## Example Kernel Module

The repository includes an example kernel module in `src/kernel-module-example` that you can use as a starting point for your own kernel modules.

To build and load the example module:

```bash
cd src/kernel-module-example
make
sudo insmod hello.ko
dmesg | tail
```

## CI/CD Integration

This project includes GitHub Actions workflows for automated building and testing of the Linux kernel. See `.github/workflows/` for details.

## License

This project is licensed under the GNU General Public License v2.0 - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.