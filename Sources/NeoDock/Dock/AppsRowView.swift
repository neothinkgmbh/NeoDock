import AppKit
import NeoDockKit
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

/// Die App-Reihe wie im macOS-Dock: jedes Icon ist eine Core-Animation-Ebene. Ein Display-Link
/// liest pro Bild die Mausposition und setzt nur Größe und Lage der Ebenen — SwiftUI rechnet beim
/// Überfahren nichts neu. Die View ist breiter und höher als die Reihe in Ruhe, damit vergrößerte
/// Icons Klicks und Züge bekommen; außerhalb der Icons lässt sie Ereignisse durch (hitTest).
final class AppsRowView: NSView, NSDraggingSource {
    // MARK: Eingaben (aus SwiftUI)
    var apps: [DockApp] = [] { didSet { if apps != oldValue { rebuildLayers() } } }
    var iconSize: CGFloat = DockMetrics.icon { didSet { if iconSize != oldValue { rebuildLayers() } } }
    var edge: DockEdge = .bottom { didSet { if edge != oldValue { rebuildLayers() } } }
    var maxScale: CGFloat = 1.6
    /// Apps, deren Icon gerade durchgehend hüpft: sie starten oder wollen Aufmerksamkeit.
    var bouncing: Set<String> = [] {
        didSet {
            guard bouncing != oldValue else { return }
            let now = CACurrentMediaTime()
            for key in bouncing.subtracting(oldValue) { startHop(key, at: now) }
            // Fertig: der angefangene Hüpfer läuft noch zu Ende, dann ruht das Icon.
            for key in oldValue.subtracting(bouncing) {
                if let start = hops[key] { startHop(key, at: now - (now - start).truncatingRemainder(dividingBy: Self.hopPeriod)) }
            }
        }
    }
    /// Kennzahlen je App-Pfad (aus dem macOS-Dock), z. B. ungelesene Mails.
    var badges: [String: String] = [:] { didSet { if badges != oldValue { updateBadges() } } }
    /// Nachgespielter Zeiger (Prüfschalter), in Koordinaten der Reihe in Ruhe; nil = echte Maus.
    var simulatedPointer: CGFloat? { didSet { if simulatedPointer != oldValue { startLink() } } }
    weak var model: DockModel?

    // MARK: Zustand
    private var iconLayers: [CALayer] = []
    private var dotLayers: [CALayer] = []
    private var badgeLayers: [BadgeLayer] = []
    private var images: [String: (normal: CGImage, pressed: CGImage)] = [:]
    private var link: CADisplayLink?
    private var strength: CGFloat = 0
    private var pointer: CGFloat?
    private var lastTimestamp: CFTimeInterval = 0
    /// Laufende Sprünge: App-Pfad → Startzeit des aktuellen Sprungs.
    private var hops: [String: CFTimeInterval] = [:]
    private var pressedIndex: Int?
    private var mouseDownPoint: CGPoint = .zero
    private var draggedKey: String?
    private var dropTargetIndex: Int?
    private var visibleFrames: [CGRect] = []
    /// Klickflächen: bei einem hüpfenden Icon die ganze Spalte in fester Höhe. Am aktuellen Hub
    /// hängend sänke die Fläche zwischen Drücken und Loslassen unter dem Zeiger weg.
    private var hitFrames: [CGRect] = []
    /// Prüfschalter NEODOCK_LOG_BOUNCE=1: protokolliert die echte Hubhöhe je Bild.
    private static let logsBounce = ProcessInfo.processInfo.environment["NEODOCK_LOG_BOUNCE"] == "1"
    private let nameTag = NameTagView()
    private var nameTagSize: NSSize = .zero

