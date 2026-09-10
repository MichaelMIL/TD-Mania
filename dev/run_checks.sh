#!/bin/sh
# Runs every harness and fails on any engine error.
#
#   dev/run_checks.sh
#
# Each harness prints its own PASS/FAIL lines; this wrapper additionally
# greps stderr, because a runtime error in Godot is a log line, not a
# non-zero exit code.
set -u
cd "$(dirname "$0")/.." || exit 1
out=$(mktemp -d)
status=0

run() {
	name=$1
	shift
	printf '%-10s' "$name"
	if ! godot --headless "$@" > "$out/$name.log" 2>&1; then
		echo "CRASHED (see $out/$name.log)"
		status=1
		return
	fi
	fails=$(grep -c '^FAIL' "$out/$name.log")
	errors=$(grep -cE 'SCRIPT ERROR|Parse Error|Compile Error' "$out/$name.log")
	passes=$(grep -c '^PASS' "$out/$name.log")
	echo "$passes passed, $fails failed, $errors engine errors"
	[ "$fails" = "0" ] && [ "$errors" = "0" ] || status=1
}

run verify --quit-after 900 dev/dev_verify.tscn
run air    --quit-after 6000 dev/dev_air.tscn
run smoke  --fixed-fps 60 --quit-after 20000 dev/dev_smoke.tscn

# The balance report plays every map several times over, which takes
# minutes rather than seconds. Opt in with: dev/run_checks.sh --full
if [ "${1:-}" = "--full" ]; then
	run report --fixed-fps 5 --quit-after 900000 dev/dev_report.tscn -- --runs 2
	grep '^\[REPORT\]' "$out/report.log"
fi

if [ "$status" = "0" ]; then
	echo "all checks passed"
else
	echo "FAILURES — logs in $out"
fi
exit $status
