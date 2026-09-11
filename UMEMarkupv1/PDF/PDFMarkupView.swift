import PDFKit
import PencilKit
import SwiftUI
import UIKit

/// Apple Pencil vs finger.
///
/// UIKit hit-testing often calls `hitTest` / `point(inside:)` with `event == nil`
/// or an event whose `allTouches` is still empty. A filter that requires a live
/// `.pencil` touch in `allTouches` therefore returns false for real Pencil
/// strokes and the overlay never becomes the hit view. Classify those calls as
/// `.unknown` and **allow** the canvas hit; `PKCanvasView.drawingPolicy` is what
/// ignores finger drawing on device.
enum PencilInput {
    enum Role {
        /// Known stylus (or the Simulator pointer, which we treat as a stylus).
        case pencil
        /// Known finger / palm — must not create marks.
        case finger
        /// Hit-test without a populated touch set. Do not reject these.
        case unknown
    }

    static var drawingPolicy: PKCanvasViewDrawingPolicy {
        #if targetEnvironment(simulator)
        .anyInput
        #else
        .pencilOnly
        #endif
    }

    static var allTouchTypes: [NSNumber] {
        [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.indirect.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue),
            NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)
        ]
    }

    /// Types that may begin a PencilKit stroke / eraser tap.
    static var stylusTouchTypes: [NSNumber] {
        #if targetEnvironment(simulator)
        allTouchTypes
        #else
        [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        #endif
    }

    /// Types that may pan the PDF while a drawing tool is selected.
    static var fingerTouchTypes: [NSNumber] {
        [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.indirect.rawValue),
            NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)
        ]
    }

    static func accepts(_ touch: UITouch) -> Bool {
        #if targetEnvironment(simulator)
        true
        #else
        touch.type == .pencil
        #endif
    }

    static func role(of event: UIEvent?) -> Role {
        #if targetEnvironment(simulator)
        return .pencil
        #else
        guard let event else { return .unknown }
        if event.type == .hover { return .pencil }
        guard let touches = event.allTouches, !touches.isEmpty else { return .unknown }
        if touches.contains(where: { $0.type == .pencil }) {
            return .pencil
        }
        return .finger
        #endif
    }
}

final class MarkupBridge {
    weak var coordinator: PDFMarkupView.Coordinator?
    weak var pdfView: PDFView?

    func addNote(text: String, pageIndex: Int, anchor: CGPoint) {
        coordinator?.addNote(text: text, pageIndex: pageIndex, anchor: anchor, pdfView: pdfView)
    }

    func captureInk() {
        coordinator?.captureInk(from: pdfView)
    }

    func undo() {
        coordinator?.undo(in: pdfView)
    }

    func goToPage(_ pageIndex: Int) {
        coordinator?.goToPage(pageIndex, pdfView: pdfView)
    }
}

/// PencilKit overlay that does not swallow hits when drawing is off, and that
/// re-enables the private overlay container PDFKit inserts (it defaults to
/// `isUserInteractionEnabled == false`, which drops Apple Pencil and finger).
final class PageInkCanvas: PKCanvasView {
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        activateOverlayAncestors()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        activateOverlayAncestors()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isUserInteractionEnabled, bounds.contains(point) else { return false }
        // Only drop the hit when we *know* this is a finger. `event == nil`
        // (or empty `allTouches`) is the normal Pencil hit-test path on device.
        if PencilInput.role(of: event) == .finger {
            return false
        }
        return super.point(inside: point, with: event)
    }

    func activateOverlayAncestors() {
        // PDFKit wraps the overlay in a container that defaults to ignoring
        // hits. Toggle only that host — never the document scroll view.
        guard let host = superview, !(host is PDFView), !(host is UIScrollView) else { return }
        host.isUserInteractionEnabled = isUserInteractionEnabled
    }
}

/// PDFView that forwards Apple Pencil hits to per-page ink canvases. Finger
/// and palm go to the document scroll view so the page still pans.
final class MarkupPDFView: PDFView {
    var inkHitTestingEnabled = false

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard inkHitTestingEnabled,
              let canvas = inkCanvas(containing: point),
              canvas.isUserInteractionEnabled else {
            return super.hitTest(point, with: event)
        }

