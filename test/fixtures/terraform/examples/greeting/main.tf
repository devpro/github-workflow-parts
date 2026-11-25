# Calls the module of the Terraform fixture from a root configuration that has a committed lock file.

terraform {
  required_version = ">= 1.9.0"
}

module "greeting" {
  source = "../../modules/greeting"

  name = "github-workflow-parts"
}

output "filename" {
  description = "Path of the greeting file"
  value       = module.greeting.filename
}
