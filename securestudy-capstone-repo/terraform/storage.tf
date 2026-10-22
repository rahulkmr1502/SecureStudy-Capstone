############################################
# Three buckets, same hardening on each:
#   data_bucket   - application data (SSE-KMS, versioned, logged, alerting)
#   trail_bucket - CloudTrail log archive
#   access_logs  - S3 server-access-log sink
############################################

resource "aws_s3_bucket" "data_bucket" {
  # checkov:skip=CKV_AWS_144:Cross-region replication needs a 2nd region + replica bucket + role; documented as a production-only control for this single-region lab
  bucket = var.bucket_name
  tags   = { Name = "securestudy-data" }
}

resource "aws_s3_bucket" "trail_bucket" {
  # checkov:skip=CKV_AWS_144:Same as data_bucket - single-region lab
  bucket = "${var.bucket_name}-cloudtrail-logs"
  tags   = { Name = "securestudy-cloudtrail" }
}

resource "aws_s3_bucket" "access_logs" {
  # checkov:skip=CKV_AWS_144:Same as data_bucket - single-region lab
  # checkov:skip=CKV_AWS_145:S3 server-access-log delivery does not support SSE-KMS target buckets; SSE-S3 (AES256) is the only option
  # checkov:skip=CKV_AWS_18:This IS the access-log destination; logging it to itself would recurse
  # checkov:skip=CKV2_AWS_62:Low-value log sink; deletion alerting is on the two buckets that matter
  bucket = "${var.bucket_name}-access-logs"
  tags   = { Name = "securestudy-access-logs" }
}

# ---------- public access blocked everywhere ----------

resource "aws_s3_bucket_public_access_block" "data_bucket" {
  bucket                  = aws_s3_bucket.data_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "trail_bucket" {
  bucket                  = aws_s3_bucket.trail_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------- versioning (fix for CKV_AWS_21 on trail bucket) ----------

resource "aws_s3_bucket_versioning" "data_bucket" {
  bucket = aws_s3_bucket.data_bucket.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_versioning" "trail_bucket" {
  bucket = aws_s3_bucket.trail_bucket.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_versioning" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  versioning_configuration { status = "Enabled" }
}

# ---------- encryption: KMS CMK (fix for CKV_AWS_145) ----------

resource "aws_s3_bucket_server_side_encryption_configuration" "data_bucket" {
  bucket = aws_s3_bucket.data_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail_bucket" {
  bucket = aws_s3_bucket.trail_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ---------- lifecycle (fix for CKV2_AWS_61 / CKV_AWS_300) ----------

resource "aws_s3_bucket_lifecycle_configuration" "data_bucket" {
  bucket     = aws_s3_bucket.data_bucket.id
  depends_on = [aws_s3_bucket_versioning.data_bucket]

  rule {
    id     = "expire-old-versions-abort-stale-uploads"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 90 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "trail_bucket" {
  bucket     = aws_s3_bucket.trail_bucket.id
  depends_on = [aws_s3_bucket_versioning.trail_bucket]

  rule {
    id     = "expire-old-versions-abort-stale-uploads"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 90 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket     = aws_s3_bucket.access_logs.id
  depends_on = [aws_s3_bucket_versioning.access_logs]

  rule {
    id     = "expire-logs-after-1-year"
    status = "Enabled"
    filter {}
    expiration { days = 365 }
    noncurrent_version_expiration { noncurrent_days = 30 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

# ---------- access logging (fix for CKV_AWS_18) ----------

resource "aws_s3_bucket_logging" "data_bucket" {
  bucket        = aws_s3_bucket.data_bucket.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "data-bucket/"
}

resource "aws_s3_bucket_logging" "trail_bucket" {
  bucket        = aws_s3_bucket.trail_bucket.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "trail-bucket/"
}

# ---------- delete-event alerting (fix for CKV2_AWS_62) ----------

resource "aws_s3_bucket_notification" "data_bucket" {
  bucket = aws_s3_bucket.data_bucket.id
  topic {
    topic_arn = aws_sns_topic.alerts.arn
    events    = ["s3:ObjectRemoved:*"]
  }
  depends_on = [aws_sns_topic_policy.alerts]
}

resource "aws_s3_bucket_notification" "trail_bucket" {
  bucket = aws_s3_bucket.trail_bucket.id
  topic {
    topic_arn = aws_sns_topic.alerts.arn
    events    = ["s3:ObjectRemoved:*"]
  }
  depends_on = [aws_sns_topic_policy.alerts]
}

# ---------- bucket policies: TLS-only on all, plus service writers ----------

data "aws_iam_policy_document" "data_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.data_bucket.arn, "${aws_s3_bucket.data_bucket.arn}/*"]
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

resource "aws_s3_bucket_policy" "data_bucket" {
  bucket = aws_s3_bucket.data_bucket.id
  policy = data.aws_iam_policy_document.data_bucket.json
}

data "aws_iam_policy_document" "trail_bucket" {
  statement {
    sid       = "AWSCloudTrailAclCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail_bucket.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }

  statement {
    sid       = "AWSCloudTrailWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail_bucket.arn}/AWSLogs/${local.account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.trail_bucket.arn, "${aws_s3_bucket.trail_bucket.arn}/*"]
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

resource "aws_s3_bucket_policy" "trail_bucket" {
  bucket = aws_s3_bucket.trail_bucket.id
  policy = data.aws_iam_policy_document.trail_bucket.json
}

data "aws_iam_policy_document" "access_logs" {
  statement {
    sid       = "S3ServerAccessLogDelivery"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.access_logs.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.access_logs.arn, "${aws_s3_bucket.access_logs.arn}/*"]
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

resource "aws_s3_bucket_policy" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  policy = data.aws_iam_policy_document.access_logs.json
}

############################################
# ALB access logs. The ALB log service cannot write to an SSE-KMS bucket, so this
# bucket uses SSE-S3; everything else about it matches the other buckets.
############################################

resource "aws_s3_bucket" "alb_logs" {
  # checkov:skip=CKV_AWS_144:Single-region project; replication is a production control
  # checkov:skip=CKV_AWS_145:ALB access-log delivery does not support SSE-KMS buckets; SSE-S3 is the only option
  # checkov:skip=CKV_AWS_18:Log sink; logging it to itself would recurse
  # checkov:skip=CKV2_AWS_62:Low-value log sink
  bucket = "${var.bucket_name}-alb-logs"
  tags   = { Name = "securestudy-alb-logs" }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket                  = aws_s3_bucket.alb_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket     = aws_s3_bucket.alb_logs.id
  depends_on = [aws_s3_bucket_versioning.alb_logs]
  rule {
    id     = "expire-logs-after-1-year"
    status = "Enabled"
    filter {}
    expiration { days = 365 }
    noncurrent_version_expiration { noncurrent_days = 30 }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}

resource "aws_s3_bucket_logging" "alb_logs" {
  bucket        = aws_s3_bucket.alb_logs.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "alb-logs-bucket/"
}

data "aws_elb_service_account" "main" {}

data "aws_iam_policy_document" "alb_logs" {
  statement {
    sid       = "AllowALBLogDelivery"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.alb_logs.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.main.arn]
    }
  }
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.alb_logs.arn, "${aws_s3_bucket.alb_logs.arn}/*"]
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

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = data.aws_iam_policy_document.alb_logs.json
}
