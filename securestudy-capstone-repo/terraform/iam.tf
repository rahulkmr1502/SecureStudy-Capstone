############################################
# Identity: no IAM users. Humans get SSO / assumed roles; machines get roles.
#   app role      - what the application servers can do (one bucket, SSM, nothing else)
#   readonly role - analyst access, MFA required
############################################

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "securestudy-app-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

# Session Manager replaces SSH: no port 22, no key pairs, every session is logged.
resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "app_permissions" {
  statement {
    sid       = "ReadWriteOwnBucketObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.data_bucket.arn}/*"]
  }
  statement {
    sid       = "ListOwnBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.data_bucket.arn]
  }
  statement {
    sid       = "UseOnlyThisKey"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.main.arn]
  }
  statement {
    sid       = "ReadDatabaseSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.main.master_user_secret[0].secret_arn]
  }
}

resource "aws_iam_role_policy" "app" {
  name   = "securestudy-app-permissions"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app_permissions.json
}

resource "aws_iam_instance_profile" "app" {
  name = "securestudy-app-profile"
  role = aws_iam_role.app.name
}

# ---------- analyst role: read-only, MFA required ----------

data "aws_iam_policy_document" "analyst_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

data "aws_iam_policy_document" "analyst_permissions" {
  statement {
    sid       = "ReadLogs"
    effect    = "Allow"
    actions   = ["logs:GetLogEvents", "logs:FilterLogEvents", "logs:StartQuery", "logs:GetQueryResults"]
    resources = ["${aws_cloudwatch_log_group.trail.arn}:*"]
  }
  statement {
    sid       = "DecryptLogs"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.main.arn]
  }
  statement {
    sid       = "ReadFindings"
    effect    = "Allow"
    actions   = ["guardduty:GetFindings", "guardduty:ListFindings"]
    resources = ["arn:aws:guardduty:${var.aws_region}:${local.account_id}:detector/${aws_guardduty_detector.main.id}"]
  }
}

resource "aws_iam_role" "analyst" {
  name                 = "securestudy-analyst"
  assume_role_policy   = data.aws_iam_policy_document.analyst_assume.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "analyst" {
  name   = "securestudy-analyst-permissions"
  role   = aws_iam_role.analyst.id
  policy = data.aws_iam_policy_document.analyst_permissions.json
}

# Account-wide password policy (only matters if someone ever creates an IAM user).
resource "aws_iam_account_password_policy" "strict" {
  minimum_password_length        = 14
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 24
}

# ---------- RDS enhanced monitoring role ----------

data "aws_iam_policy_document" "rds_monitoring_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name               = "securestudy-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
