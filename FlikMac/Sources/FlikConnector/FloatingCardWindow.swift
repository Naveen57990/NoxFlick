import AppKit
import Foundation
import QuickLookThumbnailing

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

public final class FloatingCardManager: @unchecked Sendable {
    public static let shared = FloatingCardManager()
    
    private var activeWindows: [UUID: FloatingCardWindow] = [:]
    
    private init() {}
    
    public func showCard(fileURL: URL, metadata: FlickMetadata) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let id = UUID()
            let window = FloatingCardWindow(id: id, fileURL: fileURL, metadata: metadata) { [weak self] in
                self?.removeCard(id: id)
            }
            
            self.activeWindows[id] = window
            window.animateFlightEntrance()
        }
    }
    
    public func removeCard(id: UUID) {
        DispatchQueue.main.async { [weak self] in
            if let win = self?.activeWindows.removeValue(forKey: id) {
                win.orderOut(nil)
            }
        }
    }
    
    public func closeAll(deleteFiles: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for (id, win) in self.activeWindows {
                if deleteFiles {
                    try? FileManager.default.removeItem(at: win.fileURL)
                }
                win.orderOut(nil)
            }
            self.activeWindows.removeAll()
        }
    }
}

// MARK: - Floating Card Window
public final class FloatingCardWindow: NSPanel {
    public let id: UUID
    public let fileURL: URL
    public let metadata: FlickMetadata
    private let onDismiss: () -> Void
    private let cardView: FloatingCardView
    
    private let windowWidth: CGFloat = 380
    private let windowHeight: CGFloat = 420
    private var targetOrigin: NSPoint = .zero
    
    public init(id: UUID, fileURL: URL, metadata: FlickMetadata, onDismiss: @escaping () -> Void) {
        self.id = id
        self.fileURL = fileURL
        self.metadata = metadata
        self.onDismiss = onDismiss
        
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let visibleFrame = screen.visibleFrame
        
        // Calculate true landing position based on where user aimed!
        // aimX: -1.0 (left side of screen), 0 (center), +1.0 (right side of screen)
        let normalizedAim = metadata.aimX.clamped(to: -1.0...1.0)
        let aimRatio = (normalizedAim + 1.0) / 2.0 // 0.0 to 1.0
        
        let screenMarginX: CGFloat = 30
        let availableWidth = max(0, visibleFrame.width - (screenMarginX * 2) - windowWidth)
        let targetX = visibleFrame.minX + screenMarginX + (availableWidth * CGFloat(aimRatio))
        
        // Vertical landing height based on throw velocity:
        // Soft throw (~0.8 - 1.2) = lands lower down (~visibleFrame.minY + 50)
        // Hard throw (~2.0 - 2.6) = lands higher up (~visibleFrame.maxY - windowHeight - 50)
        let clampedVel = metadata.flickVelocity.clamped(to: 0.8...2.5)
        let velRatio = (clampedVel - 0.8) / (2.5 - 0.8) // 0.0 to 1.0
        let screenMarginY: CGFloat = 40
        let availableHeight = max(0, visibleFrame.height - (screenMarginY * 2) - windowHeight)
        let targetY = visibleFrame.minY + screenMarginY + (availableHeight * CGFloat(velRatio))
        
        self.targetOrigin = NSPoint(x: targetX, y: targetY)
        
        // Flight entry trajectory: starts below screen edge aligned with throw trajectory
        let flyAngleRad = (metadata.flickAngle.clamped(to: -35...35)) * .pi / 180.0
        let trajectoryXOffset = CGFloat(tan(flyAngleRad) * 160.0)
        let minXBound = visibleFrame.minX
        let maxXBound = max(visibleFrame.minX, visibleFrame.maxX - windowWidth)
        let initialX = (targetX - trajectoryXOffset).clamped(to: minXBound...maxXBound)
        let initialY = visibleFrame.minY - windowHeight - 40
        
        let initialRect = NSRect(
            x: initialX,
            y: initialY,
            width: windowWidth,
            height: windowHeight
        )
        
        self.cardView = FloatingCardView(
            frame: NSRect(origin: .zero, size: initialRect.size),
            fileURL: fileURL,
            metadata: metadata
        )
        
        super.init(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.title = metadata.fileName
        
        self.contentView = cardView
        
        cardView.cardWindow = self
        cardView.onClose = { [weak self] in
            self?.dismissCard(deleteFile: true)
        }
        cardView.onDropped = { [weak self] in
            self?.dismissCard(deleteFile: false)
        }
    }
    
    public func animateFlightEntrance() {
        self.alphaValue = 0.0
        self.orderFrontRegardless()
        
        // Rotate the card container inside the spacious window so corners never clip!
        let angle = CGFloat(metadata.flickAngle.clamped(to: -30...30))
        cardView.setRotationAngle(angle)
        
        let targetRect = NSRect(origin: self.targetOrigin, size: CGSize(width: windowWidth, height: windowHeight))
        
        // Smooth physics-based flight arrival: flies up from bottom to target position
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.15, 0.85, 0.25, 1.0)
            self.animator().alphaValue = 1.0
            self.animator().setFrame(targetRect, display: true)
        }
    }
    
    public func dismissCard(deleteFile: Bool) {
        if deleteFile {
            try? FileManager.default.removeItem(at: fileURL)
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
            self.onDismiss()
        })
    }
}

