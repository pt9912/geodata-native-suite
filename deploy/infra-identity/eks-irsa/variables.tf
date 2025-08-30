
variable "aws_region" { type = string }
variable "cluster_name" { type = string }
variable "s3_bucket" { type = string }
variable "s3_prefix" { type = string  default = "" }
variable "secrets_manager_arns" { type = list(string)  default = [] }
variable "zone_ids" { type = list(string) default = [] } # Route53 Hosted Zone IDs
