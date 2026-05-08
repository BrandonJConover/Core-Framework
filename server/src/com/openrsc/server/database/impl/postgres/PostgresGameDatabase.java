package com.openrsc.server.database.impl.postgres;

import com.openrsc.server.Server;
import com.openrsc.server.database.JDBCDatabaseConnection;
import com.openrsc.server.database.impl.mysql.MySqlGameDatabase;

public class PostgresGameDatabase extends MySqlGameDatabase {
	private final PostgresDatabaseConnection connection;

	public PostgresGameDatabase(final Server server) {
		super(server);
		connection = new PostgresDatabaseConnection(server);
	}

	@Override
	public JDBCDatabaseConnection getConnection() {
		return connection;
	}
}
