import SwiftUI

struct SettingsView: View {
    // MARK: - Brush, export and session settings
    @Environment(\.colorScheme) private var colorScheme
    @State private var showReference = false
    @State private var referenceImage: ReferenceImage?
    let referenceViewport: CGRect
    let onReferenceChanged: (ReferenceImage?) -> Void
    @AppStorage(AppSettings.includeReferenceImage) private var includeReferenceImage = true
    @State private var selectedColorIndex: Int
    @State private var baseLineWidth: CGFloat
    @AppStorage(AppSettings.exportFull) private var exportFullDrawing = false
    @AppStorage(AppSettings.exportFormat) private var exportFormat = AppSettings.Default.exportFormat
    @AppStorage(AppSettings.resolution) private var exportResolution = AppSettings.Default.resolution
    @AppStorage(AppSettings.margin) private var exportMargin = AppSettings.Default.margin
    @AppStorage(AppSettings.includeNoise) private var includeBackgroundNoise = AppSettings.Default.includeNoise
    @AppStorage(AppSettings.transparent) private var transparentBackground = AppSettings.Default.transparent
    @AppStorage(AppSettings.autoName) private var autoNameExports = AppSettings.Default.autoName
    @AppStorage(AppSettings.prefix) private var exportPrefix = AppSettings.Default.prefix
    @AppStorage(AppSettings.autosaveMode) private var autosaveMode = AppSettings.Default.autosaveMode
    @AppStorage(AppSettings.autoload) private var autoloadOnLaunch = AppSettings.Default.autoload
    @AppStorage(AppSettings.pencilOnly) private var pencilOnly = false
    @AppStorage(AppSettings.pencilPressure) private var pencilPressure = true
    @AppStorage(AppSettings.pencilTilt) private var pencilTilt = false
    @AppStorage(AppSettings.pencilSensitivity) private var pencilSensitivity = 0.5
    @State private var paperSurface: PaperSurface
    @State private var paperPattern: PaperPattern
    @State private var paperSpacing: CGFloat
    @AppStorage(AppSettings.includePaperPattern) private var includePaperPattern = true
    let onPatternChanged: (PaperPattern, CGFloat) -> Void

    let palette: [UIColor]
    let onSelectColor: (Int) -> Void
    let onLineWidthChanged: (CGFloat) -> Void
    let onLoadPreviousSession: () -> Void
    let onDismiss: () -> Void

    init(
        referenceImage: ReferenceImage?,
        referenceViewport: CGRect,
        onReferenceChanged: @escaping (ReferenceImage?) -> Void,
        palette: [UIColor],
        currentColorIndex: Int,
        currentLineWidth: CGFloat,
        onSelectColor: @escaping (Int) -> Void,
        onLineWidthChanged: @escaping (CGFloat) -> Void,
        currentPattern: PaperPattern,
        currentSpacing: CGFloat,
        onPatternChanged: @escaping (PaperPattern, CGFloat) -> Void,
        onLoadPreviousSession: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        _referenceImage = State(initialValue: referenceImage)
        self.referenceViewport = referenceViewport
        self.onReferenceChanged = onReferenceChanged
        _paperPattern = State(initialValue: currentPattern)
        _paperSpacing = State(initialValue: currentSpacing)
        self.onPatternChanged = onPatternChanged
        self.palette = palette
        self.onSelectColor = onSelectColor
        self.onLineWidthChanged = onLineWidthChanged
        self.onLoadPreviousSession = onLoadPreviousSession
        self.onDismiss = onDismiss

        _selectedColorIndex = State(initialValue: min(max(0, currentColorIndex), max(0, palette.count - 1)))
        _baseLineWidth = State(initialValue: currentLineWidth)
        _paperSurface = State(initialValue: PaperSurface.current())

    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Paper")) {
                    Picker("Paper surface", selection: $paperSurface) {
                        Text("Quiet Paper").tag(PaperSurface.quiet)
                        Text("Electric Paper").tag(PaperSurface.electric)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: paperSurface) { _, newValue in
                        PaperSurface.setCurrent(newValue)
                    }
                    Picker("Guides", selection: $paperPattern) {
                        ForEach(PaperPattern.allCases, id: \.self) { pattern in Text(pattern.title).tag(pattern) }
                    }
                    .onChange(of: paperPattern) { _, value in onPatternChanged(value, paperSpacing) }
                    if paperPattern != .plain {
                        VStack(alignment: .leading) {
                            Text("Guide spacing: \(Int(paperSpacing)) pt")
                            Slider(value: $paperSpacing, in: PaperPatternLayout.spacingRange, step: 4)
                                .accessibilityLabel("Guide spacing")
                                .onChange(of: paperSpacing) { _, value in onPatternChanged(paperPattern, value) }
                        }
                    }
                }

                Section("Reference image") {
                    Button(referenceImage == nil ? "Import reference image" : "Edit reference image", systemImage: "photo.on.rectangle") { showReference = true }
                }

                Section(header: Text("Brush & Canvas")) {
                    colorPaletteSection
                    lineWidthSection
                }

