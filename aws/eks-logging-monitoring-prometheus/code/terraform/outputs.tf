# Outputs for EKS cluster logging and monitoring infrastructure

# EKS Cluster Information
output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "cluster_version" {
  description = "The Kubernetes version for the EKS cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_platform_version" {
  description = "Platform version for the EKS cluster"
  value       = aws_eks_cluster.main.platform_version
}

output "cluster_status" {
  description = "Status of the EKS cluster"
  value       = aws_eks_cluster.main.status
}

# EKS Node Group Information
output "node_group_arn" {
  description = "ARN of the EKS node group"
  value       = aws_eks_node_group.main.arn
}

output "node_group_status" {
  description = "Status of the EKS node group"
  value       = aws_eks_node_group.main.status
}

output "node_group_capacity_type" {
  description = "Type of capacity associated with the EKS node group"
  value       = aws_eks_node_group.main.capacity_type
}

output "node_group_instance_types" {
  description = "Instance types associated with the EKS node group"
  value       = aws_eks_node_group.main.instance_types
}

# VPC Information
output "vpc_id" {
  description = "VPC ID where the cluster is deployed"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

# IAM Role Information
output "cluster_iam_role_arn" {
  description = "IAM role ARN associated with EKS cluster"
  value       = aws_iam_role.cluster_service_role.arn
}

output "node_group_iam_role_arn" {
  description = "IAM role ARN associated with EKS node group"
  value       = aws_iam_role.node_group_role.arn
}

output "cloudwatch_agent_role_arn" {
  description = "IAM role ARN for CloudWatch agent (IRSA)"
  value       = var.enable_irsa ? aws_iam_role.cloudwatch_agent_role[0].arn : null
}

# OIDC Provider Information
output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for the EKS cluster"
  value       = var.enable_irsa ? aws_iam_openid_connect_provider.eks[0].arn : null
}

# CloudWatch Information
output "cloudwatch_log_group_names" {
  description = "Names of CloudWatch log groups created for EKS"
  value = {
    cluster_logs     = aws_cloudwatch_log_group.cluster_logs.name
    application_logs = aws_cloudwatch_log_group.container_insights_application.name
    dataplane_logs   = aws_cloudwatch_log_group.container_insights_dataplane.name
  }
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.eks_observability.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.eks_observability.dashboard_name}"
}

# CloudWatch Alarms
output "cloudwatch_alarms" {
  description = "List of CloudWatch alarm names"
  value = var.enable_cloudwatch_alarms ? [
    aws_cloudwatch_metric_alarm.high_cpu_utilization[0].alarm_name,
    aws_cloudwatch_metric_alarm.high_memory_utilization[0].alarm_name,
    aws_cloudwatch_metric_alarm.high_failed_pods[0].alarm_name,
    aws_cloudwatch_metric_alarm.node_not_ready[0].alarm_name
  ] : []
}

output "composite_alarm_name" {
  description = "Name of the composite alarm for cluster health"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_composite_alarm.cluster_health[0].alarm_name : null
}

# Prometheus Information
output "prometheus_workspace_id" {
  description = "ID of the Amazon Managed Service for Prometheus workspace"
  value       = var.enable_prometheus ? aws_prometheus_workspace.main[0].id : null
}

output "prometheus_workspace_arn" {
  description = "ARN of the Amazon Managed Service for Prometheus workspace"
  value       = var.enable_prometheus ? aws_prometheus_workspace.main[0].arn : null
}

output "prometheus_workspace_endpoint" {
  description = "Endpoint of the Amazon Managed Service for Prometheus workspace"
  value       = var.enable_prometheus ? aws_prometheus_workspace.main[0].prometheus_endpoint : null
}

output "prometheus_scraper_id" {
  description = "ID of the Prometheus scraper"
  value       = var.enable_prometheus ? aws_prometheus_scraper.main[0].id : null
}

output "prometheus_scraper_arn" {
  description = "ARN of the Prometheus scraper"
  value       = var.enable_prometheus ? aws_prometheus_scraper.main[0].arn : null
}

# SNS Information
output "sns_topic_arn" {
  description = "ARN of the SNS topic for CloudWatch alarms"
  value       = var.enable_cloudwatch_alarms && var.enable_sns_alerts ? aws_sns_topic.cloudwatch_alarms[0].arn : null
}

