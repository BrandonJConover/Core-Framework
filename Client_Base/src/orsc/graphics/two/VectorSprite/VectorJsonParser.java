package orsc.graphics.two.VectorSprite;

import java.io.*;
import java.util.*;

/**
 * Zero-dependency JSON parser for vector sprite definition files.
 * Handles the constrained grammar needed for vector sprite archives.
 */
public class VectorJsonParser {

	private char[] data;
	private int pos;

	public List<VectorDefinition> parseArchive(InputStream in) throws IOException {
		var baos = new ByteArrayOutputStream();
		var buf = new byte[4096];
		int n;
		while ((n = in.read(buf)) != -1) {
			baos.write(buf, 0, n);
		}
		return parseArchive(baos.toString("UTF-8"));
	}

	@SuppressWarnings("unchecked")
	public List<VectorDefinition> parseArchive(String json) {
		this.data = json.toCharArray();
		this.pos = 0;

		var defs = new ArrayList<VectorDefinition>();
		var root = parseObject();

		if (root.get("sprites") instanceof List<?> spritesList) {
			for (var item : spritesList) {
				if (item instanceof Map<?, ?> map) {
					defs.addAll(parseDefinition((Map<String, Object>) map));
				}
			}
		}

		return defs;
	}

	@SuppressWarnings("unchecked")
	private List<VectorDefinition> parseDefinition(Map<String, Object> json) {
		var id = getString(json, "id", "unknown");
		var subspace = getString(json, "subspace", "items");
		var entryType = getString(json, "entryType", "SPRITE");
		var layerName = getNullableString(json, "layer");

		// Multi-frame format: "frames" array present
		if (json.get("frames") instanceof List<?> framesList) {
			var defs = new ArrayList<VectorDefinition>();
			int totalFrames = framesList.size();

			for (int fi = 0; fi < framesList.size(); fi++) {
				var frameObj = framesList.get(fi);
				if (frameObj == null || !(frameObj instanceof Map<?, ?>)) {
					// null frame placeholder - skip but preserve index
					continue;
				}
				var frameMap = (Map<String, Object>) frameObj;
				var width = getInt(frameMap, "width", 48);
				var height = getInt(frameMap, "height", 32);

				var def = new VectorDefinition(id, subspace, width, height);
				def.setEntryTypeName(entryType);
				def.setLayerName(layerName);
				def.setFrameIndex(fi);
				def.setTotalFrames(totalFrames);
				def.setRequiresShift(getBool(frameMap, "requiresShift", false));
				def.setXShift(getInt(frameMap, "xShift", 0));
				def.setYShift(getInt(frameMap, "yShift", 0));
				def.setBoundWidth(getInt(frameMap, "boundWidth", 0));
				def.setBoundHeight(getInt(frameMap, "boundHeight", 0));

				parsePaletteInto(def, frameMap);
				parseShapesInto(def, frameMap);
				defs.add(def);
			}
			return defs;
		}

		// Single-frame format (backward compatible)
		var width = getInt(json, "width", 48);
		var height = getInt(json, "height", 32);

		var def = new VectorDefinition(id, subspace, width, height);
		def.setEntryTypeName(entryType);
		def.setLayerName(layerName);
		def.setRequiresShift(getBool(json, "requiresShift", false));
		def.setXShift(getInt(json, "xShift", 0));
		def.setYShift(getInt(json, "yShift", 0));
		def.setBoundWidth(getInt(json, "boundWidth", 0));
		def.setBoundHeight(getInt(json, "boundHeight", 0));

		parsePaletteInto(def, json);
		parseShapesInto(def, json);

		return List.of(def);
	}

	@SuppressWarnings("unchecked")
	private void parsePaletteInto(VectorDefinition def, Map<String, Object> json) {
		var paletteObj = json.get("palette");

		// Compact format: palette is an array of hex strings ["#FF0000", "#00FF00", ...]
		if (paletteObj instanceof List<?> paletteList) {
			var palette = new VectorPalette();
			for (int i = 0; i < paletteList.size(); i++) {
				palette.addColor("c" + i,
					VectorPalette.parseHex(paletteList.get(i).toString()));
			}
			def.setPalette(palette);
			return;
		}

		// Original format: palette is a map of name -> hex {"blade": "#C8A860", ...}
		if (paletteObj instanceof Map<?, ?> paletteMap) {
			var palette = new VectorPalette();
			for (var entry : paletteMap.entrySet()) {
				palette.addColor(entry.getKey().toString(),
					VectorPalette.parseHex(entry.getValue().toString()));
			}
			def.setPalette(palette);
		}
	}

