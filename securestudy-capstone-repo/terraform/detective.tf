############################################
# Managed detection: GuardDuty (threat detection), Security Hub (benchmark
# checks), IAM Access Analyzer (external-sharing findings), AWS Config (drift).
############################################

resource "aws_guardduty_detector" "main" {
  # checkov:skip=CKV2_AWS_3:Single-account project; the check wants an AWS Organizations-wide GuardDuty configuration, which needs a management account
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
  }
}

# Send high-severity GuardDuty findings to the same alert topic.
resource "aws_cloudwatch_event_rule" "guardduty_high" {
  name        = "securestudy-guardduty-high"
  description = "GuardDuty findings with severity 7 or above"
  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
    detail        = { severity = [{ numeric = [">=", 7] }] }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_high" {
  rule = aws_cloudwatch_event_rule.guardduty_high.name
  arn  = aws_sns_topic.alerts.arn
}

resource "aws_securityhub_account" "main" {}

resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0"
  depends_on    = [aws_securityhub_account.main]
}

resource "aws_accessanalyzer_analyzer" "main" {
  analyzer_name = "securestudy-analyzer"
  type          = "ACCOUNT"
}
