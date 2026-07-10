#!/bin/sh
# Phase 4: one bounded SSRF-safe registry/card fetch boundary.

. "$TESTLIB/assert.sh"
. "$TESTLIB/fixtures.sh"

unit_out=$(python3 - "$REPO_ROOT/tools/safe_fetch.py" "$WORK" <<'PY'
import importlib.util
import json
import pathlib
import subprocess
import signal
import sys
import time
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location("safe_fetch", sys.argv[1])
sf = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = sf
spec.loader.exec_module(sf)
work = pathlib.Path(sys.argv[2])

def flag(name, value):
    print(f"{name}={1 if value else 0}")

def blocked(url, resolver=lambda host, port, timeout: ["8.8.8.8"]):
    try:
        sf.validate_target(url, resolver=resolver)
        return False
    except sf.FetchError as exc:
        return exc.exit_code == sf.EXIT_POLICY

blocked_urls = {
    "HTTP": "http://example.test/index.json",
    "FILE": "file:///etc/passwd",
    "CREDENTIALS": "https://alice:secret@example.test/index.json",
    "TRAILING_DOT": "https://example.test./index.json",
    "ZERO_PORT": "https://example.test:0/index.json",
    "SPACE": "https://example.test/a b",
    "CONTROL": "https://example.test/a\n",
    "LOCALHOST": "https://localhost/index.json",
    "LOOPBACK4": "https://127.0.0.1/index.json",
    "LOOPBACK6": "https://[::1]/index.json",
    "RFC1918": "https://10.0.0.1/index.json",
    "LINK_LOCAL": "https://169.254.169.254/latest/meta-data/",
    "UNSPECIFIED": "https://0.0.0.0/index.json",
    "MULTICAST": "https://224.0.0.1/index.json",
    "RESERVED": "https://203.0.113.1/index.json",
}
for name, url in blocked_urls.items():
    flag("URL_" + name, blocked(url))
flag("URL_PUBLIC", not blocked("https://8.8.8.8/index.json"))
flag("URL_PUBLIC6", not blocked("https://[2606:4700:4700::1111]/index.json"))
flag(
    "DNS_MIXED",
    blocked("https://mixed.example.test/index.json", lambda *args: ["8.8.8.8", "127.0.0.1"]),
)

original_getaddrinfo = sf.socket.getaddrinfo
sf.socket.getaddrinfo = lambda *args, **kwargs: (time.sleep(0.05), [])[1]
try:
    try:
        sf._resolve_with_timeout("slow.example", 443, 0.001)
        dns_timeout = False
    except sf.FetchError as exc:
        dns_timeout = exc.category == "dns_policy"
finally:
    sf.socket.getaddrinfo = original_getaddrinfo
flag("DNS_TIMEOUT", dns_timeout)

valid_registry = json.dumps({"entries": [{"name": "Alice Developer"}]}).encode()
payload_cases = [
    ("PAYLOAD_VALID", valid_registry, "registry", "application/json", True),
    ("PAYLOAD_TEXT_PLAIN", b"rules: true\n", "text", "text/plain", True),
    ("PAYLOAD_EXACT_LIMIT", b"x" * sf.MAX_BODY_BYTES, "text", "text/plain", True),
    ("PAYLOAD_OVER_LIMIT", b"x" * (sf.MAX_BODY_BYTES + 1), "text", "text/plain", False),
    ("PAYLOAD_BAD_TYPE", valid_registry, "registry", "text/html", False),
    ("PAYLOAD_BAD_UTF8", b"\xff", "text", "text/plain", False),
    ("PAYLOAD_BAD_JSON", b"{", "json", "application/json", False),
    ("PAYLOAD_LIST_ROOT", b"[]", "json", "application/json", False),
    ("PAYLOAD_MISSING_ENTRIES", b"{}", "registry", "application/json", False),
    ("PAYLOAD_NONOBJECT_ENTRY", b'{"entries":[1]}', "registry", "application/json", False),
]
for name, data, expect, content_type, expected in payload_cases:
    try:
        sf.validate_payload(data, expect, content_type)
        actual = True
    except sf.FetchError:
        actual = False
    flag(name, actual == expected)

target = sf.validate_target("https://registry.example.test/index.json", lambda *args: ["8.8.8.8"])
captured = {}

def runner_for(status=200, body=valid_registry, content_type="application/json", headers=None, rc=0):
    headers = headers or {}
    def run(command, **kwargs):
        captured["command"] = command
        captured["env"] = kwargs["env"]
        captured["preexec_fn"] = kwargs.get("preexec_fn")
        pathlib.Path(command[command.index("--output") + 1]).write_bytes(body)
        header_lines = [f"HTTP/1.1 {status} fixture", f"Content-Type: {content_type}"]
        header_lines.extend(f"{key}: {value}" for key, value in headers.items())
        pathlib.Path(command[command.index("--dump-header") + 1]).write_text(
            "\r\n".join(header_lines) + "\r\n\r\n", encoding="iso-8859-1"
        )
        return SimpleNamespace(
            returncode=rc,
            stdout=f"{status}\n{content_type}\n{len(body)}",
            stderr="fixture",
        )
    return run

output = work / "fetched.json"
sf.fetch(target, "registry", output, runner=runner_for())
flag("FETCH_VALID", output.read_bytes() == valid_registry)
command = captured["command"]
flag("FETCH_PINNED", "--resolve" in command and "registry.example.test:443:8.8.8.8" in command)
flag("FETCH_LIMITS", "--connect-timeout" in command and "--max-time" in command and "--max-filesize" in command)
flag("FETCH_NO_REDIRECT", "--location" not in command and "-L" not in command)
flag("FETCH_GLOBOFF", "--globoff" in command)
flag("FETCH_NO_PROXY", "--noproxy" in command and not any("proxy" in key.lower() for key in captured["env"]))
flag("FETCH_NO_CURLRC", command[1] == "-q")
flag("FETCH_RLIMIT", callable(captured.get("preexec_fn")))

error_cases = [
    ("FETCH_REDIRECT", runner_for(status=302), sf.EXIT_RESPONSE, False),
    ("FETCH_NOT_FOUND", runner_for(status=404), sf.EXIT_NOT_FOUND, True),
    ("FETCH_COMPRESSED", runner_for(headers={"Content-Encoding": "gzip"}), sf.EXIT_RESPONSE, False),
    ("FETCH_DECLARED_OVERSIZE", runner_for(headers={"Content-Length": str(sf.MAX_BODY_BYTES + 1)}), sf.EXIT_RESPONSE, False),
    ("FETCH_CURL_OVERSIZE", runner_for(rc=63), sf.EXIT_RESPONSE, False),
    ("FETCH_HEADER_OVERSIZE", runner_for(rc=-signal.SIGXFSZ), sf.EXIT_RESPONSE, False),
    ("FETCH_CURL_BAD_URL", runner_for(rc=3), sf.EXIT_POLICY, False),
    ("FETCH_CHUNKED_OVERSIZE", runner_for(body=b"x" * (sf.MAX_BODY_BYTES + 1)), sf.EXIT_RESPONSE, False),
    ("FETCH_TRANSPORT", runner_for(rc=7), sf.EXIT_TRANSPORT, False),
]
for name, runner, expected_code, allow_not_found in error_cases:
    try:
        sf.fetch(target, "registry", work / (name + ".json"), allow_not_found, runner=runner)
        actual = None
    except sf.FetchError as exc:
        actual = exc.exit_code
    flag(name, actual == expected_code)
PY
)