    /// Bildstatistik für den Prüfschalter: Bilder, verpasste Bilder, längste Arbeit pro Bild.
    nonisolated(unsafe) static var stats = (frames: 0, missed: 0, maxWorkMs: 0.0)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        registerForDraggedTypes([NSPasteboard.PasteboardType(UTType.neoDockItem.identifier), .fileURL])
        nameTag.isHidden = true
        addSubview(nameTag)
        if Self.logsBounce { Task { [weak self] in await self?.logHopHeights() } }
    }

    required init?(coder: NSCoder) { fatalError("nicht aus Interface Builder") }

    override var isFlipped: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    // MARK: Geometrie

    private var step: CGFloat { iconSize + DockMetrics.iconSpacing }
    private var restWidth: CGFloat { apps.isEmpty ? 0 : CGFloat(apps.count) * step - DockMetrics.iconSpacing }
    private var restStart: CGFloat { (mainLength - restWidth) / 2 }
    private func restCenter(_ i: Int) -> CGFloat { restStart + CGFloat(i) * step + iconSize / 2 }

    // Gerechnet wird entlang der Hauptachse m: Sie wächst mit dem Index, unten nach rechts, an der
    // Seite nach unten. Erst diese Helfer setzen sie in Punkte der View um.
    private var mainLength: CGFloat { edge.isVertical ? bounds.height : bounds.width }
    private func main(of point: CGPoint) -> CGFloat { edge.isVertical ? bounds.height - point.y : point.x }

    /// Fläche um m, von der Bildschirmkante aus `depth` tief.
    private func rect(around m: CGFloat, length: CGFloat, depth: CGFloat) -> CGRect {
        switch edge {
        case .bottom: CGRect(x: m - length / 2, y: 0, width: length, height: depth)
        case .left: CGRect(x: 0, y: bounds.height - m - length / 2, width: depth, height: length)
        case .right: CGRect(x: bounds.width - depth, y: bounds.height - m - length / 2, width: depth, height: length)
        }
    }

    private func iconPosition(_ m: CGFloat) -> CGPoint {
        switch edge {
        case .bottom: CGPoint(x: m, y: 0)
        case .left: CGPoint(x: 0, y: bounds.height - m)
        case .right: CGPoint(x: bounds.width, y: bounds.height - m)
        }
    }

    /// Der Laufpunkt liegt auf der Seite des Bildschirmrands.
    private func dotPosition(_ m: CGFloat) -> CGPoint {
        let inset = DockMetrics.runDot + Space.xxs
        return switch edge {
        case .bottom: CGPoint(x: m, y: -inset)
        case .left: CGPoint(x: -inset, y: bounds.height - m)
        case .right: CGPoint(x: bounds.width + inset, y: bounds.height - m)
        }
    }

    private var iconAnchor: CGPoint {
        switch edge {
        case .bottom: CGPoint(x: 0.5, y: 0)
        case .left: CGPoint(x: 0, y: 0.5)
        case .right: CGPoint(x: 1, y: 0.5)
        }
    }

    /// An der Seite ist die View des Namensschilds wegen breit; vergrößert wird nur nahe den Icons.
    private var hoverArea: CGRect {
        let reach = iconSize * maxScale
        return switch edge {
        case .bottom: bounds
        case .left: CGRect(x: 0, y: 0, width: reach, height: bounds.height)
        case .right: CGRect(x: bounds.width - reach, y: 0, width: reach, height: bounds.height)
        }
    }

    override func layout() {
        super.layout()
        applyLayout(animated: false)
    }

    // MARK: Ebenen

    private func rebuildLayers() {
        // Ein Hüpfer ohne Icon endet nie von selbst und hielte den Display-Link am Laufen.
        hops = hops.filter { key, _ in apps.contains { $0.key == key } }
        iconLayers.forEach { $0.removeFromSuperlayer() }
        dotLayers.forEach { $0.removeFromSuperlayer() }
        iconLayers = apps.map { app in
            let l = CALayer()
            l.anchorPoint = iconAnchor
            l.contentsGravity = .resizeAspect
            l.contents = image(for: app).normal
            l.actions = Self.noActions
            layer?.addSublayer(l)
            return l
        }
        dotLayers = apps.map { app in
            let d = CALayer()
            d.cornerRadius = DockMetrics.runDot / 2
            d.bounds = CGRect(x: 0, y: 0, width: DockMetrics.runDot, height: DockMetrics.runDot)
            d.isHidden = !app.isRunning
            d.actions = Self.noActions
            layer?.addSublayer(d)
            return d
        }
        // Plakette als Unterebene des Icons: wächst bei der Vergrößerung mit und hüpft mit.
        badgeLayers = iconLayers.map { icon in
            let badge = BadgeLayer()
            icon.addSublayer(badge)
            return badge
        }
        updateBadges()
        updateDotColor()
        applyLayout(animated: false)
        updateTrackingAreas()
        // Neue Ebenen, gleiche Sprünge: die Startzeit hält die Bahn in Phase.
        hops.keys.forEach(addHopAnimation)
    }

    private func updateBadges() {
        let scale = (window?.backingScaleFactor ?? 2) * DockSettings.scaleRange.upperBound
        for (i, badge) in badgeLayers.enumerated() where apps.indices.contains(i) {
            badge.update(text: badges[apps[i].key], iconSize: iconSize, contentsScale: scale)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateDotColor()
    }

    private func updateDotColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color = NSColor.labelColor.withAlphaComponent(0.7).cgColor
            dotLayers.forEach { $0.backgroundColor = color }
        }
    }

    static let noActions: [String: CAAction] = ["position": NSNull(), "bounds": NSNull(), "transform": NSNull(),
                                                 "contents": NSNull(), "opacity": NSNull(), "hidden": NSNull()]

    /// Icon in voller Vergrößerung gerastert, damit es scharf bleibt; dazu die abgedunkelte Fassung.
    private func image(for app: DockApp) -> (normal: CGImage, pressed: CGImage) {
        let scale = window?.backingScaleFactor ?? 2
        let px = (iconSize * DockSettings.scaleRange.upperBound * scale).rounded()
        let cacheKey = "\(app.key)@\(Int(px))"
        if let cached = images[cacheKey] { return cached }
        var rect = CGRect(x: 0, y: 0, width: px, height: px)
        let normal = app.icon.cgImage(forProposedRect: &rect, context: nil, hints: nil) ?? Self.emptyImage
        let pressed = Self.darkened(normal)
        images[cacheKey] = (normal, pressed)
        return (normal, pressed)
    }

    static let emptyImage: CGImage = {
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }()

    private static func darkened(_ image: CGImage) -> CGImage {
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.draw(image, in: rect)
        ctx.setBlendMode(.sourceAtop)
        ctx.setFillColor(NSColor.black.withAlphaComponent(DockMetrics.pressedShade).cgColor)
        ctx.fill(rect)
        return ctx.makeImage() ?? image
    }

    // MARK: Display-Link — pro Bild Mausposition lesen, Ebenen setzen

    private func startLink() {
        if link == nil, window != nil {
            let l = displayLink(target: self, selector: #selector(frameTick(_:)))
            l.add(to: .main, forMode: .common)
            link = l
            lastTimestamp = 0
        }
        link?.isPaused = false
    }

    private func stopLink() {
        link?.isPaused = true
        lastTimestamp = 0
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { link?.invalidate(); link = nil }
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        addTrackingArea(edge.isVertical
            ? NSTrackingArea(rect: hoverArea, options: options, owner: self, userInfo: nil)
            : NSTrackingArea(rect: .zero, options: options.union(.inVisibleRect), owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { startLink() }

    @objc private func frameTick(_ link: CADisplayLink) {
        let workStart = CACurrentMediaTime()
        let dt: CFTimeInterval
        if lastTimestamp == 0 { dt = link.duration } else {
            dt = link.timestamp - lastTimestamp
            Self.stats.frames += 1
            if dt > link.duration * 1.5 { Self.stats.missed += 1 }
        }
        lastTimestamp = link.timestamp

        let hovering = currentPointer()
        if let x = hovering { pointer = x }
        let target: CGFloat = hovering == nil ? 0 : 1
        strength += (target - strength) * CGFloat(1 - exp(-dt / DockMetrics.magnifyEase))
        if abs(target - strength) < 0.002 { strength = target }

        applyLayout(animated: false)

        let busy = strength > 0 || draggedKey != nil
        if !busy, hovering == nil { stopLink() }
        Self.stats.maxWorkMs = max(Self.stats.maxWorkMs, (CACurrentMediaTime() - workStart) * 1000)
    }

    /// Zeiger in View-Koordinaten, solange er über der View ist; sonst nil.
    private func currentPointer() -> CGFloat? {
        if let simulated = simulatedPointer { return restStart + simulated }
        guard let window else { return nil }
        let local = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        return hoverArea.contains(local) ? main(of: local) : nil
    }

    private func applyLayout(animated: Bool) {
        guard !iconLayers.isEmpty else { model?.magnify.setExtra(0); return }
        let centers = apps.indices.map { Double(restCenter($0)) }
        let peak = 1 + (Double(maxScale) - 1) * Double(strength)
        let scales = Magnification.scales(pointerX: pointer.map(Double.init), centers: centers, maxScale: peak,
                                          reach: Double(iconSize) * DockMetrics.reachInIcons)
        let r = Magnification.shifts(scales: scales, base: Double(iconSize))
        var frames: [CGRect] = []
        var hits: [CGRect] = []
        var restingTops: [CGFloat] = []
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        for (i, l) in iconLayers.enumerated() {
            let s = CGFloat(scales[i])
            let m = restCenter(i) + CGFloat(r.shifts[i])
            l.bounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
            l.position = iconPosition(m)
            let dropBoost: CGFloat = dropTargetIndex == i ? DockMetrics.dropTargetScale : 1
            l.transform = CATransform3DMakeScale(s * dropBoost, s * dropBoost, 1)
            l.opacity = apps[i].key == draggedKey ? 0.35 : 1
            l.contents = pressedIndex == i ? image(for: apps[i]).pressed : image(for: apps[i]).normal
            dotLayers[i].position = dotPosition(m)
            dotLayers[i].isHidden = !apps[i].isRunning
            frames.append(rect(around: m, length: iconSize * s, depth: iconSize * s))
            let hopRoom = hops[apps[i].key] == nil ? 0 : iconSize * DockMetrics.bounceHeight
            hits.append(rect(around: m, length: iconSize * s, depth: iconSize * s + hopRoom))
            restingTops.append(iconSize * s)
        }
        CATransaction.commit()
        visibleFrames = frames
        hitFrames = hits
        model?.magnify.setExtra(CGFloat(r.extra))
        updateNameTag(frames: frames, restingTops: restingTops)
    }

    /// Das Schild steht über dem Icon, springt aber nicht mit (wie im macOS-Dock) — sonst stößt es
    /// beim Hüpfen an die Fensterkante und wird abgeschnitten.
    private func updateNameTag(frames: [CGRect], restingTops: [CGFloat]) {
        guard strength > 0.5, draggedKey == nil, let x = pointer, simulatedPointer != nil || window != nil else {
            nameTag.isHidden = true
            return
        }
        // Nächstes Icon zum Zeiger (ohne Lücken), damit das Schild nicht flackert.
        let index = min(apps.count - 1, max(0, Int(((x - restStart - iconSize / 2) / step).rounded())))
        if nameTag.text != apps[index].name {
            nameTag.text = apps[index].name
            nameTagSize = nameTag.fittingSize
        }
        let size = nameTagSize
        let frame = frames[index]
        let gap = restingTops[index] + Space.sm
        // An der Seite begrenzt das Fenster die Breite, sehr lange Namen werden gekürzt.
        let width = min(size.width, bounds.width - gap)
        nameTag.frame = switch edge {
        case .bottom: CGRect(x: frame.midX - size.width / 2, y: gap, width: size.width, height: size.height)
        case .left: CGRect(x: gap, y: frame.midY - size.height / 2, width: width, height: size.height)
        case .right: CGRect(x: bounds.width - gap - width, y: frame.midY - size.height / 2, width: width, height: size.height)
        }
        nameTag.isHidden = false
    }

    // MARK: Hüpfen

    /// Dauer eines Sprungs. Die Bahn ist eine Wurfparabel wie beim macOS-Dock: oben langsam
    /// wendend, unten hart aufsetzend — kein Sinus. Sie läuft als Animation im Render-Server, die
    /// App rechnet dabei kein Bild. Eine Anfrage kann stundenlang hüpfen.
    private static let hopPeriod: CFTimeInterval = DockMetrics.bouncePeriod
    private static let hopSegments = 24
    private static let hopCurve = (0...hopSegments).map { parabola(hopPeriod * Double($0) / Double(hopSegments)) }

    /// Höhe 0…1 eines Sprungs zum Zeitpunkt t (0 ≤ t < Periode): 4·u·(1−u).
    private static func parabola(_ t: CFTimeInterval) -> CGFloat {
        let u = t / hopPeriod
        return CGFloat(4 * u * (1 - u))
    }

    func hop(_ key: String) {
        guard !bouncing.contains(key) else { return }
        startHop(key, at: CACurrentMediaTime())
    }

    /// Dauerhüpfen, solange der Schlüssel in `bouncing` steht; sonst genau dieser eine Sprung.
    private func startHop(_ key: String, at start: CFTimeInterval) {
        hops[key] = start
        addHopAnimation(key)
        applyLayout(animated: false)
        guard !bouncing.contains(key) else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(start + Self.hopPeriod - CACurrentMediaTime()))
            guard let self, self.hops[key] == start, !self.bouncing.contains(key) else { return }
            self.hops[key] = nil
            self.applyLayout(animated: false)
        }
    }

    private func addHopAnimation(_ key: String) {
        guard let start = hops[key], let index = apps.firstIndex(where: { $0.key == key }) else { return }
        let height = iconSize * DockMetrics.bounceHeight
        let hop = CAKeyframeAnimation(keyPath: edge.isVertical ? "position.x" : "position.y")
        hop.values = Self.hopCurve.map { $0 * (edge == .right ? -height : height) }
        hop.duration = Self.hopPeriod
        hop.beginTime = start
        hop.repeatCount = bouncing.contains(key) ? .infinity : 1
        hop.isAdditive = true
        iconLayers[index].add(hop, forKey: "hop")
    }


    /// Prüfschalter: Die Animation läuft ohne die App, die Höhe steht in der Präsentationsebene.
    private func logHopHeights() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
            for (app, layer) in zip(apps, iconLayers) where hops[app.key] != nil {
                guard let shown = layer.presentation()?.position else { continue }
                NSLog("NeoDock HOP \(app.name) \(Int(abs(shown.x - layer.position.x) + abs(shown.y - layer.position.y)))")
            }
        }
    }

    // MARK: Klick, Drücken, Rechtsklick

    private func iconIndex(at point: CGPoint) -> Int? {
        let gap = -DockMetrics.iconSpacing / 2
        return hitFrames.firstIndex { $0.insetBy(dx: edge.isVertical ? 0 : gap, dy: edge.isVertical ? gap : 0).contains(point) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return iconIndex(at: local) == nil ? nil : self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        model?.onCloseCard?()
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        pressedIndex = iconIndex(at: mouseDownPoint)
        applyLayout(animated: false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let index = pressedIndex, draggedKey == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y) > DockMetrics.dragThreshold else { return }
        beginInternalDrag(index: index, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressedIndex = nil; applyLayout(animated: false) }
        guard let index = pressedIndex, draggedKey == nil,
              iconIndex(at: convert(event.locationInWindow, from: nil)) == index else { return }
        click(apps[index], flags: event.modifierFlags)
    }

    private func click(_ app: DockApp, flags: NSEvent.ModifierFlags) {
        // ⌘-Klick zeigt im Finder, ⌥-Klick blendet die anderen Apps aus — wie im macOS-Dock.
        if flags.contains(.command) { NSWorkspace.shared.activateFileViewerSelecting([app.url]); return }
        if flags.contains(.option) { NSWorkspace.shared.hideOtherApplications() }
        model?.apps.open(app)
        // Läuft die App schon, bestätigt ein Hüpfer den Klick; sonst hüpft sie, bis sie läuft.
        if app.isRunning { hop(app.key) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model, let index = iconIndex(at: convert(event.locationInWindow, from: nil)) else { return nil }
        return AppMenu.make(for: apps[index], apps: model.apps, settings: model.settings)
    }

    // MARK: Ziehen aus der Leiste (Umsortieren / Entfernen)

    private func beginInternalDrag(index: Int, event: NSEvent) {
        let app = apps[index]
        let item = NSPasteboardItem()
        item.setString(app.url.path, forType: NSPasteboard.PasteboardType(UTType.neoDockItem.identifier))
        let dragging = NSDraggingItem(pasteboardWriter: item)
        // Ein Icon im Sprung steht nicht an seiner Modell-Position.
        let layer = iconLayers[index], shown = layer.presentation()?.position ?? layer.position
        dragging.setDraggingFrame(visibleFrames[index].offsetBy(dx: shown.x - layer.position.x, dy: shown.y - layer.position.y),
                                  contents: app.icon)
        draggedKey = app.key
        pressedIndex = nil
        model?.apps.setDragging(app)
        beginDraggingSession(with: [dragging], event: event, source: self)
        startLink()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        defer { draggedKey = nil; model?.apps.setDragging(nil); applyLayout(animated: true) }
        guard operation.isEmpty, let model, let key = draggedKey, let app = apps.first(where: { $0.key == key }),
              let window, !barArea(of: window, reach: model.iconReach).contains(screenPoint) else { return }
        // Aus der Leiste herausgezogen (wie im macOS-Dock): nicht mehr behalten.
        model.apps.removeFromDock(app)
    }

    /// Wo ein Zug nicht als Herausziehen zählt. An der Seite ist das Fenster des Namensschilds wegen breit.
    private func barArea(of window: NSWindow, reach: CGFloat) -> CGRect {
        let frame = window.frame
        return switch edge {
        case .bottom: frame
        case .left: CGRect(x: frame.minX, y: frame.minY, width: reach, height: frame.height)
        case .right: CGRect(x: frame.maxX - reach, y: frame.minY, width: reach, height: frame.height)
        }
    }

    // MARK: Ablegen auf der Reihe

    private var internalType: NSPasteboard.PasteboardType { NSPasteboard.PasteboardType(UTType.neoDockItem.identifier) }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        startLink()
        return draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let point = convert(sender.draggingLocation, from: nil)
        let nearest = apps.isEmpty ? nil : min(apps.count - 1, max(0, Int(((main(of: point) - restStart - iconSize / 2) / step).rounded())))
        if sender.draggingPasteboard.types?.contains(internalType) == true {
            if let key = draggedKey, let dragged = apps.first(where: { $0.key == key }), let nearest, apps[nearest].key != key {
                model?.apps.move(dragged, toward: apps[nearest])
            }
            return .move
        }
        let target = iconIndex(at: point)
        if dropTargetIndex != target { dropTargetIndex = target; applyLayout(animated: true) }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropTargetIndex = nil
        applyLayout(animated: true)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { dropTargetIndex = nil }
        if sender.draggingPasteboard.types?.contains(internalType) == true { return true }
        guard let model, let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        let target = iconIndex(at: convert(sender.draggingLocation, from: nil)).map { apps[$0] }
        let bundles = urls.filter { $0.pathExtension == "app" }
        if !bundles.isEmpty, bundles.count == urls.count {
            bundles.forEach { model.apps.pin($0, before: target) }
        } else if let target {
            FileDrops.log.notice("Öffne \(urls.count) Datei(en) mit \(target.name, privacy: .public)")
            model.apps.openFiles(urls, with: target)
        } else {
            return false
        }
        return true
    }
}

