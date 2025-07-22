# General outputs
output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.suffix
}

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

# Primary region outputs
output "primary_region" {
  description = "Primary AWS region"
  value       = var.primary_region
}

output "primary_vpc_id" {
  description = "Primary VPC ID"
  value       = module.primary_vpc.vpc_id
}

output "primary_vpc_cidr" {
  description = "Primary VPC CIDR block"
  value       = module.primary_vpc.vpc_cidr_block
}

output "primary_public_subnets" {
  description = "Primary region public subnet IDs"
  value       = module.primary_vpc.public_subnets
}

output "primary_private_subnets" {
  description = "Primary region private subnet IDs"
  value       = module.primary_vpc.private_subnets
}

output "primary_transit_gateway_id" {
  description = "Primary Transit Gateway ID"
  value       = aws_ec2_transit_gateway.primary.id
}

output "primary_transit_gateway_arn" {
  description = "Primary Transit Gateway ARN"
  value       = aws_ec2_transit_gateway.primary.arn
}

# Secondary region outputs
output "secondary_region" {
  description = "Secondary AWS region"
  value       = var.secondary_region
}

output "secondary_vpc_id" {
  description = "Secondary VPC ID"
  value       = module.secondary_vpc.vpc_id
}

output "secondary_vpc_cidr" {
  description = "Secondary VPC CIDR block"
  value       = module.secondary_vpc.vpc_cidr_block
}

output "secondary_public_subnets" {
  description = "Secondary region public subnet IDs"
  value       = module.secondary_vpc.public_subnets
}

output "secondary_private_subnets" {
  description = "Secondary region private subnet IDs"
  value       = module.secondary_vpc.private_subnets
}

output "secondary_transit_gateway_id" {
  description = "Secondary Transit Gateway ID"
  value       = aws_ec2_transit_gateway.secondary.id
}

output "secondary_transit_gateway_arn" {
  description = "Secondary Transit Gateway ARN"
  value       = aws_ec2_transit_gateway.secondary.arn
}

# Cross-region networking outputs
output "transit_gateway_peering_attachment_id" {
  description = "Transit Gateway peering attachment ID"
  value       = aws_ec2_transit_gateway_peering_attachment.cross_region.id
}

output "transit_gateway_peering_attachment_state" {
  description = "Transit Gateway peering attachment state"
  value       = aws_ec2_transit_gateway_peering_attachment.cross_region.state
}

# Primary EKS cluster outputs
output "primary_cluster_id" {
  description = "Primary EKS cluster ID"
  value       = module.primary_eks.cluster_id
}

output "primary_cluster_arn" {
  description = "Primary EKS cluster ARN"
  value       = module.primary_eks.cluster_arn
}

output "primary_cluster_name" {
  description = "Primary EKS cluster name"
  value       = module.primary_eks.cluster_name
}

output "primary_cluster_endpoint" {
  description = "Primary EKS cluster endpoint"
  value       = module.primary_eks.cluster_endpoint
}

output "primary_cluster_version" {
  description = "Primary EKS cluster Kubernetes version"
  value       = module.primary_eks.cluster_version
}

output "primary_cluster_security_group_id" {
  description = "Primary EKS cluster security group ID"
  value       = module.primary_eks.cluster_security_group_id
}

output "primary_cluster_certificate_authority_data" {
  description = "Primary EKS cluster certificate authority data"
  value       = module.primary_eks.cluster_certificate_authority_data
}

output "primary_cluster_oidc_issuer_url" {
  description = "Primary EKS cluster OIDC issuer URL"
  value       = module.primary_eks.cluster_oidc_issuer_url
}

output "primary_node_group_arn" {
  description = "Primary EKS node group ARN"
  value       = module.primary_eks.eks_managed_node_groups["primary_nodes"].node_group_arn
}

output "primary_node_group_status" {
  description = "Primary EKS node group status"
  value       = module.primary_eks.eks_managed_node_groups["primary_nodes"].node_group_status
}

# Secondary EKS cluster outputs
output "secondary_cluster_id" {
  description = "Secondary EKS cluster ID"
  value       = module.secondary_eks.cluster_id
}

output "secondary_cluster_arn" {
  description = "Secondary EKS cluster ARN"
  value       = module.secondary_eks.cluster_arn
}

output "secondary_cluster_name" {
  description = "Secondary EKS cluster name"
  value       = module.secondary_eks.cluster_name
}

output "secondary_cluster_endpoint" {
  description = "Secondary EKS cluster endpoint"
  value       = module.secondary_eks.cluster_endpoint
}

output "secondary_cluster_version" {
  description = "Secondary EKS cluster Kubernetes version"
  value       = module.secondary_eks.cluster_version
}

output "secondary_cluster_security_group_id" {
  description = "Secondary EKS cluster security group ID"
  value       = module.secondary_eks.cluster_security_group_id
}

