package com.openrsc.server.net.rsc.struct.outgoing;

import com.openrsc.server.net.rsc.enums.OpcodeOut;
import com.openrsc.server.net.rsc.struct.AbstractStruct;

import java.util.List;
import java.util.Map;

public class MobsUpdateStruct extends AbstractStruct<OpcodeOut> {

	public List<Map.Entry<Integer, Integer>> mobs;
	public List<Object> mobsUpdate; // retro can be byte or short
}