/// Rote Kennzahl-Plakette oben rechts am Icon, wie im macOS-Dock.
nonisolated final class BadgeLayer: CALayer {
    /// Keine impliziten Animationen (Plakette folgt dem Icon ohne Nachziehen).
    private static func noActions() -> [String: CAAction] {
        ["position": NSNull(), "bounds": NSNull(), "hidden": NSNull(), "contents": NSNull(), "string": NSNull()]
    }
    private let label = CATextLayer()
    static let heightFactor: CGFloat = 0.4
    static let overhang: CGFloat = 0.25

    override init() {
        super.init()
        backgroundColor = NSColor.systemRed.cgColor
        borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        actions = Self.noActions()
        label.foregroundColor = NSColor.white.cgColor
        label.alignmentMode = .center
        label.actions = Self.noActions()
        addSublayer(label)
        isHidden = true
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("nicht aus Interface Builder") }

    func update(text: String?, iconSize: CGFloat, contentsScale scale: CGFloat) {
        guard let text, !text.isEmpty else { isHidden = true; return }
        let height = (iconSize * Self.heightFactor).rounded()
        let font = NSFont.systemFont(ofSize: height * 0.62, weight: .semibold)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let width = max(height, ceil(textWidth) + height * 0.55)
        bounds = CGRect(x: 0, y: 0, width: width, height: height)
        cornerRadius = height / 2
        borderWidth = max(1, height * 0.06)
        // Oben rechts, leicht über den Rand hinaus.
        position = CGPoint(x: iconSize - width / 2 + height * Self.overhang, y: iconSize - height / 2 + height * Self.overhang)
        label.font = font
        label.fontSize = font.pointSize
        label.string = text
        label.contentsScale = scale
        contentsScale = scale
        let lineHeight = ceil(font.ascender - font.descender)
        label.frame = CGRect(x: 0, y: (height - lineHeight) / 2, width: width, height: lineHeight)
        isHidden = false
    }
}

