//
//  CanvasExportManager.swift
//  InfinityPaper
//
//  Manages PDF and PNG export operations for the canvas.
//

import UIKit
import OSLog

/// Manages export operations for the canvas.
final class CanvasExportManager {
    private let logger = Logger(subsystem: "com.infinitypaper", category: "Export")

    /// Removes characters unsafe for file names; returns a non-empty prefix suitable for export names.
    static func sanitizedExportPrefix(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r")
        let scalars = trimmed.unicodeScalars.filter { !invalid.contains($0) }
        let cleaned = String(String.UnicodeScalarView(scalars))
        if cleaned.isEmpty { return AppSettings.Default.prefix }
        return String(cleaned.prefix(80))
    }
    
    /// Callback type for drawing strokes during export.
    typealias DrawStrokesCallback = (CGContext) -> Void
    
    /// Callback type for drawing noise during export.
    typealias DrawNoiseCallback = (CGContext, CGRect) -> Void
    
    /// Selects the export scope and applies the viewport transform before drawing screen coordinates.
    func exportCanvas(bounds: CGRect, viewport: CanvasViewport, fullDrawingBounds: @autoclosure () -> CGRect?,
                      backgroundColor: UIColor, drawStrokes: @escaping (CGContext, Bool) -> Void,
                      drawNoise: @escaping DrawNoiseCallback, presentShare: @escaping (URL) -> Void,
                      showToast: @escaping (String, ToastType) -> Void) {
        if AppSettings.defaults.bool(forKey: AppSettings.exportFull), let worldBounds = fullDrawingBounds() {
            exportFull(worldBounds: worldBounds, backgroundColor: backgroundColor,
                       drawStrokesWorld: { drawStrokes($0, false) }, presentShare: presentShare, showToast: showToast)
        } else {
            exportVisible(bounds: bounds, backgroundColor: backgroundColor, drawStrokes: { context in
                context.saveGState()
                context.concatenate(CanvasGeometry.viewportTransform(offset: viewport.offset, zoom: viewport.zoom))
                drawStrokes(context, true)
                context.restoreGState()
            }, drawNoise: drawNoise, presentShare: presentShare, showToast: showToast)
        }
    }

    /// Exports the entire drawing in `worldBounds` (already padded for stroke width by the caller).
    /// For viewport-only export, use `exportVisible`.
    func exportFull(
        worldBounds: CGRect,
        backgroundColor: UIColor,
        drawStrokesWorld: @escaping DrawStrokesCallback,
        presentShare: @escaping (URL) -> Void,
        showToast: @escaping (String, ToastType) -> Void
    ) {
        let defaults = AppSettings.defaults
        let margin = CGFloat(defaults.double(forKey: AppSettings.margin))
        let worldBounds = worldBounds.insetBy(dx: -margin, dy: -margin)
        let formatRaw = defaults.string(forKey: AppSettings.exportFormat) ?? AppSettings.Default.exportFormat.rawValue
        let format = ExportFormat(rawValue: formatRaw) ?? AppSettings.Default.exportFormat

        if format == .png {
            let resolution = CGFloat(defaults.double(forKey: AppSettings.resolution))
            let transparent = defaults.bool(forKey: AppSettings.transparent)
            exportFullPNG(
                backgroundColor: backgroundColor,
                worldBounds: worldBounds,
                resolution: resolution,
                transparent: transparent,
                drawStrokesWorld: drawStrokesWorld,
                presentShare: presentShare,
                showToast: showToast
            )
        } else {
            exportFullPDF(
                backgroundColor: backgroundColor,
                worldBounds: worldBounds,
                drawStrokesWorld: drawStrokesWorld,
                presentShare: presentShare,
                showToast: showToast
            )
        }
    }

    /// Exports the viewport. The stroke callback supplies screen coordinates, including zoom and scroll.
    /// - Parameters:
    ///   - bounds: The view bounds (viewport size)
    ///   - backgroundColor: The background color for export
    ///   - drawStrokes: Callback to draw strokes in the provided context (viewport coordinates)
    ///   - drawNoise: Callback to draw noise in the provided context and rect
    ///   - presentShare: Callback to present the share sheet with the exported file URL
    ///   - showToast: Callback to show toast messages
    func exportVisible(
        bounds: CGRect,
        backgroundColor: UIColor,
        drawStrokes: @escaping DrawStrokesCallback,
        drawNoise: @escaping DrawNoiseCallback,
        presentShare: @escaping (URL) -> Void,
        showToast: @escaping (String, ToastType) -> Void
    ) {
        let defaults = AppSettings.defaults
        let formatRaw = defaults.string(forKey: AppSettings.exportFormat) ?? AppSettings.Default.exportFormat.rawValue
        let format = ExportFormat(rawValue: formatRaw) ?? AppSettings.Default.exportFormat

        if format == .png {
            exportVisiblePNG(
                bounds: bounds,
                backgroundColor: backgroundColor,
                drawStrokes: drawStrokes,
                drawNoise: drawNoise,
                presentShare: presentShare,
                showToast: showToast
            )
        } else {
            exportVisiblePDF(
                bounds: bounds,
                backgroundColor: backgroundColor,
                drawStrokes: drawStrokes,
                presentShare: presentShare,
                showToast: showToast
            )
        }
    }
    
    // MARK: - Private
    
