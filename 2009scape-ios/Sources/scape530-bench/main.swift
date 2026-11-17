import Foundation
import Scape530

// scape530-bench: release-mode render benchmark.
//
//   swift run -c release scape530-bench <cache-dir> <session.bin> [frames] [WxH ...]
//
// <session.bin> is Tests/Scape530Tests/Fixtures/resizable-session.bin (a recorded login into a real region).

let args = CommandLine.arguments
guard args.count >= 3 else {
	print("usage: scape530-bench <cache-dir> <session.bin> [frames] [WxH ...]")
	exit(2)
}
let frames = args.count > 3 ? Int(args[3]) ?? 100 : 100
var sizes: [(Int, Int)] = [(765, 503), (1600, 740)]
if args.count > 4 {
	sizes = args[4...].compactMap { s in
		let p = s.split(separator: "x").compactMap { Int($0) }
		return p.count == 2 ? (p[0], p[1]) : nil
	}
}
do {
	for (w, h) in sizes {
		let client = try RenderBench.makeClient(cache: args[1], session: args[2])
		print("scene: \(RenderBench.describe(client))")
		let r = try RenderBench.run(client: client, width: w, height: h, frames: frames)
		print("\n== \(w)x\(h), \(frames) frames (checksum \(String(r.checksum, radix: 16))) ==")
		for row in r.rows { print(String(format: "%-40@ %8.3f ms", row.label as NSString, row.msPerFrame)) }
	}
} catch {
	print("error: \(error)")
	exit(1)
}
