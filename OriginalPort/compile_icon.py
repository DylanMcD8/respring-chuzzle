#!/usr/bin/env python3
"""Compile the editable Icon Composer document into the app's asset catalog."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('sdk', choices=['iphoneos', 'iphonesimulator'])
p.add_argument('app', type=Path)
p.add_argument('--icon', type=Path, default=Path(__file__).resolve().parents[1] / 'Chuzzle.icon',
               help='Icon Composer document shared with the Xcode project')
a = p.parse_args()
icon = a.icon.resolve()
with tempfile.TemporaryDirectory(prefix='chuzzle-icon-') as directory:
    out = Path(directory)
    partial = out / 'partial.plist'
    subprocess.run(['xcrun', 'actool', str(icon), '--compile', str(out),
        '--platform', a.sdk, '--minimum-deployment-target', '15.0',
        '--app-icon', 'Chuzzle', '--output-partial-info-plist', str(partial),
        '--target-device', 'iphone', '--target-device', 'ipad'], check=True)
    info = plistlib.loads((a.app / 'Info.plist').read_bytes())
    info.pop('CFBundleIconFiles', None)
    info.update(plistlib.loads(partial.read_bytes()))
    (a.app / 'Info.plist').write_bytes(plistlib.dumps(info))
    for asset in out.iterdir():
        if asset != partial:
            shutil.copyfile(asset, a.app / asset.name)
