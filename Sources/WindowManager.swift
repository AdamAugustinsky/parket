import AppKit
import ApplicationServices

struct TrackedWindow: Equatable {
    let element: AXUIElement
    let pid: pid_t

    static func == (lhs: TrackedWindow, rhs: TrackedWindow) -> Bool {
        lhs.isSameWindow(as: rhs)
    }

    func getFrame() -> CGRect? {
        var posValue: AnyObject?
        var sizeValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }

        guard CFGetTypeID(posValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: pos, size: size)
    }

    func setPosition(_ point: CGPoint) {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    func setSize(_ size: CGSize) {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
    }

    func hideOffscreen(_ screen: CGRect) {
        setPosition(CGPoint(x: screen.origin.x + 1 - screen.width, y: screen.maxY - 1))
    }

    func setFrame(_ rect: CGRect) {
        setPosition(rect.origin)
        setSize(rect.size)
    }

    func focus() {
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }
    }

    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    func isTileable() -> Bool {
        guard let role = stringAttribute(kAXRoleAttribute as CFString),
              let subrole = stringAttribute(kAXSubroleAttribute as CFString)
        else { return false }

        let minimized = boolAttribute(kAXMinimizedAttribute as CFString)
        let fullscreen = boolAttribute("AXFullScreen" as CFString)

        return role == kAXWindowRole
            && subrole == kAXStandardWindowSubrole
            && !minimized
            && !fullscreen
    }

    func title() -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func stringAttribute(_ attribute: CFString) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func boolAttribute(_ attribute: CFString) -> Bool {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return false
        }
        return value as? Bool ?? false
    }

    private func isSameWindow(as other: TrackedWindow) -> Bool {
        guard pid == other.pid else { return false }
        if CFEqual(element, other.element) { return true }

        if let windowNumber = cgWindowNumber(),
           let otherWindowNumber = other.cgWindowNumber() {
            return windowNumber == otherWindowNumber
        }

        guard let frame = getFrame(),
              let otherFrame = other.getFrame(),
              frame.isApproximatelyEqual(to: otherFrame)
        else { return false }

        let identifier = stringAttribute("AXIdentifier" as CFString)
        let otherIdentifier = other.stringAttribute("AXIdentifier" as CFString)
        if identifier != nil || otherIdentifier != nil {
            return identifier == otherIdentifier
        }

        return title() == other.title()
    }

    private func cgWindowNumber() -> Int? {
        guard let frame = getFrame(),
              let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        let expectedTitle = title()

        for info in windows {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                  pid_t(ownerPID) == pid,
                  (info[kCGWindowLayer as String] as? Int ?? 0) == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.isApproximatelyEqual(to: frame)
            else { continue }

            if let expectedTitle,
               let windowTitle = info[kCGWindowName as String] as? String,
               !windowTitle.isEmpty,
               windowTitle != expectedTitle {
                continue
            }

            return info[kCGWindowNumber as String] as? Int
        }

        return nil
    }

    func displayTitle() -> String {
        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName
        let raw = appName ?? title() ?? "Window"
        guard raw.count > 18 else { return raw }
        return String(raw.prefix(17)) + "..."
    }
}

enum WindowManager {
    static func allWindows() -> [TrackedWindow] {
        var result: [TrackedWindow] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            let pid = app.processIdentifier
            let appRef = AXUIElementCreateApplication(pid)

            var windowsValue: AnyObject?
            guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                  let windows = windowsValue as? [AXUIElement]
            else { continue }

            for win in windows {
                let tw = TrackedWindow(element: win, pid: pid)
                guard tw.isTileable() else { continue }
                result.append(tw)
            }
        }
        return result
    }

    static func focusedWindow() -> TrackedWindow? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        return focusedWindow(pid: frontApp.processIdentifier)
    }

    static func focusedWindow(pid: pid_t) -> TrackedWindow? {
        let appRef = AXUIElementCreateApplication(pid)

        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &value) == .success else {
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let win = value as! AXUIElement
        guard isStandardWindow(win) else { return nil }
        return TrackedWindow(element: win, pid: pid)
    }

    static func isStandardWindow(_ element: AXUIElement) -> Bool {
        var roleValue: AnyObject?
        var subroleValue: AnyObject?

        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue) == .success
        else { return false }

        let role = roleValue as? String
        let subrole = subroleValue as? String
        return role == kAXWindowRole && subrole == kAXStandardWindowSubrole
    }

    static func screenFrame() -> CGRect {
        guard let screen = NSScreen.main else {
            return CGRect(x: 0, y: 0, width: 1920, height: 1080)
        }
        return screenFrame(for: screen)
    }

    static func screenFrame(for screen: NSScreen) -> CGRect {
        convertRect(screen.visibleFrame)
    }

    static func screenRect(for screen: NSScreen) -> CGRect {
        convertRect(screen.frame)
    }

    private static func convertRect(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 1080
        return CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func appKitRect(fromWindowRect rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 1080
        return CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}

private extension CGRect {
    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(origin.x - other.origin.x) <= tolerance
            && abs(origin.y - other.origin.y) <= tolerance
            && abs(size.width - other.size.width) <= tolerance
            && abs(size.height - other.size.height) <= tolerance
    }
}
