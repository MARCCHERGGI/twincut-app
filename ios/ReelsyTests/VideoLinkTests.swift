import XCTest
@testable import Reelsy

final class VideoLinkTests: XCTestCase {
    func testFindsTheLinkInSharedText() throws {
        let link = try XCTUnwrap(VideoLink(text: "Look at this edit 🔥 https://www.tiktok.com/@someone/video/123?is_from_webapp=1 #fyp"))
        XCTAssertEqual(link.url.host(), "www.tiktok.com")
        XCTAssertEqual(link.siteName, "TikTok")
        XCTAssertFalse(link.namesVideoFile)
    }

    func testAnyAppOrSiteIsAccepted() throws {
        let cases = [
            ("https://youtu.be/abc", "YouTube"),
            ("https://m.youtube.com/shorts/abc", "YouTube"),
            ("https://www.instagram.com/reel/abc/", "Instagram"),
            ("https://x.com/a/status/1", "X"),
            ("https://www.facebook.com/reel/1", "Facebook"),
            ("https://pin.it/abc", "Pinterest"),
            ("https://www.example-studio.com/work/1", "example-studio.com"),
        ]
        for (text, name) in cases {
            XCTAssertEqual(VideoLink(text: text)?.siteName, name, text)
        }
    }

    func testBareAddressAndPlainHttpBecomeHttps() throws {
        XCTAssertEqual(VideoLink(text: "vimeo.com/123")?.url.absoluteString, "https://vimeo.com/123")
        XCTAssertEqual(VideoLink(text: "http://example.com/clip.mp4")?.url.absoluteString, "https://example.com/clip.mp4")
    }

    func testNonLinksAreRejected() {
        XCTAssertNil(VideoLink(text: ""))
        XCTAssertNil(VideoLink(text: "   "))
        XCTAssertNil(VideoLink(text: "great edit"))
        XCTAssertNil(VideoLink(text: "mailto:someone@example.com"))
    }

    func testVideoFileAddresses() throws {
        XCTAssertTrue(try XCTUnwrap(VideoLink(text: "https://cdn.example.com/a/B.MP4")).namesVideoFile)
        XCTAssertTrue(try XCTUnwrap(VideoLink(text: "https://example.com/take.mov?dl=1")).namesVideoFile)
        XCTAssertFalse(try XCTUnwrap(VideoLink(text: "https://example.com/watch?v=1")).namesVideoFile)
    }
}
