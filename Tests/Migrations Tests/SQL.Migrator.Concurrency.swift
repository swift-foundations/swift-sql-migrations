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

import Migrations
import SQL
import SQL_Test_Support
import Testing

// F-001 regression coverage: `migrate(_:)` has no cross-process serialization, so two runners
// can both read an empty/stale applied set and both attempt the same migration. The losing
// runner's bookkeeping INSERT then violates the applied-table's `name` PRIMARY KEY. Fixed
// `migrate(_:)` catches that failure at the insert call site and rethrows it as a named
// `SQL.Error.migration(_:)` instead of letting the engine's raw, opaque constraint-violation
// text escape.
extension SQL.Migrator {
    @Suite struct Concurrency {
        @Suite struct `Edge Case` {}
    }
}

extension SQL.Migrator.Concurrency {
    /// A minimal ``SQL/Database`` double that models the PRIMARY KEY-constrained bookkeeping
    /// table and lets a test pin the exact interleaving of a concurrent-runner race: what a
    /// stale `read` (`SELECT`) reports vs. what is already committed to the table by the time
    /// the bookkeeping `INSERT` runs.
    actor RacingDatabase: SQL.Database {
        /// What the next `read` (the applied-names `SELECT`) reports — pinned to simulate a read
        /// that completed before a concurrent migrator's commit landed.
        private let readSees: Set<String>
        /// The bookkeeping table's actual PRIMARY KEY-constrained contents.
        private var committed: Set<String>

        init(readSees: Set<String>, committed: Set<String>) {
            self.readSees = readSees
            self.committed = committed
        }

        func read<Value: Sendable>(
            _ body: @Sendable (any SQL.Connection) async throws(SQL.Error) -> Value
        ) async throws(SQL.Error) -> Value {
            try await body(RacingConnection(database: self))
        }

        func write<Value: Sendable>(
            _ body: @Sendable (any SQL.Connection) async throws(SQL.Error) -> Value
        ) async throws(SQL.Error) -> Value {
            try await body(RacingConnection(database: self))
        }

        func withRollback<Value: Sendable>(
            _ body: @Sendable (any SQL.Connection) async throws(SQL.Error) -> Value
        ) async throws(SQL.Error) -> Value {
            try await body(RacingConnection(database: self))
        }

        func namesVisibleToReader() -> [String] { Array(readSees) }

        /// Enforces the PRIMARY KEY exactly like a live engine's bookkeeping-table insert would.
        func insertBookkeeping(_ name: String) throws(SQL.Error) {
            guard committed.insert(name).inserted else {
                throw SQL.Error.execution(
                    "duplicate key value violates unique constraint \"_sql_migrations_pkey\""
                )
            }
        }
    }

    struct RacingConnection: SQL.Connection {
        let database: RacingDatabase

        func execute(_ statement: some SQL.Statement) async throws(SQL.Error) -> Int {
            guard statement.sql.contains("INSERT INTO"), let first = statement.bindings.first,
                case .text(let name) = first
            else { return 0 }
            try await database.insertBookkeeping(name)
            return 1
        }

        func fetchAll<Value: Sendable>(
            _ statement: some SQL.Statement,
            decode: (any SQL.Row) throws(SQL.Error) -> Value
        ) async throws(SQL.Error) -> [Value] {
            var results: [Value] = []
            for name in await database.namesVisibleToReader() {
                results.append(try decode(SQL.TestRow(["name": .text(name)])))
            }
            return results
        }

        func fetchOne<Value: Sendable>(
            _ statement: some SQL.Statement,
            decode: (any SQL.Row) throws(SQL.Error) -> Value
        ) async throws(SQL.Error) -> Value? {
            nil
        }
    }
}

extension SQL.Migrator.Concurrency.`Edge Case` {
    @Test
    func `bookkeeping insert race surfaces as a named migration error, not a raw engine error`() async throws {
        // This runner's read of `applied` returned empty (stale relative to a concurrent
        // migrator that has already committed "v1"'s bookkeeping row by the time this runner's
        // INSERT runs) — the classic interleaving behind F-001's raw PRIMARY KEY violations.
        let database = SQL.Migrator.Concurrency.RacingDatabase(readSees: [], committed: ["v1"])
        var migrator = SQL.Migrator()
        migrator.register("v1") { _ in }

        do {
            try await migrator.migrate(database)
            Issue.record("expected migrate() to throw on the bookkeeping-insert race")
        } catch SQL.Error.migration(let detail) {
            #expect(detail.contains("v1"))
        } catch {
            Issue.record("expected SQL.Error.migration naming the race, got \(error)")
        }
    }

    @Test
    func `non racing migration still applies cleanly against the same double`() async throws {
        // Positive control: no concurrent commit in play (`readSees` and `committed` agree), so
        // the insert is uncontended and migrate() succeeds normally.
        let database = SQL.Migrator.Concurrency.RacingDatabase(readSees: [], committed: [])
        var migrator = SQL.Migrator()
        migrator.register("v1") { _ in }

        try await migrator.migrate(database)
    }
}
