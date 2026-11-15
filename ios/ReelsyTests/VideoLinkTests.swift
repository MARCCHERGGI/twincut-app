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

    func testVideoAppsAndTheirVideoServersAreNeverFetched() throws {
        for text in ["https://v16-webapp.tiktokcdn.com/x/clip.mp4", "https://scontent.cdninstagram.com/v/a.mp4",
                     "https://video.fbcdn.net/b.mp4", "https://rr3---sn-abc.googlevideo.com/videoplayback",
                     "https://video.twimg.com/c.mp4", "https://player.vimeo.com/d.mp4", "https://www.tiktok.com/@a/video/1"] {
            XCTAssertNotNil(try XCTUnwrap(VideoLink(text: text)).platform, text)
        }
        XCTAssertNil(try XCTUnwrap(VideoLink(text: "https://twincut.pages.dev/test/sample-reel.mp4")).platform)
        XCTAssertNil(try XCTUnwrap(VideoLink(text: "https://notyoutube.com/a.mp4")).platform, "only the app's own domains")
        XCTAssertEqual(VideoLink(text: "https://v16.tiktokcdn.com/a.mp4")?.siteName, "TikTok")
        // Redirect targets are checked the same way, so a short link can't lead to a video app's file.
        XCTAssertEqual(VideoLink.platform(of: URL(string: "https://scontent-lga3-1.cdninstagram.com/o1/v/x.mp4")!), "Instagram")
        XCTAssertNil(VideoLink.platform(of: URL(string: "https://dl.dropboxusercontent.com/s/abc/take.mp4")!))
        XCTAssertEqual(VideoLink.platform(of: URL(string: "https://www.youtube.com./watch?v=1")!), "YouTube", "trailing dot")
    }

    func testRedirectOntoAVideoAppIsStopped() async throws {
        let task = URLSession.shared.dataTask(with: URL(string: "https://bit.ly/x")!)
        let moved = try XCTUnwrap(HTTPURLResponse(url: URL(string: "https://bit.ly/x")!, statusCode: 302, httpVersion: nil, headerFields: nil))

        let guardA = LinkDownloader.RedirectGuard()
        let toTikTok = URLRequest(url: URL(string: "https://v16-webapp.tiktokcdn.com/v/clip.mp4")!)
        let stopped = await guardA.urlSession(.shared, task: task, willPerformHTTPRedirection: moved, newRequest: toTikTok)
        XCTAssertNil(stopped)
        XCTAssertTrue(guardA.blocked)

        let guardB = LinkDownloader.RedirectGuard()
        let toDrive = URLRequest(url: URL(string: "https://dl.dropboxusercontent.com/s/abc/take.mp4")!)
        let followed = await guardB.urlSession(.shared, task: task, willPerformHTTPRedirection: moved, newRequest: toDrive)
        XCTAssertEqual(followed?.url, toDrive.url)
        XCTAssertFalse(guardB.blocked)
    }

    func testVideoFileAddresses() throws {
        XCTAssertTrue(try XCTUnwrap(VideoLink(text: "https://cdn.example.com/a/B.MP4")).namesVideoFile)
        XCTAssertTrue(try XCTUnwrap(VideoLink(text: "https://example.com/take.mov?dl=1")).namesVideoFile)
        XCTAssertFalse(try XCTUnwrap(VideoLink(text: "https://example.com/watch?v=1")).namesVideoFile)
    }
}
