package com.openrsc.server.net.rsc.parsers.impl;

import com.openrsc.server.constants.Classes;
import com.openrsc.server.constants.Spells;
import com.openrsc.server.model.Point;
import com.openrsc.server.model.entity.player.Player;
import com.openrsc.server.net.Packet;
import com.openrsc.server.net.rsc.enums.OpcodeIn;
import com.openrsc.server.net.rsc.parsers.PayloadParser;
import com.openrsc.server.net.rsc.struct.AbstractStruct;
import com.openrsc.server.net.rsc.struct.incoming.*;
import com.openrsc.server.util.rsc.DataConversions;
import com.openrsc.server.util.rsc.StringUtil;

/**
 * RSC Protocol-69 Parser of Incoming Packets to respective Protocol Independent Structs
 * **/
public class Payload69Parser implements PayloadParser<OpcodeIn> {
	@Override
	public OpcodeIn toOpcodeEnum(Packet packet, Player player) {
		return switch (packet.getID()) {
			case 5 -> OpcodeIn.HEARTBEAT;
			case 215 -> OpcodeIn.WALK_TO_ENTITY;
			case 255 -> OpcodeIn.WALK_TO_POINT;
			case 1 -> OpcodeIn.CONFIRM_LOGOUT;
			case 231 -> OpcodeIn.COMBAT_STYLE_CHANGED;
			case 237 -> OpcodeIn.QUESTION_DIALOG_ANSWER;
			case 236 -> OpcodeIn.PLAYER_APPEARANCE_CHANGE;
			case 29 -> OpcodeIn.SOCIAL_ADD_IGNORE;
			case 26 -> OpcodeIn.SOCIAL_ADD_FRIEND;
			case 28 -> OpcodeIn.SOCIAL_SEND_PRIVATE_MESSAGE;
			case 27 -> OpcodeIn.SOCIAL_REMOVE_FRIEND;
			case 30 -> OpcodeIn.SOCIAL_REMOVE_IGNORE;
			case 238 -> OpcodeIn.INTERACT_WITH_BOUNDARY;
			case 229 -> OpcodeIn.INTERACT_WITH_BOUNDARY2;
			case 223 -> OpcodeIn.CAST_ON_BOUNDARY;
			case 239 -> OpcodeIn.USE_WITH_BOUNDARY;
			case 245 -> OpcodeIn.NPC_TALK_TO;
			case 244 -> OpcodeIn.NPC_ATTACK;
			case 225 -> OpcodeIn.CAST_ON_NPC;
			case 243 -> OpcodeIn.NPC_USE_ITEM;
			case 226 -> OpcodeIn.PLAYER_CAST_PVP;
			case 219 -> OpcodeIn.PLAYER_USE_ITEM;
			case 228 -> OpcodeIn.PLAYER_ATTACK;
			case 235 -> OpcodeIn.PLAYER_INIT_TRADE_REQUEST;
			case 214 -> OpcodeIn.PLAYER_FOLLOW;
			case 224 -> OpcodeIn.CAST_ON_GROUND_ITEM;
			case 250 -> OpcodeIn.GROUND_ITEM_USE_ITEM;
			case 240 -> OpcodeIn.ITEM_USE_ITEM;
			case 248 -> OpcodeIn.ITEM_UNEQUIP_FROM_INVENTORY;
			case 249 -> OpcodeIn.ITEM_EQUIP_FROM_INVENTORY;
			case 246 -> OpcodeIn.ITEM_COMMAND;
			case 251 -> OpcodeIn.ITEM_DROP;
			case 227 -> OpcodeIn.CAST_ON_SELF;
			case 221 -> OpcodeIn.CAST_ON_LAND;
			case 242 -> OpcodeIn.OBJECT_COMMAND;
			case 230 -> OpcodeIn.OBJECT_COMMAND2;
			case 222 -> OpcodeIn.CAST_ON_SCENERY;
			case 241 -> OpcodeIn.USE_ITEM_ON_SCENERY;
			case 218 -> OpcodeIn.SHOP_CLOSE;
			case 217 -> OpcodeIn.SHOP_BUY;
			case 216 -> OpcodeIn.SHOP_SELL;
			case 233 -> OpcodeIn.PLAYER_DECLINED_TRADE;
			case 234 -> OpcodeIn.PLAYER_ADDED_ITEMS_TO_TRADE_OFFER;
			case 232 -> OpcodeIn.PLAYER_ACCEPTED_INIT_TRADE_REQUEST;
			case 3 -> OpcodeIn.CHAT_MESSAGE;
			case 31 -> OpcodeIn.PRIVACY_SETTINGS_CHANGED;
			case 0, 19 -> OpcodeIn.LOGIN; //19 is relogin
			case 2 -> OpcodeIn.REGISTER_ACCOUNT;
			case 220 -> OpcodeIn.CAST_ON_INVENTORY_ITEM;
			case 252 -> OpcodeIn.GROUND_ITEM_TAKE;
			case 25 -> OpcodeIn.CHANGE_PASS;
			case 213 -> OpcodeIn.GAME_SETTINGS_CHANGED;
			case 17 -> OpcodeIn.SEND_DEBUG_INFO;
			case 254 -> OpcodeIn.KNOWN_PLAYERS;
			default -> null;
		};
	}

