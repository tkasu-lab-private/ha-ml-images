#!/usr/bin/env bash
set -euo pipefail

mode=${1:-}
case "$mode" in
  check | release) ;;
  *)
    printf 'Usage: %s {check|release}\n' "$0" >&2
    exit 2
    ;;
esac

readonly registry=ghcr.io/tkasu-lab-private/ha-ml-images
readonly scanner=docker.io/docker/buildkit-syft-scanner:stable-1@sha256:873a7458c3c8ac8e32c7b796c10e1600b07b963d2aa000a72a2d97aaaa2d6315
readonly digest_pattern='^sha256:[a-f0-9]{64}$'

arm64_digest() {
  docker buildx imagetools inspect --raw "$1" |
    jq -er --arg pattern "$digest_pattern" '
      [.manifests[] | select(.platform.os == "linux" and .platform.architecture == "arm64") | .digest]
      | if length == 1 then .[0] | select(test($pattern))
        else error("expected one linux/arm64 manifest") end'
}

if [[ "$mode" == release ]]; then
  metadata_dir=$(mktemp -d)
  trap 'rm -rf -- "$metadata_dir"' EXIT
  printf "Source commit \`%s\`\n\n| Image | OCI index | Linux arm64 child | Build elapsed |\n| --- | --- | --- | ---: |\n" \
    "$GITHUB_SHA" >>"$GITHUB_STEP_SUMMARY"
fi

for target in sync ml; do
  dockerfile=$target/Dockerfile
  base=$(awk '$1 == "FROM" && $3 == "AS" && $4 == "base" {print $2}' "$dockerfile")
  expected=$(awk '$1 == "#" && $2 == "linux/arm64:" {print $3}' "$dockerfile")
  if [[ ! "$base" =~ ^docker\.io/library/python:[^[:space:]@]+@sha256:[a-f0-9]{64}$ || ! "$expected" =~ $digest_pattern ]]; then
    printf '%s must pin the official Python index and its Linux arm64 child\n' "$dockerfile" >&2
    exit 1
  fi
  if ! actual=$(arm64_digest "$base") || [[ "$actual" != "$expected" ]]; then
    printf '%s Linux arm64 base does not match %s\n' "$base" "$expected" >&2
    exit 1
  fi

  args=(--load --provenance=false --tag "ha-ml-images-$target:check")
  smoke_ref="ha-ml-images-$target:check"
  if [[ "$mode" == release ]]; then
    image="$registry/$target"
    args=(--provenance=mode=max --attest "type=sbom,generator=$scanner"
      --label "org.opencontainers.image.source=https://github.com/tkasu-lab-private/ha-ml-images"
      --label "org.opencontainers.image.revision=$GITHUB_SHA"
      --metadata-file "$metadata_dir/$target.json"
      --output "type=image,name=$image,push=true,push-by-digest=true,name-canonical=true")
  fi

  started=$SECONDS
  docker buildx build --platform linux/arm64 --file "$dockerfile" "${args[@]}" .
  elapsed=$((SECONDS - started))
  if [[ "$mode" == release ]]; then
    index=$(jq -er --arg pattern "$digest_pattern" '."containerimage.digest" | select(test($pattern))' \
      "$metadata_dir/$target.json")
    smoke_ref="$image@$index"
    child=$(arm64_digest "$smoke_ref")
  fi

  smoke='import os, duckdb; assert os.getuid() == 10001; assert duckdb.__version__ == "2.0.0"; print(duckdb.__version__)'
  if [[ "$target" == ml ]]; then
    smoke+='; import lightgbm, polars, numpy'
  fi
  docker run --rm --platform linux/arm64 --network none "$smoke_ref" python -c "$smoke"

  if [[ "$mode" == release ]]; then
    printf '%s_digest=%s\n' "$target" "$index" >>"$GITHUB_OUTPUT"
    printf "| \`%s\` | \`%s\` | \`%s\` | %s s |\n" "$image" "$index" "$child" "$elapsed" >>"$GITHUB_STEP_SUMMARY"
  fi
done
