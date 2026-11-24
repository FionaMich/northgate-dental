# Northgate's AWS account baseline: audit trail, account-wide public access block, password policy, cost anomaly
# alerts and the Storage Lens dashboard. IAM Access Analyzer is denied by the AWS free plan's service control
# policy, so it is not here (see docs/adr/0010).

locals {
  account = data.aws_caller_identity.me.account_id
}

# No bucket in this account can ever be made public, whatever its own settings say.
resource "aws_s3_account_public_access_block" "account" {
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  password_reuse_prevention      = 24
  max_password_age               = 0 # NIST 800-63B: no forced rotation; MFA is required instead
}

# ---------- CloudTrail: who did what in the account ----------

resource "aws_s3_bucket" "trail" {
  bucket = "northgate-cloudtrail-${local.account}"
}

resource "aws_s3_bucket_ownership_controls" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket                  = aws_s3_bucket.trail.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "trail" {
  bucket = aws_s3_bucket.trail.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id
  rule {
    id     = "expire-90-days"
    status = "Enabled"
    filter {}
    expiration { days = 90 }
    noncurrent_version_expiration { noncurrent_days = 90 }
  }
}

data "aws_iam_policy_document" "trail" {
  statement {
    sid       = "CloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:eu-north-1:${local.account}:trail/northgate-audit"]
    }
  }
  statement {
    sid       = "CloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail.arn}/AWSLogs/${local.account}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:eu-north-1:${local.account}:trail/northgate-audit"]
    }
  }
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.trail.arn, "${aws_s3_bucket.trail.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id
  policy = data.aws_iam_policy_document.trail.json
}

resource "aws_cloudtrail" "audit" {
  name                          = "northgate-audit"
  s3_bucket_name                = aws_s3_bucket.trail.id
  is_multi_region_trail         = true # actions in any region, including attempts in regions we never use
  include_global_service_events = true # IAM and sign-in events
  enable_log_file_validation    = true # signed digests prove no log file was changed or deleted
  depends_on                    = [aws_s3_bucket_policy.trail]
}

# ---------- costs ----------

resource "aws_ce_anomaly_monitor" "services" {
  name              = "northgate-services"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "email" {
  name             = "northgate-anomalies"
  frequency        = "DAILY"
  monitor_arn_list = [aws_ce_anomaly_monitor.services.arn]
  subscriber {
    type    = "EMAIL"
    address = var.alert_email
  }
  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = ["1"]
    }
  }
}

# ---------- Storage Lens (created by hand on 2026-11-21, imported) ----------

import {
  to = aws_s3control_storage_lens_configuration.northgate
  id = "255103685459:northgate-storage"
}

resource "aws_s3control_storage_lens_configuration" "northgate" {
  config_id = "northgate-storage"
  storage_lens_configuration {
    enabled = true
    account_level {
      bucket_level {}
    }
    include {
      regions = ["eu-north-1", "us-east-1"]
    }
  }
}
