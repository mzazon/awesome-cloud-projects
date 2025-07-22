# ==============================================================================
# CLUSTER INFORMATION OUTPUTS
# ==============================================================================

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.hybrid_monitoring.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = aws_eks_cluster.hybrid_monitoring.arn
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server"
  value       = aws_eks_cluster.hybrid_monitoring.endpoint
}

output "cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = aws_eks_cluster.hybrid_monitoring.version
}

output "cluster_platform_version" {
  description = "Platform version for the EKS cluster"
  value       = aws_eks_cluster.hybrid_monitoring.platform_version
}

output "cluster_status" {
  description = "Status of the EKS cluster"
  value       = aws_eks_cluster.hybrid_monitoring.status
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for cluster authentication"
  value       = aws_eks_cluster.hybrid_monitoring.certificate_authority[0].data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_eks_cluster.hybrid_monitoring.vpc_config[0].cluster_security_group_id
}

# ==============================================================================
# HYBRID NODES CONFIGURATION OUTPUTS
# ==============================================================================

output "remote_node_networks" {
  description = "CIDR blocks configured for remote hybrid nodes"
  value       = var.remote_node_networks
}

output "remote_pod_networks" {
  description = "CIDR blocks configured for remote pods on hybrid nodes"
  value       = var.remote_pod_networks
}

output "hybrid_nodes_configuration" {
  description = "Complete hybrid nodes configuration"
  value = {
    remote_node_networks = var.remote_node_networks
    remote_pod_networks  = var.remote_pod_networks
    cluster_name         = aws_eks_cluster.hybrid_monitoring.name
    cluster_endpoint     = aws_eks_cluster.hybrid_monitoring.endpoint
  }
}

# ==============================================================================
# NETWORK INFRASTRUCTURE OUTPUTS
# ==============================================================================

output "vpc_id" {
  description = "ID of the VPC created for the EKS cluster"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets used for Fargate"
  value       = aws_subnet.private[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways"
  value       = aws_nat_gateway.main[*].id
}

output "availability_zones" {
  description = "Availability zones used for the infrastructure"
  value       = local.azs
}

# ==============================================================================
# IAM ROLES AND SECURITY OUTPUTS
# ==============================================================================

output "cluster_iam_role_arn" {
  description = "ARN of the EKS cluster IAM role"
  value       = aws_iam_role.cluster.arn
}

output "fargate_pod_execution_role_arn" {
  description = "ARN of the Fargate pod execution role"
  value       = aws_iam_role.fargate.arn
}

output "cloudwatch_observability_role_arn" {
  description = "ARN of the CloudWatch Observability addon IAM role"
  value       = aws_iam_role.cloudwatch_observability.arn
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Identity Provider for the cluster"
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC Identity Provider for the cluster"
  value       = aws_iam_openid_connect_provider.cluster.url
}

# ==============================================================================
# FARGATE CONFIGURATION OUTPUTS
# ==============================================================================

output "fargate_profile_name" {
  description = "Name of the Fargate profile"
  value       = aws_eks_fargate_profile.cloud_workloads.fargate_profile_name
}

output "fargate_profile_arn" {
  description = "ARN of the Fargate profile"
  value       = aws_eks_fargate_profile.cloud_workloads.arn
}

output "fargate_profile_status" {
  description = "Status of the Fargate profile"
  value       = aws_eks_fargate_profile.cloud_workloads.status
}

output "fargate_namespace_selectors" {
  description = "Namespace selectors configured for the Fargate profile"
  value       = var.fargate_namespace_selectors
}

# ==============================================================================
# CLOUDWATCH AND MONITORING OUTPUTS
# ==============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for cluster logs"
  value       = aws_cloudwatch_log_group.cluster.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for cluster logs"
  value       = aws_cloudwatch_log_group.cluster.arn
}

output "cloudwatch_observability_addon_status" {
  description = "Status of the CloudWatch Observability addon"
  value       = aws_eks_addon.cloudwatch_observability.status
}

output "cloudwatch_observability_addon_version" {
  description = "Version of the CloudWatch Observability addon"
  value       = aws_eks_addon.cloudwatch_observability.addon_version
}

output "custom_metrics_namespace" {
  description = "CloudWatch namespace for custom metrics"
  value       = local.cloudwatch_namespace
}

output "container_insights_enabled" {
  description = "Whether Container Insights is enabled"
  value       = var.container_insights_enabled
}

# ==============================================================================
# EKS ADDONS OUTPUTS
# ==============================================================================

output "eks_addons" {
  description = "Status of all EKS addons"
  value = {
    cloudwatch_observability = {
      name    = aws_eks_addon.cloudwatch_observability.addon_name
      version = aws_eks_addon.cloudwatch_observability.addon_version
      status  = aws_eks_addon.cloudwatch_observability.status
    }
    coredns = {
      name    = aws_eks_addon.coredns.addon_name
      version = aws_eks_addon.coredns.addon_version
      status  = aws_eks_addon.coredns.status
    }
    kube_proxy = {
      name    = aws_eks_addon.kube_proxy.addon_name
      version = aws_eks_addon.kube_proxy.addon_version
      status  = aws_eks_addon.kube_proxy.status
    }
    vpc_cni = {
      name    = aws_eks_addon.vpc_cni.addon_name
      version = aws_eks_addon.vpc_cni.addon_version
      status  = aws_eks_addon.vpc_cni.status
    }
  }
}

