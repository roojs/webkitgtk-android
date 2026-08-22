#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHANGELOG_MD="${ROOT}/CHANGELOG.md"

die() {
	echo "$*" >&2
	exit 1
}

heading_date_is_iso() {
	[[ "${1:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

trim_section_body() {
	awk '
		{ lines[++n] = $0 }
		END {
			start = 1
			end = n
			while (start <= end && lines[start] ~ /^[[:space:]]*$/) {
				start++
			}
			while (end >= start && lines[end] ~ /^[[:space:]]*$/) {
				end--
			}
			for (i = start; i <= end; i++) {
				print lines[i]
			}
		}
	'
}

parse_sections_to_dir() {
	local changelog="$1"
	local outdir="$2"
	local section=-1
	local body_file=""
	local in_fence=0

	rm -rf "$outdir"
	mkdir -p "$outdir"

	while IFS= read -r line || [[ -n "$line" ]]; do
		if [[ "$line" =~ ^\`\`\` ]]; then
			in_fence=$((1 - in_fence))
			if (( section >= 0 )); then
				printf '%s\n' "$line" >> "$body_file"
			fi
			continue
		fi
		if (( in_fence )) && (( section < 0 )); then
			continue
		fi
		if [[ "$line" =~ ^##\ \[([^]]+)\](\ -\ (Unreleased|[0-9]{4}-[0-9]{2}-[0-9]{2}))?[[:space:]]*$ ]]; then
			section=$((section + 1))
			printf '%s\n' "${BASH_REMATCH[1]}" > "$outdir/$section.title"
			printf '%s\n' "${BASH_REMATCH[3]:-}" > "$outdir/$section.date"
			body_file="$outdir/$section.body"
			: > "$body_file"
		elif (( section >= 0 )); then
			printf '%s\n' "$line" >> "$body_file"
		fi
	done < "$changelog"

	if (( section < 0 )); then
		die "CHANGELOG.md: no ## [version] sections found"
	fi

	echo "$section"
}

find_section_index() {
	local outdir="$1"
	local want="$2"
	local last="$3"
	local index title

	for ((index = 0; index <= last; index++)); do
		title="$(<"$outdir/$index.title")"
		if [[ "$title" == "$want" ]]; then
			echo "$index"
			return 0
		fi
	done
	return 1
}

extract_unreleased_body() {
	awk '
		/^## \[Unreleased\][[:space:]]*$/ {
			in_section = 1
			next
		}
		/^## \[[^]]+\] - Unreleased[[:space:]]*$/ {
			in_section = 1
			next
		}
		in_section && /^## \[/ {
			exit
		}
		in_section {
			print
		}
	' "$CHANGELOG_MD" | trim_section_body
}

cmd_version() {
	local tmpdir last title date

	tmpdir="$(mktemp -d)"
	last="$(parse_sections_to_dir "$CHANGELOG_MD" "$tmpdir")"
	title="$(<"$tmpdir/0.title")"
	date="$(<"$tmpdir/0.date")"
	rm -rf "$tmpdir"

	if [[ "$title" == "Unreleased" ]]; then
		die "CHANGELOG.md: set the first heading to ## [X.Y.Z] - Unreleased before releasing"
	fi
	if heading_date_is_iso "$date"; then
		die "CHANGELOG.md: first section [${title}] is already dated ${date}; add a new ## [next] - Unreleased section first"
	fi
	printf '%s\n' "$title"
}

cmd_notes() {
	local tmpdir last title body

	tmpdir="$(mktemp -d)"
	last="$(parse_sections_to_dir "$CHANGELOG_MD" "$tmpdir")"
	title="$(<"$tmpdir/0.title")"
	body="$(trim_section_body < "$tmpdir/0.body")"
	rm -rf "$tmpdir"

	if [[ -z "$body" ]]; then
		die "CHANGELOG.md: empty notes for [${title}]"
	fi
	printf '%s\n' "$body"
}

cmd_release_notes() {
	local tag="$1"
	local output="$2"
	local version tmpdir last index body

	[[ -n "$tag" ]] || die "release-notes requires a tag"
	version="${tag#v}"

	tmpdir="$(mktemp -d)"
	last="$(parse_sections_to_dir "$CHANGELOG_MD" "$tmpdir")"
	if index="$(find_section_index "$tmpdir" "$version" "$last")"; then
		body="$(trim_section_body < "$tmpdir/$index.body")"
	else
		body="$(extract_unreleased_body)"
	fi
	rm -rf "$tmpdir"

	if [[ -z "$body" ]]; then
		die "CHANGELOG.md: no notes for ${tag}"
	fi

	mkdir -p "$(dirname "$output")"
	printf '%s\n' "$body" > "$output"
	echo "Wrote ${output}"
}

usage() {
	cat <<'EOF'
Usage:
  changelog.sh version
  changelog.sh notes
  changelog.sh release-notes TAG [-o OUTPUT]

Before tagging, set the first heading to:
  ## [X.Y.Z] - Unreleased
EOF
}

main() {
	[[ $# -ge 1 ]] || {
		usage >&2
		exit 1
	}

	case "$1" in
		version)
			cmd_version
			;;
		notes)
			cmd_notes
			;;
		release-notes)
			[[ $# -ge 2 ]] || die "Usage: changelog.sh release-notes TAG [-o OUTPUT]"
			local tag="$2"
			local output="${ROOT}/release-notes.md"
			shift 2
			while [[ $# -gt 0 ]]; do
				case "$1" in
					-o|--output)
						[[ $# -ge 2 ]] || die "release-notes -o requires a path"
						output="$2"
						shift 2
						;;
					*)
						die "Unknown release-notes argument: $1"
						;;
				esac
			done
			cmd_release_notes "$tag" "$output"
			;;
		-h|--help)
			usage
			;;
		*)
			die "Unknown command: $1"
			;;
	esac
}

main "$@"
