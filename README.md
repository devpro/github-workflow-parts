# GitHub workflow parts

[![CI](https://github.com/devpro/github-workflow-parts/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/devpro/github-workflow-parts/actions/workflows/ci.yml)

GitHub workflow components for code repositories.

> [!IMPORTANT]
> Keep your pipelines **safe** and **DRY**!

## Reusable workflows

> [!TIP]
> Rather than copying and pasting from one workflow to another, you can make workflows reusable.  
> Source: [Reusing workflow configurations](https://docs.github.com/en/actions/concepts/workflows-and-actions/reusing-workflow-configurations)

Containers:

- [Publish your image](.github/workflows/reusable-container-publication.yml)
- [Scan your image](.github/workflows/reusable-container-scan.yml)

.NET:

- [Ensure the quality of your code](.github/workflows/reusable-dotnet-quality.yml)

Markup (Markdown, YAML):

- [Ensure the quality of your content](.github/workflows/reusable-markup-lint.yml)

Terraform:

- [Deploy your environment](.github/workflows/reusable-terraform-deployment.yml)
- [Ensure the quality of your infrastructure code](.github/workflows/reusable-terraform-quality.yml)

## Composite actions

> [!TIP]
> Composite actions allow you to collect a series of workflow job steps into a single action which you can then run as a single job step in multiple workflows. 
> Source: [Creating a composite action](https://docs.github.com/en/actions/tutorials/create-actions/create-a-composite-action)

Containers:

- [Sign your image with Cosign](actions/cosign/sign/action.yml)

.NET:

- [Build, test your code and analyze it with Sonar](actions/dotnet/build-test-sonar/action.yml)
- [Build and test your code](actions/dotnet/build-test/action.yml)
- [Install the SDK, lint the code and restore NuGet packages](actions/dotnet/install-lint-restore/)

MongoDB:

- [Add your runner IP address to Atlas access list](actions/mongodb-atlas/add-runner-ip/action.yml)
- [Start a server in your pipeline](actions/mongodb/start/action.yml)

SBOM:

- [Generate a SBOM with Syft](actions/syft/generate-sbom/action.yml)

Terraform:

- [Setup Terraform](actions/terraform/setup/action.yml)
- [Setup TFLint](actions/tflint/setup/action.yml)

> [!NOTE]
> These composite actions download official release binaries directly (with SHA256 checksum verification)
> instead of relying on third-party marketplace actions (`hashicorp/setup-terraform`, `terraform-linters/setup-tflint`, `anchore/sbom-action`), reducing supply-chain exposure.
> Linux runners only (for example `ubuntu-latest`).
