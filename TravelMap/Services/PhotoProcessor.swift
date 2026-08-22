import UIKit

/// Prepares picked photos for upload: square crop, downscale, JPEG.
///
/// The app only ever shows these in square slots, so cropping before upload keeps both
/// the transfer and the Storage bucket small.
enum PhotoProcessor {
    /// Longest edge of an uploaded photo, in pixels.
    static let maxDimension: CGFloat = 1200
    static let compressionQuality: CGFloat = 0.8

    static func squareJPEGData(from image: UIImage) -> Data? {
        squareCropped(image).jpegData(compressionQuality: compressionQuality)
    }

    static func squareCropped(_ image: UIImage) -> UIImage {
        let side = min(image.size.width, image.size.height)
        let target = min(side, maxDimension)
        let cropOrigin = CGPoint(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format).image { _ in
            let scale = target / side
            image.draw(in: CGRect(
                x: -cropOrigin.x * scale,
                y: -cropOrigin.y * scale,
                width: image.size.width * scale,
                height: image.size.height * scale
            ))
        }
    }
}
