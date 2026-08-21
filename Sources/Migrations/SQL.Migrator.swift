public import SQL

extension SQL {

    public struct Migrator: Sendable {

        public private(set) var migrations: [SQL.Migration]

        public init() {
            self.migrations = []
        }
    }
}

extension SQL.Migrator {

    public static var appliedTableName: String { "_sql_migrations" }

    public var names: [String] { migrations.map(\.name) }

    public mutating func register(
        _ name: String,
        up: @escaping @Sendable (any SQL.Connection) async throws(SQL.Error) -> Void
    ) {
        migrations.append(SQL.Migration(name: name, up: up))
    }

    public mutating func register(_ migration: SQL.Migration) {
        migrations.append(migration)
    }

    public func pending(applied: Set<String>) -> [SQL.Migration] {
        migrations.filter { !applied.contains($0.name) }
    }

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
                do throws(SQL.Error) {
                    _ = try await connection.execute(
                        SQL.Query(
                            sql: "INSERT INTO \(Self.appliedTableName) (name) VALUES ($1)",
                            bindings: [.text(migration.name)]
                        )
                    )
                } catch {

                    throw SQL.Error.migration(
                        "\(migration.name): bookkeeping insert failed — a concurrent migrator may "
                            + "have already applied this migration (\(error))"
                    )
                }
            }
        }
    }
}
