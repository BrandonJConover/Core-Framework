package orsc.graphics.two.VectorSprite;

import java.util.ArrayList;
import java.util.List;

/**
 * Complete definition of a vector sprite including dimensions,
 * color palette, and ordered list of shapes.
 */
public class VectorDefinition {

	private String id;
	private String subspace;
	private int width;
	private int height;
	private boolean requiresShift;
	private int xShift;
	private int yShift;
	private int boundWidth;
	private int boundHeight;
	private VectorPalette palette;
	private final List<VectorShape> shapes = new ArrayList<VectorShape>();

	// Multi-frame and entry type support
	private int frameIndex;
	private int totalFrames = 1;
	private String entryTypeName = "SPRITE";
	private String layerName;

	public VectorDefinition(String id, String subspace, int width, int height) {
		this.id = id;
		this.subspace = subspace;
		this.width = width;
		this.height = height;
		this.palette = new VectorPalette();
	}

	public void addShape(VectorShape shape) {
		shapes.add(shape);
	}

	public String getId() { return id; }
	public String getSubspace() { return subspace; }
	public int getWidth() { return width; }
	public int getHeight() { return height; }
	public boolean isRequiresShift() { return requiresShift; }
	public int getXShift() { return xShift; }
	public int getYShift() { return yShift; }
	public int getBoundWidth() { return boundWidth; }
	public int getBoundHeight() { return boundHeight; }
	public VectorPalette getPalette() { return palette; }
	public List<VectorShape> getShapes() { return shapes; }

	public void setRequiresShift(boolean requiresShift) { this.requiresShift = requiresShift; }
	public void setXShift(int xShift) { this.xShift = xShift; }
	public void setYShift(int yShift) { this.yShift = yShift; }
	public void setBoundWidth(int boundWidth) { this.boundWidth = boundWidth; }
	public void setBoundHeight(int boundHeight) { this.boundHeight = boundHeight; }
	public void setPalette(VectorPalette palette) { this.palette = palette; }

	public int getFrameIndex() { return frameIndex; }
	public void setFrameIndex(int frameIndex) { this.frameIndex = frameIndex; }
	public int getTotalFrames() { return totalFrames; }
	public void setTotalFrames(int totalFrames) { this.totalFrames = totalFrames; }
	public String getEntryTypeName() { return entryTypeName; }
	public void setEntryTypeName(String entryTypeName) { this.entryTypeName = entryTypeName; }
	public String getLayerName() { return layerName; }
	public void setLayerName(String layerName) { this.layerName = layerName; }
}
