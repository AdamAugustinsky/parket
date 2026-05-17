import AppKit

package struct TabState: Equatable {
    let window: TrackedWindow
    let title: String
}

package struct TabStripState: Equatable {
    let paneID: PaneID
    let frame: CGRect
    let tabs: [TabState]
    let activeWindow: TrackedWindow
}

package final class TabStripController: NSObject {
    package static let shared = TabStripController()

    private var panel: NSPanel?
    private var container: NSView?
    private var segmentedControl: NSSegmentedControl?
    private var lastState: TabStripState?
    private var lastContentKey: TabStripContentKey?

    private override init() {}

    package func update(_ state: TabStripState?) {
        DispatchQueue.main.async {
            guard let state, state.tabs.count > 1 else {
                self.panel?.orderOut(nil)
                self.lastState = nil
                self.lastContentKey = nil
                return
            }

            let panel = self.ensurePanel()
            self.position(panel: panel, for: state)
            let contentKey = TabStripContentKey(state)
            if self.lastContentKey != contentKey {
                self.rebuildTabs(state)
                self.lastContentKey = contentKey
            }
            self.lastState = state
            panel.orderFrontRegardless()
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 34),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let container = makeNativeContainer()
        panel.contentView = container

        self.panel = panel
        self.container = container
        return panel
    }

    private func makeNativeContainer() -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.translatesAutoresizingMaskIntoConstraints = false
            glass.cornerRadius = 13
            glass.style = .regular
            glass.tintColor = NSColor.controlBackgroundColor.withAlphaComponent(0.12)

            let content = NSView()
            content.translatesAutoresizingMaskIntoConstraints = false
            glass.contentView = content
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
                content.topAnchor.constraint(equalTo: glass.topAnchor),
                content.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            ])
            return glass
        }

        let visual = NSVisualEffectView()
        visual.translatesAutoresizingMaskIntoConstraints = false
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.wantsLayer = true
        visual.layer?.cornerRadius = 13
        visual.layer?.cornerCurve = .continuous
        visual.layer?.masksToBounds = true
        visual.layer?.borderWidth = 0.5
        visual.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        return visual
    }

    private func position(panel: NSPanel, for state: TabStripState) {
        let pane = WindowManager.appKitRect(fromWindowRect: state.frame)
        let height: CGFloat = 34
        let width = max(132, min(pane.width - 24, CGFloat(state.tabs.count) * 104 + 18))
        let x = pane.minX + (pane.width - width) / 2
        let y = pane.maxY - height - 10
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func rebuildTabs(_ state: TabStripState) {
        guard let container else { return }

        segmentedControl?.removeFromSuperview()

        let control = NSSegmentedControl(
            labels: state.tabs.map(\.title),
            trackingMode: .selectOne,
            target: self,
            action: #selector(selectTab(_:))
        )
        control.translatesAutoresizingMaskIntoConstraints = false
        control.segmentStyle = .capsule
        control.segmentDistribution = .fillEqually
        control.controlSize = .small
        control.font = .systemFont(ofSize: 12, weight: .medium)

        if #available(macOS 26.0, *) {
            control.borderShape = .capsule
        }

        control.selectedSegment = state.tabs.firstIndex { $0.window == state.activeWindow } ?? 0
        for index in state.tabs.indices {
            control.setTag(index, forSegment: index)
            control.setToolTip(state.tabs[index].title, forSegment: index)
        }

        container.addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            control.topAnchor.constraint(equalTo: container.topAnchor, constant: 5),
            control.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5),
        ])
        segmentedControl = control
    }

    @objc private func selectTab(_ sender: NSSegmentedControl) {
        let index = sender.selectedSegment
        guard let state = lastState,
              state.tabs.indices.contains(index)
        else { return }
        WorkspaceManager.shared.activateTab(paneID: state.paneID, window: state.tabs[index].window)
    }
}

private struct TabStripContentKey: Equatable {
    let paneID: PaneID
    let windows: [TrackedWindow]
    let titles: [String]
    let activeWindow: TrackedWindow

    init(_ state: TabStripState) {
        paneID = state.paneID
        windows = state.tabs.map(\.window)
        titles = state.tabs.map(\.title)
        activeWindow = state.activeWindow
    }
}
