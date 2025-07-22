# Random suffix for unique resource naming
resource "random_password" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Get current AWS account ID and caller identity
data "aws_caller_identity" "current" {}

# Get availability zones for primary region
data "aws_availability_zones" "primary" {
  provider = aws.primary
  state    = "available"
}

# Get availability zones for secondary region
data "aws_availability_zones" "secondary" {
  provider = aws.secondary
  state    = "available"
}

# Local values for resource naming and configuration
locals {
  suffix                   = random_password.suffix.result
  primary_cluster_name     = "${var.project_name}-primary-${local.suffix}"
  secondary_cluster_name   = "${var.project_name}-secondary-${local.suffix}"
  primary_vpc_name         = "${var.project_name}-vpc-primary-${local.suffix}"
  secondary_vpc_name       = "${var.project_name}-vpc-secondary-${local.suffix}"
  primary_tgw_name         = "${var.project_name}-tgw-primary-${local.suffix}"
  secondary_tgw_name       = "${var.project_name}-tgw-secondary-${local.suffix}"
  service_network_name     = "${var.project_name}-service-network-${local.suffix}"
  
  # Subnet configurations
  primary_public_subnets   = [
    cidrsubnet(var.primary_vpc_cidr, 8, 1),   # 10.1.1.0/24
    cidrsubnet(var.primary_vpc_cidr, 8, 2)    # 10.1.2.0/24
  ]
  primary_private_subnets  = [
    cidrsubnet(var.primary_vpc_cidr, 8, 3),   # 10.1.3.0/24
    cidrsubnet(var.primary_vpc_cidr, 8, 4)    # 10.1.4.0/24
  ]
  secondary_public_subnets = [
    cidrsubnet(var.secondary_vpc_cidr, 8, 1), # 10.2.1.0/24
    cidrsubnet(var.secondary_vpc_cidr, 8, 2)  # 10.2.2.0/24
  ]
  secondary_private_subnets = [
    cidrsubnet(var.secondary_vpc_cidr, 8, 3), # 10.2.3.0/24
    cidrsubnet(var.secondary_vpc_cidr, 8, 4)  # 10.2.4.0/24
  ]
  
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Recipe      = "multi-cluster-eks-cross-region"
    },
    var.additional_tags
  )
}

#################################
# IAM Roles for EKS Clusters
#################################

# EKS Cluster Service Role
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.project_name}-eks-cluster-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# EKS Node Group Service Role
resource "aws_iam_role" "eks_nodegroup_role" {
  name = "${var.project_name}-eks-nodegroup-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodegroup_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodegroup_role.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodegroup_role.name
}

#################################
# Primary Region Infrastructure
#################################

# Primary VPC using AWS VPC module
module "primary_vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  
  providers = {
    aws = aws.primary
  }

  name = local.primary_vpc_name
  cidr = var.primary_vpc_cidr

  azs             = slice(data.aws_availability_zones.primary.names, 0, 2)
  public_subnets  = local.primary_public_subnets
  private_subnets = local.primary_private_subnets

  enable_nat_gateway     = true
  single_nat_gateway     = false  # Multiple NAT gateways for HA
  enable_vpn_gateway     = false
  enable_dns_hostnames   = true
  enable_dns_support     = true
  
  # Enable VPC Flow Logs for monitoring
  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true

  # Kubernetes specific tags for subnet discovery
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
    "kubernetes.io/cluster/${local.primary_cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "kubernetes.io/cluster/${local.primary_cluster_name}" = "shared"
  }

  tags = local.common_tags
}

# Primary Transit Gateway
resource "aws_ec2_transit_gateway" "primary" {
  provider = aws.primary
  
  description                     = "Primary region Transit Gateway"
  amazon_side_asn                = var.transit_gateway_amazon_side_asn.primary
  auto_accept_shared_attachments = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"

  tags = merge(local.common_tags, {
    Name = local.primary_tgw_name
  })
}

# Primary Transit Gateway VPC Attachment
resource "aws_ec2_transit_gateway_vpc_attachment" "primary" {
  provider = aws.primary
  
  subnet_ids         = module.primary_vpc.private_subnets
  transit_gateway_id = aws_ec2_transit_gateway.primary.id
  vpc_id             = module.primary_vpc.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.primary_tgw_name}-vpc-attachment"
  })
}

#################################
# Secondary Region Infrastructure
#################################

# Secondary VPC using AWS VPC module
module "secondary_vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  
  providers = {
    aws = aws.secondary
  }

  name = local.secondary_vpc_name
  cidr = var.secondary_vpc_cidr

  azs             = slice(data.aws_availability_zones.secondary.names, 0, 2)
  public_subnets  = local.secondary_public_subnets
  private_subnets = local.secondary_private_subnets

  enable_nat_gateway     = true
  single_nat_gateway     = false  # Multiple NAT gateways for HA
  enable_vpn_gateway     = false
  enable_dns_hostnames   = true
  enable_dns_support     = true
  
  # Enable VPC Flow Logs for monitoring
  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true

  # Kubernetes specific tags for subnet discovery
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
    "kubernetes.io/cluster/${local.secondary_cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "kubernetes.io/cluster/${local.secondary_cluster_name}" = "shared"
  }

  tags = local.common_tags
}

