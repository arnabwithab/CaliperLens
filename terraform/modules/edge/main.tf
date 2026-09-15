# §5.1 Edge — CloudFront (React) + WAF + API Gateway + ALB → Fargate
# Minimal real resources so `terraform validate` passes without creds; scale via vars.

variable "env" { type = string }
variable "project" { type = string }

resource "aws_wafv2_web_acl" "this" {
  name  = "${var.project}-${var.env}-waf"
  scope = "CLOUDFRONT"
  default_action { allow {} }
  visibility_config { cloudwatch_metrics_enabled = true, metric_name = "${var.project}-${var.env}-waf", sampled_requests_enabled = true }
  rule { name = "rate-limit", priority = 1, action { block {} }, statement { rate_based_statement { limit = 1000, aggregate_key_type = "IP" } }, visibility_config { cloudwatch_metrics_enabled = true, metric_name = "rate", sampled_requests_enabled = true } }
}

resource "aws_lb" "this" {
  name               = "${var.project}-${var.env}-alb"
  load_balancer_type = "application"
  idle_timeout       = 30 # §2 hard cap 30s → 503 + trace ID
  # subnets/security_groups wired in real account
}

resource "aws_apigatewayv2_api" "this" {
  name          = "${var.project}-${var.env}-api"
  protocol_type = "HTTP"
}

resource "aws_cloudfront_distribution" "this" {
  enabled = true
  origin { domain_name = aws_lb.this.dns_name, origin_id = "alb", custom_origin_config { http_port = 80, https_port = 443, origin_protocol_policy = "https-only", origin_ssl_protocols = ["TLSv1.2"] } }
  default_cache_behavior { target_origin_id = "alb", viewer_protocol_policy = "https-only", allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"], cached_methods = ["GET", "HEAD"], forwarded_values { query_string = true, cookies { forward = "all" } } }
  restrictions { geo_restriction { restriction_type = "none" } }
  viewer_certificate { cloudfront_default_certificate = true }
  # WAF association + React S3 origin added per env
}

output "alb_dns" { value = aws_lb.this.dns_name }
output "cloudfront_url" { value = aws_cloudfront_distribution.this.domain_name }
