package com.openrsc.server.plugins;

public class ScriptEndedException extends RuntimeException {
	private static final long serialVersionUID = 1L;
	public ScriptEndedException(final String message) {
		super(message);
	}

	public ScriptEndedException(final String message, final Throwable cause) {
		super(message, cause);
	}

	public ScriptEndedException(final Throwable cause) {
		super(cause);
	}
}
