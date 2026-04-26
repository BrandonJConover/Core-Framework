package com.openrsc.server.net.rsc.parsers.impl;

import com.openrsc.server.constants.Classes;
import com.openrsc.server.constants.Constants;
import com.openrsc.server.model.Point;
import com.openrsc.server.model.entity.player.Player;
import com.openrsc.server.net.Packet;
import com.openrsc.server.net.rsc.Crypto;
import com.openrsc.server.net.rsc.enums.OpcodeIn;
import com.openrsc.server.net.rsc.parsers.PayloadParser;
import com.openrsc.server.net.rsc.struct.AbstractStruct;
import com.openrsc.server.net.rsc.struct.incoming.*;
import com.openrsc.server.util.rsc.DataConversions;

import java.nio.ByteBuffer;
import java.util.Arrays;

/**
 * RSC Protocol-140 Parser of Incoming Packets to respective Protocol Independent Structs
 * **/
public class Payload140Parser implements PayloadParser<OpcodeIn> {
	@Override
	public OpcodeIn toOpcodeEnum(Packet packet, Player player) {
		return switch (packet.getID()) {
			case 5 -> OpcodeIn.HEARTBEAT; // 348
			case 215 -> OpcodeIn.WALK_TO_ENTITY; // 592
			case 194 -> OpcodeIn.WALK_TO_POINT; // 770
			case 1 -> OpcodeIn.CONFIRM_LOGOUT; // 325
			case 6 -> OpcodeIn.LOGOUT; // 156
			case 231 -> OpcodeIn.COMBAT_STYLE_CHANGED; // 700
			case 237 -> OpcodeIn.QUESTION_DIALOG_ANSWER; // 3
			case 236 -> OpcodeIn.PLAYER_APPEARANCE_CHANGE; // 65
			case 29 -> OpcodeIn.SOCIAL_ADD_IGNORE; // 101
			case 26 -> OpcodeIn.SOCIAL_ADD_FRIEND; // 622
			case 28 -> OpcodeIn.SOCIAL_SEND_PRIVATE_MESSAGE; // 185
			case 27 -> OpcodeIn.SOCIAL_REMOVE_FRIEND; // 707
			case 30 -> OpcodeIn.SOCIAL_REMOVE_IGNORE; // 511
			case 199 -> OpcodeIn.DUEL_FIRST_ACCEPTED; // 564
			case 201 -> OpcodeIn.DUEL_OFFER_ITEM; // 53
			case 200 -> OpcodeIn.DUEL_FIRST_SETTINGS_CHANGED; // 285
			case 203 -> OpcodeIn.DUEL_DECLINED; // 266
			case 198 -> OpcodeIn.DUEL_SECOND_ACCEPTED; // 412
			case 238 -> OpcodeIn.INTERACT_WITH_BOUNDARY; // 212
			case 229 -> OpcodeIn.INTERACT_WITH_BOUNDARY2; // 726
			case 252 -> OpcodeIn.GROUND_ITEM_TAKE; // 634
			case 223 -> OpcodeIn.CAST_ON_BOUNDARY; // 596
			case 239 -> OpcodeIn.USE_WITH_BOUNDARY; // 792
			case 245 -> OpcodeIn.NPC_TALK_TO; // 586
			case 195 -> OpcodeIn.NPC_COMMAND; // 543
			case 244 -> OpcodeIn.NPC_ATTACK; // 754
			case 225 -> OpcodeIn.CAST_ON_NPC; // 824
			case 243 -> OpcodeIn.NPC_USE_ITEM; // 876
			case 226 -> OpcodeIn.PLAYER_CAST_PVP; // 117
			case 219 -> OpcodeIn.PLAYER_USE_ITEM; // 145
			case 228 -> OpcodeIn.PLAYER_ATTACK; // 414
			case 204 -> OpcodeIn.PLAYER_DUEL; // 273
			case 235 -> OpcodeIn.PLAYER_INIT_TRADE_REQUEST; // 636
			case 214 -> OpcodeIn.PLAYER_FOLLOW; // 596
			case 224 -> OpcodeIn.CAST_ON_GROUND_ITEM; // 821
			case 250 -> OpcodeIn.GROUND_ITEM_USE_ITEM; // 346
			case 220 -> OpcodeIn.CAST_ON_INVENTORY_ITEM; // 567
			case 240 -> OpcodeIn.ITEM_USE_ITEM; // 377
			case 248 -> OpcodeIn.ITEM_UNEQUIP_FROM_INVENTORY; // 466
			case 249 -> OpcodeIn.ITEM_EQUIP_FROM_INVENTORY; // 267
			case 246 -> OpcodeIn.ITEM_COMMAND; // 237
			case 251 -> OpcodeIn.ITEM_DROP; // 664
			case 227 -> OpcodeIn.CAST_ON_SELF; // 411
			case 221 -> OpcodeIn.CAST_ON_LAND; // 545
			case 242 -> OpcodeIn.OBJECT_COMMAND; // 863
			case 230 -> OpcodeIn.OBJECT_COMMAND2; // 67
			case 222 -> OpcodeIn.CAST_ON_SCENERY; // 555
			case 241 -> OpcodeIn.USE_ITEM_ON_SCENERY; // 772
			case 218 -> OpcodeIn.SHOP_CLOSE; // 312
			case 217 -> OpcodeIn.SHOP_BUY; // 666
			case 216 -> OpcodeIn.SHOP_SELL; // 665
			case 232 -> OpcodeIn.PLAYER_ACCEPTED_INIT_TRADE_REQUEST; // 277
			case 233 -> OpcodeIn.PLAYER_DECLINED_TRADE; // 235
			case 234 -> OpcodeIn.PLAYER_ADDED_ITEMS_TO_TRADE_OFFER; // 500
			case 202 -> OpcodeIn.PLAYER_ACCEPTED_TRADE; // 96
			case 212 -> OpcodeIn.PRAYER_ACTIVATED; // 126
			case 211 -> OpcodeIn.PRAYER_DEACTIVATED; // 457
			case 213 -> OpcodeIn.GAME_SETTINGS_CHANGED; // 892
			case 3 -> OpcodeIn.CHAT_MESSAGE; // 643
			case 7 -> OpcodeIn.COMMAND; // 293
			case 31 -> OpcodeIn.PRIVACY_SETTINGS_CHANGED; // 777
			case 10 -> OpcodeIn.REPORT_ABUSE; // 277
			case 207 -> OpcodeIn.BANK_CLOSE; // 886
			case 206 -> OpcodeIn.BANK_WITHDRAW; // 655
			case 205 -> OpcodeIn.BANK_DEPOSIT; // 523
			case 193 -> OpcodeIn.SLEEPWORD_ENTERED; // 127
			case 0, 19 -> OpcodeIn.LOGIN; // 625
			case 2 -> OpcodeIn.REGISTER_ACCOUNT; // 129
			case 4 -> OpcodeIn.FORGOT_PASSWORD; // 848
			case 8 -> OpcodeIn.RECOVERY_ATTEMPT; // 121
			case 197 -> OpcodeIn.CHANGE_RECOVERY_REQUEST; // 882
			case 25 -> OpcodeIn.CHANGE_PASS; // 551
			case 208 -> OpcodeIn.SET_RECOVERY; // 457
			case 196 -> OpcodeIn.CANCEL_RECOVERY_REQUEST; // 651
			case 17 -> OpcodeIn.SEND_DEBUG_INFO; // 743
			case 254 -> OpcodeIn.KNOWN_PLAYERS; // 120
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
					case 3 -> Classes.RANGER;
					case 4 -> Classes.MINER;
					default -> null;
				};
				result = pl;
				break;

			case QUESTION_DIALOG_ANSWER:
				MenuOptionStruct m = new MenuOptionStruct();
				m.option = packet.readByte();
				result = m;
				break;

			case CHAT_MESSAGE:
				ChatStruct cs = new ChatStruct();
				cs.message = read177RSCString(packet.readBytes(packet.getReadableBytes()));
				result = cs;
				break;
			case COMMAND:
				CommandStruct co = new CommandStruct();
				co.command = packet.readString();
				result = co;
				break;
			case SOCIAL_ADD_FRIEND:
			case SOCIAL_REMOVE_FRIEND:
			case SOCIAL_ADD_IGNORE:
			case SOCIAL_REMOVE_IGNORE:
			case SOCIAL_SEND_PRIVATE_MESSAGE:
				FriendStruct fs = new FriendStruct();
				fs.player = DataConversions.hashToUsername(packet.readLong());
				if (opcode == OpcodeIn.SOCIAL_SEND_PRIVATE_MESSAGE) {
					fs.message = read177RSCString(packet.readBytes(packet.getReadableBytes()));
				}
				result = fs;
				break;

			case BANK_CLOSE:
				BankStruct b = new BankStruct();
				result = b;
				break;
			case BANK_WITHDRAW:
			case BANK_DEPOSIT:
				BankStruct b1 = new BankStruct();
				b1.catalogID = packet.readShort();
				b1.amount = packet.readShort();
				result = b1;
				break;

			case SHOP_CLOSE:
				ShopStruct s = new ShopStruct();
				result = s;
				break;
			case SHOP_BUY:
			case SHOP_SELL:
				ShopStruct s1 = new ShopStruct();
				s1.catalogID = packet.readShort();
				s1.stockAmount = packet.readInt();
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

			case BLINK:
			case GROUND_ITEM_TAKE:
				TargetPositionStruct tp = new TargetPositionStruct();
				tp.coordinate = new Point(packet.readShort(), packet.readShort());
				if (opcode == OpcodeIn.GROUND_ITEM_TAKE) {
					tp.itemId = packet.readShort();
				}
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
			case NPC_COMMAND:
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
				sp.spell = Constants.spellToEnum(packet.readShort());
				result = sp;
				break;

			case PLAYER_DUEL:
			case DUEL_FIRST_SETTINGS_CHANGED:
			case DUEL_FIRST_ACCEPTED:
			case DUEL_DECLINED:
			case DUEL_OFFER_ITEM:
			case DUEL_SECOND_ACCEPTED:
				PlayerDuelStruct pd = new PlayerDuelStruct();
				if (opcode == OpcodeIn.PLAYER_DUEL) {
					pd.targetPlayerID = packet.readShort();
				} else if (opcode == OpcodeIn.DUEL_OFFER_ITEM) {
					pd.duelCount = packet.readByte();
					pd.duelCatalogIDs = new int[pd.duelCount];
					pd.duelAmounts = new int[pd.duelCount];
					pd.duelNoted = new boolean[pd.duelCount];
					for (int slot = 0; slot < pd.duelCount; slot++) {
						pd.duelCatalogIDs[slot] = packet.readShort();
						pd.duelAmounts[slot] = packet.readInt();
						pd.duelNoted[slot] = false;
					}
				} else if (opcode == OpcodeIn.DUEL_FIRST_SETTINGS_CHANGED) {
					pd.disallowRetreat = packet.readByte();
					pd.disallowMagic = packet.readByte();
					pd.disallowPrayer = packet.readByte();
					pd.disallowWeapons = packet.readByte();
				}
				result = pd;
				break;

			case PLAYER_INIT_TRADE_REQUEST:
			case PLAYER_ACCEPTED_INIT_TRADE_REQUEST:
			case PLAYER_ACCEPTED_TRADE:
			case PLAYER_DECLINED_TRADE:
			case PLAYER_ADDED_ITEMS_TO_TRADE_OFFER:
				PlayerTradeStruct pt = new PlayerTradeStruct();
				if (opcode == OpcodeIn.PLAYER_INIT_TRADE_REQUEST) {
					pt.targetPlayerID = packet.readShort();
				} else if (opcode == OpcodeIn.PLAYER_ADDED_ITEMS_TO_TRADE_OFFER) {
					pt.tradeCount = packet.readByte();
					pt.tradeCatalogIDs = new int[pt.tradeCount];
					pt.tradeAmounts = new int[pt.tradeCount];
					pt.tradeNoted = new boolean[pt.tradeCount];
					for (int slot = 0; slot < pt.tradeCount; slot++) {
						pt.tradeCatalogIDs[slot] = packet.readShort();
						pt.tradeAmounts[slot] = packet.readInt();
						pt.tradeNoted[slot] = false;
					}
				}
				result = pt;
				break;

			case PRAYER_ACTIVATED:
			case PRAYER_DEACTIVATED:
				PrayerStruct p = new PrayerStruct();
				p.prayerID = packet.readByte();
				result = p;
				break;

			case GAME_SETTINGS_CHANGED:
				GameSettingStruct gs = new GameSettingStruct();
				int setting = gs.index = packet.readByte();
				int value = gs.value = packet.readByte();
				if (setting == 0) {
					gs.cameraModeAuto = value;
				} else if (setting == 2) {
					gs.mouseButtonOne = value;
				} else if (setting == 3) {
					gs.soundDisabled = value;
				}
				result = gs;
				break;

			case PRIVACY_SETTINGS_CHANGED:
				PrivacySettingsStruct pr = new PrivacySettingsStruct();
				pr.blockChat = packet.readByte();
				pr.blockPrivate = packet.readByte();
				pr.blockTrade = packet.readByte();
				pr.blockDuel = packet.readByte();
				result = pr;
				break;

			case CHANGE_PASS:
			case CANCEL_RECOVERY_REQUEST:
			case CHANGE_RECOVERY_REQUEST:
			case CHANGE_DETAILS_REQUEST:
			case SET_RECOVERY:
			case SET_DETAILS:
				SecuritySettingsStruct sec = new SecuritySettingsStruct();
				if (opcode == OpcodeIn.CHANGE_PASS) {
					// Get encrypted block
					// old + new password is always 40 characters long, with spaces at the end.
					// each blocks having encrypted 7 chars of password
					int blockLen;
					byte[] decBlock; // current decrypted block
					int session =  player.sessionId;
					int receivedSession;
					boolean errored = false;
					byte[] concatPassData = new byte[42];
					for (int i = 0; i < 6; i++) {
						blockLen = packet.readUnsignedByte();
						decBlock = Crypto.decryptRSA(packet.readBytes(blockLen), 0, blockLen);
						// TODO: there are ignored nonces at the beginning of the decrypted block
						receivedSession = ByteBuffer.wrap(Arrays.copyOfRange(decBlock, 4, 8)).getInt();
						// decrypted packet must be of length 15
						if (session == -1 && decBlock.length == 15) {
							session = receivedSession;
						} else if (session != receivedSession || decBlock.length != 15) {
							errored = true; // decryption error occurred
						}

						if (!errored) {
							System.arraycopy(decBlock, 8, concatPassData, i * 7, 7);
						}
					}

					String oldPassword = "";
					String newPassword = "";
					try {
						oldPassword = new String(Arrays.copyOfRange(concatPassData, 0, 20), "UTF8").trim();
						newPassword = new String(Arrays.copyOfRange(concatPassData, 20, 42), "UTF8").trim();
					} catch (Exception ex1) {
						//LOGGER.info("error parsing passwords in change password block");
						errored = true;
						ex1.printStackTrace();
					}

					if (!errored) {
						sec.passwords = new String[]{ oldPassword, newPassword };
					}
				} else if (opcode == OpcodeIn.SET_RECOVERY) {
					// Get the 5 recovery answers
					int blockLen;
					byte[] decBlock; // current decrypted block
					int session =  player.sessionId;
					int receivedSession;
					boolean errored = false;
					int questLen = 0;
					int answerLen = 0;
					int expBlocks = 0;
					byte[] answerData;
					String questions[] = new String[5];
					String answers[] = new String[5];
					for (int i = 0; i < 5; i++) {
						questLen = packet.readUnsignedByte();
						questions[i] = new String(packet.readBytes(questLen));
						answerLen = packet.readUnsignedByte();
						// Get encrypted block for answers
						expBlocks = (int)Math.ceil(answerLen / 7.0);
						answerData = new byte[expBlocks * 7];
						for (int j = 0; j < expBlocks; j++) {
							blockLen = packet.readUnsignedByte();
							decBlock = Crypto.decryptRSA(packet.readBytes(blockLen), 0, blockLen);
							// TODO: there are ignored nonces at the beginning of the decrypted block
							receivedSession = ByteBuffer.wrap(Arrays.copyOfRange(decBlock, 4, 8)).getInt();
							// decrypted packet must be of length 15
							if (session == -1 && decBlock.length == 15) {
								session = receivedSession;
							} else if (session != receivedSession || decBlock.length != 15) {
								errored = true; // decryption error occurred
							}

							if (!errored) {
								System.arraycopy(decBlock, 8, answerData, j * 7, 7);
							}
						}

						try {
							answers[i] = new String(answerData, "UTF8").trim();
						} catch (Exception ex) {
							//LOGGER.info("error parsing answer " + i + " in change recovery block");
							errored = true;
							ex.printStackTrace();
						}
					}

					if (!errored) {
						sec.questions = questions.clone();
						sec.answers = answers.clone();
					}
				} else if (opcode == OpcodeIn.SET_DETAILS) {
					boolean errored = false;
					int expLen = 0;
					String details[] = new String[4];
					for (int i = 0; i < 4; i++) {
						expLen = packet.readUnsignedByte();
						details[i] = new String(packet.readBytes(expLen));
						if (details[i].length() != expLen) errored = true;
					}

					if (!errored) {
						sec.details = details.clone();
					}
				}
				result = sec;
				break;

			case REPORT_ABUSE:
				ReportStruct r = new ReportStruct();
				r.targetPlayerName = DataConversions.hashToUsername(packet.readLong());
				r.reason = 0; // reason was not supplied
				r.suggestsOrMutes = 0;
				result = r;
				break;

			case SLEEPWORD_ENTERED:
				SleepStruct sl = new SleepStruct();
				sl.sleepDelay = 0;
				sl.sleepWord = packet.readString();
				result = sl;
				break;

			case HEARTBEAT:
			case SKIP_TUTORIAL:
			case LOGOUT:
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
		}

