import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum PickerRequest: Identifiable {
    case folder
    case multiFiles

    var id: String {
        switch self {
        case .folder: "folder"
        case .multiFiles: "multiFiles"
        }
    }
}

struct SystemDocumentPicker: UIViewControllerRepresentable {
    let request: PickerRequest
    let onPicked: ([URL]) -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = switch request {
        case .folder: [.folder]
        case .multiFiles: [.item]
        }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = (request == .multiFiles)
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: SystemDocumentPicker

        init(_ parent: SystemDocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.dismiss()
            if urls.isEmpty {
                parent.onCancel()
            } else {
                parent.onPicked(urls)
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
            parent.onCancel()
        }
    }
}
