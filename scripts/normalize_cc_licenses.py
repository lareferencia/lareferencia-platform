#!/usr/bin/env python3
"""Add Creative Commons identifiers to a license inventory in JSONL."""

import argparse
import json
from pathlib import Path
import re
import sys
import unicodedata
from urllib.parse import urlsplit


FAMILIES = {"by", "by-sa", "by-nd", "by-nc", "by-nc-sa", "by-nc-nd"}
VERSIONS = r"[1-4]\.0|2\.5|2\.1"
JURISDICTIONS = {
    "international": "international", "internacional": "international",
    "unported": "international", "no portada": "international", "no portado": "international",
    "generic": "international", "generica": "international",
    "argentina": "ar", "brazil": "br", "brasil": "br", "chile": "cl",
    "colombia": "co", "costa rica": "cr", "ecuador": "ec", "espana": "es",
    "spain": "es", "espanya": "es", "mexico": "mx", "peru": "pe", "portugal": "pt",
    "venezuela": "ve", "united states": "us", "estados unidos": "us",
    "estados unidos de america": "us", "united states of america": "us",
    "germany": "de", "alemania": "de", "australia": "au", "igo": "igo",
}
PORT_CODES = set(JURISDICTIONS.values()) - {"international"} | set(
    "at be bg ca ch cn cz dk eg fi fr gr gt hk hr hu il in it jp kr lu mk mt "
    "my nl no nz ph pl pr ro rs se sg si sk th tw uk vn za scotland englandandwales".split()
)

ATTRIBUTION = {"attribution", "atribucion", "atribuicao", "reconocimiento", "reconeixement"}
TERMS = {
    "non commercial": "nc", "noncommercial": "nc", "no comercial": "nc", "nocomercial": "nc",
    "nocomenrcial": "nc", "no comenrcial": "nc", "non comercial": "nc",
    "nao comercial": "nc", "naocomercial": "nc", "uso nao comercial": "nc",
    "no derivatives": "nd", "noderivatives": "nd", "noderivs": "nd",
    "no derivs": "nd", "no derivates": "nd", "noderivates": "nd",
    "sin derivadas": "nd", "sinderivadas": "nd", "sin derivados": "nd",
    "sin obra derivada": "nd", "no obra derivada": "nd", "sen obra derivada": "nd",
    "sin obras derivadas": "nd", "sinobraderivada": "nd", "sinobrasderivadas": "nd",
    "sin derivar": "nd", "sinderivar": "nd", "sem derivacoes": "nd", "semderivacoes": "nd",
    "sem derivados": "nd", "semderivados": "nd", "no derivative works": "nd",
    "sem obras derivadas": "nd", "sense obra derivada": "nd", "senseobraderivada": "nd",
    "sense obres derivades": "nd",
    "no derivats": "nd", "noderivats": "nd", "share alike": "sa", "sharealike": "sa",
    "compartir igual": "sa", "compartirigual": "sa", "compartilha igual": "sa", "compartilhaigual": "sa",
    "compartir amb la mateixa llicencia": "sa",
    "compartilhamento pela mesma licenca": "sa",
}
TERM = re.compile(r"(?:^| )(" + "|".join(sorted(TERMS, key=len, reverse=True)) + r")(?= |$)")
CC_PREFIX = re.compile(
    r"^(?:(?:licen[cs]e|licencia(?: de)?|licenca|licensa)\s+)?creative commons?\b[\s,:–—-]*"
    r"|^llicencia\s+(?:cc\b|creativ[ae] commons\b(?:\s+de\b)?)[\s,:–—-]*"
)
COMPACT_CODES = {"cc" + code.replace("-", ""): code for code in FAMILIES}
CC_CODE = r"cc[\s:-]*by(?:[\s_-]+(?:nc|sa|nd))*"
BARE_CODE_WRAPPER = re.compile(rf"\(\s*({CC_CODE})\s*\)")
CODE_WITH_VERSION_AND_NAME = re.compile(
    rf"({CC_CODE}\s+(?:{VERSIONS}))\s+((?:{'|'.join(sorted(ATTRIBUTION))})\b.+)"
)
CC_LINK = re.compile(r"""<a\s+href=(?P<quote>["'])(?P<url>https?://[^"'<>\s]+)(?P=quote)>[^<>]*</a>""", re.I)
CC_DECLARATION = re.compile(
    r"^(?:(?:esta obra|este trabajo) esta bajo (?:una )?licencia(?: (?P<international>internacional))? "
    r"|this work is licensed under (?:a |the )?)creative commons\s+"
)
CATALAN_DECLARATION = re.compile(
    r"^aquest (?:document|article) esta subjecte a (?:una|aquesta) llicencia creative commons[\s:]+"
)
COLOMBIAN_CODE = re.compile(r"cc\s+by[- ]+nc[- ]+sa\s+2\s*-\s*5\s+co")
CC_HOST = r"(?:www\.)?creativecommons\.org"
JURISDICTION_SUFFIX = "|".join(sorted(JURISDICTIONS, key=len, reverse=True))