        // Known finger / palm: give the document scroll view the touch. Do not
        // hit-test descendants — the overlay host would swallow the pan.
        if PencilInput.role(of: event) == .finger {
            return documentScrollView() ?? super.hitTest(point, with: event)
        }

        // Pencil, hover, Simulator, or unknown (nil / empty event): same path
        // that worked in PR #2. PencilKit's drawingPolicy ignores non-stylus
        // input if a later touch turns out not to be a Pencil.
        let local = convert(point, to: canvas)
        if let hit = canvas.hitTest(local, with: event) {
            return hit
        }
        if canvas.bounds.contains(local) {
            return canvas
        }
        return super.hitTest(point, with: event)
    }

    private func inkCanvas(containing point: CGPoint) -> PageInkCanvas? {
        func search(_ view: UIView) -> PageInkCanvas? {
            if let canvas = view as? PageInkCanvas {
                let local = convert(point, to: canvas)
                if canvas.bounds.contains(local) {
                    return canvas
                }
            }
            for child in view.subviews {
                if let found = search(child) {
                    return found
                }
            }
            return nil
        }
        return search(self)
    }

    func documentScrollView() -> UIScrollView? {
        if let scroll = documentView?.superview as? UIScrollView {
            return scroll
        }
        for child in subviews {
            if let scroll = child as? UIScrollView, !(child is PKCanvasView) {
                return scroll
            }
        }
        return nil
    }
}

struct PDFMarkupView: UIViewRepresentable {
    let pdfURL: URL
    @Binding var markup: MarkupDocument
    @Binding var tool: MarkupTool
    @Binding var color: Color
    @Binding var currentPage: Int
    @Binding var pageCount: Int
    var onRequestNote: (Int, CGPoint) -> Void
    var onMarkupChanged: () -> Void
    var bridge: MarkupBridge

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MarkupPDFView {
        let pdfView = MarkupPDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displayBox = .cropBox
        pdfView.displaysPageBreaks = true
        pdfView.interpolationQuality = .high
        pdfView.backgroundColor = .secondarySystemBackground
        pdfView.minScaleFactor = 0.5
        pdfView.maxScaleFactor = 8
        pdfView.usePageViewController(false)
        pdfView.delegate = context.coordinator
        pdfView.pageOverlayViewProvider = context.coordinator
        // Required so PDFPageOverlayViewProvider views participate in hit-testing.
        // Without this, PDFDocumentView eats Apple Pencil and the canvases never ink.
        // Stay on: toggling it after overlays attach is unreliable on iPadOS.
        pdfView.isInMarkupMode = true
        context.coordinator.installGestures(on: pdfView)
        context.coordinator.attach(bridge: bridge, pdfView: pdfView)
        context.coordinator.loadDocument(in: pdfView)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        return pdfView
    }

    func updateUIView(_ pdfView: MarkupPDFView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attach(bridge: bridge, pdfView: pdfView)
        if context.coordinator.loadedURL != pdfURL {
            context.coordinator.loadDocument(in: pdfView)
        }
        context.coordinator.syncToolState(in: pdfView)
        context.coordinator.reconcilePDFAnnotations(in: pdfView)
        context.coordinator.hydrateCanvasesIfNeeded(in: pdfView)
    }

