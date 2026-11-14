import AppKit
import Foundation
import QuickLookThumbnailing
import QuartzCore

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

// MARK: - Manager for Active Floating Cards
public final class FloatingCardManager: @unchecked Sendable {
    public static let shared = FloatingCardManager()
    
    private var activeWindows: [UUID: FloatingCardWindow] = [:]
    
    private init() {}
    
    public func showCard(fileURL: URL, metadata: FlickMetadata) {
        NSLog("🎴 [NoxFlick] FloatingCardManager.showCard called for: %@", fileURL.path)
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
        NSLog("🗑️ [NoxFlick] removeCard called for id: %@", id.uuidString)
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

// MARK: - Transient Bottom Portal Glow Window
public final class PortalGlowWindow: NSPanel {
    private let flareView = PortalFlareView()
    
    public init(centerX: CGFloat, bottomY: CGFloat) {
        let width: CGFloat = 380
        let height: CGFloat = 110
        let frame = NSRect(x: centerX - width / 2, y: bottomY, width: width, height: height)
        
        super.init(
            contentRect: frame,
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
        self.ignoresMouseEvents = true
        self.contentView = flareView
    }
    
    public func bloomAndDissipate(completion: (() -> Void)? = nil) {
        self.alphaValue = 0.0
        self.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 0.95
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.42
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().alphaValue = 0.0
            }, completionHandler: {
                self.orderOut(nil)
                completion?()
            })
        })
    }
}

// MARK: - Atmospheric Radial Flare View
public final class PortalFlareView: NSView {
    public override init(frame: NSRect) {
        super.init(frame: frame)
        self.wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        
        let colors = [
            NSColor(calibratedRed: 0.0, green: 0.96, blue: 1.0, alpha: 0.85).cgColor,  // Pure Cyan Core
            NSColor(calibratedRed: 0.54, green: 0.23, blue: 0.98, alpha: 0.55).cgColor, // Electric Violet
            NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.12, alpha: 0.0).cgColor   // Transparent
        ] as CFArray
        let locations: [CGFloat] = [0.0, 0.42, 1.0]
        
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else { return }
        
        ctx.saveGState()
        let radius = bounds.width * 0.45
        ctx.scaleBy(x: 1.0, y: bounds.height / (bounds.width * 0.45))
        ctx.drawRadialGradient(
            gradient,
            startCenter: CGPoint(x: bounds.midX, y: 0),
            startRadius: 0,
            endCenter: CGPoint(x: bounds.midX, y: 0),
            endRadius: radius,
            options: [.drawsAfterEndLocation]
        )
        ctx.restoreGState()
    }
}

// MARK: - Floating Card Window
public final class FloatingCardWindow: NSPanel {
    public let id: UUID
    public let fileURL: URL
    public let metadata: FlickMetadata
    private let onDismiss: () -> Void
    private let cardView: FloatingCardView
    private var portalWindow: PortalGlowWindow?
    
    private let windowWidth: CGFloat = 440
    private let windowHeight: CGFloat = 480
    private var targetOrigin: NSPoint = .zero
    private var initialX: CGFloat = 0
    private var entryY: CGFloat = 0
    
