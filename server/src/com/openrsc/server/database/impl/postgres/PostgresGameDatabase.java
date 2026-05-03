package com.openrsc.server.database.impl.postgres;

import com.openrsc.server.Server;
import com.openrsc.server.database.DatabaseType;
import com.openrsc.server.database.impl.mysql.MySqlGameDatabase;

public class PostgresGameDatabase extends MySqlGameDatabase {
        public PostgresGameDatabase(Server server) {
                super(server);
        }
        public DatabaseType getDatabaseType() {
                return DatabaseType.POSTGRES;
        }
}