	@Override
	public AbstractStruct<OpcodeIn> parse(Packet packet, Player player) {

		OpcodeIn opcode = toOpcodeEnum(packet, player);
		AbstractStruct<OpcodeIn> result = null;

		switch (opcode) {
			case COMBAT_STYLE_CHANGED:
				CombatStyleStruct c = new CombatStyleStruct();
				c.style = packet.readByte();
				result = c;
				break;

			case PLAYER_APPEARANCE_CHANGE:
				PlayerAppearanceStruct pl = new PlayerAppearanceStruct();
				pl.headRestrictions = packet.readByte();
				pl.headType = packet.readByte();
				pl.bodyType = packet.readByte();
				pl.mustEqual2 = packet.readByte();
				pl.hairColour = packet.readByte();
				pl.topColour = packet.readByte();
				pl.trouserColour = packet.readByte();
				pl.skinColour = packet.readByte();
								pl.chosenClass = switch (packet.readByte()) {
					case 0 -> Classes.ADVENTURER;
					case 1 -> Classes.WARRIOR;
					case 2 -> Classes.WIZARD;
					case 3 -> Classes.NECROMANCER;
					case 4 -> Classes.RANGER;
					default -> null;
				};
				pl.pkMode = packet.readByte();
				result = pl;
				break;

			case QUESTION_DIALOG_ANSWER:
				MenuOptionStruct m = new MenuOptionStruct();
				m.option = packet.readByte();
				result = m;
				break;

			case CHAT_MESSAGE:
				String message = packet.readString();
				if (message.startsWith("/")) {
					CommandStruct cms = new CommandStruct();
					cms.command = message.substring(1); // strip out /
					result = cms;
					opcode = OpcodeIn.COMMAND;
				} else if (message.startsWith("::")) {
					CommandStruct cms = new CommandStruct();
					cms.command = message.substring(2); // strip out ::
					result = cms;
					opcode = OpcodeIn.COMMAND;
				} else {
					ChatStruct cs = new ChatStruct();
					cs.message = message;
					result = cs;
				}
				break;
			case SOCIAL_ADD_FRIEND:
			case SOCIAL_REMOVE_FRIEND:
			case SOCIAL_ADD_IGNORE:
			case SOCIAL_REMOVE_IGNORE:
			case SOCIAL_SEND_PRIVATE_MESSAGE:
				FriendStruct fs = new FriendStruct();
				fs.player = DataConversions.hashToUsername(packet.readLong());
				if (opcode == OpcodeIn.SOCIAL_SEND_PRIVATE_MESSAGE) {
					int len = packet.readByte();
					fs.message = packet.readString(len);
				}
				result = fs;
				break;

			case SHOP_CLOSE:
				ShopStruct s = new ShopStruct();
				result = s;
				break;
			case SHOP_BUY:
			case SHOP_SELL:
				ShopStruct s1 = new ShopStruct();
				s1.catalogID = packet.readShort();
				s1.price = packet.readUnsignedShort();
				s1.amount = 1;
				result = s1;
				break;

			case ITEM_UNEQUIP_FROM_INVENTORY:
			case ITEM_EQUIP_FROM_INVENTORY:
				EquipStruct e = new EquipStruct();
				e.slotIndex = packet.readShort();
				result = e;
				break;

			case GROUND_ITEM_USE_ITEM:
				ItemOnGroundItemStruct iog = new ItemOnGroundItemStruct();
				iog.groundItemCoord = new Point(packet.readShort(), packet.readShort());
				iog.groundItemId = packet.readShort();
				iog.slotIndex = packet.readShort();
				result = iog;
				break;

			case ITEM_USE_ITEM:
				ItemOnItemStruct ioi = new ItemOnItemStruct();
				ioi.slotIndex1 = packet.readShort();
				ioi.slotIndex2 = packet.readShort();
				result = ioi;
				break;

			case USE_WITH_BOUNDARY:
			case USE_ITEM_ON_SCENERY:
				ItemOnObjectStruct ioo = new ItemOnObjectStruct();
				ioo.coordObject = new Point(packet.readShort(), packet.readShort());
				if (opcode == OpcodeIn.USE_WITH_BOUNDARY) {
					ioo.direction = packet.readByte();
				}
				ioo.slotID = packet.readShort();
				result = ioo;
				break;

			case NPC_USE_ITEM:
			case PLAYER_USE_ITEM:
				ItemOnMobStruct it = new ItemOnMobStruct();
				it.serverIndex = packet.readShort();
				it.slotIndex = packet.readShort();
				result = it;
				break;

			case GROUND_ITEM_TAKE:
				TargetPositionStruct tp = new TargetPositionStruct();
				tp.coordinate = new Point(packet.readShort(), packet.readShort());
				tp.itemId = packet.readShort();
				result = tp;
				break;

			case ITEM_COMMAND:
			case ITEM_DROP:
				ItemCommandStruct ic = new ItemCommandStruct();
				ic.index = packet.readShort();
				result = ic;
				break;

			case OBJECT_COMMAND:
			case OBJECT_COMMAND2:
			case INTERACT_WITH_BOUNDARY:
			case INTERACT_WITH_BOUNDARY2:
				TargetObjectStruct to = new TargetObjectStruct();
				to.coordObject = new Point(packet.readShort(), packet.readShort());
				if (opcode == OpcodeIn.INTERACT_WITH_BOUNDARY || opcode == OpcodeIn.INTERACT_WITH_BOUNDARY2) {
					to.direction = packet.readByte();
				}
				result = to;
				break;

			case NPC_ATTACK:
			case NPC_TALK_TO:
			case PLAYER_ATTACK:
			case PLAYER_FOLLOW:
				TargetMobStruct t = new TargetMobStruct();
				t.serverIndex = packet.readShort();
				result = t;
				break;

			case CAST_ON_SELF:
			case PLAYER_CAST_PVP:
			case CAST_ON_NPC:
			case CAST_ON_INVENTORY_ITEM:
			case CAST_ON_BOUNDARY:
			case CAST_ON_SCENERY:
			case CAST_ON_GROUND_ITEM:
			case CAST_ON_LAND:
				SpellStruct sp = new SpellStruct();
				if (opcode == OpcodeIn.PLAYER_CAST_PVP || opcode == OpcodeIn.CAST_ON_NPC
					|| opcode == OpcodeIn.CAST_ON_INVENTORY_ITEM) {
					sp.targetIndex = packet.readShort();
				} else if (opcode == OpcodeIn.CAST_ON_BOUNDARY || opcode == OpcodeIn.CAST_ON_SCENERY
					|| opcode == OpcodeIn.CAST_ON_GROUND_ITEM || opcode == OpcodeIn.CAST_ON_LAND) {
					sp.targetCoord = new Point(packet.readShort(), packet.readShort());
					if (opcode == OpcodeIn.CAST_ON_BOUNDARY) {
						sp.direction = packet.readByte();
					} else if (opcode == OpcodeIn.CAST_ON_GROUND_ITEM) {
						sp.targetIndex = packet.readShort();
					}
				}
				// reconstructed, since merged spellbook was 2 byte, likely split spellbook thought was
				// upper byte: 0 - good magic book, 1 - evil magic book, and lower byte: spell index inside
				Spells spell = null;
				boolean isEvilMagic = packet.readByte() == 1;
				int spellIndex = packet.readByte(); // spell inside the respective good/evil magic book
				if (!isEvilMagic) {
					spell = switch (spellIndex) {
						case 0 -> Spells.CHILL_BOLT;
						case 1 -> Spells.BURST_OF_STRENGTH;
						case 2 -> Spells.CAMOFLAUGE;
						case 3 -> Spells.ROCK_SKIN;
						case 4 -> Spells.WIND_BOLT_R;
						default -> null;
					};
				} else {
					spell = switch (spellIndex) {
						case 0 -> Spells.CONFUSE_R;
						case 1 -> Spells.THICK_SKIN;
						case 2 -> Spells.SHOCK_BOLT;
						case 3 -> Spells.ELEMENTAL_BOLT;
						case 4 -> Spells.FEAR;
						default -> null;
					};
				}
				sp.spell = spell;
				result = sp;
				break;

			case PLAYER_INIT_TRADE_REQUEST:
			case PLAYER_ACCEPTED_INIT_TRADE_REQUEST:
			case PLAYER_DECLINED_TRADE:
			case PLAYER_ADDED_ITEMS_TO_TRADE_OFFER:
				PlayerTradeStruct pt = new PlayerTradeStruct();
				if (opcode == OpcodeIn.PLAYER_INIT_TRADE_REQUEST) {
					pt.targetPlayerID = packet.readShort();
				} else if (opcode == OpcodeIn.PLAYER_ACCEPTED_INIT_TRADE_REQUEST) {
					pt.tradeAccepted = packet.readByte();
				} else if (opcode == OpcodeIn.PLAYER_ADDED_ITEMS_TO_TRADE_OFFER) {
					pt.tradeCount = packet.readByte();
					pt.tradeCatalogIDs = new int[pt.tradeCount];
					pt.tradeAmounts = new int[pt.tradeCount];
					pt.tradeNoted = new boolean[pt.tradeCount];
					for (int slot = 0; slot < pt.tradeCount; slot++) {
						pt.tradeCatalogIDs[slot] = packet.readShort();
						pt.tradeAmounts[slot] = packet.readUnsignedShort();
						pt.tradeNoted[slot] = false;
					}
				}
				result = pt;
				break;

			case KNOWN_PLAYERS:
				KnownPlayersStruct kp = new KnownPlayersStruct();
				kp.playerCount = packet.readShort();
				kp.playerServerIndex = new int[kp.playerCount];
				kp.playerServerAppearanceId = new int[kp.playerCount];
				for (int i = 0; i < kp.playerCount; i++) {
					kp.playerServerIndex[i] = packet.readShort();
					kp.playerServerAppearanceId[i] = packet.readShort();
				}
				result = kp;
				break;

			case GAME_SETTINGS_CHANGED:
				GameSettingStruct gs = new GameSettingStruct();
				int setting = gs.index = packet.readByte();
				int value = gs.value = packet.readByte();
				if (setting == 0) {
					gs.cameraModeAuto = value;
				} else if (setting == 1) {
					gs.playerKiller = value;
				} else if (setting == 2) {
					gs.mouseButtonOne = value;
				}
				result = gs;
				break;

			case PRIVACY_SETTINGS_CHANGED:
				PrivacySettingsStruct pr = new PrivacySettingsStruct();
				pr.hideStatus = packet.readByte();
				pr.blockChat = packet.readByte();
				pr.blockPrivate = packet.readByte();
				pr.blockTrade = packet.readByte();
				packet.readByte(); // todo:? always sent 0 here
				result = pr;
				break;

			case CHANGE_PASS:
				SecuritySettingsStruct sec = new SecuritySettingsStruct();
				String newPassword = packet.readString(20).trim(); // only newPassword sent
				sec.passwords = new String[]{ "", newPassword };

				result = sec;
				break;

			case HEARTBEAT:
			case CONFIRM_LOGOUT:
				NoPayloadStruct n = new NoPayloadStruct();
				result = n;
				break;

			case WALK_TO_POINT:
			case WALK_TO_ENTITY:
				WalkStruct w = new WalkStruct();
				w.firstStep = new Point(packet.readShort(), packet.readShort());

				int numWaypoints = packet.getReadableBytes() / 2;
				for (int stepCount = 0; stepCount < numWaypoints; stepCount++) {
					w.steps.add(new Point(packet.readByte(), packet.readByte()));
				}
				result = w;
				break;

			case SEND_DEBUG_INFO:
				DebugInfoStruct ds = new DebugInfoStruct();
				ds.infoString = packet.readString();
				result = ds;
				break;
		}

		if (result != null) {
			result.setOpcode(opcode);
		}

		return result;

	}

