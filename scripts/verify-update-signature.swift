// Verifies a Sparkle EdDSA (Ed25519) update signature against a public key,
// so the release fails if the GitHub secret doesn't match the key built into
// the app. Usage: swift verify-update-signature.swift <file> <sig-b64> <pubkey-b64>
import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4 else {
    FileHandle.standardError.write(Data("usage: verify-update-signature <file> <signature-b64> <public-key-b64>\n".utf8))
    exit(2)
}
do {
    let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
    guard let sig = Data(base64Encoded: args[2]), let pub = Data(base64Encoded: args[3]) else {
        print("✗ signature or public key isn't valid base64"); exit(1)
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: pub)
    if key.isValidSignature(sig, for: data) {
        print("✓ signature valid")
    } else {
        print("✗ signature does not match this public key"); exit(1)
    }
} catch {
    print("✗ \(error.localizedDescription)"); exit(1)
}
