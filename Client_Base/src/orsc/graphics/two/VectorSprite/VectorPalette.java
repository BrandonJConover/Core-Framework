package orsc.graphics.two.VectorSprite;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Named color palette for vector sprite definitions.
 * Maps color names to ARGB int values.
 */
public class VectorPalette {

	private final Map<String, Integer> colors = new LinkedHashMap<String, Integer>();

	public void addColor(String name, int argb) {
		colors.put(name, argb);
	}

	public int getColor(String name) {
		Integer c = colors.get(name);
		return c != null ? c : 0xFF000000;
	}

	public boolean hasColor(String name) {
		return colors.containsKey(name);
	}

	/**
	 * Parse a hex color string (#RRGGBB or #AARRGGBB) to an opaque ARGB int.
	 */
	public static int parseHex(String hex) {
		if (hex == null || hex.isEmpty()) return 0xFF000000;
		if (hex.charAt(0) == '#') hex = hex.substring(1);

		if (hex.length() == 6) {
			return 0xFF000000 | Integer.parseInt(hex, 16);
		} else if (hex.length() == 8) {
			return (int) Long.parseLong(hex, 16);
		}
		return 0xFF000000;
	}

	public Map<String, Integer> getColors() {
		return colors;
	}
}
