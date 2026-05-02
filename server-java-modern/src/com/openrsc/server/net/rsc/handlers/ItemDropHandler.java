package com.openrsc.server.net.rsc.handlers;

import com.openrsc.server.constants.ItemId;
import com.openrsc.server.model.container.Item;
import com.openrsc.server.model.entity.player.Player;
import com.openrsc.server.net.rsc.PayloadProcessor;
import com.openrsc.server.net.rsc.enums.OpcodeIn;
import com.openrsc.server.net.rsc.struct.incoming.ItemCommandStruct;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.Optional;

public final class ItemDropHandler implements PayloadProcessor<ItemCommandStruct, OpcodeIn> {
	private static final Logger LOGGER = LogManager.getLogger("OpenRSC");

	public void process(ItemCommandStruct payload, Player player) throws Exception {
		if (player.inCombat()) {
			LOGGER.info("Drop rejected for {}: in combat, slot={}", player.getUsername(), payload.index);
			player.message("You can't do that whilst you are fighting");
			player.resetPath();
			return;
		}

		if (player.getDuel().isDueling()) {
			LOGGER.info("Drop rejected for {}: actively dueling, slot={}", player.getUsername(), payload.index);
			return;
		}

		if (player.isBusy()) {
			LOGGER.info("Drop rejected for {}: player busy, slot={}", player.getUsername(), payload.index);
			player.resetPath();
			return;
		}

		if (player.getTrade().isTradeActive() || (player.getDuel().isDuelActive() && !player.inCombat())) {
			// prevent dropping of items during trade & duels windows
			LOGGER.info("Drop rejected for {}: trade/duel window active, slot={}", player.getUsername(), payload.index);
			return;
		}

		player.resetAll();
		int inventorySlot = payload.index;
		int amount;
		boolean respectDropX = player.isUsingCustomClient() && player.getWorld().getServer().getConfig().WANT_DROP_X;
		if (respectDropX) {
			amount = payload.amount;
		} else {
			amount = 0;
		}

		if (inventorySlot < -1 || inventorySlot >= player.getCarriedItems().getInventory().size()) {
			LOGGER.info("Drop rejected for {}: invalid slot={}, inventorySize={}",
				player.getUsername(), inventorySlot, player.getCarriedItems().getInventory().size());
			player.setSuspiciousPlayer(true, "item drop item inventorySlot < -1 or inventorySlot >= inv size");
			return;
		}
		Item tempitem = null;

		// User wants to drop the item from equipment tab
		if (inventorySlot == -1 && player.isUsingCustomClient() && player.getWorld().getServer().getConfig().WANT_EQUIPMENT_TAB) {
			int realid = payload.realIndex;
			int slot = player.getCarriedItems().getEquipment().searchEquipmentForItem(realid);
			if (slot != -1) {
				tempitem = player.getCarriedItems().getEquipment().get(slot);
				if (!respectDropX) {
					amount = tempitem.getAmount();
				}
			}
		} else {
			if (inventorySlot != -1) {
				tempitem = player.getCarriedItems().getInventory().get(inventorySlot);
				if (!respectDropX) {
					amount = tempitem.getAmount();
				}
			}
		}

		if (tempitem == null || tempitem.getCatalogId() == ItemId.NOTHING.id()) {
			LOGGER.info("Drop rejected for {}: empty slot={}, realIndex={}",
				player.getUsername(), inventorySlot, payload.realIndex);
			return;
		}
		final Item item = new Item(tempitem.getCatalogId(), amount, tempitem.getNoted(), tempitem.getItemId());

		if (amount <= 0) {
			LOGGER.info("Drop rejected for {}: non-positive amount={}, slot={}, catalogId={}",
				player.getUsername(), amount, inventorySlot, tempitem.getCatalogId());
			return;
		}

		if (item.getNoted() && !player.getConfig().WANT_BANK_NOTES) {
			player.message("Notes have been disabled; you cannot drop them anymore.");
			player.message("You may either deposit it in the bank or sell to a shop instead.");
			return;
		}

		if (item.getCatalogId() > player.getClientLimitations().maxItemId) {
			player.message("You don't even know what that is...!");
			player.message("Definitely update your client before trying to drop that item.");
			return;
		}

		if (inventorySlot != -1) {
			final int idCount = player.getCarriedItems().getInventory().countId(item.getCatalogId(), Optional.of(item.getNoted()));

			if (amount > idCount)
				amount = idCount;
		}

		final boolean fromInventory = inventorySlot != -1;

		// Set temporary amount until event executes and double checks.
		item.getItemStatus().setAmount(amount);
		LOGGER.info("Drop accepted for {}: slot={}, catalogId={}, amount={}, noted={}, fromInventory={}",
			player.getUsername(), inventorySlot, item.getCatalogId(), amount, item.getNoted(), inventorySlot != -1);

		// Set up our player to drop an item after walking
		if (!player.getWalkingQueue().finished()) {
			player.setDropItemEvent(inventorySlot, item);
		}
		else {
			player.setDropItemEvent(inventorySlot, item);
			player.runDropEvent(fromInventory);
		}
	}
}