t_begin F-05 "safe fetch rejects unsafe URL/DNS classes and pins only public HTTPS"
for key in HTTP FILE CREDENTIALS TRAILING_DOT ZERO_PORT SPACE CONTROL LOCALHOST LOOPBACK4 LOOPBACK6 RFC1918 LINK_LOCAL \
    UNSPECIFIED MULTICAST RESERVED PUBLIC PUBLIC6; do
    assert_grep "^URL_${key}=1$" "$unit_out"
done
assert_grep '^DNS_MIXED=1$' "$unit_out"
assert_grep '^DNS_TIMEOUT=1$' "$unit_out"
t_end

t_begin F-05 "safe fetch enforces media, UTF-8, JSON shape, redirects, limits, and proxy isolation"
for key in PAYLOAD_VALID PAYLOAD_TEXT_PLAIN PAYLOAD_EXACT_LIMIT PAYLOAD_OVER_LIMIT \
    PAYLOAD_BAD_TYPE PAYLOAD_BAD_UTF8 PAYLOAD_BAD_JSON PAYLOAD_LIST_ROOT \
    PAYLOAD_MISSING_ENTRIES PAYLOAD_NONOBJECT_ENTRY FETCH_VALID FETCH_PINNED FETCH_LIMITS \
    FETCH_NO_REDIRECT FETCH_GLOBOFF FETCH_NO_PROXY FETCH_NO_CURLRC FETCH_RLIMIT FETCH_REDIRECT FETCH_NOT_FOUND \
    FETCH_COMPRESSED FETCH_DECLARED_OVERSIZE FETCH_CURL_OVERSIZE FETCH_HEADER_OVERSIZE \
    FETCH_CURL_BAD_URL FETCH_CHUNKED_OVERSIZE \
    FETCH_TRANSPORT; do
    assert_grep "^${key}=1$" "$unit_out"
