package com.openrsc.server.database.impl.postgres;

import com.openrsc.server.Server;
import com.openrsc.server.database.DatabaseType;
import com.openrsc.server.database.JDBCDatabaseConnection;
import com.openrsc.server.util.SystemUtil;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.sql.Statement;

public class PostgresDatabaseConnection extends JDBCDatabaseConnection {
	private static final Logger LOGGER = LogManager.getLogger();

	private final Server server;
	private Connection connection;
	private Statement statement;
	private boolean connected;

	public PostgresDatabaseConnection(final Server server) {
		this.server = server;
		connected = false;
	}

	public synchronized boolean open() {
		close();

		try {
			Class.forName("org.postgresql.Driver");
		} catch (final ClassNotFoundException e) {
			LOGGER.catching(e);
			System.exit(1);
		}

		try {
			connection = DriverManager.getConnection(
				"jdbc:postgresql://" + getServer().getConfig().DB_HOST + "/" + getServer().getConfig().DB_NAME,
				getServer().getConfig().DB_USER,
				getServer().getConfig().DB_PASS
			);
			statement = getConnection().createStatement();
			statement.setEscapeProcessing(true);
			connected = checkConnection();
		} catch (final SQLException e) {
			LOGGER.catching(e);
			connected = false;
		}

		if (isConnected()) {
			LOGGER.info(getServer().getName() + " - Connected to PostgreSQL!");
		} else {
			LOGGER.error("Unable to connect to PostgreSQL");
			SystemUtil.exit(1);
		}

		return isConnected();
	}

	@Override
	public synchronized void close() {
		try {
			if (statement != null) {
				statement.close();
			}
		} catch (final SQLException e) {
			LOGGER.catching(e);
		}
		try {
			if (getConnection() != null) {
				getConnection().close();
			}
		} catch (final SQLException e) {
			LOGGER.catching(e);
		}
		connected = false;
		statement = null;
		connection = null;
	}

	@Override
	public DatabaseType getDatabaseType() {
		return DatabaseType.POSTGRES;
	}

	@Override
	protected boolean checkConnection() {
		try {
			getStatement().executeQuery("SELECT CURRENT_DATE");
			return true;
		} catch (final SQLException e) {
			return false;
		}
	}

	public final Server getServer() {
		return server;
	}

	@Override
	protected Statement getStatement() {
		return statement;
	}

	@Override
	public synchronized Connection getConnection() {
		return connection;
	}

	@Override
	public boolean isConnected() {
		return connected;
	}
}
