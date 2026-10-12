import Foundation
import ImageIO
import CoreGraphics

public enum ImagePreparationError: Error, Equatable {
    case unreadable
    case tooSmall
    case tooLarge
}

public enum ImagePreparation {
    private static let qualities: [Double] = [0.85, 0.7, 0.55, 0.4]

    public static func jpeg(from source: Data, maxEdge: Int = Limits.photoEdge, maxBytes: Int = Limits.photoBytes) throws -> Data {
        guard let imageSource = CGImageSourceCreateWithData(source as CFData, nil),
              CGImageSourceGetCount(imageSource) > 0 else { throw ImagePreparationError.unreadable }
        var edge = maxEdge
        while edge >= 320 {
            guard let image = downscaled(imageSource, maxEdge: edge) else { throw ImagePreparationError.unreadable }
            guard max(image.width, image.height) >= Limits.photoMinimumEdges.long,
                  min(image.width, image.height) >= Limits.photoMinimumEdges.short else { throw ImagePreparationError.tooSmall }
            for quality in qualities {
                if let data = encode(image, quality: quality), data.count <= maxBytes { return data }
            }
            edge /= 2
        }
        throw ImagePreparationError.tooLarge
    }

    public static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return (image.width, image.height)
    }

    public static func thumbnail(from data: Data, maxEdge: Int) -> CGImage? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { downscaled($0, maxEdge: maxEdge) }
    }

    private static func downscaled(_ source: CGImageSource, maxEdge: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func encode(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
