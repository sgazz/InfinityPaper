import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ReferencePhotoPicker: UIViewControllerRepresentable {
    let onStart: () -> Void
    let onCancel: () -> Void
    let onResult: (Result<(Data, CGSize), Error>) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ReferencePhotoPicker
        init(parent: ReferencePhotoPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else { parent.onCancel(); return }
            parent.onStart()
            let completion = parent.onResult
            let identifier = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true } ?? UTType.image.identifier
            provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, error in
                let result = Result<(Data, CGSize), Error> {
                    if let error { throw error }
                    guard let url else { throw CocoaError(.fileReadUnknown) }
                    // The provider URL is valid only within this callback. Decode before returning.
                    return try ReferenceImageData.prepare(url: url)
                }
                DispatchQueue.main.async { completion(result) }
            }
        }
    }
}
