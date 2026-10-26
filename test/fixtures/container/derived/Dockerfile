# The default names a base no registry has, so a build ignoring the base of the run fails rather than passing on a published one.
ARG BASE_IMAGE=registry.invalid/never-published:latest
FROM ${BASE_IMAGE}
RUN test "$(cat /base-marker)" = built-in-this-run
