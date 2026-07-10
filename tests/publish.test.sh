#!/bin/sh
# Phase 2 publication integrity regressions for the POSIX candidate and employer paths.

. "$TESTLIB/assert.sh"
. "$TESTLIB/fixtures.sh"

fixture_isolated_env "$WORK/publish-contracts"
trap 'fixture_cleanup' EXIT INT TERM

make_candidate_repo() {
    _pub_root=$1
    rm -rf "$_pub_root"
    python3 - "$_pub_root" <<'PY'
import json
import sys
from pathlib import Path

import yaml

root = Path(sys.argv[1])
(root / "rules").mkdir(parents=True)

def write_json(path, document):
    with path.open("w", encoding="utf-8") as handle:
        json.dump(document, handle, indent=2)
        handle.write("\n")

write_json(
    root / "profile.json",
    {
        "schema_version": "0.1.0",
        "name": "Alice Developer",
        "title": "Backend Engineer",
        "seniority": "senior",
        "primary_domains": ["Software Engineering"],
        "skills": ["Python"],
    },
)
(root / "rules.yaml").write_text(
    yaml.safe_dump(
        {
            "schema_version": "0.1.0",
            "engagement": {"allowed_types": ["contract"]},
            "remote": {"policy": "remote_only"},
            "filters": {},
            "privacy": {"zone_1_public": [], "zone_2_paid": [], "zone_3_private": []},
        },
        sort_keys=False,
    ),
    encoding="utf-8",
)
write_json(root / "evidence.json", {"schema_version": "0.1.0", "items": []})
(root / "SKILL.md").write_text(
    "---\nname: scoutica\ndescription: Mock candidate card\n---\n\n# Mock card\n",
    encoding="utf-8",
)
(root / "rules" / "evaluate-fit.md").write_text("# Evaluate fit\n", encoding="utf-8")
PY
    git -C "$_pub_root" init -q
    git -C "$_pub_root" add profile.json rules.yaml evidence.json SKILL.md rules/evaluate-fit.md
    git -C "$_pub_root" commit -q -m "Initial candidate card"
    git -C "$_pub_root" branch -M main
}

make_employer_repo() {
    _pub_root=$1
    rm -rf "$_pub_root"
    python3 - "$_pub_root" <<'PY'
import json
import sys
from pathlib import Path

import yaml

root = Path(sys.argv[1])
(root / "roles").mkdir(parents=True)

def write_json(path, document):
    with path.open("w", encoding="utf-8") as handle:
        json.dump(document, handle, indent=2)
        handle.write("\n")

write_json(
    root / "recruiter_profile.json",
    {
        "scoutica_version": "0.4.0",
        "entity_type": "in-house",
        "organization": {"name": "Example Organization", "domain": "example.test"},
        "engagement_types": ["contract"],
    },
)
(root / "hiring_rules.yaml").write_text(
    yaml.safe_dump({"commitments": {}}, sort_keys=False), encoding="utf-8"
)
write_json(
    root / "roles" / "backend-engineer.json",
    {
        "scoutica_version": "0.4.0",
        "job_id": "req_abcdef",
        "title": "Backend Engineer",
        "status": "active",
        "requirements": {"hard_skills": ["Python"]},
        "location": {"type": "remote"},
    },
)
PY
    git -C "$_pub_root" init -q
    git -C "$_pub_root" add recruiter_profile.json hiring_rules.yaml roles/backend-engineer.json
    git -C "$_pub_root" commit -q -m "Initial employer card"
    git -C "$_pub_root" branch -M main
}

attach_accepting_remote() {
    _pub_repo=$1
    _pub_remote=$2
    fixture_make_git_remote "$_pub_remote" >/dev/null
    git -C "$_pub_repo" remote add origin "$_pub_remote"
    git -C "$_pub_repo" push -q -u origin main
}

install_rejecting_hook() {
    _pub_remote=$1
    printf '%s\n' '#!/bin/sh' 'echo "fixture: push rejected" >&2' 'exit 1' \
        > "$_pub_remote/hooks/pre-receive"
    chmod +x "$_pub_remote/hooks/pre-receive"
}

