#!/bin/zsh

if (( $# != 2 )); then
    print -u2 "Usage: ${0:t} <input_file> <output_file>"
    exit 2
fi

input_file=$1
output_file=$2

if [[ ! -r "$input_file" ]]; then
    print -u2 "${0:t}: cannot read input file: $input_file"
    exit 1
fi

for dependency in cidr python3; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        print -u2 "${0:t}: required command not found: $dependency"
        exit 1
    fi
done

# Build the complete result next to the destination, then rename it into place.
# A bad input line must never leave a partial or error-filled output file.
tmpfile=$(mktemp -- "${output_file}.tmp.XXXXXX") || exit 1

cleanup() {
    [[ -e "$tmpfile" ]] && rm -f -- "$tmpfile"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

line_number=0

while IFS= read -r line || [[ -n "$line" ]]; do
    (( line_number++ ))
    line=${line%$'\r'}

    # Empty lines are harmless separators in client-provided lists.
    [[ -z "${line//[[:space:]]/}" ]] && continue

    parser_output=$(cidr -s -- "$line" 2>&1)
    parser_status=$?

    if (( parser_status != 0 )) || [[ -z "${parser_output//[[:space:]]/}" ]]; then
        print -u2 "${0:t}: line $line_number could not be normalized: $line"
        [[ -n "$parser_output" ]] && print -u2 "${0:t}: cidr returned: $parser_output"
        exit 1
    fi

    # cidr unfortunately exits 0 for inputs it cannot parse and prints messages
    # such as "invalid IPNetwork ..." on stdout. Validate every comma-separated
    # value independently before allowing it into the result.
    validated_output=$(python3 -c '
import ipaddress
import sys

values = [value.strip() for value in sys.argv[1].split(",")]

try:
    if not values or any(not value for value in values):
        raise ValueError("empty value in cidr output")
    networks = [ipaddress.ip_network(value, strict=True) for value in values]
except ValueError as error:
    print(error, file=sys.stderr)
    raise SystemExit(1)

for network in networks:
    print(network.with_prefixlen)
' "$parser_output" 2>&1)

    if (( $? != 0 )); then
        print -u2 "${0:t}: line $line_number is invalid: $line"
        print -u2 "${0:t}: cidr returned: $parser_output"
        print -u2 "${0:t}: validation failed: $validated_output"
        exit 1
    fi

    print -r -- "$validated_output" >> "$tmpfile"
done < "$input_file"

if ! sort -u -o "$tmpfile" -- "$tmpfile"; then
    print -u2 "${0:t}: failed to sort normalized addresses"
    exit 1
fi

# Match normal shell redirection permissions for new files, and retain the
# destination's permissions when replacing an existing file.
if [[ -e "$output_file" ]]; then
    chmod --reference="$output_file" "$tmpfile" || exit 1
else
    chmod '=rw' "$tmpfile" || exit 1
fi

mv -f -- "$tmpfile" "$output_file"
