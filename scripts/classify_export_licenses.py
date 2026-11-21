#!/usr/bin/env python3
"""Classify a license inventory and omit values that describe access."""

import argparse
import json
from pathlib import Path
import re
import sys

from cc_license_fragments import resolve_pending_cc, apply_structural_repairs, apply_url_priority, apply_ordered_name, declaration_fallback, detect, fallback, reference_subtype, review_reference
from normalize_cc_licenses import normalize, plain


ACCESS = re.compile(
    r"(?:oa[ _-](?:all|none|restricted|embargo(?:ed)?|metadata)|"
    r"green|gold|hybrid|bronze|diamond|"
    r"abiert[oa](?:access|\s*\(texto completo\))?|abert[oa]|"
    r"restringid[oa](?:\s*\(solo referencia\))?|restrit[oa]|"
    r"cerrad[oa]|fechad[oa]|embargad[oa]|embargo|"
    r"(?:open|restricted|closed|embargoed|metadata[ _-]*only)[ _-]*access|"
    r"(?:acceso|acesso) (?:abiert[oa]|abert[oa]|libre|livre|publico|"
    r"restringido|restrito|cerrado|fechado|embargado|sob embargo|"
    r"(?:en linea|en sitio|ao texto completo) sin restricciones|"
    r"restringido al texto completo|a texto completo|aberto e gratuito|parcial|restrito/embargado)|"
    r"(?:solo|apenas|somente) metadados|solo metadatos|"
    r"sem restricao de acesso|liberar o conteudo para acesso publico)"
)
ACCESS_URL = re.compile(
    r"^(?:info:eu-repo/semantics/(?:open|restricted|closed|embargoed)access|"
    r"https?:/{1,2}(?:purl\.org/coar|vocabularies\.coar-repositories\.org)/access_rights?/[^\s]*)/?$",
    re.I,
)
COPYRIGHT = re.compile(
    r"©|\bcopyright\b|\ball rights reserved\b|"
    r"\b(?:derechos|direitos|drets) reservad[oa]s\b|\bdrets reservats\b|"
    r"\breserva de todos los derechos\b|\btodos os direitos reservados\b"
)
CC_REFERENCE = re.compile(r"creative\s+commons|creativecommons\.org|\bcc[ -]+by\b|\bcc[ -]*0\b")
RIGHTS_STATEMENT = re.compile(r"rightsstatements\.org/(?:vocab|page)/([a-z-]+)/(\d+\.\d+)", re.I)
PUBLIC_DOMAIN_MARK = re.compile(r"creativecommons\.org/publicdomain/mark/1\.0\b", re.I)
SOFTWARE = re.compile(r"gnu\.org/(?:licenses|copyleft)/|opensource\.org/licenses/|"
                      r"apache\.org/licenses/license-2\.0\b|"
                      r"\b(?:gnu (?:general public|free documentation) license|"
                      r"mit license|bsd license|apache license)\b", re.I)
INSTITUTIONAL = {
    "licencia rephip", "licenca padrao ipea",
    "licencia de distribucion no exclusiva sedici", "regime::licenca padrao enap",
}
TEXT_SCOPE = re.compile(
    r"(?:nomes (?:pel|per al) text|solo (?:para |el )?(?:el )?texto|"
    r"somente (?:para |o )?(?:o )?texto|(?:text only|only (?:the )?text))"
)
COPYRIGHT_PREFIX = re.compile(r"^(?:copyright\s*(?:\(c\))?|\(c\)|©)\s*", re.I)
CC_WITH_SCOPE = re.compile(r"([^\[;]+?)\s*\[([^\[\]]+)\](?:\s*;\s*(.+))?", re.S)
CC_WITH_COPYRIGHT = re.compile(
    r"(cc[.\s-]*by(?:[-\s]*(?:nc|nd|sa))*(?:\s+\d+\.\d+)?)(?:\s*,\s*|\s+)(.+)",
    re.I | re.S,
)
COPYRIGHT_WITH_CC = re.compile(
    r"((?:copyright\s*(?:\(c\))?|©|direitos autorais|direitos de autor)\s+\d{4})"
    r"\s+(cc(?:[.\s-]*by\b|[-\s]+atribui[cç][aã]o\b).*)",
    re.I,
)
INSTITUTIONAL_NOTICE_WITH_LICENSE = re.compile(
    r"((?:(?:©|\(cc\))\s+\d{4}\s+UPV/EHU|©\s*[^,]+,))\s+(.+)", re.I,
)
ALTERNATIVE_WITH_COPYRIGHT = re.compile(
    r"(.+?)(?:\s*[,;]\s*|\s+)((?:copyright\b|\(c\)|©|direitos autorais\b).+)",
    re.I | re.S,
)
COPYRIGHT_BEFORE_ALTERNATIVES = re.compile(
    r"((?:copyright\s*(?:\(c\))?|©|direitos autorais|direitos de autor)\s+\d{4})\s+(.+)",
    re.I | re.S,
)
ALTERNATIVE_SEPARATOR = re.compile(r"\s+(?:or|ou|o)\s+", re.I)