done
t_end

fixture_isolated_env "$WORK/jobs-security"
trap 'fixture_cleanup' EXIT INT TERM
cat > "$FIXTURE_BIN/curl" <<'SH'
#!/bin/sh
printf 'called\n' >> "${FAKE_CURL_LOG:?}"
exit 7
SH
chmod +x "$FIXTURE_BIN/curl"
FAKE_CURL_LOG="$WORK/fake-curl.log"; export FAKE_CURL_LOG
: > "$FAKE_CURL_LOG"

cat > "$WORK/local-index.json" <<'JSON'
{"entries":[{"card_url":"https://example.test/alice","name":"Alice Developer","title":"Engineer","seniority":"senior","skills":["Python"],"availability":"available"}]}
JSON

t_begin F-05 "jobs --local is bounded, pure JSON, and performs zero network calls"
"$SCOUTICA" jobs search --local "$WORK/local-index.json" \
    --registry https://127.0.0.1/private --json >"$WORK/local.out" 2>"$WORK/local.err"
assert_eq 0 "$?"
assert_exit 0 python3 -m json.tool "$WORK/local.out"
assert_grep '"count": 1' "$WORK/local.out"
assert_eq 0 "$(wc -c < "$FAKE_CURL_LOG" | tr -d ' ')"
assert_exit 0 python3 - "$WORK/local.out" <<'PY'
import pathlib, sys
data = pathlib.Path(sys.argv[1]).read_bytes()
assert data.lstrip().startswith(b"{") and b"\x1b" not in data
PY

printf '{' > "$WORK/invalid-index.json"
: > "$WORK/invalid.out"
"$SCOUTICA" jobs search --local "$WORK/invalid-index.json" --json \
    >"$WORK/invalid.out" 2>"$WORK/invalid.err"
assert_ne 0 "$?"
assert_eq 0 "$(wc -c < "$WORK/invalid.out" | tr -d ' ')"
assert_ne 0 "$(wc -c < "$WORK/invalid.err" | tr -d ' ')"
t_end

t_begin F-05 "jobs security rejections fail closed without curl or bundled fallback"
for unsafe in 'file:///etc/passwd' 'http://127.0.0.1' \
    'https://localhost' 'https://alice:secret@example.test'; do
    : > "$WORK/unsafe.out"
    "$SCOUTICA" jobs search --registry "$unsafe" --json \
        >"$WORK/unsafe.out" 2>"$WORK/unsafe.err"
    assert_ne 0 "$?" "$unsafe rejected"
    assert_eq 0 "$(wc -c < "$WORK/unsafe.out" | tr -d ' ')"
    assert_no_grep 'bundled examples' "$WORK/unsafe.err"
done
assert_eq 0 "$(wc -c < "$FAKE_CURL_LOG" | tr -d ' ')" "unsafe targets never reach curl"

