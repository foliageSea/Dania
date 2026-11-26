#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

usage() {
  printf '%s\n' \
    'Usage: scripts/release.sh X.Y.Z [BUILD_NUMBER] [--push]' \
    '       scripts/release.sh --check-tag vX.Y.Z' \
    'The version and build number (1-2100000000) must both increase.'
}

die() {
  printf 'release: %s\n' "$*" >&2
  exit 1
}

# Compare validated decimal strings without overflowing shell integers.
decimal_gt() {
  (( ${#1} > ${#2} )) || { (( ${#1} == ${#2} )) && [[ $1 > $2 ]]; }
}

version_gt() {
  local -a next current
  local i
  IFS=. read -r -a next <<< "$1"
  IFS=. read -r -a current <<< "$2"
  for i in 0 1 2; do
    if [[ ${next[i]} != "${current[i]}" ]]; then
      decimal_gt "${next[i]}" "${current[i]}"
      return
    fi
  done
  return 1
}

# Read the project's plain top-level YAML fields and reject duplicate keys.
manifest_field() {
  awk -v key="$1" '
    $0 ~ ("^" key "[[:blank:]]*:[[:space:]]") {
      count++
      sub(/\r$/, "")
      sub(/^[^:]+:[[:blank:]]*/, "")
      sub(/[[:blank:]]+#.*$/, "")
      sub(/[[:blank:]]+$/, "")
      value = $0
    }
    $0 ~ ("^" key "[[:blank:]]*:$") { count++ }
    END { if (count != 1 || value == "") exit 1; print value }
  ' pubspec.yaml
}

check_tag=false
push=false
version=
build=
component='(0|[1-9][0-9]*)'
version_pattern="$component\.${component}\.${component}"
build_pattern='[1-9][0-9]*'
max_build=2100000000 # Android/Google Play versionCode limit.

case ${1-} in
  -h|--help) usage; exit 0 ;;
  --check-tag)
    [[ $# == 2 && $2 =~ ^v$version_pattern$ ]] || die 'Expected --check-tag vX.Y.Z.'
    check_tag=true
    version=${2#v}
    ;;
  *)
    for arg in "$@"; do
      case $arg in
        --push)
          ! $push || die 'Specify --push only once.'
          push=true
          ;;
        *)
          if [[ -z $version && $arg =~ ^$version_pattern$ ]]; then
            version=$arg
          elif [[ -n $version && -z $build && $arg =~ ^$build_pattern$ ]]; then
            build=$arg
          else
            die "Unexpected argument: '$arg'. Expected X.Y.Z [BUILD_NUMBER] [--push]."
          fi
          ;;
      esac
    done
    [[ -n $version ]] || { usage >&2; exit 1; }
    ;;
esac

CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
[[ -f pubspec.yaml && ! -L pubspec.yaml ]] || die 'Expected a regular pubspec.yaml.'
name=$(manifest_field name) && [[ $name == dania ]] || die 'Expected exactly one top-level name: dania in pubspec.yaml.'
manifest=$(manifest_field version) && [[ $manifest =~ ^$version_pattern\+$build_pattern$ ]] ||
  die 'Expected exactly one top-level version: X.Y.Z+BUILD_NUMBER with a positive decimal build in pubspec.yaml.'
current_version=${manifest%+*}
current_build=${manifest##*+}
if decimal_gt "$current_build" "$max_build"; then
  die "pubspec.yaml build $current_build exceeds the Android limit ($max_build)."
fi
tag="v$version"

if $check_tag; then
  [[ $version == "$current_version" ]] || die "Tag $tag does not match pubspec.yaml ($manifest)."
  printf '%s\n' "$version"
  exit 0
fi

branch_ref=$(git symbolic-ref --quiet HEAD) || die 'Release requires a checked-out Git branch.'
[[ $branch_ref == refs/heads/* ]] || die 'HEAD does not point to a local branch.'
git ls-files --error-unmatch -- pubspec.yaml >/dev/null || die 'pubspec.yaml must be tracked.'
status=$(git status --porcelain=v1 --untracked-files=all) || die 'Could not check Git status.'
[[ -z $status ]] || die 'Git checkout must be clean (including untracked files).'
for state in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer; do
  [[ ! -e $(git rev-parse --git-path "$state") ]] || die 'Finish the in-progress Git operation before releasing.'
done

version_gt "$version" "$current_version" || die "Version $version must be greater than $current_version."
if [[ -z $build ]]; then
  build=$((current_build + 1))
fi
if decimal_gt "$build" "$max_build"; then
  die "Build $build exceeds the Android limit ($max_build)."
fi
decimal_gt "$build" "$current_build" || die "Build $build must be greater than $current_build."

tag_ref="refs/tags/$tag"
if git show-ref --verify --quiet "$tag_ref"; then
  die "Tag $tag already exists locally."
fi

if $push; then
  push_url=$(git remote get-url --push --all origin) || die 'No push URL for origin.'
  [[ -n $push_url && $push_url != *$'\n'* ]] || die 'Atomic release requires exactly one push URL for origin.'
  remote_tags=$(git ls-remote --refs -- "$push_url" "$tag_ref") || die 'Could not check tags at the origin push URL.'
  while IFS=$'\t' read -r _ ref; do
    [[ $ref != "$tag_ref" ]] || die "Tag $tag already exists on origin."
  done <<< "$remote_tags"
fi

git var GIT_AUTHOR_IDENT >/dev/null && git var GIT_COMMITTER_IDENT >/dev/null || die 'Configure Git author and committer identity before releasing.'

release="$version+$build"
tmp=$(mktemp "$PWD/.release-pubspec.XXXXXX")
trap 'rm -f -- "$tmp"' EXIT
cp -p pubspec.yaml "$tmp"
# Replace only the validated version scalar, retaining spacing and comments.
sed -E "s/^(version[[:blank:]]*:[[:blank:]]+)[^[:space:]]+/\1$release/" pubspec.yaml > "$tmp"
mv -f -- "$tmp" pubspec.yaml

git commit --only -m "Release $tag" -- pubspec.yaml || die 'Commit failed; pubspec.yaml was updated but no tag was created.'
git tag -a "$tag" -m "Release $tag" || die "The release commit exists, but tag $tag could not be created."

if $push; then
  # Require the tag to still be absent, and never implicitly push other tags.
  git -c remote.origin.mirror=false push --atomic --no-follow-tags \
    --force-with-lease="$tag_ref:" origin "$branch_ref:$branch_ref" "$tag_ref:$tag_ref" ||
    die "Atomic push failed; the release commit and $tag remain local. Resolve the remote error before retrying the push."
  printf 'Published %s (%s) to origin.\n' "$tag" "$release"
else
  printf 'Created local release %s (%s); nothing was pushed.\n' "$tag" "$release"
fi
