# GitHub workflow parts

[![CI](https://github.com/devpro/github-workflow-parts/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/devpro/github-workflow-parts/actions/workflows/ci.yml)

GitHub workflow components for code repositories.

> [!IMPORTANT]
> Keep pipelines **safe** and **DRY**!

## Reusable workflows

> [!TIP]
> Rather than copying and pasting from one workflow to another, you can make workflows reusable.  
> Source: [Reusing workflow configurations](https://docs.github.com/en/actions/concepts/workflows-and-actions/reusing-workflow-configurations)

Containers:

- [Publish an image](.github/workflows/reusable-container-publication.yml)
- [Scan an image](.github/workflows/reusable-container-scan.yml)

.NET:

- [Ensure the quality of the code](.github/workflows/reusable-dotnet-quality.yml)

Git:

- [Tell what changed, the version and the branch slug, for the jobs that follow](.github/workflows/reusable-git-check.yml)

GitHub Pages:

- [Build a site and deploy it](.github/workflows/reusable-pages-deployment.yml)

Markup (Markdown, YAML):

- [Ensure the quality of the content](.github/workflows/reusable-markup-lint.yml)

Node.js:

- [Lint, build, test and analyze the code](.github/workflows/reusable-node-quality.yml)
- [Publish a package to npmjs.org or GitHub Packages](.github/workflows/reusable-npm-publication.yml)

Terraform:

- [Deploy or destroy an environment](.github/workflows/reusable-terraform-deployment.yml)
- [Ensure the quality of the infrastructure code](.github/workflows/reusable-terraform-quality.yml)

## Composite actions

> [!TIP]
> Composite actions allow you to collect a series of workflow job steps into a single action which you can then run as a single job step in multiple workflows. 
> Source: [Creating a composite action](https://docs.github.com/en/actions/tutorials/create-actions/create-a-composite-action)

Containers:

- [Build and push an image for one or more platforms](actions/container/build-push/action.yml)
- [Sign an image with Cosign](actions/cosign/sign/action.yml)
- [Setup QEMU to build images for other platforms](actions/qemu/setup/action.yml)
- [Scan an image or a directory with Trivy](actions/trivy/scan/action.yml)

.NET:

- [Build, test the code and analyze it with Sonar](actions/dotnet/build-test-sonar/action.yml)
- [Build and test the code](actions/dotnet/build-test/action.yml)
- [Install the SDK, lint the code and restore NuGet packages](actions/dotnet/install-lint-restore/action.yml)
- [Package the projects and push them to a NuGet registry](actions/dotnet/pack-push/action.yml)

Git:

- [Tell whether a commit changes some paths](actions/git/check-changes/action.yml)

Go:

- [Lint the code with the Go toolchain](actions/go/lint/action.yml)
- [Scan the code with govulncheck](actions/govulncheck/scan/action.yml)
- [Setup GoReleaser](actions/goreleaser/setup/action.yml)

Helm:

- [Setup Helm](actions/helm/setup/action.yml)
- [Setup chart-testing](actions/chart-testing/setup/action.yml)

License compliance:

- [Analyze the dependencies with FOSSA](actions/fossa/analyze/action.yml)

MongoDB:

- [Add the runner IP address to the Atlas access list](actions/mongodb-atlas/add-runner-ip/action.yml)
- [Start a server in the pipeline](actions/mongodb/start/action.yml)

Node.js:

- [Publish a package unless its version already is](actions/npm/publish/action.yml)
- [Install the Playwright browsers](actions/playwright/install/action.yml)

Sonar:

- [Analyze the code of a project other than .NET](actions/sonar/scan/action.yml)

SBOM:

- [Generate a SBOM with Syft](actions/syft/generate-sbom/action.yml)

Task:

- [Setup Task](actions/task/setup/action.yml)

Terraform:

- [Setup Terraform](actions/terraform/setup/action.yml)
- [Setup TFLint](actions/tflint/setup/action.yml)

> [!NOTE]
> These composite actions download official release binaries directly (with SHA256 checksum verification) instead of relying on third-party marketplace actions, reducing supply-chain exposure.
> Linux runners only (for example `ubuntu-latest`).
