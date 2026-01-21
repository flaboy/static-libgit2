# Makefile for building libgit2 static framework
# Uses dependency tracking to avoid rebuilding
# All commands output to build.log using tee
# Supports parallel builds with -jN option

REPO_ROOT := $(shell pwd)
DEPENDENCIES_ROOT := $(REPO_ROOT)/dependencies
BUILD_LOG := $(REPO_ROOT)/build.log

AVAILABLE_PLATFORMS := iphoneos iphonesimulator maccatalyst maccatalyst-arm64 macosx-arm64 macosx

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
NC := \033[0m # No Color

# Detect number of CPU cores for parallel builds
NUM_CORES := $(shell sysctl -n hw.ncpu 2>/dev/null || echo 8)

# Logging function - all commands should use this
# Note: tee -a is generally safe for parallel writes in practice
LOG = @echo "$(GREEN)[$(shell date +%H:%M:%S)]$(NC) $(1)" | tee -a $(BUILD_LOG)

.PHONY: all clean clean-deps help copy_modulemap
.DEFAULT_GOAL := all

# Main target
all: Clibgit2.xcframework | $(BUILD_LOG)
	@echo "$(GREEN)Build completed successfully!$(NC)" | tee -a $(BUILD_LOG)

# Initialize build log
$(BUILD_LOG):
	@echo "Build started at $(shell date)" > $(BUILD_LOG)
	@echo "========================================" >> $(BUILD_LOG)
	@echo "Parallel build: Use 'make -j$(NUM_CORES)' for faster builds" >> $(BUILD_LOG)
	@echo "Each platform builds independently in separate directories" >> $(BUILD_LOG)

# Clean targets
clean:
	@$(call LOG,"Cleaning build artifacts...")
	@rm -rf $(DEPENDENCIES_ROOT) 2>&1 | tee -a $(BUILD_LOG) || true
	@rm -rf $(REPO_ROOT)/*.xcframework 2>&1 | tee -a $(BUILD_LOG) || true
	@rm -rf $(REPO_ROOT)/install* 2>&1 | tee -a $(BUILD_LOG) || true
	@rm -f $(BUILD_LOG) 2>&1 | tee -a $(BUILD_LOG) 2>/dev/null || true

clean-deps:
	@$(call LOG,"Cleaning dependencies...")
	@rm -rf $(DEPENDENCIES_ROOT) 2>&1 | tee -a $(BUILD_LOG) || true

# Create directories
$(DEPENDENCIES_ROOT):
	@mkdir -p $(DEPENDENCIES_ROOT) 2>&1 | tee -a $(BUILD_LOG)

# Platform-specific install directories
INSTALL_DIRS := $(foreach p,$(AVAILABLE_PLATFORMS),install/$(p)/lib install-openssl/$(p)/lib install-libssh2/$(p)/lib install/$(p)/include install-openssl/$(p)/include install-libssh2/$(p)/include)
$(INSTALL_DIRS):
	@mkdir -p $@ 2>&1 | tee -a $(BUILD_LOG)

# Download sources (markers to track downloads)
OPENSSL_TAR := $(DEPENDENCIES_ROOT)/openssl-3.6.0.tar.gz
LIBSSH2_TAR := $(DEPENDENCIES_ROOT)/libssh2-1.11.1.tar.gz
LIBGIT2_ZIP := $(DEPENDENCIES_ROOT)/v1.8.4.zip

$(OPENSSL_TAR): | $(DEPENDENCIES_ROOT) $(BUILD_LOG)
	@$(call LOG,"Downloading OpenSSL...")
	@cd $(DEPENDENCIES_ROOT) && (test -f openssl-3.6.0.tar.gz || wget -q https://github.com/openssl/openssl/releases/download/openssl-3.6.0/openssl-3.6.0.tar.gz) 2>&1 | tee -a $(BUILD_LOG)

$(LIBSSH2_TAR): | $(DEPENDENCIES_ROOT) $(BUILD_LOG)
	@$(call LOG,"Downloading libssh2...")
	@cd $(DEPENDENCIES_ROOT) && (test -f libssh2-1.11.1.tar.gz || wget -q https://www.libssh2.org/download/libssh2-1.11.1.tar.gz) 2>&1 | tee -a $(BUILD_LOG)

$(LIBGIT2_ZIP): | $(DEPENDENCIES_ROOT) $(BUILD_LOG)
	@$(call LOG,"Downloading libgit2...")
	@cd $(DEPENDENCIES_ROOT) && (test -f v1.8.4.zip || wget -q https://github.com/libgit2/libgit2/archive/refs/tags/v1.8.4.zip) 2>&1 | tee -a $(BUILD_LOG)

# Build OpenSSL for each platform
define openssl_platform_template
OPENSSL_$(1)_LIB := install-openssl/$(1)/lib/libssl.a

$$(OPENSSL_$(1)_LIB): $(OPENSSL_TAR) | install-openssl/$(1)/lib $(BUILD_LOG)
	@$$(call LOG,"Building OpenSSL for $(1)...")
	@bash -c 'set -e; \
		cd $$(DEPENDENCIES_ROOT); \
		rm -rf openssl-3.6.0-$(1); \
		tar xzf openssl-3.6.0.tar.gz 2>&1 | tee -a $$(BUILD_LOG); \
		mv openssl-3.6.0 openssl-3.6.0-$(1) 2>&1 | tee -a $$(BUILD_LOG) || true; \
		cd openssl-3.6.0-$(1); \
		case "$(1)" in \
			iphoneos) \
				TARGET_OS=ios64-cross; \
				export CFLAGS="-isysroot $$(shell xcodebuild -version -sdk iphoneos Path) -arch arm64 -mios-version-min=13.0"; \
				;; \
			iphonesimulator) \
				TARGET_OS=iossimulator-xcrun; \
				export CFLAGS="-isysroot $$(shell xcodebuild -version -sdk iphonesimulator Path) -miphonesimulator-version-min=13.0"; \
				;; \
			maccatalyst) \
				TARGET_OS=darwin64-x86_64-cc; \
				export CFLAGS="-isysroot $$(shell xcodebuild -version -sdk macosx Path) -target x86_64-apple-ios14.1-macabi"; \
				;; \
			maccatalyst-arm64) \
				TARGET_OS=darwin64-arm64-cc; \
				export CFLAGS="-isysroot $$(shell xcodebuild -version -sdk macosx Path) -target arm64-apple-ios14.1-macabi"; \
				;; \
			macosx) \
				TARGET_OS=darwin64-x86_64-cc; \
				export CFLAGS="-isysroot $$(shell xcodebuild -version -sdk macosx Path)"; \
				;; \
			macosx-arm64) \
				TARGET_OS=darwin64-arm64-cc; \
				export CFLAGS="-isysroot $$(shell xcodebuild -version -sdk macosx Path)"; \
				;; \
		esac; \
		./Configure --prefix=$$(REPO_ROOT)/install-openssl/$(1) \
			--openssldir=$$(REPO_ROOT)/install-openssl/$(1) \
			$$$$TARGET_OS no-shared no-dso no-hw no-engine 2>&1 | tee -a $$(BUILD_LOG); \
		make 2>&1 | tee -a $$(BUILD_LOG); \
		make install_sw install_ssldirs 2>&1 | tee -a $$(BUILD_LOG); \
		unset CFLAGS \
	'
endef

$(foreach p,$(AVAILABLE_PLATFORMS),$(eval $(call openssl_platform_template,$(p))))

# Build libssh2 for each platform
define libssh2_platform_template
LIBSSH2_$(1)_LIB := install-libssh2/$(1)/lib/libssh2.a

$$(LIBSSH2_$(1)_LIB): $(LIBSSH2_TAR) $$(OPENSSL_$(1)_LIB) | install-libssh2/$(1)/lib $(BUILD_LOG)
	@$$(call LOG,"Building libssh2 for $(1)...")
	@bash -c 'set -e; \
		cd $$(DEPENDENCIES_ROOT); \
		rm -rf libssh2-1.11.1-$(1); \
		tar xzf libssh2-1.11.1.tar.gz 2>&1 | tee -a $$(BUILD_LOG); \
		mv libssh2-1.11.1 libssh2-1.11.1-$(1) 2>&1 | tee -a $$(BUILD_LOG) || true; \
		cd libssh2-1.11.1-$(1); \
		rm -rf build && mkdir build && cd build; \
		case "$(1)" in \
			iphoneos) \
				SYSROOT=$$$$(xcodebuild -version -sdk iphoneos Path); \
				cmake -DBUILD_SHARED_LIBS=NO -DCMAKE_BUILD_TYPE=Release \
					-DCMAKE_C_COMPILER_WORKS=ON -DCMAKE_CXX_COMPILER_WORKS=ON \
					-DCMAKE_OSX_DEPLOYMENT_TARGET=12.4 \
					-DCMAKE_INSTALL_PREFIX=$$(REPO_ROOT)/install-libssh2/$(1) \
					-DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_SYSROOT=$$$$SYSROOT \
					-DCRYPTO_BACKEND=OpenSSL \
					-DOPENSSL_ROOT_DIR=$$(REPO_ROOT)/install-openssl/$(1) \
					-DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF .. 2>&1 | tee -a $$(BUILD_LOG); \
				;; \
			iphonesimulator) \
				ARCH=$$$$(arch); \
				SYSROOT=$$$$(xcodebuild -version -sdk iphonesimulator Path); \
				cmake -DBUILD_SHARED_LIBS=NO -DCMAKE_BUILD_TYPE=Release \
					-DCMAKE_C_COMPILER_WORKS=ON -DCMAKE_CXX_COMPILER_WORKS=ON \
					-DCMAKE_OSX_DEPLOYMENT_TARGET=12.4 \
					-DCMAKE_INSTALL_PREFIX=$$(REPO_ROOT)/install-libssh2/$(1) \
					-DCMAKE_OSX_ARCHITECTURES=$$$$ARCH -DCMAKE_OSX_SYSROOT=$$$$SYSROOT \
					-DCRYPTO_BACKEND=OpenSSL \
					-DOPENSSL_ROOT_DIR=$$(REPO_ROOT)/install-openssl/$(1) \
					-DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF .. 2>&1 | tee -a $$(BUILD_LOG); \
				;; \
			maccatalyst) \
				SYSROOT=$$$$(xcodebuild -version -sdk macosx Path); \
				cmake -DBUILD_SHARED_LIBS=NO -DCMAKE_BUILD_TYPE=Release \
					-DCMAKE_C_COMPILER_WORKS=ON -DCMAKE_CXX_COMPILER_WORKS=ON \
					-DCMAKE_OSX_DEPLOYMENT_TARGET=12.4 \
					-DCMAKE_INSTALL_PREFIX=$$(REPO_ROOT)/install-libssh2/$(1) \
					-DCMAKE_C_FLAGS="-target x86_64-apple-ios14.1-macabi" -DCMAKE_OSX_ARCHITECTURES=x86_64 \
					-DCRYPTO_BACKEND=OpenSSL \
					-DOPENSSL_ROOT_DIR=$$(REPO_ROOT)/install-openssl/$(1) \
					-DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF .. 2>&1 | tee -a $$(BUILD_LOG); \
				;; \
			maccatalyst-arm64) \
				SYSROOT=$$$$(xcodebuild -version -sdk macosx Path); \
				cmake -DBUILD_SHARED_LIBS=NO -DCMAKE_BUILD_TYPE=Release \
					-DCMAKE_C_COMPILER_WORKS=ON -DCMAKE_CXX_COMPILER_WORKS=ON \
					-DCMAKE_OSX_DEPLOYMENT_TARGET=12.4 \
					-DCMAKE_INSTALL_PREFIX=$$(REPO_ROOT)/install-libssh2/$(1) \
					-DCMAKE_C_FLAGS="-target arm64-apple-ios14.1-macabi" -DCMAKE_OSX_ARCHITECTURES=arm64 \
					-DCRYPTO_BACKEND=OpenSSL \
					-DOPENSSL_ROOT_DIR=$$(REPO_ROOT)/install-openssl/$(1) \
					-DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF .. 2>&1 | tee -a $$(BUILD_LOG); \
				;; \
			macosx) \
				cmake -DBUILD_SHARED_LIBS=NO -DCMAKE_BUILD_TYPE=Release \
					-DCMAKE_C_COMPILER_WORKS=ON -DCMAKE_CXX_COMPILER_WORKS=ON \
					-DCMAKE_OSX_DEPLOYMENT_TARGET=12.4 \
					-DCMAKE_INSTALL_PREFIX=$$(REPO_ROOT)/install-libssh2/$(1) \
					-DCMAKE_OSX_ARCHITECTURES=x86_64 \
					-DCRYPTO_BACKEND=OpenSSL \
					-DOPENSSL_ROOT_DIR=$$(REPO_ROOT)/install-openssl/$(1) \
					-DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF .. 2>&1 | tee -a $$(BUILD_LOG); \
				;; \
			macosx-arm64) \
				cmake -DBUILD_SHARED_LIBS=NO -DCMAKE_BUILD_TYPE=Release \
					-DCMAKE_C_COMPILER_WORKS=ON -DCMAKE_CXX_COMPILER_WORKS=ON \
					-DCMAKE_OSX_DEPLOYMENT_TARGET=12.4 \
					-DCMAKE_INSTALL_PREFIX=$$(REPO_ROOT)/install-libssh2/$(1) \
					-DCMAKE_OSX_ARCHITECTURES=arm64 \
					-DCRYPTO_BACKEND=OpenSSL \
					-DOPENSSL_ROOT_DIR=$$(REPO_ROOT)/install-openssl/$(1) \
					-DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF .. 2>&1 | tee -a $$(BUILD_LOG); \
				;; \
		esac; \
		cmake --build . --target install 2>&1 | tee -a $$(BUILD_LOG) \
	'
endef

$(foreach p,$(AVAILABLE_PLATFORMS),$(eval $(call libssh2_platform_template,$(p))))

# Build libgit2 for each platform
define libgit2_platform_template
LIBGIT2_$(1)_LIB := install/$(1)/lib/libgit2_all.a

$$(LIBGIT2_$(1)_LIB): $(LIBGIT2_ZIP) $$(OPENSSL_$(1)_LIB) $$(LIBSSH2_$(1)_LIB) | install/$(1)/lib $(BUILD_LOG)
	@$$(call LOG,"Building libgit2 for $(1)...")
	@bash -c 'set -e; \
		cd $$(DEPENDENCIES_ROOT); \
		rm -rf libgit2-1.8.4-$(1); \
		ditto -x -k --sequesterRsrc --rsrc v1.8.4.zip ./ 2>&1 | tee -a $$(BUILD_LOG); \
		mv libgit2-1.8.4 libgit2-1.8.4-$(1) 2>&1 | tee -a $$(BUILD_LOG) || true; \
		cd libgit2-1.8.4-$(1); \
		rm -rf build && mkdir build && cd build; \
		case "$(1)" in \
			iphoneos) \
				SYSROOT=$$$$(xcodebuild -version -sdk iphoneos Path); \
				cmake -DBUILD_SHARED_LIBS=NO -DCMAKE_BUILD_TYPE=Release \
					-DCMAKE_C_COMPILER_WORKS=ON -DCMAKE_CXX_COMPILER_WORKS=ON \
					-DCMAKE_OSX_DEPLOYMENT_TARGET=12.4 \
					-DCMAKE_INSTALL_PREFIX=$$(REPO_ROOT)/install/$(1) \
					-DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_SYSROOT=$$$$SYSROOT \
					-DBUILD_CLAR=NO -DBUILD_TESTS=OFF -DUSE_SSH=ON -DGIT_SSH_MEMORY_CREDENTIALS=1 \
					-DCMAKE_PREFIX_PATH="$$(REPO_ROOT)/install-libssh2/$(1);$$(REPO_ROOT)/install-openssl/$(1)" .. 2>&1 | tee -a $$(BUILD_LOG); \
				;; \
			iphonesimulator) \
				ARCH=$$$$(arch); \
				SYSROOT=$$$$(xcodebuild -version -sdk iphonesimulator Path); \
				cmake -DBUILD_SHARED_LIBS=NO -DCMAKE_BUILD_TYPE=Release \
					-DCMAKE_C_COMPILER_WORKS=ON -DCMAKE_CXX_COMPILER_WORKS=ON \
					-DCMAKE_OSX_DEPLOYMENT_TARGET=12.4 \
					-DCMAKE_INSTALL_PREFIX=$$(REPO_ROOT)/install/$(1) \
					-DCMAKE_OSX_ARCHITECTURES=$$$$ARCH -DCMAKE_OSX_SYSROOT=$$$$SYSROOT \
					-DBUILD_CLAR=NO -DBUILD_TESTS=OFF -DUSE_SSH=ON -DGIT_SSH_MEMORY_CREDENTIALS=1 \
					-DCMAKE_PREFIX_PATH="$$(REPO_ROOT)/install-libssh2/$(1);$$(REPO_ROOT)/install-openssl/$(1)" .. 2>&1 | tee -a $$(BUILD_LOG); \
				;; \
			maccatalyst) \
				SYSROOT=$$$$(xcodebuild -version -sdk macosx Path); \
				cmake -DBUILD_SHARED_LIBS=NO -DCMAKE_BUILD_TYPE=Release \
					-DCMAKE_C_COMPILER_WORKS=ON -DCMAKE_CXX_COMPILER_WORKS=ON \
					-DCMAKE_OSX_DEPLOYMENT_TARGET=12.4 \
					-DCMAKE_INSTALL_PREFIX=$$(REPO_ROOT)/install/$(1) \
					-DCMAKE_C_FLAGS="-target x86_64-apple-ios14.1-macabi" -DCMAKE_OSX_ARCHITECTURES=x86_64 \
					-DBUILD_CLAR=NO -DBUILD_TESTS=OFF -DUSE_SSH=ON -DGIT_SSH_MEMORY_CREDENTIALS=1 \
					-DCMAKE_PREFIX_PATH="$$(REPO_ROOT)/install-libssh2/$(1);$$(REPO_ROOT)/install-openssl/$(1)" .. 2>&1 | tee -a $$(BUILD_LOG); \
				;; \
			maccatalyst-arm64) \
				SYSROOT=$$$$(xcodebuild -version -sdk macosx Path); \
				cmake -DBUILD_SHARED_LIBS=NO -DCMAKE_BUILD_TYPE=Release \
					-DCMAKE_C_COMPILER_WORKS=ON -DCMAKE_CXX_COMPILER_WORKS=ON \
					-DCMAKE_OSX_DEPLOYMENT_TARGET=12.4 \
					-DCMAKE_INSTALL_PREFIX=$$(REPO_ROOT)/install/$(1) \
					-DCMAKE_C_FLAGS="-target arm64-apple-ios14.1-macabi" -DCMAKE_OSX_ARCHITECTURES=arm64 \
					-DBUILD_CLAR=NO -DBUILD_TESTS=OFF -DUSE_SSH=ON -DGIT_SSH_MEMORY_CREDENTIALS=1 \
					-DCMAKE_PREFIX_PATH="$$(REPO_ROOT)/install-libssh2/$(1);$$(REPO_ROOT)/install-openssl/$(1)" .. 2>&1 | tee -a $$(BUILD_LOG); \
				;; \
			macosx) \
				cmake -DBUILD_SHARED_LIBS=NO -DCMAKE_BUILD_TYPE=Release \
					-DCMAKE_C_COMPILER_WORKS=ON -DCMAKE_CXX_COMPILER_WORKS=ON \
					-DCMAKE_OSX_DEPLOYMENT_TARGET=12.4 \
					-DCMAKE_INSTALL_PREFIX=$$(REPO_ROOT)/install/$(1) \
					-DCMAKE_OSX_ARCHITECTURES=x86_64 \
					-DBUILD_CLAR=NO -DBUILD_TESTS=OFF -DUSE_SSH=ON -DGIT_SSH_MEMORY_CREDENTIALS=1 \
					-DCMAKE_PREFIX_PATH="$$(REPO_ROOT)/install-libssh2/$(1);$$(REPO_ROOT)/install-openssl/$(1)" .. 2>&1 | tee -a $$(BUILD_LOG); \
				;; \
			macosx-arm64) \
				cmake -DBUILD_SHARED_LIBS=NO -DCMAKE_BUILD_TYPE=Release \
					-DCMAKE_C_COMPILER_WORKS=ON -DCMAKE_CXX_COMPILER_WORKS=ON \
					-DCMAKE_OSX_DEPLOYMENT_TARGET=12.4 \
					-DCMAKE_INSTALL_PREFIX=$$(REPO_ROOT)/install/$(1) \
					-DCMAKE_OSX_ARCHITECTURES=arm64 \
					-DBUILD_CLAR=NO -DBUILD_TESTS=OFF -DUSE_SSH=ON -DGIT_SSH_MEMORY_CREDENTIALS=1 \
					-DCMAKE_PREFIX_PATH="$$(REPO_ROOT)/install-libssh2/$(1);$$(REPO_ROOT)/install-openssl/$(1)" .. 2>&1 | tee -a $$(BUILD_LOG); \
				;; \
		esac; \
		cmake --build . --target libgit2package 2>&1 | tee -a $$(BUILD_LOG); \
		if ! cmake --install . --component libgit2 2>&1 | tee -a $$(BUILD_LOG); then \
			if ! cmake --install . 2>&1 | tee -a $$(BUILD_LOG); then \
				echo "CMake install failed, using fallback: manually installing libgit2..." 2>&1 | tee -a $$(BUILD_LOG); \
				mkdir -p $$(REPO_ROOT)/install/$(1)/lib $$(REPO_ROOT)/install/$(1)/include 2>&1 | tee -a $$(BUILD_LOG); \
				cp libgit2.a $$(REPO_ROOT)/install/$(1)/lib/ 2>&1 | tee -a $$(BUILD_LOG); \
				cp -r ../include/* $$(REPO_ROOT)/install/$(1)/include/ 2>&1 | tee -a $$(BUILD_LOG) || true; \
			fi; \
		fi; \
		cd $$(REPO_ROOT); \
		if [ ! -f install/$(1)/lib/libgit2.a ]; then \
			echo "Note: libgit2.a not in install directory, copying from build directory..." 2>&1 | tee -a $$(BUILD_LOG); \
			mkdir -p install/$(1)/lib; \
			cp $$(DEPENDENCIES_ROOT)/libgit2-1.8.4-$(1)/build/libgit2.a install/$(1)/lib/ 2>&1 | tee -a $$(BUILD_LOG); \
		fi; \
		libtool -v -static -o libgit2_all.a install-openssl/$(1)/lib/*.a install/$(1)/lib/*.a install-libssh2/$(1)/lib/*.a 2>&1 | tee -a $$(BUILD_LOG); \
		cp libgit2_all.a install/$(1)/lib/ 2>&1 | tee -a $$(BUILD_LOG); \
		rm libgit2_all.a \
	'
endef

$(foreach p,$(AVAILABLE_PLATFORMS),$(eval $(call libgit2_platform_template,$(p))))

# Collect all libgit2 libraries
ALL_LIBGIT2_LIBS := $(foreach p,$(AVAILABLE_PLATFORMS),$(LIBGIT2_$(p)_LIB))

# Create fat binaries for macOS and Mac Catalyst
install/macosx-fat/lib/libgit2_all.a: $(LIBGIT2_macosx_LIB) $(LIBGIT2_macosx-arm64_LIB) | $(BUILD_LOG)
	@$(call LOG,"Creating fat binary for macosx...")
	@mkdir -p install/macosx-fat/lib 2>&1 | tee -a $(BUILD_LOG)
	@lipo install/macosx/lib/libgit2_all.a install/macosx-arm64/lib/libgit2_all.a -create -output install/macosx-fat/lib/libgit2_all.a 2>&1 | tee -a $(BUILD_LOG)

install/maccatalyst-fat/lib/libgit2_all.a: $(LIBGIT2_maccatalyst_LIB) $(LIBGIT2_maccatalyst-arm64_LIB) | $(BUILD_LOG)
	@$(call LOG,"Creating fat binary for maccatalyst...")
	@mkdir -p install/maccatalyst-fat/lib 2>&1 | tee -a $(BUILD_LOG)
	@lipo install/maccatalyst/lib/libgit2_all.a install/maccatalyst-arm64/lib/libgit2_all.a -create -output install/maccatalyst-fat/lib/libgit2_all.a 2>&1 | tee -a $(BUILD_LOG)

# Create xcframework
Clibgit2.xcframework: $(ALL_LIBGIT2_LIBS) install/macosx-fat/lib/libgit2_all.a install/maccatalyst-fat/lib/libgit2_all.a | $(BUILD_LOG)
	@$(call LOG,"Creating XCFramework...")
	@cd $(REPO_ROOT) && \
	xcodebuild -create-xcframework \
		-library install/macosx-fat/lib/libgit2_all.a -headers install/macosx/include \
		-library install/maccatalyst-fat/lib/libgit2_all.a -headers install/maccatalyst/include \
		-library install/iphoneos/lib/libgit2_all.a -headers install/iphoneos/include \
		-library install/iphonesimulator/lib/libgit2_all.a -headers install/iphonesimulator/include \
		-output Clibgit2.xcframework 2>&1 | tee -a $(BUILD_LOG)
	@$(MAKE) copy_modulemap

# Copy modulemap to all framework directories
copy_modulemap:
	@$(call LOG,"Copying module.modulemap...")
	@find Clibgit2.xcframework -mindepth 1 -maxdepth 1 -type d | while read d; do \
		cp Clibgit2_modulemap $$d/Headers/module.modulemap 2>&1 | tee -a $(BUILD_LOG); \
	done

# Help target
help:
	@echo "Available targets:"
	@echo "  all              - Build everything (default)"
	@echo "  clean            - Remove all build artifacts"
	@echo "  clean-deps       - Remove only dependencies directory"
	@echo "  help             - Show this help message"
	@echo ""
	@echo "Build log: $(BUILD_LOG)"
	@echo ""
	@echo "Parallel Build Support:"
	@echo "  - Use 'make -j$(NUM_CORES)' to build all platforms in parallel"
	@echo "  - Each platform builds independently (different build directories)"
	@echo "  - Example: make -j8 (builds up to 8 platforms simultaneously)"
	@echo ""
	@echo "The Makefile uses dependency tracking to avoid rebuilding:"
	@echo "  - Each platform's libraries are built only if dependencies changed"
	@echo "  - All output is logged to $(BUILD_LOG) using tee (thread-safe)"
	@echo "  - Build artifacts are protected from accidental deletion"
	@echo ""
	@echo "Build order per platform:"
	@echo "  1. OpenSSL (required by libssh2 and libgit2)"
	@echo "  2. libssh2 (requires OpenSSL)"
	@echo "  3. libgit2 (requires OpenSSL and libssh2)"
	@echo "  4. Merge all libraries into libgit2_all.a"
