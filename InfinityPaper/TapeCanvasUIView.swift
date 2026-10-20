import UIKit

final class TapeCanvasUIView: UIView {
    /// Curated brush widths shared with the toolbar.
    static let toolbarWidthPresets: [CGFloat] = [1.5, 2.5, 4.0, 6.0]

    private(set) var documentReady = false
    private var documentSessionURL: URL?
    private(set) var eraserSelected = false
    private var eraserLocation: CGPoint?
    private(set) var paperPattern: PaperPattern = .plain
    private(set) var paperSpacing: CGFloat = PaperPatternLayout.defaultSpacing
    private let sessionState = TapeCanvasSessionState()
    private lazy var selection = CanvasSelectionController(state: sessionState)
    var selectedTool: CanvasTool { selection.isEnabled ? .lasso : eraserSelected ? .eraser : .pen }
    var selectedStrokeCount: Int { selection.selectedIDs.count }
    private var currentStroke: TapeSessionStroke?
    private var restoringSession = false
    private var viewport = CanvasViewport() {
        didSet { if !restoringSession, oldValue != viewport { sessionState.noteMutationForPersistence() } }
    }
    private var contentOffset: CGPoint {
        get { viewport.offset }
        set { viewport.offset = newValue }
    }
    private var zoomScale: CGFloat {
        get { viewport.zoom }
        set { viewport.zoom = newValue }
    }
    private var paperMovementLocked = false
    private let input = CanvasInputController()
    private var pencilSettingsObserver: NSObjectProtocol?
    private var paperSurfaceObserverToken: NSObjectProtocol?
    private var lastTouchLocation: CGPoint?
    private let rendering = CanvasRenderState()
    private let motion = CanvasMotionController()
    private var cachedPaperSurface: PaperSurface = .quiet
    /// Adaptive background color that responds to system dark mode.
    private var backgroundColorTone: UIColor {
        PaperSurface.adaptiveBackgroundColor
    }
    private var baseStrokeColor: UIColor = UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 0.9)
    private var baseLineWidth: CGFloat = AppSettings.Default.lineWidth
    private lazy var toastManager: CanvasToastManager = {
        CanvasToastManager(parentView: self, traitCollection: traitCollection)
    }()
    private let referenceRenderer = CanvasReferenceRenderer()
    var referenceImage: ReferenceImage? { sessionState.referenceImage }
    var referenceViewport: CGRect { viewport.worldRect(for: bounds.size) }

    func setReferenceImage(_ image: ReferenceImage?) {
        guard documentReady else { return }
        finishCurrentStroke()
        do { try sessionState.setReferenceImage(image) }
        catch { showToast(text: "Could not apply reference image", type: .error); return }
        markDrawingContentChanged()
        requestDisplayIfNeeded(force: true)
        postToolbarStateChange()
    }

    private let exportManager = CanvasExportManager()
    private lazy var persistence: CanvasPersistenceCoordinator = {
        let manager = CanvasSessionManager(store: SessionFileStore(url: documentSessionURL ?? SessionPersistence.sessionURL()))
        let coordinator = CanvasPersistenceCoordinator(state: sessionState, manager: manager,
            makeSnapshot: { [weak self] in self?.makeSessionSnapshot() },
            shouldDeferActiveSave: { [weak self] in
                self?.currentStroke != nil && UIApplication.shared.applicationState == .active
            }, keepEmptySession: documentSessionURL != nil)
        coordinator.onLoaded = { [weak self] session in self?.applyLoadedSession(session) }
        coordinator.onSaved = { [weak self] in
            self?.showToast(text: NSLocalizedString("toast.saved", comment: "Saved"), type: .success)
        }
        coordinator.onLoadFinished = { [weak self] succeeded in
            guard let self else { return }
            if succeeded { self.documentReady = true }
            self.isUserInteractionEnabled = self.documentReady
            self.postToolbarStateChange()
            if !succeeded { self.showToast(text: "Could not load this drawing. Return to My drawings to retry.", type: .error) }
        }
        coordinator.onError = { [weak self] message in self?.showToast(text: message, type: .error) }
        return coordinator
    }()
    private lazy var panRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        recognizer.minimumNumberOfTouches = 2
        recognizer.maximumNumberOfTouches = 2
        return recognizer
    }()
    private lazy var pinchRecognizer: UIPinchGestureRecognizer = {
        UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    }()
    private lazy var twoFingerDoubleTapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerDoubleTap(_:)))
        recognizer.numberOfTouchesRequired = 2
        recognizer.numberOfTapsRequired = 2
        recognizer.cancelsTouchesInView = false
        return recognizer
    }()

    /// Opens the full Settings sheet from the toolbar.
    var onOpenFullSettings: (() -> Void)?
    /// Called when undo/redo availability or line width changes so SwiftUI toolbar can refresh.
    var onToolbarStateChange: (() -> Void)?

    var toolbarUndoEnabled: Bool { sessionState.canUndo }
    var toolbarRedoEnabled: Bool { sessionState.canRedo }
    var toolbarBaseLineWidth: CGFloat { baseLineWidth }
    var toolbarPaperMovementLocked: Bool { paperMovementLocked }

    /// Exposed for Settings: current brush color.
    var exposedBaseStrokeColor: UIColor { baseStrokeColor }
    /// Includes any additional colors earned in earlier versions.
    var exposedPrimaryPalette: [UIColor] {
        CanvasBrush.palette.indices.map { CanvasBrush.color(at: $0, traits: traitCollection) }
    }

    /// Called from Settings: set line width.
    func setBaseLineWidthFromSettings(_ width: CGFloat) {
        baseLineWidth = width
        AppSettings.defaults.set(Double(width), forKey: AppSettings.lineWidth)
        postToolbarStateChange()
    }
    /// After SwiftUI confirmation from the toolbar “More” menu (no second alert).
    func toolbarClearCanvasConfirmed() {
        clearLastDrawingSession()
        showToast(text: NSLocalizedString("toast.session_cleared", comment: "Session cleared"), type: .warning)
    }

    /// Scrolls so the current drawing (if any) is roughly centered in the viewport.
    func toolbarCenterViewOnContent() {
        guard bounds.width > 1 else { return }
        viewport.center(on: sessionState.rawWorldBoundingRect(currentStroke: currentStroke), in: bounds.size)
        requestDisplayIfNeeded()
        postToolbarStateChange()
        showToast(text: NSLocalizedString("toast.view_centered", comment: "View centered"), type: .info)
    }

    func toolbarZoomIn() {
        zoomBy(step: 1.2)
    }

    func toolbarZoomOut() {
        zoomBy(step: 1 / 1.2)
    }

    func toolbarResetView() {
        resetZoomAndCenter(animated: true)
    }

    func toolbarFitContent() {
        fitContentInView(animated: true)
    }
    /// Called from Settings: load the last saved session.
    func loadSessionFromSettings() {
        guard sessionState.hasUnsavedChanges || currentStroke != nil else { persistence.load(); return }
        guard let controller = findViewController() else { return }
        let alert = UIAlertController(title: "Load saved drawing?",
                                      message: "Unsaved changes in this drawing will be discarded.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Discard changes and load", style: .destructive) { [weak self] _ in
            self?.persistence.load()
        })
        controller.present(alert, animated: true)
    }
    // MARK: - Toolbar (SwiftUI)

    private func postToolbarStateChange() {
        onToolbarStateChange?()
    }

    func toolbarUndo() {
        undoLastStroke()
    }

    func toolbarRedo() {
        redoLastStroke()
    }

    func toolbarExport() {
        exportVisible()
    }

    func toolbarOpenFullSettings() {
        finishCurrentStroke()
        motion.stop()
        onOpenFullSettings?()
    }

    func toolbarSetPaperMovementLocked(_ locked: Bool) {
        paperMovementLocked = locked
        if locked {
            motion.stopDeceleration()
            motion.stopAutoScroll()
            lastTouchLocation = nil
        }
        postToolbarStateChange()
        showToast(
            text: locked
                ? NSLocalizedString("toast.paper_movement_locked", comment: "Paper movement locked")
                : NSLocalizedString("toast.paper_movement_unlocked", comment: "Paper movement unlocked"),
            type: .info
        )
    }

    /// Toolbar / popover: set one of the curated widths.
    func toolbarSetLineWidthPreset(at index: Int) {
        guard Self.toolbarWidthPresets.indices.contains(index) else { return }
        finishCurrentStroke()
        eraserSelected = false
        selection.setEnabled(false)
        setBaseLineWidthFromSettings(Self.toolbarWidthPresets[index])
    }

    /// Index into `toolbarWidthPresets` nearest to the current width (for selection ring).
    func toolbarWidthPresetIndex() -> Int {
        let presets = Self.toolbarWidthPresets
        guard !presets.isEmpty else { return 0 }
        return presets.indices.min { a, b in
            abs(presets[a] - baseLineWidth) < abs(presets[b] - baseLineWidth)
        } ?? 0
    }

    /// Persisted palette index clamped to the current exposed palette (toolbar selection ring).
    var toolbarSelectedPaletteIndex: Int {
        let palette = exposedPrimaryPalette
        guard !palette.isEmpty else { return 0 }
        let defaults = AppSettings.defaults
        let idx = defaults.integer(forKey: AppSettings.colorIndex)
        return min(max(0, idx), palette.count - 1)
    }

    func toolbarSelectColor(at index: Int) {
        let palette = exposedPrimaryPalette
        guard palette.indices.contains(index) else { return }
        finishCurrentStroke()
        eraserSelected = false
        selection.setEnabled(false)
        baseStrokeColor = CanvasBrush.color(at: index, traits: traitCollection)
        AppSettings.defaults.set(index, forKey: AppSettings.colorIndex)
        postToolbarStateChange()
    }

    init(sessionURL: URL) {
        documentSessionURL = sessionURL
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        configureCommon()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        documentReady = true
        configureCommon()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        documentReady = true
        configureCommon()
    }

    deinit {
        motion.stop()
        persistence.stop()
        if let token = pencilSettingsObserver { NotificationCenter.default.removeObserver(token) }
        if let token = paperSurfaceObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            finishCurrentStroke()
            motion.stopDeceleration()
            persistence.saveBeforeDetaching()
        }
    }

    override func draw(_ rect: CGRect) {
        guard rendering.needsRedraw, let context = UIGraphicsGetCurrentContext() else { return }
        
        // Background (no separate layer so it does not cover our strokes)
        let bgColor = backgroundColorTone.resolvedColor(with: traitCollection)
        context.setFillColor(bgColor.cgColor)
        context.fill(rect)
        
        // Draw noise texture
        rendering.drawPaper(in: context, rect: rect, background: backgroundColorTone,
                            surface: PaperSurface.current(), traits: traitCollection)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.saveGState()
        context.concatenate(CanvasGeometry.viewportTransform(offset: contentOffset, zoom: zoomScale))
        referenceRenderer.draw(referenceImage, in: context)
        drawPaperPattern(in: context, visibleOnly: true)
        drawStrokes(in: context, visibleOnly: true)
        CanvasSelectionRenderer.draw(selection, in: context, zoom: zoomScale)
        context.restoreGState()
        if eraserSelected, let point = eraserLocation {
            let center = CGPoint(x: (point.x - contentOffset.x) * zoomScale, y: (point.y - contentOffset.y) * zoomScale)
            context.setStrokeColor(UIColor.label.withAlphaComponent(0.55).cgColor)
            context.setLineWidth(1)
            context.strokeEllipse(in: CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24))
        }
        
        rendering.didDraw(viewport: viewport)
    }

    override func setNeedsDisplay() {
        rendering.needsRedraw = true
        super.setNeedsDisplay()
    }

    override func setNeedsDisplay(_ rect: CGRect) {
        rendering.needsRedraw = true
        super.setNeedsDisplay(rect)
    }

    private func markDrawingContentChanged() { rendering.contentChanged() }
    private func requestDisplayIfNeeded(force: Bool = false) {
        if rendering.requiresDisplay(viewport: viewport, force: force) { setNeedsDisplay() }
    }

    /// Appends touch samples using `coalescedTouches` when available so fast strokes stay curved between display frames.
    /// Timestamps are spaced monotonically between the last stored time and `touch.timestamp` so width/speed stays stable.
    private func appendStrokeSamplesFromTouch(_ touch: UITouch, event: UIEvent?) {
        guard var stroke = currentStroke else { return }
        let samples = event?.coalescedTouches(for: touch) ?? [touch]
        let n = samples.count
        let lastT = stroke.times.last ?? touch.timestamp
        let endT = max(touch.timestamp, lastT + 1e-4)
        let span = endT - lastT

        for i in 0..<n {
            let p = viewport.worldPoint(samples[i].location(in: self))
            if let lp = stroke.points.last {
                let dist = hypot(p.x - lp.x, p.y - lp.y)
                if dist < 0.02, i < n - 1 { continue }
            }
            let t: TimeInterval
            if n == 1 {
                t = endT
            } else {
                t = lastT + span * Double(i + 1) / Double(n)
            }
            stroke.points.append(p)
            stroke.times.append(t)
            if !stroke.widthScales.isEmpty { stroke.widthScales.append(input.widthScale(for: samples[i])) }
        }
        currentStroke = stroke
        sessionState.noteMutationForPersistence()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard (panRecognizer.state == .possible || panRecognizer.state == .failed),
              (pinchRecognizer.state == .possible || pinchRecognizer.state == .failed) else { return }
        guard currentStroke == nil, let touch = input.begin(touches, event: event) else { return }
        motion.stopDeceleration()
        persistence.invalidatePendingLoad()
        let location = touch.location(in: self)
        if selection.isEnabled {
            motion.stop()
            selection.begin(at: viewport.worldPoint(location), zoom: zoomScale)
            return
        }
        if eraserSelected {
            sessionState.beginErasing()
            eraseTo(viewport.worldPoint(location))
            return
        }
        lastTouchLocation = location
        let color = baseStrokeColor
        currentStroke = TapeSessionStroke(
            points: [viewport.worldPoint(location)],
            times: [touch.timestamp],
            color: color,
            lineWidth: baseLineWidth,
            widthScales: input.capturesWidthProfile ? [input.widthScale(for: touch)] : []
        )
        sessionState.noteMutationForPersistence()
        if !paperMovementLocked { motion.startAutoScroll() }
        markDrawingContentChanged()
        requestDisplayIfNeeded()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard (panRecognizer.state == .possible || panRecognizer.state == .failed),
              (pinchRecognizer.state == .possible || pinchRecognizer.state == .failed) else { return }
        guard let touch = input.tracked(in: touches) else { return }
        let location = touch.location(in: self)
        if selection.isEnabled {
            for sample in event?.coalescedTouches(for: touch) ?? [touch] { selection.move(to: viewport.worldPoint(sample.location(in: self))) }
            return
        }
        if eraserSelected {
            for sample in event?.coalescedTouches(for: touch) ?? [touch] { eraseTo(viewport.worldPoint(sample.location(in: self))) }
            return
        }
        lastTouchLocation = location
        appendStrokeSamplesFromTouch(touch, event: event)
        markDrawingContentChanged()
        requestDisplayIfNeeded()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = input.tracked(in: touches) else { return }
        defer { input.finish() }
        if selection.isEnabled {
            selection.move(to: viewport.worldPoint(touch.location(in: self)))
            selection.finishGesture()
            return
        }
        if eraserSelected {
            eraseTo(viewport.worldPoint(touch.location(in: self)))
            finishCurrentStroke()
            return
        }
        appendStrokeSamplesFromTouch(touch, event: event)
        finishCurrentStroke()
    }

    /// System interruptions preserve ink; navigation gestures cancel their tentative drawing touch.
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard input.tracked(in: touches) != nil else { return }
        defer { input.finish() }
        if selection.isEnabled { selection.finishGesture(cancelled: true); return }
        if eraserSelected { finishCurrentStroke(); return }
        let navigating = panRecognizer.state == .began || panRecognizer.state == .changed
            || pinchRecognizer.state == .began || pinchRecognizer.state == .changed
        if navigating {
            currentStroke = nil
            lastTouchLocation = nil
            motion.stopAutoScroll()
            sessionState.noteMutationForPersistence()
            markDrawingContentChanged()
            requestDisplayIfNeeded()
        } else {
            finishCurrentStroke()
        }
    }

    private func finishCurrentStroke() {
        input.finish()
        selection.finishGesture()
        sessionState.endErasing()
        eraserLocation = nil
        if let stroke = currentStroke { sessionState.commitCompletedStroke(stroke) }
        currentStroke = nil
        lastTouchLocation = nil
        motion.stopAutoScroll()
        markDrawingContentChanged()
        requestDisplayIfNeeded()
        postToolbarStateChange()
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard !paperMovementLocked else {
            recognizer.setTranslation(.zero, in: self)
            if recognizer.state == .began || recognizer.state == .changed {
                motion.stopDeceleration()
            }
            return
        }
        switch recognizer.state {
        case .began:
            motion.stopDeceleration()
        case .changed:
            let translation = recognizer.translation(in: self)
            viewport.pan(by: translation)
            recognizer.setTranslation(.zero, in: self)
            requestDisplayIfNeeded()
        case .ended, .cancelled:
            let velocity = recognizer.velocity(in: self)
            motion.startDeceleration(velocity: CGPoint(x: velocity.x / zoomScale, y: velocity.y / zoomScale))
        default:
            break
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard !paperMovementLocked else { return }
        _ = viewport.zoom(by: recognizer.scale, at: recognizer.location(in: self))
        requestDisplayIfNeeded()
        recognizer.scale = 1
    }

    private func advanceAutoScroll(dt: CGFloat) {
        guard !paperMovementLocked else {
            motion.stopAutoScroll()
            return
        }
        guard let lastTouchLocation, currentStroke != nil else {
            motion.stopAutoScroll()
            return
        }
        contentOffset.x += (90 * dt) / zoomScale
        viewport.clamp()
        let worldPoint = viewport.worldPoint(lastTouchLocation)
        guard var stroke = currentStroke else {
            motion.stopAutoScroll()
            return
        }
        let lastT = stroke.times.last ?? CACurrentMediaTime()
        let stamp = lastT + Double(dt)
        stroke.points.append(worldPoint)
        stroke.times.append(stamp)
        if let last = stroke.widthScales.last { stroke.widthScales.append(last) }
        currentStroke = stroke
        sessionState.noteMutationForPersistence()
        markDrawingContentChanged()
        requestDisplayIfNeeded()
    }

    private func makeSessionSnapshot() -> StoredSession {
        var snapshot = sessionState.buildStoredSession(contentOffset: contentOffset, zoomScale: zoomScale,
                                        currentStroke: currentStroke, savedAt: Date().timeIntervalSince1970)
        snapshot.paperPattern = paperPattern
        snapshot.paperSpacing = paperSpacing
        return snapshot
    }

    private func applyLoadedSession(_ session: StoredSession) {
        input.finish()
        motion.stop()
        currentStroke = nil
        eraserLocation = nil
        selection.clear()
        paperPattern = session.paperPattern ?? .plain
        paperSpacing = session.paperSpacing ?? PaperPatternLayout.defaultSpacing
        restoringSession = true
        viewport = CanvasViewport(offset: CGPoint(x: session.contentOffset.x, y: session.contentOffset.y),
                                  zoom: session.zoomScale ?? 1)
        restoringSession = false
        rendering.invalidateStrokes()
        markDrawingContentChanged()
        requestDisplayIfNeeded(force: true)
        postToolbarStateChange()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Update background color to adapt to dark mode / paper surface.
        backgroundColor = backgroundColorTone.resolvedColor(with: traitCollection)

        let surfaceNow = PaperSurface.current()
        if surfaceNow != cachedPaperSurface {
            cachedPaperSurface = surfaceNow
            rendering.invalidatePaper()
            markDrawingContentChanged()
            requestDisplayIfNeeded()
        }
        
        toastManager.updateLayout(in: bounds)
    }

    /// Shared light/dark refresh; invoked when `userInterfaceStyle` changes via `registerForTraitChanges`.
    private func handleUserInterfaceStyleChange(previous: UITraitCollection?) {
        if traitCollection.userInterfaceStyle != previous?.userInterfaceStyle {
            // Dark mode changed - update colors and redraw
            backgroundColor = backgroundColorTone.resolvedColor(with: traitCollection)
            rendering.invalidatePaper() // Invalidate noise tile cache to regenerate with new colors
            toastManager.updateTraitCollection(traitCollection)
            applySavedBrushSettings()
            postToolbarStateChange()
            markDrawingContentChanged()
            requestDisplayIfNeeded()
        }
    }

    func toolbarSetTool(_ tool: CanvasTool) {
        finishCurrentStroke()
        eraserSelected = tool == .eraser
        selection.setEnabled(tool == .lasso)
        postToolbarStateChange()
        if tool == .lasso {
            showToast(text: "Loop around strokes to select. Drag inside the dashed frame to move.")
        }
    }

    func toolbarDuplicateSelection() {
        selection.duplicate(offset: CGPoint(x: 24 / zoomScale, y: 24 / zoomScale))
    }

    func toolbarDeleteSelection() { selection.delete() }
    func toolbarDeselect() { selection.clear() }

    private func eraseTo(_ point: CGPoint) {
        let previous = eraserLocation ?? point
        eraserLocation = point
        if sessionState.erase(from: previous, to: point, radius: 12 / zoomScale) {
            rendering.invalidateStrokes()
            markDrawingContentChanged()
        }
        requestDisplayIfNeeded(force: true)
    }

    func setPaperPattern(_ pattern: PaperPattern, spacing: CGFloat) {
        guard documentReady, spacing.isFinite else { return }
        paperPattern = pattern
        paperSpacing = min(PaperPatternLayout.spacingRange.upperBound, max(PaperPatternLayout.spacingRange.lowerBound, spacing))
        sessionState.noteMutationForPersistence()
        markDrawingContentChanged()
        requestDisplayIfNeeded(force: true)
    }

    func saveForLibrary(completion: @escaping (Result<Void, Error>) -> Void) {
        let wasEnabled = isUserInteractionEnabled
        isUserInteractionEnabled = false
        finishCurrentStroke()
        motion.stop()
        persistence.invalidatePendingLoad()
        persistence.saveAndWait { [weak self] result in
            if case .failure = result { self?.isUserInteractionEnabled = wasEnabled }
            completion(result)
        }
    }

    private func drawPaperPattern(in context: CGContext, visibleOnly: Bool) {
        let margin = CGFloat(AppSettings.defaults.double(forKey: AppSettings.margin))
        let rect = visibleOnly ? viewport.worldRect(for: bounds.size)
            : sessionState.worldBoundingRectForExport(currentStroke: currentStroke,
                includeReference: AppSettings.defaults.bool(forKey: AppSettings.includeReferenceImage))?.insetBy(dx: -margin, dy: -margin)
        guard let rect else { return }
        PaperPatternRenderer.draw(in: context, rect: rect, pattern: paperPattern, spacing: paperSpacing,
                                  zoom: visibleOnly ? zoomScale : 1, traits: traitCollection)
    }

    private func drawStrokes(in context: CGContext, visibleOnly: Bool) {
        rendering.drawStrokes(in: context, session: sessionState, currentStroke: currentStroke,
                              viewport: viewport, size: bounds.size, visibleOnly: visibleOnly,
                              movingIDs: selection.selectedIDs, translation: selection.translation)
    }

    /// Removes the most recently completed stroke (Undo). No-op if nothing to undo.
    private func undoLastStroke() {
        finishCurrentStroke()
        guard sessionState.undoLastStroke() else { return }
        selection.clear()
        rendering.invalidateStrokes()
        markDrawingContentChanged()
        requestDisplayIfNeeded()
        showToast(text: NSLocalizedString("toast.undo", comment: "Undo"), type: .warning)
        postToolbarStateChange()
    }

    /// Re-applies the most recently undone stroke (Redo). No-op if nothing to redo.
    private func redoLastStroke() {
        finishCurrentStroke()
        guard sessionState.redoLastStroke() else { return }
        selection.clear()
        rendering.invalidateStrokes()
        markDrawingContentChanged()
        requestDisplayIfNeeded()
        showToast(text: NSLocalizedString("toast.redo", comment: "Redo"), type: .success)
        postToolbarStateChange()
    }

    private func exportVisible() {
        finishCurrentStroke()
        exportManager.exportCanvas(bounds: bounds, viewport: viewport,
            fullDrawingBounds: sessionState.worldBoundingRectForExport(currentStroke: currentStroke,
                includeReference: AppSettings.defaults.bool(forKey: AppSettings.includeReferenceImage)),
            backgroundColor: backgroundColorTone.resolvedColor(with: traitCollection),
            drawStrokes: { [weak self] context, visibleOnly in
                guard let self else { return }
                let defaults = AppSettings.defaults
                if defaults.bool(forKey: AppSettings.includeReferenceImage) {
                    self.referenceRenderer.draw(self.referenceImage, in: context)
                }
                if defaults.bool(forKey: AppSettings.includePaperPattern) {
                    self.drawPaperPattern(in: context, visibleOnly: visibleOnly)
                }
                self.drawStrokes(in: context, visibleOnly: visibleOnly)
            },
            drawNoise: { [weak self] context, rect in
                guard let self else { return }
                self.rendering.drawPaper(in: context, rect: rect, background: self.backgroundColorTone,
                                         surface: PaperSurface.current(), traits: self.traitCollection)
            },
            presentShare: { [weak self] in self?.presentShare(url: $0) },
            showToast: { [weak self] in self?.showToast(text: $0, type: $1) })
    }

    private func presentShare(url: URL) {
        guard let controller = findViewController() else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = self
        activity.popoverPresentationController?.sourceRect = CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
        controller.present(activity, animated: true)
    }

    private func clearLastDrawingSession() {
        input.finish()
        selection.clear()
        eraserLocation = nil
        motion.stop()
        currentStroke = nil
        lastTouchLocation = nil
        persistence.clear()
        rendering.invalidateStrokes()
        markDrawingContentChanged()
        requestDisplayIfNeeded(force: true)
        postToolbarStateChange()
    }

    private func showToast(text: String, type: ToastType = .info) {
        toastManager.show(text: text, type: type)
    }

    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController {
                var presented = vc
                while let next = presented.presentedViewController { presented = next }
                return presented
            }
            responder = next
        }
        return nil
    }

    private func configureCommon() {
        input.configure(pan: panRecognizer, pinch: pinchRecognizer, reset: twoFingerDoubleTapRecognizer)
        pencilSettingsObserver = NotificationCenter.default.addObserver(forName: AppSettings.pencilInputDidChange,
            object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.finishCurrentStroke()
                self.motion.stop()
                self.input.configure(pan: self.panRecognizer, pinch: self.pinchRecognizer, reset: self.twoFingerDoubleTapRecognizer)
            }
        selection.onChange = { [weak self] contentChanged in
            guard let self else { return }
            if contentChanged { self.rendering.invalidateStrokes(); self.markDrawingContentChanged() }
            self.requestDisplayIfNeeded(force: true)
            self.postToolbarStateChange()
        }
        motion.onDecelerationStep = { [weak self] delta in
            guard let self else { return }
            self.contentOffset.x -= delta.x
            self.contentOffset.y -= delta.y
            self.viewport.clamp()
            self.requestDisplayIfNeeded()
        }
        motion.onAutoScrollStep = { [weak self] dt in self?.advanceAutoScroll(dt: dt) }
        isMultipleTouchEnabled = true
        addGestureRecognizer(panRecognizer)
        addGestureRecognizer(pinchRecognizer)
        addGestureRecognizer(twoFingerDoubleTapRecognizer)
        _ = toastManager // Initialize toast manager
        persistence.start(autoload: documentSessionURL != nil ? true : nil) { [weak self] in
            self?.finishCurrentStroke()
            self?.motion.stopDeceleration()
        }
        applySavedBrushSettings()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: TapeCanvasUIView, previousTraitCollection: UITraitCollection) in
            self?.handleUserInterfaceStyleChange(previous: previousTraitCollection)
        }
        if paperSurfaceObserverToken == nil {
            paperSurfaceObserverToken = NotificationCenter.default.addObserver(
                forName: PaperSurface.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.cachedPaperSurface = PaperSurface.current()
                self.backgroundColor = self.backgroundColorTone.resolvedColor(with: self.traitCollection)
                self.rendering.invalidatePaper()
                self.markDrawingContentChanged()
                self.requestDisplayIfNeeded()
            }
        }
    }

    @objc private func handleTwoFingerDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        resetZoomAndCenter(animated: true)
    }

    private func resetZoomAndCenter(animated: Bool) {
        let apply = {
            self.zoomScale = 1
            self.toolbarCenterViewOnContent()
        }
        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                apply()
            }
        } else {
            apply()
        }
    }

    private func fitContentInView(animated: Bool) {
        guard let rect = sessionState.rawWorldBoundingRect(currentStroke: currentStroke),
              rect.width > 0, rect.height > 0, bounds.width > 48, bounds.height > 48 else {
            resetZoomAndCenter(animated: animated)
            return
        }
        let apply = {
            self.viewport.fit(rect, in: self.bounds.size)
            self.requestDisplayIfNeeded()
            self.postToolbarStateChange()
            self.showToast(text: NSLocalizedString("toast.view_fit_content", comment: "Fit content"), type: .info)
        }
        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                apply()
            }
        } else {
            apply()
        }
    }

    private func zoomBy(step: CGFloat) {
        guard viewport.zoom(by: step, at: CGPoint(x: bounds.midX, y: bounds.midY)) else { return }
        requestDisplayIfNeeded()
        postToolbarStateChange()
    }

    /// Applies brush color and line width from UserDefaults (set in Settings) so they persist across launches.
    private func applySavedBrushSettings() {
        baseStrokeColor = CanvasBrush.color(at: toolbarSelectedPaletteIndex, traits: traitCollection)
        let defaults = AppSettings.defaults
        baseLineWidth = CGFloat(defaults.double(forKey: AppSettings.lineWidth))
    }

    // MARK: - Accessibility (Canvas)

    override var isAccessibilityElement: Bool {
        get { true }
        // This view represents the interactive drawing canvas; ignore external setters.
        set { }
    }

    override var accessibilityLabel: String? {
        get { "Infinity Paper canvas" }
        set { }
    }

    override var accessibilityHint: String? {
        get {
            NSLocalizedString(input.pencilOnly ? "accessibility.canvas_hint_pencil" : "accessibility.canvas_hint_toolbar", comment: "Canvas gestures and toolbar")
        }
        set { }
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { [.allowsDirectInteraction, .updatesFrequently] }
        set { }
    }

}