# Secondary Transit Gateway
resource "aws_ec2_transit_gateway" "secondary" {
  provider = aws.secondary
  
  description                     = "Secondary region Transit Gateway"
  amazon_side_asn                = var.transit_gateway_amazon_side_asn.secondary
  auto_accept_shared_attachments = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"

  tags = merge(local.common_tags, {
    Name = local.secondary_tgw_name
  })
}

# Secondary Transit Gateway VPC Attachment
resource "aws_ec2_transit_gateway_vpc_attachment" "secondary" {
  provider = aws.secondary
  
  subnet_ids         = module.secondary_vpc.private_subnets
  transit_gateway_id = aws_ec2_transit_gateway.secondary.id
  vpc_id             = module.secondary_vpc.vpc_id

  tags = merge(local.common_tags, {
    Name = "${local.secondary_tgw_name}-vpc-attachment"
  })
}

#################################
# Cross-Region Transit Gateway Peering
#################################

# Transit Gateway Peering Connection
resource "aws_ec2_transit_gateway_peering_attachment" "cross_region" {
  provider = aws.primary
  
  peer_region             = var.secondary_region
  peer_transit_gateway_id = aws_ec2_transit_gateway.secondary.id
  transit_gateway_id      = aws_ec2_transit_gateway.primary.id

  tags = merge(local.common_tags, {
    Name = "multi-cluster-tgw-peering"
  })
}

# Accept peering connection in secondary region
resource "aws_ec2_transit_gateway_peering_attachment_accepter" "cross_region" {
  provider = aws.secondary
  
  transit_gateway_peering_attachment_id = aws_ec2_transit_gateway_peering_attachment.cross_region.id

  tags = merge(local.common_tags, {
    Name = "multi-cluster-tgw-peering-accepter"
  })
}

# Wait for peering attachment to be available
resource "time_sleep" "wait_for_peering" {
  depends_on = [aws_ec2_transit_gateway_peering_attachment_accepter.cross_region]
  create_duration = "60s"
}

# Primary Transit Gateway route to secondary region
resource "aws_ec2_transit_gateway_route" "primary_to_secondary" {
  provider = aws.primary
  
  destination_cidr_block         = var.secondary_vpc_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.cross_region.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.primary.association_default_route_table_id

  depends_on = [time_sleep.wait_for_peering]
}

# Secondary Transit Gateway route to primary region
resource "aws_ec2_transit_gateway_route" "secondary_to_primary" {
  provider = aws.secondary
  
  destination_cidr_block         = var.primary_vpc_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.cross_region.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.secondary.association_default_route_table_id

  depends_on = [time_sleep.wait_for_peering]
}

#################################
# EKS Clusters
#################################

# Primary EKS Cluster using AWS EKS module
module "primary_eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"
  
  providers = {
    aws = aws.primary
  }

  cluster_name    = local.primary_cluster_name
  cluster_version = var.kubernetes_version

  cluster_endpoint_private_access      = var.cluster_endpoint_private_access
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # VPC configuration
  vpc_id                   = module.primary_vpc.vpc_id
  subnet_ids               = concat(module.primary_vpc.private_subnets, module.primary_vpc.public_subnets)
  control_plane_subnet_ids = module.primary_vpc.private_subnets

  # IAM role configuration
  create_iam_role = false
  iam_role_arn    = aws_iam_role.eks_cluster_role.arn

  # Control plane logging
  cluster_enabled_log_types = var.enable_control_plane_logging ? var.control_plane_log_types : []

  # EKS Managed Node Groups
  eks_managed_node_groups = {
    primary_nodes = {
      name = "primary-nodes"

      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type

      min_size     = var.node_scaling_config.min_size
      max_size     = var.node_scaling_config.max_size
      desired_size = var.node_scaling_config.desired_size

      # Launch template configuration
      create_launch_template = false
      launch_template_name   = ""

      # Node group configuration
      create_iam_role = false
      iam_role_arn    = aws_iam_role.eks_nodegroup_role.arn

      # Use private subnets for worker nodes
      subnet_ids = module.primary_vpc.private_subnets

      # Security groups
      create_security_group = true

      # Node labels and taints
      labels = {
        Environment = var.environment
        Region      = var.primary_region
        NodeGroup   = "primary-nodes"
      }

      # User data for node configuration
      pre_bootstrap_user_data = <<-EOT
        #!/bin/bash
        /etc/eks/bootstrap.sh ${local.primary_cluster_name}
      EOT

      tags = merge(local.common_tags, {
        Name = "${local.primary_cluster_name}-nodes"
      })
    }
  }

  # Add-ons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  # Security group rules
  node_security_group_additional_rules = {
    # Allow worker nodes to communicate with each other
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    
    # Allow communication from secondary region VPC
    ingress_secondary_vpc = {
      description = "Allow traffic from secondary VPC"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      cidr_blocks = [var.secondary_vpc_cidr]
    }
  }

  tags = local.common_tags
}

