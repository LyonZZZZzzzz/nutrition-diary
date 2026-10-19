import SwiftUI

#if os(iOS)
import UIKit

struct CameraCaptureButton<Label: View>: View {
    let onCapture: (Data) -> Void
    @ViewBuilder let label: () -> Label
    @State private var showingCamera = false

    var body: some View {
        Button { showingCamera = true } label: { label() }
            .sheet(isPresented: $showingCamera) {
                CameraPicker { data in
                    onCapture(data)
                    showingCamera = false
                }
                .ignoresSafeArea()
            }
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.92) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct PlatformMealImage: View {
    let data: Data

    var body: some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image).resizable()
        } else {
            Color.secondary.opacity(0.15)
        }
    }
}
#else
import AppKit

struct CameraCaptureButton<Label: View>: View {
    let onCapture: (Data) -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {} label: { label() }.disabled(true)
    }
}

struct PlatformMealImage: View {
    let data: Data

    var body: some View {
        if let image = NSImage(data: data) {
            Image(nsImage: image).resizable()
        } else {
            Color.secondary.opacity(0.15)
        }
    }
}
#endif
