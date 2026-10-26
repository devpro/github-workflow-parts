---
name: adopt-workflow-parts
description: >
  Move a repository's GitHub workflows onto the github-workflow-parts catalog, change the catalog when a repository needs a part it lacks,
  and bump consumers to a new catalog commit.
  Use when adopting, updating or bumping workflow parts in any repository, or when an IstarCI run of a consumer fails.
---

# Adopt workflow parts

## Goal

The catalog is a high quality set of GitHub parts that pushes best practices into every repository and removes most of their pipeline code.
A consumer workflow is a few `uses:` of reusable workflows with inputs, no hand written tool installs, no action referenced by a version tag.

## Procedure

### Catalog change

1. Start from the closest existing part and verify every claim (a CLI flag, a config file, a release) before stating it.
2. Propose the design: steps, inputs with defaults, and what the change adds or removes.
3. Wait for approval before any edit.
4. Edit, run `test/run_static_checks.sh`, commit, `istarci wait`.
5. The user pushes; consumers reference the pushed SHA only.

### Consumer adoption

1. `git rev-parse --abbrev-ref HEAD`: commit on the current branch, unless it is `main`, where a feature branch comes first.
2. Strip any UTF-8 byte order mark from tracked files and set `.editorconfig` `charset = utf-8-bom` to `utf-8`, in a commit of its own.
3. Replace `.github/workflows` jobs with the reusable workflows, every `uses:` and `workflow-parts-version` on the same full SHA.
4. Change one repository first, show its diff, wait, then do the others.
5. Commit, then `istarci wait`, and fix what fails before moving on.

### Bump pass

1. Replace the old SHA with the new one in every `uses:` and `workflow-parts-version` of each repository.
2. Commit "Use workflow parts *short sha*, ..." stating what the new commit brings, then `istarci wait` repository by repository.
3. A failure from a new check (a vulnerability found by an image scan) is fixed in its own commit, in the same pass.

## Conventions

### Reusable workflows

- A few broad steps driven by conventions:
  npm scripts `lint`, `format:check`, `typecheck`, `build`, `test` run with `--if-present`, a Pages build with `npm ci` then `npm run build`.
- Optional parts behind a flag or an input with a default (`mongodb-enabled`, `mongodb-version`, `severity`),
  and a single optional `custom-tests` step.
- Never one step running whatever command a caller gives.
- Every shell input reaches the script through `env:`, never `${{ }}` inside `run:`, which is a script injection.
- Tool configuration files of the repository are respected (`sonar-project.properties`, `.trivyignore.yaml`).
- The checkout of the catalog itself is added to `.git/info/exclude`, so linters and scanners of the consumer skip it.
- No test in a publication workflow (`pkg.yml`): quality runs in CI, publication only builds and ships.
- `reusable-dotnet-quality.yml` is an old example, improved alongside rather than copied.

### Supply chain

Safety before convenience, and fewer dependencies over more.

- First-party actions (`actions/*`, `github/*`) pinned by full SHA with a `# vX.Y.Z` inline comment with two spaces before (yamllint).
- No third-party action: a tool is a release binary checked against its SHA256 in a `setup` action, or the runner's OS packages.
- No third-party container image; `ghcr.io/devpro/*` and Docker Hub `devprofr/*` are first party.
- No Dependabot: versions are bumped by hand after checking the release exists.
- Lock files with hashes: `npm ci`, `pip install --require-hashes`, never an unpinned global install.
- A vulnerable image with no fixed release is replaced by a first-party one (`alpine-node` over `node`, an in-suite mailbox over Mailpit)
  rather than ignored.
- A Trivy ignore, with a reason and an expiry under a month, is the last resort, for something run unprivileged in tests only.
- An npm `overrides` entry is a last resort too:
  only when no release of the parent package, `latest` or `next`, fixes the dependency, and it is reverted once one does.
- Secrets stay secrets, even a low value one such as an IndexNow key in a public repository.

### Versions

- Node.js 24 by default, a library tested on 22, 24 and 26.
- MongoDB 9.0 in Docker Compose files, a single-node replica set `rs0` when the code uses transactions.

## Boundaries

- Azure DevOps and GitLab pipelines are never removed or emptied: the same repositories run on several CI systems.
  GitLab gets its own session; only a minimal path fix keeping it working is allowed here.
- Deliberately vulnerable images for security workshops (container-images `tinyfilemanager`, `nextportal`) are left untouched,
  neither scanned nor published.
- Commit only when asked, never push, never commit on `main`.
- YAML and Markdown linters are never run by an agent: CI runs them.

## IstarCI

- The daemon runs every commit by itself: after a commit, `istarci wait` only.
- `istarci run <sha>` retries a run that must run again (daemon restart, change to `~/.istarci/config.yml`), never right after a commit.
- A command over the 600 second tool limit is moved to the background, against the foreground rule:
  `timeout 590 istarci wait` then call it again while the run is going.
- `.istarci.yml` of a consumer sets the runner image per job (`ghcr.io/devpro/debian-node-playwright` for browser tests),
  the jobs needing Docker,
  and `skipJobs` for jobs that must never run on the developer machine (kind's privileged node, a QEMU registration in the kernel).
- The global ignores of image scans live in `~/.istarci/config.yml`, each with a reason and an expiry.

## Gotchas

- npm keeps the lock entry of a parent package when an override is added, and may even drop the child:
  delete the lock entries of the parent and of the child, then `npm install`, and check `npm ls <child> --all` says `overridden`.
- Use the Node.js of `~/.nvm/versions/node/v24.22.1/bin`: the shell `PATH` may resolve an older, vulnerable one.
- A file starting with a byte order mark breaks some tools,
  and `dotnet format` fails every C# file when `.editorconfig` asks for `utf-8-bom` and the files have none.
- `build-push` uses the Docker daemon BuildKit (`--builder default`), with one tag per platform merged by `docker buildx imagetools create`,
  as a `docker-container` builder cannot see images of the daemon.
- Trivy scans Java dependencies with `--offline-scan`, or it calls Maven Central for each one.
- CodeQL needs more memory than the default on large code bases, and its .NET extractor needs ICU.
- Python scanners reading non-ASCII sources need `PYTHONUTF8=1` in a container whose locale is not UTF-8.
- Playwright tests are found through `node_modules/.bin/playwright` of the root only, not of a workspace.
- A Sonar scan without `sonar-host-url` targets SonarCloud.

## Commits

- One sentence saying why, in the writing style of `AGENTS.md`: no em dash, no second person, the why timeless.
- Script files `snake_case`, committed with the executable bit (`git update-index --chmod=+x`).
- The final report lists each repository, branch, commit and run result, and what is left to the user (pushes, secrets, a first publication run).
