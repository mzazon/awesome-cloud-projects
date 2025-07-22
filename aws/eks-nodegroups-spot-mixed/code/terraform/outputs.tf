# Cluster Information
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = var.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = data.aws_eks_cluster.cluster.endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = data.aws_eks_cluster.cluster.vpc_config[0].cluster_security_group_id
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN of the EKS cluster"
  value       = data.aws_eks_cluster.cluster.role_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = data.aws_eks_cluster.cluster.certificate_authority[0].data
}

output "cluster_version" {
  description = "The Kubernetes version for the cluster"
  value       = data.aws_eks_cluster.cluster.version
}

output "cluster_platform_version" {
  description = "Platform version for the cluster"
  value       = data.aws_eks_cluster.cluster.platform_version
}

output "cluster_vpc_id" {
  description = "VPC ID where the cluster is deployed"
  value       = data.aws_eks_cluster.cluster.vpc_config[0].vpc_id
}

output "cluster_subnet_ids" {
  description = "List of subnet IDs where the cluster is deployed"
  value       = data.aws_eks_cluster.cluster.vpc_config[0].subnet_ids
}

# Node Group Information
output "node_group_role_arn" {
  description = "Amazon Resource Name (ARN) of the EKS Node Group Role"
  value       = aws_iam_role.node_group_role.arn
}

output "node_group_role_name" {
  description = "Name of the EKS Node Group Role"
  value       = aws_iam_role.node_group_role.name
}

# Spot Node Group Outputs
output "spot_node_group_arn" {
  description = "Amazon Resource Name (ARN) of the spot EKS Node Group"
  value       = aws_eks_node_group.spot_node_group.arn
}

output "spot_node_group_id" {
  description = "EKS cluster name and spot node group name separated by a colon"
  value       = aws_eks_node_group.spot_node_group.id
}

output "spot_node_group_status" {
  description = "Status of the spot EKS Node Group"
  value       = aws_eks_node_group.spot_node_group.status
}

output "spot_node_group_capacity_type" {
  description = "Type of capacity associated with the spot EKS Node Group"
  value       = aws_eks_node_group.spot_node_group.capacity_type
}

output "spot_node_group_instance_types" {
  description = "Set of instance types associated with the spot EKS Node Group"
  value       = aws_eks_node_group.spot_node_group.instance_types
}

output "spot_node_group_scaling_config" {
  description = "Configuration block with scaling settings for the spot node group"
  value       = aws_eks_node_group.spot_node_group.scaling_config
}

output "spot_node_group_resources" {
  description = "List of objects containing information about underlying resources of the spot node group"
  value       = aws_eks_node_group.spot_node_group.resources
}

# On-Demand Node Group Outputs
output "ondemand_node_group_arn" {
  description = "Amazon Resource Name (ARN) of the on-demand EKS Node Group"
  value       = aws_eks_node_group.ondemand_node_group.arn
}

output "ondemand_node_group_id" {
  description = "EKS cluster name and on-demand node group name separated by a colon"
  value       = aws_eks_node_group.ondemand_node_group.id
}

output "ondemand_node_group_status" {
  description = "Status of the on-demand EKS Node Group"
  value       = aws_eks_node_group.ondemand_node_group.status
}

output "ondemand_node_group_capacity_type" {
  description = "Type of capacity associated with the on-demand EKS Node Group"
  value       = aws_eks_node_group.ondemand_node_group.capacity_type
}

output "ondemand_node_group_instance_types" {
  description = "Set of instance types associated with the on-demand EKS Node Group"
  value       = aws_eks_node_group.ondemand_node_group.instance_types
}

output "ondemand_node_group_scaling_config" {
  description = "Configuration block with scaling settings for the on-demand node group"
  value       = aws_eks_node_group.ondemand_node_group.scaling_config
}

output "ondemand_node_group_resources" {
  description = "List of objects containing information about underlying resources of the on-demand node group"
  value       = aws_eks_node_group.ondemand_node_group.resources
}

# Cluster Autoscaler Information
output "cluster_autoscaler_enabled" {
  description = "Whether cluster autoscaler is enabled"
  value       = var.enable_cluster_autoscaler
}

output "cluster_autoscaler_role_arn" {
  description = "ARN of the cluster autoscaler IAM role"
  value       = var.enable_cluster_autoscaler ? aws_iam_role.cluster_autoscaler_role[0].arn : null
}

output "cluster_autoscaler_service_account_name" {
  description = "Name of the cluster autoscaler service account"
  value       = var.enable_cluster_autoscaler ? kubernetes_service_account.cluster_autoscaler_sa[0].metadata[0].name : null
}

# Node Termination Handler Information
output "node_termination_handler_enabled" {
  description = "Whether AWS Node Termination Handler is enabled"
  value       = var.enable_node_termination_handler
}

