# linux/arm64: sha256:df540bfd30bd380e89a349611ce42aa67bcb542d58c047706616eb6ba2f86a1b
FROM docker.io/library/python:3.12.16-slim-bookworm@sha256:935c3c5b12357a7e10caa9c1e6ca5692344d97cf229832ef584be2cec9fc03df AS base

FROM base AS wheelhouse
COPY locks/duckdb.txt /tmp/wheels.txt
RUN python -m pip --isolated --disable-pip-version-check --no-cache-dir download \
      --no-index --no-deps --require-hashes --only-binary=:all: \
      --dest /wheelhouse -r /tmp/wheels.txt \
    && sed -E 's|^https://files\.pythonhosted\.org/[^ ]*/([^/ ]+)|/wheelhouse/\1|' \
      /tmp/wheels.txt > /wheelhouse/requirements.txt

FROM base
RUN --network=none --mount=type=bind,from=wheelhouse,source=/wheelhouse,target=/wheelhouse \
    python -m pip --isolated --disable-pip-version-check --no-cache-dir install \
      --no-index --require-hashes --only-binary=:all: -r /wheelhouse/requirements.txt
USER 10001:10001
