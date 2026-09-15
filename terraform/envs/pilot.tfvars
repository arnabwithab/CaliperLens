# §4 pilot sizing — minimal cost, same code paths
env               = "pilot"
fargate_min       = 1
fargate_max       = 3
fargate_cpu       = "512" # 0.5 vCPU
pg_instance_class = "db.t4g.medium"
pg_replica_count  = 0
rds_proxy_cap     = 50
bedrock_tpm       = 30000 # on-demand pilot quota
lambda_reserved   = 10
