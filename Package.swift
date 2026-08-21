// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "swift-sql-migrations",
    platforms: [
        .macOS(.v27)
    ],
    products: [
        .library(name: "Migrations", targets: ["Migrations"])
    ],
    dependencies: [

        .package(url: "https://github.com/swift-foundations/swift-sql.git", branch: "main")
    ],
    targets: [

        .target(
            name: "Migrations",
            dependencies: [
                .product(name: "SQL", package: "swift-sql")
            ],
            path: "Sources/Migrations"
        ),

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

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let membrane: [SwiftSetting] = [
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("ExistentialAny"),
    ]
    target.swiftSettings = (target.swiftSettings ?? []) + membrane
}
