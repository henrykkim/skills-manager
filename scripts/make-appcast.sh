#!/bin/zsh
# Writes a single-item Sparkle appcast for one release (auto-updates spec §6.3).
# Used by .github/workflows/release.yml and the local rehearsal.
set -euo pipefail
zmodload zsh/zutil
zparseopts -D -E -F -A opt -- -version: -build: -url: -sign-output: -notes: -out:
VERSION="${opt[--version]}"; BUILD="${opt[--build]}"; URL="${opt[--url]}"
SIGN="${opt[--sign-output]}"; NOTES="${opt[--notes]}"; OUT="${opt[--out]}"

[[ -s "$NOTES" ]] || { echo "Release notes missing or empty: $NOTES" >&2; exit 1; }
SIG="$(sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p' <<< "$SIGN")"
LEN="$(sed -nE 's/.*length="([0-9]+)".*/\1/p' <<< "$SIGN")"
[[ -n "$SIG" && -n "$LEN" ]] || { echo "Can't read signature/length from: $SIGN" >&2; exit 1; }

esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' <<< "$1"; }
HTML=""; IN_LIST=0
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" == "- "* || "$line" == "* "* ]]; then
    (( IN_LIST )) || { HTML+="<ul>"; IN_LIST=1; }
    HTML+="<li>$(esc "${line:2}")</li>"
  else
    (( IN_LIST )) && { HTML+="</ul>"; IN_LIST=0; }
    [[ -n "${line// }" ]] && HTML+="<p>$(esc "$line")</p>"
  fi
done < "$NOTES"
(( IN_LIST )) && HTML+="</ul>"

cat > "$OUT" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Skills Manager</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[$HTML]]></description>
      <enclosure url="$URL" type="application/octet-stream" sparkle:edSignature="$SIG" length="$LEN"/>
    </item>
  </channel>
</rss>
EOF
echo "wrote $OUT"
