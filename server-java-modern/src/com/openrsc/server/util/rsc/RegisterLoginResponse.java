package com.openrsc.server.util.rsc;

public class RegisterLoginResponse {
	// 177 to 204, possibly earlier than 177.
	public static final int SERVER_TIMEOUT = -1;
	public static final int LOGIN_SUCCESSFUL = 0;
	public static final int RECONNECT_SUCCESFUL = 1;
	public static final int REGISTER_SUCCESSFUL = 2;
	public static final int USERNAME_TAKEN_OR_INVALID = 3; // wrong password or username taken
	public static final int ACCOUNT_LOGGEDIN = 4;
	public static final int CLIENT_UPDATED = 5;
	public static final int IP_IN_USE = 6;
	public static final int LOGIN_ATTEMPTS_EXCEEDED = 7;
	public static final int ACCOUNT_TEMP_DISABLED = 11;
	public static final int ACCOUNT_PERM_DISABLED = 12;
	public static final int USERNAME_TAKEN_DISALLOWED = 13; // disallowed usernames like m0d
	public static final int WORLD_IS_FULL = 14;
	public static final int NEED_MEMBERS_ACCOUNT = 15;
	public static final int LOGIN_MEMBERS_SERVER = 16;
	public static final int UNSUCCESSFUL = 100;

	// 38 - 40, possibly later than 40.
	public static final int WORLD_IS_FULL_RETRO = 2;
	public static final int USERNAME_TAKEN_RETRO = 3; // same as modern
	public static final int INVALID_USERNAME_OR_PASSWORD_RETRO = 3;
	public static final int USERNAME_ALREADY_IN_USE_RETRO = 4; // what is this really
	public static final int CLIENT_UPDATED_RETRO = 5; // same as modern

	public static int translateNewToOld(int responseCode, int clientversion, boolean registering) {
		for (int i = 0; i < LoginResponse.LOGIN_SUCCESSFUL.length; i++) {
			if (responseCode == LoginResponse.LOGIN_SUCCESSFUL[i]) {
				return LOGIN_SUCCESSFUL;
			}
		}

		if (clientversion >= 93) {
			if (registering && responseCode == REGISTER_SUCCESSFUL) {
				return REGISTER_SUCCESSFUL;
			}
			return switch (responseCode) {
				case LoginResponse.SERVER_TIMEOUT -> SERVER_TIMEOUT;
				case LoginResponse.LOGIN_UNSUCCESSFUL -> UNSUCCESSFUL;
				case LoginResponse.RECONNECT_SUCCESFUL -> RECONNECT_SUCCESFUL;
				case LoginResponse.INVALID_CREDENTIALS -> USERNAME_TAKEN_OR_INVALID;
				case LoginResponse.ACCOUNT_LOGGEDIN -> ACCOUNT_LOGGEDIN;
				case LoginResponse.CLIENT_UPDATED -> CLIENT_UPDATED;
				case LoginResponse.IP_IN_USE -> IP_IN_USE;
				case LoginResponse.LOGIN_ATTEMPTS_EXCEEDED -> LOGIN_ATTEMPTS_EXCEEDED;
				case LoginResponse.ACCOUNT_TEMP_DISABLED -> ACCOUNT_TEMP_DISABLED;
				case LoginResponse.ACCOUNT_PERM_DISABLED -> ACCOUNT_PERM_DISABLED;
				case LoginResponse.WORLD_IS_FULL -> WORLD_IS_FULL;
				case LoginResponse.NEED_MEMBERS_ACCOUNT -> NEED_MEMBERS_ACCOUNT;
				default -> UNSUCCESSFUL;
			};
		} else {
			return switch (responseCode) {
				case LoginResponse.RECONNECT_SUCCESFUL, REGISTER_SUCCESSFUL -> LOGIN_SUCCESSFUL;
				case LoginResponse.CLIENT_UPDATED -> CLIENT_UPDATED_RETRO;
				case LoginResponse.INVALID_CREDENTIALS -> !registering ? INVALID_USERNAME_OR_PASSWORD_RETRO : USERNAME_TAKEN_RETRO;
				case LoginResponse.ACCOUNT_LOGGEDIN, LoginResponse.IP_IN_USE, LoginResponse.USERNAME_ALREADY_IN_USE -> USERNAME_ALREADY_IN_USE_RETRO;
				case LoginResponse.WORLD_IS_FULL -> WORLD_IS_FULL_RETRO;
				default -> UNSUCCESSFUL;
			};
		}
	}

}
