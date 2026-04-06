package orsc.graphics.two.VectorSprite;

import orsc.graphics.two.SpriteArchive.*;

import java.io.*;
import java.util.*;

/**
 * Converts raster sprite archives (.osar) into vector sprite JSON definitions.
 *
 * Uses greedy maximal-rectangle decomposition to convert pixel art into
 * compact rect-based vector definitions. Each unique color in a sprite
 * becomes a palette entry, and contiguous same-color pixel regions are
 * merged into the largest possible rectangles.
 *
 * Usage: java orsc.graphics.two.VectorSprite.RasterToVectorConverter [input.osar] [output.json]
 */
public class RasterToVectorConverter {

	public static void main(String[] args) throws Exception {
		String inputPath = args.length > 0 ? args[0] : "Cache/video/Custom_Sprites.osar";
		String outputPath = args.length > 1 ? args[1] : "Vector_Sprites_All.json";

		System.out.println("=== Raster to Vector Sprite Converter ===");
		System.out.println("Input:  " + inputPath);
		System.out.println("Output: " + outputPath);

		File inputFile = new File(inputPath);
		if (!inputFile.exists()) {
			System.err.println("ERROR: Input file not found: " + inputPath);
			System.exit(1);
		}

		Unpacker unpacker = new Unpacker();
		Workspace workspace = unpacker.unpackArchive(inputFile);

		if (workspace == null) {
			System.err.println("ERROR: Failed to unpack archive");
			System.exit(1);
		}

		System.out.println("Archive:    " + workspace.getName());
		System.out.println("Subspaces:  " + workspace.getSubspaceCount());
		System.out.println("Entries:    " + workspace.getEntryCount());
		System.out.println("Sprites:    " + workspace.getSpriteCount());
		System.out.println("Animations: " + workspace.getAnimationCount());
		System.out.println();

		int totalEntries = 0;
		int totalFrames = 0;
		int totalShapes = 0;

		try (PrintWriter out = new PrintWriter(new BufferedWriter(new FileWriter(outputPath), 1 << 20))) {
			out.println("{");
			out.println("  \"version\": 1,");
			out.println("  \"sprites\": [");

			boolean firstEntry = true;

			for (Subspace subspace : workspace.getSubspaces()) {
				String subName = subspace.getName();
				System.out.println("Converting subspace: " + subName
					+ " (" + subspace.getEntryCount() + " entries)");

				for (Entry entry : subspace.getEntryList()) {
					Frame[] frames = entry.getFrames();
					if (frames == null || frames.length == 0) continue;

					// Check for at least one valid frame
					boolean hasValid = false;
					for (Frame f : frames) {
						if (f != null && f.getPixels() != null && f.getWidth() > 0) {
							hasValid = true;
							break;
						}
					}
					if (!hasValid) continue;

					if (!firstEntry) out.println(",");
					firstEntry = false;

					String entryType = switch (entry.getType()) {
						case SPRITE -> "SPRITE";
						case PLAYER_PART -> "PLAYER_PART";
						case PLAYER_EQUIPPABLE_HASCOMBAT -> "PLAYER_EQUIPPABLE_HASCOMBAT";
						case PLAYER_EQUIPPABLE_NOCOMBAT -> "PLAYER_EQUIPPABLE_NOCOMBAT";
						case NPC -> "NPC";
					};

					String layerName = entry.getLayer() != null ? entry.getLayer().name() : null;

					if (frames.length == 1 && frames[0] != null) {
						// Single-frame: use compact format
						int shapeCount = writeSingleFrame(out, entry.getID(), subName,
							entryType, layerName, frames[0]);
						totalShapes += shapeCount;
						totalFrames++;
					} else {
						// Multi-frame: use frames array
						int shapeCount = writeMultiFrame(out, entry.getID(), subName,
							entryType, layerName, frames);
						totalShapes += shapeCount;
						for (Frame f : frames) {
							if (f != null) totalFrames++;
						}
					}
					totalEntries++;
				}
			}

			out.println();
			out.println("  ]");
			out.println("}");
		}

		System.out.println();
		System.out.println("=== Conversion Complete ===");
		System.out.println("Entries converted: " + totalEntries);
		System.out.println("Frames converted:  " + totalFrames);
		System.out.println("Total shapes:      " + totalShapes);
		System.out.println("Output written to: " + outputPath);
	}

