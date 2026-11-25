# Gives the CI (.github/workflows/ci.yml) a minimal configuration to test reusable-terraform-quality.yml.
# The workflow runs terraform fmt, init and validate, then Checkov, TFLint and Trivy.
# Uses no cloud provider, so that the test needs no credentials.

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