install_rejecting_commit_hook() {
    _pub_repo=$1
    printf '%s\n' '#!/bin/sh' 'echo "fixture: commit rejected" >&2' 'exit 1' \
        > "$_pub_repo/.git/hooks/pre-commit"
    chmod +x "$_pub_repo/.git/hooks/pre-commit"
}

modify_candidate_card() {
    python3 - "$1/profile.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    document = json.load(handle)
document["summary"] = "Updated mock candidate summary."
with open(path, "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY
}

modify_employer_card() {
    python3 - "$1/recruiter_profile.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    document = json.load(handle)
document["organization"]["description"] = "Updated mock organization."
with open(path, "w", encoding="utf-8") as handle:
    json.dump(document, handle, indent=2)
    handle.write("\n")
PY
}

stage_unrelated_paths() {
    _pub_repo=$1
    python3 - "$_pub_repo" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
(root / ".env").write_text("MOCK_SECRET=not-a-real-secret\n", encoding="utf-8")
(root / "unrelated.py").write_text('print("unrelated mock source")\n', encoding="utf-8")
PY
    mkdir -p "$_pub_repo/rules"
    printf '%s\n' 'Mock private note that is not a protocol rule.' > "$_pub_repo/rules/private-notes.md"
    printf '%s\n' '%PDF-1.4 mock private document' > "$_pub_repo/private-cv.pdf"
    git -C "$_pub_repo" add .env unrelated.py rules/private-notes.md private-cv.pdf
}

run_candidate_publish() {
    _pub_output=$1
    _pub_repo=$2
    "$SCOUTICA" publish "$_pub_repo" >"$_pub_output" 2>&1
    PUB_RC=$?
}

run_employer_publish() {
    _pub_output=$1
    _pub_repo=$2
    "$SCOUTICA" org publish "$_pub_repo" >"$_pub_output" 2>&1
    PUB_RC=$?
}

assert_publish_refusal_preserves_index() {
    _pub_kind=$1
    _pub_repo=$2
    _pub_remote=$3
    _pub_output=$4
    _pub_before=$5
    _pub_after=$6

    cp "$_pub_repo/.git/index" "$_pub_before"
    _pub_head_before=$(git -C "$_pub_repo" rev-parse HEAD)
    _pub_remote_before=$(git --git-dir="$_pub_remote" rev-parse refs/heads/main)
    rm -f "$SCOUTICA_HOME/registry.json"

    if [ "$_pub_kind" = candidate ]; then
        run_candidate_publish "$_pub_output" "$_pub_repo"
    else
        run_employer_publish "$_pub_output" "$_pub_repo"
    fi
    assert_ne 0 "$PUB_RC" "publish must refuse a noncanonical pre-existing index"
    cp "$_pub_repo/.git/index" "$_pub_after"
    assert_file_eq "$_pub_before" "$_pub_after" "refusal must preserve .git/index byte-for-byte"
    assert_eq "$_pub_head_before" "$(git -C "$_pub_repo" rev-parse HEAD)" "refusal must create no commit"
    assert_eq "$_pub_remote_before" "$(git --git-dir="$_pub_remote" rev-parse refs/heads/main)" \
        "refusal must not push"
    assert_no_grep 'Successfully published' "$_pub_output" "refusal must not print publish success"
    assert_not_exists "$SCOUTICA_HOME/registry.json" "refusal must not record a publish event"
}

t_begin F-01 "candidate publish refuses unrelated staged files without changing index, commit, or remote"
candidate_refusal="$WORK/candidate-refusal"
candidate_refusal_remote="$WORK/candidate-refusal.git"
make_candidate_repo "$candidate_refusal"
attach_accepting_remote "$candidate_refusal" "$candidate_refusal_remote"
modify_candidate_card "$candidate_refusal"
stage_unrelated_paths "$candidate_refusal"
assert_publish_refusal_preserves_index candidate "$candidate_refusal" "$candidate_refusal_remote" \
    "$WORK/candidate-refusal.out" "$WORK/candidate-refusal.before" "$WORK/candidate-refusal.after"
t_end

t_begin F-01 "employer publish refuses unrelated staged files without changing index, commit, or remote"
employer_refusal="$WORK/employer-refusal"
employer_refusal_remote="$WORK/employer-refusal.git"
make_employer_repo "$employer_refusal"
attach_accepting_remote "$employer_refusal" "$employer_refusal_remote"
modify_employer_card "$employer_refusal"
stage_unrelated_paths "$employer_refusal"
assert_publish_refusal_preserves_index employer "$employer_refusal" "$employer_refusal_remote" \
    "$WORK/employer-refusal.out" "$WORK/employer-refusal.before" "$WORK/employer-refusal.after"
t_end

t_begin F-01 "candidate canonical-only publish commits and pushes to a local bare remote"
candidate_success="$WORK/candidate-success"
candidate_success_remote="$WORK/candidate-success.git"
make_candidate_repo "$candidate_success"
attach_accepting_remote "$candidate_success" "$candidate_success_remote"
candidate_success_before=$(git -C "$candidate_success" rev-parse HEAD)
modify_candidate_card "$candidate_success"
rm -f "$SCOUTICA_HOME/registry.json"
run_candidate_publish "$WORK/candidate-success.out" "$candidate_success"
assert_eq 0 "$PUB_RC" "canonical candidate publish must succeed"
candidate_success_after=$(git -C "$candidate_success" rev-parse HEAD)
assert_ne "$candidate_success_before" "$candidate_success_after" "canonical change must create a commit"
assert_eq "$candidate_success_after" \
    "$(git --git-dir="$candidate_success_remote" rev-parse refs/heads/main)" "candidate commit must reach remote"
assert_exit 0 git -C "$candidate_success" diff --cached --quiet
assert_grep 'Successfully published' "$WORK/candidate-success.out"
assert_exists "$SCOUTICA_HOME/registry.json" "successful candidate publish records its event"
t_end

t_begin F-01 "employer canonical-only publish commits and pushes to a local bare remote"
employer_success="$WORK/employer-success"
employer_success_remote="$WORK/employer-success.git"
make_employer_repo "$employer_success"
attach_accepting_remote "$employer_success" "$employer_success_remote"
employer_success_before=$(git -C "$employer_success" rev-parse HEAD)
modify_employer_card "$employer_success"
run_employer_publish "$WORK/employer-success.out" "$employer_success"
assert_eq 0 "$PUB_RC" "canonical employer publish must succeed"
employer_success_after=$(git -C "$employer_success" rev-parse HEAD)
assert_ne "$employer_success_before" "$employer_success_after" "canonical change must create a commit"
assert_eq "$employer_success_after" \
    "$(git --git-dir="$employer_success_remote" rev-parse refs/heads/main)" "employer commit must reach remote"
assert_exit 0 git -C "$employer_success" diff --cached --quiet
assert_grep 'Successfully published' "$WORK/employer-success.out"
t_end

assert_failed_commit() {
    _pub_kind=$1
    _pub_repo=$2
    _pub_remote=$3
    _pub_output=$4
    _pub_head_before=$(git -C "$_pub_repo" rev-parse HEAD)
    _pub_remote_before=$(git --git-dir="$_pub_remote" rev-parse refs/heads/main)
    rm -f "$SCOUTICA_HOME/registry.json"
    install_rejecting_commit_hook "$_pub_repo"

    if [ "$_pub_kind" = candidate ]; then
        run_candidate_publish "$_pub_output" "$_pub_repo"
    else
        run_employer_publish "$_pub_output" "$_pub_repo"
    fi
    assert_ne 0 "$PUB_RC" "rejected commit must return nonzero"
    assert_eq "$_pub_head_before" "$(git -C "$_pub_repo" rev-parse HEAD)" \
        "rejected commit must not advance HEAD"
    assert_eq "$_pub_remote_before" "$(git --git-dir="$_pub_remote" rev-parse refs/heads/main)" \
        "rejected commit must not push"
    assert_grep 'Commit failed' "$_pub_output" "rejected commit must be explicit"
    assert_no_grep 'Successfully published' "$_pub_output" "rejected commit must not print success"
    assert_not_exists "$SCOUTICA_HOME/registry.json" "rejected commit must not record publish success"
}

t_begin F-14 "candidate rejected commit is nonzero with no false success"
candidate_commit_reject="$WORK/candidate-commit-reject"
candidate_commit_reject_remote="$WORK/candidate-commit-reject.git"
make_candidate_repo "$candidate_commit_reject"
attach_accepting_remote "$candidate_commit_reject" "$candidate_commit_reject_remote"
modify_candidate_card "$candidate_commit_reject"
assert_failed_commit candidate "$candidate_commit_reject" "$candidate_commit_reject_remote" \
    "$WORK/candidate-commit-reject.out"
t_end

t_begin F-14 "employer rejected commit is nonzero with no false success"
employer_commit_reject="$WORK/employer-commit-reject"
employer_commit_reject_remote="$WORK/employer-commit-reject.git"
make_employer_repo "$employer_commit_reject"
attach_accepting_remote "$employer_commit_reject" "$employer_commit_reject_remote"
modify_employer_card "$employer_commit_reject"
assert_failed_commit employer "$employer_commit_reject" "$employer_commit_reject_remote" \
    "$WORK/employer-commit-reject.out"
t_end

assert_failed_push() {
    _pub_kind=$1
    _pub_repo=$2
    _pub_remote=$3
    _pub_output=$4
    _pub_remote_before=$(git --git-dir="$_pub_remote" rev-parse refs/heads/main)
    rm -f "$SCOUTICA_HOME/registry.json"
    install_rejecting_hook "$_pub_remote"

    if [ "$_pub_kind" = candidate ]; then
        run_candidate_publish "$_pub_output" "$_pub_repo"
    else
        run_employer_publish "$_pub_output" "$_pub_repo"
    fi
    assert_ne 0 "$PUB_RC" "rejected push must return nonzero"
    assert_eq "$_pub_remote_before" "$(git --git-dir="$_pub_remote" rev-parse refs/heads/main)" \
        "rejected push must not advance remote"
    assert_no_grep 'Successfully published' "$_pub_output" "rejected push must not print success"
    assert_not_exists "$SCOUTICA_HOME/registry.json" "rejected push must not record publish success"
}

t_begin F-14 "candidate rejected remote push is nonzero with no false success"
candidate_reject="$WORK/candidate-reject"
candidate_reject_remote="$WORK/candidate-reject.git"
make_candidate_repo "$candidate_reject"
attach_accepting_remote "$candidate_reject" "$candidate_reject_remote"
modify_candidate_card "$candidate_reject"
assert_failed_push candidate "$candidate_reject" "$candidate_reject_remote" "$WORK/candidate-reject.out"
t_end

t_begin F-14 "employer rejected remote push is nonzero with no false success"
employer_reject="$WORK/employer-reject"
employer_reject_remote="$WORK/employer-reject.git"
make_employer_repo "$employer_reject"
attach_accepting_remote "$employer_reject" "$employer_reject_remote"
modify_employer_card "$employer_reject"
assert_failed_push employer "$employer_reject" "$employer_reject_remote" "$WORK/employer-reject.out"
t_end

assert_missing_origin() {
    _pub_kind=$1
    _pub_repo=$2
    _pub_output=$3
    rm -f "$SCOUTICA_HOME/registry.json"
    if [ "$_pub_kind" = candidate ]; then
        run_candidate_publish "$_pub_output" "$_pub_repo"
    else
        run_employer_publish "$_pub_output" "$_pub_repo"
    fi
    assert_ne 0 "$PUB_RC" "missing origin must return nonzero"
    assert_no_grep 'Successfully published' "$_pub_output" "missing origin must not print success"
    assert_not_exists "$SCOUTICA_HOME/registry.json" "missing origin must not record publish success"
}

t_begin F-14 "candidate publish without origin is nonzero with no false success"
candidate_no_origin="$WORK/candidate-no-origin"
make_candidate_repo "$candidate_no_origin"
modify_candidate_card "$candidate_no_origin"
assert_missing_origin candidate "$candidate_no_origin" "$WORK/candidate-no-origin.out"
t_end

t_begin F-14 "employer publish without origin is nonzero with no false success"
employer_no_origin="$WORK/employer-no-origin"
make_employer_repo "$employer_no_origin"
modify_employer_card "$employer_no_origin"
assert_missing_origin employer "$employer_no_origin" "$WORK/employer-no-origin.out"
t_end

fixture_cleanup
