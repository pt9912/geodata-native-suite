
# EKS IRSA – IAM Rollen für ServiceAccounts

Dieses Modul erstellt IAM-Rollen für:
- `external-dns` (Namespace `external-dns`) → Route53-Zugriff
- `fetch` (Namespace `geodata`) → S3-Read und Secrets Manager Read
- `index-service` (Namespace `geodata`) → S3-Read und Secrets Manager Read

## Nutzung
```bash
terraform init
terraform apply -var='cluster_name=geodata-eks' -var='aws_region=eu-central-1'   -var='s3_bucket=data-bucket' -var='s3_prefix=cache/'   -var='secrets_manager_arns=["arn:aws:secretsmanager:eu-central-1:123456789012:secret:nasa/edl/token-*"]'   -var='zone_ids=["Z123456789ABCDEFG"]'
```
> Tipp: `zone_ids` bitte hart begrenzen (Least Privilege).
