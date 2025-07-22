# =========================================
# VPC and Networking Outputs
# =========================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
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

# =========================================
# EKS Cluster Outputs
# =========================================

output "eks_cluster_id" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "eks_cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = module.eks.cluster_arn
}

output "eks_cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "eks_cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = module.eks.cluster_oidc_issuer_url
}

output "eks_cluster_version" {
  description = "The Kubernetes version for the EKS cluster"
  value       = module.eks.cluster_version
}

output "eks_node_groups" {
  description = "Map of EKS node groups"
  value       = module.eks.eks_managed_node_groups
}

# =========================================
# ECS Cluster Outputs
# =========================================

output "ecs_cluster_id" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.id
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_task_definition_arn" {
  description = "ARN of the ECS task definition"
  value       = aws_ecs_task_definition.observability_demo.arn
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.observability_demo.name
}

output "ecs_service_arn" {
  description = "ARN of the ECS service"
  value       = aws_ecs_service.observability_demo.id
}

# =========================================
# CloudWatch Outputs
# =========================================

output "cloudwatch_log_groups" {
  description = "Map of CloudWatch log groups"
  value = {
    eks_application     = aws_cloudwatch_log_group.eks_application.name
    ecs_application     = aws_cloudwatch_log_group.ecs_application.name
    ecs_cluster         = aws_cloudwatch_log_group.ecs_cluster.name
    container_insights  = aws_cloudwatch_log_group.container_insights.name
  }
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.container_observability.dashboard_name}"
}

output "cloudwatch_alarms" {
  description = "List of CloudWatch alarm names"
  value = [
    aws_cloudwatch_metric_alarm.eks_high_cpu.alarm_name,
    aws_cloudwatch_metric_alarm.eks_high_memory.alarm_name,
    aws_cloudwatch_metric_alarm.ecs_unhealthy_tasks.alarm_name,
    aws_cloudwatch_metric_alarm.cpu_anomaly_alarm.alarm_name
  ]
}

# =========================================
# SNS Topic Outputs
# =========================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.container_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for alerts"
  value       = aws_sns_topic.container_alerts.name
}

# =========================================
# IAM Role Outputs
# =========================================

output "iam_roles" {
  description = "Map of IAM roles created"
  value = {
    aws_load_balancer_controller = module.aws_load_balancer_controller_irsa_role.iam_role_arn
    cloudwatch_observability     = module.cloudwatch_observability_irsa_role.iam_role_arn
    adot_collector               = module.adot_collector_irsa_role.iam_role_arn
    ecs_task_execution           = aws_iam_role.ecs_task_execution_role.arn
    performance_optimizer        = var.enable_automated_optimization ? aws_iam_role.lambda_execution_role[0].arn : null
  }
}

# =========================================
# Monitoring Stack Outputs
# =========================================

output "prometheus_service_name" {
  description = "Name of the Prometheus service"
  value       = "prometheus-server"
}

output "grafana_service_name" {
  description = "Name of the Grafana service"
  value       = "grafana"
}

output "monitoring_namespace" {
  description = "Kubernetes namespace for monitoring stack"
  value       = var.monitoring_namespace
}

output "grafana_admin_password" {
  description = "Admin password for Grafana"
  value       = var.grafana_admin_password
  sensitive   = true
}

# =========================================
# OpenSearch Outputs
# =========================================

output "opensearch_domain_endpoint" {
  description = "Domain-specific endpoint used to submit index, search, and data upload requests"
  value       = var.enable_opensearch ? aws_opensearch_domain.container_logs[0].endpoint : null
}

output "opensearch_domain_arn" {
  description = "ARN of the OpenSearch domain"
  value       = var.enable_opensearch ? aws_opensearch_domain.container_logs[0].arn : null
}

output "opensearch_kibana_endpoint" {
  description = "Domain-specific endpoint for Kibana without https scheme"
  value       = var.enable_opensearch ? aws_opensearch_domain.container_logs[0].kibana_endpoint : null
}

# =========================================
# Lambda Function Outputs
# =========================================

output "performance_optimizer_function_name" {
  description = "Name of the performance optimizer Lambda function"
  value       = var.enable_automated_optimization ? aws_lambda_function.performance_optimizer[0].function_name : null
}

output "performance_optimizer_function_arn" {
  description = "ARN of the performance optimizer Lambda function"
  value       = var.enable_automated_optimization ? aws_lambda_function.performance_optimizer[0].arn : null
}

# =========================================
# Access Information
# =========================================

output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${local.eks_cluster_name}"
}

output "grafana_url" {
  description = "URL to access Grafana (if LoadBalancer is enabled)"
  value       = var.enable_grafana_lb ? "http://${data.kubernetes_service.grafana.status.0.load_balancer.0.ingress.0.hostname}" : "Port-forward: kubectl port-forward -n ${var.monitoring_namespace} svc/grafana 3000:80"
}