def plain(value):
    folded = unicodedata.normalize("NFKD", value.casefold())
    return "".join(c for c in folded if not unicodedata.combining(c))


def family_code(label):
    if re.fullmatch(r"cc[\s-]*0", label):
        return "CC0"
    if label in COMPACT_CODES:
        return "CC-" + COMPACT_CODES[label].upper()
    label = re.sub(r"^cc\s*[-:.]?\s*", "", label)
    if re.fullmatch(r"by(?:\s*/\s*(?:nc|nd|sa))+", label):
        label = re.sub(r"\s*/\s*", "-", label)
    words = re.sub(r"[\s_\-–—,]+", " ", label).strip()
    abbreviation = words.replace(" ", "-")
    if abbreviation in FAMILIES:
        return "CC-" + abbreviation.upper()
    if words == "attribution by":
        return "CC-BY"
    first, _, tail = words.partition(" ")
    if first not in ATTRIBUTION:
        return None
    tokens = ["by"]
    while tail:
        match = TERM.match(tail)
        if not match:
            return None
        tokens.append(TERMS[match[1]])
        tail = tail[match.end():].strip()
    code = "-".join(tokens)
    return "CC-" + code.upper() if code in FAMILIES else None


def from_url(value):
    anchor = CC_LINK.fullmatch(value)
    if anchor:
        value = anchor["url"]
    # Repair common transcription errors only on the official license host.
    if re.match(rf"^{CC_HOST}/", value, re.I):
        value = "https://" + value
    value = re.sub(rf"^(?:hhtp|ttps|httpss)://(?={CC_HOST}/)", "https://", value, flags=re.I)
    value = re.sub(
        rf"^(https?://{CC_HOST}/licen[cs]es)\s+(?=by\b)", r"\1/", value, flags=re.I,
    )
    if re.match(rf"^https?://{CC_HOST}/licen[cs]es/", value, re.I):
        value = re.sub(r"[-‐‑–—]+\s*(?=[a-z]{2}(?:[-/]))", "-", value.replace("\u00ad", ""), flags=re.I)
    if not re.match(r"https?://", value, re.IGNORECASE) or any(c.isspace() for c in value):
        return None
    try:
        url = urlsplit(value)
        if url.username is not None:
            return None
        host = url.hostname
    except ValueError:
        return None
    if host == "i.creativecommons.org":
        badge = re.fullmatch(
            r"/l/([^/]+)/([^/]+)(?:/([^/]+))?/(?:88x31|80x15)\.(?:png|svg)",
            url.path, re.I,
        )
        if badge:
            path = "/".join(part for part in badge.groups() if part)
            return from_url("https://creativecommons.org/licenses/" + path)
        return None
    if host == "quijote.biblio.iteso.mx":
        match = re.fullmatch(rf"/licencias/cc-(by(?:-[a-z]+)*)-({VERSIONS})-mx\.pdf", url.path, re.I)
        if match and match[1].lower() in FAMILIES and match[2] != "4.0":
            return "CC-" + match[1].upper(), match[2], "mx"
        return None
    if host == "repositorio.uca.edu.sv":
        match = re.fullmatch(r"/jspui/licencias/cc-(by(?:-[a-z]+)*)-4\.0\.pdf/?", url.path, re.I)
        if match and match[1].lower() in FAMILIES:
            return "CC-" + match[1].upper(), "4.0", "international"
        return None
    if host not in {"creativecommons.org", "www.creativecommons.org"}:
        return None
    parts = [part for part in url.path.lower().rstrip(".").split("/") if part]
    if parts and re.fullmatch(r"(?:deed|legalcode)(?:\.[a-z0-9_-]+)?", parts[-1]):
        parts.pop()
    if parts == ["publicdomain", "zero", "1.0"]:
        return "CC0", "1.0", "international"
    if len(parts) == 2 and parts[0] == "about" and parts[1] == "cc0":
        return "CC0", None, None
    if len(parts) >= 4 and parts[:2] == ["licenses", "by"]:
        end = 2
        while end < len(parts) and parts[end] in {"nc", "nd", "sa"}:
            end += 1
        if end > 2:
            parts = ["licenses", "-".join(parts[1:end]), *parts[end:]]
    if not 2 <= len(parts) <= 4 or parts[0] not in {"licenses", "licences", "licenceses"}:
        return None
    code = parts[1].removeprefix("cc-")
    code = {"by-ncnd": "by-nc-nd", "by-ncsa": "by-nc-sa"}.get(code, code)
    if code not in FAMILIES:
        return None
    family = "CC-" + code.upper()
    if len(parts) == 2:
        return family, None, None
    version = parts[2]
    if not re.fullmatch(VERSIONS, version):
        return (family, None, None) if version in {"1", "2", "3", "4"} and len(parts) == 3 else None
    jurisdiction = "international" if len(parts) == 3 else parts[3]
    if jurisdiction != "international" and (jurisdiction not in PORT_CODES or version == "4.0"):
        jurisdiction = None
    return family, version, jurisdiction


