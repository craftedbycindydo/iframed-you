import Foundation
import CryptoKit
import Security

public enum Hex {
    public static func isValid(_ text: String, bytes: Int) -> Bool {
        text.utf8.count == bytes * 2 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    public static func encode<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    public static func decode(_ text: String, bytes: Int) -> Data? {
        guard isValid(text, bytes: bytes) else { return nil }
        let digits = text.utf8.map { $0 <= 57 ? $0 - 48 : $0 - 87 }
        return Data(stride(from: 0, to: digits.count, by: 2).map { digits[$0] << 4 | digits[$0 + 1] })
    }
}

public enum Pin {
    public static let bytes = 32
    public static let frameIdLength = 32

    public static func fingerprint(ofCertificate der: Data) -> String {
        Hex.encode(SHA256.hash(data: der))
    }

    public static func isValid(_ fp: String) -> Bool {
        Hex.isValid(fp, bytes: bytes)
    }

    public static func frameId(for fp: String) -> String {
        String(fp.prefix(frameIdLength))
    }

    public static func matches(_ observed: String, pin: String) -> Bool {
        isValid(pin) && PairingCrypto.constantTimeEquals(observed, pin)
    }
}

public enum PairingCrypto {
    public static let label = "skylit-pair-v2"

    public static func randomBytes(_ count: Int = 32) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { throw FrameError.invalidResponse }
        return Data(bytes)
    }

    public static func sha256(_ data: Data) -> String {
        Hex.encode(SHA256.hash(data: data))
    }

    public static func derive(nP: Data, nF: Data, fpRaw: Data) -> (digest: Data, code: String, pick: String) {
        var message = Data(label.utf8)
        message.append(0)
        message.append(fpRaw)
        let digest = Array(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: nP + nF)))
        func u32(_ offset: Int) -> UInt32 {
            digest[offset..<offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
        }
        return (Data(digest), String(format: "%06u", u32(0) % 1_000_000), String(format: "%02u", u32(4) % 100))
    }

    public static func constantTimeEquals(_ left: String, _ right: String) -> Bool {
        let a = Array(left.utf8), b = Array(right.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
