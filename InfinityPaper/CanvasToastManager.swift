//
//  CanvasToastManager.swift
//  InfinityPaper
//
//  Manages toast message presentation for the canvas view.
//

import UIKit

/// Toast message types with distinct visual styles.
enum ToastType {
    case success
    case error
    case warning
    case info

    var backgroundColor: UIColor {
        switch self {
        case .success: return UIColor(red: 0.12, green: 0.42, blue: 0.2, alpha: 1)
        case .error: return UIColor(red: 0.7, green: 0.12, blue: 0.15, alpha: 1)
        case .warning: return UIColor(red: 0.95, green: 0.65, blue: 0.1, alpha: 1)
        case .info: return UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.2, alpha: 1) : UIColor(white: 0.95, alpha: 1) }
        }
    }

    var textColor: UIColor {
        switch self {
        case .warning: return .black
        case .info: return .label
        default: return .white
        }
    }
}

/// Manages toast message presentation for the canvas.
final class CanvasToastManager {
    private let label: UILabel
    private var timer: Timer?
    private var currentToastType: ToastType = .info
    private weak var parentView: UIView?
    private var currentTraitCollection: UITraitCollection
    
    private enum Layout {
        static let toastBottomOffset: CGFloat = 96
        static let toastWidthMax: CGFloat = 220
        static let toastHorizontalMargin: CGFloat = 32
        static let toastVisibleDuration: TimeInterval = 1.2
    }
    
    private enum DesignTokens {
        static let cornerRadiusMedium: CGFloat = 10
        static let animationDurationFast: TimeInterval = 0.15
        static let animationDurationMedium: TimeInterval = 0.2
    }
    
    /// Initializes the toast manager with a parent view.
    /// - Parameters:
    ///   - parentView: The view that will host the toast label
    ///   - traitCollection: Initial trait collection for appearance
    init(parentView: UIView, traitCollection: UITraitCollection) {
        self.parentView = parentView
        self.currentTraitCollection = traitCollection
        self.label = UILabel()
        configureLabel()
        parentView.addSubview(label)
    }
    
    /// Updates the trait collection for appearance changes (e.g., dark mode).
    func updateTraitCollection(_ traitCollection: UITraitCollection) {
        currentTraitCollection = traitCollection
        updateAppearance()
    }
    
    /// Updates the toast label frame for layout changes.
    /// - Parameter bounds: The parent view's bounds
    func updateLayout(in bounds: CGRect) {
        let toastWidth = min(bounds.width - Layout.toastHorizontalMargin, Layout.toastWidthMax)
        label.frame = CGRect(
            x: (bounds.width - toastWidth) / 2,
            y: bounds.height - Layout.toastBottomOffset,
            width: toastWidth,
            height: 36
        )
    }
    
    /// Shows a toast message with the specified type.
    /// - Parameters:
    ///   - text: The message text to display
    ///   - type: The toast type (default: .info)
    func show(text: String, type: ToastType = .info) {
        guard let parentView = parentView else { return }
        
        timer?.invalidate()
        label.text = text
        updateAppearance(for: type)
        parentView.bringSubviewToFront(label)
        
        // Animate based on type: error/warning get slight scale animation
        let scale: CGFloat = (type == .error || type == .warning) ? 1.05 : 1.0
        
        label.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        label.alpha = 0
        
        UIView.animate(withDuration: DesignTokens.animationDurationFast, delay: 0, options: [.curveEaseOut]) {
            self.label.alpha = 1
            self.label.transform = CGAffineTransform(scaleX: scale, y: scale)
        } completion: { _ in
            UIView.animate(withDuration: DesignTokens.animationDurationFast * 0.67) {
                self.label.transform = .identity
            }
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: Layout.toastVisibleDuration, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: DesignTokens.animationDurationMedium) {
                self?.label.alpha = 0
                self?.label.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
            }
        }
    }
    
    // MARK: - Private
    
    private func configureLabel() {
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.layer.cornerRadius = DesignTokens.cornerRadiusMedium
        label.layer.masksToBounds = true
        label.alpha = 0
        updateAppearance()
    }
    
    private func updateAppearance(for type: ToastType? = nil) {
        if let type { currentToastType = type }
        let toastType = currentToastType
        label.textColor = toastType.textColor.resolvedColor(with: currentTraitCollection)
        label.backgroundColor = toastType.backgroundColor.resolvedColor(with: currentTraitCollection)
    }
}
