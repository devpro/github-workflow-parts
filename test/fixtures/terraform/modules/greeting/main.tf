# Module of the Terraform fixture, validated on its own and through the example calling it.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

variable "name" {
  description = "Name the greeting is addressed to"
  type        = string
}

resource "local_file" "greeting" {
  filename = "${path.root}/greeting.txt"
  content  = "Hello ${var.name}.\n"
}

output "filename" {
  description = "Path of the greeting file"
  value       = local_file.greeting.filename
}
