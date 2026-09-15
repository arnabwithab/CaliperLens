# Remote state — S3 + DynamoDB lock, KMS. Uncomment when AWS account is ready.
# terraform {
#   backend "s3" {
#     bucket         = "caliperlens-terraform-state"
#     key            = "caliperlens/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "caliperlens-terraform-lock"
#     encrypt        = true
#     kms_key_id     = "alias/caliperlens-terraform"
#   }
# }
