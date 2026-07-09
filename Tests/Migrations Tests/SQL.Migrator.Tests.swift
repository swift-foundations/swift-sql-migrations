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

// MARK: - Pure (no database)

@Test func `migrator preserves registration order`() {
    var migrator = SQL.Migrator()
    migrator.register("v1_accounts") { _ in }
    migrator.register("v2_repositories") { _ in }
    migrator.register("v3_traffic") { _ in }
    #expect(migrator.names == ["v1_accounts", "v2_repositories", "v3_traffic"])
}

@Test func `migrator pending excludes applied preserving order`() {
    var migrator = SQL.Migrator()
    migrator.register("a") { _ in }
    migrator.register("b") { _ in }
    migrator.register("c") { _ in }
    migrator.register("d") { _ in }
    let pending = migrator.pending(applied: ["a", "c"])
    #expect(pending.map(\.name) == ["b", "d"])
}

@Test func `migrator pending empty when all applied`() {
    var migrator = SQL.Migrator()
    migrator.register("a") { _ in }
    migrator.register("b") { _ in }
    #expect(migrator.pending(applied: ["a", "b"]).isEmpty)
}

@Test func `migrator applied table name is stable`() {
    #expect(SQL.Migrator.appliedTableName == "_sql_migrations")
}

@Test func `register built migration appends`() {
    var migrator = SQL.Migrator()
    migrator.register(SQL.Migration(name: "x") { _ in })
    #expect(migrator.names == ["x"])
}

// MARK: - Scripted (over SQL.TestDatabase)

@Test func `migrate creates table first then inserts bookkeeping rows`() async throws {
    let database = SQL.TestDatabase()
    var migrator = SQL.Migrator()
    migrator.register("v1") { _ in }
    migrator.register("v2") { _ in }

    try await migrator.migrate(database)

    let executed = await database.executed
    #expect(executed.first?.sql.contains("CREATE TABLE IF NOT EXISTS _sql_migrations") == true)
    #expect(executed.contains { $0.sql.contains("SELECT name FROM _sql_migrations") })

    let inserts = executed.filter { $0.sql.contains("INSERT INTO _sql_migrations") }
    #expect(inserts.count == 2)
    #expect(inserts[0].bindings == [.text("v1")])
    #expect(inserts[1].bindings == [.text("v2")])
}

@Test func `migrate skips already applied migrations`() async throws {
    let database = SQL.TestDatabase()
    // The applied-names SELECT consumes this scripted result set.
    await database.script(rows: [["name": .text("v1")]])

    var migrator = SQL.Migrator()
    migrator.register("v1") { _ in }
    migrator.register("v2") { _ in }

    try await migrator.migrate(database)

    let executed = await database.executed
    let inserts = executed.filter { $0.sql.contains("INSERT INTO _sql_migrations") }
    #expect(inserts.count == 1)
    #expect(inserts[0].bindings == [.text("v2")])
}

@Test func `migrate failing up propagates without recording`() async throws {
    let database = SQL.TestDatabase()
    var migrator = SQL.Migrator()
    migrator.register("v1") { _ throws(SQL.Error) in throw SQL.Error.migration("boom") }
    migrator.register("v2") { _ in }

    await #expect(throws: SQL.Error.self) {
        try await migrator.migrate(database)
    }

    let executed = await database.executed
    // The CREATE TABLE and the applied-names SELECT ran; no bookkeeping INSERT was recorded
    // because v1's `up` threw before the insert, and v2 is never reached.
    #expect(executed.first?.sql.contains("CREATE TABLE") == true)
    #expect(!executed.contains { $0.sql.contains("INSERT INTO _sql_migrations") })
}
