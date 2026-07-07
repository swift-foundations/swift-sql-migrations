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
    /// An ordered set of named migrations plus a runner: register migrations in order, then
    /// ``migrate(_:)`` applies the pending ones and records each in an applied-migrations table.
    public struct Migrator: Sendable {
        /// The registered migrations, in registration (application) order.
        public private(set) var migrations: [SQL.Migration]

        public init() {
            self.migrations = []
        }
    }
}

extension SQL.Migrator {
    /// The name of the table used to record applied migrations.
    public static var appliedTableName: String { "_sql_migrations" }

    /// The registered migration names, in application order. Pure — testable without a database.
    public var names: [String] { migrations.map(\.name) }

    /// Registers a migration. Registration order is application order.
    public mutating func register(
        _ name: String,
        up: @escaping @Sendable (any SQL.Connection) async throws(SQL.Error) -> Void
    ) {
        migrations.append(SQL.Migration(name: name, up: up))
    }

    /// Appends an already-built migration.
    public mutating func register(_ migration: SQL.Migration) {
        migrations.append(migration)
    }

    /// Computes which registered migrations are not yet in `applied`, preserving application order.
    ///
    /// Pure — testable without a database.
    public func pending(applied: Set<String>) -> [SQL.Migration] {
        migrations.filter { !applied.contains($0.name) }
    }

    /// Applies every pending migration in order.
    ///
    /// The applied-migrations table is created if absent, then the set of already-applied names is
    /// read, then each pending migration runs inside ONE ``SQL/Database/write(_:)`` scope together
    /// with the insert of its bookkeeping row — so a failed migration leaves no partial record (the
    /// write scope rolls back the migration's statements and its bookkeeping insert atomically).
    public func migrate(_ database: any SQL.Database) async throws(SQL.Error) {
        let created = SQL.Query(
            sql: """
                CREATE TABLE IF NOT EXISTS \(Self.appliedTableName) (
                    name TEXT PRIMARY KEY,
                    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
                )
                """
        )
        _ = try await database.execute(created)

        let appliedNames = try await database.read {
            (connection: any SQL.Connection) throws(SQL.Error) -> [String] in
            try await connection.fetchAll(
                SQL.Query(sql: "SELECT name FROM \(Self.appliedTableName)")
            ) { row throws(SQL.Error) in
                try row.string("name")
            }
        }

        let applied = Set(appliedNames)

        for migration in pending(applied: applied) {
            try await database.write { (connection: any SQL.Connection) throws(SQL.Error) in
                try await migration.up(connection)
                _ = try await connection.execute(
                    SQL.Query(
                        sql: "INSERT INTO \(Self.appliedTableName) (name) VALUES ($1)",
                        bindings: [.text(migration.name)]
                    )
                )
            }
        }
    }
}
// swiftlint:enable no_any_protocol_existential
