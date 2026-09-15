# §5.2 Cognito (per-org groups → org_id) + §5.11 KMS + Secrets Manager + §5.13 service identity
variable "env" { type = string }
variable "project" { type = string }

resource "aws_kms_key" "this" {
  description             = "${var.project}-${var.env} CMK — Aurora, S3, Logs"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "this" { name = "alias/${var.project}-${var.env}", target_key_id = aws_kms_key.this.key_id }

resource "aws_secretsmanager_secret" "db" {
  name       = "${var.project}/${var.env}/db"
  kms_key_id = aws_kms_key.this.id
}

resource "aws_cognito_user_pool" "this" {
  name = "${var.project}-${var.env}"
  # one group per clinic → org_id claim; JWKS cached on Fargate, 30m/7d TTL
  # groups created per org outside TF or via for_each over var.orgs
}

resource "aws_iam_role" "fargate_task" {
  name = "${var.project}-${var.env}-fargate-task"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" } }] })
  # Bedrock invoke via VPC endpoint — no API keys, IAM only (§5.11)
}

output "kms_key_id" { value = aws_kms_key.this.id }
output "cognito_user_pool_id" { value = aws_cognito_user_pool.this.id }
