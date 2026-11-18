# linux/arm64: sha256:3dc01f342e31ad8de39338d14ab12de0090c9102b34f75ca9774ff1f4f5e904e
FROM docker.io/library/python:3.12.16-bookworm@sha256:4209fae09a3e20afd863e528bfddc235da5fd5977983e1996cd54cc9a72e6267 AS base

FROM base AS wheelhouse
COPY locks/duckdb.txt locks/ml.txt /locks/
RUN cat /locks/duckdb.txt /locks/ml.txt > /tmp/wheels.txt \
    && python -m pip --isolated --disable-pip-version-check --no-cache-dir download \
      --no-index --no-deps --require-hashes --only-binary=:all: \
      --dest /wheelhouse -r /tmp/wheels.txt \
    && sed -E 's|^https://files\.pythonhosted\.org/[^ ]*/([^/ ]+)|/wheelhouse/\1|' \
      /tmp/wheels.txt > /wheelhouse/requirements.txt

FROM base
RUN --network=none --mount=type=bind,from=wheelhouse,source=/wheelhouse,target=/wheelhouse \
    python -m pip --isolated --disable-pip-version-check --no-cache-dir install \
      --no-index --require-hashes --only-binary=:all: -r /wheelhouse/requirements.txt
USER 10001:10001
