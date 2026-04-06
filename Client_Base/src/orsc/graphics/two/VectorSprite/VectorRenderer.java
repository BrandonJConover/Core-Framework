package orsc.graphics.two.VectorSprite;

import orsc.graphics.two.SpriteArchive.Entry;
import orsc.graphics.two.SpriteArchive.Frame;

import java.awt.*;
import java.awt.geom.Ellipse2D;
import java.awt.geom.GeneralPath;
import java.awt.image.BufferedImage;
import java.awt.image.DataBufferInt;
import java.util.Comparator;
import java.util.List;

/**
 * Rasterizes VectorDefinition objects into standard Frame/Entry objects
 * compatible with the existing rendering pipeline.
 *
 * Uses Java2D Graphics2D with anti-aliasing disabled and integer coordinates
 * to preserve the pixel-art aesthetic of RuneScape Classic.
 */
public class VectorRenderer {

	/**
	 * Rasterize a VectorDefinition and write pixels into a Frame.
	 * The Frame's internal pixel array (shared with its Sprite) is populated directly.
	 */
	public static Frame renderToFrame(VectorDefinition def) {
		Frame frame = new Frame(
			def.getWidth(), def.getHeight(),
			def.isRequiresShift(),
			def.getXShift(), def.getYShift(),
			def.getBoundWidth(), def.getBoundHeight()
		);

		BufferedImage image = new BufferedImage(
			def.getWidth(), def.getHeight(), BufferedImage.TYPE_INT_ARGB);
		Graphics2D g = image.createGraphics();

		// Pixel-art settings: no anti-aliasing, pure stroke control
		g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_OFF);
		g.setRenderingHint(RenderingHints.KEY_STROKE_CONTROL, RenderingHints.VALUE_STROKE_PURE);
		g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_SPEED);

		// Start with fully transparent
		g.setComposite(AlphaComposite.Clear);
		g.fillRect(0, 0, def.getWidth(), def.getHeight());
		g.setComposite(AlphaComposite.SrcOver);

		// Render each shape in painter's order
		for (VectorShape shape : def.getShapes()) {
			renderShape(g, shape, def.getPalette());
		}

		g.dispose();

		// Extract rendered pixels and convert to RSC format
		// In RSC: pixel value 0 = transparent, non-zero = opaque RGB
		int[] rendered = ((DataBufferInt) image.getRaster().getDataBuffer()).getData();
		int[] framePixels = frame.getPixels();
		for (int i = 0; i < rendered.length && i < framePixels.length; i++) {
			int alpha = (rendered[i] >> 24) & 0xFF;
			if (alpha < 128) {
				framePixels[i] = 0; // Transparent in RSC
			} else {
				int rgb = rendered[i] & 0x00FFFFFF;
				framePixels[i] = rgb == 0 ? 1 : rgb; // Avoid 0 = transparent for black
			}
		}

		return frame;
	}

	/**
	 * Convert a single VectorDefinition into a single-frame Entry.
	 */
	public static Entry toEntry(VectorDefinition def) {
		Entry.TYPE type = resolveEntryType(def.getEntryTypeName());
		Frame.LAYER layer = resolveLayer(def.getLayerName(), type);

		var entry = new Entry(def.getId(), type, layer, 1);
		entry.getFrames()[0] = renderToFrame(def);
		return entry;
	}

	/**
	 * Convert multiple VectorDefinitions (sharing the same id) into a multi-frame Entry.
	 * Definitions must be sorted by frameIndex.
	 */
	public static Entry toMultiFrameEntry(List<VectorDefinition> frameDefs) {
		if (frameDefs.isEmpty()) return null;

		VectorDefinition first = frameDefs.get(0);
		int totalFrames = first.getTotalFrames();
		Entry.TYPE type = resolveEntryType(first.getEntryTypeName());
		Frame.LAYER layer = resolveLayer(first.getLayerName(), type);

		var entry = new Entry(first.getId(), type, layer, totalFrames);

		for (VectorDefinition def : frameDefs) {
			int fi = def.getFrameIndex();
			if (fi >= 0 && fi < totalFrames) {
				entry.getFrames()[fi] = renderToFrame(def);
			}
		}

		return entry;
	}

	private static Entry.TYPE resolveEntryType(String name) {
		if (name == null) return Entry.TYPE.SPRITE;
		return switch (name) {
			case "NPC" -> Entry.TYPE.NPC;
			case "PLAYER_PART" -> Entry.TYPE.PLAYER_PART;
			case "PLAYER_EQUIPPABLE_HASCOMBAT" -> Entry.TYPE.PLAYER_EQUIPPABLE_HASCOMBAT;
			case "PLAYER_EQUIPPABLE_NOCOMBAT" -> Entry.TYPE.PLAYER_EQUIPPABLE_NOCOMBAT;
			default -> Entry.TYPE.SPRITE;
		};
	}

	private static Frame.LAYER resolveLayer(String name, Entry.TYPE type) {
		if (name == null || type.getLayers().length == 0) return null;
		try {
			return Frame.LAYER.valueOf(name);
		} catch (IllegalArgumentException e) {
			return type.getLayers().length > 0 ? type.getLayers()[0] : null;
		}
	}

	private static void renderShape(Graphics2D g, VectorShape shape, VectorPalette palette) {
		if (shape instanceof VectorShape.Rect r) {
			renderRect(g, r, palette);
		} else if (shape instanceof VectorShape.Polygon p) {
			renderPolygon(g, p, palette);
		} else if (shape instanceof VectorShape.Circle c) {
			renderCircle(g, c, palette);
		} else if (shape instanceof VectorShape.Ellipse e) {
			renderEllipse(g, e, palette);
		} else if (shape instanceof VectorShape.Line l) {
			renderLine(g, l, palette);
		} else if (shape instanceof VectorShape.Path p) {
			renderPath(g, p, palette);
		}
	}

	private static void renderRect(Graphics2D g, VectorShape.Rect r, VectorPalette palette) {
		if (r.fill() != null) {
			g.setColor(toColor(palette, r.fill()));
			g.fillRect(r.x(), r.y(), r.w(), r.h());
		}
		if (r.stroke() != null) {
			g.setColor(toColor(palette, r.stroke()));
			g.setStroke(pixelStroke(r.strokeWidth()));
			g.drawRect(r.x(), r.y(), r.w(), r.h());
		}
	}

	private static void renderPolygon(Graphics2D g, VectorShape.Polygon p, VectorPalette palette) {
		int nPoints = Math.min(p.xPoints().length, p.yPoints().length);
		var poly = new java.awt.Polygon(p.xPoints(), p.yPoints(), nPoints);

		if (p.fill() != null) {
			g.setColor(toColor(palette, p.fill()));
			g.fillPolygon(poly);
		}
		if (p.stroke() != null) {
			g.setColor(toColor(palette, p.stroke()));
			g.setStroke(pixelStroke(p.strokeWidth()));
			g.drawPolygon(poly);
		}
	}

	private static void renderCircle(Graphics2D g, VectorShape.Circle c, VectorPalette palette) {
		int x = c.cx() - c.r();
		int y = c.cy() - c.r();
		int d = c.r() * 2;

		if (c.fill() != null) {
			g.setColor(toColor(palette, c.fill()));
			g.fillOval(x, y, d, d);
		}
		if (c.stroke() != null) {
			g.setColor(toColor(palette, c.stroke()));
			g.setStroke(pixelStroke(c.strokeWidth()));
			g.drawOval(x, y, d, d);
		}
	}

	private static void renderEllipse(Graphics2D g, VectorShape.Ellipse e, VectorPalette palette) {
		var ellipse = new Ellipse2D.Double(
			e.cx() - e.rx(), e.cy() - e.ry(),
			e.rx() * 2.0, e.ry() * 2.0
		);

		if (e.fill() != null) {
			g.setColor(toColor(palette, e.fill()));
			g.fill(ellipse);
		}
		if (e.stroke() != null) {
			g.setColor(toColor(palette, e.stroke()));
			g.setStroke(pixelStroke(e.strokeWidth()));
			g.draw(ellipse);
		}
	}

	private static void renderLine(Graphics2D g, VectorShape.Line l, VectorPalette palette) {
		if (l.stroke() != null) {
			g.setColor(toColor(palette, l.stroke()));
			g.setStroke(pixelStroke(l.strokeWidth()));
			g.drawLine(l.x1(), l.y1(), l.x2(), l.y2());
		}
	}

	private static void renderPath(Graphics2D g, VectorShape.Path p, VectorPalette palette) {
		var path = new GeneralPath();

		for (VectorShape.PathCommand cmd : p.commands()) {
			if (cmd instanceof VectorShape.PathCommand.MoveTo m) {
				path.moveTo(m.x(), m.y());
			} else if (cmd instanceof VectorShape.PathCommand.LineTo l) {
				path.lineTo(l.x(), l.y());
			} else if (cmd instanceof VectorShape.PathCommand.QuadTo q) {
				path.quadTo(q.cx(), q.cy(), q.x(), q.y());
			} else if (cmd instanceof VectorShape.PathCommand.CurveTo c) {
				path.curveTo(c.cx1(), c.cy1(), c.cx2(), c.cy2(), c.x(), c.y());
			} else if (cmd instanceof VectorShape.PathCommand.Close) {
				path.closePath();
			}
		}

		if (p.fill() != null) {
			g.setColor(toColor(palette, p.fill()));
			g.fill(path);
		}
		if (p.stroke() != null) {
			g.setColor(toColor(palette, p.stroke()));
			g.setStroke(pixelStroke(p.strokeWidth()));
			g.draw(path);
		}
	}

	/**
	 * Resolve a color name through the palette, or parse as hex if not found.
	 */
	private static Color toColor(VectorPalette palette, String name) {
		if (palette.hasColor(name)) {
			return new Color(palette.getColor(name), true);
		}
		if (name.startsWith("#")) {
			return new Color(VectorPalette.parseHex(name), true);
		}
		return Color.BLACK;
	}

	/**
	 * Create a BasicStroke with square caps and miter joins for pixel-crisp edges.
	 */
	private static BasicStroke pixelStroke(int width) {
		return new BasicStroke(width, BasicStroke.CAP_SQUARE, BasicStroke.JOIN_MITER);
	}
}