# ==============================================================================
# ENCRYPTION AND SECURITY OUTPUTS
# ==============================================================================

output "encryption_config" {
  description = "Cluster encryption configuration"
  value = var.cluster_encryption_enabled ? {
    enabled     = true
    kms_key_arn = aws_kms_key.cluster[0].arn
    kms_key_id  = aws_kms_key.cluster[0].key_id
    resources   = ["secrets"]
  } : {
    enabled = false
  }
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for cluster encryption (if enabled)"
  value       = var.cluster_encryption_enabled ? aws_kms_key.cluster[0].arn : null
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for cluster encryption (if enabled)"
  value       = var.cluster_encryption_enabled ? aws_kms_alias.cluster[0].name : null
}

# ==============================================================================
# SAMPLE APPLICATIONS OUTPUTS
# ==============================================================================

output "sample_applications" {
  description = "Information about deployed sample applications"
  value = var.deploy_sample_applications ? {
    namespace     = kubernetes_namespace.cloud_apps[0].metadata[0].name
    deployment    = kubernetes_deployment.sample_app[0].metadata[0].name
    service       = kubernetes_service.sample_app[0].metadata[0].name
    replicas      = var.sample_app_replicas
    deployed      = true
  } : {
    deployed = false
  }
}

# ==============================================================================
# KUBECTL AND AWS CLI COMMANDS
# ==============================================================================

output "kubectl_config_command" {
  description = "Command to configure kubectl for the cluster"
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.name} --name ${aws_eks_cluster.hybrid_monitoring.name}"
}

output "cluster_info_commands" {
  description = "Useful commands for cluster management and monitoring"
  value = {
    update_kubeconfig = "aws eks update-kubeconfig --region ${data.aws_region.current.name} --name ${aws_eks_cluster.hybrid_monitoring.name}"
    get_cluster_info  = "kubectl cluster-info"
    get_nodes         = "kubectl get nodes -o wide"
    get_pods_all      = "kubectl get pods -A"
    get_namespaces    = "kubectl get namespaces"
    describe_cluster  = "aws eks describe-cluster --name ${aws_eks_cluster.hybrid_monitoring.name}"
    view_logs         = "aws logs describe-log-groups --log-group-name-prefix /aws/eks/${aws_eks_cluster.hybrid_monitoring.name}"
  }
}

# ==============================================================================
# CLOUDWATCH MONITORING URLS
# ==============================================================================

output "cloudwatch_console_urls" {
  description = "Direct links to CloudWatch console for monitoring"
  value = {
    container_insights = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#container-insights:performance/EKS:Cluster?~(query~(controls~(CW*3a*3aEKS.cluster~'${aws_eks_cluster.hybrid_monitoring.name})~context~()))"
    log_groups        = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/$252Faws$252Feks$252F${aws_eks_cluster.hybrid_monitoring.name}"
    metrics           = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#metricsV2:graph=~();namespace=AWS/EKS"
  }
}

# ==============================================================================
# COST AND RESOURCE INFORMATION
# ==============================================================================

output "cost_optimization_features" {
  description = "Cost optimization features enabled"
  value = {
    single_nat_gateway = var.single_nat_gateway
    fargate_only      = true
    spot_instances    = var.enable_spot_instances
    log_retention     = "${var.cluster_log_retention_days} days"
  }
}

output "resource_summary" {
  description = "Summary of created resources"
  value = {
    vpc_created           = true
    public_subnets       = length(aws_subnet.public)
    private_subnets      = length(aws_subnet.private)
    nat_gateways         = length(aws_nat_gateway.main)
    fargate_profiles     = 1
    eks_addons           = 4 + (var.install_ebs_csi_driver ? 1 : 0) + (var.install_efs_csi_driver ? 1 : 0)
    sample_apps_deployed = var.deploy_sample_applications
    monitoring_enabled   = true
  }
}

# ==============================================================================
# TROUBLESHOOTING INFORMATION
# ==============================================================================

output "troubleshooting_info" {
  description = "Common troubleshooting commands and information"
  value = {
    check_addon_status    = "aws eks describe-addon --cluster-name ${aws_eks_cluster.hybrid_monitoring.name} --addon-name amazon-cloudwatch-observability"
    check_fargate_profile = "aws eks describe-fargate-profile --cluster-name ${aws_eks_cluster.hybrid_monitoring.name} --fargate-profile-name ${aws_eks_fargate_profile.cloud_workloads.fargate_profile_name}"
    view_cluster_logs    = "aws logs tail /aws/eks/${aws_eks_cluster.hybrid_monitoring.name}/cluster --follow"
    check_pod_logs       = "kubectl logs -n amazon-cloudwatch deployment/cloudwatch-agent"
  }
}