output "secondary_cluster_certificate_authority_data" {
  description = "Secondary EKS cluster certificate authority data"
  value       = module.secondary_eks.cluster_certificate_authority_data
}

output "secondary_cluster_oidc_issuer_url" {
  description = "Secondary EKS cluster OIDC issuer URL"
  value       = module.secondary_eks.cluster_oidc_issuer_url
}

output "secondary_node_group_arn" {
  description = "Secondary EKS node group ARN"
  value       = module.secondary_eks.eks_managed_node_groups["secondary_nodes"].node_group_arn
}

output "secondary_node_group_status" {
  description = "Secondary EKS node group status"
  value       = module.secondary_eks.eks_managed_node_groups["secondary_nodes"].node_group_status
}

# IAM role outputs
output "eks_cluster_role_arn" {
  description = "EKS cluster service role ARN"
  value       = aws_iam_role.eks_cluster_role.arn
}

output "eks_nodegroup_role_arn" {
  description = "EKS node group service role ARN"
  value       = aws_iam_role.eks_nodegroup_role.arn
}

# VPC Lattice outputs
output "vpc_lattice_service_network_id" {
  description = "VPC Lattice service network ID"
  value       = var.enable_vpc_lattice ? aws_vpclattice_service_network.multi_cluster[0].id : null
}

output "vpc_lattice_service_network_arn" {
  description = "VPC Lattice service network ARN"
  value       = var.enable_vpc_lattice ? aws_vpclattice_service_network.multi_cluster[0].arn : null
}

output "vpc_lattice_service_network_name" {
  description = "VPC Lattice service network name"
  value       = var.enable_vpc_lattice ? aws_vpclattice_service_network.multi_cluster[0].name : null
}

# Route 53 health check outputs
output "primary_health_check_id" {
  description = "Primary region Route 53 health check ID"
  value       = var.create_route53_health_checks && var.health_check_fqdn_primary != "" ? aws_route53_health_check.primary[0].id : null
}

output "secondary_health_check_id" {
  description = "Secondary region Route 53 health check ID"
  value       = var.create_route53_health_checks && var.health_check_fqdn_secondary != "" ? aws_route53_health_check.secondary[0].id : null
}

# kubectl configuration commands
output "kubectl_config_primary" {
  description = "kubectl configuration command for primary cluster"
  value       = "aws eks update-kubeconfig --region ${var.primary_region} --name ${module.primary_eks.cluster_name} --alias primary-cluster"
}

output "kubectl_config_secondary" {
  description = "kubectl configuration command for secondary cluster"
  value       = "aws eks update-kubeconfig --region ${var.secondary_region} --name ${module.secondary_eks.cluster_name} --alias secondary-cluster"
}

# Verification commands
output "verification_commands" {
  description = "Commands to verify the deployment"
  value = {
    primary_cluster_status   = "aws eks describe-cluster --name ${module.primary_eks.cluster_name} --region ${var.primary_region}"
    secondary_cluster_status = "aws eks describe-cluster --name ${module.secondary_eks.cluster_name} --region ${var.secondary_region}"
    primary_nodes           = "kubectl --context=primary-cluster get nodes"
    secondary_nodes         = "kubectl --context=secondary-cluster get nodes"
    tgw_peering_status      = "aws ec2 describe-transit-gateway-peering-attachments --transit-gateway-peering-attachment-ids ${aws_ec2_transit_gateway_peering_attachment.cross_region.id} --region ${var.primary_region}"
  }
}

# Cost estimation information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    eks_clusters          = "~$146 (2 clusters × $73/month)"
    ec2_instances         = "~$142 (6 m5.large instances × $69.12/month)"
    transit_gateways      = "~$73 (2 TGW × $36.50/month)"
    nat_gateways         = "~$91 (4 NAT gateways × $32.85/month + data processing)"
    vpc_lattice          = "~$20-40 (based on service usage)"
    data_transfer        = "~$10-50 (cross-region transfer costs)"
    total_estimated      = "~$482-542/month"
    note                 = "Costs vary based on usage, data transfer, and region. Includes compute, networking, and AWS service charges."
  }
}

# Security and compliance information
output "security_features" {
  description = "Security features enabled in this deployment"
  value = {
    eks_private_endpoints    = var.cluster_endpoint_private_access
    vpc_flow_logs           = "Enabled on both VPCs"
    iam_roles_least_privilege = "Separate roles for clusters and node groups"
    security_groups         = "Configured for cross-region communication"
    encryption_at_rest      = "EBS volumes encrypted by default"
    control_plane_logging   = var.enable_control_plane_logging ? "Enabled" : "Disabled"
    vpc_lattice_auth        = var.enable_vpc_lattice ? var.vpc_lattice_auth_type : "N/A"
  }
}