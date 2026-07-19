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
    ///
    /// ### Concurrent runners
    ///
    /// `migrate(_:)` does not acquire a cross-process lock, so two runners started against the
    /// same database can both read an empty/stale applied set and both attempt the same
    /// migration. Concurrent invocation is therefore safe only when every registered migration's
    /// `up` body is idempotent (e.g. `CREATE TABLE IF NOT EXISTS`-style DDL) — non-idempotent
    /// migrations still require a single-runner deployment contract or external serialization.
    ///
    /// When two runners do race, the *loser*'s bookkeeping `INSERT` violates the applied-table's
    /// `name` `PRIMARY KEY` — that failure is caught at the insert call site and rethrown as a
    /// named ``SQL/Error/migration(_:)`` identifying the migration, instead of letting the
    /// engine's raw, opaque constraint-violation text escape. The enclosing `write` scope still
    /// rolls back on that throw, so the losing runner's `up()` effects are discarded atomically
    /// along with the failed insert.
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
                do {
                    _ = try await connection.execute(
                        SQL.Query(
                            sql: "INSERT INTO \(Self.appliedTableName) (name) VALUES ($1)",
                            bindings: [.text(migration.name)]
                        )
                    )
                } catch {
                    // Between the `applied` read above and this insert, a concurrent migrator may
                    // have already committed this exact migration's bookkeeping row — the insert
                    // then fails with a raw, engine-specific error (typically a PRIMARY KEY
                    // violation on `name`). Name that race explicitly via the typed error domain
                    // rather than letting the opaque engine error propagate; the enclosing `write`
                    // scope still rolls back on this throw, discarding this runner's `up()`
                    // effects atomically (see the concurrency contract on ``migrate(_:)``).
                    throw SQL.Error.migration(
                        "\(migration.name): bookkeeping insert failed — a concurrent migrator may "
                            + "have already applied this migration (\(error))"
                    )
                }
            }
        }
    }
}
// swiftlint:enable no_any_protocol_existential
