import AppKit
import ApplicationServices

/// Draws the goal text in the middle of the menu bar on every screen.
///
/// macOS doesn't let apps put status items in the middle of the menu bar, so this
/// floats a small transparent window over the menu bar instead, and moves it out of
/// the way of the app menus (left), the notch, and other status items (right).
@MainActor
final class GoalOverlay {
    /// Space kept between the goal text and anything else in the menu bar.
    static let padding: CGFloat = 32
    /// Don't squeeze the goal into a gap narrower than this.
    static let minWidth: CGFloat = 80

    var onClick: (() -> Void)?
    /// Supplies the menu bar's current appearance so the text matches its color.
    var appearanceSource: (() -> NSAppearance?)?

    private var text: String?
    private var windows: [ObjectIdentifier: OverlayWindow] = [:]
    private var timer: Timer?

    init() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            // Give the new app's menus a moment to appear before measuring them.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { MainActor.assumeIsolated { self?.refresh() } }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Status items come and go without notifications, so re-check periodically.
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func setText(_ newText: String?) {
        text = newText
        refresh()
    }

    func refresh() {
        let screens = NSScreen.screens
        let liveIDs = Set(screens.map(ObjectIdentifier.init))
        for (id, window) in windows where !liveIDs.contains(id) {
            window.orderOut(nil)
            windows[id] = nil
        }

        guard let text, !text.isEmpty else {
            windows.values.forEach { $0.orderOut(nil) }
            return
        }

        let ownWindowNumbers = Set(windows.values.map(\.windowNumber))
        let statusItemRects = Self.statusItemRects(excluding: ownWindowNumbers)
        let menusRightOffset = Self.appMenusRightOffset()

        for screen in screens {
            let window = windows[ObjectIdentifier(screen)] ?? {
                let w = OverlayWindow()
                w.onClick = { [weak self] in self?.onClick?() }
                windows[ObjectIdentifier(screen)] = w
                return w
            }()

            let barHeight = Self.menuBarHeight(on: screen)
            window.label.font = NSFont.menuBarFont(ofSize: 0)
            window.label.stringValue = text
            window.appearance = appearanceSource?()

            let wanted = ceil(window.label.intrinsicContentSize.width) + 4
            guard let slot = Self.placement(width: wanted, on: screen,
                                            barHeight: barHeight,
                                            statusItemRects: statusItemRects,
                                            menusRightOffset: menusRightOffset) else {
                window.orderOut(nil)
                continue
            }
            let frame = NSRect(x: slot.minX, y: screen.frame.maxY - barHeight,
                               width: slot.width, height: barHeight)
            if window.frame != frame { window.setFrame(frame, display: true) }
            if !window.isVisible { window.orderFrontRegardless() }
        }
    }

    // MARK: Layout

    /// Picks the horizontal span for the goal text: as close to the screen's center as
    /// possible, inside a gap that's free of menus, the notch and status items.
    private static func placement(width: CGFloat, on screen: NSScreen, barHeight: CGFloat,
                                  statusItemRects: [CGRect], menusRightOffset: CGFloat?) -> (minX: CGFloat, width: CGFloat)? {
        let sf = screen.frame
        var blocked: [ClosedRange<CGFloat>] = []

        // App menus (Apple menu, app name, File, Edit, …) on the left.
        if let offset = menusRightOffset {
            blocked.append(sf.minX...(sf.minX + offset))
        } else {
            // Without Accessibility access we can't measure them; assume a typical width.
            blocked.append(sf.minX...(sf.minX + min(sf.width * 0.3, 420)))
        }

        // The camera notch.
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           right.minX > left.maxX {
            blocked.append((sf.minX + left.maxX)...(sf.minX + right.minX))
        }

        // Status items: everything from the leftmost one to the right edge.
        let menuBarBand = cgRect(fromScreenTop: sf, height: barHeight)
        let itemsHere = statusItemRects.filter { $0.intersects(menuBarBand) }
        if let leftmost = itemsHere.map(\.minX).min() {
            blocked.append(leftmost...sf.maxX)
        }

        // Free gaps = screen width minus blocked ranges, shrunk by padding on both sides.
        var gaps: [ClosedRange<CGFloat>] = []
        var cursor = sf.minX
        for range in blocked.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if range.lowerBound > cursor { gaps.append(cursor...range.lowerBound) }
            cursor = max(cursor, range.upperBound)
        }
        if cursor < sf.maxX { gaps.append(cursor...sf.maxX) }
        gaps = gaps.compactMap { g in
            let lo = g.lowerBound + padding, hi = g.upperBound - padding
            return hi - lo >= minWidth ? lo...hi : nil
        }
        guard !gaps.isEmpty else { return nil }