	@SuppressWarnings("unchecked")
	private void parseShapesInto(VectorDefinition def, Map<String, Object> json) {
		// Compact format: "rects" is array of [x, y, w, h, paletteIndex]
		if (json.get("rects") instanceof List<?> rectsList) {
			for (var rectItem : rectsList) {
				if (rectItem instanceof List<?> coords && coords.size() >= 5) {
					int x = ((Number) coords.get(0)).intValue();
					int y = ((Number) coords.get(1)).intValue();
					int w = ((Number) coords.get(2)).intValue();
					int h = ((Number) coords.get(3)).intValue();
					int ci = ((Number) coords.get(4)).intValue();
					def.addShape(new VectorShape.Rect(x, y, w, h, "c" + ci, null, 0));
				}
			}
			return;
		}

		// Original format: "shapes" is array of shape objects
		if (json.get("shapes") instanceof List<?> shapesList) {
			for (var shapeItem : shapesList) {
				if (shapeItem instanceof Map<?, ?> shapeMap) {
					var shape = parseShape((Map<String, Object>) shapeMap);
					if (shape != null) def.addShape(shape);
				}
			}
		}
	}

	@SuppressWarnings("unchecked")
	private VectorShape parseShape(Map<String, Object> json) {
		var type = getString(json, "type", "");
		var fill = getNullableString(json, "fill");
		var stroke = getNullableString(json, "stroke");
		var strokeWidth = getInt(json, "strokeWidth", 1);

		return switch (type) {
			case "rect" -> new VectorShape.Rect(
				getInt(json, "x", 0), getInt(json, "y", 0),
				getInt(json, "w", 0), getInt(json, "h", 0),
				fill, stroke, strokeWidth);
			case "polygon" -> new VectorShape.Polygon(
				getIntArray(json, "xPoints"), getIntArray(json, "yPoints"),
				fill, stroke, strokeWidth);
			case "circle" -> new VectorShape.Circle(
				getInt(json, "cx", 0), getInt(json, "cy", 0),
				getInt(json, "r", 0), fill, stroke, strokeWidth);
			case "ellipse" -> new VectorShape.Ellipse(
				getInt(json, "cx", 0), getInt(json, "cy", 0),
				getInt(json, "rx", 0), getInt(json, "ry", 0),
				fill, stroke, strokeWidth);
			case "line" -> new VectorShape.Line(
				getInt(json, "x1", 0), getInt(json, "y1", 0),
				getInt(json, "x2", 0), getInt(json, "y2", 0),
				stroke, strokeWidth);
			case "path" -> new VectorShape.Path(
				parsePathCommands(json), fill, stroke, strokeWidth);
			default -> null;
		};
	}

	@SuppressWarnings("unchecked")
	private VectorShape.PathCommand[] parsePathCommands(Map<String, Object> json) {
		if (!(json.get("commands") instanceof List<?> commandsList)) {
			return new VectorShape.PathCommand[0];
		}

		var cmds = new ArrayList<VectorShape.PathCommand>();
		for (var cmdObj : commandsList) {
			if (!(cmdObj instanceof Map<?, ?>)) continue;
			var cmd = (Map<String, Object>) cmdObj;
			var cmdType = getString(cmd, "type", "");

			VectorShape.PathCommand pc = switch (cmdType) {
				case "moveTo" -> new VectorShape.PathCommand.MoveTo(
					getInt(cmd, "x", 0), getInt(cmd, "y", 0));
				case "lineTo" -> new VectorShape.PathCommand.LineTo(
					getInt(cmd, "x", 0), getInt(cmd, "y", 0));
				case "quadTo" -> new VectorShape.PathCommand.QuadTo(
					getInt(cmd, "cx", 0), getInt(cmd, "cy", 0),
					getInt(cmd, "x", 0), getInt(cmd, "y", 0));
				case "curveTo" -> new VectorShape.PathCommand.CurveTo(
					getInt(cmd, "cx1", 0), getInt(cmd, "cy1", 0),
					getInt(cmd, "cx2", 0), getInt(cmd, "cy2", 0),
					getInt(cmd, "x", 0), getInt(cmd, "y", 0));
				case "close" -> new VectorShape.PathCommand.Close();
				default -> null;
			};
			if (pc != null) cmds.add(pc);
		}

		return cmds.toArray(new VectorShape.PathCommand[0]);
	}

	// --- Minimal JSON tokenizer/parser ---

	private void skipWhitespace() {
		while (pos < data.length && Character.isWhitespace(data[pos])) pos++;
	}

	private char peek() {
		skipWhitespace();
		return pos < data.length ? data[pos] : 0;
	}

