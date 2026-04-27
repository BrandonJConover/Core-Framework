package com.openrsc.server.database.patches;

public class PatchApplicationException extends RuntimeException {

    private static final long serialVersionUID = 1L;

    public PatchApplicationException(String message) {
        super(message);
    }

    public PatchApplicationException(String message, Throwable cause) {
        super(message, cause);
    }

    public PatchApplicationException(Throwable cause) {
        super(cause);
    }

    protected PatchApplicationException(String message, Throwable cause, boolean enableSuppression, boolean writableStackTrace) {
        super(message, cause, enableSuppression, writableStackTrace);
    }
}