        let center = sf.midX
        func span(in gap: ClosedRange<CGFloat>) -> (minX: CGFloat, width: CGFloat) {
            let w = min(width, gap.upperBound - gap.lowerBound)
            let x = min(max(center - w / 2, gap.lowerBound), gap.upperBound - w)
            return (x, w)
        }
        func distance(_ s: (minX: CGFloat, width: CGFloat)) -> CGFloat { abs(s.minX + s.width / 2 - center) }

        // Prefer gaps where the whole goal fits; among those, the one closest to center.
        // If it fits nowhere, use the widest gap and let the text truncate.
        let fitting = gaps.filter { $0.upperBound - $0.lowerBound >= width }
        if let best = fitting.map(span).min(by: { distance($0) < distance($1) }) { return best }
        let widest = gaps.max { ($0.upperBound - $0.lowerBound) < ($1.upperBound - $1.lowerBound) }!
        return span(in: widest)
    }

    private static func menuBarHeight(on screen: NSScreen) -> CGFloat {
        if screen.safeAreaInsets.top > 0 { return screen.safeAreaInsets.top }
        let h = screen.frame.maxY - screen.visibleFrame.maxY
        return h > 0 ? h : NSStatusBar.system.thickness
    }

    /// Converts the top band of a screen (Cocoa coords) into CoreGraphics global coords.
    private static func cgRect(fromScreenTop sf: NSRect, height: CGFloat) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? sf.height
        return CGRect(x: sf.minX, y: primaryHeight - sf.maxY, width: sf.width, height: height)
    }

    /// Frames (CoreGraphics coords) of every status item window in the menu bar.
    private static func statusItemRects(excluding own: Set<Int>) -> [CGRect] {
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return info.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == statusLevel,
                  let number = w[kCGWindowNumber as String] as? Int, !own.contains(number),
                  let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width > 0, bounds.width < 600 else { return nil }
            return bounds
        }
    }

    /// How far from a screen's left edge the current app's menus extend, using
    /// Accessibility. Returns nil if we don't have Accessibility permission.
    private static func appMenusRightOffset() -> CGFloat? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.menuBarOwningApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef else { return nil }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement], !children.isEmpty else { return nil }

        var rightEdge: CGFloat = 0
        var leftEdge: CGFloat = .greatestFiniteMagnitude
        for child in children {
            guard let pos = axValue(child, kAXPositionAttribute, CGPoint.self, .cgPoint),
                  let size = axValue(child, kAXSizeAttribute, CGSize.self, .cgSize) else { continue }
            leftEdge = min(leftEdge, pos.x)
            rightEdge = max(rightEdge, pos.x + size.width)
        }
        guard rightEdge > 0 else { return nil }
        // The Apple menu sits at the left edge of whichever screen the menus were measured on.
        let screenMinX = NSScreen.screens.first { $0.frame.minX <= leftEdge && leftEdge < $0.frame.maxX }?.frame.minX ?? 0
        return rightEdge - screenMinX
    }

    private static func axValue<T>(_ element: AXUIElement, _ attribute: String, _: T.Type, _ type: AXValueType) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let value = ref, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AXValueGetValue(value as! AXValue, type, pointer) else { return nil }
        return pointer.pointee
    }
}

/// A transparent, click-through-except-for-the-text window that sits in the menu bar.
private final class OverlayWindow: NSPanel {
    let label = NSTextField(labelWithString: "")
    var onClick: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        // Show on every desktop, but not over full-screen apps (their menu bar is hidden).
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        label.lineBreakMode = .byTruncatingTail
        label.alignment = .center
        label.textColor = .labelColor
        label.cell?.truncatesLastVisibleLine = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let content = ClickView()
        content.onClick = { [weak self] in self?.onClick?() }
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        contentView = content
    }

    override var canBecomeKey: Bool { false }
}

private final class ClickView: NSView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }
}