"$SCOUTICA" resolve https://127.0.0.1 >"$WORK/resolve-unsafe.out" 2>"$WORK/resolve-unsafe.err"
assert_ne 0 "$?"
assert_eq 0 "$(wc -c < "$FAKE_CURL_LOG" | tr -d ' ')" "unsafe resolve never reaches curl"
t_end

installed="$WORK/installed"
install_home="$WORK/install-home"
download_bin="$WORK/download-bin"
mkdir -p "$install_home" "$download_bin"
cat > "$download_bin/curl" <<'SH'
#!/bin/sh
url=""
out=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o)
            shift
            out=${1:-}
            ;;
        -*) ;;
        *) url=$1 ;;
    esac
    shift
done
[ -n "$url" ] && [ -n "$out" ] || exit 2
relative=${url#https://raw.githubusercontent.com/traylinx/scoutica-protocol/main/}
source_file="${REPO_ROOT:?}/$relative"
[ -f "$source_file" ] || exit 22
mkdir -p "$(dirname "$out")"
cp "$source_file" "$out"
SH
chmod +x "$download_bin/curl"
HOME="$install_home" SCOUTICA_HOME="$installed" PATH="$download_bin:$PATH" \
    bash "$REPO_ROOT/install.sh" >"$WORK/install.out" 2>"$WORK/install.err"
assert_eq 0 "$?" "isolated POSIX install succeeds"
assert_exists "$installed/protocol/examples/sample_card/profile.json"
assert_exists "$installed/protocol/examples/employer_card/roles/senior-ai-architect.json"
cat > "$installed/bin/safe_fetch.py" <<'PY'
#!/usr/bin/env python3
import json, os, pathlib, sys

mode = os.environ.get("FAKE_SAFE_FETCH_MODE", "delegate")
args = sys.argv[1:]
if mode == "discovery":
    url = args[args.index("--url") + 1]
    if url.endswith("/scoutica.json"):
        output = pathlib.Path(args[args.index("--output") + 1])
        output.write_text(json.dumps({"card_url": "https://127.0.0.1/private"}), encoding="utf-8")
        raise SystemExit(0)
if mode in {"2", "3", "4", "5"}:
    raise SystemExit(int(mode))
os.execv(sys.executable, [sys.executable, os.environ["REAL_SAFE_FETCH"], *args])
PY
REAL_SAFE_FETCH="$REPO_ROOT/tools/safe_fetch.py"; export REAL_SAFE_FETCH

t_begin F-05 "jobs fallback is limited to transport failure and remains pure JSON"
FAKE_SAFE_FETCH_MODE=3 "$installed/bin/scoutica" jobs search --json \
    >"$WORK/fallback.out" 2>"$WORK/fallback.err"
assert_eq 0 "$?"
assert_exit 0 python3 -m json.tool "$WORK/fallback.out"
assert_grep 'bundled examples' "$WORK/fallback.err"

FAKE_SAFE_FETCH_MODE=4 "$installed/bin/scoutica" jobs search --json \
    >"$WORK/not-found.out" 2>"$WORK/not-found.err"
assert_eq 0 "$?"
assert_exit 0 python3 -m json.tool "$WORK/not-found.out"
assert_grep 'bundled examples' "$WORK/not-found.err"

: > "$WORK/policy.out"
FAKE_SAFE_FETCH_MODE=2 "$installed/bin/scoutica" jobs search --json \
    >"$WORK/policy.out" 2>"$WORK/policy.err"
assert_eq 2 "$?"
assert_eq 0 "$(wc -c < "$WORK/policy.out" | tr -d ' ')"
assert_no_grep 'bundled examples' "$WORK/policy.err"
t_end

t_begin F-05 "resolve revalidates a discovery card_url through the same boundary"
FAKE_SAFE_FETCH_MODE=discovery "$installed/bin/scoutica" \
    resolve https://public.example.test/card >"$WORK/discovery.out" 2>"$WORK/discovery.err"
assert_eq 2 "$?" "private discovery pointer is rejected"
assert_grep 'non-public address' "$WORK/discovery.err"
assert_eq 0 "$(wc -c < "$FAKE_CURL_LOG" | tr -d ' ')" "private discovery pointer never reaches curl"
t_end
