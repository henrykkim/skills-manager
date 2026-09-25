#!/bin/zsh
# Checks make-appcast.sh output is valid XML with the right Sparkle fields.
set -euo pipefail
cd "$(dirname "$0")/../.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cat > "$T/notes.md" <<'EOF'
- See skills from every project you use with Claude.
- Tags show where each skill works — & "quotes" <stay> safe.

Thanks for using Skills Manager.
EOF
scripts/make-appcast.sh --version 0.2.0 --build 42 \
  --url "https://github.com/henrykkim/skills-manager/releases/download/v0.2.0/SkillsManager-0.2.0.dmg" \
  --sign-output 'sparkle:edSignature="QUJD" length="12345"' \
  --notes "$T/notes.md" --out "$T/appcast.xml"
xmllint --noout "$T/appcast.xml"
x() { xmllint --xpath "$1" "$T/appcast.xml"; }
fail() { echo "✗ $1"; exit 1; }
[[ "$(x 'string(//item/*[local-name()="version"])')" == "42" ]] || fail "sparkle:version"
[[ "$(x 'string(//item/*[local-name()="shortVersionString"])')" == "0.2.0" ]] || fail "shortVersionString"
[[ "$(x 'string(//item/*[local-name()="minimumSystemVersion"])')" == "14.0" ]] || fail "minimumSystemVersion"
[[ "$(x 'string(//enclosure/@url)')" == *"/v0.2.0/SkillsManager-0.2.0.dmg" ]] || fail "enclosure url"
[[ "$(x 'string(//enclosure/@*[local-name()="edSignature"])')" == "QUJD" ]] || fail "edSignature"
[[ "$(x 'string(//enclosure/@length)')" == "12345" ]] || fail "length"
DESC="$(x 'string(//item/description)')"
[[ "$DESC" == *"<li>See skills from every project you use with Claude.</li>"* ]] || fail "first bullet: $DESC"
[[ "$DESC" == *"&amp; &quot;quotes&quot; &lt;stay&gt; safe"* ]] || fail "escaping: $DESC"
[[ "$DESC" == *"<p>Thanks for using Skills Manager.</p>"* ]] || fail "paragraph: $DESC"
# Missing notes must fail.
if scripts/make-appcast.sh --version 0.2.0 --build 1 --url u --sign-output 'sparkle:edSignature="A" length="1"' \
     --notes "$T/nope.md" --out "$T/x.xml" 2>/dev/null; then fail "missing notes accepted"; fi
echo "✓ make-appcast tests passed"
