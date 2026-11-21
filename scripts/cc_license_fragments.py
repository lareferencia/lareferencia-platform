"""Recognize corroborating Creative Commons declarations embedded in rights values."""

import re

from normalize_cc_licenses import (
    ATTRIBUTION, FAMILIES, JURISDICTIONS, PORT_CODES, TERMS, VERSIONS, from_url, plain,
)


def choices(words):
    return "|".join(re.escape(word).replace(r"\ ", r"[\s-]+") for word in sorted(words, key=len, reverse=True))


SEP = r"[\s_./–—‐‑:-]*"
CODE = re.compile(rf"(?<!\w)(?:(?P<prefix>creative\s*commons?|cc){SEP})?"
                  rf"(?P<by>by)(?P<terms>(?:{SEP}(?:nd|sa|nc))*)(?!\w)"
                  rf"|(?<!\w)cc{SEP}(?P<instrument>0|pdm)(?!\w)")
NAME_ATTRIBUTION = ATTRIBUTION | {"attibution", "atributtion", "attribuzione", "aitortu", "attributions"}
NAME_TERMS = {**TERMS, "sinderivados": "nd", "no derivadas": "nd", "noderivadas": "nd", "sinderivas": "nd", "noncomercial": "nc",
              "non commerciale": "nc", "non opere derivate": "nd", "ezkomertziala": "nc",
              "ez komertziala": "nc", "laneratorririkgabe": "nd", "partekatuberdin": "sa"}
NAME = re.compile(rf"\b(?:{choices(NAME_ATTRIBUTION)})(?:\s*/\s*(?:{choices(NAME_ATTRIBUTION)}))?"
                  rf"(?P<terms>(?:[\s,_–—‐‑-]+(?:{choices(NAME_TERMS)}))*)(?!\w)")
TERM = re.compile(choices(NAME_TERMS))
NAME_JURISDICTIONS = {**JURISDICTIONS, "italia": "it", "internazionale": "international",
                      "nazioartekoa": "international", "nazioarteko": "international", "espainia": "es"}
QUALIFIER = rf"(?:{choices(NAME_JURISDICTIONS)}|{choices(PORT_CODES)})"
SUFFIX = re.compile(rf"[\s/-]+(?:(?P<v>{VERSIONS})(?:[\s-]+(?P<j>{QUALIFIER})\b)?"
                    rf"|(?P<jfirst>{choices(NAME_JURISDICTIONS)})[\s-]+(?P<vlast>{VERSIONS}))(?![\w.]*\d)(?!\w)")
URL = re.compile(r"""(?:\b[a-z]+://|(?<![\w./@-])(?:www\.|i\.)?creativecommons\.org/)[^\s<>"'()\[\]]+""")
SPACED_PATH = re.compile(r"(https?://(?:www\.)?creativecommons\.org/licenses/)(by(?:\s+(?:nd|sa|nc))+)(?=/)")
CONTEXT = re.compile(r"(?:\bcc|creative\s*commons?)(?:\s+de)?[\s:–—-]*$")
BLOCK = re.compile(r"\b(?:ejemplo|exemplo|example|exemple|sense cap|without|except|excepto|"
                   r"sin (?:una )?licencia|sem (?:uma )?licenca|not (?:licensed|under|cc|creative commons)|no (?:se aplica|esta baj[oa])|(?:no|non|nao|sin|sem) (?:cc|creative commons)|open data commons|odc-by)\b")
NOTICE = re.compile(r"©|\bcopyright\b|\(c\)|\(cc\)\s*\d{4}|\b(?:derechos de autor|direitos (?:autorais|de autor)|"
                    r"all rights reserved|(?:derechos|direitos|drets) reserva\w+)")
UNKNOWN_TERM = re.compile(r"[–—‐‑_-]+[a-z]|\s+(?:no[n]?|sin|sem|sense|share|compart\w*)\b")


REFERENCE_HOST = r"(?:(?:https?|httpss)://)?(?:www\.)?creativecommons\.org"
HOMEPAGE = re.compile(rf"(?:{REFERENCE_HOST}|https?://br\.creativecommons\.org)/?", re.I)
CC0_CHOOSER = re.compile(rf"{REFERENCE_HOST}/choose/zero/?(?:\?lang=[a-z_-]+)?", re.I)
LICENSE_PATH = re.compile(r"^(https?://(?:www\.)?creativecommons\.org)/(?:license|licencias|licenses)/"
                          r"(by(?:[-.]?(?:nd|nc|sa))*)(?=/|$)", re.I)


def reference_subtype(value):
    label = plain(value.strip())
    if re.search(r"\bsense cap llicencia creative commons\b", label):
        return "cc_negated"
    if re.fullmatch(r"(?:ejemplo|exemplo|example|exemple):\s*https?://(?:www\.)?creativecommons\.org/[^\s]+", label):
        return "cc_example"
    if HOMEPAGE.fullmatch(value.strip()):
        return "cc_homepage"
    if CC0_CHOOSER.fullmatch(value.strip()):
        return "cc0_selector"
    return None


