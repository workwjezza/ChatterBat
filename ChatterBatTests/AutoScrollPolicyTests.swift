import XCTest
@testable import ChatterBat

final class AutoScrollPolicyTests: XCTestCase {
    func testDefaultsToFollowingNewContent() {
        let policy = AutoScrollPolicy()
        XCTAssertTrue(policy.shouldAutoScrollToNewContent)
    }

    func testScrollingAwayFromBottomStopsFollowing() {
        var policy = AutoScrollPolicy()
        policy.userDidScroll(atBottom: false)
        XCTAssertFalse(policy.shouldAutoScrollToNewContent)
    }

    func testScrollingBackToBottomResumesFollowing() {
        var policy = AutoScrollPolicy()
        policy.userDidScroll(atBottom: false)
        policy.userDidScroll(atBottom: true)
        XCTAssertTrue(policy.shouldAutoScrollToNewContent)
    }

    func testResetRestoresFollowingRegardlessOfPriorState() {
        var policy = AutoScrollPolicy()
        policy.userDidScroll(atBottom: false)
        policy.reset()
        XCTAssertTrue(policy.shouldAutoScrollToNewContent)
    }
}
