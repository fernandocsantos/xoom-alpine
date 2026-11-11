#!/usr/bin/env python3
"""
Verifica a cadeia de confiança de um pacote Alpine sem usar o apk:
  chave RSA (de /usr/share/apk/keys/<arch>) -> assinatura do APKINDEX
  -> checksum "C:" do pacote no índice -> assinatura do próprio pacote.

Uso: verifica-apk.py <dir_chaves> <APKINDEX.tar.gz> <pacote.apk> <nome>
"""
import base64
import hashlib
import io
import os
import subprocess
import sys
import tarfile
import tempfile
import zlib


def gzip_streams(data):
    """Separa os membros gzip concatenados, devolvendo os bytes brutos."""
    out, pos = [], 0
    while pos < len(data):
        d = zlib.decompressobj(16 + zlib.MAX_WBITS)
        d.decompress(data[pos:])
        end = len(data) - len(d.unused_data)
        out.append(data[pos:end])
        pos = end
    return out


def check_sig(keys_dir, sig_stream, signed_bytes):
    tar = tarfile.open(fileobj=io.BytesIO(zlib.decompress(sig_stream, 16 + zlib.MAX_WBITS)))
    m = next(m for m in tar.getmembers() if m.name.startswith(".SIGN.RSA"))
    algo = "-sha256" if m.name.startswith(".SIGN.RSA256.") else "-sha1"
    key = os.path.join(keys_dir, m.name.split(".", 3)[3])
    with tempfile.NamedTemporaryFile() as s, tempfile.NamedTemporaryFile() as b:
        s.write(tar.extractfile(m).read()); s.flush()
        b.write(signed_bytes); b.flush()
        r = subprocess.run(["openssl", "dgst", algo, "-verify", key, "-signature", s.name, b.name],
                           capture_output=True, text=True)
    if "Verified OK" not in r.stdout:
        sys.exit(f"ASSINATURA INVÁLIDA ({m.name}): {r.stdout}{r.stderr}")
    return os.path.basename(key)


keys_dir, index_path, apk_path, name = sys.argv[1:5]

idx = gzip_streams(open(index_path, "rb").read())
k = check_sig(keys_dir, idx[0], b"".join(idx[1:]))
print(f"APKINDEX: assinatura OK ({k})")

text = tarfile.open(fileobj=io.BytesIO(zlib.decompress(b"".join(idx[1:]), 16 + zlib.MAX_WBITS)))
text = text.extractfile("APKINDEX").read().decode()
entry = next(e for e in text.split("\n\n") if f"\nP:{name}\n" in "\n" + e + "\n")
fields = dict(l.split(":", 1) for l in entry.splitlines() if ":" in l)
print(f"índice: {name} {fields['V']}")

apk = gzip_streams(open(apk_path, "rb").read())
k = check_sig(keys_dir, apk[0], apk[1])
print(f"pacote: assinatura do controle OK ({k})")
q1 = "Q1" + base64.b64encode(hashlib.sha1(apk[1]).digest()).decode()
if q1 != fields["C"]:
    sys.exit(f"CHECKSUM DIVERGE: índice {fields['C']} pacote {q1}")
print("pacote: checksum confere com o índice")

ctrl = tarfile.open(fileobj=io.BytesIO(zlib.decompress(apk[1], 16 + zlib.MAX_WBITS)))
pkginfo = ctrl.extractfile(".PKGINFO").read().decode()
datahash = next(l.split("=", 1)[1].strip() for l in pkginfo.splitlines() if l.startswith("datahash"))
if hashlib.sha256(b"".join(apk[2:])).hexdigest() != datahash:
    sys.exit("DATAHASH DIVERGE")
print("pacote: dados conferem com o datahash")
