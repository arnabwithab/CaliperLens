variable "aws_region" { type = string, default = "us-east-1" }
variable "env" { type = string, default = "pilot", description = "pilot or prod — §4 two sizings" }
variable "project" { type = string, default = "caliperlens" }

# §4 pilot vs full sizing — flipped via tfvars, nothing rewritten
variable "fargate_min" { type = number, default = 1 }
variable "fargate_max" { type = number, default = 3 }
variable "fargate_cpu" { type = string, default = "512" } # 0.5 vCPU pilot, 1024 prod
variable "fargate_streams_per_task" { type = number, default = 15 }

variable "pg_instance_class" { type = string, default = "db.t4g.medium" } # prod: db.r6g.large
variable "pg_replica_count" { type = number, default = 0 }                # prod: 1
variable "rds_proxy_cap" { type = number, default = 50 }

variable "bedrock_tpm" { type = number, default = 150000 } # §5.5 math
variable "lambda_reserved" { type = number, default = 10 } # prod: 100
variable "lambda_timeout" { type = number, default = 30 }
variable "lambda_memory" { type = number, default = 512 }
