// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-migrations open source project
//
// Copyright (c) 2026 Coen ten Thije Boonkkamp and the swift-migrations project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

public import SQL

// `any SQL.Connection` / `any SQL.Database` existentials are the deliberate
// engine-free membrane design of swift-sql: conformers are engine-specific and
// heterogeneous; generics would leak the engine type into consumer signatures.
// swiftlint:disable no_any_protocol_existential
extension SQL {
    /// A single named migration: an identifier plus the work that applies it.
    ///
    /// The `up` closure receives a transaction-scoped ``SQL/Connection`` — every statement it runs
    /// commits atomically with the migration's bookkeeping row (see ``SQL/Migrator/migrate(_:)``),
    /// mirroring the `register("name") { db in … }` shape.
    public struct Migration: Sendable {
        public let name: String
        public let up: @Sendable (any SQL.Connection) async throws(SQL.Error) -> Void

        public init(
            name: String,
            up: @escaping @Sendable (any SQL.Connection) async throws(SQL.Error) -> Void
        ) {
            self.name = name
            self.up = up
        }
    }
}
// swiftlint:enable no_any_protocol_existential
