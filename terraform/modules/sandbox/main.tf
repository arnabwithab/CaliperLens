# §5.10 Lambda sandbox — payload rows only (≤200KB), zero S3/DB access, 512MB/30s
variable "env" { type = string }
variable "project" { type = string }
variable "lambda_reserved" { type = number }
variable "lambda_timeout" { type = number }
variable "lambda_memory" { type = number }

resource "aws_iam_role" "lambda" {
  name               = "${var.project}-${var.env}-sandbox"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }] })
  # NO S3 or DB policy — second data path cannot exist (§5.10)
}

resource "aws_lambda_function" "sandbox" {
  function_name = "${var.project}-${var.env}-sandbox"
  role          = aws_iam_role.lambda.arn
  package_type  = "Zip"
  filename      = "dummy.zip" # real image/layer built via CI + ECR
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory
  # no VPC egress, base64 PNG returned, matplotlib layer baked in
}

resource "aws_lambda_provisioned_concurrency_config" "this" {
  count                             = var.lambda_reserved > 0 ? 1 : 0
  function_name                     = aws_lambda_function.sandbox.function_name
  provisioned_concurrent_executions = var.lambda_reserved
  qualifier                         = aws_lambda_function.sandbox.version
}
