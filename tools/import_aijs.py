#!/usr/bin/env python3
"""scoutica import aijs — deterministic, OFFLINE converter from an ai-job-search fork
(MadsLorentzen/ai-job-search, MIT) into a Scoutica Skill Card.

Reads ONLY local files passed via argv. No network, no git, no AI, no shell — every value
from the source is treated as untrusted text and written through json.dump / yaml.safe_dump,
so quotes/backslashes/`$(...)`/newlines land as literal data and can never execute or corrupt
the output. See SPRINT-AIJS-INTEROP mapping contract.

Exit codes (contract, mirrored in tests/interop.test.sh):
  0  success
  2  placeholder-abort — a required field (title/seniority/skills/primary_domains) is unfilled
  3  enum-unresolvable  — a required enum (seniority) could not be resolved in a non-TTY run
  4  target refusal      — target dir non-empty without --force, or a target file is a symlink
  1  usage / IO error
"""
import argparse
import datetime
import json
import os
import re
import shutil
import sys
import tempfile

try:
    import yaml  # PyYAML; falls back to JSON (valid YAML subset) if absent
    _HAVE_YAML = True
except Exception:
    _HAVE_YAML = False

SCHEMA_VERSION = "0.1.0"
CARD_FILES = ("profile.json", "rules.yaml", "evidence.json", "SKILL.md")

JAA = os.path.join(".claude", "skills", "job-application-assistant")
SCR = os.path.join(".claude", "skills", "job-scraper")


# ── warnings/report (field NAMES only — never echo an imported PII value) ──────────────────
_WARNINGS = []
def warn(field, why):
    _WARNINGS.append((field, why))


# ── source IO ──────────────────────────────────────────────────────────────────────────────
def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


# ── placeholder detection ───────────────────────────────────────────────────────────────────
# Upstream template tokens look like [YOUR_NAME], [DEGREE], [JOB_TITLE], [DOMAIN_1],
# [YOUR_LANGUAGES with proficiency levels]. A value is "unfilled" if it is bracketed and
# contains an ALL-CAPS run of >=2 (real values never do).
def is_placeholder(v):
    if not v:
        return True
    s = v.strip()
    return s.startswith("[") and s.endswith("]") and re.search(r"[A-Z]{2,}", s) is not None


def clean(v):
    return re.sub(r"\s+", " ", (v or "")).strip()


# ── markdown section helpers ────────────────────────────────────────────────────────────────
def section(text, heading):
    """Return the lines under a `## heading` or `### heading` up to the next header of same/higher level."""
    lines = text.splitlines()
    out, depth, capturing = [], None, False
    for ln in lines:
        m = re.match(r"^(#{2,3})\s+(.*)$", ln)
        if m:
            level, name = len(m.group(1)), clean(m.group(2))
            if capturing and level <= depth:
                break
            if name.lower() == heading.lower():
                capturing, depth = True, level
                continue
        if capturing:
            out.append(ln)
    return out


def bullets(lines):
    out = []
    for ln in lines:
        m = re.match(r"^\s*[-*]\s+(.*)$", ln)
        if m:
            out.append(clean(m.group(1)))
    return out


# ── identity bullets: `- **Name:** value` ─────────────────────────────────────────────────────
def parse_identity(text):
    ident = {}
    for ln in section(text, "Identity"):
        m = re.match(r"^\s*[-*]\s*\*\*(.+?):\*\*\s*(.*)$", ln)
        if m:
            ident[clean(m.group(1)).lower()] = clean(m.group(2))
    return ident


# ── professional experience: `### TITLE - COMPANY (START - END)` ──────────────────────────────
_ROLE_RE = re.compile(r"^###\s+(.*)$")
_DATES_RE = re.compile(r"\((\d{4})\s*[-–—]\s*(\d{4}|present|now|current)\)", re.IGNORECASE)

def parse_roles(text):
    roles = []
    for ln in section(text, "Professional Experience"):
        m = _ROLE_RE.match(ln)
        if not m:
            continue
        head = clean(m.group(1))
        title = head.split(" - ")[0].split(" – ")[0].strip()
        dm = _DATES_RE.search(head)
        start = int(dm.group(1)) if dm else None
        end_raw = dm.group(2) if dm else None
        end = datetime.date.today().year if (end_raw and not end_raw.isdigit()) else (int(end_raw) if end_raw else None)
        roles.append({"title": title, "start": start, "end": end})
    return roles


