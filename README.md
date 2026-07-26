# swift-sql-migrations

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)

An ordered set of named schema migrations and a runner that applies each pending one — together with its bookkeeping row — in a single atomic write against any `SQL.Database`.

---

## Installation

```swift
dependencies: [
    .package(
        url: "https://github.com/swift-foundations/swift-sql-migrations.git",
        branch: "main"
    )
]
```

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "Migrations", package: "swift-sql-migrations")
    ]
)
```

The package publishes no tags yet, so the dependency is pinned to `main`.

---

## Community

<!-- BEGIN: discussion -->
*Discussion thread will be created at first public release.*
<!-- END: discussion -->

---

## License

Apache 2.0. See [LICENSE](LICENSE.md).