def copyright_alternatives(value):
    value = value.strip()
    if not ALTERNATIVE_SEPARATOR.search(value):
        return None
    match = COPYRIGHT_BEFORE_ALTERNATIVES.fullmatch(value)
    if match:
        notice, declaration = match.groups()
    else:
        match = ALTERNATIVE_WITH_COPYRIGHT.fullmatch(value)
        if not match:
            return None
        declaration, notice = match.groups()
    alternatives = ALTERNATIVE_SEPARATOR.split(declaration)
    if len(alternatives) < 2:
        return None
    licenses = []
    for alternative in alternatives:
        cc = normalize(alternative)
        if not cc["family"]:
            return None
        if cc not in licenses:
            licenses.append(cc)
    # A candidate must impose a subset of the conditions of every alternative.
    conditions = [set(cc["family"].split("-")[1:]) for cc in licenses]
    least = [cc for cc, terms in zip(licenses, conditions) if all(terms <= other for other in conditions)]
    return least[0] if len(least) == 1 else None, licenses, notice.strip()


def mixed_cc(value):
    match = CC_WITH_SCOPE.fullmatch(value.strip()) if "[" in value else None
    if match:
        license_text, scope, notice = match.groups()
        if TEXT_SCOPE.fullmatch(" ".join(plain(scope).split())):
            if notice is None or COPYRIGHT.search(plain(notice)) or COPYRIGHT_PREFIX.match(notice):
                cc = normalize(license_text)
                if cc["family"]:
                    return cc, scope.strip(), notice.strip() if notice else None

    match = CC_WITH_COPYRIGHT.fullmatch(value.strip())
    if match and COPYRIGHT_PREFIX.match(match[2]):
        cc = normalize(match[1])
        if cc["family"]:
            return cc, None, match[2].strip()

    match = COPYRIGHT_WITH_CC.fullmatch(value.strip())
    if match:
        license_text = re.sub(r"\s+creative commons$", "", match[2], flags=re.I)
        cc = normalize(license_text)
        if cc["family"]:
            return cc, None, match[1].strip()
    match = INSTITUTIONAL_NOTICE_WITH_LICENSE.fullmatch(value.strip())
    if match:
        cc = normalize(match[2])
        if cc["family"]:
            return cc, None, match[1].rstrip(",").strip()
    return None


def is_access(value, label):
    value = re.sub(r"^dc\.rights\.accessrights:\s*", "", value, flags=re.I)
    label = label.lstrip("| ").replace("_", " ").rstrip(".!")
    if ACCESS_URL.fullmatch(value) or ACCESS.fullmatch(label):
        return True
    parts = re.split(r"\s*/\s*", label)
    if len(parts) > 1 and all(ACCESS.fullmatch(part) for part in parts):
        return True
    # Access labels may include a reason, audience, or embargo date.
    return bool(re.fullmatch(
        r"(?:restricted access|acceso restringido|acesso restrito)\s*[-–:]\s*"
        r"(?:author['’]s decision|publisher['’]s policy|confidentiality agreement|por decision del autor)|"
        r"acceso restringido (?:para |a )?la comunidad universitaria(?: de la [a-z0-9 -]+)?|"
        r"open access with restricted files|open access, restricted access ou embargoed access|"
        r"acceso al texto completo restringido|"
        r"(?:embargoed access|acceso embargado|acesso embargado)\s*[-–:]?\s*"
        r"(?:(?:until|hasta|ate)\s+)?\d{4}(?:-\d{2}(?:-\d{2})?)?",
        label,
    ))


