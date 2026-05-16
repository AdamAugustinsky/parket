import AppKit

typealias WindowPane = Pane<TrackedWindow>

package final class Monitor {
    let displayID: CGDirectDisplayID
    var screen: NSScreen
    var workspaces: [[WindowPane]] = Array(repeating: [], count: Config.shared.workspaceCount)
    var layouts: [Layout] = Array(repeating: .tile, count: Config.shared.workspaceCount)
    var focusedPaneIndices: [Int] = Array(repeating: 0, count: Config.shared.workspaceCount)
    var active: Int = 0
    var previousActive: Int = 0
    private var retileScheduled = false

    init(displayID: CGDirectDisplayID, screen: NSScreen) {
        self.displayID = displayID
        self.screen = screen
    }

    func switchTo(_ index: Int) {
        guard index >= 0, index < Config.shared.workspaceCount, index != active else { return }

        let previous = active
        previousActive = previous
        saveFocusedIndex()
        active = index

        hideWorkspace(previous)
        retile()
        restoreFocusedWindow()
    }

    func moveActiveWindowTo(_ index: Int) {
        guard index >= 0, index < Config.shared.workspaceCount, index != active else { return }
        guard let pane = removeFocusedPane() else { return }

        workspaces[index].insert(pane, at: 0)
        clampFocusedPaneIndex(index)
        retile()
        hidePane(pane)
        restoreFocusedWindow()
    }

    func insertWindow(_ window: TrackedWindow) {
        for workspace in workspaces where workspace.contains(where: { $0.contains(window) }) {
            return
        }
        workspaces[active].insert(Pane(windows: [window]), at: 0)
        focusedPaneIndices[active] = 0
    }

    func addWindow(_ window: TrackedWindow) {
        insertWindow(window)
        scheduleRetile()
    }

    @discardableResult
    func removeFocusedPane() -> WindowPane? {
        guard let location = activeLocation() else { return nil }
        let pane = workspaces[active].remove(at: location.paneIndex)
        clampFocusedPaneIndex(active)
        return pane
    }

    func removeWindows(where predicate: (TrackedWindow) -> Bool) -> Bool {
        var needsRetile = false
        var changed = false

        for workspaceIndex in 0..<Config.shared.workspaceCount {
            var workspaceChanged = false
            for paneIndex in workspaces[workspaceIndex].indices.reversed() {
                let removed = workspaces[workspaceIndex][paneIndex].removeAll(where: predicate)
                guard removed > 0 else { continue }
                workspaceChanged = true
                if workspaces[workspaceIndex][paneIndex].isEmpty {
                    workspaces[workspaceIndex].remove(at: paneIndex)
                }
            }

            if workspaceChanged {
                changed = true
                needsRetile = needsRetile || workspaceIndex == active
                clampFocusedPaneIndex(workspaceIndex)
            }
        }

        if changed && needsRetile { scheduleRetile() }
        return changed
    }

    func containsWindow(_ window: TrackedWindow) -> Bool {
        workspaces.contains { workspace in
            workspace.contains { $0.contains(window) }
        }
    }

    func focusNext() { focusOffset(1) }
    func focusPrev() { focusOffset(-1) }

    private func focusOffset(_ offset: Int) {
        guard var location = activeLocation() else { return }
        guard let target = PaneOperations.focusOffset(
            in: &workspaces[active],
            from: location,
            offset: offset
        ) else { return }

        location = target
        focusedPaneIndices[active] = location.paneIndex
        retile()
        focusActiveWindow(at: location)
    }

    func moveFocused(offset: Int) {
        guard let location = activeLocation() else { return }
        guard let target = PaneOperations.moveFocused(
            in: &workspaces[active],
            from: location,
            offset: offset
        ) else { return }

        focusedPaneIndices[active] = target.paneIndex
        retile()
        focusActiveWindow(at: target)
    }

    func groupFocused(offset: Int) {
        guard let location = activeLocation() else { return }
        guard let target = PaneOperations.groupFocused(
            in: &workspaces[active],
            from: location,
            offset: offset
        ) else { return }

        focusedPaneIndices[active] = target.paneIndex
        retile()
        focusActiveWindow(at: target)
    }

    func expelFocused(offset: Int) {
        guard let location = activeLocation() else { return }
        guard let target = PaneOperations.expelFocused(
            from: &workspaces[active],
            location: location,
            offset: offset
        ) else { return }

        focusedPaneIndices[active] = target.paneIndex
        retile()
        focusActiveWindow(at: target)
    }

    func swapMaster() {
        guard let location = activeLocation(), location.paneIndex != 0 else { return }
        workspaces[active].swapAt(0, location.paneIndex)
        let target = PaneLocation(paneIndex: 0, windowIndex: location.windowIndex)
        focusedPaneIndices[active] = 0
        retile()
        focusActiveWindow(at: target)
    }

    func toggleLayout() {
        layouts[active] = layouts[active] == .tile ? .monocle : .tile
        retile()
        if layouts[active] == .monocle {
            activeWindow()?.raise()
        }
    }

    func activateTab(index: Int) {
        guard !workspaces[active].isEmpty else { return }
        let paneIndex = min(focusedPaneIndices[active], workspaces[active].count - 1)
        guard workspaces[active][paneIndex].windows.indices.contains(index) else { return }
        workspaces[active][paneIndex].activeIndex = index
        let location = PaneLocation(paneIndex: paneIndex, windowIndex: index)
        retile()
        focusActiveWindow(at: location)
    }

    private func scheduleRetile() {
        guard !retileScheduled else { return }
        retileScheduled = true
        DispatchQueue.main.async { [self] in
            retileScheduled = false
            retile()
            StatusBar.shared.update()
        }
    }

    @discardableResult
    func retile() -> CGRect {
        cleanupWorkspace(active)
        let screen = WindowManager.screenFrame(for: self.screen)
        let offscreen = WindowManager.screenRect(for: self.screen)
        let frames = Tiler.calculateFrames(count: workspaces[active].count, screen: screen, layout: layouts[active])

        for (paneIndex, paneFrame) in frames.enumerated() {
            guard workspaces[active].indices.contains(paneIndex) else { continue }
            let pane = workspaces[active][paneIndex]
            for (windowIndex, window) in pane.windows.enumerated() {
                if windowIndex == pane.activeIndex {
                    window.setFrame(paneFrame)
                } else {
                    window.hideOffscreen(offscreen)
                }
            }
        }
        return screen
    }

    package func resizeWorkspaces(to count: Int) {
        let old = workspaces.count
        guard count != old else { return }

        if count > old {
            workspaces.append(contentsOf: Array(repeating: [], count: count - old))
            layouts.append(contentsOf: Array(repeating: .tile, count: count - old))
            focusedPaneIndices.append(contentsOf: Array(repeating: 0, count: count - old))
        } else {
            let overflow = workspaces[count..<old].flatMap { $0 }
            workspaces.removeSubrange(count...)
            layouts.removeSubrange(count...)
            focusedPaneIndices.removeSubrange(count...)
            if active >= count {
                active = count - 1
            }
            if previousActive >= count {
                previousActive = active
            }
            workspaces[active].append(contentsOf: overflow)
        }
    }

    func saveFocusedIndex() {
        guard let location = activeLocation() else { return }
        focusedPaneIndices[active] = location.paneIndex
        workspaces[active][location.paneIndex].activeIndex = location.windowIndex
    }

    func copyState(from source: Monitor) {
        workspaces = source.workspaces
        layouts = source.layouts
        focusedPaneIndices = source.focusedPaneIndices
        active = source.active
        previousActive = source.previousActive
    }

    func resetState() {
        let count = Config.shared.workspaceCount
        workspaces = Array(repeating: [], count: count)
        layouts = Array(repeating: .tile, count: count)
        focusedPaneIndices = Array(repeating: 0, count: count)
        active = 0
        previousActive = 0
    }

    func restoreFocusedWindow() {
        guard let location = savedLocation() else { return }
        focusActiveWindow(at: location)
    }

    func restoreAllWindows() {
        let screen = WindowManager.screenFrame(for: self.screen)
        let center = CGPoint(
            x: screen.origin.x + screen.width / 4,
            y: screen.origin.y + screen.height / 4
        )
        let size = CGSize(width: screen.width / 2, height: screen.height / 2)

        for workspace in workspaces {
            for pane in workspace {
                for win in pane.windows {
                    win.setFrame(CGRect(origin: center, size: size))
                }
            }
        }
    }

    func location(of window: TrackedWindow, workspaceIndex: Int) -> PaneLocation? {
        guard workspaces.indices.contains(workspaceIndex) else { return nil }
        return PaneOperations.location(of: window, in: workspaces[workspaceIndex])
    }

    @discardableResult
    func activateWindow(_ window: TrackedWindow, workspaceIndex: Int) -> Bool {
        guard let location = location(of: window, workspaceIndex: workspaceIndex) else { return false }
        focusedPaneIndices[workspaceIndex] = location.paneIndex
        workspaces[workspaceIndex][location.paneIndex].activeIndex = location.windowIndex
        return true
    }

    func tabStripState() -> TabStripState? {
        guard let location = activeLocation() else { return nil }
        let pane = workspaces[active][location.paneIndex]
        guard pane.windows.count > 1 else { return nil }

        let screen = WindowManager.screenFrame(for: self.screen)
        let frames = Tiler.calculateFrames(count: workspaces[active].count, screen: screen, layout: layouts[active])
        guard frames.indices.contains(location.paneIndex) else { return nil }

        return TabStripState(
            frame: frames[location.paneIndex],
            titles: pane.windows.map { $0.displayTitle() },
            activeIndex: pane.activeIndex
        )
    }

    private func activeLocation() -> PaneLocation? {
        if let focused = WindowManager.focusedWindow(),
           let location = location(of: focused, workspaceIndex: active) {
            workspaces[active][location.paneIndex].activeIndex = location.windowIndex
            focusedPaneIndices[active] = location.paneIndex
            return location
        }
        return savedLocation()
    }

    private func savedLocation() -> PaneLocation? {
        guard !workspaces[active].isEmpty else { return nil }
        clampFocusedPaneIndex(active)
        let paneIndex = focusedPaneIndices[active]
        let pane = workspaces[active][paneIndex]
        guard !pane.windows.isEmpty else { return nil }
        return PaneLocation(paneIndex: paneIndex, windowIndex: pane.activeIndex)
    }

    private func activeWindow() -> TrackedWindow? {
        guard let location = savedLocation() else { return nil }
        return workspaces[active][location.paneIndex].activeWindow
    }

    private func focusActiveWindow(at location: PaneLocation) {
        guard workspaces[active].indices.contains(location.paneIndex),
              let window = workspaces[active][location.paneIndex].activeWindow
        else { return }
        window.focus()
        if layouts[active] == .monocle {
            window.raise()
        }
    }

    private func hideWorkspace(_ index: Int) {
        guard workspaces.indices.contains(index) else { return }
        for pane in workspaces[index] {
            hidePane(pane)
        }
    }

    private func hidePane(_ pane: WindowPane) {
        let screen = WindowManager.screenRect(for: self.screen)
        for window in pane.windows {
            window.hideOffscreen(screen)
        }
    }

    private func cleanupWorkspace(_ index: Int) {
        guard workspaces.indices.contains(index) else { return }
        for paneIndex in workspaces[index].indices.reversed() {
            workspaces[index][paneIndex].removeAll { !$0.isTileable() }
            if workspaces[index][paneIndex].isEmpty {
                workspaces[index].remove(at: paneIndex)
            }
        }
        clampFocusedPaneIndex(index)
    }

    private func clampFocusedPaneIndex(_ index: Int) {
        guard focusedPaneIndices.indices.contains(index) else { return }
        if workspaces[index].isEmpty {
            focusedPaneIndices[index] = 0
        } else {
            focusedPaneIndices[index] = min(max(focusedPaneIndices[index], 0), workspaces[index].count - 1)
            workspaces[index][focusedPaneIndices[index]].normalizeActiveIndex()
        }
    }
}
