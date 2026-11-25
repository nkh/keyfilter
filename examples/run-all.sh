#!/bin/sh
# Run all the examples, from wherever you are.
here=$(cd "$(dirname "$0")" && pwd)
failed=0
count=0

for example in "$here"/[0-9][0-9]-*.sh
	do
	count=$((count + 1))
	name=$(basename "$example")

	if "$example" >/dev/null 2>"${TMPDIR:-/tmp}/keyfilter-example.$$"
		then
		printf 'ok      %s\n' "$name"
		else
		printf 'FAILED  %s\n' "$name"
		sed 's/^/        /' "${TMPDIR:-/tmp}/keyfilter-example.$$"
		failed=$((failed + 1))
		fi
	done

rm -f "${TMPDIR:-/tmp}/keyfilter-example.$$"

printf '%s examples, %s failed\n' "$count" "$failed"

[ "$failed" -eq 0 ]
