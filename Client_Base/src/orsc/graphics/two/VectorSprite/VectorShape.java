package orsc.graphics.two.VectorSprite;

/**
 * Sealed interface representing vector shape primitives.
 * All coordinates are integers for pixel-grid alignment.
 */
public sealed interface VectorShape
	permits VectorShape.Rect, VectorShape.Polygon, VectorShape.Circle,
		VectorShape.Ellipse, VectorShape.Line, VectorShape.Path {

	record Rect(int x, int y, int w, int h,
				String fill, String stroke, int strokeWidth) implements VectorShape {}

	record Polygon(int[] xPoints, int[] yPoints,
				   String fill, String stroke, int strokeWidth) implements VectorShape {}

	record Circle(int cx, int cy, int r,
				  String fill, String stroke, int strokeWidth) implements VectorShape {}

	record Ellipse(int cx, int cy, int rx, int ry,
				   String fill, String stroke, int strokeWidth) implements VectorShape {}

	record Line(int x1, int y1, int x2, int y2,
				String stroke, int strokeWidth) implements VectorShape {}

	record Path(PathCommand[] commands,
				String fill, String stroke, int strokeWidth) implements VectorShape {}

	/**
	 * Path drawing commands for complex shapes.
	 */
	sealed interface PathCommand
		permits PathCommand.MoveTo, PathCommand.LineTo,
			PathCommand.QuadTo, PathCommand.CurveTo, PathCommand.Close {

		record MoveTo(int x, int y) implements PathCommand {}
		record LineTo(int x, int y) implements PathCommand {}
		record QuadTo(int cx, int cy, int x, int y) implements PathCommand {}
		record CurveTo(int cx1, int cy1, int cx2, int cy2, int x, int y) implements PathCommand {}
		record Close() implements PathCommand {}
	}
}
