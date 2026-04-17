# ----------------------------------------------------------------------------
# aws-eks module - main.tf
#
# Provisions a private-control-plane EKS cluster with:
#   - VPC, private and intra subnets across AZs, NAT gateways
#   - KMS keys for EKS secrets + EBS volumes
#   - EKS cluster (private API by default) with IRSA enabled
#   - System and GPU managed node groups
#   - VPC Interface Endpoints for ECR / STS / EC2 / SSM / S3 gateway
#   - Private ECR repository for image mirroring
# ----------------------------------------------------------------------------

locals {
  cluster_name = "${var.name_prefix}-eks"

  base_tags = merge(var.tags, {
    "module" = "aws-eks"
  })

  azs = var.availability_zones
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

resource "random_id" "suffix" {
  byte_length = 3
}

# ----------------------------------------------------------------------------
# VPC
# ----------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.base_tags, {
    "Name" = "${var.name_prefix}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.base_tags, { "Name" = "${var.name_prefix}-igw" })
}

resource "aws_subnet" "public" {
  count                   = length(var.private_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 200 + count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.base_tags, {
    "Name"                                        = "${var.name_prefix}-public-${local.azs[count.index]}"
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  })
}

resource "aws_subnet" "private" {
  count                   = length(var.private_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.base_tags, {
    "Name"                                        = "${var.name_prefix}-private-${local.azs[count.index]}"
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  })
}

resource "aws_subnet" "intra" {
  count             = length(var.intra_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.intra_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.base_tags, {
    "Name" = "${var.name_prefix}-intra-${local.azs[count.index]}"
  })
}

resource "aws_eip" "nat" {
  count  = length(var.private_subnet_cidrs)
  domain = "vpc"
  tags   = merge(local.base_tags, { "Name" = "${var.name_prefix}-nat-${count.index}" })
}

resource "aws_nat_gateway" "this" {
  count         = length(var.private_subnet_cidrs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.base_tags, {
    "Name" = "${var.name_prefix}-nat-${local.azs[count.index]}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.base_tags, { "Name" = "${var.name_prefix}-rt-public" })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }

  tags = merge(local.base_tags, { "Name" = "${var.name_prefix}-rt-private-${local.azs[count.index]}" })
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table" "intra" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.base_tags, { "Name" = "${var.name_prefix}-rt-intra" })
}

resource "aws_route_table_association" "intra" {
  count          = length(aws_subnet.intra)
  subnet_id      = aws_subnet.intra[count.index].id
  route_table_id = aws_route_table.intra.id
}

# ----------------------------------------------------------------------------
# KMS - EKS secrets + EBS
# ----------------------------------------------------------------------------

resource "aws_kms_key" "eks" {
  count                   = var.enable_kms ? 1 : 0
  description             = "EKS envelope encryption for ${local.cluster_name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = merge(local.base_tags, { "Name" = "${var.name_prefix}-eks-kms" })
}

resource "aws_kms_alias" "eks" {
  count         = var.enable_kms ? 1 : 0
  name          = "alias/${var.name_prefix}-eks"
  target_key_id = aws_kms_key.eks[0].id
}

# ----------------------------------------------------------------------------
# VPC endpoints (private connectivity for ECR, STS, S3, etc.)
# ----------------------------------------------------------------------------

resource "aws_security_group" "vpc_endpoints" {
  count       = var.enable_vpc_endpoints ? 1 : 0
  name        = "${var.name_prefix}-vpce-sg"
  description = "Allow HTTPS from the VPC to VPC Interface Endpoints."
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.base_tags, { "Name" = "${var.name_prefix}-vpce-sg" })
}

locals {
  interface_endpoints = var.enable_vpc_endpoints ? [
    "ecr.api",
    "ecr.dkr",
    "sts",
    "ec2",
    "ec2messages",
    "ssm",
    "ssmmessages",
    "logs",
    "secretsmanager",
  ] : []
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(local.interface_endpoints)
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.intra[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.base_tags, { "Name" = "${var.name_prefix}-vpce-${each.key}" })
}

resource "aws_vpc_endpoint" "s3_gateway" {
  count             = var.enable_vpc_endpoints ? 1 : 0
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(aws_route_table.private[*].id, [aws_route_table.intra.id])

  tags = merge(local.base_tags, { "Name" = "${var.name_prefix}-vpce-s3" })
}

# ----------------------------------------------------------------------------
# IAM for EKS control plane and node groups
# ----------------------------------------------------------------------------

data "aws_iam_policy_document" "eks_cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${var.name_prefix}-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume.json
  tags               = local.base_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

data "aws_iam_policy_document" "eks_node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node" {
  name               = "${var.name_prefix}-eks-node"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume.json
  tags               = local.base_tags
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_ssm" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ----------------------------------------------------------------------------
# CloudWatch log group for EKS control plane logging
# ----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = var.enable_kms ? aws_kms_key.eks[0].arn : null
  tags              = local.base_tags
}

# ----------------------------------------------------------------------------
# EKS cluster
# ----------------------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.kubernetes_version

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  vpc_config {
    subnet_ids              = concat(aws_subnet.private[*].id, aws_subnet.intra[*].id)
    endpoint_private_access = true
    endpoint_public_access  = var.public_endpoint_enabled
    public_access_cidrs     = var.public_endpoint_enabled ? var.public_endpoint_cidrs : null
  }

  dynamic "encryption_config" {
    for_each = var.enable_kms ? [1] : []
    content {
      resources = ["secrets"]
      provider {
        key_arn = aws_kms_key.eks[0].arn
      }
    }
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  kubernetes_network_config {
    ip_family         = "ipv4"
    service_ipv4_cidr = "172.20.0.0/16"
  }

  tags = local.base_tags

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_cloudwatch_log_group.eks,
  ]
}

# ----------------------------------------------------------------------------
# IRSA - OIDC provider for the cluster
# ----------------------------------------------------------------------------

data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  tags            = local.base_tags
}

# ----------------------------------------------------------------------------
# Node groups
# ----------------------------------------------------------------------------

resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "system"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = var.system_node_group.instance_types
  ami_type        = "AL2_x86_64"
  capacity_type   = "ON_DEMAND"
  disk_size       = var.system_node_group.disk_size_gb

  scaling_config {
    desired_size = var.system_node_group.desired_size
    min_size     = var.system_node_group.min_size
    max_size     = var.system_node_group.max_size
  }

  update_config {
    max_unavailable_percentage = 33
  }

  labels = {
    "workload" = "system"
  }

  tags = local.base_tags

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

resource "aws_eks_node_group" "gpu" {
  count           = var.gpu_node_group.enabled ? 1 : 0
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "gpu"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = var.gpu_node_group.instance_types
  ami_type        = "AL2_x86_64_GPU"
  capacity_type   = "ON_DEMAND"
  disk_size       = var.gpu_node_group.disk_size_gb

  scaling_config {
    desired_size = var.gpu_node_group.desired_size
    min_size     = var.gpu_node_group.min_size
    max_size     = var.gpu_node_group.max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    "workload" = "llm-inference"
    "gpu"      = "nvidia"
  }

  dynamic "taint" {
    for_each = var.gpu_node_group.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = local.base_tags

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# ----------------------------------------------------------------------------
# Optional: private ECR repository for mirrored images
# ----------------------------------------------------------------------------

resource "aws_ecr_repository" "mirror" {
  count                = var.enable_ecr ? 1 : 0
  name                 = "${var.name_prefix}-llm-stack"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = var.enable_kms ? "KMS" : "AES256"
    kms_key         = var.enable_kms ? aws_kms_key.eks[0].arn : null
  }

  tags = local.base_tags
}
