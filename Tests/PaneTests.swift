import Foundation
@testable import ParketCore

enum PaneTests {
    static func runAll() -> (passed: Int, failed: Int) {
        var passed = 0
        var failed = 0

        func check(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
            if condition {
                passed += 1
            } else {
                fputs("FAIL \(file):\(line): \(message)\n", stderr)
                failed += 1
            }
        }

        do {
            var panes = [Pane(windows: [1]), Pane(windows: [2, 3])]
            let loc = PaneLocation(paneIndex: 0, windowIndex: 0)
            let target = PaneOperations.focusOffset(in: &panes, from: loc, offset: 1)
            check(target == PaneLocation(paneIndex: 1, windowIndex: 0), "focus enters next pane first tab")
            let target2 = PaneOperations.focusOffset(in: &panes, from: target!, offset: 1)
            check(target2 == PaneLocation(paneIndex: 1, windowIndex: 1), "focus cycles inside grouped pane")
            let target3 = PaneOperations.focusOffset(in: &panes, from: target2!, offset: 1)
            check(target3 == PaneLocation(paneIndex: 0, windowIndex: 0), "focus wraps back to first pane")
        }

        do {
            var panes = [Pane(windows: [1]), Pane(windows: [2]), Pane(windows: [3])]
            let target = PaneOperations.groupFocused(
                in: &panes,
                from: PaneLocation(paneIndex: 2, windowIndex: 0),
                offset: -1
            )
            check(panes == [Pane(windows: [1]), Pane(windows: [2, 3], activeIndex: 1)], "group previous appends source tab")
            check(target == PaneLocation(paneIndex: 1, windowIndex: 1), "group previous focuses moved tab")
        }

        do {
            var panes = [Pane(windows: [1]), Pane(windows: [2]), Pane(windows: [3])]
            let target = PaneOperations.groupFocused(
                in: &panes,
                from: PaneLocation(paneIndex: 1, windowIndex: 0),
                offset: 1
            )
            check(panes == [Pane(windows: [1]), Pane(windows: [2, 3], activeIndex: 0)], "group next prepends source tab")
            check(target == PaneLocation(paneIndex: 1, windowIndex: 0), "group next focuses moved tab")
        }

        do {
            var panes = [Pane(windows: [1]), Pane(windows: [2, 3], activeIndex: 1)]
            let target = PaneOperations.expelFocused(
                from: &panes,
                location: PaneLocation(paneIndex: 1, windowIndex: 1),
                offset: 1
            )
            check(panes == [Pane(windows: [1]), Pane(windows: [2]), Pane(windows: [3])], "expel after creates new pane")
            check(target == PaneLocation(paneIndex: 2, windowIndex: 0), "expel after focuses new pane")
        }

        do {
            var panes = [Pane(windows: [1]), Pane(windows: [2, 3, 4], activeIndex: 1)]
            let target = PaneOperations.moveFocused(
                in: &panes,
                from: PaneLocation(paneIndex: 1, windowIndex: 1),
                offset: 1
            )
            check(panes[1] == Pane(windows: [2, 4, 3], activeIndex: 2), "move focused reorders tabs inside group")
            check(target == PaneLocation(paneIndex: 1, windowIndex: 2), "move focused reports tab target")
        }

        do {
            var panes = [Pane(windows: [1]), Pane(windows: [2]), Pane(windows: [3])]
            let target = PaneOperations.moveFocused(
                in: &panes,
                from: PaneLocation(paneIndex: 1, windowIndex: 0),
                offset: 1
            )
            check(panes == [Pane(windows: [1]), Pane(windows: [3]), Pane(windows: [2])], "move focused reorders panes for ungrouped pane")
            check(target == PaneLocation(paneIndex: 2, windowIndex: 0), "move focused reports pane target")
        }

        do {
            var pane = Pane(windows: [1, 2, 3], activeIndex: 2)
            pane.removeAll { $0 == 3 }
            check(pane == Pane(windows: [1, 2], activeIndex: 1), "removal clamps active index")
            pane.removeAll { _ in true }
            check(pane == Pane<Int>(windows: []), "empty removal resets active index")
        }

        return (passed, failed)
    }
}