def text_label(label):
    label = re.sub(r"^(?:licencia|licenca|license) ", "", CC_PREFIX.sub("", label)).rstrip(".")
    label = re.sub(r" (?:license|licence|llicencia)$", "", label)
    label = re.sub(r"^atribucion\s*/\s*reconocimiento\b", "atribucion", label)
    code_version = re.fullmatch(r"(cc[\s.:-]*by(?:[\s_-]+(?:nc|sa|nd))*)\s+([1-4])([,-])([05])", label)
    if code_version:
        family = family_code(code_version[1])
        version = f"{code_version[2]}.{code_version[4]}"
        if family and re.fullmatch(VERSIONS, version):
            return family, version, None
    label = re.sub(rf"(?<=[a-z])(?=({VERSIONS})(?:{JURISDICTION_SUFFIX})$)", " ", label)
    label = re.sub(rf"(?<=\d)(?={JURISDICTION_SUFFIX}$)", " ", label)
    if re.fullmatch(r"cc[ -]*0 1\.0 universal", label):
        return "CC0", "1.0", "international"
    if label == "atribucionnocomercialsinderivar":
        return "CC-BY-NC-ND", None, None
    match = re.fullmatch(rf"(.+?)[ -]+({VERSIONS})(?:[ -]+(.+))?", label)
    if match:
        family = family_code(match[1])
        suffix = match[3]
        jurisdiction = JURISDICTIONS.get(suffix)
        if jurisdiction is None and suffix in PORT_CODES:
            jurisdiction = suffix
        if family and (suffix is None or jurisdiction):
            return family, match[2], jurisdiction
    family = family_code(label)
    if family:
        return family, None, None
    for name in sorted(JURISDICTIONS, key=len, reverse=True):
        if label.endswith(" " + name):
            family = family_code(label[:-(len(name) + 1)])
            if family:
                return family, None, JURISDICTIONS[name]
    return None


def from_text(value):
    label = " ".join(plain(value.replace("\u00ad", "")).split())
    label = re.sub(r"[-‐‑–—]+", "-", label)
    if re.fullmatch(r"licenca de atribuicao creative commons \(reutilizacao permitida\)\.?", label):
        return "CC-BY", None, None
    label = CATALAN_DECLARATION.sub("", label)
    label = re.sub(r"(?<=\))\s+(?:license|licence)\.?$", "", label)
    declaration = CC_DECLARATION.match(label)
    if declaration:
        result = text_label(label[declaration.end():])
        if result:
            family, version, jurisdiction = result
            if declaration["international"] and jurisdiction not in {None, "international"}:
                return None
            return family, version, "international" if declaration["international"] else jurisdiction
        if not declaration["international"]:
            label = label[declaration.end():]
    label, prefixed = CC_PREFIX.subn("", label)
    if prefixed and re.fullmatch(r"\([^()]+\)", label):
        return text_label(label[1:-1].strip())
    wrapper = BARE_CODE_WRAPPER.fullmatch(label)
    if wrapper:
        return text_label(wrapper[1])
    match = re.fullmatch(r"(.+?)\s*\(([^()]+)\)", label)
    if not match:
        match = re.fullmatch(r"(cc[-\s]+by(?:[-\s]+(?:nc|sa|nd))*)\s+[-–—]\s+(.+)", label)
    if not match:
        match = CODE_WITH_VERSION_AND_NAME.fullmatch(label)
        if match:
            code, title = map(text_label, match.groups())
            if not code or not title or code[:2] != title[:2]:
                return None
    if not match:
        return text_label(label)
    title = text_label(match[1].strip())
    abbreviation_text = match[2].strip()
    if title == ("CC-BY-NC-SA", "2.5", "co") and COLOMBIAN_CODE.fullmatch(abbreviation_text):
        abbreviation_text = "cc by-nc-sa 2.5 co"
    abbreviation = text_label(abbreviation_text)
    if not title or not abbreviation or title[0] != abbreviation[0]:
        return None
    if any(left and right and left != right for left, right in zip(title[1:], abbreviation[1:])):
        return None
    return tuple(left or right for left, right in zip(title, abbreviation))


def normalize(value):
    value = value.strip()
    family, version, jurisdiction = from_url(value) or from_text(value) or (None, None, None)
    specific = family
    if version and jurisdiction:
        specific = f"{family}-{version}"
        if jurisdiction != "international":
            specific += "-" + jurisdiction.upper()
    return dict(family=family, specific=specific, version=version, jurisdiction=jurisdiction)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inventory", type=Path, help="input JSONL with a value field")
    args = parser.parse_args()
    with args.inventory.open(encoding="utf-8") as stream:
        for number, line in enumerate(stream, 1):
            try:
                row = json.loads(line)
                value = row["value"]
                if not isinstance(value, str):
                    raise ValueError("value must be a string")
                if "creativeCommons" in row:
                    raise ValueError("creativeCommons already exists")
            except (KeyError, TypeError, ValueError) as error:
                parser.exit(1, f"{args.inventory}:{number}: {error}\n")
            row["creativeCommons"] = normalize(value)
            print(json.dumps(row, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
