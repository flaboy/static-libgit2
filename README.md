# static-libgit2

This repository makes it easier to include the C library [Libgit2](https://libgit2.org) into an iOS or Mac application. It does *not* try to provide any sort of nice, Swifty wrapper over the `libgit2` APIs.

## Original Project

This repository is a fork and enhancement of:
- **Original repository**: https://github.com/bdewey/static-libgit2
- **Build script source**: https://github.com/light-tech/LibGit2-On-iOS

The original `LibGit2-On-iOS` project doesn't expose the C Language bindings as its own Swift Package, choosing instead to use their framework as a binary target in their Swift Language binding project [MiniGit](https://github.com/light-tech/MiniGit). If you want Swift bindings, you should probably use that project! However, if you want to work directly with the C API, _this_ is the project for you want to start with.

## Enhancements in This Fork

This fork includes significant improvements to the build system:

### 1. Makefile-Based Build System
- **Dependency tracking**: Automatically avoids rebuilding unchanged components
- **Build protection**: Protects build artifacts from accidental deletion
- **Parallel build support**: Build multiple platforms simultaneously using `make -jN`
- **Comprehensive logging**: All build output is logged to `build.log` using `tee`
- **Platform isolation**: Each platform uses independent build directories to enable safe parallel builds

### 2. Build Improvements
- Independent build directories per platform (prevents conflicts during parallel builds)
- Automatic fallback mechanisms for installation failures
- Better error handling and logging
- Support for all Apple platforms: iOS, iOS Simulator, Mac Catalyst, and macOS

### 3. Release Management
- Pre-built XCFramework available via GitHub Releases
- Swift Package Manager integration with remote binary targets
- Checksum verification for security

## Usage in an Application

If you are writing an iOS or Mac app that needs access to `libgit2`, you can simply add this package to your project via Swift Package Manager. The `libgit2` C Language APIs are provided through the `Clibgit2` module, so you can access them with `import Clibgit2`. For example, the following SwiftUI view will show the `libgit2` version:

```swift
import Clibgit2
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text(LIBGIT2_VERSION)
            .padding()
    }
}
```

## Usage in another package

If you want to use `static-libgit2` in another package (say, to expose some cool Swift bindings to the C API), include the following in your `Package.swift`:

```swift
    dependencies: [
      .package(url: "https://github.com/flaboy/static-libgit2", from: "1.8.4-20260121"),
    ],
```

# What's Included

`static-libgit2` includes the following libraries:

| Library | Version |
| ------- | ------- |
| libgit2 | 1.8.4   |
| openssl | 3.6.0   |
| libssh2 | 1.11.1  |

The original build recipe comes from the insightful project https://github.com/light-tech/LibGit2-On-iOS. 

# Build it yourself

You don't need to depend on this package's pre-built libraries. You can build your own version of the framework.

## Using Makefile (Recommended)

The project includes a Makefile that provides:
- **Dependency tracking**: Avoids rebuilding unchanged components
- **Build protection**: Protects build artifacts from accidental deletion
- **Comprehensive logging**: All build output is logged to `build.log` using `tee`

```bash
# You need the tool `wget`
brew install wget

# Clone the repository
git clone https://github.com/flaboy/static-libgit2
cd static-libgit2

# Build using Makefile (recommended)
make

# Parallel build for faster compilation (recommended for multi-core CPUs)
# Each platform builds independently, so you can use -jN where N is your CPU cores
make -j8

# Or specify the number of parallel jobs
make -j$(sysctl -n hw.ncpu)

# Sequential build (verbose, slower)
make -j1

# Clean build artifacts
make clean

# View build log
tail -f build.log
```

## Using Shell Script (Legacy)

The original shell script is still available:

```bash
# You need the tool `wget`
brew install wget
git clone https://github.com/flaboy/static-libgit2
cd static-libgit2
./build-libgit2-framework.sh
```

## Pre-built Releases

Pre-built XCFrameworks are available via [GitHub Releases](https://github.com/flaboy/static-libgit2/releases). The Swift Package Manager automatically downloads the binary from releases, so you don't need to build it yourself unless you want to customize the build.
