package com.openrsc.server.plugins;

public class SpellFailureException extends RuntimeException {

	private static final long serialVersionUID = 1L;

	public SpellFailureException(String reason) {
		super(reason);
	}

}
