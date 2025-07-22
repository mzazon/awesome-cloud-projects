# Output values for EKS CloudWatch Container Insights deployment
# These outputs provide important information about the monitoring setup

output "cluster_name" {
  description = "Name of the EKS cluster being monitored"
  value       = var.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint of the EKS cluster"
  value       = data.aws_eks_cluster.cluster.endpoint
  sensitive   = true
}

output "cluster_version" {
  description = "Version of the EKS cluster"
  value       = data.aws_eks_cluster.cluster.version
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = data.aws_eks_cluster.cluster.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for monitoring alerts"
  value       = aws_sns_topic.eks_monitoring_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for monitoring alerts"
  value       = aws_sns_topic.eks_monitoring_alerts.name
}

output "cloudwatch_agent_role_arn" {
  description = "ARN of the IAM role used by CloudWatch agent"
  value       = aws_iam_role.cloudwatch_agent_role.arn
}

output "cloudwatch_namespace" {
  description = "Kubernetes namespace where CloudWatch monitoring components are deployed"
  value       = kubernetes_namespace.amazon_cloudwatch.metadata[0].name
}

# CloudWatch Alarm outputs
output "cpu_alarm_name" {
  description = "Name of the CPU utilization CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_cpu.alarm_name
}

output "cpu_alarm_arn" {
  description = "ARN of the CPU utilization CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_cpu.arn
}

output "memory_alarm_name" {
  description = "Name of the memory utilization CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_memory.alarm_name
}

output "memory_alarm_arn" {
  description = "ARN of the memory utilization CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_memory.arn
}

output "failed_pods_alarm_name" {
  description = "Name of the failed pods CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.failed_pods.alarm_name
}

output "failed_pods_alarm_arn" {
  description = "ARN of the failed pods CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.failed_pods.arn
}

# CloudWatch Log Groups outputs
output "log_groups" {
  description = "CloudWatch Log Groups created for Container Insights"
  value = {
    application  = aws_cloudwatch_log_group.container_insights_application.name
    dataplane    = aws_cloudwatch_log_group.container_insights_dataplane.name
    host         = aws_cloudwatch_log_group.container_insights_host.name
    performance  = aws_cloudwatch_log_group.container_insights_performance.name
  }
}

output "log_group_arns" {
  description = "ARNs of CloudWatch Log Groups created for Container Insights"
  value = {
    application  = aws_cloudwatch_log_group.container_insights_application.arn
    dataplane    = aws_cloudwatch_log_group.container_insights_dataplane.arn
    host         = aws_cloudwatch_log_group.container_insights_host.arn
    performance  = aws_cloudwatch_log_group.container_insights_performance.arn
  }
}

# Container Insights dashboard URL
output "container_insights_dashboard_url" {
  description = "URL to access Container Insights dashboard in AWS Console"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#cw:dashboard=ContainerInsights;context=${var.cluster_name}"
}

# CloudWatch Logs Insights URL
output "logs_insights_url" {
  description = "URL to access CloudWatch Logs Insights for the cluster"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#logsV2:logs-insights"
}

# Monitoring configuration summary
output "monitoring_summary" {
  description = "Summary of monitoring configuration"
  value = {
    cluster_name                = var.cluster_name
    environment                 = var.environment
    cpu_threshold_percent       = var.cpu_alarm_threshold
    memory_threshold_percent    = var.memory_alarm_threshold
    alarm_evaluation_periods    = var.alarm_evaluation_periods
    log_retention_days         = var.log_retention_days
    notification_email         = var.notification_email
    control_plane_logging      = var.enable_control_plane_logging
  }
}

# Verification commands
output "verification_commands" {
  description = "Commands to verify the monitoring setup"
  value = {
    check_metrics = "aws cloudwatch list-metrics --namespace ContainerInsights --dimensions Name=ClusterName,Value=${var.cluster_name}"
    check_pods    = "kubectl get pods -n amazon-cloudwatch"
    check_alarms  = "aws cloudwatch describe-alarms --alarm-names EKS-${var.cluster_name}-HighCPU EKS-${var.cluster_name}-HighMemory EKS-${var.cluster_name}-FailedPods"
  }
}

# Resource counts for cost estimation
output "resource_counts" {
  description = "Count of resources created for cost estimation"
  value = {
    cloudwatch_alarms     = 3
    sns_topics           = 1
    sns_subscriptions    = 1
    log_groups           = 4
    kubernetes_daemonsets = 2
    iam_roles            = 1
    kubernetes_configmaps = 2
  }
}