#!/usr/bin/env python3
"""Normalize harvested rights values to the LA Referencia family catalog (v3)."""
import argparse
import json
import re
from pathlib import Path
from urllib.parse import urlsplit

from classify_export_licenses import classify_inventory_row
from normalize_cc_licenses import plain

from rights_catalog import REVIEWED_DECLARATIONS, REVIEWED_URLS
from rights_catalog import FAMILIES, INSTRUMENTS, NAMES, SLUGS, URLS, STATEMENT_CODES, STATEMENT_URI


def entry(family, version=None, jurisdiction=None, **details):
    if family not in FAMILIES:
        raise ValueError(f"Unknown license family: {family}")
    jurisdiction = jurisdiction.upper() if jurisdiction and jurisdiction != 'international' else jurisdiction
    country = {'UK':'GB','SCOTLAND':'GB','ENGLANDANDWALES':'GB'}.get(jurisdiction)
    if jurisdiction and len(jurisdiction) == 2 and not country:
        country = jurisdiction
    return dict(family=family, version=version, country=country, jurisdiction=jurisdiction, **details)


def parse_link(literal):
    try:
        url = urlsplit(literal)
        host = (url.hostname or '').removeprefix('www.')
        if url.username or url.port or host not in URLS:
            return None
    except ValueError:
        return None
    match = re.fullmatch(URLS[host], url.path.lower())
    if match:
        slug, version = match.groups()
        details = {'instrument':slug} if slug in ('agpl','sissl') or slug.startswith('bsd-') else {}
        return entry(SLUGS[slug], version.replace('-','.') if version else None, **details)


def declared_name(value):
    parts = re.split(r'(?=\(c\)|©|\bcopyright\b)', value, maxsplit=1, flags=re.I)
    name = re.sub(r'^(?:codi:|termo::|regime::)\s*', '', plain(parts[0]).strip().rstrip('.').strip())
    notice = parts[1].strip() if len(parts)>1 else None
    details = {'scope':'code'} if plain(value).startswith('codi:') else {}
    if name in INSTRUMENTS:
        return entry('INSTITUTIONAL', instrument=INSTRUMENTS[name]), notice
    if name == "publisher's bespoke license":
        return entry('OTHER-LICENSE', instrument=parts[0].strip()), notice
    name = name.removeprefix("licencia ")
    for family, pattern in NAMES.items():
        match = pattern.fullmatch(name)
        if match:
            for k in ('variant','modifier'):
                if v := match.groupdict().get(k):
                    details[k] = v.replace(' ','-')
            return entry(family, match['version'], **details), notice
    return None, None


def reviewed_declaration(value):
    literal = value.strip()
    anchor = re.fullmatch(r'<a href="([^"]+)">\1</a>', literal, re.I)
    url = anchor[1] if anchor else literal
    if match := re.fullmatch(r'https?://(?:www\.)?([^/?#]+)(/[^?#\s]+)', url, re.I):
        details = REVIEWED_URLS.get(match[1].lower() + match[2])
        if details:
            return entry(**details), None, "catalog_url"
    notice_prefix = re.fullmatch(r"(©[^.]+\.)\s+Under an (Elsevier user license)", literal, re.I)
    if notice_prefix:
        details = REVIEWED_DECLARATIONS[notice_prefix[2].lower()]
        return entry(**details), notice_prefix[1], "catalog_name"
    parts = re.split(r'(?=\(c\)|©)', literal, maxsplit=1, flags=re.I)
    key = " ".join(plain(parts[0]).replace("’", "'").split()).rstrip(".")
    details = REVIEWED_DECLARATIONS.get(key)
    if details:
        notice = parts[1] if len(parts) == 2 else None
        return entry(**details), notice, "catalog_name"
    return None, None, None


def from_cc(cc, **details):
    return entry(cc['family'] or 'CC-UNSPECIFIED', cc['version'], cc['jurisdiction'], **details)


def normalize_rights(value):
    old = classify_inventory_row({'value':value})
    if old is None:
        return None
    return project_rights(old)


