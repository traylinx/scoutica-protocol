#!/bin/sh
# Phase 1 gate: tracked Pydantic models accept and reject the authoritative schema corpus.

. "${TESTLIB:-$(CDPATH= cd -- "$(dirname -- "$0")/lib" && pwd)}/assert.sh"

_test_python=${SCOUTICA_TEST_PYTHON:-python3}

t_begin - "candidate Pydantic models match authoritative JSON Schemas"
if ! "$_test_python" "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/model_schema_parity_test.py"; then
    t_fail "model/schema parity corpus failed"
fi
t_end

[ "$_A_FAILED" -eq 0 ]
