import AppKit

typealias WindowPane = Pane<TrackedWindow>

package final class Monitor {
    let displayID: CGDirectDisplayID
    var screen: NSScreen
    var workspaces: [[WindowPane]] = Array(repeating: [], count: Config.shared.workspaceCount)
    var layouts: [Layout] = Array(repeating: .tile, count: Config.shared.workspaceCount)
    var focusedPaneIDs: [PaneID?] = Array(repeating: nil, count: Config.shared.workspaceCount)
    var lastStackPaneIDs: [PaneID?] = Array(repeating: nil, count: Config.shared.workspaceCount)
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
        normalizeWorkspace(previous)
        active = index

        hideWorkspace(previous)
        retile()
        restoreFocusedWindow()
    }

    func moveActiveWindowTo(_ index: Int) {
        guard index >= 0, index < Config.shared.workspaceCount, index != active else { return }
        guard let pane = removeFocusedPane() else { return }

        workspaces[index].insert(pane, at: 0)
        focusedPaneIDs[index] = pane.id
        normalizeWorkspace(index)
        retile()
        hidePane(pane)
        restoreFocusedWindow()
    }

    func insertWindow(_ window: TrackedWindow) {
        for workspace in workspaces where workspace.contains(where: { $0.contains(window) }) {
            return
        }
        let pane = Pane(windows: [window])
        workspaces[active].insert(pane, at: 0)
        focusedPaneIDs[active] = pane.id
    }

    func addWindow(_ window: TrackedWindow) {
        insertWindow(window)
        scheduleRetile()
    }

    @discardableResult
    func removeFocusedPane() -> WindowPane? {
        guard let location = savedLocation() else { return nil }
        let pane = workspaces[active].remove(at: location.paneIndex)
        normalizeWorkspace(active, preferredPaneIndex: location.paneIndex)
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
                normalizeWorkspace(workspaceIndex)
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
    func focusLeft() { focusHorizontal(left: true) }
    func focusRight() { focusHorizontal(left: false) }

    private func focusOffset(_ offset: Int) {
        guard var location = savedLocation() else { return }
        guard let target = PaneOperations.focusOffset(
            in: &workspaces[active],
            from: location,
            offset: offset
        ) else { return }

        location = target
        focusedPaneIDs[active] = workspaces[active][location.paneIndex].id
        if location.paneIndex != 0 {
            lastStackPaneIDs[active] = workspaces[active][location.paneIndex].id
        }
        retile(cleanup: false)
        focusActiveWindow(at: location)
    }

    private func focusHorizontal(left: Bool) {
        guard layouts[active] == .tile else {
            focusOffset(left ? -1 : 1)
            return
        }
        guard let location = savedLocation() else { return }

        let target = left
            ? PaneOperations.focusLeft(in: workspaces[active], from: location)
            : PaneOperations.focusRight(
                in: workspaces[active],
                from: location,
                rememberedStackPaneID: lastStackPaneIDs[active]
            )

        guard let target else { return }

        if location.paneIndex != 0 {
            lastStackPaneIDs[active] = workspaces[active][location.paneIndex].id
        }
        if target.paneIndex != 0 {
            lastStackPaneIDs[active] = workspaces[active][target.paneIndex].id
        }
        focusedPaneIDs[active] = workspaces[active][target.paneIndex].id
        retile(cleanup: false)
        focusActiveWindow(at: target)
    }

    func moveFocused(offset: Int) {
        guard let location = savedLocation() else { return }
        guard let target = PaneOperations.moveFocused(
            in: &workspaces[active],
            from: location,
            offset: offset
        ) else { return }

        focusedPaneIDs[active] = workspaces[active][target.paneIndex].id
        retile(cleanup: false)
        focusActiveWindow(at: target)
    }

    func groupFocused(offset: Int) {
        guard let location = savedLocation() else { return }
        guard let target = PaneOperations.groupFocused(
            in: &workspaces[active],
            from: location,
            offset: offset
        ) else { return }

        focusedPaneIDs[active] = workspaces[active][target.paneIndex].id
        retile(cleanup: false)
        focusActiveWindow(at: target)
    }

    func expelFocused(offset: Int) {
        guard let location = savedLocation() else { return }
        guard let target = PaneOperations.expelFocused(
            from: &workspaces[active],
            location: location,
            offset: offset
        ) else { return }

        focusedPaneIDs[active] = workspaces[active][target.paneIndex].id
        retile(cleanup: false)
        focusActiveWindow(at: target)
    }

    func swapMaster() {
        guard let location = savedLocation(), location.paneIndex != 0 else { return }
        workspaces[active].swapAt(0, location.paneIndex)
        let target = PaneLocation(paneIndex: 0, windowIndex: location.windowIndex)
        focusedPaneIDs[active] = workspaces[active][0].id
        retile(cleanup: false)
        focusActiveWindow(at: target)
    }

    func toggleLayout() {
        layouts[active] = layouts[active] == .tile ? .monocle : .tile
        retile(cleanup: false)
        if layouts[active] == .monocle {
            activeWindow()?.raise()
        }
    }

    func activateTab(paneID: PaneID, window: TrackedWindow) {
        guard let paneIndex = PaneOperations.location(of: paneID, in: workspaces[active]),
              let windowIndex = workspaces[active][paneIndex].firstIndex(of: window)
        else { return }

        focusedPaneIDs[active] = paneID
        workspaces[active][paneIndex].activeWindow = window
        let location = PaneLocation(paneIndex: paneIndex, windowIndex: windowIndex)
        retile(cleanup: false)
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
    func retile(cleanup: Bool = true) -> CGRect {
        if cleanup {
            cleanupWorkspace(active)
        } else {
            normalizeWorkspace(active)
        }
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
            focusedPaneIDs.append(contentsOf: Array(repeating: nil, count: count - old))
            lastStackPaneIDs.append(contentsOf: Array(repeating: nil, count: count - old))
        } else {
            let overflow = workspaces[count..<old].flatMap { $0 }
            workspaces.removeSubrange(count...)
            layouts.removeSubrange(count...)
            focusedPaneIDs.removeSubrange(count...)
            lastStackPaneIDs.removeSubrange(count...)
            if active >= count {
                active = count - 1
            }
            if previousActive >= count {
                previousActive = active
            }
            workspaces[active].append(contentsOf: overflow)
            normalizeWorkspace(active)
        }
    }

    func saveFocusedIndex() {
        normalizeWorkspace(active)
    }

    func copyState(from source: Monitor) {
        workspaces = source.workspaces
        layouts = source.layouts
        focusedPaneIDs = source.focusedPaneIDs
        lastStackPaneIDs = source.lastStackPaneIDs
        active = source.active
        previousActive = source.previousActive
    }

    func resetState() {
        let count = Config.shared.workspaceCount
        workspaces = Array(repeating: [], count: count)
        layouts = Array(repeating: .tile, count: count)
        focusedPaneIDs = Array(repeating: nil, count: count)
        lastStackPaneIDs = Array(repeating: nil, count: count)
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

    func activeWindow(workspaceIndex: Int, paneIndex: Int) -> TrackedWindow? {
        guard workspaces.indices.contains(workspaceIndex),
              workspaces[workspaceIndex].indices.contains(paneIndex)
        else { return nil }
        return workspaces[workspaceIndex][paneIndex].activeWindow
    }

    @discardableResult
    func activateWindow(_ window: TrackedWindow, workspaceIndex: Int) -> Bool {
        guard let location = location(of: window, workspaceIndex: workspaceIndex) else { return false }
        focusedPaneIDs[workspaceIndex] = workspaces[workspaceIndex][location.paneIndex].id
        workspaces[workspaceIndex][location.paneIndex].activeWindow = window
        return true
    }

    func tabStripState() -> TabStripState? {
        guard let location = savedLocation() else { return nil }
        let pane = workspaces[active][location.paneIndex]
        guard pane.windows.count > 1 else { return nil }

        let screen = WindowManager.screenFrame(for: self.screen)
        let frames = Tiler.calculateFrames(count: workspaces[active].count, screen: screen, layout: layouts[active])
        guard frames.indices.contains(location.paneIndex) else { return nil }

        return TabStripState(
            paneID: pane.id,
            frame: frames[location.paneIndex],
            tabs: pane.windows.map { TabState(window: $0, title: $0.displayTitle()) },
            activeWindow: pane.activeWindow ?? pane.windows[location.windowIndex]
        )
    }

    private func savedLocation() -> PaneLocation? {
        guard !workspaces[active].isEmpty else { return nil }
        normalizeWorkspace(active)
        guard let focusedPaneID = focusedPaneIDs[active],
              let paneIndex = PaneOperations.location(of: focusedPaneID, in: workspaces[active])
        else { return nil }
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
              workspaces[active][location.paneIndex].windows.indices.contains(location.windowIndex)
        else { return }
        let window = workspaces[active][location.paneIndex].windows[location.windowIndex]
        workspaces[active][location.paneIndex].activeWindow = window
        WorkspaceManager.shared.noteInternalFocus(window)
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
        removeDuplicateWindows(in: index)
        for paneIndex in workspaces[index].indices.reversed() {
            workspaces[index][paneIndex].removeAll { !$0.isTileable() }
            if workspaces[index][paneIndex].isEmpty {
                workspaces[index].remove(at: paneIndex)
            }
        }
        normalizeWorkspace(index)
    }

    private func removeDuplicateWindows(in index: Int) {
        var seen: [TrackedWindow] = []
        var deduped: [WindowPane] = []

        for var pane in workspaces[index] {
            pane.windows = pane.windows.filter { window in
                if seen.contains(window) {
                    return false
                }
                seen.append(window)
                return true
            }

            guard !pane.isEmpty else { continue }
            pane.normalizeActiveWindow()
            deduped.append(pane)
        }

        workspaces[index] = deduped
    }

    private func normalizeWorkspace(_ index: Int, preferredPaneIndex: Int? = nil) {
        guard focusedPaneIDs.indices.contains(index), workspaces.indices.contains(index) else { return }

        for paneIndex in workspaces[index].indices {
            workspaces[index][paneIndex].normalizeActiveWindow()
        }

        if workspaces[index].isEmpty {
            focusedPaneIDs[index] = nil
            lastStackPaneIDs[index] = nil
            return
        }

        if let lastStackPaneID = lastStackPaneIDs[index],
           !workspaces[index].contains(where: { $0.id == lastStackPaneID }) {
            lastStackPaneIDs[index] = nil
        }

        if let focusedPaneID = focusedPaneIDs[index],
           workspaces[index].contains(where: { $0.id == focusedPaneID }) {
            return
        }

        let targetIndex = preferredPaneIndex.map {
            min(max($0, 0), workspaces[index].count - 1)
        } ?? 0
        focusedPaneIDs[index] = workspaces[index][targetIndex].id
    }
}
