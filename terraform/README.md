# Terraform — CaliperLens AWS prod

`architecture.md` §3-§10, one architecture two sizings (§4). `docker-compose.yaml` stays local — this stack is AWS prod only.

## Layout

```
terraform/
  envs/pilot.tfvars   # 1×0.5 vCPU, db.t4g.medium, Lambda 10
  envs/prod.tfvars    # 3-10×1 vCPU, db.r6g.large+replica, Lambda 100, 150k TPM
  modules/{edge,serve,data,sandbox,identity,o11y}
```

## Usage

```bash
make tf-init   # terraform init (once)
make tf-plan ENV=pilot   # plan pilot; ENV=prod for full sizing
make tf-apply ENV=pilot  # apply (needs AWS creds + BAA)
make tf-fmt    # fmt -check
```

Remote state (`backend.tf`) is S3 + DynamoDB + KMS

Parity seams (§10): same container image, same `LLM_BACKEND=bedrock`/`AUTH_BACKEND=cognito`/`VECTOR_BACKEND=pgvector` flags that local runs with `=local`. `terraform plan` never touches `make dev`.
