#!/usr/bin/env python3
"""Check public package hygiene and archive consistency (not licensing clearance)."""
import argparse,hashlib,io,json,plistlib,zipfile
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--ipa',type=Path);a=p.parse_args()
r=Path(__file__).resolve().parents[1]
for f in r.rglob('*'):
 if any(x in f.parts for x in ['.git','.build','DerivedData','release-output']):continue
 if not f.is_file():continue
 assert f.suffix not in ('.mobileprovision','.p12','.p8','.key'),f'Private signing file: {f.relative_to(r)}'
 assert f.stat().st_size<100*1024*1024,f'File exceeds GitHub normal-file limit: {f.relative_to(r)}'
for name in ('icon.png','menu.png','gameplay.png'):assert (r/'docs/images'/name).is_file(),name
with zipfile.ZipFile(r/'OriginalPort/Original/Chuzzle.ipa') as z:
 assert z.testzip() is None
 assert all(n.startswith('Payload/') for n in z.namelist()),'Original archive has non-app metadata'
result={'source_hygiene':'pass','readme_images_present':True}
if a.ipa:
 with zipfile.ZipFile(a.ipa) as z:
  assert z.testzip() is None
  assert not any(any(t in n for t in ('embedded.mobileprovision','_CodeSignature/','iTunesMetadata.plist')) for n in z.namelist())
  info=plistlib.loads(z.read('Payload/Chuzzle.app/Info.plist'))
  assert info['CFBundleSupportedPlatforms']==['iPhoneOS'],'Simulator package cannot ship'
  assert info['CFBundleDisplayName']=='Chuzzle'
  exe=z.read('Payload/Chuzzle.app/'+info['CFBundleExecutable'])
  assert b'[CHUZZLE-AOT-VALIDATED]' not in exe
  assert b'[CHUZZLE-AOT-MISSING]' in exe
  for n in z.namelist():
   if n.endswith('.ipa'):
    with zipfile.ZipFile(io.BytesIO(z.read(n))) as nested:
     assert nested.testzip() is None
     assert all(x.startswith('Payload/') for x in nested.namelist())
  result.update(version=info['CFBundleShortVersionString'],build=info['CFBundleVersion'],ipa_sha256=hashlib.sha256(a.ipa.read_bytes()).hexdigest(),unsigned_package_hygiene='pass')
print(json.dumps(result,indent=2))
