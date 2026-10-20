import SwiftUI

struct DrawingLibraryView: View {
    private let store = DrawingLibraryStore()
    @State private var drawings: [DrawingSummary] = []
    @State private var selected: DrawingDocument?
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var renameTarget: DrawingDocument?
    @State private var title = ""
    @State private var deleteTarget: DrawingDocument?
    @State private var createAfterClosing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if drawings.isEmpty, !busy {
                    ContentUnavailableView("Your drawings", systemImage: "square.stack.3d.up",
                        description: Text("Create a drawing to start sketching. Your work is saved separately."))
                        .padding(.top, 80)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 16)], spacing: 20) {
                        ForEach(drawings) { drawing in
                            Button {
                                Task { await perform { selected = try await store.open(drawing.id) } }
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    DrawingThumbnail(drawing: drawing)
                                        .frame(height: 140)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    Text(drawing.document.title).font(.headline).lineLimit(2)
                                    Text(drawing.updatedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Open drawing")
                            .contextMenu { drawingActions(drawing) }
                            .overlay(alignment: .topTrailing) {
                                Menu { drawingActions(drawing) } label: {
                                    Image(systemName: "ellipsis")
                                        .padding(10)
                                        .background(.regularMaterial, in: Circle())
                                }
                                .accessibilityLabel("Actions for \(drawing.document.title)")
                                .padding(6)
                            }
                            .accessibilityAction(named: "Rename") { title = drawing.document.title; renameTarget = drawing.document }
                            .accessibilityAction(named: "Duplicate") {
                                Task { await perform { _ = try await store.duplicate(drawing.id); try await reload() } }
                            }
                            .accessibilityAction(named: "Delete") { deleteTarget = drawing.document }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("My drawings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await perform { try await reload() } } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New drawing", systemImage: "plus") { Task { await perform { selected = try await store.create() } } }
                }
            }
            .disabled(busy)
            .overlay { if busy { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        }
        .task {
            await perform {
                try await reload()
                if AppSettings.defaults.bool(forKey: AppSettings.autoload),
                   let raw = AppSettings.defaults.string(forKey: DrawingLibraryStore.activeDrawingKey),
                   let id = UUID(uuidString: raw), drawings.contains(where: { $0.id == id }) {
                    selected = try await store.open(id)
                }
            }
        }
        .fullScreenCover(item: $selected, onDismiss: {
            AppSettings.defaults.removeObject(forKey: DrawingLibraryStore.activeDrawingKey)
            Task {
                await perform {
                    try await reload()
                    if createAfterClosing {
                        createAfterClosing = false
                        selected = try await store.create()
                    }
                }
            }
        }) { document in
            TapeCanvasView(document: document, sessionURL: store.sessionURL(for: document.id)) { newDrawing in
                createAfterClosing = newDrawing
                selected = nil
            }
            .id(document.id)
            .interactiveDismissDisabled()
            .onAppear { AppSettings.defaults.set(document.id.uuidString, forKey: DrawingLibraryStore.activeDrawingKey) }
        }
        .alert("Rename drawing", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } }), presenting: renameTarget) { document in
            TextField("Drawing name", text: $title)
            Button("Save") {
                let newTitle = title
                renameTarget = nil
                Task { await perform { try await store.rename(document.id, title: newTitle); try await reload() } }
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: { _ in Text("Choose a name for this drawing.") }
        .alert("Delete drawing?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), presenting: deleteTarget) { document in
            Button("Delete", role: .destructive) {
                deleteTarget = nil
                Task { await perform { try await store.delete(document.id); try await reload() } }
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { document in Text("This permanently deletes “\(document.title)” and its saved file.") }
        .alert("Could not complete the operation", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    @ViewBuilder
    private func drawingActions(_ drawing: DrawingSummary) -> some View {
        Button("Rename", systemImage: "pencil") { title = drawing.document.title; renameTarget = drawing.document }
        Button("Duplicate", systemImage: "plus.square.on.square") {
            Task { await perform { _ = try await store.duplicate(drawing.id); try await reload() } }
        }
        Button("Delete", systemImage: "trash", role: .destructive) { deleteTarget = drawing.document }
    }

    private func reload() async throws { drawings = try await store.list() }

    private func perform(_ operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { try await operation() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct DrawingThumbnail: View {
    let drawing: DrawingSummary

    var body: some View {
        Canvas { context, size in
            guard let bounds = drawing.previewBounds else { return }
            let scale = min((size.width - 20) / max(1, bounds.width), (size.height - 20) / max(1, bounds.height))
            if let reference = drawing.referencePreview, let image = UIImage(data: reference.imageData) {
                var layer = context
                layer.opacity = reference.opacity
                let rect = CGRect(x: (reference.x - bounds.midX) * scale + size.width / 2,
                                  y: (reference.y - bounds.midY) * scale + size.height / 2,
                                  width: reference.width * scale, height: reference.height * scale)
                layer.draw(Image(uiImage: image), in: rect)
            }
            for stroke in drawing.preview {
                var path = Path()
                for (index, point) in stroke.points.enumerated() {
                    let mapped = CGPoint(x: (point.x - bounds.midX) * scale + size.width / 2,
                                         y: (point.y - bounds.midY) * scale + size.height / 2)
                    if index == 0 { path.move(to: mapped) } else { path.addLine(to: mapped) }
                }
                let color = stroke.color
                // Keep light ink visible on the fixed light thumbnail surface.
                let isLight = color.red + color.green + color.blue > 2.5
                let tint = isLight ? Color.gray : Color(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
                if let point = stroke.points.first, stroke.points.allSatisfy({ $0.x == point.x && $0.y == point.y }) {
                    let center = CGPoint(x: (point.x - bounds.midX) * scale + size.width / 2,
                                         y: (point.y - bounds.midY) * scale + size.height / 2)
                    let diameter = max(2, stroke.lineWidth * scale)
                    context.fill(Path(ellipseIn: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                                                       width: diameter, height: diameter)), with: .color(tint))
                } else {
                    context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: max(1, stroke.lineWidth * scale), lineCap: .round, lineJoin: .round))
                }
            }
        }
        .background(Color(red: 0.97, green: 0.96, blue: 0.93))
        .overlay {
            if drawing.previewUnavailable {
                Label("Preview unavailable", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.black)
            }
        }
        .accessibilityHidden(true)
    }
}
