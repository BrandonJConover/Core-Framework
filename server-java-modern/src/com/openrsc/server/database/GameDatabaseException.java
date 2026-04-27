package com.openrsc.server.database;

public class GameDatabaseException extends RuntimeException {
	private static final long serialVersionUID = 1L;
	public GameDatabaseException(Class<?> type, final String reason) {
		super(type.getSimpleName() + ": " + reason);
	}
}
