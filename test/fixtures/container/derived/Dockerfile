# Sets a default base that no registry has, so that a build fails when it does not use the base of the run.
ARG BASE_IMAGE=registry.invalid/never-published:latest
FROM ${BASE_IMAGE}
RUN test "$(cat /base-marker)" = built-in-this-run