def fragment_url(url):
    parsed = from_url(url)
    if parsed:
        return parsed
    if len(url) % 2 == 0 and url[:len(url)//2] == url[len(url)//2:]:
        return from_url(url[:len(url)//2])
    anomalous = re.fullmatch(r"https?://(?:www\.)?creativecommons\.org/licenses/([a-z-]+)/4\.[1-9]\d*/?", url)
    if anomalous and anomalous[1] in FAMILIES:
        return "CC-" + anomalous[1].upper(), None, None
    match = LICENSE_PATH.match(url)
    if match:
        tokens = re.findall(r"by|nd|nc|sa", match[2].lower())
        family = "-".join(tokens)
        if family in FAMILIES:
            return from_url(match[1] + "/licenses/" + family + url[match.end():])
    return None


SCOPE_EXCEPTION = re.compile(r",\s*(?:except where otherwise noted|excepto d[oó]nde est[aá] identificado)\s*,", re.I)
GENERIC_FRAGMENT = re.compile(
    r"\b(?:licen[çcs]a|licen[cs]e|llic[eè]ncies?|llic[eè]ncia|lic[eè]ncia|licencia)(?:\s+(?:de|d&apos;[uú]s de))?\s+creative commons"
    r"|\b(?:termos|direitos) da creative commons|\bcreative commons\s+(?:licen[cs]e|licencia|licen[çc]a)\b", re.I)
DECLARATION = re.compile(r"\b(?:sob|sota|bajo|under|termos|terms|licensed|licenciado|licenciada|subjecte|subjecta|subject to|distribuid[oa]|protegido|contem|conte|otorga|sujet[oa]|publicat|publicad[oa])\b")
GENERIC_END = re.compile(rf"\s*(?P<version>{VERSIONS})?(?:\s+(?P<jur>international|internacional|unported))?\s*[.:;]?\s*(?:fonte:.*)?$", re.I)


def declaration_fallback(value):
    scope = SCOPE_EXCEPTION.search(value)
    text = SCOPE_EXCEPTION.sub(lambda m: " " * len(m[0]), value)
    folded = plain(text)
    if BLOCK.search(folded) or re.search(r"\b(?:not|never|nao|sense|ninguna|nenhuma|ningun|sem|sin|no)\b", folded):
        return None
    standalone = re.fullmatch(rf"(?:licen[çcs]a |licencia |llicència )?creative commons(?: licen[çcs]a)? (?P<version>{VERSIONS})(?: (?P<jur>international|internacional|unported))?\.?", text.strip(), re.I)
    if standalone:
        cc = dict(family=None, specific=None, version=standalone["version"],
                  jurisdiction="international" if standalone["jur"] else None)
        start = value.index(text.strip())
        return dict(creativeCommons=cc, ccEvidence=[dict(rule="generic_version", fragment=text.strip(),
                    start=start, end=start + len(text.strip()), **cc)])
    result = detect(text) if scope else None
    if not result:
        match = GENERIC_FRAGMENT.search(text)
        if not match or not DECLARATION.search(plain(text[:match.start()])):
            return None
        if re.search(r"https?://|\bby\b|creative commons|atribuci|attribution|reconocimiento", plain(text[:match.start()])):
            return None
        end = GENERIC_END.fullmatch(text[match.end():].strip())
        if not end:
            return None
        cc = dict(family=None, version=end["version"], jurisdiction="international" if end["jur"] else None, specific=None)
        result = dict(creativeCommons=cc, ccEvidence=[dict(rule="generic_fragment", fragment=match[0],
                      start=match.start(), end=match.end(), **cc)])
        prefix = text[:match.start()]
        if NOTICE.search(plain(prefix)):
            result["copyright"] = prefix.strip()
    if scope:
        result["scope"] = value[:scope.end()].strip(" ,")
    return result


def detect(value, prefer_code=False):
    folded = plain(value)
    if BLOCK.search(folded):
        return None
    # Preserve offsets in the original even with combining marks or expanding case folds.
    positions = [i for i, char in enumerate(value) for _ in plain(char)] + [len(value)]
    found = []

    def add(rule, start, end, family, version, jurisdiction):
        found.append(dict(rule=rule, fragment=value[positions[start]:positions[end]],
                          family=family, version=version, jurisdiction=jurisdiction,
                          start=positions[start], end=positions[end]))

    masked = list(folded)
    for m in SPACED_PATH.finditer(folded):
        for i in range(m.start(2), m.end(2)):
            if masked[i].isspace():
                masked[i] = "-"
    for m in URL.finditer("".join(masked)):
        url = m[0].rstrip(".,;")
        parsed = fragment_url(url)
        if re.fullmatch(r"(?:https?://)?(?:www\.)?creativecommons\.org/publicdomain/mark/1\.0/?", url):
            parsed = ("CC-PDM", "1.0", "international")
        if parsed:
            add("url", m.start(), m.start()+len(url), *parsed)
        elif "creativecommons.org/" in url:
            return None
        masked[m.start():m.end()] = " " * len(m[0])
    text = "".join(masked)
    for rule, pattern in (("code", CODE), ("name", NAME)):
        for m in pattern.finditer(text):
            suffix = SUFFIX.match(text, m.end())
            end = suffix.end() if suffix else m.end()
            version = (suffix["v"] or suffix["vlast"]) if suffix else None
            j = (suffix["j"] or suffix["jfirst"]) if suffix else None
            jurisdiction = NAME_JURISDICTIONS.get(j, j)
            context = CONTEXT.search(text[:m.start()])
            if rule == "code" and m["instrument"]:
                family = "CC0" if m["instrument"] == "0" else "CC-PDM"
            else:
                if rule == "code":
                    terms = re.findall(r"sa|nd|nc", m["terms"])
                    if not (terms or m["prefix"] or context):
                        continue
                else:
                    terms = [NAME_TERMS[re.sub(r"[\s-]+", " ", term[0])] for term in TERM.finditer(m["terms"])]
                    if not (terms or context or suffix or any(hit["rule"] in {"code", "url"} for hit in found)):
                        continue
                code = "-".join(["by", *terms])
                if code not in FAMILIES or (not suffix and UNKNOWN_TERM.match(text[m.end():])):
                    return None
                family = "CC-" + code.upper()
            add(rule, m.start(), end, family, version, jurisdiction)

    if not found:
        return None
    fields = [{hit[key] for hit in found if hit[key]} for key in ("family", "version", "jurisdiction")]
    chosen_by_code = False
    if prefer_code and any(len(options) > 1 for options in fields):
        codes = [hit for hit in found if hit["rule"] == "code"]
        if codes and all(hit["rule"] in {"name", "code"} for hit in found) and any(hit["rule"] == "name" for hit in found):
            fields = [{hit[key] for hit in codes if hit[key]} for key in ("family", "version", "jurisdiction")]
            chosen_by_code = True
    if any(len(options) > 1 for options in fields):
        return None
    family, version, jurisdiction = (next(iter(options), None) for options in fields)
    specific = family
    if version and jurisdiction:
        specific += "-" + version
        if jurisdiction != "international":
            specific += "-" + jurisdiction.upper()
    result = dict(creativeCommons=dict(family=family, version=version, jurisdiction=jurisdiction,
                                       specific=specific), ccEvidence=found)
    if chosen_by_code:
        result["decisionRule"] = "explicit_code"
    scope = re.search(r"\[([^\[\]]+)\]", value)
    if scope and re.fullmatch(r"(?:nomes (?:pel|per al) text|solo (?:para )?el texto|text only|only the text|somente (?:para )?o texto)", plain(scope[1]).strip()):
        result["scope"] = scope[1].strip()
    # Keep notices on either side of the declaration, including the original punctuation.
    for part in (value[:min(h['start'] for h in found)], value[max(h['end'] for h in found):]):
        if NOTICE.search(plain(part)):
            result["copyright"] = part.strip().rstrip(" ,;/(").lstrip(" ,;/").strip()
    return result


# Standalone labels and affirmative declarations with no license conditions.
GENERIC_CC = re.compile(
    r"(?:(?:licencia|licenca|llicencia)(?: de)? )?creative commons(?: licen[cs]e)?|"
    r"under a creative commons licen[cs]e|"
    r"aquest(?:a)? (?:document|article|publicacio|material) (?:esta subject[ea] a|te) "
    r"(?:una?|aquesta) llicencia (?:de )?creative commons|"
    r"(?:este|esta) (?:e um artigo publicado em acesso aberto sob|(?:trabalho|obra) esta sob) "
    r"uma licenca creative commons(?:\. fonte: (?:o )?pdf do artigo)?|"
    r"this is an open access article distributed under the terms of the creative commons license"
    r"(?:\. fonte: (?:o )?pdf do artigo)?"
)
GENERIC_DECLARATION = re.compile(
    rf"(?:este trabalho esta sob uma licenca creative commons(?: (?P<version>{VERSIONS}))?"
    r"(?:\. fonte: (?:o )?pdf do artigo)?|"
    r"this work is distributed under this creative commons license|"
    r"este es un articulo publicado en acceso abierto bajo una licencia creative commons|"
    r"obra distribuida bajo licencia creative commons)"
)
COPYRIGHT_GENERIC = re.compile(
    r"(?P<notice>copyright\s*(?:\(c\)\s*)?\d{4})\s+(?P<license>licen[çc]a creative commons)\.?", re.I
)
# A word boundary can be missing between attribution and its translated conditions.
JOINED_NAME = re.compile(rf"\b({choices(NAME_ATTRIBUTION)})(?=(?:{choices(NAME_TERMS)}))")


def fallback(value):
    clean = value.strip().strip("\u200b\ufeff\u2060").strip()
    label = plain(clean)
    rule = None
    notice = None
    if re.fullmatch(r"https?://(?:www\.)?creativecommons\.org\.?/+[^\s?#]+", label):
        url = re.sub(r"^(https?://(?:www\.)?creativecommons\.org)\.?/+", r"\1/", label)
        parsed = from_url(url)
        if parsed:
            family, version, jurisdiction = parsed
            rule = "normalized_url"
    elif re.fullmatch(r"creative commons public domain mark(?:\s*\(pdm\))?\.?", label):
        family, version, jurisdiction, rule = "CC-PDM", None, None, "instrument_name"
    elif JOINED_NAME.search(label):
        # Reuse the fragment grammar and its agreement checks on the entire declaration.
        # Build the offset map so evidence still points into the unmodified source.
        folded = plain(value)
        offsets = [i for i, char in enumerate(value) for _ in plain(char)] + [len(value)]
        splits = {offsets[m.end()] for m in JOINED_NAME.finditer(folded)}
        expanded, original = [], []
        for i, char in enumerate(value):
            if i in splits:
                expanded.append(" ")
                original.append(i)
            expanded.append(char)
            original.append(i)
        original.append(len(value))
        result = detect("".join(expanded))
        if result and any(h["rule"] == "name" for h in result["ccEvidence"]):
            for h in result["ccEvidence"]:
                start, end = original[h["start"]], original[h["end"]]
                h.update(fragment=value[start:end], start=start, end=end)
                if h["rule"] == "name":
                    h["rule"] = "joined_name"
            return result
    elif GENERIC_CC.fullmatch(" ".join(label.split()).rstrip(".")):
        family, version, jurisdiction, rule = None, None, None, "unspecified_cc"
    elif declaration := GENERIC_DECLARATION.fullmatch(" ".join(label.split()).rstrip(".")):
        family, version, jurisdiction, rule = None, declaration["version"], None, "generic_declaration"
    elif declaration := COPYRIGHT_GENERIC.fullmatch(clean):
        family, version, jurisdiction, rule = None, None, None, "generic_declaration"
        notice = declaration["notice"]
        clean = declaration["license"]
    if rule:
        specific = family
        if version and jurisdiction:
            specific = f"{family}-{version}"
            if jurisdiction != "international":
                specific += "-" + jurisdiction.upper()
        start = value.index(clean)
        cc = dict(family=family, version=version, jurisdiction=jurisdiction, specific=specific)
        result = dict(creativeCommons=cc, ccEvidence=[
            dict(rule=rule, fragment=clean, start=start, end=start+len(clean), **cc)
        ])
        if notice:
            result["copyright"] = notice
        return result


def review_reference(value):
    """Resolve remaining declarations without discarding competing evidence."""
    text = value.strip()
    label = plain(text)
    if BLOCK.search(label):
        return None
    empty = dict(family=None, specific=None, jurisdiction=None, version=None)
    for path, subtype in ((r"licenses/?(?:\?lang=[\w-]+)?|choose/?", "cc_directory"),
                          (r"licenses/\d+\.\d+/?", "cc_version_only_url")):
        if re.fullmatch(rf"{REFERENCE_HOST}/(?:{path})", label):
            return dict(category="NON_CC", subtype=subtype)

    cc = None
    details = {}
    if re.match(r"https?://(?:www\.)?creativecommons\.org/", label):
        url = re.sub(r"\s+", "", label).replace("‐", "-").replace("‑", "-")
        if re.fullmatch(r"https?://(?:www\.)?creativecommons\.org/licenses/cc0/?", url):
            cc = dict(empty, family="CC0", specific="CC0")
        else:
            url = re.sub(r"/by-(nd|sa)-nc/", r"/by-nc-\1/", url)
            if re.fullmatch(r"https?://(?:www\.)?creativecommons\.org/licenses/by(?:-nc)?(?:-sa|-nd)?/"
                            rf"(?:{VERSIONS})/(?:[a-z]{{2}}/)?(?:deed(?:\.[\w-]+)?|legalcode)?", url):
                cc = detect(url)["creativeCommons"]
        rule = "repaired_license_url"
    elif doi := re.fullmatch(r"(.+?)\s+https?://doi\.org/10\.[^\s]+", text, re.I | re.S):
        generic = fallback(doi[1]) or declaration_fallback(doi[1])
        if generic:
            cc = generic["creativeCommons"]
        rule = "declaration_with_doi"
    elif re.fullmatch(r"licencia de distribucion no.exclusiva\s*\(creative commons\)", label):
        cc, rule = empty, "generic_distribution"
    elif re.search(r"licencia creative commons asignacion\s+4\.0 internacional\b", label):
        if (DECLARATION.search(label) or "se autoriza" in label) and not CODE.search(label):
            cc, rule = dict(empty, version="4.0", jurisdiction="international"), "generic_declaration"
    elif "://" not in text:
        parts = re.split(r"\s*[;\n]+\s*", text.strip())
        scoped = []
        for part in parts:
            m = re.fullmatch(r"(.+?)\s*\[([^\]]+)\]", part) or re.fullmatch(
                r"(presentaci[oó]|v[ií]deo)\s+publica[dt]a?\s+sota llic[eè]ncia\s+(.+?)\.?", part, re.I)
            if m:
                license_text, scope = m.groups() if '[' in part else (m[2], m[1])
                result = detect(license_text)
                if result:
                    scoped.append(dict(scope=scope, **result["creativeCommons"]))
        if len(scoped) == len(parts) and len(parts) > 1:
            return dict(category="CC", subtype="scoped_licenses", scopedLicenses=scoped, creativeCommons=empty)
        m = re.search(r"\(\s*((?:cc\s*[-:]?\s*)?by[\s\w./–—-]*)\s*\)\s*\.?$", text, re.I)
        if m:
            title = text[:m.start()].strip()
            named = detect(title)
            if named and all(h["rule"] == "name" for h in named["ccEvidence"]):
                code = normalize_code_declaration(m[1])
                details = dict(nameInterpretation=named["creativeCommons"], declaredCode=m[1])
                if named.get("copyright"):
                    details["copyright"] = named["copyright"]
                if code:
                    cc, rule = code, "explicit_code"
                elif re.fullmatch(r"(?:cc[ -]*)?by(?:[ -]+[a-z]{2})+(?:\s+\d\.\d(?:\s+[a-z]{2})?)?", m[1], re.I):
                    return dict(category="CC", subtype="cc_name_candidate", creativeCommons=empty, **details)
        # Textual names can contain unfamiliar terms. Require agreement of all
        # complete codes, independent of whether the name is in the vocabulary.
        if cc is None and NAME.search(label) and not re.search(r"[;\[\]]|\b(?:except|not|without|video)\b", label):
            codes = []
            for token in CODE.finditer(text.lower()):
                if not (token["prefix"] or token["terms"] or token["instrument"]):
                    continue
                tail = text[token.end():]
                if re.match(r"[-_/.][A-Za-z]|\s+(?:ns|as|mc)\b", tail, re.I):
                    return None
                suffix = SUFFIX.match(plain(tail))
                end = token.end() + (suffix.end() if suffix else 0)
                code = normalize_code_declaration(text[token.start():end])
                if not code:
                    return None
                codes.append((text[token.start():end], code))
            if codes and all(code == codes[0][1] for _, code in codes):
                details["declaredCode"], cc = codes[0]
                rule = "explicit_code"
    if cc is not None:
        return dict(category="CC", subtype=("public_domain_dedication" if cc["family"]=="CC0" else
                    "license" if cc["family"] else "cc_unspecified"), creativeCommons=cc,
                    ccEvidence=[dict(rule=rule, fragment=text, start=value.index(text),
                                     end=value.index(text)+len(text), **cc)], **details)


def normalize_code_declaration(text):
    text = re.sub(r"(?i)(?<=by)([ -]+)(nd|sa)([ -]+)nc\b", r"\1nc\3\2", text.strip())
    match = CODE.match(plain(text.strip()))
    if match and (not text[match.end():].strip() or SUFFIX.fullmatch(plain(text[match.end():]))):
        result = detect(text)
        if result:
            return result["creativeCommons"]


# Match a sequence of license conditions. Each token has a semantic role;
# punctuation, case, accents and conjunctions do not determine the family.
ORDERED_BY = NAME_ATTRIBUTION | {"atrib", "atribucio", "paternite", "uznanie autorstwa"}
ORDERED_TERMS = {
    **NAME_TERMS, "non commerciale": "nc", "pas d'utilisation commerciale": "nc",
    "pas de modification": "nd", "sans modification": "nd", "sin obra derivada": "nd",
    "non derivadas": "nd", "senseobresderivades": "nd", "sem obras derivadas": "nd",
    "partage dans les memes conditions": "sa", "condividi allo stesso modo": "sa",
    "bez utworow zaleznych": "nd", "compartilhar igual": "sa",
}
ORDERED_SEPARATOR = r"[\s.,:/_–—‐‑-]*(?:(?:y|e|et|and|i)\s+)?"
ORDERED_START = re.compile(rf"(?<!\w)({choices(ORDERED_BY)})(?=\W|{choices(ORDERED_TERMS)}|$)")
ORDERED_NEXT = re.compile(rf"{ORDERED_SEPARATOR}({choices(ORDERED_TERMS)})")
ORDERED_CODE = re.compile(r"\s*\(\s*((?:cc[ .-]*)?by[\w\s./–—-]*)\s*\)\s*\.?$", re.I)


def apply_ordered_name(row):
    value = row["value"]
    label = plain(value)
    start = ORDERED_START.search(label)
    if not start or BLOCK.search(label) or "://" in label or row.get("declaredLicenses") or row.get("scopedLicenses"):
        return
    prefix = label[:start.start()]
    if re.search(r"\b(?:not|sin|sem|no|nao|sans|by)\b|[;\[\]]", prefix):
        return
    end = start.end()
    components = []
    while match := ORDERED_NEXT.match(label, end):
        components.append(ORDERED_TERMS[re.sub(r"[\s-]+", " ", match[1])])
        end = match.end()
    if not components:
        return
    family = "-".join(["by", *components])
    if family not in FAMILIES:
        return
    suffix = SUFFIX.match(label, end)
    version = jurisdiction = None
    if suffix:
        version = suffix["v"] or suffix["vlast"]
        j = suffix["j"] or suffix["jfirst"]
        jurisdiction = NAME_JURISDICTIONS.get(j, j)
        end = suffix.end()
    # An unfamiliar condition or a second declaration requires separate interpretation.
    tail = re.sub(r"^\s+(?:license|licence)\b", "", label[end:]).strip()
    code = ORDERED_CODE.fullmatch(tail)
    if tail.strip(". ") and not code:
        return
    valid_code = normalize_code_declaration(code[1]) if code else None
    if valid_code and row["creativeCommons"]["family"]:
        return  # Preserve the existing decision and evidence.
    if code and not valid_code and not re.fullmatch(r"(?:cc[ -]*)?by(?:[ -]+[a-z]{2})+(?:\s+\d\.\d(?:\s+[a-z]{2})?)?", code[1], re.I):
        return
    family = "CC-" + family.upper()
    # Country labels beside 4.0 are not country-ported license identifiers.
    if version == "4.0" and jurisdiction not in {"international", "igo"}:
        jurisdiction = None
    specific = family
    if version and jurisdiction:
        specific += "-" + version
        if jurisdiction != "international":
            specific += "-" + jurisdiction.upper()
    cc = dict(family=family, specific=specific, version=version, jurisdiction=jurisdiction)
    if valid_code:
        row["nameInterpretation"] = cc
        cc = valid_code
    if row["creativeCommons"]["family"] == cc["family"]:
        return
    positions = [i for i, char in enumerate(value) for _ in plain(char)] + [len(value)]
    first, last = positions[start.start()], positions[end]
    row.update(category="CC", subtype="license", creativeCommons=cc, decisionRule="explicit_code" if valid_code else "ordered_name",
               ccEvidence=[dict(rule="ordered_name", fragment=value[first:last], start=first, end=last, **row.get("nameInterpretation", cc))])
    if code:
        raw_code = ORDERED_CODE.search(value)
        if raw_code:
            row["declaredCode"] = raw_code[1]
    if NOTICE.search(prefix):
        row.setdefault("copyright", value[:first].strip(" ,;"))


LICENSE_LINK = re.compile(
    r"(?:https?(?::/{1,2}|;//)|(?<![\w./@-]))(?:www\.)?creativecommons\.org/"
    r"\s*li\s*cen[cs]es/(?:by(?:\s+(?:nc|nd|sa))+(?=/)|[^\s<>\"'()\[\]]+)"
    r"[^\s<>\"'()\[\]]*|" + URL.pattern, re.I)
REORDERED_NOTICE = re.compile(r"\s*cc[ -]by[ -](nd|sa)[ -]nc\s*,?\s*(\(c\).+)\s*", re.I | re.S)


def normalized_link(literal):
    url = literal.lower()
    url = re.sub(r"^https?[:;]/{1,2}(?=(?:www\.)?creativecommons\.org/)", "https://", url)
    url = re.sub(r"(creativecommons\.org/)\s*li\s*cen([cs])es/", r"\1licen\2es/", url)
    url = SPACED_PATH.sub(lambda m: m[1] + "-".join(m[2].split()), url)
    return re.sub(rf"(/licen[cs]es/)(by(?:-nc)?(?:-nd|-sa)?)({VERSIONS})(?=/|$)", r"\1\2/\3", url)


def apply_url_priority(row):
    value = row["value"]
    notice = REORDERED_NOTICE.fullmatch(value)
    if notice and not row["creativeCommons"]["family"]:
        family = "CC-BY-NC-" + notice[1].upper()
        cc = dict(family=family, specific=family, version=None, jurisdiction=None)
        row.update(category="CC", subtype="license", decisionRule="reordered_code", creativeCommons=cc,
                   copyright=notice[2], ccEvidence=[dict(rule="reordered_code", fragment=value,
                   start=0, end=len(value), **cc)])
        return
    if ("." not in value or row.get("declaredLicenses") or row.get("scopedLicenses")
            or BLOCK.search(plain(value))):
        return
    links = []
    masked = list(value)
    for match in LICENSE_LINK.finditer(value):
        literal = value[match.start():match.end()].rstrip(".,;")
        url = normalized_link(literal)
        parsed = fragment_url(url)
        if re.fullmatch(r"(?:https?://)?(?:www\.)?creativecommons\.org/publicdomain/mark/1\.0/?", url):
            parsed = "CC-PDM", "1.0", "international"
        if parsed:
            family, version, jurisdiction = parsed
            specific = family
            if version and jurisdiction:
                specific += "-" + version
                if jurisdiction != "international":
                    specific += "-" + jurisdiction.upper()
            cc = dict(family=family, version=version, jurisdiction=jurisdiction, specific=specific)
            links.append(dict(rule="url", fragment=literal, start=match.start(),
                              end=match.start()+len(literal), **cc))
        masked[match.start():match.end()] = " " * len(match[0])
    if masked == list(value):
        return
    text = "".join(masked)
    if links:
        fields = ("family", "version", "jurisdiction")
        options = [{hit[k] for hit in links if hit[k]} for k in fields]
        if any(len(items) > 1 for items in options):
            row.update(category="NON_CC", subtype="cc_reference_unresolved", decisionRule="conflicting_urls",
                       creativeCommons=dict.fromkeys((*fields, "specific")), ccEvidence=links)
            return
        best = max(links, key=lambda h: sum(h[k] is not None for k in fields))
        chosen = {k:best[k] for k in (*fields, "specific")}
        previous = row["creativeCommons"]
        if previous["family"] == chosen["family"] and chosen["version"] is None and previous["version"]:
            return
        rule = "license_url"
        hits = links
    else:
        if row["category"] == "CC" or row["subtype"] != "cc_reference_unresolved":
            return
        # An informative or malformed URL may accompany an explicit declaration.
        match = CODE.search(plain(text))
        if not match or not match["prefix"]:
            return
        result = detect(text, prefer_code=True)
        if not result or not any(hit["rule"] == "code" for hit in result["ccEvidence"]):
            return
        chosen, hits, rule = result["creativeCommons"], result["ccEvidence"], "explicit_code"
    if row["creativeCommons"] != chosen:
        prior = row["creativeCommons"]
        if prior["family"]:
            row["previousInterpretation"] = prior
        if links and NOTICE.search(plain(text)) and not row.get("copyright"):
            notice_start = NOTICE.search(plain(text))
            if len(plain(text)) == len(text):
                notice_text = re.split(r",\s*Creative Commons\b|\s+under CC\b", text[notice_start.start():], maxsplit=1, flags=re.I)[0]
                row["copyright"] = notice_text.strip(" ,;")
        subtype = {"CC0":"public_domain_dedication", "CC-PDM":"public_domain_mark"}.get(chosen["family"], "license")
        row.update(category="CC", subtype=subtype, creativeCommons=chosen, decisionRule=rule, ccEvidence=hits)


# Repair only structural damage. The complete family must still pass this grammar.
V14_URL = re.compile(
    rf"(?P<scheme>(?:(?:https?://)?https?|ttp|hhttp|ht6tps|htpp|htttp))://creativecommons\.org/"
    rf"(?P<directory>licenses|lincenses)/(?P<code>by(?:(?:-|%2d|/)(?:nc|sa|nd))*)"
    rf"(?P<separator>[-/])(?P<version>{VERSIONS})(?P<tail>(?:/(?:[a-z]{{2}}|igo))?"
    rf"(?:/(?:legalcode|deed)(?:\.[a-z_-]+)?)?/?)", re.I)
V14_BY = r"(?:atribucio[n]?|atribuicao|reconocimiento|attribution|reconeixement|paternite)"
V14_LICENSE = r"(?:licencia|licenca|llicencia|licence|license)"
V14_NAME = re.compile(
    rf"(?:{V14_LICENSE}\s+(?:de\s+|d['’])?{V14_BY}\s+(?:de\s+)?creative commons|"
    rf"{V14_LICENSE}\s+creative commons\s+{V14_BY})\b")
V14_GENERIC = re.compile(rf"{V14_LICENSE}\s+publica\s+creative commons\s+{V14_LICENSE}\s+({VERSIONS})\.?")


def apply_structural_repairs(row):
    value = row["value"]
    text = value.strip()
    url = V14_URL.fullmatch(text)
    if url:
        code = url["code"].lower().replace("%2d", "-").replace("/", "-")
        if code not in FAMILIES:
            return
        canonical = f'https://creativecommons.org/licenses/{code}/{url["version"]}{url["tail"]}'
        if url["scheme"].lower() in {"http", "https"} and url["directory"].lower() == "licenses" and url["code"].lower() == code and url["separator"] == "/":
            return
        parsed = from_url(canonical)
        if not parsed:
            return
        family, version, jurisdiction = parsed
        rule = "license_url_structure"
    else:
        if row["category"] == "CC" or not re.search(r"creative\s+commons", text, re.I):
            return
        label = plain(text)
        if BLOCK.search(label) or re.search(r"://|\b(?:not|sin|no|sem|nao|sans|by|nc|nd|sa)\b", label):
            return
        version = jurisdiction = None
        generic = V14_GENERIC.fullmatch(label)
        if generic:
            family, version, rule = None, generic[1], "generic_public_license"
        else:
            name = V14_NAME.search(label)
            if not name or re.search(r"creative commons|[;\[\]]|noncommercial|nocomercial|compartir|derivad", label[:name.start()]):
                return
            suffix = SUFFIX.match(label, name.end())
            end = suffix.end() if suffix else name.end()
            if not re.fullmatch(r"\s*\.?(?:\s*fonte:\s*(?:o\s+)?pdf\s+(?:do artigo|do livro))?\s*\.?", label[end:]):
                return
            if suffix:
                version = suffix["v"] or suffix["vlast"]
                j = suffix["j"] or suffix["jfirst"]
                jurisdiction = NAME_JURISDICTIONS.get(j, j)
                if version == "4.0" and jurisdiction not in {"international", "igo"}:
                    jurisdiction = None
            offsets = [i for i, char in enumerate(text) for _ in plain(char)] + [len(text)]
            prefix = text[:offsets[name.start()]]
            if NOTICE.search(plain(prefix)):
                row.setdefault("copyright", re.split(r"\.\s+", prefix.strip(), maxsplit=1)[0].rstrip("."))
            text = text[offsets[name.start()]:offsets[end]]
            family, rule = "CC-BY", "attribution_license_name"
    specific = family
    if family and version and jurisdiction:
        specific += "-" + version
        if jurisdiction != "international":
            specific += "-" + jurisdiction.upper()
    cc = dict(family=family, version=version, jurisdiction=jurisdiction, specific=specific)
    if row["category"] == "CC" and row["creativeCommons"] == cc:
        return
    start = value.index(text)
    row.update(category="CC", subtype="license" if family else "cc_unspecified", creativeCommons=cc,
               decisionRule=rule, ccEvidence=[dict(rule=rule, fragment=text, start=start, end=start+len(text), **cc)])


# These fallbacks operate on unresolved declarations only. A complete family
# is required even when the version segment cannot be interpreted.
EXACT_FAMILY = choices(FAMILIES)
CC_ORIGIN = r"https?://(?:www\.)?creativecommons\.org/"
COMPLETE_PATH = re.compile(
    rf"(?P<family>{EXACT_FAMILY})/(?P<version>{VERSIONS})"
    rf"(?:/(?:{choices(PORT_CODES)}|igo))?(?:/(?:legalcode|deed)(?:\.[a-z_-]+)?)?/?", re.I)
NUMERIC_VERSION_PATH = re.compile(
    rf"{CC_ORIGIN}licenses/(?P<family>{EXACT_FAMILY})/(?P<version>(?=[.\d]*\d)[.\d]+)"
    rf"(?:/(?:{choices(PORT_CODES)}|igo))?(?:/(?:legalcode|deed)(?:\.[a-z_-]+)?)?/?", re.I)
WRITTEN_CODE = rf"cc[ -](?:{EXACT_FAMILY})"
GLUED_CODE = re.compile(rf"(?P<code>{WRITTEN_CODE})(?P<ending>{VERSIONS}|licen[cs]e)", re.I)
SCOPE_PAIR = re.compile(
    rf"(presentació)\s+publicada\s+sota\s+llicència\s+({WRITTEN_CODE}(?:\s+(?:{VERSIONS}))?)\.\s+"
    rf"(vídeo)\s+publicat\s+sota\s+llicència\s+({WRITTEN_CODE}(?:\s+(?:{VERSIONS}))?)\.?", re.I)


def resolve_pending_cc(row):
    if row["subtype"] != "cc_reference_unresolved":
        return
    value = row["value"]
    text = value.strip()
    if re.fullmatch(r"https?://(?:www\.)?creativecommons\.org\.ar/licencias\.html", text, re.I):
        row.update(subtype="cc_directory", decisionRule="license_directory")
        return
    scoped = SCOPE_PAIR.fullmatch(text)
    if scoped:
        scopes = [dict(scope=scoped[i], **normalize_code_declaration(scoped[i+1])) for i in (1, 3)]
        row.update(category="CC", subtype="scoped_licenses", scopedLicenses=scopes, decisionRule="scoped_codes")
        return

    clean = text.strip("”’“\u200b\ufeff:")
    origin = re.match(CC_ORIGIN, clean, re.I)
    if origin:
        path = clean[origin.end():]
        if COMPLETE_PATH.fullmatch(path):
            parsed = from_url("https://creativecommons.org/licenses/" + path)
            rule = "missing_license_directory"
        elif clean != text and path.lower().startswith("licenses/") and COMPLETE_PATH.fullmatch(path[len("licenses/"):]):
            parsed = from_url(clean)
            rule = "url_outer_punctuation"
        else:
            broken = NUMERIC_VERSION_PATH.fullmatch(clean)
            if not broken or re.fullmatch(VERSIONS, broken["version"]):
                return
            parsed = ("CC-" + broken["family"].upper(), None, None)
            rule = "unresolved_version"
        if not parsed:
            return
        family, version, jurisdiction = parsed
        specific = family
        if version and jurisdiction:
            specific += "-" + version
            if jurisdiction != "international":
                specific += "-" + jurisdiction.upper()
        cc = dict(family=family, specific=specific, version=version, jurisdiction=jurisdiction)
        fragment = text
    else:
        match = GLUED_CODE.search(text)
        if not match or BLOCK.search(plain(text)):
            return
        prefix, suffix = text[:match.start()], text[match.end():]
        if not (not prefix or re.fullmatch(r"\(cc\)\s+\d{4}\s+[^()]+\(", prefix, re.I)
                or (DECLARATION.search(plain(prefix)) and not re.search(
                    r"://|\b(?:cc|by|not|sin|no|nao|sem|sans)\b", plain(prefix)))):
            return
        if not re.fullmatch(r"\)?\.?(?:\s+Fonte: PDF do artigo\.)?", suffix, re.I):
            return
        version = match["ending"] if re.fullmatch(VERSIONS, match["ending"]) else None
        cc = normalize_code_declaration(match["code"] + (" " + version if version else ""))
        fragment = match[0]
        rule = "code_attached_version" if version else "code_attached_license"
        if prefix.startswith("(cc)"):
            row["copyright"] = prefix.rstrip(" (")
    start = value.index(fragment)
    row.update(category="CC", subtype="license", creativeCommons=cc, decisionRule=rule,
               ccEvidence=[dict(rule=rule, fragment=fragment, start=start, end=start+len(fragment), **cc)])