output "node_termination_handler_version" {
  description = "Version of AWS Node Termination Handler installed"
  value       = var.enable_node_termination_handler ? var.node_termination_handler_version : null
}

# Cost Monitoring Information
output "cost_monitoring_enabled" {
  description = "Whether cost monitoring is enabled"
  value       = var.enable_cost_monitoring
}

output "spot_interruption_log_group_name" {
  description = "Name of the CloudWatch log group for spot interruptions"
  value       = var.enable_cost_monitoring ? aws_cloudwatch_log_group.spot_interruptions[0].name : null
}

output "spot_interruption_alarm_name" {
  description = "Name of the CloudWatch alarm for spot interruptions"
  value       = var.enable_cost_monitoring && var.sns_topic_arn != "" ? aws_cloudwatch_metric_alarm.spot_interruption_alarm[0].alarm_name : null
}

# Demo Application Information
output "demo_app_service_name" {
  description = "Name of the demo application service"
  value       = kubernetes_service.spot_demo_service.metadata[0].name
}

output "demo_app_deployment_name" {
  description = "Name of the demo application deployment"
  value       = kubernetes_deployment.spot_demo_app.metadata[0].name
}

# IRSA Configuration
output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  value       = var.enable_irsa ? (var.oidc_provider_arn != "" ? var.oidc_provider_arn : aws_iam_openid_connect_provider.cluster_oidc[0].arn) : null
}

output "oidc_issuer_url" {
  description = "URL of the OIDC issuer"
  value       = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

# kubectl Configuration Commands
output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.name} --name ${var.cluster_name}"
}

# Verification Commands
output "verify_nodes_command" {
  description = "Command to verify node groups are running"
  value       = "kubectl get nodes --show-labels"
}

output "verify_spot_nodes_command" {
  description = "Command to verify spot nodes specifically"
  value       = "kubectl get nodes -l node-type=spot"
}

output "verify_ondemand_nodes_command" {
  description = "Command to verify on-demand nodes specifically"
  value       = "kubectl get nodes -l node-type=on-demand"
}

output "verify_demo_app_command" {
  description = "Command to verify demo application deployment"
  value       = "kubectl get pods -l app=spot-demo-app -o wide"
}

output "verify_cluster_autoscaler_command" {
  description = "Command to verify cluster autoscaler deployment"
  value       = var.enable_cluster_autoscaler ? "kubectl get deployment cluster-autoscaler -n kube-system" : "Cluster autoscaler not enabled"
}

output "verify_node_termination_handler_command" {
  description = "Command to verify node termination handler deployment"
  value       = var.enable_node_termination_handler ? "kubectl get daemonset aws-node-termination-handler -n kube-system" : "Node termination handler not enabled"
}

# Cost Optimization Information
output "cost_optimization_summary" {
  description = "Summary of cost optimization features enabled"
  value = {
    spot_instances_enabled               = true
    mixed_instance_types_enabled         = true
    cluster_autoscaler_enabled          = var.enable_cluster_autoscaler
    node_termination_handler_enabled    = var.enable_node_termination_handler
    cost_monitoring_enabled              = var.enable_cost_monitoring
    spot_node_group_instance_types       = var.spot_node_group_config.instance_types
    ondemand_node_group_instance_types   = var.ondemand_node_group_config.instance_types
    estimated_cost_savings               = "Up to 90% on compute costs for spot instances"
  }
}

# Security Information
output "security_features" {
  description = "Security features enabled in the deployment"
  value = {
    irsa_enabled                     = var.enable_irsa
    least_privilege_iam             = true
    pod_disruption_budget_enabled   = true
    node_taints_configured          = length(var.spot_node_taints) > 0
    security_contexts_configured    = true
  }
}

# Networking Information
output "networking_configuration" {
  description = "Networking configuration details"
  value = {
    vpc_id                = data.aws_eks_cluster.cluster.vpc_config[0].vpc_id
    subnet_ids           = local.subnet_ids
    cluster_security_group_id = data.aws_eks_cluster.cluster.vpc_config[0].cluster_security_group_id
    endpoint_config      = data.aws_eks_cluster.cluster.vpc_config[0].endpoint_config
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Configure kubectl: ${local.kubectl_config_command}",
    "2. Verify node groups: kubectl get nodes --show-labels",
    "3. Check cluster autoscaler: kubectl get pods -n kube-system -l app=cluster-autoscaler",
    "4. Verify demo application: kubectl get pods -l app=spot-demo-app -o wide",
    "5. Monitor spot interruptions: kubectl logs -n kube-system -l app.kubernetes.io/name=aws-node-termination-handler",
    "6. Configure workload tolerations for spot instances",
    "7. Set up cost monitoring dashboards",
    "8. Test application resilience to spot interruptions"
  ]
}

# Local value for kubectl config command
locals {
  kubectl_config_command = "aws eks update-kubeconfig --region ${data.aws_region.current.name} --name ${var.cluster_name}"
}