# Secondary EKS Cluster using AWS EKS module
module "secondary_eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"
  
  providers = {
    aws = aws.secondary
  }

  cluster_name    = local.secondary_cluster_name
  cluster_version = var.kubernetes_version

  cluster_endpoint_private_access      = var.cluster_endpoint_private_access
  cluster_endpoint_public_access       = var.cluster_endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # VPC configuration
  vpc_id                   = module.secondary_vpc.vpc_id
  subnet_ids               = concat(module.secondary_vpc.private_subnets, module.secondary_vpc.public_subnets)
  control_plane_subnet_ids = module.secondary_vpc.private_subnets

  # IAM role configuration
  create_iam_role = false
  iam_role_arn    = aws_iam_role.eks_cluster_role.arn

  # Control plane logging
  cluster_enabled_log_types = var.enable_control_plane_logging ? var.control_plane_log_types : []

  # EKS Managed Node Groups
  eks_managed_node_groups = {
    secondary_nodes = {
      name = "secondary-nodes"

      instance_types = var.node_instance_types
      capacity_type  = var.node_capacity_type

      min_size     = var.node_scaling_config.min_size
      max_size     = var.node_scaling_config.max_size
      desired_size = var.node_scaling_config.desired_size

      # Launch template configuration
      create_launch_template = false
      launch_template_name   = ""

      # Node group configuration
      create_iam_role = false
      iam_role_arn    = aws_iam_role.eks_nodegroup_role.arn

      # Use private subnets for worker nodes
      subnet_ids = module.secondary_vpc.private_subnets

      # Security groups
      create_security_group = true

      # Node labels and taints
      labels = {
        Environment = var.environment
        Region      = var.secondary_region
        NodeGroup   = "secondary-nodes"
      }

      # User data for node configuration
      pre_bootstrap_user_data = <<-EOT
        #!/bin/bash
        /etc/eks/bootstrap.sh ${local.secondary_cluster_name}
      EOT

      tags = merge(local.common_tags, {
        Name = "${local.secondary_cluster_name}-nodes"
      })
    }
  }

  # Add-ons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  # Security group rules
  node_security_group_additional_rules = {
    # Allow worker nodes to communicate with each other
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    
    # Allow communication from primary region VPC
    ingress_primary_vpc = {
      description = "Allow traffic from primary VPC"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      cidr_blocks = [var.primary_vpc_cidr]
    }
  }

  tags = local.common_tags
}

#################################
# VPC Lattice Service Network (Optional)
#################################

# VPC Lattice Service Network for cross-cluster service discovery
resource "aws_vpclattice_service_network" "multi_cluster" {
  count = var.enable_vpc_lattice ? 1 : 0
  
  provider = aws.primary
  
  name      = local.service_network_name
  auth_type = var.vpc_lattice_auth_type

  tags = merge(local.common_tags, {
    Name = local.service_network_name
  })
}

# Associate primary VPC with service network
resource "aws_vpclattice_service_network_vpc_association" "primary" {
  count = var.enable_vpc_lattice ? 1 : 0
  
  provider = aws.primary
  
  vpc_identifier             = module.primary_vpc.vpc_id
  service_network_identifier = aws_vpclattice_service_network.multi_cluster[0].id

  tags = merge(local.common_tags, {
    Name = "${local.service_network_name}-primary-vpc"
  })
}

# Associate secondary VPC with service network
resource "aws_vpclattice_service_network_vpc_association" "secondary" {
  count = var.enable_vpc_lattice ? 1 : 0
  
  provider = aws.primary
  
  vpc_identifier             = module.secondary_vpc.vpc_id
  service_network_identifier = aws_vpclattice_service_network.multi_cluster[0].id

  tags = merge(local.common_tags, {
    Name = "${local.service_network_name}-secondary-vpc"
  })
}

#################################
# Route 53 Health Checks (Optional)
#################################

# Health check for primary region
resource "aws_route53_health_check" "primary" {
  count = var.create_route53_health_checks && var.health_check_fqdn_primary != "" ? 1 : 0
  
  fqdn                            = var.health_check_fqdn_primary
  port                            = 80
  type                            = "HTTP"
  resource_path                   = "/"
  failure_threshold               = 3
  request_interval                = 30
  cloudwatch_logs_region          = var.primary_region
  cloudwatch_alarm_region         = var.primary_region
  insufficient_data_health_status = "Failure"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-primary-health-check"
  })
}

# Health check for secondary region
resource "aws_route53_health_check" "secondary" {
  count = var.create_route53_health_checks && var.health_check_fqdn_secondary != "" ? 1 : 0
  
  fqdn                            = var.health_check_fqdn_secondary
  port                            = 80
  type                            = "HTTP"
  resource_path                   = "/"
  failure_threshold               = 3
  request_interval                = 30
  cloudwatch_logs_region          = var.secondary_region
  cloudwatch_alarm_region         = var.secondary_region
  insufficient_data_health_status = "Failure"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-secondary-health-check"
  })
}