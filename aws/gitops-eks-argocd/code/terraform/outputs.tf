# Output values for GitOps workflow infrastructure
# These outputs provide essential information for accessing and managing the deployed infrastructure

# Cluster Information
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_version" {
  description = "Version of the EKS cluster"
  value       = module.eks.cluster_version
}

output "cluster_platform_version" {
  description = "Platform version for the EKS cluster"
  value       = module.eks.cluster_platform_version
}

output "cluster_status" {
  description = "Status of the EKS cluster (CREATING, ACTIVE, DELETING, FAILED)"
  value       = module.eks.cluster_status
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = module.eks.cluster_arn
}

# OIDC Provider Information
output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider for IRSA"
  value       = module.eks.oidc_provider_arn
}

# Node Group Information
output "eks_managed_node_groups" {
  description = "Map of attribute maps for all EKS managed node groups created"
  value       = module.eks.eks_managed_node_groups
  sensitive   = true
}

output "node_security_group_id" {
  description = "Security group ID attached to the EKS node group"
  value       = module.eks.node_security_group_id
}

# VPC Information
output "vpc_id" {
  description = "ID of the VPC where the cluster is deployed"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnets
}

output "availability_zones" {
  description = "List of availability zones used"
  value       = local.azs
}

# CodeCommit Repository Information
output "codecommit_repository_name" {
  description = "Name of the CodeCommit repository for GitOps configuration"
  value       = aws_codecommit_repository.gitops_config.repository_name
}

output "codecommit_repository_id" {
  description = "ID of the CodeCommit repository"
  value       = aws_codecommit_repository.gitops_config.repository_id
}

output "codecommit_clone_url_http" {
  description = "HTTP clone URL for the CodeCommit repository"
  value       = aws_codecommit_repository.gitops_config.clone_url_http
}

output "codecommit_clone_url_ssh" {
  description = "SSH clone URL for the CodeCommit repository"
  value       = aws_codecommit_repository.gitops_config.clone_url_ssh
}

# ArgoCD Information
output "argocd_namespace" {
  description = "Kubernetes namespace where ArgoCD is installed"
  value       = var.install_argocd ? kubernetes_namespace.argocd[0].metadata[0].name : null
}

output "argocd_server_service_name" {
  description = "Name of the ArgoCD server service"
  value       = var.install_argocd ? "argocd-server" : null
}

output "argocd_ingress_hostname" {
  description = "Hostname of the ArgoCD server ingress (ALB)"
  value       = var.install_argocd ? try(kubernetes_ingress_v1.argocd_server[0].status[0].load_balancer[0].ingress[0].hostname, null) : null
}

# IAM Role Information
output "aws_load_balancer_controller_role_arn" {
  description = "ARN of the IAM role for AWS Load Balancer Controller"
  value       = var.install_aws_load_balancer_controller ? module.aws_load_balancer_controller_irsa_role[0].iam_role_arn : null
}

output "ebs_csi_driver_role_arn" {
  description = "ARN of the IAM role for EBS CSI driver"
  value       = var.enable_ebs_csi_driver ? module.ebs_csi_irsa_role[0].iam_role_arn : null
}

# CloudWatch Information
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for EKS cluster logs"
  value       = aws_cloudwatch_log_group.eks_cluster.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for EKS cluster logs"
  value       = aws_cloudwatch_log_group.eks_cluster.arn
}

# Security Group Information
output "cluster_primary_security_group_id" {
  description = "The cluster primary security group ID created by EKS"
  value       = module.eks.cluster_primary_security_group_id
}

# Resource Naming Information
output "resource_name_prefix" {
  description = "Prefix used for naming resources"
  value       = local.cluster_name
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = var.create_random_suffix ? random_string.suffix[0].result : null
}

# Connection Information for kubectl
output "kubectl_config_command" {
  description = "Command to configure kubectl for the EKS cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# ArgoCD Access Information
output "argocd_admin_password_command" {
  description = "Command to retrieve ArgoCD admin password"
  value       = var.install_argocd ? "kubectl get secret argocd-initial-admin-secret -n ${kubernetes_namespace.argocd[0].metadata[0].name} -o jsonpath='{.data.password}' | base64 -d" : null
}

output "argocd_server_url" {
  description = "URL to access ArgoCD server (when ALB is ready)"
  value       = var.install_argocd ? "https://${try(kubernetes_ingress_v1.argocd_server[0].status[0].load_balancer[0].ingress[0].hostname, "pending")}" : null
}

# Environment and Project Information
output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# Resource Tags
output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# Validation Information
output "deployment_validation" {
  description = "Commands to validate the deployment"
  value = {
    check_nodes     = "kubectl get nodes"
    check_pods      = "kubectl get pods -n ${var.install_argocd ? kubernetes_namespace.argocd[0].metadata[0].name : "argocd"}"
    check_services  = "kubectl get services -n ${var.install_argocd ? kubernetes_namespace.argocd[0].metadata[0].name : "argocd"}"
    check_ingress   = "kubectl get ingress -n ${var.install_argocd ? kubernetes_namespace.argocd[0].metadata[0].name : "argocd"}"
  }
}