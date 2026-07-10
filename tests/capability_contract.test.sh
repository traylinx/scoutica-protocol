#!/bin/sh
# Phase 0 gate: canonical support contract stays aligned with shipped entrypoints.

. "${TESTLIB:-$(CDPATH= cd -- "$(dirname -- "$0")/lib" && pwd)}/assert.sh"

t_begin - "canonical CLI capability/support contract"
assert_exit 0 python3 "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/capability_contract_test.py"
t_end

[ "$_A_FAILED" -eq 0 ]
