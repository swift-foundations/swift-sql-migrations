// swift-tools-version: 6.3.3

import PackageDescription

let package = Package(
    name: "swift-migrations",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "Migrations", targets: ["Migrations"])
    ],
    dependencies: [
        // URL-form: swift-sql formerly had to be consumed via a local/path dependency because it
        // in turn depended on swift-postgresql-standard by path (that package's macro target used
        // a relative symlink that only resolved in the sibling workspace layout, so it couldn't be
        // a cloned source-control checkout — and SwiftPM rejects a revision-based dependency that
        // itself depends on a local package). swift-postgresql-standard now vendors those sources
        // as real files, so swift-sql resolves as a plain revision-based dependency, and this
        // package can do the same.
        .package(url: "https://github.com/swift-foundations/swift-sql.git", branch: "main")
    ],
    targets: [
        // MARK: - Migrations (ordered migration set + runner over SQL.Database)

        .target(
            name: "Migrations",
            dependencies: [
                .product(name: "SQL", package: "swift-sql")
            ],
            path: "Sources/Migrations"
        ),

        // MARK: - Tests

        .testTarget(
            name: "Migrations Tests",
            dependencies: [
                "Migrations",
                .product(name: "SQL", package: "swift-sql"),
                .product(name: "SQL Test Support", package: "swift-sql"),
            ],
            path: "Tests/Migrations Tests"
        ),
    ],
    swiftLanguageModes: [.v6]
)

// Membrane build settings, mirroring the swift-server / swift-sql trio.
for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let membrane: [SwiftSetting] = [
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("ExistentialAny"),
    ]
    target.swiftSettings = (target.swiftSettings ?? []) + membrane
}