# CloudWatch Logs Insights Queries
output "logs_insights_query_names" {
  description = "Names of CloudWatch Logs Insights saved queries"
  value = var.monitoring_config.enable_logs_insights_queries ? [
    aws_cloudwatch_query_definition.eks_control_plane_errors[0].name,
    aws_cloudwatch_query_definition.eks_authentication_failures[0].name,
    aws_cloudwatch_query_definition.application_pod_errors[0].name,
    aws_cloudwatch_query_definition.pod_restart_analysis[0].name,
    aws_cloudwatch_query_definition.resource_usage_analysis[0].name
  ] : []
}

# Kubernetes Resources
output "kubernetes_namespace" {
  description = "Name of the Kubernetes namespace for monitoring components"
  value       = kubernetes_namespace.amazon_cloudwatch.metadata[0].name
}

output "fluent_bit_daemonset_name" {
  description = "Name of the Fluent Bit DaemonSet"
  value       = kubernetes_daemonset.fluent_bit.metadata[0].name
}

output "cloudwatch_agent_daemonset_name" {
  description = "Name of the CloudWatch Agent DaemonSet"
  value       = kubernetes_daemonset.cloudwatch_agent.metadata[0].name
}

output "sample_app_deployment_name" {
  description = "Name of the sample application deployment"
  value       = var.deploy_sample_app ? kubernetes_deployment.sample_app[0].metadata[0].name : null
}

output "sample_app_service_name" {
  description = "Name of the sample application service"
  value       = var.deploy_sample_app ? kubernetes_service.sample_app[0].metadata[0].name : null
}

# Configuration Commands
output "kubectl_config_command" {
  description = "Command to update kubeconfig for the EKS cluster"
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.name} --name ${aws_eks_cluster.main.name}"
}

output "logs_insights_url" {
  description = "URL to access CloudWatch Logs Insights"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:logs-insights"
}

output "prometheus_console_url" {
  description = "URL to access Amazon Managed Service for Prometheus console"
  value       = var.enable_prometheus ? "https://${data.aws_region.current.name}.console.aws.amazon.com/prometheus/home?region=${data.aws_region.current.name}#/workspaces/${aws_prometheus_workspace.main[0].id}" : null
}

# Monitoring Setup Status
output "monitoring_setup_complete" {
  description = "Indicates if the monitoring setup is complete"
  value = {
    eks_cluster_created           = aws_eks_cluster.main.status == "ACTIVE"
    node_group_created           = aws_eks_node_group.main.status == "ACTIVE"
    cloudwatch_logging_enabled   = length(var.control_plane_logging) > 0
    container_insights_enabled   = var.enable_container_insights
    prometheus_enabled           = var.enable_prometheus
    cloudwatch_alarms_enabled    = var.enable_cloudwatch_alarms
    sns_alerts_enabled           = var.enable_sns_alerts
    fluent_bit_deployed          = true
    cloudwatch_agent_deployed    = true
    sample_app_deployed          = var.deploy_sample_app
  }
}

# Additional Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost for the monitoring infrastructure (USD)"
  value = {
    note = "Actual costs may vary based on usage patterns, log volume, and metrics retention"
    eks_cluster = "~$73/month for control plane"
    ec2_instances = "~$30-60/month for t3.medium instances (depends on scaling)"
    cloudwatch_logs = "~$10-50/month (depends on log volume)"
    container_insights = "~$10-30/month (depends on metrics volume)"
    prometheus = "~$20-40/month (depends on metrics ingestion)"
    total_estimated = "~$143-253/month"
  }
}

output "next_steps" {
  description = "Next steps after deployment"
  value = [
    "1. Run: ${local.cluster_name_unique} to configure kubectl",
    "2. Check cluster status: kubectl get nodes",
    "3. Verify monitoring pods: kubectl get pods -n amazon-cloudwatch",
    "4. Access CloudWatch dashboard: ${aws_cloudwatch_dashboard.eks_observability.dashboard_name}",
    "5. View logs in CloudWatch Logs Insights",
    "6. Set up SNS notifications by providing sns_endpoint variable",
    "7. Consider deploying additional monitoring tools like Grafana"
  ]
}