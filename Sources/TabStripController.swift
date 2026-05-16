import AppKit

package struct TabStripState {
    let frame: CGRect
    let titles: [String]
    let activeIndex: Int
}

package final class TabStripController: NSObject {
    package static let shared = TabStripController()

    private var panel: NSPanel?
    private var container: NSView?
    private var stack: NSStackView?
    private var lastTitles: [String] = []
    private var lastActiveIndex: Int = -1

    private override init() {}

    package func update(_ state: TabStripState?) {
        DispatchQueue.main.async {
            guard let state, state.titles.count > 1 else {
                self.panel?.orderOut(nil)
                self.lastTitles = []
                self.lastActiveIndex = -1
                return
            }

            let panel = self.ensurePanel()
            self.position(panel: panel, for: state)
            if self.lastTitles != state.titles || self.lastActiveIndex != state.activeIndex {
                self.rebuildTabs(titles: state.titles, activeIndex: state.activeIndex)
                self.lastTitles = state.titles
                self.lastActiveIndex = state.activeIndex
            }
            panel.orderFrontRegardless()
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 28),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let container = NSView(frame: panel.contentView?.bounds ?? .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        container.layer?.cornerRadius = 7
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.75).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fillEqually
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        panel.contentView = container
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])

        self.panel = panel
        self.container = container
        self.stack = stack
        return panel
    }

    private func position(panel: NSPanel, for state: TabStripState) {
        let pane = WindowManager.appKitRect(fromWindowRect: state.frame)
        let height: CGFloat = 30
        let width = max(120, min(pane.width - 16, CGFloat(state.titles.count) * 92 + 10))
        let x = pane.minX + (pane.width - width) / 2
        let y = pane.maxY - height - 8
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func rebuildTabs(titles: [String], activeIndex: Int) {
        guard let stack else { return }
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for (index, title) in titles.enumerated() {
            let button = NSButton(title: title, target: self, action: #selector(selectTab(_:)))
            button.tag = index
            button.isBordered = false
            button.font = .systemFont(ofSize: 11, weight: index == activeIndex ? .semibold : .regular)
            button.contentTintColor = index == activeIndex ? .labelColor : .secondaryLabelColor
            button.wantsLayer = true
            button.layer?.cornerRadius = 5
            button.layer?.backgroundColor = index == activeIndex
                ? NSColor.controlAccentColor.withAlphaComponent(0.20).cgColor
                : NSColor.clear.cgColor
            button.cell?.lineBreakMode = .byTruncatingTail
            stack.addArrangedSubview(button)
        }
    }

    @objc private func selectTab(_ sender: NSButton) {
        WorkspaceManager.shared.activateTab(index: sender.tag)
    }
}