// MARK: - Floating Card View
public final class FloatingCardView: NSView, NSDraggingSource {
    public weak var cardWindow: FloatingCardWindow?
    public let fileURL: URL
    public let metadata: FlickMetadata
    
    public var onClose: (() -> Void)?
    public var onDropped: (() -> Void)?
    
    private let cardContainer = NSView()
    private let headerView = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let previewImageView = NSImageView()
    private let footerView = NSView()
    private let sizeLabel = NSTextField(labelWithString: "")
    private let dragHintLabel = NSTextField(labelWithString: "")
    
    private let cardWidth: CGFloat = 250
    private let cardHeight: CGFloat = 320
    
    private var dragStartWindowOrigin: NSPoint = .zero
    private var initialMouseLocation: NSPoint = .zero
    private var isDraggingWindow = false
    
    public init(frame: NSRect, fileURL: URL, metadata: FlickMetadata) {
        self.fileURL = fileURL
        self.metadata = metadata
        super.init(frame: frame)
        
        self.wantsLayer = true
        setupViews()
        loadThumbnail()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func setRotationAngle(_ angle: CGFloat) {
        cardContainer.frameCenterRotation = angle
    }
    
    private func setupViews() {
        // Center the 250x320 card inside the 340x400 window so rotations up to 35 deg NEVER clip
        let cardOriginX = (bounds.width - cardWidth) / 2
        let cardOriginY = (bounds.height - cardHeight) / 2
        cardContainer.frame = NSRect(x: cardOriginX, y: cardOriginY, width: cardWidth, height: cardHeight)
        cardContainer.wantsLayer = true
        cardContainer.layer?.cornerRadius = 16
        cardContainer.layer?.masksToBounds = true
        cardContainer.layer?.backgroundColor = NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.14, alpha: 0.95).cgColor
        cardContainer.layer?.borderColor = NSColor(calibratedRed: 0.49, green: 0.23, blue: 0.93, alpha: 0.8).cgColor
        cardContainer.layer?.borderWidth = 1.5
        addSubview(cardContainer)
        
        // Deep Card Shadow
        self.shadow = NSShadow()
        self.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.65)
        self.shadow?.shadowOffset = NSSize(width: 0, height: -8)
        self.shadow?.shadowBlurRadius = 22
        
        let cBounds = cardContainer.bounds
        
        // 1. Header Bar (Height 36)
        headerView.frame = NSRect(x: 0, y: cBounds.height - 36, width: cBounds.width, height: 36)
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        cardContainer.addSubview(headerView)
        
        // File Title
        titleLabel.frame = NSRect(x: 12, y: 8, width: cBounds.width - 50, height: 20)
        titleLabel.stringValue = metadata.fileName
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingMiddle
        headerView.addSubview(titleLabel)
        
        // Close Button (✕)
        closeButton.frame = NSRect(x: cBounds.width - 32, y: 7, width: 22, height: 22)
        closeButton.title = "✕"
        closeButton.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        closeButton.isBordered = false
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 11
        closeButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        closeButton.contentTintColor = .white
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        headerView.addSubview(closeButton)
        
        // 2. Footer Bar (Height 32)
        footerView.frame = NSRect(x: 0, y: 0, width: cBounds.width, height: 32)
        footerView.wantsLayer = true
        footerView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        cardContainer.addSubview(footerView)
        
