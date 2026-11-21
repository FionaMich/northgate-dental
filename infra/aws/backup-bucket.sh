#!/usr/bin/env bash
# Creates the backup bucket and its two keys (blueprint section 52), in eu-north-1 where this AWS account lives (ADR 0003).
#   aws login --profile northgate && infra/aws/backup-bucket.sh
# Safe to run again. Writes the upload-only key to infra/backup-upload.env (git-ignored) for the VM; the read-only key is
# saved as the local profile northgate-restore and never goes to the VM.
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-northgate}" AWS_REGION=eu-north-1
account="$(aws sts get-caller-identity --query Account --output text)"
bucket="northgate-backups-$account"

if ! aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
  aws s3api create-bucket --bucket "$bucket" --create-bucket-configuration LocationConstraint=$AWS_REGION >/dev/null
fi
aws s3api put-public-access-block --bucket "$bucket" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-versioning --bucket "$bucket" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$bucket" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
# 30 days for every copy, so an overwrite from the VM can never erase an earlier one before then.
aws s3api put-bucket-lifecycle-configuration --bucket "$bucket" --lifecycle-configuration '{"Rules":[{"ID":"expire-30-days",
  "Status":"Enabled","Filter":{"Prefix":"nightly/"},"Expiration":{"Days":30},"NoncurrentVersionExpiration":{"NoncurrentDays":30},
  "AbortIncompleteMultipartUpload":{"DaysAfterInitiation":2}}]}'
aws s3api put-bucket-tagging --bucket "$bucket" --tagging 'TagSet=[{Key=product,Value=northgate},{Key=environment,Value=production}]'

make_user() { # name, policy json
  aws iam get-user --user-name "$1" >/dev/null 2>&1 || aws iam create-user --user-name "$1" --tags Key=product,Value=northgate >/dev/null
  aws iam put-user-policy --user-name "$1" --policy-name "$1" --policy-document "$2"
}
make_user northgate-backup-upload "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"s3:PutObject\",
  \"Resource\":\"arn:aws:s3:::$bucket/nightly/*\"}]}"
make_user northgate-backup-restore "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:ListBucket\"],
  \"Resource\":[\"arn:aws:s3:::$bucket\",\"arn:aws:s3:::$bucket/nightly/*\"]}]}"

# The upload key goes straight into a git-ignored file for the VM's infra/.env, never onto the screen.
keyfile="$(dirname "$0")/../backup-upload.env"
if [ "$(aws iam list-access-keys --user-name northgate-backup-upload --query 'length(AccessKeyMetadata)')" = 0 ]; then
  umask 077
  read -r id secret < <(aws iam create-access-key --user-name northgate-backup-upload --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text)
  printf 'AWS_ACCESS_KEY_ID=%s\nAWS_SECRET_ACCESS_KEY=%s\nBACKUP_BUCKET=%s\n' "$id" "$secret" "$bucket" > "$keyfile"
  echo "upload-only key written to infra/backup-upload.env (git-ignored); copy it into infra/.env on the VM"
fi
if [ "$(aws iam list-access-keys --user-name northgate-backup-restore --query 'length(AccessKeyMetadata)')" = 0 ]; then
  read -r id secret < <(aws iam create-access-key --user-name northgate-backup-restore --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text)
  aws configure set aws_access_key_id "$id" --profile northgate-restore
  aws configure set aws_secret_access_key "$secret" --profile northgate-restore
  aws configure set region eu-north-1 --profile northgate-restore
fi

# A US$1 monthly budget alert, if none exists yet (blueprint: budget alerts before any resource).
if ! aws budgets describe-budgets --account-id "$account" --query 'Budgets[].BudgetName' --output text | grep -q northgate; then
  email="$(git config user.email)"
  aws budgets create-budget --account-id "$account" \
    --budget '{"BudgetName":"northgate-monthly","BudgetLimit":{"Amount":"1","Unit":"USD"},"TimeUnit":"MONTHLY","BudgetType":"COST"}' \
    --notifications-with-subscribers "[{\"Notification\":{\"NotificationType\":\"ACTUAL\",\"ComparisonOperator\":\"GREATER_THAN\",\"Threshold\":80},
      \"Subscribers\":[{\"SubscriptionType\":\"EMAIL\",\"Address\":\"$email\"}]}]"
fi
echo "BACKUP_BUCKET=$bucket"
