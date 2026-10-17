#!/usr/bin/env python3
"""Pack the pool and the mint page into single gzipped files for the contract.

    python3 tools/build.py

Writes onchain/pool.html.gz and onchain/mint.html.gz. The admin page uploads them.
"""
import gzip, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = open(os.path.join(ROOT, 'lib.js')).read()


def pack(src):
    html = open(os.path.join(ROOT, src)).read()
    # no hosted files on-chain: drop config.js, inline lib.js
    html = html.replace('<script src="../config.js"></script>\n', '')
    html = html.replace('<script src="../lib.js"></script>', '<script>' + LIB + '</script>')
    assert '../lib.js' not in html and '../config.js' not in html, src
    return gzip.compress(html.encode('utf-8'), compresslevel=9, mtime=0)


os.makedirs(os.path.join(ROOT, 'onchain'), exist_ok=True)
for src, out, key in [('pool/index.html', 'onchain/pool.html.gz', '/*POOL_DATA*/null'),
                      ('input/index.html', 'onchain/mint.html.gz', '/*POOL_CONFIG*/null')]:
    data = pack(src)
    assert gzip.decompress(data).decode().count(key) == 1, (src, 'placeholder must appear exactly once')
    open(os.path.join(ROOT, out), 'wb').write(data)
    print(f'{out}: {len(data):,} bytes')