/// Ein einziges Namensschild aus Glas, das mit dem Zeiger mitwandert.
final class NameTagView: NSView {
    private let glass = NSGlassEffectView()
    private let label = NSTextField(labelWithString: "")

    var text: String {
        get { label.stringValue }
        set { if label.stringValue != newValue { label.stringValue = newValue } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        let container = NSView()
        container.addSubview(label)
        glass.contentView = container
        glass.cornerRadius = 12
        addSubview(glass)
    }

    required init?(coder: NSCoder) { fatalError("nicht aus Interface Builder") }

    override var fittingSize: NSSize {
        let size = label.intrinsicContentSize
        return NSSize(width: ceil(size.width) + Space.lg, height: ceil(size.height) + Space.sm)
    }

    override func layout() {
        super.layout()
        glass.frame = bounds
        label.frame = bounds.insetBy(dx: Space.sm, dy: Space.xs)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Rechtsklick auf ein App-Icon — wie im macOS-Dock.
enum AppMenu {
    @MainActor
    static func make(for app: DockApp, apps: AppsProvider, settings: DockSettings) -> NSMenu {
        let menu = NSMenu()
        let running = apps.runningApp(app)
        let isFinder = app.key == AppsProvider.key(AppsProvider.finderURL)
        menu.addItem(ClosureMenuItem(running == nil ? "Öffnen" : "Neues Fenster / nach vorne") { apps.open(app) })
        menu.addItem(.separator())
        if !isFinder {
            let keep = ClosureMenuItem("Im Dock behalten") { apps.togglePinned(app) }
            keep.state = settings.isPinned(app.url) ? .on : .off
            menu.addItem(keep)
        }
        menu.addItem(ClosureMenuItem("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) })
        if let running, !isFinder {
            menu.addItem(.separator())
            menu.addItem(running.isHidden ? ClosureMenuItem("Einblenden") { running.unhide() }
                                          : ClosureMenuItem("Ausblenden") { running.hide() })
            menu.addItem(ClosureMenuItem("Beenden") { running.terminate() })
            let force = ClosureMenuItem("Sofort beenden") { running.forceTerminate() }
            force.isAlternate = true
            force.keyEquivalentModifierMask = .option
            menu.addItem(force)
        }
        return menu
    }
}

/// Menüeintrag mit Closure: das Zielobjekt hängt als representedObject am Eintrag (hält es am Leben).
@MainActor
func ClosureMenuItem(_ title: String, handler: @escaping () -> Void) -> NSMenuItem {
    let action = MenuAction(handler)
    let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
    item.target = action
    item.representedObject = action
    return item
}

final class MenuAction: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func run() { handler() }
}

/// SwiftUI-Hülle. Liest die Modellwerte in `updateNSView` — SwiftUI beobachtet sie dort und ruft
/// die Aktualisierung nur auf, wenn sich Apps, Größe oder Hüpf-Zustand ändern, nie pro Mausbewegung.
struct AppsRow: NSViewRepresentable {
    let model: DockModel

    func makeNSView(context: Context) -> AppsRowView {
        let view = AppsRowView()
        view.model = model
        model.appsRowView = view
        return view
    }

    func updateNSView(_ view: AppsRowView, context: Context) {
        view.edge = model.edge
        view.maxScale = CGFloat(model.settings.effectiveScale)
        view.iconSize = model.iconSize
        view.apps = model.apps.apps
        view.bouncing = model.apps.launching.union(model.attentionKeys)
        view.badges = model.badges.labels
    }
}
