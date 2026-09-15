output "alb_dns" { value = module.edge.alb_dns }
output "cloudfront_url" { value = module.edge.cloudfront_url }
output "cognito_pool_id" { value = module.identity.cognito_user_pool_id }
output "db_proxy_endpoint" { value = module.data.proxy_endpoint }
