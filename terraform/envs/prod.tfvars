# §4 full sizing — morning-huddle burst ready, same architecture
env               = "prod"
fargate_min       = 3
fargate_max       = 10
fargate_cpu       = "1024" # 1 vCPU
pg_instance_class = "db.r6g.large"
pg_replica_count  = 1
rds_proxy_cap     = 50
bedrock_tpm       = 150000 # §5.5: 50*2*2.5k/2≈125k + headroom
lambda_reserved   = 100