        sizeLabel.frame = NSRect(x: 12, y: 6, width: 90, height: 20)
        sizeLabel.stringValue = formatBytes(metadata.fileSize)
        sizeLabel.font = NSFont.systemFont(ofSize: 11)
        sizeLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        footerView.addSubview(sizeLabel)
        
        dragHintLabel.frame = NSRect(x: cBounds.width - 110, y: 6, width: 98, height: 20)
        dragHintLabel.stringValue = "Drag to save ➔"
        dragHintLabel.alignment = .right
        dragHintLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        dragHintLabel.textColor = NSColor(calibratedRed: 0.02, green: 0.71, blue: 0.83, alpha: 1.0)
        footerView.addSubview(dragHintLabel)
        
        // 3. Preview Image View (Middle)
        let previewY: CGFloat = 32
        let previewH: CGFloat = cBounds.height - 36 - 32
        previewImageView.frame = NSRect(x: 0, y: previewY, width: cBounds.width, height: previewH)
        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.wantsLayer = true
        previewImageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.2).cgColor
        cardContainer.addSubview(previewImageView)
    }
    
    private func loadThumbnail() {
        let ext = fileURL.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic", "webp", "gif"].contains(ext) {
            if let img = NSImage(contentsOf: fileURL) {
                previewImageView.image = img
                return
            }
        }
        
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: CGSize(width: 320, height: 320),
            scale: NSScreen.main?.backingScaleFactor ?? 2.0,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateRepresentations(for: request) { [weak self] rep, _, _ in
            if let image = rep?.nsImage {
                DispatchQueue.main.async {
                    self?.previewImageView.image = image
                }
            } else {
                DispatchQueue.main.async {
                    self?.previewImageView.image = NSWorkspace.shared.icon(forFile: self?.fileURL.path ?? "")
                }
            }
        }
    }
    
    @objc private func handleClose() {
        onClose?()
    }
    
    // Only intercept mouse events that actually land inside the rotated card container!
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let pointInCard = cardContainer.convert(point, from: self)
        if !cardContainer.bounds.contains(pointInCard) {
            return nil // Transparent padding: clicks pass directly through to underlying apps!
        }
        
        let hit = super.hitTest(point)
        return hit ?? self
    }
    
    // MARK: - Native Dragging (NSDraggingSource)
    public override func mouseDown(with event: NSEvent) {
        let pointInView = convert(event.locationInWindow, from: nil)
        let pointInCard = cardContainer.convert(pointInView, from: self)
        let pointInHeader = headerView.convert(pointInCard, from: cardContainer)
        
        initialMouseLocation = event.locationInWindow
        dragStartWindowOrigin = cardWindow?.frame.origin ?? .zero
        
        if headerView.bounds.contains(pointInHeader) {
            isDraggingWindow = true
        } else {
            isDraggingWindow = false
        }
    }
    
    public override func mouseDragged(with event: NSEvent) {
        if isDraggingWindow {
            guard let window = cardWindow else { return }
            let currentMouseLocation = NSEvent.mouseLocation
            let deltaX = currentMouseLocation.x - (dragStartWindowOrigin.x + initialMouseLocation.x)
            let deltaY = currentMouseLocation.y - (dragStartWindowOrigin.y + initialMouseLocation.y)
            window.setFrameOrigin(NSPoint(x: dragStartWindowOrigin.x + deltaX, y: dragStartWindowOrigin.y + deltaY))
            return
        }
        
        // Start Native macOS File Drag directly to Finder / Desktop / Apps!
        let distance = hypot(event.locationInWindow.x - initialMouseLocation.x, event.locationInWindow.y - initialMouseLocation.y)
        if distance > 4.0 {
            startFileDrag(with: event)
        }
    }
    
    private func startFileDrag(with event: NSEvent) {
        let pasteboardItem = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        let dragBounds = previewImageView.bounds
        let snapshot = previewImageView.image ?? NSWorkspace.shared.icon(forFile: fileURL.path)
        pasteboardItem.setDraggingFrame(previewImageView.convert(dragBounds, to: self), contents: snapshot)
        
        beginDraggingSession(with: [pasteboardItem], event: event, source: self)
    }
    
    public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }
    
    public func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation != [] {
            DispatchQueue.main.async { [weak self] in
                self?.onDropped?()
            }
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