    static func dismantleUIView(_ uiView: MarkupPDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    final class Coordinator: NSObject, PDFPageOverlayViewProvider, PDFViewDelegate, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        var parent: PDFMarkupView
        var loadedURL: URL?
        private var canvases: [ObjectIdentifier: PageInkCanvas] = [:]
        private var pageForCanvas: [ObjectIdentifier: PDFPage] = [:]
        private var appliedAnnotationIDs: Set<UUID> = []
        private var panRecognizer: UIPanGestureRecognizer?
        private var tapRecognizer: UITapGestureRecognizer?
        private var previewLayer: CAShapeLayer?
        private var saveWorkItem: DispatchWorkItem?
        private var isApplyingInk = false

        init(_ parent: PDFMarkupView) {
            self.parent = parent
        }

        func attach(bridge: MarkupBridge, pdfView: PDFView) {
            bridge.coordinator = self
            bridge.pdfView = pdfView
        }

        func loadDocument(in pdfView: MarkupPDFView) {
            canvases.removeAll()
            pageForCanvas.removeAll()
            appliedAnnotationIDs.removeAll()
            loadedURL = parent.pdfURL
            let document = PDFDocument(url: parent.pdfURL)
            pdfView.document = document
            parent.pageCount = document?.pageCount ?? 0
            parent.currentPage = parent.pageCount > 0 ? 1 : 0
            if let document {
                MarkupRenderer.applyAll(parent.markup, to: document)
            }
            appliedAnnotationIDs = Set(parent.markup.annotations.map(\.id))
            if let first = document?.page(at: 0) {
                pdfView.go(to: first)
            }
            syncToolState(in: pdfView)
        }

        func installGestures(on pdfView: PDFView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 1
            // Underline stays a selection drag (finger or Pencil). Ink/highlight
            // do not use this recognizer.
            pan.allowedTouchTypes = [
                NSNumber(value: UITouch.TouchType.direct.rawValue),
                NSNumber(value: UITouch.TouchType.indirect.rawValue),
                NSNumber(value: UITouch.TouchType.pencil.rawValue),
                NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)
            ]
            pan.requiresExclusiveTouchType = false
            pan.delegate = self
            pan.cancelsTouchesInView = true
            pdfView.addGestureRecognizer(pan)
            panRecognizer = pan

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.requiresExclusiveTouchType = false
            tap.delegate = self
            pdfView.addGestureRecognizer(tap)
            tapRecognizer = tap
        }

        func syncToolState(in pdfView: MarkupPDFView? = nil) {
            let host = pdfView ?? findMarkupPDFView()
            panRecognizer?.isEnabled = parent.tool.capturesPageDrag
            tapRecognizer?.isEnabled = parent.tool.capturesPageTap

            if let host {
                applyHostInteractionPolicy(to: host)
            }

            for canvas in canvases.values {
                configure(canvas)
            }
        }

        func reconcilePDFAnnotations(in pdfView: PDFView) {
            guard let document = pdfView.document else { return }
            let desired = Set(parent.markup.annotations.map(\.id))
            let extra = appliedAnnotationIDs.subtracting(desired)
            if !extra.isEmpty {
                for pageIndex in 0..<document.pageCount {
                    guard let page = document.page(at: pageIndex) else { continue }
                    for id in extra {
                        MarkupRenderer.remove(id: id, from: page)
                    }
                }
                appliedAnnotationIDs.subtract(extra)
            }
            for record in parent.markup.annotations where !appliedAnnotationIDs.contains(record.id) {
                guard let page = document.page(at: record.pageIndex) else { continue }
                MarkupRenderer.apply(record, to: page)
                appliedAnnotationIDs.insert(record.id)
            }
        }

        /// First SwiftUI frame can attach overlays before `markup.json` is read.
        /// Fill empty canvases once the sidecar arrives, without clobbering live strokes.
        func hydrateCanvasesIfNeeded(in pdfView: PDFView) {
            for canvas in canvases.values {
                guard canvas.drawing.strokes.isEmpty,
                      let page = pageForCanvas[ObjectIdentifier(canvas)] else { continue }
                let pageIndex = pdfView.document?.index(for: page) ?? 0
                let hasInk = parent.markup.drawingData(for: pageIndex)?.isEmpty == false
                let hasHighlight = parent.markup.highlightData(for: pageIndex)?.isEmpty == false
                if hasInk || hasHighlight {
                    applyStoredDrawing(to: canvas, pageIndex: pageIndex)
                }
            }
        }

        func pdfView(_ pdfView: PDFView, overlayViewFor page: PDFPage) -> UIView? {
            let key = ObjectIdentifier(page)
            if let existing = canvases[key] {
                configure(existing)
                if let host = pdfView as? MarkupPDFView {
                    applyHostInteractionPolicy(to: host)
                } else {
                    enablePageViewInteraction(in: pdfView)
                }
                return existing
            }

            let canvas = PageInkCanvas()
            canvas.delegate = self
            canvas.backgroundColor = .clear
            canvas.isOpaque = false
            canvas.minimumZoomScale = 1
            canvas.maximumZoomScale = 1
            canvas.isScrollEnabled = false
            canvas.delaysContentTouches = false
            canvas.alwaysBounceVertical = false
            canvas.alwaysBounceHorizontal = false
            canvas.contentInsetAdjustmentBehavior = .never
            configure(canvas)

            if let index = pdfView.document?.index(for: page) {
                applyStoredDrawing(to: canvas, pageIndex: index)
            }

            canvases[key] = canvas
            pageForCanvas[ObjectIdentifier(canvas)] = page

            // PDFPageView is created around the same turn; enable it after attach.
            DispatchQueue.main.async { [weak self, weak pdfView, weak canvas] in
                guard let self, let pdfView else { return }
                canvas?.activateOverlayAncestors()
                self.enablePageViewInteraction(in: pdfView)
                self.syncToolState(in: pdfView as? MarkupPDFView)
            }
            return canvas
        }

