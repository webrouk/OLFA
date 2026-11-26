#!/usr/bin/env python3
"""Regenerates web/content/legal.json from the app's legal texts, so the website
and the app always show the same Terms, Privacy Policy and Professional Policy.

The single source is mobile/lib/features/legal/legal_content*.dart.
Run from the repository root:  python3 web/tools/extract-legal.py
"""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = [ROOT / 'mobile/lib/features/legal/legal_content.dart', ROOT / 'mobile/lib/features/legal/legal_content_fr.dart']
OUT = ROOT / 'web/content/legal.json'
STR = r"'((?:[^'\\]|\\.)*)'"
LITS = r"((?:\s*'(?:[^'\\]|\\.)*'\s*)+)"


def text(chunk: str) -> str:
    s = ''.join(re.findall(STR, chunk))
    return s.replace("\\'", "'").replace('\\n', '\n').replace('\\$', '$')


def main() -> None:
    docs = {}
    for f in SRC:
        src = f.read_text(encoding='utf-8')
        for m in re.finditer(r"const (_?\w+) = LegalDoc\((.*?)\n\);", src, re.S):
            name, body = m.group(1), m.group(2)

            def field(key: str) -> str:
                mm = re.search(key + r":" + LITS + ",", body, re.S)
                if not mm:
                    raise SystemExit(f'{f.name}: {name} has no {key}')
                return text(mm.group(1))

            sections = [[text(a), text(b)] for a, b in re.findall(r"LegalSection\(" + LITS + "," + LITS + r"\)", body, re.S)]
            docs[name] = {'title': field('title'), 'updated': field('updated'), 'intro': field('intro'), 'sections': sections}
    need = ['_termsEn', '_termsAr', 'termsFr', '_privacyEn', '_privacyAr', 'privacyFr', '_proEn', '_proAr', 'professionalPolicyFr']
    missing = [k for k in need if k not in docs or not docs[k]['sections']]
    if missing:
        raise SystemExit(f'missing or empty: {missing}')
    OUT.write_text(json.dumps(docs, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    print(f'wrote {OUT.relative_to(ROOT)} ({len(docs)} documents)')


if __name__ == '__main__':
    main()