output "prometheus_url" {
  description = "URL to access Prometheus (port-forward required)"
  value       = "Port-forward: kubectl port-forward -n ${var.monitoring_namespace} svc/prometheus-server 9090:80"
}

# Data source for Grafana service (if LoadBalancer is enabled)
data "kubernetes_service" "grafana" {
  count = var.enable_grafana_lb ? 1 : 0

  metadata {
    name      = "grafana"
    namespace = var.monitoring_namespace
  }

  depends_on = [helm_release.grafana]
}

# =========================================
# Verification Commands
# =========================================

output "verification_commands" {
  description = "Commands to verify the deployment"
  value = {
    check_eks_cluster        = "aws eks describe-cluster --name ${local.eks_cluster_name} --region ${var.aws_region}"
    check_ecs_cluster        = "aws ecs describe-clusters --clusters ${local.ecs_cluster_name} --region ${var.aws_region}"
    check_container_insights = "aws cloudwatch list-metrics --namespace AWS/ContainerInsights --region ${var.aws_region}"
    check_prometheus_pods    = "kubectl get pods -n ${var.monitoring_namespace} -l app=prometheus"
    check_grafana_pods       = "kubectl get pods -n ${var.monitoring_namespace} -l app.kubernetes.io/name=grafana"
    check_adot_collector     = "kubectl get pods -n ${var.monitoring_namespace} -l app.kubernetes.io/name=opentelemetry-collector"
    check_cloudwatch_alarms  = "aws cloudwatch describe-alarms --alarm-names ${aws_cloudwatch_metric_alarm.eks_high_cpu.alarm_name} --region ${var.aws_region}"
    check_opensearch_domain  = var.enable_opensearch ? "aws opensearch describe-domain --domain-name ${local.opensearch_domain} --region ${var.aws_region}" : "OpenSearch is disabled"
    check_lambda_function    = var.enable_automated_optimization ? "aws lambda get-function --function-name ${aws_lambda_function.performance_optimizer[0].function_name} --region ${var.aws_region}" : "Performance optimizer is disabled"
  }
}

# =========================================
# Cost Estimation
# =========================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    eks_cluster                = "~$73 (cluster) + ~$90 (3 x t3.large nodes)"
    ecs_fargate_tasks         = "~$30 (2 tasks running continuously)"
    cloudwatch_logs           = "~$20 (log ingestion and storage)"
    cloudwatch_metrics        = "~$15 (custom metrics and alarms)"
    opensearch                = var.enable_opensearch ? "~$60 (3 x t3.small.search instances)" : "$0 (disabled)"
    lambda_function           = var.enable_automated_optimization ? "~$1 (hourly execution)" : "$0 (disabled)"
    data_transfer             = "~$10 (estimated)"
    total_estimated           = var.enable_opensearch && var.enable_automated_optimization ? "~$299/month" : (var.enable_opensearch ? "~$298/month" : "~$239/month")
    note                      = "Costs may vary based on usage patterns, data volume, and selected instance types"
  }
}

# =========================================
# Next Steps
# =========================================

output "next_steps" {
  description = "Next steps after deployment"
  value = [
    "1. Configure kubectl: ${local.kubectl_config_command}",
    "2. Access Grafana: ${var.enable_grafana_lb ? "Use LoadBalancer URL" : "Port-forward: kubectl port-forward -n ${var.monitoring_namespace} svc/grafana 3000:80"}",
    "3. Access Prometheus: kubectl port-forward -n ${var.monitoring_namespace} svc/prometheus-server 9090:80",
    "4. View CloudWatch dashboard: https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.container_observability.dashboard_name}",
    "5. Configure SNS email subscription for alerts (if not already done)",
    "6. Deploy sample applications to generate metrics and traces",
    "7. Customize Grafana dashboards for your specific use cases",
    "8. Review and adjust CloudWatch alarm thresholds",
    "9. Consider implementing custom metrics for business KPIs"
  ]
}

# =========================================
# Security Considerations
# =========================================

output "security_notes" {
  description = "Important security considerations"
  value = [
    "1. EKS cluster endpoint is publicly accessible - consider private endpoint for production",
    "2. OpenSearch domain uses basic authentication - implement fine-grained access control for production",
    "3. Grafana uses default admin password - change immediately for production use",
    "4. ECS tasks run in public subnets - move to private subnets for production",
    "5. Review and restrict IAM role permissions based on least privilege principle",
    "6. Enable AWS Config and GuardDuty for additional security monitoring",
    "7. Consider using AWS Secrets Manager for sensitive configuration data",
    "8. Implement network security groups with minimum required access",
    "9. Enable AWS CloudTrail for API audit logging",
    "10. Consider using AWS Systems Manager Session Manager instead of direct SSH access"
  ]
}

# =========================================
# Local Values for Outputs
# =========================================

locals {
  kubectl_config_command = "aws eks update-kubeconfig --region ${var.aws_region} --name ${local.eks_cluster_name}"
}