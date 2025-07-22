# Cluster Information
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_iam_role_name" {
  description = "IAM role name associated with EKS cluster"
  value       = module.eks.cluster_iam_role_name
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN associated with EKS cluster"
  value       = module.eks.cluster_iam_role_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_version" {
  description = "The Kubernetes version for the EKS cluster"
  value       = module.eks.cluster_version
}

output "cluster_platform_version" {
  description = "Platform version for the EKS cluster"
  value       = module.eks.cluster_platform_version
}

output "cluster_status" {
  description = "Status of the EKS cluster. One of `CREATING`, `ACTIVE`, `DELETING`, `FAILED`"
  value       = module.eks.cluster_status
}

# VPC Information
output "vpc_id" {
  description = "ID of the VPC where the cluster security group is located"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "nat_gateway_ids" {
  description = "List of IDs of the NAT Gateways"
  value       = module.vpc.natgw_ids
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway"
  value       = module.vpc.igw_id
}

# Node Group Information
output "node_groups" {
  description = "Map of attribute maps for all EKS managed node groups created"
  value       = module.eks.eks_managed_node_groups
  sensitive   = true
}

output "node_security_group_id" {
  description = "ID of the node shared security group"
  value       = module.eks.node_security_group_id
}

# OIDC Provider Information
output "oidc_provider" {
  description = "The OpenID Connect identity provider (issuer URL without leading `https://`)"
  value       = module.eks.oidc_provider
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider if `enable_irsa = true`"
  value       = module.eks.oidc_provider_arn
}

# App Mesh Information
output "mesh_name" {
  description = "Name of the App Mesh service mesh"
  value       = aws_appmesh_mesh.service_mesh.name
}

output "mesh_id" {
  description = "ID of the App Mesh service mesh"
  value       = aws_appmesh_mesh.service_mesh.id
}

output "mesh_arn" {
  description = "ARN of the App Mesh service mesh"
  value       = aws_appmesh_mesh.service_mesh.arn
}

output "mesh_resource_owner" {
  description = "Resource owner of the App Mesh service mesh"
  value       = aws_appmesh_mesh.service_mesh.resource_owner
}

# ECR Repository Information
output "ecr_repository_urls" {
  description = "Map of ECR repository URLs"
  value = var.create_ecr_repositories ? {
    for name, repo in aws_ecr_repository.app_repos : name => repo.repository_url
  } : {}
}

output "ecr_repository_arns" {
  description = "Map of ECR repository ARNs"
  value = var.create_ecr_repositories ? {
    for name, repo in aws_ecr_repository.app_repos : name => repo.arn
  } : {}
}

# IAM Role ARNs
output "appmesh_controller_role_arn" {
  description = "ARN of the App Mesh Controller IAM role"
  value       = module.appmesh_controller_irsa_role.iam_role_arn
}

output "load_balancer_controller_role_arn" {
  description = "ARN of the AWS Load Balancer Controller IAM role"
  value       = module.load_balancer_controller_irsa_role.iam_role_arn
}

output "app_pods_role_arn" {
  description = "ARN of the application pods IAM role"
  value       = module.app_pods_irsa_role.iam_role_arn
}

output "ebs_csi_driver_role_arn" {
  description = "ARN of the EBS CSI driver IAM role"
  value       = module.ebs_csi_irsa_role.iam_role_arn
}

# Application Namespace
output "application_namespace" {
  description = "Kubernetes namespace for the demo applications"
  value       = kubernetes_namespace.app_namespace.metadata[0].name
}

# Helm Release Information
output "appmesh_controller_status" {
  description = "Status of the App Mesh Controller Helm release"
  value       = helm_release.appmesh_controller.status
}

output "aws_load_balancer_controller_status" {
  description = "Status of the AWS Load Balancer Controller Helm release"
  value       = helm_release.aws_load_balancer_controller.status
}

output "cloudwatch_agent_status" {
  description = "Status of the CloudWatch Agent Helm release"
  value       = var.enable_container_insights ? helm_release.cloudwatch_agent[0].status : "disabled"
}

output "fluent_bit_status" {
  description = "Status of the Fluent Bit Helm release"
  value       = var.enable_container_insights ? helm_release.fluent_bit[0].status : "disabled"
}

# Configuration Information
output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "region" {
  description = "AWS region"
  value       = var.aws_region
}

output "account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

# Network Security
output "additional_node_security_group_id" {
  description = "ID of the additional security group for worker nodes"
  value       = aws_security_group.node_group_additional.id
}

# Monitoring and Observability
output "xray_tracing_enabled" {
  description = "Whether X-Ray tracing is enabled"
  value       = var.enable_xray_tracing
}

output "container_insights_enabled" {
  description = "Whether CloudWatch Container Insights is enabled"
  value       = var.enable_container_insights
}

# Deployment Configuration
output "canary_deployment_enabled" {
  description = "Whether canary deployment is enabled"
  value       = var.enable_canary_deployment
}

output "traffic_weights" {
  description = "Traffic distribution configuration"
  value = {
    primary = local.primary_weight
    canary  = local.canary_weight
  }
}

# Service Accounts
output "service_account_names" {
  description = "Names of created Kubernetes service accounts"
  value = {
    for sa_name, sa in kubernetes_service_account.app_service_accounts : sa_name => sa.metadata[0].name
  }
}

# Tags
output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.tags
}

# Random Suffix
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Complete Resource Names
output "resource_names" {
  description = "Complete names of major resources"
  value = {
    cluster_name    = local.name
    mesh_name      = aws_appmesh_mesh.service_mesh.name
    vpc_name       = "${local.name}-vpc"
    namespace_name = var.app_namespace
  }
}