# Contributing

## Run the pipeline locally

[IstarCI](https://github.com/devpro/istarci) runs the GitHub Actions pipeline in Docker before the push.
`istarci add` and `istarci install-hook` set it up for this repository.

### Jobs left to GitHub

`test-qemu-setup` registers an emulator in the kernel, so `.istarci.yml` skips it, as a local run leaves the machine unchanged.
The jobs on `ubuntu-24.04-arm` run arm64 binaries, the tools installed and the `RUN` steps of the images built, which only an arm64 processor executes natively.
IstarCI runs them on an arm64 machine, emulated on an amd64 one with a `qemu-aarch64` registration holding the F flag (from `qemu-user-static`), and skips them with a warning otherwise.

## Run the static checks

`test/run_static_checks.sh` runs actionlint, shellcheck on the scripts of the composite actions, and the conventions of `test/check_workflow_parts.py`.
A part no CI job can exercise is listed in `UNTESTED_PARTS` of that file, with the reason.
