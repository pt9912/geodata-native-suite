
data "aws_eks_cluster" "this" { name = var.cluster_name }
data "aws_eks_cluster_auth" "this" { name = var.cluster_name }
data "aws_iam_openid_connect_provider" "this" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

locals {
  oidc_issuer       = replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
  sa_external_dns   = "system:serviceaccount:external-dns:external-dns"
  sa_fetch          = "system:serviceaccount:geodata:fetch"
  sa_index          = "system:serviceaccount:geodata:index-service"
}

# ---------- IAM Role: external-dns ----------
data "aws_iam_policy_document" "assume_external_dns" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = [local.sa_external_dns]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.this.arn]
    }
  }
}

resource "aws_iam_role" "external_dns" {
  name               = "geodata-external-dns-irsa"
  assume_role_policy = data.aws_iam_policy_document.assume_external_dns.json
}

data "aws_iam_policy_document" "external_dns_route53" {
  statement {
    sid     = "ListZones"
    effect  = "Allow"
    actions = ["route53:ListHostedZones", "route53:ListHostedZonesByName", "route53:ListResourceRecordSets"]
    resources = ["*"]
  }
  statement {
    sid     = "ChangeRecords"
    effect  = "Allow"
    actions = ["route53:ChangeResourceRecordSets"]
    resources = [for z in var.zone_ids : "arn:aws:route53:::hostedzone/${z}"]
  }
}

resource "aws_iam_policy" "external_dns_route53" {
  name   = "geodata-external-dns-route53"
  policy = data.aws_iam_policy_document.external_dns_route53.json
}

resource "aws_iam_role_policy_attachment" "attach_extdns" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns_route53.arn
}

# ---------- IAM Role: fetch (S3 + Secrets Manager) ----------
data "aws_iam_policy_document" "assume_fetch" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = [local.sa_fetch]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.this.arn]
    }
  }
}

resource "aws_iam_role" "fetch" {
  name               = "geodata-fetch-irsa"
  assume_role_policy = data.aws_iam_policy_document.assume_fetch.json
}

data "aws_iam_policy_document" "fetch_policy" {
  statement {
    sid     = "ReadS3"
    effect  = "Allow"
    actions = ["s3:GetObject","s3:ListBucket"]
    resources = [
      "arn:aws:s3:::${var.s3_bucket}",
      "arn:aws:s3:::${var.s3_bucket}/${var.s3_prefix}*"
    ]
  }
  statement {
    sid     = "ReadSecretsManager"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue","secretsmanager:DescribeSecret"]
    resources = var.secrets_manager_arns
  }
}

resource "aws_iam_policy" "fetch" {
  name   = "geodata-fetch-policy"
  policy = data.aws_iam_policy_document.fetch_policy.json
}

resource "aws_iam_role_policy_attachment" "attach_fetch" {
  role       = aws_iam_role.fetch.name
  policy_arn = aws_iam_policy.fetch.arn
}

# ---------- IAM Role: index-service (S3 + Secrets Manager) ----------
data "aws_iam_policy_document" "assume_index" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = [local.sa_index]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.this.arn]
    }
  }
}

resource "aws_iam_role" "index" {
  name               = "geodata-index-irsa"
  assume_role_policy = data.aws_iam_policy_document.assume_index.json
}

resource "aws_iam_policy" "index" {
  name   = "geodata-index-policy"
  policy = data.aws_iam_policy_document.fetch_policy.json
}

resource "aws_iam_role_policy_attachment" "attach_index" {
  role       = aws_iam_role.index.name
  policy_arn = aws_iam_policy.index.arn
}

output "irsa_roles" {
  value = {
    external_dns = aws_iam_role.external_dns.arn
    fetch        = aws_iam_role.fetch.arn
    index        = aws_iam_role.index.arn
  }
}
