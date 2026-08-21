public import SQL

extension SQL {

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
