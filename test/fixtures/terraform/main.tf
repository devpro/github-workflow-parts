# Minimal, valid Terraform configuration used by this repository's own CI (see .github/workflows/ci.yml)
# to exercise the reusable-terraform-quality.yml workflow end-to-end: terraform fmt/init/validate,
# Checkov, TFLint and Trivy all run against it.
# It intentionally has no cloud provider dependency so it can run without any credentials.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

resource "local_file" "example" {
  filename = "${path.module}/example.txt"
  content  = "Hello from the github-workflow-parts CI test fixture.\n"
}
