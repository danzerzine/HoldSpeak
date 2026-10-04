#!/usr/bin/env python3
"""Prepend a release to docs/appcast.xml, the Sparkle feed served by GitHub Pages.

Usage: appcast-add.py VERSION BUILD DMG_URL SIGN_UPDATE_OUTPUT NOTES_FILE
SIGN_UPDATE_OUTPUT is what Sparkle's sign_update prints:
  sparkle:edSignature="..." length="..."
NOTES_FILE holds one change per line; it becomes the "what's new" list.
"""
import html
import re
import sys
from email.utils import formatdate
from pathlib import Path

FEED = Path(__file__).resolve().parent.parent / "docs" / "appcast.xml"
KEEP = 10
HEAD = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Speak!</title>
    <link>https://danzerzine.github.io/Speak/</link>
"""
TAIL = """  </channel>
</rss>
"""


def main() -> None:
    version, build, url, signed, notes_file = sys.argv[1:6]
    m = re.search(r'sparkle:edSignature="([^"]+)"\s+length="(\d+)"', signed)
    if not m:
        sys.exit(f"unexpected sign_update output: {signed!r}")
    sig, length = m.groups()
    notes = [l.strip() for l in Path(notes_file).read_text().splitlines() if l.strip()]
    lis = "".join(f"<li>{html.escape(n)}</li>" for n in notes) or "<li>Fixes and improvements.</li>"
    item = f"""    <item>
      <title>Speak! {version}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/danzerzine/Speak/releases/tag/v{version}</sparkle:fullReleaseNotesLink>
      <description><![CDATA[<ul>{lis}</ul>]]></description>
      <enclosure url="{url}" sparkle:edSignature="{sig}" length="{length}" type="application/octet-stream"/>
    </item>
"""
    old = re.findall(r"    <item>.*?</item>\n", FEED.read_text(), re.S) if FEED.exists() else []
    FEED.write_text(HEAD + item + "".join(old[: KEEP - 1]) + TAIL)


if __name__ == "__main__":
    main()