def compute_years(roles):
    starts = [r["start"] for r in roles if r["start"]]
    ends = [r["end"] for r in roles if r["end"]]
    if not starts:
        return None
    latest = max(ends) if ends else datetime.date.today().year
    return max(0, latest - min(starts))


# ── seniority inference ────────────────────────────────────────────────────────────────────────
_SENIORITY_KEYWORDS = [
    ("executive", ["chief", "cxo", "cto", "ceo", "cfo", "coo", "vp", "vice president", "head of"]),
    ("director", ["director"]),
    ("manager", ["manager"]),
    ("lead", ["lead", "principal", "staff"]),
    ("senior", ["senior", "sr.", "sr "]),
    ("junior", ["junior", "jr.", "jr ", "associate"]),
    ("entry", ["intern", "graduate", "trainee", "entry-level", "entry level"]),
]

def infer_seniority(roles, years):
    for r in roles:
        t = (" " + r["title"].lower() + " ")
        for level, kws in _SENIORITY_KEYWORDS:
            if any(k in t for k in kws):
                return level
    if years is None:
        return None
    if years <= 1:
        return "entry"
    if years <= 3:
        return "junior"
    if years <= 7:
        return "mid"
    if years <= 12:
        return "senior"
    return "lead"


# ── skills / domains / tools ─────────────────────────────────────────────────────────────────
def _skill_name(bullet):
    m = re.match(r"^\*\*(.+?)\*\*", bullet)          # **Python** (expert): ...
    if m:
        return clean(m.group(1))
    return clean(re.split(r"[:(]", bullet)[0])        # fallback: text before ( or :

def parse_skills(profile_text, claude_text):
    for head in ("Programming & ML", "Programming and ML", "Programming"):
        b = bullets(section(profile_text, head))
        if b:
            return dedup([_skill_name(x) for x in b])
    # fallback: CLAUDE.md Primary + Secondary
    out = []
    for label in ("Primary", "Secondary"):
        for ln in claude_text.splitlines():
            m = re.match(r"^\s*[-*]?\s*\*\*%s:\*\*\s*(.*)$" % label, ln)
            if m:
                out += [clean(x) for x in m.group(1).split(",")]
    return dedup(out)

def parse_domains(profile_text, claude_text):
    for head in ("Domain Expertise", "Domain"):
        b = bullets(section(profile_text, head))
        if b:
            return dedup(b)
    for ln in claude_text.splitlines():
        m = re.match(r"^\s*[-*]?\s*\*\*Domain:\*\*\s*(.*)$", ln)
        if m:
            return dedup([clean(x) for x in m.group(1).split(",")])
    return []

def parse_tools(profile_text, claude_text):
    for head in ("Software & Tools", "Software and Tools", "Software", "Tools & platforms", "Tools"):
        b = bullets(section(profile_text, head))
        if b:
            out = []
            for line in b:
                out += [clean(x) for x in line.split(",")]
            return dedup(out)
    return []


def dedup(items):
    seen, out = set(), []
    for it in items:
        it = clean(it)
        if it and it.lower() not in seen:
            seen.add(it.lower())
            out.append(it)
    return out


# ── languages ───────────────────────────────────────────────────────────────────────────────
_LEVEL_MAP = {
    "native": "native", "mother tongue": "native", "mothertongue": "native",
    "fluent": "fluent", "c2": "fluent", "c1": "fluent",
    "professional": "professional", "b2": "professional", "b1": "professional",
    "conversational": "professional", "working": "professional",
    "basic": "basic", "a2": "basic", "a1": "basic", "beginner": "basic", "elementary": "basic",
}

def parse_languages(ident):
    raw = ident.get("languages", "")
    if not raw or is_placeholder(raw):
        return []
    out = []
    for part in raw.split(","):
        m = re.match(r"^\s*(.+?)\s*\(([^)]+)\)\s*$", part)
        if not m:
            warn("spoken_languages", "entry without a (level), omitted")
            continue
        lang = clean(m.group(1))
        lvl = _LEVEL_MAP.get(clean(m.group(2)).lower())
        if not lvl:
            warn("spoken_languages", "unrecognized proficiency, entry omitted")
            continue
        out.append({"language": lang, "level": lvl})
    return out


