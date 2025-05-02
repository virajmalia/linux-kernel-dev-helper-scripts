obj-m += hello.o

# Default to running kernel if KERNEL_SRC is not specified
KERNEL_SRC ?= /lib/modules/$(shell uname -r)/build
# Build output directory (can be set to a custom location)
KBUILD_OUTPUT ?= $(KERNEL_SRC)
# Optional kernel version parameter
KERNEL_VERSION ?= $(shell uname -r)

all:
	make -C $(KERNEL_SRC) M=$(PWD) O=$(KBUILD_OUTPUT) modules

# Basic clean - removes most build artifacts
clean:
	make -C $(KERNEL_SRC) M=$(PWD) O=$(KBUILD_OUTPUT) clean

# Deep clean - removes ALL build artifacts including backups and cached files
distclean: clean
	@rm -f *.o.cmd *.ko.cmd .*.o.cmd .*.ko.cmd
	@rm -f *.mod *.mod.c *.symvers *.order
	@rm -f .*.mod .*.mod.c .*.symvers .*.order
	@rm -f .*cmd .tmp_versions/*
	@rm -rf .tmp_versions
	@rm -f *~ core

# Remove EVERYTHING, including generated files, editor backups, patches, etc.
mrproper: distclean
	@rm -f *.orig *.rej
	@rm -f *.patch *.diff
	@rm -f .*.sw[a-p]
	@rm -f *.gcno *.gcda
	@rm -f cscope.* TAGS tags

# Reset - wipe build directory and start fresh
reset: mrproper
	@echo "All build artifacts removed. Starting fresh."

# Target to build against the custom kernel in /usr/src/linux
custom:
	$(MAKE) KERNEL_SRC=/usr/src/linux KBUILD_OUTPUT=/kernel-build

# Target to build against a specified kernel version
# Usage: make version KERNEL_VERSION=5.15.0-58-generic
version:
	$(MAKE) KERNEL_SRC=/lib/modules/$(KERNEL_VERSION)/build

# Target to build against all installed kernels
all-versions:
	@echo "Building module for all installed kernel versions..."
	@for kver in $$(ls -1 /lib/modules/ | grep -v "extramodules"); do \
		echo "Building for kernel $${kver}..."; \
		$(MAKE) version KERNEL_VERSION=$${kver} || echo "Failed to build for $${kver}"; \
	done

# Target to clean build artifacts for all installed kernels
clean-all-versions:
	@echo "Cleaning module for all installed kernel versions..."
	@for kver in $$(ls -1 /lib/modules/ | grep -v "extramodules"); do \
		echo "Cleaning for kernel $${kver}..."; \
		$(MAKE) clean KERNEL_VERSION=$${kver} || echo "Failed to clean for $${kver}"; \
	done

# Install module(s)
install:
	make -C $(KERNEL_SRC) M=$(PWD) O=$(KBUILD_OUTPUT) modules_install

# Clean and rebuild from scratch
rebuild: distclean all

help:
	@echo "Available targets:"
	@echo "  all             - Build module against running kernel (default)"
	@echo "  clean           - Remove most build artifacts for current kernel"
	@echo "  distclean       - Remove all build artifacts for current kernel"
	@echo "  mrproper        - Remove everything including editor backups and patches"
	@echo "  reset           - Complete cleanup to start fresh" 
	@echo "  rebuild         - Clean everything and rebuild from scratch"
	@echo "  custom          - Build module against custom kernel in /usr/src/linux"
	@echo "  version         - Build module against specific kernel version"
	@echo "                    Usage: make version KERNEL_VERSION=5.15.0-58-generic"
	@echo "  all-versions    - Build module against all installed kernel versions"
	@echo "  clean-all-versions - Clean build artifacts for all kernel versions"
	@echo "  install         - Install the built module(s)"
	@echo ""
	@echo "Environment variables:"
	@echo "  KERNEL_SRC     - Path to kernel source (default: running kernel)"
	@echo "  KBUILD_OUTPUT  - Path to kernel build output (default: same as KERNEL_SRC)"
	@echo "  KERNEL_VERSION - Kernel version to build against (default: running kernel)"