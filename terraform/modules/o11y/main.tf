# §5.12 Observability — same /metrics name local and AWS, 3 planes
variable "env" { type = string }
variable "project" { type = string }

resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.project}/${var.env}/api"
  retention_in_days = 30
  kms_key_id        = "alias/${var.project}-${var.env}"
  # KMS-encrypted, structured JSON with trace_id/session_id/node — same logger (§10)
}

resource "aws_prometheus_workspace" "amp" {
  alias = "${var.project}-${var.env}"
  # remote-write from /metrics — IAM auth, no self-hosted Prometheus
}

resource "aws_grafana_workspace" "this" {
  account_access_type = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  # dashboards: p95/TTFT/req rate/err rate/cost-per-query/cache hit-rate (§5.12)
}

resource "aws_cloudtrail" "this" {
  name = "${var.project}-${var.env}-trail"
  # S3 + CW Logs, server-access logging on lake bucket (§5.11)
}

# Audit S3 Object Lock + lifecycle 7yr is on the app's audit bucket (§5.12) — see data module lake bucket config.
# LangSmith full tracing is SaaS (BAA) — no AWS resource, flagged via LANGSMITH_TRACING env (§5.12).