		if (result != null) {
			result.setOpcode(opcode);
		}

		return result;

	}

	private String read177RSCString(byte[] data) {
		int formattedLength = 0;
		int aFlag = -1;
		char[] stringBuilder = new char[100];
		char[] characterDictionary = new char[]{' ', 'e', 't', 'a', 'o', 'i', 'h', 'n', 's', 'r', 'd', 'l', 'u', 'm', 'w', 'c', 'y', 'f', 'g', 'p', 'b', 'v', 'k', 'x', 'j', 'q', 'z', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ' ', '!', '?', '.', ',', ':', ';', '(', ')', '-', '&', '*', '\\', '\'', '@', '#', '+', '=', '£', '$', '%', '\"', '[', ']'};
		for (byte charByte : data) {
			int character = charByte & 255;
			int charIdx = character >> 4 & 15;
			if (aFlag == -1) {
				if (charIdx < 13) {
					stringBuilder[formattedLength++] = characterDictionary[charIdx];
				} else {
					aFlag = charIdx;
				}
			} else {
				stringBuilder[formattedLength++] = characterDictionary[(aFlag << 4) + charIdx - 195];
				aFlag = -1;
			}

			charIdx = character & 15;
			if (aFlag == -1) {
				if (charIdx < 13) {
					stringBuilder[formattedLength++] = characterDictionary[charIdx];
				} else {
					aFlag = charIdx;
				}
			} else {
				stringBuilder[formattedLength++] = characterDictionary[(aFlag << 4) + charIdx - 195];
				aFlag = -1;
			}
		}

		boolean forceCapital = true;
		for (int charIdx = 0; charIdx < formattedLength; charIdx++) {
			char asciiChar = stringBuilder[charIdx];
			if (charIdx > 4 && asciiChar == '@') {
				stringBuilder[charIdx] = ' ';
			}

			if (asciiChar == '%') {
				stringBuilder[charIdx] = ' ';
			}

			if (forceCapital && asciiChar >= 'a' && asciiChar <= 'z') {
				stringBuilder[charIdx] = (char) (stringBuilder[charIdx] - 32); // make uppercase
				forceCapital = false;
			}

			if (asciiChar == '.' || asciiChar == '!') {
				forceCapital = true;
			}
		}

		return new String(stringBuilder, 0, formattedLength);
	}

	// a basic check is done on authentic opcodes against their possible lengths
	public static boolean isPossiblyValid(int opcode, int length, int protocolVer) {
		// no ISAAC in this version, don't need this
		return true;
	}
}