    private func exportVisiblePDF(
        bounds: CGRect,
        backgroundColor: UIColor,
        drawStrokes: @escaping DrawStrokesCallback,
        presentShare: @escaping (URL) -> Void,
        showToast: @escaping (String, ToastType) -> Void
    ) {
        let defaults = AppSettings.defaults
        let margin = CGFloat(defaults.double(forKey: AppSettings.margin))
        
        let pageBounds = CGRect(
            origin: .zero,
            size: CGSize(
                width: bounds.width + 2 * margin,
                height: bounds.height + 2 * margin
            )
        )
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let data = renderer.pdfData { context in
            context.beginPage()
            let cgContext = context.cgContext
            cgContext.setFillColor(backgroundColor.cgColor)
            cgContext.fill(pageBounds)
            cgContext.translateBy(x: margin, y: margin)
            cgContext.clip(to: CGRect(origin: .zero, size: bounds.size))
            drawStrokes(cgContext)
        }
        
        finishExport(data, extension: "pdf", presentShare: presentShare, showToast: showToast)
    }
    
    private func exportVisiblePNG(
        bounds: CGRect,
        backgroundColor: UIColor,
        drawStrokes: @escaping DrawStrokesCallback,
        drawNoise: @escaping DrawNoiseCallback,
        presentShare: @escaping (URL) -> Void,
        showToast: @escaping (String, ToastType) -> Void
    ) {
        let defaults = AppSettings.defaults
        let resolution = CGFloat(defaults.double(forKey: AppSettings.resolution))
        let margin = CGFloat(defaults.double(forKey: AppSettings.margin))
        let includeNoise = defaults.bool(forKey: AppSettings.includeNoise)
        let transparent = defaults.bool(forKey: AppSettings.transparent)
        
        let contentSize = bounds.size
        let imageSize = CGSize(width: contentSize.width + 2 * margin, height: contentSize.height + 2 * margin)
        let image = renderPNG(size: imageSize, scale: resolution, background: backgroundColor, transparent: transparent) {
            if includeNoise && !transparent, let noiseCtx = UIGraphicsGetCurrentContext() {
                noiseCtx.saveGState()
                noiseCtx.translateBy(x: margin, y: margin)
                drawNoise(noiseCtx, CGRect(origin: .zero, size: contentSize))
                noiseCtx.restoreGState()
            }

            if let strokeCtx = UIGraphicsGetCurrentContext() {
                strokeCtx.saveGState()
                strokeCtx.translateBy(x: margin, y: margin)
                strokeCtx.clip(to: CGRect(origin: .zero, size: contentSize))
                drawStrokes(strokeCtx)
                strokeCtx.restoreGState()
            }
        }
        
        finishPNG(image, presentShare: presentShare, showToast: showToast)
    }
    
    private func exportFullPDF(
        backgroundColor: UIColor,
        worldBounds: CGRect,
        drawStrokesWorld: @escaping DrawStrokesCallback,
        presentShare: @escaping (URL) -> Void,
        showToast: @escaping (String, ToastType) -> Void
    ) {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: worldBounds.size))
        let data = renderer.pdfData { context in
            context.beginPage()
            let cgContext = context.cgContext
            cgContext.setFillColor(backgroundColor.cgColor)
            cgContext.fill(CGRect(origin: .zero, size: worldBounds.size))
            cgContext.translateBy(x: -worldBounds.origin.x, y: -worldBounds.origin.y)
            drawStrokesWorld(cgContext)
        }
        
        finishExport(data, extension: "pdf", presentShare: presentShare, showToast: showToast)
    }
    
    private func exportFullPNG(
        backgroundColor: UIColor,
        worldBounds: CGRect,
        resolution: CGFloat,
        transparent: Bool,
        drawStrokesWorld: @escaping DrawStrokesCallback,
        presentShare: @escaping (URL) -> Void,
        showToast: @escaping (String, ToastType) -> Void
    ) {
        let imageSize = CGSize(width: worldBounds.size.width, height: worldBounds.size.height)
        let effectiveScale = CanvasGeometry.exportScale(size: imageSize, requested: resolution)
        let image = renderPNG(size: imageSize, scale: effectiveScale, background: backgroundColor, transparent: transparent) {
            // Paper texture is only included in viewport PNG exports.

            guard let ctx = UIGraphicsGetCurrentContext() else { return }
            ctx.saveGState()
            ctx.translateBy(x: -worldBounds.origin.x, y: -worldBounds.origin.y)
            drawStrokesWorld(ctx)
            ctx.restoreGState()
        }
        
        finishPNG(image, presentShare: presentShare, showToast: showToast)
    }

    private func renderPNG(size: CGSize, scale: CGFloat, background: UIColor, transparent: Bool,
                           draw: () -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.setFillColor((transparent ? UIColor.clear : background).cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: size))
            draw()
        }
    }

    private func finishPNG(_ image: UIImage, presentShare: (URL) -> Void,
                           showToast: (String, ToastType) -> Void) {
        guard let data = image.pngData() else {
            logger.error("Export PNG data failed")
            reportExportFailure(showToast: showToast)
            return
        }
        finishExport(data, extension: "png", presentShare: presentShare, showToast: showToast)
    }

    private func reportExportFailure(showToast: (String, ToastType) -> Void) {
        showToast("Export failed", .error)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func finishExport(
        _ data: Data,
        extension ext: String,
        presentShare: (URL) -> Void,
        showToast: (String, ToastType) -> Void
    ) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent(exportFileName(extension: ext))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            presentShare(url)
            showToast("\(ext.uppercased()) exported", .success)
        } catch {
            logger.error("Export write failed: \(error.localizedDescription)")
            reportExportFailure(showToast: showToast)
        }
    }

    private func exportFileName(extension ext: String) -> String {
        let defaults = AppSettings.defaults
        let autoName = defaults.bool(forKey: AppSettings.autoName)
        let prefix = Self.sanitizedExportPrefix(defaults.string(forKey: AppSettings.prefix))
        
        if autoName {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            formatter.timeZone = TimeZone.current
            let stamp = formatter.string(from: Date())
            return "\(prefix)\(stamp).\(ext)"
        }
        
        return "InfinityPaper.\(ext)"
    }
}

