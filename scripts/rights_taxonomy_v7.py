"""Project recognized v6 rights into nine reporting families."""
import re
from normalize_cc_licenses import plain

FAMILIES = ('CC', 'SOFTWARE', 'DATA', 'INSTITUTIONAL', 'EDITORIAL', 'PUBLIC-DOMAIN',
            'RE', 'Copyright', 'OTHER-LICENSE')
SOFTWARE = {'GPL', 'LGPL', 'GFDL', 'MIT', 'BSD', 'Apache', 'OSL'}
SOFTWARE_DETAILS = {'AGPL', 'MPL', 'CDDL', 'EUPL', 'SISSL', 'ZPL'}
EDITORIAL = {"publisher's bespoke license", 'standard youtube license', 'elsevier user license'}


def copyright_subtype(value):
    text = plain(value)
    if re.search(r'\b(some|algun(?:os)?|algum|alguns)\b', text) and 'reserv' in text:
        return 'SOME-RIGHTS-RESERVED'
    if re.search(r'\b(all|todos|tots)\b', text) and 'reserv' in text:
        return 'ALL-RIGHTS-RESERVED'
    return 'RIGHTS-RESERVED' if 'reserv' in text else 'NOTICE'


def declaration(old, value):
    family = old['family']
    instrument = old.get('instrument', family)
    kind = 'license'
    details = {}
    if family in ('CC0', 'PDDL', 'CC-PDM'):
        instrument = family
        details['scheme'] = 'Open Data Commons' if family == 'PDDL' else 'Creative Commons'
        kind = 'public_domain_mark' if family == 'CC-PDM' else 'public_domain_dedication'
        family = 'PUBLIC-DOMAIN'
    elif family.startswith('CC-'):
        instrument = family[3:]
        family = 'CC'
        details['scheme'] = 'Creative Commons'
    elif family in SOFTWARE:
        family = 'SOFTWARE'
    elif family in ('ODbL', 'ODC-BY'):
        family = 'DATA'
        details['scheme'] = 'Open Data Commons'
    elif family == 'RE':
        instrument = old['subtype']
        kind = 'rights_statement'
    elif family == 'Copyright':
        instrument = copyright_subtype(value)
        kind = 'copyright_notice'
    elif family == 'INSTITUTIONAL':
        instrument = old.get('instrument', 'UNSPECIFIED')
    elif family == 'OTHER-LICENSE':
        if instrument.upper() in SOFTWARE_DETAILS:
            family, instrument = 'SOFTWARE', instrument.upper()
        elif instrument.casefold() in EDITORIAL:
            family = 'EDITORIAL'
    else:
        raise ValueError(f'Unknown v6 family {family}')
    return {**old, **details, 'family':family, 'instrument':instrument, 'kind':kind}


def project_v7(source):
    row = dict(source, taxonomyVersion=7)
    for key in ('licenses', 'alternatives', 'candidates', 'superseded'):
        if key in source:
            row[key] = [declaration(old, source['value']) for old in source[key]]
    entries = row['licenses']
    if any(s['code']=='PUBLIC-DOMAIN' for s in source.get('rightsStatements', [])):
        entries.append(dict(family='PUBLIC-DOMAIN', instrument='UNSPECIFIED',
                            kind='public_domain_statement', version=None, country=None, jurisdiction=None))
        row['evidence'] = [*row.get('evidence', []), dict(rule='v6_public_domain_label',fragment=source['value'])]
        row.pop('status', None)
    if entries and source.get('copyright') and not any(e['family']=='Copyright' for e in entries):
        entries.append(declaration(dict(family='Copyright', version=None, country=None, jurisdiction=None),
                                   source['copyright']))
    return row