# ── availability (optional; skip+warn if unresolved) ─────────────────────────────────────────
def map_availability(ident):
    s = ident.get("status", "").lower()
    if not s or is_placeholder(ident.get("status", "")):
        return None
    if "not looking" in s or "not open" in s or "happily employed" in s:
        return "not_looking"
    if "immediat" in s or "available now" in s:
        return "immediately"
    if "2 week" in s or "two week" in s:
        return "in_2_weeks"
    if "8 week" in s or "2 month" in s or "two month" in s:
        return "in_8_weeks"
    if "4 week" in s or "1 month" in s or "one month" in s:
        return "in_4_weeks"
    warn("availability", "status did not match a known window, omitted")
    return None


# ── education / certs / specializations ──────────────────────────────────────────────────────
def parse_education(text):
    for ln in section(text, "Education"):
        cells = [clean(c) for c in ln.strip().strip("|").split("|")]
        if len(cells) >= 3 and cells[0] and not is_placeholder(cells[0]) \
                and cells[0].lower() != "degree" and not set(cells[0]) <= set("-: "):
            return "%s, %s" % (cells[0], cells[2])
    return None

def _is_sep(cell):
    return not cell or set(cell) <= set("-:| ")

def parse_specializations(text):
    out = []
    for ln in section(text, "Education"):
        if "|" not in ln:
            continue
        cells = [clean(c) for c in ln.strip().strip("|").split("|")]
        if len(cells) < 4 or _is_sep(cells[0]):                 # skip header separator / malformed rows
            continue
        topics = cells[3]
        if topics and not is_placeholder(topics) and topics.lower() != "key topics" and not _is_sep(topics):
            out += [clean(x) for x in topics.split(",")]
    return dedup(out)

def parse_certs(claude_text):
    out = []
    for ln in bullets(section(claude_text, "Certifications")):
        name = re.split(r"\s+-\s+", ln)[0]
        name = re.sub(r"\*\*", "", name)
        if name and not is_placeholder(name):
            out.append(clean(name))
    return dedup(out)

def parse_summary(claude_text):
    body = "\n".join(section(claude_text, "Summary")).strip()
    if body and not is_placeholder(body):
        return body[:600]
    return None


# ── evidence: only items that carry a URL (schema requires `url`) ────────────────────────────
_URL_RE = re.compile(r"https?://[^\s)\]<>\"']+")

def parse_evidence(profile_text, ident, skills, domains):
    # Every evidence item MUST claim >=1 demonstrated skill (schema: skills_demonstrated non-empty).
    # We only emit items whose skill linkage is honest. A bare GitHub/portfolio/LinkedIn URL does NOT
    # prove any specific skill (we are offline and never fetch it), so attaching skills to it would
    # inflate the scorer's evidence bonus with unverified claims — those links are intentionally NOT
    # emitted as skill-evidence. The candidate can add richer, verifiable evidence by hand. Publications
    # name their subject, so their skill/domain linkage is defensible.
    items = []

    # Publications — demonstrate skills named in the title, else fall back to primary domains
    for ln in section(profile_text, "Publications"):
        line = re.sub(r"^\s*[-*\d.]+\s*", "", ln).strip()
        u = _URL_RE.search(line)
        if line and u and not is_placeholder(line):
            dem = [s for s in skills if s.lower() in line.lower()] or domains[:2] or skills[:3]
            if not dem:
                continue
            # "Author, X. (YEAR). Title. Venue. URL" → take the sentence after the (YEAR).
            after_year = re.sub(r"^.*?\(\d{4}\)\.?\s*", "", line, count=1)
            body = after_year if after_year and after_year != line else line
            body = _URL_RE.sub("", body)                       # never let the URL become the title
            title = clean(re.split(r"\.\s", body)[0]) or "Publication"
            items.append({"type": "publication", "title": title[:200], "url": u.group(0),
                          "description": "Peer-reviewed publication.", "skills_demonstrated": dem})
    return items


# ── rules.yaml pieces ───────────────────────────────────────────────────────────────────────
_ENG_NORMALIZE = {"freelance": "contract"}
_INDUSTRY_LEXICON = {"gambling", "betting", "casino", "weapons", "arms", "defense", "defence",
                     "tobacco", "alcohol", "adult", "porn", "oil", "gas", "fossil", "mining", "crypto"}