def classify(value):
    text = value.strip()
    label = " ".join(plain(text).split()).rstrip(".")
    if is_access(text, label):
        return None
    cc = normalize(text)
    if not cc["family"]:
        mixed = re.fullmatch(r"([^()]+?)\s*\(([^()]+)\)", label)
        if mixed and ACCESS.fullmatch(mixed[1].strip()):
            cc = normalize(mixed[2])
    if cc["family"]:
        return "CC", "public_domain_dedication" if cc["family"] == "CC0" else "license", cc
    if PUBLIC_DOMAIN_MARK.search(text):
        mark = dict(family="CC-PDM", specific="CC-PDM-1.0", version="1.0", jurisdiction="international")
        return "CC", "public_domain_mark", mark
    if RIGHTS_STATEMENT.search(text):
        return "NON_CC", "rights_statement", cc
    if COPYRIGHT.search(label):
        return "COPYRIGHT", "notice", cc
    if label in {"domini public", "dominio publico", "public domain"}:
        return "NON_CC", "public_domain_label", cc
    if SOFTWARE.search(text):
        return "NON_CC", "software_or_documentation_license", cc
    if label in INSTITUTIONAL:
        return "NON_CC", "institutional_license", cc
    reference = reference_subtype(text)
    if reference:
        return "NON_CC", reference, cc
    if CC_REFERENCE.search(label):
        return "NON_CC", "cc_reference_unresolved", cc
    if re.search(r"\b(?:licencia|licenca|license|licence|llicencia)\b", label):
        return "NON_CC", "license_or_policy_unidentified", cc
    return "NON_CC", "unclassified", cc


def classify_inventory_row(row):
    alternatives = copyright_alternatives(row["value"])
    if alternatives:
        cc, declared, notice = alternatives
        if cc:
            category = "CC"
            subtype = "public_domain_dedication" if cc["family"] == "CC0" else "license"
        else:
            category, subtype = "NON_CC", "cc_reference_unresolved"
            cc = normalize("")
        row.update(category=category, subtype=subtype, creativeCommons=cc,
                   declaredLicenses=declared, copyright=notice)
        apply_url_priority(row)
        return row
    mixed = mixed_cc(row["value"])
    if mixed:
        cc, scope, notice = mixed
        row.update(category="CC", subtype="license", creativeCommons=cc,
                   scope=scope, copyright=notice)
        apply_url_priority(row)
        return row
    result = classify(row["value"])
    if result is None:
        return None
    category, subtype, cc = result
    row.update(category=category, subtype=subtype, creativeCommons=cc)
    if category != "CC":
        fragments = detect(row["value"]) or fallback(row["value"]) or declaration_fallback(row["value"])
        if fragments:
            family = fragments["creativeCommons"]["family"]
            subtype = {"CC0": "public_domain_dedication", "CC-PDM": "public_domain_mark"}.get(family, "license")
            if family is None:
                subtype = "cc_unspecified"
            row.update(category="CC", subtype=subtype, **fragments)
        elif subtype == "cc_reference_unresolved" or CC_REFERENCE.search(plain(row["value"])):
            decision = review_reference(row["value"])
            if decision:
                row.update(decision)
            else:
                preferred = detect(row["value"], prefer_code=True)
                if preferred and preferred.get("decisionRule"):
                    row.update(category="CC", subtype="license", **preferred)
    apply_ordered_name(row)
    apply_url_priority(row)
    apply_structural_repairs(row)
    resolve_pending_cc(row)
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inventory", type=Path)
    args = parser.parse_args()
    with args.inventory.open(encoding="utf-8") as source:
        for line in source:
            row = json.loads(line)
            if classify_inventory_row(row) is not None:
                print(json.dumps(row, ensure_ascii=False, separators=(",", ":")))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
