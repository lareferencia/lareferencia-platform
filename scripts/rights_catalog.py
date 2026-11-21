"""Version 3 of the LA Referencia license family catalog and recognition rules."""
import re

FAMILIES = (
    'CC-BY', 'CC-BY-SA', 'CC-BY-ND', 'CC-BY-NC', 'CC-BY-NC-SA', 'CC-BY-NC-ND',
    'CC-UNSPECIFIED', 'CC0', 'CC-PDM', 'GPL', 'LGPL', 'GFDL', 'MIT', 'BSD', 'Apache',
    'OSL', 'ODC-BY', 'ODbL', 'PDDL', 'INSTITUTIONAL', 'OTHER-LICENSE', 'RIGHTSSTATEMENTS',
)
# Persistent statement identifiers, with the spelling used by the vocabulary.
STATEMENT_CODES = {code.casefold(): code for code in (
    "InC", "InC-OW-EU", "InC-EDU", "InC-NC", "InC-RUU", "NoC-CR",
    "NoC-NC", "NoC-OKLR", "NoC-US", "CNE", "UND", "NKC",
)}
STATEMENT_URI = re.compile(
    r"""(?:^|(?<=[\s<("'=]))(?:(?:https?|ttps|ophttps)://)?(?:www\.)?rightsstatements\.org/"""
    r"""(?:vocab|page)/([a-z-]+)/([0-9]+\.[0-9]+)/?(?=$|[?#\s<>"'),;])""", re.I
)

INSTRUMENTS = {
    'licencia rephip': 'RepHip', 'licenca padrao ipea': 'IPEA',
    'licencia de distribucion no exclusiva sedici': 'SEDICI', 'licenca padrao enap': 'ENAP',
}
NAMES = {
    'GPL': r'(?:gnu )?(?:gpl|general public license(?: gpl)?)',
    'LGPL': r'(?:gnu )?(?:lgpl|lesser general public license)',
    'GFDL': r'(?:gnu )?(?:gfdl|free documentation license)',
    'MIT': r'(?:the )?mit(?: license)?', 'Apache': r'apache(?: license)?',
    'BSD': r'bsd(?:-(?P<variant>[23]-clause))?(?: license)?',
    'OSL': r'osl|open software license',
    'ODC-BY': r'open data commons attribution license(?: \(odc-by\))?|odc-by',
    'ODbL': r'(?:open data commons )?open database license(?: \((?:odc-)?odbl\))?|odbl',
    'PDDL': r'(?:open data commons )?public domain dedication and license(?: \(pddl\))?|pddl',
}
NAMES = {f: re.compile(r'(?:'+p+r')(?:[ -]+(?:version |v)?(?P<version>\d+(?:\.\d+)?))?'
                      r'(?:[ -](?P<modifier>only|or[ -]later))?') for f,p in NAMES.items()}
URLS = {
    'gnu.org': (r'/(?:licenses|copyleft)/(?:old-licenses/)?(gpl|lgpl|lesser|fdl|agpl)'
                r'(?:-([0-9]+\.[0-9]+))?(?:\.[a-z-]+)?(?:\.html|\.txt)?/?'),
    'opensource.org': (r'/licenses?/(mit|bsd-[23]-clause|apache|gpl|lgpl|osl|sissl)'
                       r'(?:-(\d+[.-]\d+))?(?:\.php)?/?'),
    'apache.org': r'/licenses/(license)-(\d+\.\d+)(?:\.txt)?/?',
    'opendatacommons.org': r'/licenses/(by|odbl|pddl)(?:/(\d+[.-]\d+))?/?',
}
SLUGS = {'gpl':'GPL','lgpl':'LGPL','lesser':'LGPL','fdl':'GFDL','mit':'MIT','license':'Apache',
         'apache':'Apache','osl':'OSL','by':'ODC-BY','odbl':'ODbL','pddl':'PDDL',
         'bsd-2-clause':'BSD','bsd-3-clause':'BSD','sissl':'OTHER-LICENSE','agpl':'OTHER-LICENSE'}

