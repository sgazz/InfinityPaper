//
//  ContentView.swift
//  InfinityPaper
//
//  Created by Gazza on 17. 1. 2026..
//

import SwiftUI

struct ContentView: View {

    var body: some View {
        ZStack {
            TapeCanvasView()
            .ignoresSafeArea()
        }
    }
}

private struct ToolbarSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = CGSize(width: 340, height: 52)
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct TapeCanvasView: View {
    @StateObject private var toolbarBroker = CanvasToolbarStateBroker()
    @State private var showSettings = false
    @AppStorage("firstUseOrientationDismissed") private var firstUseOrientationDismissed = false

    @State private var toolbarMeasuredSize: CGSize = ToolbarSizePreferenceKey.defaultValue
    @State private var showClearCanvasConfirmation = false
    @State private var showNewSpaceConfirmation = false
    @State private var chromeHiddenForFocus = false


    var body: some View {
        ZStack {
            TapeCanvasRepresentable(
                toolbarBroker: toolbarBroker,
                onOpenFullSettings: { DispatchQueue.main.async { showSettings = true } }
            )
            .ignoresSafeArea()

            GeometryReader { _ in
                VStack {
                    Spacer(minLength: 0)
                    if !firstUseOrientationDismissed {
                        VStack(spacing: 10) {
                            Text(NSLocalizedString("first_use.lead", comment: "First session one-line hint"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(NSLocalizedString("first_use.body", comment: "First session second line"))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 28)
                        .padding(.top, 64)
                        .padding(.bottom, 8)
                        .opacity(chromeHiddenForFocus ? 0 : 1)
                        .allowsHitTesting(!chromeHiddenForFocus)
                        .transition(.opacity)
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                firstUseOrientationDismissed = true
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .allowsHitTesting(!chromeHiddenForFocus)

            GeometryReader { geo in
                let safe = geo.safeAreaInsets
                let isiPhonePortrait = UIDevice.current.userInterfaceIdiom == .phone && geo.size.height > geo.size.width
                let display = CGPoint(
                    x: geo.size.width / 2,
                    y: safe.top + 11 + toolbarMeasuredSize.height / 2
                        + (isiPhonePortrait ? toolbarMeasuredSize.height : 0)
                )

                ZStack {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)

                    CanvasFloatingToolbar(
                        broker: toolbarBroker,
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
                                showNewSpaceConfirmation = true
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
                    .frame(maxWidth: max(0, geo.size.width - safe.leading - safe.trailing - 16))
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(
                                key: ToolbarSizePreferenceKey.self,
                                value: g.size
                            )
                        }
                    )
                    .position(display)
                    .allowsHitTesting(true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .opacity(chromeHiddenForFocus ? 0 : 1)
            .allowsHitTesting(!chromeHiddenForFocus)
        }
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
        .onPreferenceChange(ToolbarSizePreferenceKey.self) { toolbarMeasuredSize = $0 }
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
        .confirmationDialog(
            String(localized: "toolbar.new_space_confirm_title"),
            isPresented: $showNewSpaceConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "toolbar.new_space_confirm_action"), role: .destructive) {
                toolbarBroker.canvas?.toolbarPerformNewSpace()
            }
            Button(String(localized: "action.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "toolbar.new_space_confirm_message"))
        }
        .sheet(isPresented: $showSettings) {
            if let cv = toolbarBroker.canvas {
                SettingsView(
                    palette: cv.exposedPrimaryPalette,
                    currentColorIndex: cv.toolbarSelectedPaletteIndex,
                    currentLineWidth: cv.toolbarBaseLineWidth,
                    onSelectColor: { index in
                        cv.toolbarSelectColor(at: index)
                    },
                    onLineWidthChanged: { width in
                        cv.setBaseLineWidthFromSettings(width)
                    },
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
}

private struct TapeCanvasRepresentable: UIViewRepresentable {
    @ObservedObject var toolbarBroker: CanvasToolbarStateBroker
    var onOpenFullSettings: () -> Void

    func makeUIView(context: Context) -> TapeCanvasUIView {
        let view = TapeCanvasUIView()
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

