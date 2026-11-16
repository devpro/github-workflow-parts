plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# A plugin pinned to an exact version, for the check of TFLint plugin versions.
plugin "azurerm" {
  enabled = true
  version = "0.33.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}
