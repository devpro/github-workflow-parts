# Contributing

## Run the pipeline locally

[IstarCI](https://github.com/devpro/istarci) runs the GitHub Actions pipeline in Docker before the push.
`istarci add` and `istarci install-hook` set it up for this repository.

## Run the static checks

`test/run_static_checks.sh` runs actionlint, shellcheck on the scripts of the composite actions, and the conventions of `test/check_workflow_parts.py`.
A part no CI job can exercise is listed in `UNTESTED_PARTS` of that file, with the reason.
