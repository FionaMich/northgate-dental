terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # shortcut: local state (git-ignored) while one person runs Terraform; move to an S3 backend with locking
  # before CI or a second person applies.
}

provider "aws" {
  profile = "northgate"  # `aws login --profile northgate` on Fiona's laptop
  region  = "eu-north-1" # the account's fixed region (ADR 0003)
  default_tags {
    tags = { product = "northgate", environment = "production", managed_by = "terraform" }
  }
}

data "aws_caller_identity" "me" {}