    public init(id: UUID, fileURL: URL, metadata: FlickMetadata, onDismiss: @escaping () -> Void) {
        self.id = id
        self.fileURL = fileURL
        self.metadata = metadata
        self.onDismiss = onDismiss
        
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let visibleFrame = screen.visibleFrame
        
        // Calculate true physical landing position based on aim angle and velocity
        let normalizedAim = metadata.aimX.clamped(to: -1.0...1.0)
        let aimRatio = (normalizedAim + 1.0) / 2.0 // 0.0 to 1.0
        
        let screenMarginX: CGFloat = 40
        let availableWidth = max(0, visibleFrame.width - (screenMarginX * 2) - windowWidth)
        let targetX = visibleFrame.minX + screenMarginX + (availableWidth * CGFloat(aimRatio))
        
        // Vertical landing height based on throw velocity
        let clampedVel = metadata.flickVelocity.clamped(to: 0.8...2.5)
        let velRatio = (clampedVel - 0.8) / (2.5 - 0.8) // 0.0 to 1.0
        let screenMarginY: CGFloat = 50
        let availableHeight = max(0, visibleFrame.height - (screenMarginY * 2) - windowHeight)
        let targetY = visibleFrame.minY + screenMarginY + (availableHeight * CGFloat(velRatio))
        
        self.targetOrigin = NSPoint(x: targetX, y: targetY)
        
        // Flight entry trajectory: starts below screen edge aligned with throw vector
        let flyAngleRad = (metadata.flickAngle.clamped(to: -35...35)) * .pi / 180.0
        let trajectoryXOffset = CGFloat(tan(flyAngleRad) * 180.0)
        let minXBound = visibleFrame.minX
        let maxXBound = max(visibleFrame.minX, visibleFrame.maxX - windowWidth)
        self.initialX = (targetX - trajectoryXOffset).clamped(to: minXBound...maxXBound)
        self.entryY = visibleFrame.minY
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
        NSLog("🚀 [NoxFlick] animateFlightEntrance targetOrigin: (%f, %f)", targetOrigin.x, targetOrigin.y)
        self.alphaValue = 0.0
        self.orderFrontRegardless()
        
        // 1. Play sound chime with stereo panning (aimX) and capped 50% max volume
        SoundManager.shared.playArrivalChime(aimX: metadata.aimX)
        
        // 2. Trigger bottom bezel entrance portal flare
        let portalCenter = self.initialX + (windowWidth / 2)
        let portal = PortalGlowWindow(centerX: portalCenter, bottomY: self.entryY)
        self.portalWindow = portal
        portal.bloomAndDissipate { [weak self] in
            self?.portalWindow = nil
        }
        
        // 3. Rotate card with physics throw tilt
        let angle = CGFloat(metadata.flickAngle.clamped(to: -30...30))
        cardView.setRotationAngle(angle)
        
        let targetRect = NSRect(origin: self.targetOrigin, size: CGSize(width: windowWidth, height: windowHeight))
        
        // 4. Smooth flight arrival curve (Apple fluid spring curve)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.48
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            self.animator().alphaValue = 1.0
            self.animator().setFrame(targetRect, display: true)
        }, completionHandler: { [weak self] in
            self?.cardView.pulseLandingGlow()
        })
    }
    
    public func dismissCard(deleteFile: Bool) {
        if deleteFile {
            try? FileManager.default.removeItem(at: fileURL)
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.orderOut(nil)
            self.onDismiss()
        })
    }
}

// MARK: - Premium Floating Card View with Multi-Tier Neon Glow
public final class FloatingCardView: NSView, NSDraggingSource {
    public weak var cardWindow: FloatingCardWindow?
    public let fileURL: URL
    public let metadata: FlickMetadata
    
    public var onClose: (() -> Void)?
    public var onDropped: (() -> Void)?
    
    // Core container hierarchy
    private let rotatableRootView = NSView()
    private let glowBackdropView = NSView()
    private let cardContainer = NSView()
    private let glassEffectView = NSVisualEffectView()
    private let borderOverlayView = NSView()
    private let borderLayer = CAGradientLayer()
    private let borderShapeMask = CAShapeLayer()
    
    // Sublayer glows
    private let ambientBloomLayer = CALayer()
    private let rimGlowLayer = CALayer()
    private let dropShadowLayer = CALayer()
    
    // Content Views
    private let headerView = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let previewImageView = NSImageView()
    private let footerView = NSView()
    private let sizeBadgeView = NSView()
    private let sizeLabel = NSTextField(labelWithString: "")
    private let dragHintLabel = NSTextField(labelWithString: "")
    
