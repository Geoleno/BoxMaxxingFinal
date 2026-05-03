import UIKit
import Photos

// MARK: - Result Exporter

final class ResultExporter {

    // Renders the entire scrollable content of the Results UIScrollView as a single JPG
    // and saves it to the user's Photo Library.
    // Note: Add NSPhotoLibraryAddUsageDescription to Info.plist if not already present.
    func exportFullResultAsJPG(scrollView: UIScrollView, completion: ((Bool) -> Void)? = nil) {
        let fullSize = CGSize(
            width: scrollView.contentSize.width,
            height: scrollView.contentSize.height
        )

        guard fullSize.width > 0, fullSize.height > 0 else {
            print("ResultExporter: Invalid scroll view content size")
            completion?(false)
            return
        }

        let renderer = UIGraphicsImageRenderer(size: fullSize)
        let jpgImage = renderer.image { _ in
            let savedOffset = scrollView.contentOffset
            let savedFrame = scrollView.frame

            scrollView.contentOffset = .zero
            scrollView.frame = CGRect(origin: .zero, size: fullSize)
            scrollView.layer.render(in: UIGraphicsGetCurrentContext()!)
            scrollView.contentOffset = savedOffset
            scrollView.frame = savedFrame
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                print("ResultExporter: Photo Library access denied — \(status)")
                DispatchQueue.main.async { completion?(false) }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: jpgImage)
            }) { success, error in
                if success {
                    print("ResultExporter: Full result saved as JPG ✅")
                } else {
                    print("ResultExporter: Save failed — \(error?.localizedDescription ?? "unknown")")
                }
                DispatchQueue.main.async { completion?(success) }
            }
        }
    }
}
