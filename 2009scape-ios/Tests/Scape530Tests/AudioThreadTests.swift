import Foundation
import XCTest
@testable import Scape530

/// Songs load off the main thread in the app; this must work on a background thread's stack.
final class AudioThreadTests: XCTestCase {
	func testSongLoadsOnBackgroundThread() throws {
		guard let dir = ProcessInfo.processInfo.environment["SCAPE530_CACHE"] else { throw XCTSkip("needs SCAPE530_CACHE") }
		let store = ConfigStore(disk: try DiskCache(directory: URL(fileURLWithPath: dir)))
		let mixer = AudioMixer(store: store)
		let done = expectation(description: "loaded")
		DispatchQueue(label: "test.audio").async {
			for id in [62, 0, 1, 2, 3, 76, 150] { mixer.music.play(songId: id) }
			done.fulfill()
		}
		wait(for: [done], timeout: 300)
	}
}
