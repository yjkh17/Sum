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
            Task.detached { [scan, parent = self.parent] in
                // نجمع أرقام كل صفحة بمهمة فرعية مستقلة ثم نلصقها لاحقًا
                let allNumbers: [Double] = try await withThrowingTaskGroup(of: [Double].self) { group in
                    for index in 0..<scan.pageCount {
                        let uiImage = scan.imageOfPage(at: index)
                        guard let cgImage = uiImage.cgImage else { continue }
                        
                        group.addTask {
                            (try? await TextScannerService.recognizeNumbers(in: cgImage)) ?? []
                        }
                    }
                    
                    var merged: [Double] = []
                    for try await nums in group {
                        merged.append(contentsOf: nums)
                    }
                    return merged
                }
                
                await MainActor.run {
                    parent.onScanCompleted(allNumbers)
                    parent.dismiss()
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
