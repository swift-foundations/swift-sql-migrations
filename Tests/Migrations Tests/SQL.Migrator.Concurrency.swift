import Migrations
import SQL
import SQL_Test_Support
import Testing

extension SQL.Migrator {
    @Suite struct Concurrency {
        @Suite struct `Edge Case` {}
    }
}

extension SQL.Migrator.Concurrency {

    enum Racing {}
}

extension SQL.Migrator.Concurrency.Racing {

    actor Database: SQL.Database {

        private let readSees: Set<String>

        private var committed: Set<String>

        init(readSees: Set<String>, committed: Set<String>) {
            self.readSees = readSees
            self.committed = committed
        }
    }

    struct Connection: SQL.Connection {
        let database: Database
    }
}

extension SQL.Migrator.Concurrency.Racing.Database {

    func read<Value: Sendable>(
        _ body: @Sendable (any SQL.Connection) async throws(SQL.Error) -> Value
    ) async throws(SQL.Error) -> Value {
        try await body(SQL.Migrator.Concurrency.Racing.Connection(database: self))
    }

    func write<Value: Sendable>(
        _ body: @Sendable (any SQL.Connection) async throws(SQL.Error) -> Value
    ) async throws(SQL.Error) -> Value {
        try await body(SQL.Migrator.Concurrency.Racing.Connection(database: self))
    }

    func withRollback<Value: Sendable>(
        _ body: @Sendable (any SQL.Connection) async throws(SQL.Error) -> Value
    ) async throws(SQL.Error) -> Value {
        try await body(SQL.Migrator.Concurrency.Racing.Connection(database: self))
    }

    fileprivate func namesVisibleToReader() -> [String] { Array(readSees) }

    fileprivate func insertBookkeeping(_ name: String) throws(SQL.Error) {
        guard committed.insert(name).inserted else {
            throw SQL.Error.execution(
                "duplicate key value violates unique constraint \"_sql_migrations_pkey\""
            )
        }
    }
}

extension SQL.Migrator.Concurrency.Racing.Connection {
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

extension SQL.Migrator.Concurrency.`Edge Case` {
    @Test
    func `bookkeeping insert race surfaces as a named migration error, not a raw engine error`()
        async throws
    {

        let database = SQL.Migrator.Concurrency.Racing.Database(readSees: [], committed: ["v1"])
        var migrator = SQL.Migrator()
        migrator.register("v1") { _ in }

        do throws(SQL.Error) {
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

        let database = SQL.Migrator.Concurrency.Racing.Database(readSees: [], committed: [])
        var migrator = SQL.Migrator()
        migrator.register("v1") { _ in }

        try await migrator.migrate(database)
    }
}
