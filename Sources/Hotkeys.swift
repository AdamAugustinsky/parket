import Cocoa
import ApplicationServices

package final class Hotkeys {
    package static let shared = Hotkeys()

    private var tap: CFMachPort?

    private init() {}

    package func start() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Hotkeys.callback,
            userInfo: nil
        ) else {
            fputs("parket: failed to create event tap (check Input Monitoring permission)\n", stderr)
            exit(1)
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private static let callback: CGEventTapCallBack = { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = Hotkeys.shared.tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        let config = Config.shared
        let hasModifier = flags.contains(config.modifier)
        let hasShift = flags.contains(.maskShift)

        guard hasModifier else {
            return Unmanaged.passRetained(event)
        }

        for binding in config.customBindings {
            guard binding.combo.matches(keyCode: keyCode, flags: flags, globalModifier: config.modifier) else { continue }
            let cmd = binding.command
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", cmd]
                try? process.run()
            }
            return nil
        }

        if let number = config.numberKeys[keyCode] {
            guard isWorkspaceCombo(flags: flags, shift: hasShift, globalModifier: config.modifier) else {
                return Unmanaged.passRetained(event)
            }
            let index = number - 1
            DispatchQueue.main.async {
                if hasShift {
                    WorkspaceManager.shared.moveActiveWindowTo(index)
                } else {
                    WorkspaceManager.shared.switchTo(index)
                }
            }
            return nil
        }

        let b = config.bindings

        if matches(b.focusMonitorPrev, keyCode: keyCode, flags: flags, globalModifier: config.modifier) {
            DispatchQueue.main.async { WorkspaceManager.shared.focusMonitor(offset: -1) }
            return nil
        }
        if matches(b.focusMonitorNext, keyCode: keyCode, flags: flags, globalModifier: config.modifier) {
            DispatchQueue.main.async { WorkspaceManager.shared.focusMonitor(offset: 1) }
            return nil
        }
        if matches(b.moveMonitorPrev, keyCode: keyCode, flags: flags, globalModifier: config.modifier) {
            DispatchQueue.main.async { WorkspaceManager.shared.moveWindowToMonitor(offset: -1) }
            return nil
        }
        if matches(b.moveMonitorNext, keyCode: keyCode, flags: flags, globalModifier: config.modifier) {
            DispatchQueue.main.async { WorkspaceManager.shared.moveWindowToMonitor(offset: 1) }
            return nil
        }
        if matches(b.lastWorkspace, keyCode: keyCode, flags: flags, globalModifier: config.modifier) {
            DispatchQueue.main.async { WorkspaceManager.shared.switchToLast() }
            return nil
        }
        if matches(b.focusNext, keyCode: keyCode, flags: flags, globalModifier: config.modifier) {
            DispatchQueue.main.async { WorkspaceManager.shared.focusNext() }
            return nil
        }
        if matches(b.focusPrev, keyCode: keyCode, flags: flags, globalModifier: config.modifier) {
            DispatchQueue.main.async { WorkspaceManager.shared.focusPrev() }
            return nil
        }
        if matches(b.moveNext, keyCode: keyCode, flags: flags, globalModifier: config.modifier) {
            DispatchQueue.main.async { WorkspaceManager.shared.moveFocused(offset: 1) }
            return nil
        }
        if matches(b.movePrev, keyCode: keyCode, flags: flags, globalModifier: config.modifier) {
            DispatchQueue.main.async { WorkspaceManager.shared.moveFocused(offset: -1) }
            return nil
        }
        if matches(b.groupNext, keyCode: keyCode, flags: flags, globalModifier: config.modifier) {
            DispatchQueue.main.async { WorkspaceManager.shared.groupFocused(offset: 1) }
            return nil
        }
        if matches(b.groupPrev, keyCode: keyCode, flags: flags, globalModifier: config.modifier) {
            DispatchQueue.main.async { WorkspaceManager.shared.groupFocused(offset: -1) }
            return nil
        }
        if matches(b.expelNext, keyCode: keyCode, flags: flags, globalModifier: config.modifier) {
            DispatchQueue.main.async { WorkspaceManager.shared.expelFocused(offset: 1) }
            return nil
        }
        if matches(b.expelPrev, keyCode: keyCode, flags: flags, globalModifier: config.modifier) {
            DispatchQueue.main.async { WorkspaceManager.shared.expelFocused(offset: -1) }
            return nil
        }
        if matches(b.swapMaster, keyCode: keyCode, flags: flags, globalModifier: config.modifier) {
            DispatchQueue.main.async { WorkspaceManager.shared.swapMaster() }
            return nil
        }
        if matches(b.toggleLayout, keyCode: keyCode, flags: flags, globalModifier: config.modifier) {
            DispatchQueue.main.async { WorkspaceManager.shared.toggleLayout() }
            return nil
        }
        if matches(b.decreaseMasterRatio, keyCode: keyCode, flags: flags, globalModifier: config.modifier) {
            DispatchQueue.main.async { WorkspaceManager.shared.adjustMasterRatio(by: -0.05) }
            return nil
        }
        if matches(b.increaseMasterRatio, keyCode: keyCode, flags: flags, globalModifier: config.modifier) {
            DispatchQueue.main.async { WorkspaceManager.shared.adjustMasterRatio(by: 0.05) }
            return nil
        }
        if matches(b.resetMasterRatio, keyCode: keyCode, flags: flags, globalModifier: config.modifier) {
            DispatchQueue.main.async { WorkspaceManager.shared.resetMasterRatio() }
            return nil
        }

        return Unmanaged.passRetained(event)
    }

    private static func matches(
        _ combos: [KeyCombo],
        keyCode: UInt16,
        flags: CGEventFlags,
        globalModifier: CGEventFlags
    ) -> Bool {
        combos.contains { $0.matches(keyCode: keyCode, flags: flags, globalModifier: globalModifier) }
    }

    private static func isWorkspaceCombo(
        flags: CGEventFlags,
        shift: Bool,
        globalModifier: CGEventFlags
    ) -> Bool {
        let combo = KeyCombo(key: 0, shift: shift)
        return combo.matches(keyCode: 0, flags: flags, globalModifier: globalModifier)
    }
}