	private char next() {
		skipWhitespace();
		return pos < data.length ? data[pos++] : 0;
	}

	private Object parseValue() {
		char c = peek();
		if (c == '{') return parseObject();
		if (c == '[') return parseArray();
		if (c == '"') return parseString();
		if (c == 't' || c == 'f') return parseBoolean();
		if (c == 'n') return parseNull();
		if (c == '-' || (c >= '0' && c <= '9')) return parseNumber();
		throw new RuntimeException("Unexpected character '" + c + "' at position " + pos);
	}

	private Map<String, Object> parseObject() {
		var map = new LinkedHashMap<String, Object>();
		next(); // consume '{'
		if (peek() == '}') { next(); return map; }

		while (true) {
			var key = parseString();
			if (next() != ':') throw new RuntimeException("Expected ':' at " + pos);
			map.put(key, parseValue());

			char sep = next();
			if (sep == '}') break;
			if (sep != ',') throw new RuntimeException("Expected ',' or '}' at " + pos);
		}
		return map;
	}

	private List<Object> parseArray() {
		var list = new ArrayList<>();
		next(); // consume '['
		if (peek() == ']') { next(); return list; }

		while (true) {
			list.add(parseValue());
			char sep = next();
			if (sep == ']') break;
			if (sep != ',') throw new RuntimeException("Expected ',' or ']' at " + pos);
		}
		return list;
	}

	private String parseString() {
		next(); // consume opening '"'
		var sb = new StringBuilder();
		while (pos < data.length) {
			char c = data[pos++];
			if (c == '"') return sb.toString();
			if (c == '\\') {
				if (pos >= data.length) break;
				char esc = data[pos++];
				switch (esc) {
					case '"': case '\\': case '/': sb.append(esc); break;
					case 'n': sb.append('\n'); break;
					case 't': sb.append('\t'); break;
					case 'r': sb.append('\r'); break;
					case 'u':
						sb.append((char) Integer.parseInt(new String(data, pos, 4), 16));
						pos += 4;
						break;
					default: sb.append(esc);
				}
			} else {
				sb.append(c);
			}
		}
		throw new RuntimeException("Unterminated string at " + pos);
	}

	private Number parseNumber() {
		skipWhitespace();
		int start = pos;
		boolean isFloat = false;

		if (pos < data.length && data[pos] == '-') pos++;
		while (pos < data.length && data[pos] >= '0' && data[pos] <= '9') pos++;
		if (pos < data.length && data[pos] == '.') {
			isFloat = true;
			pos++;
			while (pos < data.length && data[pos] >= '0' && data[pos] <= '9') pos++;
		}
		if (pos < data.length && (data[pos] == 'e' || data[pos] == 'E')) {
			isFloat = true;
			pos++;
			if (pos < data.length && (data[pos] == '+' || data[pos] == '-')) pos++;
			while (pos < data.length && data[pos] >= '0' && data[pos] <= '9') pos++;
		}

		var numStr = new String(data, start, pos - start);
		if (isFloat) return Double.parseDouble(numStr);
		long val = Long.parseLong(numStr);
		if (val >= Integer.MIN_VALUE && val <= Integer.MAX_VALUE) return (int) val;
		return val;
	}

	private Boolean parseBoolean() {
		skipWhitespace();
		if (data[pos] == 't') { pos += 4; return Boolean.TRUE; }
		else { pos += 5; return Boolean.FALSE; }
	}

	private Object parseNull() {
		pos += 4;
		return null;
	}

	// --- Utility extraction methods ---

	private static String getString(Map<String, Object> map, String key, String defaultVal) {
		var val = map.get(key);
		return val != null ? val.toString() : defaultVal;
	}

	private static String getNullableString(Map<String, Object> map, String key) {
		if (!map.containsKey(key)) return null;
		var val = map.get(key);
		if (val == null) return null;
		var str = val.toString();
		return "null".equals(str) ? null : str;
	}

	private static int getInt(Map<String, Object> map, String key, int defaultVal) {
		if (map.get(key) instanceof Number num) return num.intValue();
		return defaultVal;
	}

	private static boolean getBool(Map<String, Object> map, String key, boolean defaultVal) {
		if (map.get(key) instanceof Boolean b) return b;
		return defaultVal;
	}

	@SuppressWarnings("unchecked")
	private static int[] getIntArray(Map<String, Object> map, String key) {
		if (!(map.get(key) instanceof List<?> list)) return new int[0];
		var arr = new int[list.size()];
		for (int i = 0; i < list.size(); i++) {
			if (list.get(i) instanceof Number num) arr[i] = num.intValue();
		}
		return arr;
	}
}