def project_rights(old):
    value = old['value']
    result = dict(value=value, licenses=[])
    if old.get('copyright'):
        result['copyright'] = old['copyright']
    # Keep applicable links and labels separate from examples and citations.
    linked = []
    if not re.search(r'\b(example|ejemplo|exemplo|not|without|sin licencia|sem licenca)\b', plain(value)):
        for match in re.finditer(r'https?://[^\s<>"\x27()]+', value, re.I):
            literal = match[0].rstrip('.,;')
            license = parse_link(literal)
            if license and license not in [item for item,_ in linked]:
                linked.append((license,literal))
    named, notice = declared_name(value)
    if old['category']=='CC':
        for key in ('decisionRule', 'previousInterpretation', 'declaredCode', 'nameInterpretation'):
            if key in old:
                result[key] = old[key]
        for cc in old.get('scopedLicenses') or [old['creativeCommons']]:
            scope = cc.get('scope') or old.get('scope')
            result['licenses'].append(from_cc(cc, **({'scope':scope} if scope else {})))
        if old.get('declaredLicenses'):
            result['alternatives'] = [from_cc(cc) for cc in old['declaredLicenses']]
        result['evidence'] = old.get('ccEvidence') or [dict(fragment=value, rule='v15_cc')]
    if linked:
        competing_url = any(hit.get('rule') == 'url' for hit in result.get('evidence', []))
        if len(linked)>1 or (result['licenses'] and (competing_url or old.get('declaredLicenses') or old.get('scopedLicenses'))):
            result['candidates'] = result.pop('licenses') + [item for item,_ in linked]
            result['licenses'] = []
            result['status'] = 'review'
        else:
            if result['licenses']:
                result['superseded'] = result['licenses']
            result['licenses'] = [linked[0][0]]
        result.setdefault('evidence', []).extend(dict(fragment=s, rule='catalog_url') for _,s in linked)
    elif named and not result['licenses']:
        result['licenses'] = [named]
        result['evidence'] = [dict(fragment=value, rule='catalog_name')]
        if notice:
            result['copyright'] = notice
    if not result['licenses'] and not result.get('candidates'):
        reviewed, notice, rule = reviewed_declaration(value)
        if reviewed:
            result['licenses'] = [reviewed]
            result['evidence'] = [dict(fragment=value, rule=rule)]
            if notice:
                result['copyright'] = notice
    if old['subtype']=='notice' and not result.get('copyright'):
        result['copyright'] = value
    # A reviewed license URL can contain the path segment /copyright/.
    if result.get('copyright') == value and value.startswith(('http://', 'https://')):
        if any(hit['rule'] == 'catalog_url' and hit['fragment'] == value for hit in result.get('evidence', [])):
            result.pop('copyright')
    if "rightsstatements.org" in value.lower() and not re.search(
        r"\b(?:example|ejemplo|exemplo|exemple)\b", plain(value)
    ):
        for match in STATEMENT_URI.finditer(value):
            code = STATEMENT_CODES.get(match[1].casefold())
            if code is None or match[2] != "1.0":
                continue
            statement = dict(code=code, version=match[2])
            if statement in result.setdefault("rightsStatements", []):
                continue
            result["rightsStatements"].append(statement)
            result["licenses"].append(entry("RIGHTSSTATEMENTS", match[2],
                                            kind="rights_statement", subtype=code, code=code))
            result.setdefault("evidence", []).append(dict(rule="rights_statement_url",
                                                         fragment=match[0]))
    if old['subtype']=='public_domain_label':
        result['rightsStatements']=[dict(code='PUBLIC-DOMAIN')]
    if old.get('declaredLicenses') and not result['licenses']:
        result['alternatives'] = [from_cc(cc) for cc in old['declaredLicenses']]
    if not result['licenses']:
        result.setdefault('status',old['subtype'])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inventory',type=Path)
    args=parser.parse_args()
    with args.inventory.open(encoding='utf-8') as stream:
        for line in stream:
            source=json.loads(line)
            result=normalize_rights(source['value'])
            if result is not None:
                print(json.dumps({**source,**result},ensure_ascii=False,separators=(',',':')))


if __name__=='__main__':
    main()