	public static boolean isPossiblyValid(int opcode, int length, int protocolVer) {
		if (protocolVer != 38) {
			return true;
		}
		int payloadLength = length - 1; // subtract off opcode length.

		return switch (opcode) {
			case 5 -> payloadLength == 0;
			case 215 -> payloadLength >= 4;
			case 255 -> payloadLength >= 4;
			case 1 -> payloadLength == 0;
			case 231 -> payloadLength == 1;
			case 237 -> payloadLength == 1;
			case 236 -> payloadLength == 10;
			case 29 -> payloadLength == 8;
			case 26 -> payloadLength == 8;
			case 28 -> payloadLength >= 9;
			case 27 -> payloadLength == 8;
			case 30 -> payloadLength == 8;
			case 238 -> payloadLength == 5;
			case 229 -> payloadLength == 5;
			case 223 -> payloadLength == 7;
			case 239 -> payloadLength == 7;
			case 245 -> payloadLength == 2;
			case 244 -> payloadLength == 2;
			case 225 -> payloadLength == 4;
			case 243 -> payloadLength == 4;
			case 226 -> payloadLength == 4;
			case 219 -> payloadLength == 4;
			case 228 -> payloadLength == 2;
			case 235 -> payloadLength == 2;
			case 214 -> payloadLength == 2;
			case 224 -> payloadLength == 8;
			case 250 -> payloadLength == 8;
			case 252 -> payloadLength == 6;
			case 220 -> payloadLength == 4;
			case 240 -> payloadLength == 4;
			case 248 -> payloadLength == 2;
			case 249 -> payloadLength == 2;
			case 246 -> payloadLength == 2;
			case 251 -> payloadLength == 2;
			case 227 -> payloadLength == 2;
			case 221 -> payloadLength == 6;
			case 242 -> payloadLength == 4;
			case 230 -> payloadLength == 4;
			case 222 -> payloadLength == 6;
			case 241 -> payloadLength == 6;
			case 218 -> payloadLength == 0;
			case 217 -> payloadLength == 4;
			case 216 -> payloadLength == 4;
			case 233 -> payloadLength == 0;
			case 234 -> payloadLength >= 1;
			case 232 -> payloadLength == 1;
			case 213 -> payloadLength == 2;
			case 3 -> payloadLength >= 0;
			case 31 -> payloadLength == 5;
			case 25 -> payloadLength == 20;
			case 254 -> payloadLength >= 2;
			case 17 -> payloadLength > 0;
			default -> {
				System.out.println("Received inauthentic opcode %d from authentic claiming client".formatted(opcode));
				yield false;
			}
		};
	}
}
