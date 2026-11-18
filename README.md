# ha-ml-images

Attested Linux arm64 images for homelab Home Assistant sync and ML. Both
contain DuckDB, and the ML image adds LightGBM, Polars and their dependencies.
Homelab mounts the sync program through a ConfigMap. Both images run as UID and
GID 10001.

## Refresh the wheel lock

Review the Python bases and their Linux arm64 manifests with
`docker buildx imagetools inspect`. Update each Dockerfile's `FROM` digest and
`linux/arm64` digest together. Use the proposed ML base to resolve wheels for
the native Linux arm64 CPython runtime. Replace the explicit versions below
with the versions under review. Pin transitive versions as well so repeated
resolution uses the same set.

```bash
set -euo pipefail
base=$(awk '$1 == "FROM" && $4 == "base" {print $2}' ml/Dockerfile)
report=$(mktemp)
trap 'rm -f "$report"' EXIT
docker run --rm --platform linux/arm64 "$base" \
  python -m pip --isolated --disable-pip-version-check install --dry-run \
  --ignore-installed --only-binary=:all: --quiet --report - \
  duckdb==2.0.0 lightgbm==4.7.0 narwhals==2.28.0 numpy==2.5.5 \
  polars==2.1.0 polars-runtime-32==2.1.0 scipy==1.18.1 > "$report"

wheel_lines='sort_by(.metadata.name | ascii_downcase)[] | .download_info
  | if (.url | startswith("https://files.pythonhosted.org/")) and
       (.archive_info.hashes.sha256 | test("^[a-f0-9]{64}$"))
    then "\(.url) --hash=sha256:\(.archive_info.hashes.sha256)"
    else error("expected a PyPI wheel URL with a SHA-256 hash") end'
jq -er ".install | map(select(.metadata.name == \"duckdb\")) | $wheel_lines" \
  "$report" > locks/duckdb.txt
jq -er ".install | map(select(.metadata.name != \"duckdb\")) | $wheel_lines" \
  "$report" > locks/ml.txt
```

Review each URL and SHA-256 against the upstream release and check the
publisher attestation where available. The initial inputs and upstream
provenance are recorded in homelab Beads issue `homelab-9ph.37.3.1`. The URL
and hash identify a single compatible wheel per package, including
architecture-independent wheels and compatible ABI3 wheels. Commit the two
text locks. The PR workflow builds and smoke-tests both images on arm64,
including installation with the build network disabled.

## Release and verify

1. Review the PR and merge to protected `main` after both image smoke tests pass.
2. Dispatch **Release images** on `main`, then approve the `release` environment
   deployment. Use the OCI index digests and Linux arm64 child digests in the
   successful run's summary.
3. After the first publish, make both GHCR packages public. In each package's
   settings, disable inherited repository access and grant Actions access to
   `tkasu-lab-private/ha-ml-images` as the sole Write grant.
4. Verify both attestations and pull both index digests on a clean Docker host
   using an empty Docker client configuration. Paste the index digests from
   the run summary into the first two lines.

```bash
SYNC_DIGEST='sha256:<sync-index-digest>'
ML_DIGEST='sha256:<ml-index-digest>'
repo=tkasu-lab-private/ha-ml-images

set -euo pipefail
anonymous_config=$(mktemp -d)
trap 'rm -rf "$anonymous_config"' EXIT
printf '{"auths":{"ghcr.io":{}}}\n' > "$anonymous_config/config.json"

for image in "ghcr.io/$repo/sync@$SYNC_DIGEST" "ghcr.io/$repo/ml@$ML_DIGEST"; do
  gh attestation verify "oci://$image" \
    --repo "$repo" \
    --signer-workflow "$repo/.github/workflows/release.yml" \
    --source-ref refs/heads/main \
    --deny-self-hosted-runners
  docker --config "$anonymous_config" pull --platform linux/arm64 "$image"
done
```

Record both index and child digests, the source commit, build durations, the
verification results and the package settings in `homelab-9ph.37.3.2.1`.
Record the sync index digest in `homelab-9ph.37.3.2.2` for staging. Repeat
attestation verification before pinning a digest in homelab.
