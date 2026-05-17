import Foundation
import AppKit

package final class WorkspaceManager {
    package static let shared = WorkspaceManager()

    private(set) var monitors: [Monitor] = []
    private(set) var focusedMonitorIndex: Int = 0
    private var screenChangeWork: DispatchWorkItem?
    private var focusEchoSuppressionUntil: Date?

    var focusedMonitor: Monitor { monitors[focusedMonitorIndex] }

    private init() {}

    package func bootstrap() {
        rebuildMonitors()
        focusedMonitorIndex = 0
        let windows = WindowManager.allWindows()
        for window in windows {
            monitorForWindow(window).insertWindow(window)
        }
        for monitor in monitors {
            monitor.retile()
        }
        if let app = NSWorkspace.shared.frontmostApplication, app.activationPolicy == .regular {
            revealFocusedWindow(pid: app.processIdentifier)
        }
        StatusBar.shared.update()
    }

    func switchTo(_ index: Int) {
        focusedMonitor.switchTo(index)
        StatusBar.shared.update()
    }

    func switchToLast() {
        let target = focusedMonitor.previousActive
        guard target != focusedMonitor.active else { return }
        switchTo(target)
    }

    @discardableResult
    func revealFocusedWindow(pid: pid_t) -> Bool {
        guard let window = WindowManager.focusedWindow(pid: pid) else { return false }
        if revealWindow(window) { return true }
        return adoptFocusedWindow(window)
    }

    @discardableResult
    func revealWindow(_ window: TrackedWindow) -> Bool {
        guard !monitors.isEmpty else { return false }
        guard !shouldSuppressFocusEcho(for: window) else { return true }

        for (monitorIndex, monitor) in monitors.enumerated() {
            for workspaceIndex in 0..<monitor.workspaces.count {
                guard monitor.location(of: window, workspaceIndex: workspaceIndex) != nil else {
                    continue
                }

                let monitorChanged = focusedMonitorIndex != monitorIndex
                let workspaceChanged = monitor.active != workspaceIndex
                guard monitorChanged || workspaceChanged else {
                    monitor.activateWindow(window, workspaceIndex: workspaceIndex)
                    monitor.retile()
                    StatusBar.shared.update()
                    return true
                }

                focusedMonitor.saveFocusedIndex()
                focusedMonitorIndex = monitorIndex
                monitor.activateWindow(window, workspaceIndex: workspaceIndex)

                if workspaceChanged {
                    monitor.switchTo(workspaceIndex)
                } else {
                    monitor.retile()
                    window.focus()
                    if monitor.layouts[workspaceIndex] == .monocle {
                        window.raise()
                    }
                }

                StatusBar.shared.update()
                return true
            }
        }
        return false
    }

    @discardableResult
    private func adoptFocusedWindow(_ window: TrackedWindow) -> Bool {
        guard window.isTileable() else { return false }
        let monitor = monitorForWindow(window)
        monitor.addWindow(window)
        if let monitorIndex = monitors.firstIndex(where: { $0 === monitor }) {
            focusedMonitorIndex = monitorIndex
        }
        StatusBar.shared.update()
        return true
    }

    func moveActiveWindowTo(_ index: Int) {
        focusedMonitor.moveActiveWindowTo(index)
        StatusBar.shared.update()
    }

    func addWindow(_ window: TrackedWindow) {
        for monitor in monitors where monitor.containsWindow(window) { return }
        focusedMonitor.addWindow(window)
        StatusBar.shared.update()
    }

    func removeWindow(pid: pid_t) {
        removeWindows { $0.pid == pid }
    }

    func removeWindow(_ window: TrackedWindow) {
        removeWindows { $0 == window }
    }

    private func removeWindows(where predicate: (TrackedWindow) -> Bool) {
        var changed = false
        for monitor in monitors {
            if monitor.removeWindows(where: predicate) {
                changed = true
            }
        }
        guard changed else { return }
        StatusBar.shared.update()
    }

    func focusNext() {
        focusedMonitor.focusNext()
        StatusBar.shared.update()
    }

    func focusPrev() {
        focusedMonitor.focusPrev()
        StatusBar.shared.update()
    }

    func focusLeft() {
        focusedMonitor.focusLeft()
        StatusBar.shared.update()
    }

    func focusRight() {
        focusedMonitor.focusRight()
        StatusBar.shared.update()
    }

    func moveFocused(offset: Int) {
        focusedMonitor.moveFocused(offset: offset)
        StatusBar.shared.update()
    }

    func groupFocused(offset: Int) {
        focusedMonitor.groupFocused(offset: offset)
        StatusBar.shared.update()
    }

    func expelFocused(offset: Int) {
        focusedMonitor.expelFocused(offset: offset)
        StatusBar.shared.update()
    }

    func activateTab(paneID: PaneID, window: TrackedWindow) {
        focusedMonitor.activateTab(paneID: paneID, window: window)
        StatusBar.shared.update()
    }

    func swapMaster() {
        focusedMonitor.swapMaster()
    }

    func toggleLayout() {
        focusedMonitor.toggleLayout()
        StatusBar.shared.update()
    }

    func adjustMasterRatio(by delta: CGFloat) {
        Config.shared.masterRatio = min(max(Config.shared.masterRatio + delta, 0.20), 0.80)
        for monitor in monitors {
            monitor.retile()
        }
    }

    func resetMasterRatio() {
        Config.shared.masterRatio = 0.50
        for monitor in monitors {
            monitor.retile()
        }
    }

    func focusMonitor(offset: Int) {
        guard monitors.count > 1 else { return }
        focusedMonitor.saveFocusedIndex()
        focusedMonitorIndex = (focusedMonitorIndex + offset + monitors.count) % monitors.count
        let target = focusedMonitor
        target.restoreFocusedWindow()
        StatusBar.shared.update()
    }

    func moveWindowToMonitor(offset: Int) {
        guard monitors.count > 1 else { return }

        let source = focusedMonitor
        guard let pane = source.removeFocusedPane() else { return }
        let focused = pane.activeWindow
        source.retile()

        let targetIndex = (focusedMonitorIndex + offset + monitors.count) % monitors.count
        let target = monitors[targetIndex]
        target.workspaces[target.active].insert(pane, at: 0)
        target.focusedPaneIDs[target.active] = pane.id
        target.retile()

        focusedMonitorIndex = targetIndex
        if let focused {
            noteInternalFocus(focused)
            focused.focus()
        }
        StatusBar.shared.update()
    }

    package func handleScreenChange() {
        screenChangeWork?.cancel()
        let work = DispatchWorkItem { [self] in
            performScreenChange()
        }
        screenChangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func performScreenChange() {
        screenChangeWork = nil
        let old = Dictionary(uniqueKeysWithValues: monitors.map { ($0.displayID, $0) })
        let oldPrimaryID = primaryDisplayID()
        let focusedDisplayID = monitors.isEmpty ? 0 : focusedMonitor.displayID
        rebuildMonitors()

        for monitor in monitors {
            if let existing = old[monitor.displayID] {
                monitor.copyState(from: existing)
            }
        }

        let currentIDs = Set(monitors.map { $0.displayID })
        for (id, oldMonitor) in old where !currentIDs.contains(id) {
            let target = monitors[0]
            for ws in oldMonitor.workspaces {
                for pane in ws {
                    target.workspaces[target.active].insert(pane, at: 0)
                }
            }
        }

        let newPrimaryID = primaryDisplayID()

        if newPrimaryID != oldPrimaryID,
           let newPrimary = monitors.first(where: { $0.displayID == newPrimaryID }),
           let oldPrimary = monitors.first(where: { $0.displayID == oldPrimaryID }),
           newPrimary.workspaces.allSatisfy({ $0.isEmpty }) {
            newPrimary.copyState(from: oldPrimary)
            oldPrimary.resetState()
        }

        if newPrimaryID != oldPrimaryID {
            focusedMonitorIndex = monitors.firstIndex(where: { $0.displayID == newPrimaryID }) ?? 0
        } else {
            focusedMonitorIndex = monitors.firstIndex(where: { $0.displayID == focusedDisplayID }) ?? 0
        }

        for monitor in monitors {
            monitor.retile()
        }
        StatusBar.shared.update()
    }

    package func reloadConfig() {
        Config.load()
        let count = Config.shared.workspaceCount
        for monitor in monitors {
            monitor.resizeWorkspaces(to: count)
            monitor.retile()
        }
        StatusBar.shared.update()
        fputs("parket: config reloaded\n", stderr)
    }

    package func restoreAllWindows() {
        for monitor in monitors {
            monitor.restoreAllWindows()
        }
    }

    func tabStripState() -> TabStripState? {
        guard !monitors.isEmpty else { return nil }
        return focusedMonitor.tabStripState()
    }

    func noteInternalFocus(_ window: TrackedWindow) {
        focusEchoSuppressionUntil = Date().addingTimeInterval(0.5)
    }

    private func shouldSuppressFocusEcho(for window: TrackedWindow) -> Bool {
        guard let focusEchoSuppressionUntil else { return false }
        if Date() <= focusEchoSuppressionUntil {
            return true
        }
        self.focusEchoSuppressionUntil = nil
        return false
    }

    private func rebuildMonitors() {
        monitors = NSScreen.screens
            .map { screen in
                Monitor(
                    displayID: WindowManager.displayID(for: screen),
                    screen: screen
                )
            }
            .sorted { $0.screen.frame.origin.x < $1.screen.frame.origin.x }
    }

    private func primaryDisplayID() -> CGDirectDisplayID {
        guard !monitors.isEmpty else { return 0 }
        return monitors.first(where: { $0.screen == NSScreen.main })?.displayID ?? monitors[0].displayID
    }

    private func monitorForWindow(_ window: TrackedWindow) -> Monitor {
        guard monitors.count > 1, let frame = window.getFrame() else {
            return monitors[0]
        }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        for monitor in monitors {
            let rect = WindowManager.screenRect(for: monitor.screen)
            if rect.contains(center) {
                return monitor
            }
        }
        return monitors[0]
    }
}