        func pdfView(_ view: PDFView, willDisplayOverlayView overlayView: UIView, for _: PDFPage) {
            (overlayView as? PageInkCanvas)?.activateOverlayAncestors()
            if let canvas = overlayView as? PageInkCanvas {
                configure(canvas)
            }
            if let host = view as? MarkupPDFView {
                applyHostInteractionPolicy(to: host)
            } else {
                enablePageViewInteraction(in: view)
            }
        }

        func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
            guard let canvas = overlayView as? PKCanvasView else { return }
            persistInk(canvas, page: page, document: pdfView.document)
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingInk, let page = pageForCanvas[ObjectIdentifier(canvasView)] else { return }
            persistInk(canvasView, page: page, document: findPDFView(from: canvasView)?.document)
            scheduleSave()
        }

        func addNote(text: String, pageIndex: Int, anchor: CGPoint, pdfView: PDFView?) {
            let record = MarkupRecord(
                pageIndex: pageIndex,
                kind: .note,
                colorHex: parent.color.hexString(),
                text: text,
                anchor: CodablePoint(anchor)
            )
            parent.markup.annotations.append(record)
            if let page = pdfView?.document?.page(at: pageIndex) {
                MarkupRenderer.apply(record, to: page)
                appliedAnnotationIDs.insert(record.id)
            }
            parent.onMarkupChanged()
        }

        func captureInk(from pdfView: PDFView?) {
            saveWorkItem?.cancel()
            persistAllInk(document: pdfView?.document)
        }

        func goToPage(_ pageIndex: Int, pdfView: PDFView?) {
            guard let pdfView,
                  let document = pdfView.document,
                  pageIndex >= 0,
                  pageIndex < document.pageCount,
                  let page = document.page(at: pageIndex) else { return }
            pdfView.go(to: page)
            updatePageIndex(pdfView)
        }

        func undo(in pdfView: PDFView?) {
            if parent.tool.enablesInkCanvas,
               let page = pdfView?.currentPage,
               let canvas = canvases[ObjectIdentifier(page)],
               canvas.undoManager?.canUndo == true {
                canvas.undoManager?.undo()
                return
            }
            guard let last = parent.markup.annotations.last else { return }
            parent.markup.annotations.removeLast()
            if let page = pdfView?.document?.page(at: last.pageIndex) {
                MarkupRenderer.remove(id: last.id, from: page)
            }
            appliedAnnotationIDs.remove(last.id)
            parent.onMarkupChanged()
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView else { return }
            updatePageIndex(pdfView)
            enablePageViewInteraction(in: pdfView)
            if let host = pdfView as? MarkupPDFView {
                syncToolState(in: host)
            }
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let pdfView = recognizer.view as? PDFView else { return }
            switch recognizer.state {
            case .began:
                attachPreview(to: pdfView)
                updatePreview(in: pdfView, from: recognizer)
            case .changed:
                updatePreview(in: pdfView, from: recognizer)
            case .ended:
                commitLinearMarkup(in: pdfView, from: recognizer)
                clearPreview()
            default:
                clearPreview()
            }
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let pdfView = recognizer.view as? PDFView else { return }
            let location = recognizer.location(in: pdfView)
            guard let page = pdfView.page(for: location, nearest: true) else { return }
            let pagePoint = pdfView.convert(location, to: page)
            let pageIndex = pdfView.document?.index(for: page) ?? 0

            if parent.tool == .eraser {
                if let annotation = annotationHit(on: page, at: pagePoint),
                   let token = annotation.userName,
                   let id = UUID(uuidString: token) {
                    parent.markup.annotations.removeAll { $0.id == id }
                    MarkupRenderer.remove(id: id, from: page)
                    appliedAnnotationIDs.remove(id)
                    parent.onMarkupChanged()
                }
                return
            }

            if parent.tool == .note {
                parent.onRequestNote(pageIndex, pagePoint)
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer == panRecognizer {
                return parent.tool.capturesPageDrag
            }
            if gestureRecognizer == tapRecognizer {
                return parent.tool.capturesPageTap
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer == tapRecognizer
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if gestureRecognizer == tapRecognizer, parent.tool == .eraser {
                return PencilInput.accepts(touch)
            }
            return true
        }

        private func configure(_ canvas: PageInkCanvas) {
            let inkColor = UIColor(parent.color)
            canvas.drawingPolicy = PencilInput.drawingPolicy
            canvas.drawingGestureRecognizer.allowedTouchTypes = PencilInput.stylusTouchTypes
            canvas.isUserInteractionEnabled = parent.tool.enablesInkCanvas
            canvas.isScrollEnabled = false
            canvas.delaysContentTouches = false
            canvas.canCancelContentTouches = false
            canvas.panGestureRecognizer.isEnabled = false
            canvas.activateOverlayAncestors()
            switch parent.tool {
            case .ink:
                canvas.tool = PKInkingTool(.pen, color: inkColor, width: 4)
            case .highlight:
                canvas.tool = PKInkingTool(
                    .marker,
                    color: inkColor.withAlphaComponent(0.55),
                    width: 16
                )
            case .eraser:
                canvas.tool = PKEraserTool(.vector)
            default:
                break
            }
        }

        /// PDFKit overlays only receive Pencil when markup mode stays on and the
        /// private overlay host is interaction-enabled. Finger pans use the
        /// document scroll view — do not disable it for Ink / Highlight / Eraser.
        private func applyHostInteractionPolicy(to host: MarkupPDFView) {
            host.isInMarkupMode = true
            host.inkHitTestingEnabled = parent.tool.enablesInkCanvas
            enablePageViewInteraction(in: host)

            guard let scroll = host.documentScrollView() else { return }
            if parent.tool.blocksDocumentScroll {
                scroll.isScrollEnabled = false
                return
            }
            scroll.isScrollEnabled = true
            #if targetEnvironment(simulator)
            scroll.panGestureRecognizer.allowedTouchTypes = PencilInput.allTouchTypes
            #else
            if parent.tool.enablesInkCanvas {
                scroll.panGestureRecognizer.allowedTouchTypes = PencilInput.fingerTouchTypes
            } else {
                scroll.panGestureRecognizer.allowedTouchTypes = PencilInput.allTouchTypes
            }
            #endif
        }

        private func applyStoredDrawing(to canvas: PKCanvasView, pageIndex: Int) {
            var combined = PKDrawing()
            if let data = parent.markup.drawingData(for: pageIndex),
               let ink = try? PKDrawing(data: data) {
                combined = combined.appending(ink)
            }
            if let data = parent.markup.highlightData(for: pageIndex),
               let highlight = try? PKDrawing(data: data) {
                combined = combined.appending(highlight)
            }
            isApplyingInk = true
            canvas.drawing = combined
            isApplyingInk = false
        }

        private func enablePageViewInteraction(in pdfView: PDFView) {
            guard let documentView = pdfView.documentView else { return }
            for subview in documentView.subviews {
                subview.isUserInteractionEnabled = true
            }
            for canvas in canvases.values {
                canvas.activateOverlayAncestors()
            }
        }

        private func annotationHit(on page: PDFPage, at point: CGPoint) -> PDFAnnotation? {
            if let exact = page.annotation(at: point), exact.userName != nil {
                return exact
            }
            let slop: CGFloat = 16
            let probe = CGRect(x: point.x - slop, y: point.y - slop, width: slop * 2, height: slop * 2)
            return page.annotations.first { annotation in
                annotation.userName != nil && annotation.bounds.intersects(probe)
            }
        }

        private func commitLinearMarkup(in pdfView: PDFView, from recognizer: UIPanGestureRecognizer) {
            let end = recognizer.location(in: pdfView)
            let translation = recognizer.translation(in: pdfView)
            let start = CGPoint(x: end.x - translation.x, y: end.y - translation.y)
            guard let page = pdfView.page(for: start, nearest: true) else { return }
            let startPage = pdfView.convert(start, to: page)
            let endPage = pdfView.convert(end, to: page)
            let pageIndex = pdfView.document?.index(for: page) ?? 0
            guard parent.tool == .underline else { return }
            let kind: MarkupKind = .underline

            var rects: [CodableRect] = []
            if let selection = page.selection(from: startPage, to: endPage) {
                for line in selection.selectionsByLine() {
                    let bounds = line.bounds(for: page)
                    if bounds.width > 1, bounds.height > 1 {
                        rects.append(CodableRect(bounds))
                    }
                }
            }
            if rects.isEmpty {
                let rect = CGRect(
                    x: min(startPage.x, endPage.x),
                    y: min(startPage.y, endPage.y),
                    width: abs(endPage.x - startPage.x),
                    height: max(abs(endPage.y - startPage.y), 12)
                )
                if rect.width > 6 {
                    rects.append(CodableRect(rect))
                }
            }
            guard !rects.isEmpty else { return }

            let record = MarkupRecord(
                pageIndex: pageIndex,
                kind: kind,
                colorHex: parent.color.hexString(),
                rects: rects
            )
            parent.markup.annotations.append(record)
            MarkupRenderer.apply(record, to: page)
            appliedAnnotationIDs.insert(record.id)
            parent.onMarkupChanged()
        }

        private func persistInk(_ canvas: PKCanvasView, page: PDFPage, document: PDFDocument?) {
            let pageIndex = document?.index(for: page) ?? max(parent.currentPage - 1, 0)
            var inkDrawing = PKDrawing()
            var highlightDrawing = PKDrawing()
            inkDrawing.strokes = canvas.drawing.strokes.filter { $0.ink.inkType != .marker }
            highlightDrawing.strokes = canvas.drawing.strokes.filter { $0.ink.inkType == .marker }
            parent.markup.upsertInk(
                pageIndex: pageIndex,
                drawingData: inkDrawing.strokes.isEmpty ? Data() : inkDrawing.dataRepresentation()
            )
            parent.markup.upsertHighlight(
                pageIndex: pageIndex,
                drawingData: highlightDrawing.strokes.isEmpty ? Data() : highlightDrawing.dataRepresentation()
            )
        }

        private func persistAllInk(document: PDFDocument?) {
            for canvas in canvases.values {
                guard let page = pageForCanvas[ObjectIdentifier(canvas)] else { continue }
                persistInk(canvas, page: page, document: document)
            }
        }

        private func scheduleSave() {
            saveWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.parent.onMarkupChanged()
            }
            saveWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }

        private func attachPreview(to pdfView: PDFView) {
            let layer = CAShapeLayer()
            layer.fillColor = UIColor(parent.color)
                .withAlphaComponent(parent.tool == .highlight ? 0.28 : 0.08)
                .cgColor
            layer.strokeColor = UIColor(parent.color).cgColor
            layer.lineWidth = parent.tool == .underline ? 2 : 1
            pdfView.layer.addSublayer(layer)
            previewLayer = layer
        }

        private func updatePreview(in pdfView: PDFView, from recognizer: UIPanGestureRecognizer) {
            let end = recognizer.location(in: pdfView)
            let translation = recognizer.translation(in: pdfView)
            let start = CGPoint(x: end.x - translation.x, y: end.y - translation.y)
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            previewLayer?.path = UIBezierPath(roundedRect: rect, cornerRadius: 2).cgPath
        }

        private func clearPreview() {
            previewLayer?.removeFromSuperlayer()
            previewLayer = nil
        }

        private func updatePageIndex(_ pdfView: PDFView) {
            guard let page = pdfView.currentPage, let document = pdfView.document else { return }
            parent.currentPage = document.index(for: page) + 1
            parent.pageCount = document.pageCount
        }

        private func findPDFView(from view: UIView) -> PDFView? {
            var current: UIView? = view
            while let node = current {
                if let pdf = node as? PDFView { return pdf }
                current = node.superview
            }
            return nil
        }

        private func findMarkupPDFView() -> MarkupPDFView? {
            if let host = parent.bridge.pdfView as? MarkupPDFView {
                return host
            }
            return nil
        }
    }
}
