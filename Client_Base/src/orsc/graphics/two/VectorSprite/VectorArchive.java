package orsc.graphics.two.VectorSprite;

import orsc.graphics.two.SpriteArchive.Entry;

import java.io.*;
import java.util.*;
import java.util.zip.GZIPInputStream;

/**
 * Loads vector sprite definitions from a JSON archive file and produces
 * Entry objects compatible with the spriteTree structure.
 *
 * Supports both plain JSON (.json) and GZIP-compressed (.vspr) archives.
 * Handles single-frame and multi-frame entries (animations, NPCs, equipment).
 */
public class VectorArchive {

	/**
	 * Load vector sprite definitions from an archive file.
	 *
	 * @param archiveFile JSON or GZIP'd JSON archive
	 * @return Map matching spriteTree format: subspace -> (entryName -> Entry)
	 */
	public static Map<String, Map<String, Entry>> load(File archiveFile) {
		Map<String, Map<String, Entry>> result = new HashMap<>();

		if (!archiveFile.exists()) {
			return result;
		}

		try {
			InputStream in;
			if (archiveFile.getName().endsWith(".vspr")) {
				in = new GZIPInputStream(new FileInputStream(archiveFile));
			} else {
				in = new FileInputStream(archiveFile);
			}

			VectorJsonParser parser = new VectorJsonParser();
			List<VectorDefinition> defs = parser.parseArchive(in);
			in.close();

			// Group definitions by (subspace, id) for multi-frame support
			Map<String, Map<String, List<VectorDefinition>>> grouped = new LinkedHashMap<>();
			for (VectorDefinition def : defs) {
				grouped
					.computeIfAbsent(def.getSubspace(), k -> new LinkedHashMap<>())
					.computeIfAbsent(def.getId(), k -> new ArrayList<>())
					.add(def);
			}

			int singleCount = 0;
			int multiCount = 0;

			for (var subEntry : grouped.entrySet()) {
				String subspace = subEntry.getKey();
				result.computeIfAbsent(subspace, k -> new HashMap<>());

				for (var idEntry : subEntry.getValue().entrySet()) {
					String id = idEntry.getKey();
					List<VectorDefinition> frameDefs = idEntry.getValue();

					Entry entry;
					if (frameDefs.size() == 1 && frameDefs.get(0).getTotalFrames() <= 1) {
						// Single-frame entry
						entry = VectorRenderer.toEntry(frameDefs.get(0));
						singleCount++;
					} else {
						// Multi-frame entry: sort by frame index and render
						frameDefs.sort(Comparator.comparingInt(VectorDefinition::getFrameIndex));
						entry = VectorRenderer.toMultiFrameEntry(frameDefs);
						multiCount++;
					}

					if (entry != null) {
						result.get(subspace).put(id, entry);
					}
				}
			}

			System.out.println("Loaded " + singleCount + " sprites + "
				+ multiCount + " animations from " + archiveFile.getName());

		} catch (Exception e) {
			System.err.println("Error loading vector sprites: " + e.getMessage());
			e.printStackTrace();
		}

		return result;
	}
}