	/**
	 * Write a single-frame sprite definition (backward-compatible format).
	 * Returns the number of shapes generated.
	 */
	private static int writeSingleFrame(PrintWriter out, String id, String subspace,
										String entryType, String layerName, Frame frame) {
		FrameVector fv = convertFrame(frame);

		out.print("    {");
		out.print("\"id\": \"" + escapeJson(id) + "\", ");
		out.print("\"subspace\": \"" + escapeJson(subspace) + "\", ");
		out.print("\"entryType\": \"" + entryType + "\", ");
		if (layerName != null) {
			out.print("\"layer\": \"" + layerName + "\", ");
		}
		out.print("\"width\": " + frame.getWidth() + ", ");
		out.print("\"height\": " + frame.getHeight());

		if (frame.getUseShift()) {
			out.print(", \"requiresShift\": true");
			out.print(", \"xShift\": " + frame.getOffsetX());
			out.print(", \"yShift\": " + frame.getOffsetY());
		}
		if (frame.getBoundWidth() > 0) {
			out.print(", \"boundWidth\": " + frame.getBoundWidth());
		}
		if (frame.getBoundHeight() > 0) {
			out.print(", \"boundHeight\": " + frame.getBoundHeight());
		}

		out.print(", ");
		writePalette(out, fv.palette());
		out.print(", ");
		writeRects(out, fv.rects());
		out.print("}");

		return fv.rects().size();
	}

	/**
	 * Write a multi-frame sprite definition with frames array.
	 * Returns total number of shapes across all frames.
	 */
	private static int writeMultiFrame(PrintWriter out, String id, String subspace,
									   String entryType, String layerName, Frame[] frames) {
		out.print("    {");
		out.print("\"id\": \"" + escapeJson(id) + "\", ");
		out.print("\"subspace\": \"" + escapeJson(subspace) + "\", ");
		out.print("\"entryType\": \"" + entryType + "\"");
		if (layerName != null) {
			out.print(", \"layer\": \"" + layerName + "\"");
		}
		out.print(", \"frames\": [");

		int totalShapes = 0;
		boolean firstFrame = true;

		for (int fi = 0; fi < frames.length; fi++) {
			Frame frame = frames[fi];
			if (frame == null) {
				// Write a null placeholder to preserve frame indices
				if (!firstFrame) out.print(", ");
				firstFrame = false;
				out.print("null");
				continue;
			}

			if (!firstFrame) out.print(", ");
			firstFrame = false;

			FrameVector fv = convertFrame(frame);
			totalShapes += fv.rects().size();

			out.print("{");
			out.print("\"width\": " + frame.getWidth() + ", ");
			out.print("\"height\": " + frame.getHeight());

			if (frame.getUseShift()) {
				out.print(", \"requiresShift\": true");
				out.print(", \"xShift\": " + frame.getOffsetX());
				out.print(", \"yShift\": " + frame.getOffsetY());
			}
			if (frame.getBoundWidth() > 0) {
				out.print(", \"boundWidth\": " + frame.getBoundWidth());
			}
			if (frame.getBoundHeight() > 0) {
				out.print(", \"boundHeight\": " + frame.getBoundHeight());
			}

			out.print(", ");
			writePalette(out, fv.palette());
			out.print(", ");
			writeRects(out, fv.rects());
			out.print("}");
		}

		out.print("]}");
		return totalShapes;
	}