def parse_engagement_types(ident, dealbreakers_text):
    s = (ident.get("status", "") + " " + dealbreakers_text).lower()
    found = []
    if "contract" in s or "freelance" in s:
        found.append("contract")
    if "fractional" in s or "part-time" in s or "part time" in s:
        found.append("fractional")
    if "advisory" in s or "advisor" in s or "board seat" in s:
        found.append("advisory")
    if "intern" in s:
        found.append("internship")
    if "permanent" in s or "full-time" in s or "full time" in s or "employed" in s:
        found.append("permanent")
    found = [_ENG_NORMALIZE.get(t, t) for t in found]
    if not found:
        warn("engagement.allowed_types", "no signal in source, defaulted to [permanent]")
        return ["permanent"]
    return dedup(found)

def map_remote_policy(ident, dealbreakers_text):
    s = (ident.get("constraints", "") + " " + ident.get("location", "") + " " + dealbreakers_text).lower()
    if not s.strip():
        warn("remote.policy", "no signal in source, defaulted to flexible")
        return "flexible"
    has_remote = "remote" in s
    has_onsite = ("on-site" in s or "on site" in s or "onsite" in s or "in office" in s or "in-office" in s)
    if "hybrid" in s:
        return "hybrid"
    if has_remote and has_onsite:
        return "flexible"
    if has_remote:
        return "remote_only"
    if has_onsite:
        return "on_site"
    warn("remote.policy", "no remote signal in source, defaulted to flexible")
    return "flexible"

def parse_blocked_industries(dealbreakers_text):
    out = []
    for ln in dealbreakers_text.splitlines():
        low = ln.lower()
        if "industr" in low and ":" in ln:
            out += [clean(x) for x in ln.split(":", 1)[1].split(",")]
        else:
            for tok in re.split(r"[,/]", ln):
                if clean(tok).lower() in _INDUSTRY_LEXICON:
                    out.append(clean(tok))
    return dedup([x for x in out if x and not is_placeholder(x)])

def parse_stack_keywords(search_text, skills):
    kws = []
    for m in re.finditer(r'"([^"]+)"', search_text):
        term = clean(m.group(1))
        if term and not term.lower().startswith("site:") and len(term) < 40:
            kws.append(term)
    kws = dedup(kws + skills)
    return kws[:15]


# ── atomic emit with symlink guard ───────────────────────────────────────────────────────────
def _json_dump(obj, path):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2, ensure_ascii=False)
        f.write("\n")

def _yaml_dump(obj, path):
    with open(path, "w", encoding="utf-8") as f:
        if _HAVE_YAML:
            yaml.safe_dump(obj, f, sort_keys=False, allow_unicode=True, default_flow_style=False)
        else:
            json.dump(obj, f, indent=2, ensure_ascii=False)  # JSON is a valid YAML subset
            f.write("\n")


def _write_card(dstdir, profile, rules, evidence):
    _json_dump(profile, os.path.join(dstdir, "profile.json"))
    _yaml_dump(rules, os.path.join(dstdir, "rules.yaml"))
    _json_dump(evidence, os.path.join(dstdir, "evidence.json"))
    with open(os.path.join(dstdir, "SKILL.md"), "w", encoding="utf-8") as f:
        f.write(build_skill_md(profile))


def build_skill_md(profile):
    tags = ", ".join(profile.get("skills", [])[:8])
    return (
        "---\n"
        "name: scoutica\n"
        "description: AI-readable professional profile with automated opportunity filtering\n"
        "metadata:\n"
        "  tags: %s\n"
        "  version: %s\n"
        "  source: ai-job-search import\n"
        "---\n\n"
        "# Scoutica Skill Card\n\n"
        "AI-readable professional profile imported from an ai-job-search fork.\n\n"
        "## Data Files\n"
        "- [profile.json](./profile.json)\n"
        "- [rules.yaml](./rules.yaml)\n"
        "- [evidence.json](./evidence.json)\n\n"
        "## Important Rules\n"
        "1. Never fabricate capabilities. Only report what is in `profile.json`.\n"
        "2. Respect the Rules of Engagement. If `rules.yaml` says REJECT, do not override.\n"
        "3. Candidate sovereignty. This profile serves the candidate, not the employer.\n"
        % (tags, SCHEMA_VERSION)
    )


