package com.openrsc.server.plugins;

public class PluginInterruptedException extends RuntimeException {
	private static final long serialVersionUID = 1L;
	public PluginInterruptedException(final String message) {
		super(message);
	}

	public PluginInterruptedException(final String message, final Throwable cause) {
		super(message, cause);
	}

	public PluginInterruptedException(final Throwable cause) {
		super(cause);
	}
}
