// swift-tools-version: 6.3.1

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
        // Path-form (not URL-form) is forced by SwiftPM: swift-sql itself depends on
        // swift-postgresql-standard via a PATH dependency (that package's macro target uses a
        // relative symlink that only resolves in the sibling workspace layout, so it cannot be a
        // cloned source-control checkout). SwiftPM rejects a revision-based dependency that in turn
        // has a local/path dependency ("… is required using a revision-based requirement and it
        // depends on local package 'swift-postgresql-standard', which is not supported"), so
        // swift-sql must be consumed in-place too. See the report on this upstream constraint.
        .package(path: "/Users/coen/Developer/swift-foundations/swift-sql")
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