def main():
    ap = argparse.ArgumentParser(prog="scoutica import aijs", add_help=True)
    ap.add_argument("--src", required=True)
    ap.add_argument("--to", required=True)
    ap.add_argument("--salary-floor-eur", type=int, default=None)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--tty", type=int, default=0)
    args = ap.parse_args()

    src, target = args.src, args.to
    if not os.path.isdir(src):
        print("  ❌ source directory not found: %s" % src, file=sys.stderr)
        return 1
    if args.salary_floor_eur is not None and args.salary_floor_eur < 0:
        print("  ❌ --salary-floor-eur must be a non-negative integer", file=sys.stderr)
        return 1

    profile_text = read(os.path.join(src, JAA, "01-candidate-profile.md"))
    claude_text = read(os.path.join(src, "CLAUDE.md"))
    eval_text = read(os.path.join(src, JAA, "04-job-evaluation.md"))
    search_text = read(os.path.join(src, SCR, "search-queries.md"))
    if not profile_text and not claude_text:
        print("  ❌ no ai-job-search profile found (need %s or CLAUDE.md)" % os.path.join(JAA, "01-candidate-profile.md"),
              file=sys.stderr)
        return 1

    ident = parse_identity(profile_text or claude_text)
    roles = parse_roles(profile_text or claude_text)
    years = compute_years(roles)
    skills = parse_skills(profile_text, claude_text)
    domains = parse_domains(profile_text, claude_text)

    # title: LinkedIn headline (rare) else most recent role title
    title = None
    if ident.get("linkedin headline") and not is_placeholder(ident["linkedin headline"]):
        title = ident["linkedin headline"]
    elif roles and roles[0]["title"] and not is_placeholder(roles[0]["title"]):
        title = roles[0]["title"]

    # ── required-field placeholder/missing gate → exit 2 (nothing written) ──
    missing = []
    if not title:
        missing.append("title (Identity LinkedIn headline / most recent role)")
    if not skills:
        missing.append("skills (Technical Skills → Programming & ML)")
    if not domains:
        missing.append("primary_domains (Technical Skills → Domain Expertise)")
    if missing:
        print("  ❌ import aborted — required fields are unfilled placeholders:", file=sys.stderr)
        for m in missing:
            print("     • %s" % m, file=sys.stderr)
        print("  Fill these in the ai-job-search fork (run /setup) and re-import.", file=sys.stderr)
        return 2

    # ── seniority (required enum) → exit 3 if unresolvable in non-TTY ──
    seniority = infer_seniority(roles, years)
    if not seniority:
        if args.tty:
            try:
                ans = input("  Seniority [entry/junior/mid/senior/lead/manager/director/executive]: ").strip().lower()
            except EOFError:
                ans = ""
            if ans in ("entry", "junior", "mid", "senior", "lead", "manager", "director", "executive"):
                seniority = ans
        if not seniority:
            print("  ❌ import aborted — could not resolve required enum 'seniority' from the source", file=sys.stderr)
            print("     (no seniority keyword in role titles and no datable experience to infer from).", file=sys.stderr)
            return 3

    # ── build profile.json ──
    profile = {"schema_version": SCHEMA_VERSION, "title": title, "seniority": seniority,
               "skills": skills, "primary_domains": domains}
    if ident.get("name") and not is_placeholder(ident["name"]):
        profile["name"] = ident["name"]
    if years is not None:
        profile["years_experience"] = years
    avail = map_availability(ident)
    if avail:
        profile["availability"] = avail
    tools = parse_tools(profile_text, claude_text)
    if tools:
        profile["tools_and_platforms"] = tools
    certs = parse_certs(claude_text)
    if certs:
        profile["certifications_and_licenses"] = certs
    specs = parse_specializations(profile_text)
    if specs:
        profile["specializations"] = specs
    langs = parse_languages(ident)
    if langs:
        profile["spoken_languages"] = langs
    edu = parse_education(profile_text)
    if edu:
        profile["education"] = edu
    summary = parse_summary(claude_text)
    if summary:
        profile["summary"] = summary

    # ── build rules.yaml ──
    dealbreakers = "\n".join(section(eval_text, "Deal-breakers") or section(eval_text, "Deal-Breakers"))
    rules = {
        "schema_version": SCHEMA_VERSION,
        "engagement": {"allowed_types": parse_engagement_types(ident, dealbreakers)},
        "remote": {"policy": map_remote_policy(ident, dealbreakers)},
        "filters": {},
        "privacy": {
            "zone_1_public": ["title", "seniority", "primary_domains", "availability"],
            "zone_2_paid": ["full_profile", "evidence", "experience_details"],
            "zone_3_private": ["name", "email", "phone", "exact_salary"],
        },
    }
    if args.salary_floor_eur is not None:
        # roe.schema minimum_base_eur allows only these keys (additionalProperties:false) — never internship
        _COMP_KEYS = ("permanent", "contract", "fractional", "advisory")
        floors = {t: args.salary_floor_eur for t in rules["engagement"]["allowed_types"] if t in _COMP_KEYS}
        if floors:
            rules["engagement"]["compensation"] = {"minimum_base_eur": floors}
        else:
            warn("engagement.compensation", "salary floor given but no compensable engagement type; omitted")
    blocked = parse_blocked_industries(dealbreakers)
    if blocked:
        rules["filters"]["blocked_industries"] = blocked
    stack = parse_stack_keywords(search_text, skills)
    if stack:
        rules["filters"]["stack_keywords"] = {"preferred": stack}

    # ── build evidence.json ──
    evidence = {"schema_version": SCHEMA_VERSION, "items": parse_evidence(profile_text, ident, skills, domains)}

    # ── target refusal checks (exit 4) ──
    # Refuse a symlinked target, a symlinked immediate parent (symlink-escape via the dir we write
    # into), or any symlinked card file. NB: we deliberately do NOT walk to the filesystem root —
    # system symlinks (/tmp→/private/tmp, /var→/private/var on macOS) are legitimate and would break
    # normal use; a symlink deeper in a user-supplied path is the user's own choice.
    abs_target = os.path.abspath(target)
    parent = os.path.dirname(abs_target) or "."
    if os.path.islink(target):
        print("  ❌ refusing: target is a symlink: %s" % target, file=sys.stderr)
        return 4
    if os.path.islink(parent):
        print("  ❌ refusing: target's parent directory is a symlink: %s" % parent, file=sys.stderr)
        return 4
    if os.path.isdir(target):
        existing = [f for f in os.listdir(target) if not f.startswith(".")]
        if existing and not args.force:
            print("  ❌ refusing: target directory is not empty (use --force): %s" % target, file=sys.stderr)
            return 4
    for f in CARD_FILES:
        fp = os.path.join(target, f)
        if os.path.islink(fp):
            print("  ❌ refusing to overwrite symlink: %s" % fp, file=sys.stderr)
            return 4

    # ── emit: build the whole card in a temp dir, then commit ──
    # Accepted residuals (proportionate for a non-privileged, user-invoked, offline tool writing to a
    # user-chosen target — same symlink-safety bar as the identity-key writer elsewhere in this repo):
    #   • TOCTOU: `parent` is islink-checked above, then used below; an attacker able to swap `parent`
    #     for a symlink in that window (which requires pre-existing write access to parent's parent —
    #     i.e. they could already attack the target directly) could redirect the write. Closing this
    #     fully needs openat/O_NOFOLLOW fd-relative operations; out of scope here.
    #   • The --force path replaces four files individually; a crash mid-way can leave a mixed card.
    #     POSIX has no atomic multi-file rename; the fresh-target path below IS fully atomic.
    if not os.path.exists(target):
        # fresh target → atomic whole-card commit: one directory rename, so a crash never leaves a
        # partial or mixed card. (POSIX has no atomic multi-file rename for the --force case below.)
        os.makedirs(parent, exist_ok=True)
        tmp = tempfile.mkdtemp(prefix=".import_aijs.", dir=parent)
        try:
            _write_card(tmp, profile, rules, evidence)
            os.rename(tmp, target)
        except BaseException:
            shutil.rmtree(tmp, ignore_errors=True)
            raise
    else:
        # existing (--force) target → stage in a temp subdir, then replace file-by-file
        tmp = tempfile.mkdtemp(prefix=".import_aijs.", dir=target)
        try:
            _write_card(tmp, profile, rules, evidence)
            for f in CARD_FILES:
                os.replace(os.path.join(tmp, f), os.path.join(target, f))
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    # ── report: field NAMES + counts only, never PII values ──
    print("  ✅ Imported ai-job-search fork → Scoutica Skill Card in %s/" % target)
    print("     profile.json  (%d fields)" % len(profile))
    print("     rules.yaml    (%d engagement type(s), %d blocked industr(y/ies))"
          % (len(rules["engagement"]["allowed_types"]), len(rules["filters"].get("blocked_industries", []))))
    print("     evidence.json (%d item(s))" % len(evidence["items"]))
    print("     SKILL.md")
    if _WARNINGS:
        print("  ⚠ notes:")
        for field, why in _WARNINGS:
            print("     • %s: %s" % (field, why))
    print("  ℹ behavioral profile, writing style, and interview stories were NOT imported (data minimization).")
    print("  Next: review the card, then `scoutica validate` and `scoutica publish` when ready.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
