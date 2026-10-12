import Foundation
import XCTest
import CoreGraphics
import ImageIO
@testable import SkylitCore

final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    struct Call {
        let request: URLRequest
        let body: Data?

        var json: NSDictionary? {
            body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? NSDictionary }
        }
    }

    enum Reply {
        case status(Int, String)
        case failure(Error)
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private var recorded: [Call] = []

    init(_ replies: [Reply] = []) {
        self.replies = replies
    }

    var calls: [Call] { lock.withLock { recorded } }

    func queue(_ reply: Reply) {
        lock.withLock { replies.append(reply) }
    }

    func send(_ request: URLRequest, body: Data?, onProgress: (@Sendable (Double) -> Void)?) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply = lock.withLock {
            recorded.append(Call(request: request, body: body))
            return replies.isEmpty ? .status(200, "{}") : replies.removeFirst()
        }
        onProgress?(1)
        switch reply {
        case .failure(let error):
            throw error
        case .status(let status, let text):
            return (Data(text.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
}

let testURL = URL(string: "http://192.168.1.20:8765")!

func makeAPI(_ transport: HTTPTransport, token: String? = "tok") -> FrameAPI {
    FrameAPI(baseURL: testURL, token: token, transport: transport)
}

func makeImage(width: Int, height: Int, type: String = "public.png") -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(red: 0.6, green: 0.3, blue: 0.2, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(red: 0.9, green: 0.8, blue: 0.7, alpha: 1)
    context.fillEllipse(in: CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, type as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return output as Data
}

func isolatedDefaults() -> UserDefaults {
    let suite = "skylit-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

func fixedDate(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

func makeMarkedImage(width: Int, height: Int, type: String, orientation: Int) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: height - height / 3, width: width / 3, height: height / 3))
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, type as CFString, 1, nil) else { return Data() }
    CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyOrientation: orientation] as CFDictionary)
    return CGImageDestinationFinalize(destination) ? output as Data : Data()
}

func orientation(of data: Data) -> Int? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
    return properties[kCGImagePropertyOrientation] as? Int
}

struct SampledColor {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    var isRed: Bool { red > 180 && green < 90 && blue < 90 }
}

func cornerColors(of data: Data) -> (topLeft: SampledColor, topRight: SampledColor, bottomLeft: SampledColor, bottomRight: SampledColor)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    func sample(_ x: Int, _ y: Int) -> SampledColor {
        let offset = (y * width + x) * 4
        return SampledColor(red: pixels[offset], green: pixels[offset + 1], blue: pixels[offset + 2])
    }
    let inset = 20
    return (sample(inset, inset), sample(width - inset, inset), sample(inset, height - inset), sample(width - inset, height - inset))
}
