import Foundation

package enum Layout {
    case tile
    case monocle
}

package enum Tiler {
    package static func calculateFrames(count: Int, screen: CGRect, layout: Layout) -> [CGRect] {
        guard count > 0 else { return [] }
        switch layout {
        case .tile: return tileFrames(count: count, screen: screen)
        case .monocle: return monocleFrames(count: count, screen: screen)
        }
    }

    static func tile(windows: [TrackedWindow], screen: CGRect, layout: Layout) {
        let frames = calculateFrames(count: windows.count, screen: screen, layout: layout)
        for (i, frame) in frames.enumerated() {
            windows[i].setFrame(frame)
        }
    }

    private static func tileFrames(count: Int, screen: CGRect) -> [CGRect] {
        if count == 1 {
            return [screen]
        }

        var result: [CGRect] = []
        result.reserveCapacity(count)
        let masterWidth = floor(screen.width * Config.shared.masterRatio)
        let gap = max(Config.shared.windowGap, 0)
        let horizontalGap = min(gap, max(screen.width - 1, 0))
        let masterInset = floor(horizontalGap / 2)
        let stackInset = horizontalGap - masterInset

        result.append(CGRect(
            x: screen.origin.x, y: screen.origin.y,
            width: max(masterWidth - masterInset, 0), height: screen.height
        ))

        let stackCount = count - 1
        let stackX = screen.origin.x + masterWidth + stackInset
        let stackWidth = max(screen.maxX - stackX, 0)
        let verticalGap = stackCount > 1
            ? min(gap, max(screen.height / CGFloat(stackCount - 1), 0))
            : 0
        let availableStackHeight = max(screen.height - verticalGap * CGFloat(stackCount - 1), 0)
        let stackHeight = floor(availableStackHeight / CGFloat(stackCount))

        for i in 1..<count {
            let y = screen.origin.y + CGFloat(i - 1) * (stackHeight + verticalGap)
            let h = (i == count - 1)
                ? screen.maxY - y
                : stackHeight
            result.append(CGRect(
                x: stackX, y: y,
                width: stackWidth, height: max(h, 0)
            ))
        }
        return result
    }

    private static func monocleFrames(count: Int, screen: CGRect) -> [CGRect] {
        Array(repeating: screen, count: count)
    }
}
