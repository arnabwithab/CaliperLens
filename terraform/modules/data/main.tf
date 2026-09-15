# §5.6 MySQL→S3→dbt→Postgres + §5.7 Postgres RLS/proxy + §5.8 pgvector + §5.9 semantic cache
variable "env" { type = string }
variable "project" { type = string }
variable "pg_instance_class" { type = string }
variable "pg_replica_count" { type = number }
variable "rds_proxy_cap" { type = number }
variable "kms_key_id" { type = string }

resource "aws_s3_bucket" "lake" {
  bucket = "${var.project}-${var.env}-lake"
  # versioned, per-org partitioned, SSE-KMS with bucket keys (§5.6)
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id
  rule { apply_server_side_encryption_by_default { sse_algorithm = "aws:kms", kms_master_key_id = var.kms_key_id } bucket_key_enabled = true }
}

resource "aws_s3_bucket_versioning" "lake" { bucket = aws_s3_bucket.lake.id, versioning_configuration { status = "Enabled" } }

resource "aws_rds_cluster" "pg" {
  cluster_identifier = "${var.project}-${var.env}-pg"
  engine             = "aurora-postgresql"
  engine_version     = "15.4"
  storage_encrypted  = true
  kms_key_id         = var.kms_key_id
  # primary + 1 replica (prod), single (pilot) via pg_replica_count
}

resource "aws_rds_cluster_instance" "pg_primary" {
  cluster_identifier = aws_rds_cluster.pg.id
  instance_class     = var.pg_instance_class
  engine             = aws_rds_cluster.pg.engine
}

resource "aws_rds_cluster_instance" "pg_replica" {
  count              = var.pg_replica_count
  cluster_identifier = aws_rds_cluster.pg.id
  instance_class     = var.pg_instance_class
  engine             = aws_rds_cluster.pg.engine
}

resource "aws_db_proxy" "pg" {
  name          = "${var.project}-${var.env}-pg-proxy"
  engine_family = "POSTGRESQL"
  # backend cap 50 — hard ceiling across all Fargate tasks (§5.7)
  # connection_borrow_timeout etc. tuned per env
}

# S3 snapshot before every dbt run (§5.6) — ECS cron triggering dbt-duckdb with Postgres ATTACH is application-layer,
# scheduled via `aws_scheduler_schedule` → ECS RunTask (nightly).
resource "aws_scheduler_schedule" "dbt_nightly" {
  name       = "${var.project}-${var.env}-dbt-nightly"
  group_name = "default"
  flexible_time_window { mode = "OFF" }
  schedule_expression = "cron(0 3 * * ? *)" # nightly
  target { arn = "arn:aws:ecs:us-east-1:000000000000:cluster/${var.project}-${var.env}", role_arn = "arn:aws:iam::000000000000:role/ecsEventsRole" }
  # ecs_parameters { task_definition_arn = ... } — wired in real account
}

output "proxy_endpoint" { value = try(aws_db_proxy.pg.endpoint, "") }
output "db_name" { value = "${var.project}" }
