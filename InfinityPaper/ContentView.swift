//
//  ContentView.swift
//  InfinityPaper
//
//  Created by Gazza on 17. 1. 2026..
//

import SwiftUI

struct ContentView: View {

    var body: some View { DrawingLibraryView() }
}

struct TapeCanvasView: View {
    let document: DrawingDocument
    let sessionURL: URL
    let onClose: (Bool) -> Void
    @State private var closing = false
    @State private var closeError: String?

    @StateObject private var toolbarBroker = CanvasToolbarStateBroker()
    @State private var showSettings = false
    @State private var showHelp = false
    @AppStorage(AppSettings.pencilOnly) private var pencilOnly = false
    private var pencilOnlyMode: Bool {
        CanvasInputPolicy.pencilOnly(requested: pencilOnly, supportsPencil: UIDevice.current.userInterfaceIdiom == .pad)
    }
    @AppStorage("firstUseOrientationDismissed") private var firstUseOrientationDismissed = false

    @State private var showClearCanvasConfirmation = false
    @State private var chromeHiddenForFocus = false


    var body: some View {
        ZStack {
            TapeCanvasRepresentable(
                toolbarBroker: toolbarBroker,
                sessionURL: sessionURL,
                onOpenFullSettings: { DispatchQueue.main.async { showSettings = true } }
            )
            .ignoresSafeArea(edges: .bottom)

            if !firstUseOrientationDismissed && !chromeHiddenForFocus {
                VStack {
                    Spacer(minLength: 0)
                    CanvasQuickHelpView(pencilOnly: pencilOnlyMode, onLearnMore: { showHelp = true }) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            firstUseOrientationDismissed = true
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                .transition(.opacity)
            }

        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !chromeHiddenForFocus {
                CanvasFloatingToolbar(
                    broker: toolbarBroker,
                    onMyDrawings: { closeDrawing(newDrawing: false) },
                    onSelectColor: { idx in
                        toolbarBroker.canvas?.toolbarSelectColor(at: idx)
                    },
                    onSelectLineWidthPreset: { idx in
                        toolbarBroker.canvas?.toolbarSetLineWidthPreset(at: idx)
                    },
                    onUndo: {
                        toolbarBroker.canvas?.toolbarUndo()
                    },
                    onRedo: {
                        toolbarBroker.canvas?.toolbarRedo()
                    },
                    onExport: {
                        toolbarBroker.canvas?.toolbarExport()
                    },
                    onSettings: {
                        toolbarBroker.canvas?.toolbarOpenFullSettings()
                    },
                    onTogglePaperLock: {
                        DispatchQueue.main.async {
                            guard let canvas = toolbarBroker.canvas else { return }
                            canvas.toolbarSetPaperMovementLocked(!canvas.toolbarPaperMovementLocked)
                        }
                    },
                    onInfinityClearCanvas: {
                        DispatchQueue.main.async {
                            showClearCanvasConfirmation = true
                        }
                    },
                    onInfinityNewSpace: {
                        DispatchQueue.main.async {
                            closeDrawing(newDrawing: true)
                        }
                    },
                    onInfinityCenterView: {
                        DispatchQueue.main.async {
                            toolbarBroker.canvas?.toolbarCenterViewOnContent()
                        }
                    },
                    onInfinityFocusMode: {
                        withAnimation(.easeOut(duration: 0.28)) {
                            chromeHiddenForFocus = true
                        }
                    },
                    onInfinityZoomIn: {
                        DispatchQueue.main.async {
                            toolbarBroker.canvas?.toolbarZoomIn()
                        }
                    },
                    onInfinityZoomOut: {
                        DispatchQueue.main.async {
                            toolbarBroker.canvas?.toolbarZoomOut()
                        }
                    },
                    onInfinityResetView: {
                        DispatchQueue.main.async {
                            toolbarBroker.canvas?.toolbarResetView()
                        }
                    },
                    onInfinityFitContent: {
                        DispatchQueue.main.async {
                            toolbarBroker.canvas?.toolbarFitContent()
                        }
                    }
                )
                .disabled(closing)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 8)
            }
        }
        .background(Color(uiColor: PaperSurface.adaptiveBackgroundColor).ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if chromeHiddenForFocus {
                Button {
                    withAnimation(.easeOut(duration: 0.28)) {
                        chromeHiddenForFocus = false
                    }
                } label: {
                    Text(String(localized: "toolbar.focus_show_tools"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.bottom, 28)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay { if closing { ProgressView("Saving drawing…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .accessibilityLabel(document.title)
        .confirmationDialog(
            String(localized: "toolbar.clear_confirm_title"),
            isPresented: $showClearCanvasConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "toolbar.clear_confirm_action"), role: .destructive) {
                toolbarBroker.canvas?.toolbarClearCanvasConfirmed()
            }
            Button(String(localized: "action.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "toolbar.clear_confirm_message"))
        }
        .alert("Could not save drawing", isPresented: Binding(get: { closeError != nil }, set: { if !$0 { closeError = nil } })) {
            Button("OK", role: .cancel) { closeError = nil }
        } message: { Text(closeError ?? "") }
        .sheet(isPresented: $showHelp) { CanvasHelpView() }
        .sheet(isPresented: $showSettings) {
            if let cv = toolbarBroker.canvas {
                SettingsView(
                    referenceImage: cv.referenceImage,
                    referenceViewport: cv.referenceViewport,
                    onReferenceChanged: { cv.setReferenceImage($0) },
                    palette: cv.exposedPrimaryPalette,
                    currentColorIndex: cv.toolbarSelectedPaletteIndex,
                    currentLineWidth: cv.toolbarBaseLineWidth,
                    onSelectColor: { index in
                        cv.toolbarSelectColor(at: index)
                    },
                    onLineWidthChanged: { width in
                        cv.setBaseLineWidthFromSettings(width)
                    },
                    currentPattern: cv.paperPattern,
                    currentSpacing: cv.paperSpacing,
                    onPatternChanged: { pattern, spacing in cv.setPaperPattern(pattern, spacing: spacing) },
                    onLoadPreviousSession: {
                        cv.loadSessionFromSettings()
                    },
                    onDismiss: { showSettings = false }
                )
            } else {
                Color.clear
                    .onAppear { showSettings = false }
            }
        }
    }
    private func closeDrawing(newDrawing: Bool) {
        guard !closing, let canvas = toolbarBroker.canvas else { return }
        closing = true
        canvas.saveForLibrary { result in
            closing = false
            switch result {
            case .success: onClose(newDrawing)
            case .failure(let error): closeError = error.localizedDescription
            }
        }
    }

}

private struct TapeCanvasRepresentable: UIViewRepresentable {
    @ObservedObject var toolbarBroker: CanvasToolbarStateBroker
    let sessionURL: URL
    var onOpenFullSettings: () -> Void

    func makeUIView(context: Context) -> TapeCanvasUIView {
        let view = TapeCanvasUIView(sessionURL: sessionURL)
        view.onOpenFullSettings = onOpenFullSettings
        view.onToolbarStateChange = { [weak toolbarBroker] in
            toolbarBroker?.syncFromCanvas()
        }
        toolbarBroker.attach(view)
        return view
    }

    func updateUIView(_ uiView: TapeCanvasUIView, context: Context) {
        uiView.onOpenFullSettings = onOpenFullSettings
        uiView.onToolbarStateChange = { [weak toolbarBroker] in
            toolbarBroker?.syncFromCanvas()
        }
    }
}

