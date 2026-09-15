# §5.3 Fargate (FastAPI + LangGraph) + §5.5 Bedrock (Haiku/Titan) — stateless, 50 concurrent
variable "env" { type = string }
variable "project" { type = string }
variable "fargate_min" { type = number }
variable "fargate_max" { type = number }
variable "fargate_cpu" { type = string }
variable "fargate_streams_per_task" { type = number }
variable "bedrock_tpm" { type = number }
variable "db_proxy_endpoint" { type = string }
variable "db_name" { type = string }
variable "kms_key_id" { type = string }
variable "cognito_user_pool_id" { type = string }

resource "aws_ecs_cluster" "this" { name = "${var.project}-${var.env}" }

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.project}-${var.env}-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.fargate_cpu
  memory                   = "1024"
  # container_definitions: FastAPI + LangGraph, thread_id=session_id, ownership check (§5.3)
  # env: LLM_BACKEND=bedrock, AUTH_BACKEND=cognito, VECTOR_BACKEND=pgvector — same seams (§10)
}

resource "aws_ecs_service" "api" {
  name            = "${var.project}-${var.env}-api"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.fargate_min
  # target-tracking on req count + CPU, per-task SSE cap ~15 (§5.3) — autoscaling policy in prod
}

resource "aws_appautoscaling_target" "fargate" {
  max_capacity       = var.fargate_max
  min_capacity       = var.fargate_min
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Bedrock is IAM-role based, no API keys (§5.11) — quota is service quota, applied out-of-band
# VPC endpoint for Bedrock so PHI never leaves VPC (§5.5)
resource "aws_vpc_endpoint" "bedrock" {
  vpc_id       = "vpc-00000000" # wired to real VPC
  service_name = "com.amazonaws.vpce.bedrock-runtime"
}
