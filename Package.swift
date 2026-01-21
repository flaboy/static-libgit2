// swift-tools-version: 5.6

import PackageDescription

let package = Package(
  name: "static-libgit2",
  platforms: [.iOS(.v13)],
  products: [
    // Products define the executables and libraries a package produces, and make them visible to other packages.
    .library(
      name: "static-libgit2",
      targets: [
        "Clibgit2",
        "LinkerConfigurator"
      ]
    ),
  ],
  dependencies: [
    // Dependencies declare other packages that this package depends on.
    // .package(url: /* package url */, from: "1.0.0"),
  ],
  targets: [
    // Use remote binary from GitHub Release (recommended for users)
    .binaryTarget(
      name: "Clibgit2",
      url: "https://github.com/flaboy/xc-libgit2/releases/download/1.8.4/Clibgit2.xcframework.zip",
      checksum: "f62a6760f8c2ff1a82e4fb80c69fe2aa068458c7619f5b98c53c71579f72f9c7"
    ),
    // Alternative: Use local path (for development)
    // .binaryTarget(name: "Clibgit2", path: "Clibgit2.xcframework"),
    .target(name: "LinkerConfigurator", linkerSettings: [
      .linkedLibrary("z"),
      .linkedLibrary("iconv")
    ])
  ]
)