	/**
	 * Convert a Frame's pixel data into vector palette + rect shapes.
	 */
	static FrameVector convertFrame(Frame frame) {
		int[] pixels = frame.getPixels();
		int w = frame.getWidth();
		int h = frame.getHeight();

		// Count color frequencies (skip transparent = 0)
		Map<Integer, Integer> colorFreq = new LinkedHashMap<>();
		for (int p : pixels) {
			if (p != 0) {
				colorFreq.merge(p, 1, Integer::sum);
			}
		}

		if (colorFreq.isEmpty()) {
			return new FrameVector(new ArrayList<>(), new ArrayList<>());
		}

		// Sort colors by frequency (most common first for better compression)
		List<Map.Entry<Integer, Integer>> sorted = new ArrayList<>(colorFreq.entrySet());
		sorted.sort((a, b) -> b.getValue() - a.getValue());

		// Build palette: color int -> index, ordered hex list
		Map<Integer, Integer> colorToIndex = new LinkedHashMap<>();
		List<String> paletteList = new ArrayList<>();
		int ci = 0;
		for (var entry : sorted) {
			colorToIndex.put(entry.getKey(), ci++);
			paletteList.add(String.format("#%06X", entry.getKey() & 0xFFFFFF));
		}

		// Decompose each color layer into maximal rectangles
		// Compact format: [x, y, w, h, paletteIndex]
		List<int[]> compactRects = new ArrayList<>();
		for (var entry : sorted) {
			int color = entry.getKey();
			int palIdx = colorToIndex.get(color);
			List<int[]> rects = decomposeToRects(pixels, w, h, color);
			for (int[] rect : rects) {
				compactRects.add(new int[]{rect[0], rect[1], rect[2], rect[3], palIdx});
			}
		}

		return new FrameVector(paletteList, compactRects);
	}

	/**
	 * Greedy maximal-rectangle decomposition for a single color.
	 * Scans left-to-right, top-to-bottom. For each unvisited pixel of the
	 * target color, expands right as far as possible, then expands down
	 * as far as possible while maintaining the full width.
	 *
	 * Returns list of [x, y, width, height] arrays.
	 */
	static List<int[]> decomposeToRects(int[] pixels, int w, int h, int color) {
		boolean[] visited = new boolean[pixels.length];
		List<int[]> rects = new ArrayList<>();

		for (int y = 0; y < h; y++) {
			for (int x = 0; x < w; x++) {
				int idx = y * w + x;
				if (pixels[idx] != color || visited[idx]) continue;

				// Expand right
				int rw = 0;
				while (x + rw < w) {
					int ci = y * w + x + rw;
					if (pixels[ci] != color || visited[ci]) break;
					rw++;
				}

				// Expand down, maintaining full width
				int rh = 1;
				expandDown:
				while (y + rh < h) {
					for (int dx = 0; dx < rw; dx++) {
						int ci = (y + rh) * w + x + dx;
						if (pixels[ci] != color || visited[ci]) break expandDown;
					}
					rh++;
				}

				// Mark visited
				for (int dy = 0; dy < rh; dy++) {
					for (int dx = 0; dx < rw; dx++) {
						visited[(y + dy) * w + x + dx] = true;
					}
				}

				rects.add(new int[]{x, y, rw, rh});
			}
		}
		return rects;
	}

	// --- JSON writing helpers ---

	private static void writePalette(PrintWriter out, List<String> palette) {
		out.print("\"palette\": [");
		for (int i = 0; i < palette.size(); i++) {
			if (i > 0) out.print(", ");
			out.print("\"" + palette.get(i) + "\"");
		}
		out.print("]");
	}

	private static void writeRects(PrintWriter out, List<int[]> rects) {
		out.print("\"rects\": [");
		for (int i = 0; i < rects.size(); i++) {
			if (i > 0) out.print(",");
			int[] r = rects.get(i);
			out.print("[" + r[0] + "," + r[1] + "," + r[2] + "," + r[3] + "," + r[4] + "]");
		}
		out.print("]");
	}

	private static String escapeJson(String s) {
		if (s == null) return "";
		return s.replace("\\", "\\\\")
			.replace("\"", "\\\"")
			.replace("\n", "\\n")
			.replace("\r", "\\r")
			.replace("\t", "\\t");
	}

	// --- Data records ---

	record FrameVector(List<String> palette, List<int[]> rects) {}
}
