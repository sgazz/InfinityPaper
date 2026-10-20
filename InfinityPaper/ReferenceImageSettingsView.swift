import SwiftUI
import UniformTypeIdentifiers

struct ReferenceImageSettingsView: View {
    let viewport: CGRect
    let onApply: (ReferenceImage?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reference: ReferenceImage?
    @State private var preview: UIImage?
    @State private var scale: CGFloat = 1
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var busy = false
    @State private var cancelled = false
    @State private var errorMessage: String?

    init(reference: ReferenceImage?, viewport: CGRect, onApply: @escaping (ReferenceImage?) -> Void) {
        _reference = State(initialValue: reference)
        _preview = State(initialValue: reference.flatMap { UIImage(data: $0.imageData) })
        self.viewport = viewport
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Choose from Photos", systemImage: "photo") { showPhotos = true }
                    Button("Choose from Files", systemImage: "folder") { showFiles = true }
                } footer: { Text("One reference image per drawing. Choosing another replaces it when you tap Done. Imports are resized to at most 2048 pixels per side.") }
                if reference != nil {
                    Section("Reference") {
                        if let preview {
                            Canvas { context, size in
                                guard let reference else { return }
                                let scale = min(size.width / max(1, viewport.width), size.height / max(1, viewport.height))
                                let frame = CGRect(x: (size.width - viewport.width * scale) / 2,
                                                   y: (size.height - viewport.height * scale) / 2,
                                                   width: viewport.width * scale, height: viewport.height * scale)
                                context.fill(Path(frame), with: .color(Color(uiColor: .secondarySystemBackground)))
                                context.clip(to: Path(frame))
                                context.opacity = reference.isVisible ? reference.opacity : 0
                                context.draw(Image(uiImage: preview), in: CGRect(
                                    x: (reference.x - viewport.minX) * scale + frame.minX,
                                    y: (reference.y - viewport.minY) * scale + frame.minY,
                                    width: reference.width * scale, height: reference.height * scale))
                            }
                            .frame(height: 180)
                            .accessibilityLabel("Reference position preview")
                        }
                        Toggle("Show reference", isOn: Binding(get: { reference?.isVisible ?? true }, set: { reference?.isVisible = $0 }))
                        Text("Opacity")
                        Slider(value: Binding(get: { reference?.opacity ?? 0.5 }, set: { reference?.opacity = $0 }), in: 0...1)
                            .accessibilityLabel("Reference opacity")
                        Text("Size")
                        Slider(value: Binding(get: { scale }, set: { value in
                            reference?.resize(by: value / scale)
                            scale = value
                        }), in: 0.1...4)
                        .accessibilityLabel("Reference size")
                    }
                    Section("Position") {
                        HStack {
                            direction("Move left", icon: "arrow.left", dx: -1, dy: 0)
                            direction("Move up", icon: "arrow.up", dx: 0, dy: -1)
                            direction("Move down", icon: "arrow.down", dx: 0, dy: 1)
                            direction("Move right", icon: "arrow.right", dx: 1, dy: 0)
                        }
                        Button("Center in current view") { reference?.center(at: CGPoint(x: viewport.midX, y: viewport.midY)) }
                        Button("Fit to current view") { reference?.fit(in: viewport); scale = 1 }
                    }
                    Section {
                        Button("Remove reference", role: .destructive) { reference = nil; preview = nil }
                    } footer: { Text("The reference is locked behind your strokes. Use this panel to position it. Done applies the changes as one undo step; Cancel keeps the original.") }
                }
            }
            .disabled(busy)
            .navigationTitle("Reference image")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancelled = true; dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { onApply(reference); dismiss() }.disabled(busy) }
            }
            .overlay { if busy { ProgressView("Importing image…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        }
        .interactiveDismissDisabled(busy)
        .sheet(isPresented: $showPhotos) {
            ReferencePhotoPicker(onStart: { showPhotos = false; busy = true }, onCancel: { showPhotos = false }, onResult: receive)
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                busy = true
                Task {
                    let imported = await Task.detached(priority: .userInitiated) {
                        Result<(Data, CGSize), Error> {
                            let access = url.startAccessingSecurityScopedResource()
                            defer { if access { url.stopAccessingSecurityScopedResource() } }
                            return try ReferenceImageData.prepare(url: url)
                        }
                    }.value
                    receive(imported)
                }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { errorMessage = error.localizedDescription }
            }
        }
        .alert("Could not import image", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func receive(_ result: Result<(Data, CGSize), Error>) {
        guard !cancelled else { return }
        busy = false
        switch result {
        case .success(let value):
            var image = ReferenceImage(id: UUID(), imageData: value.0, x: 0, y: 0, width: value.1.width, height: value.1.height)
            image.fit(in: viewport, imageSize: value.1)
            reference = image
            preview = UIImage(data: value.0)
            scale = 1
        case .failure(let error): errorMessage = error.localizedDescription
        }
    }

    private func direction(_ title: String, icon: String, dx: CGFloat, dy: CGFloat) -> some View {
        Button {
            guard var image = reference else { return }
            image.center(at: CGPoint(x: image.rect.midX + dx * max(1, viewport.width * 0.05),
                                     y: image.rect.midY + dy * max(1, viewport.height * 0.05)))
            reference = image
        } label: { Image(systemName: icon).frame(maxWidth: .infinity, minHeight: 44) }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
    }
}
