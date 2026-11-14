import XCTest

/// The whole first-run path a reviewer takes: welcome, a starter template, the bundled
/// sample clips, the editor, a real export. Screenshots are kept for the App Store listing.
final class ReelsyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-reset"]
        app.launch()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFirstReelWithSampleClips() throws {
        let next = app.buttons["onboarding-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        shot("01-welcome")
        next.tap()
        next.tap()
        next.tap()

        let starter = app.buttons["starter-card-0"]
        XCTAssertTrue(starter.waitForExistence(timeout: 10))
        sleep(1)
        shot("02-home")
        starter.tap()

        let samples = app.buttons["use-samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 10))
        let count = app.staticTexts["clip-count"]
        let before = count.label
        app.buttons["clip-count-minus"].tap()
        XCTAssertNotEqual(count.label, before, "clip count changes")
        app.buttons["clip-count-plus"].tap()
        XCTAssertEqual(count.label, before)
        sleep(1)  // let the counter's number transition settle before the store screenshot
        shot("03-template")
        samples.tap()

        let export = app.buttons["export-button"]
        XCTAssertTrue(export.waitForExistence(timeout: 60))
        sleep(3)
        shot("04-editor")

        app.buttons["Text"].tap()
        sleep(1)
        shot("05-text")

        export.tap()
        sleep(2)
        shot("05b-export-tapped")
        let done = app.buttons["done-button"]
        // The simulator renders Core Image in software on CI: 600 s reached 81% on one runner.
        XCTAssertTrue(done.waitForExistence(timeout: 1200), "export finishes")
        XCTAssertTrue(app.buttons["save-button"].exists)
        sleep(2)
        shot("06-export")
        done.tap()
        let leave = app.buttons["Leave without saving"]
        XCTAssertTrue(leave.waitForExistence(timeout: 5), "Done asks before discarding an unsaved reel")
        leave.tap()

        XCTAssertTrue(app.buttons["choose-reel"].waitForExistence(timeout: 10), "back home")
    }

    /// The core feature with nothing saved on the phone: copy the bundled reel, play it on Twincut's beat.
    func testCopySampleReel() throws {
        let next = app.buttons["onboarding-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap()
        next.tap()
        next.tap()

        let sample = app.buttons["sample-reel"]
        XCTAssertTrue(sample.waitForExistence(timeout: 10))
        sample.tap()

        let samples = app.buttons["use-samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 180), "analysis finishes and opens the template")
        XCTAssertTrue(app.staticTexts["8 shots"].exists, "all 8 cuts of the sample found")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", " BPM")).firstMatch.exists, "tempo found")
        sleep(1)
        shot("08-sample-template")
        samples.tap()

        XCTAssertTrue(app.buttons["export-button"].waitForExistence(timeout: 180), "the editor opens with the sample clips")
        app.buttons["Sound"].tap()
        XCTAssertTrue(app.buttons["Beat"].waitForExistence(timeout: 5), "Twincut's beat is offered")
        XCTAssertTrue(app.buttons["Beat"].isSelected, "and is the default")
        XCTAssertFalse(app.buttons["Reel's audio"].exists, "the copied reel's audio is never offered")
        sleep(1)
        shot("09-sample-sound")
    }

    /// Templated apps fall apart at large text and on small screens; walk every screen there.
    /// Each key control must stay on screen and tappable. Screenshots are for a visual check.
    func testLayoutAtLargestText() throws {
        app.terminate()
        app.launchArguments = ["-uitest-reset", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()

        let next = app.buttons["onboarding-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertTrue(next.isHittable, "onboarding button on screen")
        shot("L1-welcome")
        next.tap(); next.tap(); next.tap()

        let choose = app.buttons["choose-reel"]
        XCTAssertTrue(choose.waitForExistence(timeout: 10))
        XCTAssertTrue(choose.isHittable, "choose button on screen")
        shot("L2-home")

        app.buttons["sample-reel"].firstMatch.tap()
        let samples = app.buttons["use-samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 60))
        XCTAssertTrue(samples.isHittable, "sample clips button on screen")
        shot("L3-template")
        samples.tap()

        let export = app.buttons["export-button"]
        XCTAssertTrue(export.waitForExistence(timeout: 60))
        XCTAssertTrue(export.isHittable, "export button on screen")
        shot("L4-editor-clips")
        for tab in ["Text", "Sound"] {
            app.buttons[tab].tap()
            sleep(1)
            shot("L5-editor-\(tab.lowercased())")
        }
    }

    /// Apple's own accessibility audit (contrast, clipped text, Dynamic Type, hit regions, labels)
    /// on every screen of the reviewer's path. Collects every issue, then fails listing them all.
    func testAccessibilityAuditOnEveryScreen() throws {
        var issues: [String] = []
        func audit(_ screen: String) throws {
            sleep(2)  // let the push or tab animation finish
            try app.performAccessibilityAudit { issue in
                let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' id=\($0.identifier)" } ?? "no element"
                issues.append("\(screen): \(issue.compactDescription) [\(element)]")
                return true
            }
        }

        try audit("welcome")
        let next = app.buttons["onboarding-next"]
        next.tap(); next.tap(); next.tap()

        XCTAssertTrue(app.buttons["choose-reel"].waitForExistence(timeout: 10))
        try audit("home")

        app.buttons["sample-reel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["use-samples"].waitForExistence(timeout: 60))
        try audit("template")
        app.buttons["use-samples"].tap()

        XCTAssertTrue(app.buttons["export-button"].waitForExistence(timeout: 60))
        for tab in ["Clips", "Text", "Sound"] {
            app.buttons[tab].firstMatch.tap()
            try audit("editor-\(tab)")
        }
        XCTAssertTrue(issues.isEmpty, "\(issues.count) accessibility issues:\n" + issues.joined(separator: "\n"))
    }

    /// Leaving mid-export stops the render with a plain message, and Try again starts it over.
    func testLeavingDuringExportOffersTryAgain() throws {
        let next = app.buttons["onboarding-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap(); next.tap(); next.tap()
        app.buttons["starter-card-0"].tap()
        app.buttons["use-samples"].tap()
        let export = app.buttons["export-button"]
        XCTAssertTrue(export.waitForExistence(timeout: 60))
        export.tap()
        sleep(2)

        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(app.staticTexts["Export didn't finish"].waitForExistence(timeout: 10), "the render stops")
        app.buttons["Try again"].tap()
        XCTAssertTrue(app.staticTexts["Exporting in 1080p"].waitForExistence(timeout: 5), "and starts over")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(export.waitForExistence(timeout: 10), "back in the editor")
    }

    /// Cancel during analysis goes straight home, and the sample can be read again without a duplicate.
    func testCancelAnalysisThenReadSampleTwice() throws {
        let next = app.buttons["onboarding-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap(); next.tap(); next.tap()

        let sample = app.buttons["sample-reel"]
        XCTAssertTrue(sample.waitForExistence(timeout: 10))
        sample.tap()
        let photosStep = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Copying from Photos"))
        XCTAssertFalse(photosStep.firstMatch.exists, "no Photos step for the bundled sample")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(sample.waitForExistence(timeout: 10), "back home")

        for _ in 0..<2 {
            sample.tap()
            XCTAssertTrue(app.buttons["use-samples"].waitForExistence(timeout: 60))
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(sample.waitForExistence(timeout: 10))
        }
        app.swipeUp()  // "Your templates" is a lazy grid below the fold
        sleep(1)
        let saved = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Sample reel,"))
        XCTAssertEqual(saved.count, 1, "reading the sample twice keeps one template")
    }

    /// Links from any app: plain text gets a hint, a page link explains how to save the video,
    /// a direct video link is downloaded and read like any other video.
    func testPastedLinks() throws {
        let next = app.buttons["onboarding-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap(); next.tap(); next.tap()

        let field = app.textFields["link-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("great edit\n")
        XCTAssertTrue(app.staticTexts["That isn't a link. In any app, tap Share on the video, then Copy link."].waitForExistence(timeout: 5))

        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))  // the rejected text stays for editing
        field.typeText("https://www.youtube.com/shorts/abc123\n")
        let open = app.buttons["open-in-app"]
        XCTAssertTrue(open.waitForExistence(timeout: 20), "a page link opens the how-to sheet")
        let named = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Open the link in YouTube"))
        XCTAssertTrue(named.firstMatch.exists, "the sheet names where the link goes")
        sleep(1)
        shot("10-page-link")
        app.buttons["close-link-sheet"].tap()
        XCTAssertTrue(open.waitForNonExistence(timeout: 5), "the sheet closes")

        field.tap()
        field.typeText("https://twincut.pages.dev/test/sample-reel.mp4\n")
        XCTAssertTrue(app.buttons["use-samples"].waitForExistence(timeout: 120), "the linked video is downloaded and read")
        XCTAssertTrue(app.staticTexts["8 shots"].exists, "all 8 cuts of the linked video found")
    }

    /// Launch time as Apple defines it: tap to first frame, five launches.
    func testLaunchTime() throws {
        app.terminate()
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }

    func testSettingsOpenAndShowPolicyLinks() throws {
        let next = app.buttons["onboarding-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap(); next.tap(); next.tap()
        let settings = app.buttons["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.buttons["Privacy policy"].waitForExistence(timeout: 5) || app.links["Privacy policy"].exists)
        shot("07-settings")
    }
}
