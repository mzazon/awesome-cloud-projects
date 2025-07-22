# EKS Cluster outputs
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = data.aws_eks_cluster.cluster.name
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server"
  value       = data.aws_eks_cluster.cluster.endpoint
}

output "cluster_version" {
  description = "Version of the EKS cluster"
  value       = data.aws_eks_cluster.cluster.version
}

output "cluster_security_group_id" {
  description = "Security group ID of the EKS cluster"
  value       = var.create_eks_cluster ? module.eks[0].cluster_security_group_id : null
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN of the EKS cluster"
  value       = data.aws_eks_cluster.cluster.role_arn
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

output "cluster_primary_security_group_id" {
  description = "Primary security group ID of the EKS cluster"
  value       = var.create_eks_cluster ? module.eks[0].cluster_primary_security_group_id : null
}

# VPC outputs (only if created)
output "vpc_id" {
  description = "ID of the VPC where the cluster is deployed"
  value       = var.create_eks_cluster && var.vpc_id == "" ? module.vpc[0].vpc_id : var.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = var.create_eks_cluster && var.vpc_id == "" ? module.vpc[0].vpc_cidr_block : null
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = var.create_eks_cluster && var.vpc_id == "" ? module.vpc[0].private_subnets : null
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = var.create_eks_cluster && var.vpc_id == "" ? module.vpc[0].public_subnets : null
}

# Node group outputs
output "node_group_arn" {
  description = "Amazon Resource Name (ARN) of the EKS Node Group"
  value       = var.create_eks_cluster ? module.eks[0].eks_managed_node_groups["operators_nodegroup"].arn : null
}

output "node_group_status" {
  description = "Status of the EKS Node Group"
  value       = var.create_eks_cluster ? module.eks[0].eks_managed_node_groups["operators_nodegroup"].status : null
}

# ACK Controller outputs
output "ack_controller_role_arn" {
  description = "ARN of the IAM role for ACK controllers"
  value       = aws_iam_role.ack_controller_role.arn
}

output "ack_system_namespace" {
  description = "Namespace where ACK controllers are deployed"
  value       = var.ack_system_namespace
}

output "ack_s3_controller_status" {
  description = "Status of the ACK S3 controller deployment"
  value       = var.ack_controllers.s3.enabled ? "enabled" : "disabled"
}

output "ack_iam_controller_status" {
  description = "Status of the ACK IAM controller deployment"
  value       = var.ack_controllers.iam.enabled ? "enabled" : "disabled"
}

output "ack_lambda_controller_status" {
  description = "Status of the ACK Lambda controller deployment"
  value       = var.ack_controllers.lambda.enabled ? "enabled" : "disabled"
}

# Custom operator outputs
output "operator_namespace" {
  description = "Namespace where the custom operator is deployed"
  value       = var.operator_namespace
}

output "platform_operator_service_account" {
  description = "Service account name for the platform operator"
  value       = kubernetes_service_account.platform_operator_controller_manager.metadata[0].name
}

output "application_crd_name" {
  description = "Name of the custom Application CRD"
  value       = "applications.platform.example.com"
}

# Security outputs
output "additional_security_group_id" {
  description = "ID of the additional security group for operator workloads"
  value       = aws_security_group.additional_sg.id
}

output "cluster_logs_kms_key_arn" {
  description = "ARN of the KMS key used for encrypting cluster logs"
  value       = var.create_eks_cluster && var.enable_logging ? aws_kms_key.cluster_logs[0].arn : null
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for EKS cluster logs"
  value       = var.create_eks_cluster && var.enable_logging ? aws_cloudwatch_log_group.cluster_logs[0].name : null
}

# Monitoring outputs
output "metrics_service_name" {
  description = "Name of the metrics service for operator monitoring"
  value       = var.enable_monitoring ? kubernetes_service.platform_operator_metrics[0].metadata[0].name : null
}

output "metrics_service_endpoint" {
  description = "Endpoint for accessing operator metrics"
  value       = var.enable_monitoring ? "${kubernetes_service.platform_operator_metrics[0].metadata[0].name}.${var.operator_namespace}.svc.cluster.local:8080" : null
}

# Sample application outputs
output "sample_application_name" {
  description = "Name of the deployed sample application"
  value       = var.deploy_sample_application ? var.sample_app_config.name : null
}

output "sample_application_namespace" {
  description = "Namespace of the deployed sample application"
  value       = var.deploy_sample_application ? "default" : null
}

# Configuration outputs
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
}

output "project_name" {
  description = "Project name used for resource naming"
  value       = var.project_name
}

output "resource_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.resource_suffix
}

# Kubeconfig command
output "kubeconfig_command" {
  description = "Command to update kubeconfig for cluster access"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${data.aws_eks_cluster.cluster.name}"
}

# Useful kubectl commands
output "kubectl_commands" {
  description = "Useful kubectl commands for managing the deployment"
  value = {
    get_ack_controllers     = "kubectl get pods -n ${var.ack_system_namespace}"
    get_applications        = "kubectl get applications -A"
    get_operator_logs       = "kubectl logs -n ${var.operator_namespace} -l app=platform-operator"
    port_forward_metrics    = var.enable_monitoring ? "kubectl port-forward -n ${var.operator_namespace} svc/${kubernetes_service.platform_operator_metrics[0].metadata[0].name} 8080:8080" : null
    check_sample_app        = var.deploy_sample_application ? "kubectl get application ${var.sample_app_config.name} -o yaml" : null
  }
}

# AWS CLI commands for resource verification
output "aws_cli_commands" {
  description = "AWS CLI commands for verifying created resources"
  value = {
    list_s3_buckets      = "aws s3 ls | grep ${var.sample_app_config.name}-${var.sample_app_config.environment}"
    list_iam_roles       = "aws iam list-roles | grep ${var.sample_app_config.name}-${var.sample_app_config.environment}"
    list_lambda_functions = "aws lambda list-functions | grep ${var.sample_app_config.name}-${var.sample_app_config.environment}"
  }
}

# Network configuration
output "network_configuration" {
  description = "Network configuration details"
  value = {
    vpc_id                    = var.create_eks_cluster && var.vpc_id == "" ? module.vpc[0].vpc_id : var.vpc_id
    cluster_security_group_id = var.create_eks_cluster ? module.eks[0].cluster_security_group_id : null
    additional_security_group = aws_security_group.additional_sg.id
    network_policy_enabled    = var.enable_network_policy
  }
}

# IRSA configuration
output "irsa_configuration" {
  description = "IAM Roles for Service Accounts configuration"
  value = {
    enabled                = var.enable_irsa
    oidc_provider_arn     = var.create_eks_cluster ? module.eks[0].oidc_provider_arn : null
    controller_role_arn   = aws_iam_role.ack_controller_role.arn
    service_account_name  = kubernetes_service_account.platform_operator_controller_manager.metadata[0].name
  }
}