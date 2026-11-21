import Foundation

/// Port of rt4 `TitleScreen.load`: the backdrop drawn behind the login interface and the loading bar.
public enum TitleScreen {
	/// rt4 `TitleScreen.load`: sprite "titlebg" scaled to `canvasHeight * 956 / 503` wide and centred, then sprite
	/// "logo" centred horizontally at y = 18. Missing sprites draw nothing.
	public static func draw(store: ConfigStore, into r: inout Raster) {
		let height = r.height
		let width = height * 956 / 503
		if let bg = (try? store.sprite(named: "titlebg")) ?? nil, let f = bg.frames.first {
			r.drawScaled(f, x: (r.width - width) / 2, y: 0, w: width, h: height)
		}
		if let logo = (try? store.sprite(named: "logo")) ?? nil, let f = logo.frames.first {
			r.draw(f, x: r.width / 2 - f.width / 2, y: 18)
		}
	}
}
