
import SwiftUI
import VisionKit

struct DocumentScannerView: UIViewControllerRepresentable {
    var onScanCompleted: @MainActor ([Double]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView

        init(parent: DocumentScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            Task.detached {
                var allNumbers: [Double] = []
                for index in 0..<scan.pageCount {
                    let uiImage = scan.imageOfPage(at: index)
                    guard let cgImage = uiImage.cgImage else { continue }
                    if let nums = try? await TextScannerService.recognizeNumbers(in: cgImage) {
                        allNumbers.append(contentsOf: nums)
                    }
                }
                await MainActor.run {
                    self.parent.onScanCompleted(allNumbers)
                    self.parent.dismiss()
                }
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.dismiss()
        }
    }
}
