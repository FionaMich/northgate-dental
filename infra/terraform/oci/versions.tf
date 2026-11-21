terraform {
  required_version = ">= 1.9"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.0"
    }
  }
  # shortcut: local state (git-ignored) while one person runs Terraform; move to an Object Storage backend
  # before a second person or CI applies changes, so two applies can never race.
}

provider "oci" {
  config_file_profile = "DEFAULT" # ~/.oci/config on Fiona's laptop; never in the repository
  region              = var.region
}