                if UIDevice.current.userInterfaceIdiom == .pad { pencilSection }

                Section(header: Text("Export & Share")) {
                    exportSection
                }

                Section(header: Text("Session & Storage"), footer: Text("Each drawing is saved separately. Clear empties the current drawing after confirmation; other drawings stay in your library.")) {
                    autosaveSection
                    Button {
                        onLoadPreviousSession()
                    } label: {
                        Text("Load last saved session")
                    }
                }

                Section(header: Text("About")) {
                    Text("InfinityPaper")
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")")
                    if let websiteURL = AppLinks.website {
                        Link("Website", destination: websiteURL)
                    }
                }
            }
            .sheet(isPresented: $showReference) {
                ReferenceImageSettingsView(reference: referenceImage, viewport: referenceViewport) { image in
                    referenceImage = image
                    onReferenceChanged(image)
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("Done") { onDismiss() } } }
        }
    }
    
    private var pencilSection: some View {
        Section {
            Toggle("Draw only with Apple Pencil", isOn: $pencilOnly)
                .onChange(of: pencilOnly) { _, _ in
                    NotificationCenter.default.post(name: AppSettings.pencilInputDidChange, object: nil)
                }
            Toggle("Pressure changes line width", isOn: $pencilPressure)
            if pencilPressure {
                VStack(alignment: .leading) {
                    Text("Pressure sensitivity")
                    Slider(value: $pencilSensitivity, in: 0...1)
                        .accessibilityLabel("Pressure sensitivity")
                    Text("Higher sensitivity makes lighter pressure produce wider strokes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle("Tilt widens strokes", isOn: $pencilTilt)
        } header: { Text("Apple Pencil") }
        footer: { Text("In Pencil-only mode, one finger moves the paper and two fingers zoom. Pressure and tilt affect new strokes when supported by your Pencil. Turn off paper movement lock to pan.") }
    }

    private var autosaveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Autosave mode", selection: $autosaveMode) {
                Text("On background").tag(AutosaveMode.onBackground)
                Text("Periodic").tag(AutosaveMode.periodic)
            }
            .pickerStyle(.segmented)
            .onChange(of: autosaveMode) { _, _ in
                NotificationCenter.default.post(name: AppSettings.autosaveModeDidChange, object: nil)
            }
            Text("On background: save when you leave the app. Periodic: also save every 60 seconds.")
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle("Reopen last drawing on launch", isOn: $autoloadOnLaunch)
            Text("When on, the last open drawing is reopened on app launch.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var colorPaletteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Default brush color")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(palette.enumerated()), id: \.0) { idx, _ in
                        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
                        let color = Color(CanvasBrush.color(at: idx, traits: traits))
                        Button {
                            selectedColorIndex = idx
                            onSelectColor(idx)
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 32, height: 32)
                                .overlay(Circle().stroke(Color.primary.opacity(selectedColorIndex == idx ? 0.6 : 0.15),
                                                         lineWidth: selectedColorIndex == idx ? 3 : 1))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(CanvasBrush.colorName(at: idx)))
                        .accessibilityAddTraits(selectedColorIndex == idx ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var lineWidthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Default line width: \(String(format: "%.1f", baseLineWidth))")
            Slider(value: $baseLineWidth, in: 1.0...8.0, step: 0.2) {
                Text("Line Width")
            } minimumValueLabel: {
                Text("1.0")
            } maximumValueLabel: {
                Text("8.0")
            }
            .onChange(of: baseLineWidth) { _, newValue in
                onLineWidthChanged(newValue)
            }
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Include reference image", isOn: $includeReferenceImage)
            Toggle("Include paper guides", isOn: $includePaperPattern)
            Toggle("Export entire drawing", isOn: $exportFullDrawing)
            Picker("Export format", selection: $exportFormat) {
                Text("PDF").tag(ExportFormat.pdf)
                Text("PNG").tag(ExportFormat.png)
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Margins")
                Slider(value: $exportMargin, in: 0...64, step: 2)
                Text("\(Int(exportMargin)) pt")
            }

            if exportFormat == .png {
                HStack {
                    Text("Resolution")
                    Slider(value: $exportResolution, in: 1.0...4.0, step: 0.5)
                    Text(String(format: "x%.1f", exportResolution))
                }

                Toggle("Include background noise (viewport PNG)", isOn: $includeBackgroundNoise)
                    .disabled(exportFullDrawing)
                Toggle("Transparent background (PNG)", isOn: $transparentBackground)
            }

            Toggle("Auto-name exports", isOn: $autoNameExports)
            TextField("Export prefix", text: $exportPrefix)
                .disabled(!autoNameExports)
                .textInputAutocapitalization(.never)
                .onAppear { exportPrefix = CanvasExportManager.sanitizedExportPrefix(exportPrefix) }
                .onChange(of: exportPrefix) { _, newValue in
                    let sanitized = CanvasExportManager.sanitizedExportPrefix(newValue)
                    if sanitized != newValue {
                        exportPrefix = sanitized
                    }
                }
        }
    }

}