# Reviewed declarations and instrument URLs. Keys are folded, whitespace-normalized
# declarations or exact host/path pairs on the issuing organization's site.
ELSEVIER_USER_LICENSE = dict(family="OTHER-LICENSE", instrument="Elsevier User License")

REVIEWED_DECLARATIONS = {
    "gnu general public licens": dict(family="GPL"),
    "licencia publica general de gnu v3.0": dict(family="GPL", version="3.0"),
    "llicencia publica general de gnu": dict(family="GPL"),
    "elsevier user license": ELSEVIER_USER_LICENSE,
    "llicencia oberta d'us d'informacio - catalunya": dict(family="INSTITUTIONAL", instrument="Llicència oberta d’ús d’informació - Catalunya"),
    "licencia institucional": dict(family="INSTITUTIONAL"),
    "institutional licence": dict(family="INSTITUTIONAL"),
    "termo: licenca padrao enap": dict(family="INSTITUTIONAL", instrument="ENAP"),
    "common development and distribution license (cddl)": dict(family="OTHER-LICENSE", instrument="CDDL"),
    "lgpl v. 3.0": dict(family="LGPL", version="3.0"),
    "el present treball esta llicenciat sota llicencia gpl": dict(family="GPL"),
    "gpl 3.0+": dict(family="GPL", version="3.0", modifier="or-later"),
    "gnu affero general public license version 3": dict(family="OTHER-LICENSE", instrument="agpl", version="3.0"),
    "codi: agpl": dict(family="OTHER-LICENSE", instrument="agpl", scope="code"),
    "termo::licenca comum::standard youtube license": dict(family="OTHER-LICENSE", instrument="Standard YouTube License"),
    "text: l'autor. video: llicencia estandard de youtube": dict(family="OTHER-LICENSE", instrument="Standard YouTube License", scope="video"),
    "zero-clause bsd": dict(family="BSD", instrument="0BSD"),
    "zope public license 2.1": dict(family="OTHER-LICENSE", instrument="ZPL", version="2.1"),
    "european union public licence (eupl) v1.2": dict(family="OTHER-LICENSE", instrument="EUPL", version="1.2"),
    "codi: mozilla public license 2.0": dict(family="OTHER-LICENSE", instrument="MPL", version="2.0", scope="code"),
    "this is an open access article under the open government license (ogl)": dict(family="OTHER-LICENSE", instrument="OGL"),
}

REVIEWED_URLS = {
    "freebsd.org/copyright/freebsd-license.html": dict(family="BSD", instrument="bsd-2-clause"),
    "elsevier.com/open-access/userlicense/1.0/": dict(**ELSEVIER_USER_LICENSE, version="1.0"),
    "elsevier.com/about/policies/open-access-licenses/elsevier-user-license": ELSEVIER_USER_LICENSE,
    "elsevier.com/about/our-business/policies/open-access-licenses/elsevier-user-license": ELSEVIER_USER_LICENSE,
    "elsevier.com/about/open-access/open-access-policies/oa-license-policy/elsevier-user-license": ELSEVIER_USER_LICENSE,
    "opensource.org/license/cddl-1-1": dict(family="OTHER-LICENSE", instrument="CDDL", version="1.1"),
    "opensource.org/license/agpl-3-0": dict(family="OTHER-LICENSE", instrument="agpl", version="3.0"),
    "opensource.org/license/0bsd": dict(family="BSD", instrument="0BSD"),
    "opensource.org/license/mit-0": dict(family="MIT", instrument="MIT-0"),
    "opensource.org/license/zpl-2-1": dict(family="OTHER-LICENSE", instrument="ZPL", version="2.1"),
    "mozilla.org/MPL/MPL-1.1.html": dict(family="OTHER-LICENSE", instrument="MPL", version="1.1"),
    "mozilla.org/en-US/MPL/2.0/": dict(family="OTHER-LICENSE", instrument="MPL", version="2.0"),
    "gnu.org/licenses/gpl-3.0.ca.htmlº": dict(family="GPL", version="3.0"),
}
