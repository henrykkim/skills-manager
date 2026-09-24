#!/bin/zsh
# Signs a file with a throwaway Ed25519 key (CryptoKit) and checks the
# verifier accepts it and rejects a tampered file and a wrong key.
set -euo pipefail
cd "$(dirname "$0")/../.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
echo "update payload" > "$T/update.dmg"
cat > "$T/sign.swift" <<'EOF'
import CryptoKit
import Foundation
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let key = Curve25519.Signing.PrivateKey()
let other = Curve25519.Signing.PrivateKey()
print(try key.signature(for: data).base64EncodedString())
print(key.publicKey.rawRepresentation.base64EncodedString())
print(other.publicKey.rawRepresentation.base64EncodedString())
EOF
OUT=("${(@f)$(swift "$T/sign.swift" "$T/update.dmg")}")
SIG="$OUT[1]"; PUB="$OUT[2]"; WRONG="$OUT[3]"
swift scripts/verify-update-signature.swift "$T/update.dmg" "$SIG" "$PUB"
if swift scripts/verify-update-signature.swift "$T/update.dmg" "$SIG" "$WRONG" 2>/dev/null; then echo "✗ wrong key accepted"; exit 1; fi
echo "tampered" >> "$T/update.dmg"
if swift scripts/verify-update-signature.swift "$T/update.dmg" "$SIG" "$PUB" 2>/dev/null; then echo "✗ tampered file accepted"; exit 1; fi
echo "✓ verify-signature tests passed"
