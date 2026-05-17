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

        func pane(_ id: UInt64, _ windows: [Int], activeIndex: Int = 0) -> Pane<Int> {
            Pane(id: PaneID(id), windows: windows, activeIndex: activeIndex)
        }

        do {
            var panes = [pane(1, [1]), pane(2, [2, 3])]
            let loc = PaneLocation(paneIndex: 0, windowIndex: 0)
            let target = PaneOperations.focusOffset(in: &panes, from: loc, offset: 1)
            check(target == PaneLocation(paneIndex: 1, windowIndex: 0), "focus enters next pane first tab")
            check(panes[1].activeWindow == 2, "focus next activates first grouped tab")

            let target2 = PaneOperations.focusOffset(in: &panes, from: target!, offset: 1)
            check(target2 == PaneLocation(paneIndex: 1, windowIndex: 1), "focus cycles inside grouped pane")
            check(panes[1].activeWindow == 3, "focus inside group updates active window identity")

            let target3 = PaneOperations.focusOffset(in: &panes, from: target2!, offset: 1)
            check(target3 == PaneLocation(paneIndex: 0, windowIndex: 0), "focus wraps back to first pane")
            check(panes[0].activeWindow == 1, "focus wrap activates single pane")
        }

        do {
            let panes = [
                pane(1, [1]),
                pane(2, [2]),
                pane(3, [3]),
                pane(4, [4]),
                pane(5, [5]),
                pane(6, [6]),
            ]
            let target = PaneOperations.focusLeft(
                in: panes,
                from: PaneLocation(paneIndex: 5, windowIndex: 0)
            )
            check(target == PaneLocation(paneIndex: 0, windowIndex: 0), "focus left jumps from bottom stack pane to master")

            let remembered = PaneOperations.focusRight(
                in: panes,
                from: PaneLocation(paneIndex: 0, windowIndex: 0),
                rememberedStackPaneID: PaneID(6)
            )
            check(remembered == PaneLocation(paneIndex: 5, windowIndex: 0), "focus right returns to remembered stack pane")

            let defaultRight = PaneOperations.focusRight(
                in: panes,
                from: PaneLocation(paneIndex: 0, windowIndex: 0),
                rememberedStackPaneID: nil
            )
            check(defaultRight == PaneLocation(paneIndex: 1, windowIndex: 0), "focus right falls back to first stack pane")
        }

        do {
            var panes = [pane(1, [1]), pane(2, [2]), pane(3, [3])]
            let target = PaneOperations.groupFocused(
                in: &panes,
                from: PaneLocation(paneIndex: 2, windowIndex: 0),
                offset: -1
            )
            check(panes.map(\.windows) == [[1], [2, 3]], "group previous appends active tab")
            check(panes[1].activeWindow == 3, "group previous focuses moved tab by identity")
            check(target == PaneLocation(paneIndex: 1, windowIndex: 1), "group previous reports moved tab")
        }

        do {
            var panes = [pane(1, [1]), pane(2, [2]), pane(3, [3])]
            let target = PaneOperations.groupFocused(
                in: &panes,
                from: PaneLocation(paneIndex: 1, windowIndex: 0),
                offset: 1
            )
            check(panes.map(\.windows) == [[1], [2, 3]], "group next prepends active tab")
            check(panes[1].activeWindow == 2, "group next focuses moved tab by identity")
            check(target == PaneLocation(paneIndex: 1, windowIndex: 0), "group next reports moved tab")
        }

        do {
            var panes = [pane(1, [1]), pane(2, [2, 3], activeIndex: 1), pane(3, [4])]
            let target = PaneOperations.groupFocused(
                in: &panes,
                from: PaneLocation(paneIndex: 1, windowIndex: 1),
                offset: 1
            )
            check(panes.map(\.windows) == [[1], [2], [3, 4]], "group from grouped source moves only active tab")
            check(panes[2].activeWindow == 3, "target group focuses moved active tab")
            check(target == PaneLocation(paneIndex: 2, windowIndex: 0), "group from grouped source reports target")
        }

        do {
            var panes = [pane(1, [1]), pane(2, [2, 3], activeIndex: 1)]
            let target = PaneOperations.expelFocused(
                from: &panes,
                location: PaneLocation(paneIndex: 1, windowIndex: 1),
                offset: 1
            )
            check(panes.map(\.windows) == [[1], [2], [3]], "expel after creates new pane")
            check(panes[2].activeWindow == 3, "expelled pane keeps moved tab active")
            check(target == PaneLocation(paneIndex: 2, windowIndex: 0), "expel after focuses new pane")
        }

        do {
            var panes = [pane(1, [1]), pane(2, [2, 3, 4], activeIndex: 1)]
            let target = PaneOperations.moveFocused(
                in: &panes,
                from: PaneLocation(paneIndex: 1, windowIndex: 1),
                offset: 1
            )
            check(panes[1].windows == [2, 4, 3], "move focused reorders tabs inside group")
            check(panes[1].activeWindow == 3, "move focused preserves active tab identity")
            check(target == PaneLocation(paneIndex: 1, windowIndex: 2), "move focused reports tab target")
        }

        do {
            var panes = [pane(1, [1]), pane(2, [2, 3], activeIndex: 1)]
            let target = PaneOperations.moveFocused(
                in: &panes,
                from: PaneLocation(paneIndex: 1, windowIndex: 1),
                offset: 1
            )
            check(panes[1].windows == [2, 3], "move focused does not wrap grouped tabs")
            check(panes[1].activeWindow == 3, "failed move keeps active tab")
            check(target == PaneLocation(paneIndex: 1, windowIndex: 1), "failed move reports unchanged location")
        }

        do {
            var panes = [pane(1, [1]), pane(2, [2]), pane(3, [3])]
            let target = PaneOperations.moveFocused(
                in: &panes,
                from: PaneLocation(paneIndex: 1, windowIndex: 0),
                offset: 1
            )
            check(panes.map(\.windows) == [[1], [3], [2]], "move focused reorders panes for ungrouped pane")
            check(panes[2].id == PaneID(2), "moving pane preserves pane identity")
            check(target == PaneLocation(paneIndex: 2, windowIndex: 0), "move focused reports pane target")
        }

        do {
            var panes = [pane(1, [1]), pane(2, [2]), pane(3, [3])]
            let target = PaneOperations.moveFocused(
                in: &panes,
                from: PaneLocation(paneIndex: 2, windowIndex: 0),
                offset: 1
            )
            check(panes.map(\.windows) == [[1], [2], [3]], "move focused does not wrap panes")
            check(target == PaneLocation(paneIndex: 2, windowIndex: 0), "failed pane move reports unchanged location")
        }

        do {
            var pane = pane(1, [1, 2, 3], activeIndex: 2)
            pane.removeAll { $0 == 3 }
            check(pane.windows == [1, 2], "removal deletes matching tab")
            check(pane.activeWindow == 2, "removal clamps active window by identity")
            pane.removeAll { _ in true }
            check(pane.windows.isEmpty, "empty removal removes all windows")
            check(pane.activeWindow == nil, "empty removal clears active window")
        }

        return (passed, failed)
    }
}