    private let cardWidth: CGFloat = 260
    private let cardHeight: CGFloat = 330
    private let cornerRadius: CGFloat = 18
    
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
        rotatableRootView.frameCenterRotation = angle
    }
    
    public func pulseLandingGlow() {
        let pulseAnim = CABasicAnimation(keyPath: "shadowOpacity")
        pulseAnim.fromValue = 0.95
        pulseAnim.toValue = 0.55
        pulseAnim.duration = 0.65
        pulseAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ambientBloomLayer.add(pulseAnim, forKey: "pulse")
        
        let rimPulse = CABasicAnimation(keyPath: "shadowOpacity")
        rimPulse.fromValue = 0.90
        rimPulse.toValue = 0.65
        rimPulse.duration = 0.65
        rimPulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
        rimGlowLayer.add(rimPulse, forKey: "rimPulse")
    }
    
    private func setupViews() {
        // 1. Center the rotatable root view inside the spacious 440x480 canvas
        let rootOriginX = (bounds.width - cardWidth) / 2
        let rootOriginY = (bounds.height - cardHeight) / 2
        let rootFrame = NSRect(x: rootOriginX, y: rootOriginY, width: cardWidth, height: cardHeight)
        
        rotatableRootView.frame = rootFrame
        rotatableRootView.wantsLayer = true
        addSubview(rotatableRootView)
        
        // 2. Multi-tier Atmospheric Neon Glow Backdrop (outside masksToBounds)
        glowBackdropView.frame = NSRect(origin: .zero, size: rootFrame.size)
        glowBackdropView.wantsLayer = true
        glowBackdropView.layer?.masksToBounds = false
        rotatableRootView.addSubview(glowBackdropView)
        
        setupNeonGlowLayers(for: glowBackdropView.layer!)
        
        // 3. Card Container with Frosted Glass & Obsidian Core
        cardContainer.frame = NSRect(origin: .zero, size: rootFrame.size)
        cardContainer.wantsLayer = true
        cardContainer.layer?.cornerRadius = cornerRadius
        cardContainer.layer?.masksToBounds = true
        rotatableRootView.addSubview(cardContainer)
        
        // Live macOS frosted glass blur
        glassEffectView.frame = cardContainer.bounds
        glassEffectView.autoresizingMask = [.width, .height]
        glassEffectView.blendingMode = .behindWindow
        glassEffectView.material = .hudWindow
        glassEffectView.state = .active
        cardContainer.addSubview(glassEffectView)
        
        // Deep obsidian tint overlay
        let tintView = NSView(frame: cardContainer.bounds)
        tintView.autoresizingMask = [.width, .height]
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.13, alpha: 0.88).cgColor
        cardContainer.addSubview(tintView)
        
        let cBounds = cardContainer.bounds
        
        // 4. Preview Image View (Middle)
        let previewY: CGFloat = 34
        let previewH: CGFloat = cBounds.height - 38 - 34
        previewImageView.frame = NSRect(x: 0, y: previewY, width: cBounds.width, height: previewH)
        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.wantsLayer = true
        previewImageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.15).cgColor
        cardContainer.addSubview(previewImageView)
        
        // 5. Header Bar (Frosted Translucent)
        headerView.frame = NSRect(x: 0, y: cBounds.height - 38, width: cBounds.width, height: 38)
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        cardContainer.addSubview(headerView)
        
        let headerLine = CALayer()
        headerLine.frame = CGRect(x: 0, y: 0, width: cBounds.width, height: 0.5)
        headerLine.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        headerView.layer?.addSublayer(headerLine)
        
        // File Title
        titleLabel.frame = NSRect(x: 14, y: 9, width: cBounds.width - 56, height: 20)
        titleLabel.stringValue = metadata.fileName
        titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingMiddle
        headerView.addSubview(titleLabel)
        
        // Close Button (Frosted Circle ✕)
        closeButton.frame = NSRect(x: cBounds.width - 32, y: 8, width: 22, height: 22)
        closeButton.title = "✕"
        closeButton.font = NSFont.systemFont(ofSize: 10.5, weight: .bold)
        closeButton.isBordered = false
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 11
        closeButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        closeButton.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        closeButton.layer?.borderWidth = 0.5
        closeButton.contentTintColor = .white
        closeButton.target = self
        closeButton.action = #selector(handleClose)
        headerView.addSubview(closeButton)
        
        // 6. Footer Bar (Frosted Glass)
        footerView.frame = NSRect(x: 0, y: 0, width: cBounds.width, height: 34)
        footerView.wantsLayer = true
        footerView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        cardContainer.addSubview(footerView)
        
        let footerLine = CALayer()
        footerLine.frame = CGRect(x: 0, y: 33.5, width: cBounds.width, height: 0.5)
        footerLine.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        footerView.layer?.addSublayer(footerLine)
        
        // Size Badge
        sizeBadgeView.frame = NSRect(x: 12, y: 7, width: 84, height: 20)
        sizeBadgeView.wantsLayer = true
        sizeBadgeView.layer?.cornerRadius = 6
        sizeBadgeView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        footerView.addSubview(sizeBadgeView)
        
        sizeLabel.frame = NSRect(x: 4, y: 2, width: 76, height: 16)
        sizeLabel.stringValue = formatBytes(metadata.fileSize)
        sizeLabel.alignment = .center
        sizeLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        sizeLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        sizeBadgeView.addSubview(sizeLabel)
        
        // Luminous Neon Drag Hint
        dragHintLabel.frame = NSRect(x: cBounds.width - 120, y: 7, width: 108, height: 20)
        dragHintLabel.stringValue = "Drag to save ➔"
        dragHintLabel.alignment = .right
        dragHintLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        dragHintLabel.textColor = NSColor(calibratedRed: 0.0, green: 0.96, blue: 1.0, alpha: 1.0)
        footerView.addSubview(dragHintLabel)
        
        // 7. Top-most Iridescent Neon Border Overlay (unobstructed by header/footer)
        borderOverlayView.frame = cardContainer.bounds
        borderOverlayView.autoresizingMask = [.width, .height]
        borderOverlayView.wantsLayer = true
        cardContainer.addSubview(borderOverlayView)
        setupIridescentBorder()
    }
    
    private func setupNeonGlowLayers(for hostLayer: CALayer) {
        let roundedPath = CGPath(roundedRect: CGRect(origin: .zero, size: CGSize(width: cardWidth, height: cardHeight)),
                                 cornerWidth: cornerRadius,
                                 cornerHeight: cornerRadius,
                                 transform: nil)
        
        // Layer 1: Ground Elevation Shadow
        dropShadowLayer.frame = CGRect(origin: .zero, size: CGSize(width: cardWidth, height: cardHeight))
        dropShadowLayer.shadowPath = roundedPath
        dropShadowLayer.shadowColor = NSColor.black.cgColor
        dropShadowLayer.shadowRadius = 24
        dropShadowLayer.shadowOpacity = 0.65
        dropShadowLayer.shadowOffset = CGSize(width: 0, height: -8)
        hostLayer.addSublayer(dropShadowLayer)
        
        // Layer 2: Atmospheric Deep Violet Neon Bloom
        ambientBloomLayer.frame = CGRect(origin: .zero, size: CGSize(width: cardWidth, height: cardHeight))
        ambientBloomLayer.shadowPath = roundedPath
        ambientBloomLayer.shadowColor = NSColor(calibratedRed: 0.55, green: 0.22, blue: 0.98, alpha: 1.0).cgColor
        ambientBloomLayer.shadowRadius = 36
        ambientBloomLayer.shadowOpacity = 0.60
        ambientBloomLayer.shadowOffset = CGSize(width: 0, height: -2)
        hostLayer.addSublayer(ambientBloomLayer)
        
        // Layer 3: Crisp Electric Cyan Inner Rim Radiance
        rimGlowLayer.frame = CGRect(origin: .zero, size: CGSize(width: cardWidth, height: cardHeight))
        rimGlowLayer.shadowPath = roundedPath
        rimGlowLayer.shadowColor = NSColor(calibratedRed: 0.0, green: 0.96, blue: 1.0, alpha: 1.0).cgColor
        rimGlowLayer.shadowRadius = 15
        rimGlowLayer.shadowOpacity = 0.80
        rimGlowLayer.shadowOffset = .zero
        hostLayer.addSublayer(rimGlowLayer)
    }
    
    private func setupIridescentBorder() {
        let cardRect = CGRect(origin: .zero, size: CGSize(width: cardWidth, height: cardHeight))
        
        borderLayer.frame = cardRect
        borderLayer.colors = [
            NSColor(calibratedRed: 0.0, green: 0.96, blue: 1.0, alpha: 0.95).cgColor,   // Electric Cyan
            NSColor(calibratedRed: 0.23, green: 0.51, blue: 0.96, alpha: 0.90).cgColor,  // Royal Azure
            NSColor(calibratedRed: 0.58, green: 0.28, blue: 0.98, alpha: 0.95).cgColor,  // Neon Violet
            NSColor(calibratedRed: 0.96, green: 0.25, blue: 0.65, alpha: 0.90).cgColor,  // Electric Magenta
            NSColor(calibratedRed: 0.0, green: 0.96, blue: 1.0, alpha: 0.95).cgColor    // Loop back to Cyan
        ]
        borderLayer.startPoint = CGPoint(x: 0.0, y: 1.0)
        borderLayer.endPoint = CGPoint(x: 1.0, y: 0.0)
        
        let strokePath = CGPath(roundedRect: cardRect.insetBy(dx: 1.0, dy: 1.0),
                                cornerWidth: cornerRadius,
                                cornerHeight: cornerRadius,
                                transform: nil)
        
        borderShapeMask.path = strokePath
        borderShapeMask.fillColor = nil
        borderShapeMask.strokeColor = NSColor.black.cgColor
        borderShapeMask.lineWidth = 2.0
        borderShapeMask.frame = cardRect
        
        borderLayer.mask = borderShapeMask
        borderOverlayView.layer?.addSublayer(borderLayer)
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
            size: CGSize(width: 340, height: 340),
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
    
    // Pass clicks through the transparent neon aura outside the card
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let pointInCard = cardContainer.convert(point, from: self)
        if !cardContainer.bounds.contains(pointInCard) {
            return nil
        }
        let hit = super.hitTest(point)
        if hit === borderOverlayView {
            return self
        }
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
        
        // Native macOS File Drag directly to Finder / Desktop / Apps
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
