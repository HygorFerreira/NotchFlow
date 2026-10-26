"""Validate the release feed against the exact app and archive being published."""
import base64
from pathlib import Path
import plistlib
import sys
import xml.etree.ElementTree as ET

app, feed, archive = map(Path, sys.argv[1:])
with (app / 'Contents/Info.plist').open('rb') as source:
    info = plistlib.load(source)
ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
root = ET.parse(feed).getroot()
items = root.findall('./channel/item')
assert len(items) == 1, 'Expected one update in this release feed'
item = items[0]
assert item.findtext('sparkle:version', namespaces=ns) == info['CFBundleVersion'], 'Build mismatch'
assert item.findtext('sparkle:shortVersionString', namespaces=ns) == info['CFBundleShortVersionString'], 'Version mismatch'
assert item.findtext('sparkle:minimumSystemVersion', namespaces=ns) == info['LSMinimumSystemVersion'], 'OS mismatch'
enclosure = item.find('enclosure')
assert enclosure is not None, 'Missing update archive'
assert int(enclosure.attrib['length']) == archive.stat().st_size, 'Archive size mismatch'
assert enclosure.attrib['url'] == f"https://github.com/HygorFerreira/NotchFlow/releases/download/v{info['CFBundleShortVersionString']}/{archive.name}", 'Download URL mismatch'
assert len(base64.b64decode(enclosure.attrib['{' + ns['sparkle'] + '}edSignature'], validate=True)) == 64, 'Missing archive signature'
assert info['SURequireSignedFeed'] and info['SUVerifyUpdateBeforeExtraction'], 'Signature enforcement disabled'
print('Appcast version, archive, signature metadata and download URL validated')
