# One architecture, two sizings (§4). Sizes flip via tfvars, no code rewrite.
# Local parity (§10): this stack is AWS prod only — `make dev`/`docker-compose` stays local.

module "edge" {
  source = "./modules/edge"
  env     = var.env
  project = var.project
}

module "identity" {
  source = "./modules/identity"
  env     = var.env
  project = var.project
}

module "data" {
  source            = "./modules/data"
  env               = var.env
  project           = var.project
  pg_instance_class = var.pg_instance_class
  pg_replica_count  = var.pg_replica_count
  rds_proxy_cap     = var.rds_proxy_cap
  kms_key_id        = module.identity.kms_key_id
}

module "serve" {
  source                   = "./modules/serve"
  env                      = var.env
  project                  = var.project
  fargate_min              = var.fargate_min
  fargate_max              = var.fargate_max
  fargate_cpu              = var.fargate_cpu
  fargate_streams_per_task = var.fargate_streams_per_task
  bedrock_tpm              = var.bedrock_tpm
  db_proxy_endpoint        = module.data.proxy_endpoint
  db_name                  = module.data.db_name
  kms_key_id               = module.identity.kms_key_id
  cognito_user_pool_id     = module.identity.cognito_user_pool_id
}

module "sandbox" {
  source          = "./modules/sandbox"
  env             = var.env
  project         = var.project
  lambda_reserved = var.lambda_reserved
  lambda_timeout  = var.lambda_timeout
  lambda_memory   = var.lambda_memory
}

module "o11y" {
  source  = "./modules/o11y"
  env     = var.env
  project = var.project
}
