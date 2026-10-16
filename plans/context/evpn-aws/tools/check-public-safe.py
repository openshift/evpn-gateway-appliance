#!/usr/bin/env python3
"""Scan this directory for material that must not be published: customer data and secrets.

Usage: tools/check-public-safe.py [--terms FILE] [--allow-private] [path ...]
(default path: the whole directory). Exit status is 1 if anything is found. Red Hat internal links, ticket keys and product
identifiers are fine here; customer data, credentials and personal contact details are not.

Detects: email addresses, non-documentation IPv4 addresses, 12-digit AWS account IDs,
cloud/API tokens and private keys, SSH public keys, support-case numbers,
`password = value` assignments, and links to selected chat and private document services.
Every non-binary file is scanned whatever its name or extension
(Containerfiles, Terraform, Jinja templates), so it can also vet a source snapshot before
an import. `--allow-private` skips RFC 1918, carrier-grade NAT and link-local addresses,
which are noise in lab examples but can still identify a customer network in a doc. Customer, partner and account names cannot be detected by
pattern: keep them in a private file outside the repository and pass it with --terms
(one case-insensitive term per line, `#` comments allowed).

Append `public-safe: ok` to a line (in a comment) to accept a known false positive.
"""
import ipaddress
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
BINARY = {".png", ".jpg", ".jpeg", ".gif", ".ico", ".pdf", ".gz", ".tgz", ".tar", ".zip", ".xz",
          ".bz2", ".qcow2", ".raw", ".vmdk", ".woff", ".woff2", ".ttf", ".pyc"}
MAX_BYTES = 2_000_000
ALLOW_PRIVATE = False
CGNAT = ipaddress.ip_network("100.64.0.0/10")  # public-safe: ok
DOC_IPS = re.compile(r"^(127\.|0\.0\.0\.0|169\.254\.169\.254|203\.0\.113\.|198\.51\.100\.|192\.0\.2\.)")
RULES = [
    ("email address", re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}"), None),
    ("IPv4 address", re.compile(r"(?<![\w.])(\d{1,3}\.){3}\d{1,3}(?![\w.])"), lambda m: skip_ip(m[0])),
    ("12-digit account ID", re.compile(r"(?<![\w.-])\d{12}(?![\w.-])"), None),
    ("AWS access key ID", re.compile(r"\b(AKIA|ASIA)[0-9A-Z]{16}\b"), None),
    ("token", re.compile(r"\b(gh[pousr]_[A-Za-z0-9]{30,}|xox[abprs]-[A-Za-z0-9-]{10,}|glpat-[A-Za-z0-9_-]{20,})"), None),
    ("private key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"), None),
    ("SSH public key", re.compile(r"\bssh-(rsa|ed25519|dss)\s+AAAA[0-9A-Za-z+/=]{20,}"), None),
    ("internal chat, private document or ticket link",
     re.compile(r"https?://[\w.-]*(slack\.com/archives|docs\.google\.com/(document|spreadsheets|presentation|forms)"
                r"|drive\.google\.com|sharepoint\.com|hub\.redhat\.com/hub\?)[^\s)>\"`]*"), None),
    ("support-case number", re.compile(r"(?i)\b(support case|sfdc case|case (number|no\.?|#))\s*:?\s*0?\d{6,8}\b"), None),
    ("secret assignment", re.compile(r"(?i)\b(password|passwd|secret|api[_-]?key|token)\b\s*[:=]\s*['\"]?[A-Za-z0-9/+_-]{8,}"),
     lambda m: bool(re.search(r"\$|<|\{|example|placeholder|xxxx|secretName|SecretName", m[0], re.I))),
]


def skip_ip(text):
    if DOC_IPS.match(text):
        return True
    try:
        addr = ipaddress.ip_address(text)
    except ValueError:
        return True  # not an address, e.g. a version number such as 1.2.3.400
    return ALLOW_PRIVATE and (addr.is_private or addr.is_link_local or addr in CGNAT)


def files(paths):
    for p in paths or [ROOT]:
        p = pathlib.Path(p)
        yield from (sorted(p.rglob("*")) if p.is_dir() else [p])


def main():
    global ALLOW_PRIVATE
    args = sys.argv[1:]
    if "--allow-private" in args:
        ALLOW_PRIVATE = True
        args.remove("--allow-private")
    terms = []
    if "--terms" in args:
        i = args.index("--terms")
        terms = [t.strip().lower() for t in pathlib.Path(args[i + 1]).read_text().splitlines()
                 if t.strip() and not t.startswith("#")]
        del args[i:i + 2]
    found = []
    for f in files(args):
        if not f.is_file() or f.suffix.lower() in BINARY or ".git" in f.parts:
            continue
        data = f.read_bytes()
        if len(data) > MAX_BYTES or b"\0" in data[:4096]:
            continue
        rel = f.relative_to(ROOT) if ROOT in f.parents else f
        for n, line in enumerate(data.decode("utf-8", errors="ignore").splitlines(), 1):
            if "public-safe: ok" in line:
                continue
            for kind, rx, skip in RULES:
                for m in rx.finditer(line):
                    if not (skip and skip(m)):
                        found.append(f"{rel}:{n}: {kind}: {m[0][:60]}")
            for t in terms:
                if t in line.lower():
                    found.append(f"{rel}:{n}: listed term: {t}")
    print("\n".join(found) or "nothing to withhold found")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
