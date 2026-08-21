package com.openrsc.server.login;

import com.openrsc.server.Server;
import com.openrsc.server.database.impl.mysql.queries.logging.SecurityChangeLog;
import com.openrsc.server.database.struct.PlayerLoginData;
import com.openrsc.server.model.entity.player.Player;
import com.openrsc.server.net.rsc.ActionSender;
import com.openrsc.server.util.rsc.DataConversions;
import io.netty.channel.Channel;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

/**
 * Used to run change password functionality on the Login thread
 */
public class PasswordChangeRequest extends LoginExecutorProcess {

	/**
	 * The asynchronous logger.
	 */
	private static final Logger LOGGER = LogManager.getLogger("OpenRSC");

	private final Server server;
	private final Channel channel;
	private Player player;
	private String oldPassword;
	private String newPassword;

	public PasswordChangeRequest(final Server server, final Channel channel, final Player player, final String oldPassword, final String newPassword) {
		this.server = server;
		this.channel = channel;
		this.setPlayer(player);
		this.setOldPassword(oldPassword);
		this.setNewPassword(newPassword);
	}

	public Player getPlayer() {
		return player;
	}

	private void setPlayer(Player player) {
		this.player = player;
	}

	public String getOldPassword() {
		return oldPassword;
	}

	private void setOldPassword(final String oldPassword) {
		this.oldPassword = oldPassword;
	}

	public String getNewPassword() {
		return newPassword;
	}

	private void setNewPassword(final String newPassword) {
		this.newPassword = newPassword;
	}

	public Server getServer() {
		return server;
	}

	public Channel getChannel() {
		return channel;
	}

	protected void processInternal() {
		LOGGER.info("Password change attempt from: " + getPlayer().getCurrentIP());

		try {
			PlayerLoginData playerData = getPlayer().getWorld().getServer().getDatabase().getPlayerLoginData(player.getUsername());
			String lastDBPass = playerData.password;
			String DBsalt = playerData.salt;
			String newDBPass;
			int playerID = getPlayer().getID();
			// Always require the current password. The client version is
			// self-reported at login and is not clamped, so gating this check
			// on version (previously ">= 93") let an attacker on a hijacked
			// session declare an old version and change the password without
			// knowing the current one — turning a transient session compromise
			// into permanent account takeover.
			if (!DataConversions.checkPassword(getOldPassword(), DBsalt, lastDBPass)) {
				LOGGER.info(getPlayer().getCurrentIP() + " - Pass change failed: The current password did not match players record.");
				ActionSender.sendMessage(getPlayer(), "No changes made, your current password did not match");
				return;
			}

			if (getNewPassword().length() < 4 || getNewPassword().length() > 20) {
				LOGGER.info(getPlayer().getCurrentIP() + " - Pass change failed: New password is either too long or too short.");
				ActionSender.sendMessage(getPlayer(), "No changes made, your new password must be 4-20 characters.");
				return;
			}

			newDBPass = DataConversions.hashPassword(getNewPassword(), DBsalt);
			getPlayer().getWorld().getServer().getDatabase().saveNewPassword(playerID, newDBPass);

			String lastPw, earlierPw;
			try {
				earlierPw = getServer().getDatabase().getPreviousPassword(playerID);
			} catch (Exception e) {
				earlierPw = "";
			}
			lastPw = lastDBPass;

			getPlayer().getWorld().getServer().getDatabase().savePreviousPasswords(playerID, lastPw, earlierPw);

			// Do not record the actual password hashes in the audit log; a
			// change event plus the player/IP (captured by SecurityChangeLog)
			// is enough for moderation without leaving crackable material in
			// a table read by tooling.
			getPlayer().getWorld().getServer().getGameLogger().addQuery(new SecurityChangeLog(getPlayer(), SecurityChangeLog.ChangeEvent.PASSWORD_CHANGE,
				"Password changed"));
			ActionSender.sendMessage(getPlayer(), "Your password was successfully changed!");
			LOGGER.info(getPlayer().getCurrentIP() + " - Password change successful");

		} catch (Exception e) {
			LOGGER.catching(e);
		}
	}
}
