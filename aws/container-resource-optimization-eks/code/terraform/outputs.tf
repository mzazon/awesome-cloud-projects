# Output values for EKS container resource optimization infrastructure
# These outputs provide important information for validation and integration

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = var.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = data.aws_eks_cluster.cluster.endpoint
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = data.aws_eks_cluster.cluster.arn
}

output "namespace_name" {
  description = "Kubernetes namespace for cost optimization workloads"
  value       = kubernetes_namespace.cost_optimization.metadata[0].name
}

output "metrics_server_status" {
  description = "Status of the Metrics Server deployment"
  value = {
    name      = helm_release.metrics_server.name
    namespace = helm_release.metrics_server.namespace
    version   = helm_release.metrics_server.version
    status    = helm_release.metrics_server.status
  }
}

output "vpa_status" {
  description = "Status of the VPA deployment"
  value = {
    name      = helm_release.vpa.name
    namespace = helm_release.vpa.namespace
    version   = helm_release.vpa.version
    status    = helm_release.vpa.status
  }
}

output "test_application" {
  description = "Test application deployment information"
  value = var.create_test_application ? {
    deployment_name = kubernetes_deployment.test_app[0].metadata[0].name
    service_name    = kubernetes_service.test_app[0].metadata[0].name
    replicas        = var.test_app_replicas
    namespace       = kubernetes_namespace.cost_optimization.metadata[0].name
    cpu_request     = var.test_app_cpu_request
    memory_request  = var.test_app_memory_request
  } : null
}

output "vpa_policies" {
  description = "VPA policy information"
  value = var.create_test_application ? {
    recommendation_mode = "resource-test-app-vpa"
    auto_mode_enabled   = var.enable_vpa_auto_mode
    update_mode         = var.vpa_update_mode
    min_cpu             = var.vpa_min_cpu
    max_cpu             = var.vpa_max_cpu
    min_memory          = var.vpa_min_memory
    max_memory          = var.vpa_max_memory
  } : null
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch cost optimization dashboard"
  value = var.enable_cost_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.cost_optimization[0].dashboard_name}" : null
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = var.enable_cost_dashboard ? aws_cloudwatch_dashboard.cost_optimization[0].dashboard_name : null
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for cost alerts"
  value       = var.enable_cost_alerts ? aws_sns_topic.cost_alerts[0].arn : null
}

output "cost_alarm_name" {
  description = "Name of the CloudWatch alarm for cost monitoring"
  value       = var.enable_cost_alerts ? aws_cloudwatch_metric_alarm.high_resource_waste[0].alarm_name : null
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for cost optimization automation"
  value       = aws_lambda_function.cost_optimization.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function for cost optimization automation"
  value       = aws_lambda_function.cost_optimization.function_name
}

output "container_insights_addon" {
  description = "Container Insights addon information"
  value = var.enable_container_insights ? {
    addon_name    = aws_eks_addon.container_insights[0].addon_name
    status        = aws_eks_addon.container_insights[0].status
    addon_version = aws_eks_addon.container_insights[0].addon_version
  } : null
}

output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_metrics_server = "kubectl get deployment metrics-server -n kube-system"
    check_vpa_components = "kubectl get pods -n kube-system | grep vpa"
    check_test_app       = var.create_test_application ? "kubectl get pods -n ${kubernetes_namespace.cost_optimization.metadata[0].name}" : "Test application not deployed"
    get_vpa_recommendations = var.create_test_application ? "kubectl describe vpa resource-test-app-vpa -n ${kubernetes_namespace.cost_optimization.metadata[0].name}" : "VPA not configured"
    check_resource_usage = "kubectl top pods -n ${kubernetes_namespace.cost_optimization.metadata[0].name}"
  }
}

output "cost_optimization_urls" {
  description = "Important URLs for cost optimization monitoring"
  value = {
    cloudwatch_dashboard = var.enable_cost_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.cost_optimization[0].dashboard_name}" : null
    container_insights   = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#container-insights:performance/dashboard/EKS:Cluster?~(query~(~'${var.cluster_name}~'~'${var.aws_region})~context~())"
    cost_explorer        = "https://console.aws.amazon.com/cost-management/home?region=${var.aws_region}#/dashboard"
  }
}

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Wait 10-15 minutes for VPA to collect sufficient metrics",
    "2. Check VPA recommendations: kubectl describe vpa -n ${kubernetes_namespace.cost_optimization.metadata[0].name}",
    "3. Monitor resource usage: kubectl top pods -n ${kubernetes_namespace.cost_optimization.metadata[0].name}",
    "4. View cost dashboard: ${var.enable_cost_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.cost_optimization[0].dashboard_name}" : "Dashboard not enabled"}",
    "5. Review CloudWatch Container Insights for detailed metrics",
    "6. Consider enabling VPA auto mode after validating recommendations"
  ]
}

output "troubleshooting_commands" {
  description = "Commands for troubleshooting common issues"
  value = {
    check_cluster_connectivity = "kubectl cluster-info"
    verify_metrics_server      = "kubectl get apiservice v1beta1.metrics.k8s.io -o yaml"
    check_vpa_installation     = "kubectl get crd verticalpodautoscalers.autoscaling.k8s.io"
    view_vpa_logs             = "kubectl logs -n kube-system -l app=vpa-recommender"
    check_container_insights   = var.enable_container_insights ? "kubectl get pods -n amazon-cloudwatch" : "Container Insights not enabled"
    view_lambda_logs          = "aws logs describe-log-streams --log-group-name /aws/lambda/eks-cost-optimization-${random_id.suffix.hex}"
  }
}

output "resource_summary" {
  description = "Summary of created resources"
  value = {
    kubernetes_namespace    = kubernetes_namespace.cost_optimization.metadata[0].name
    metrics_server_deployed = helm_release.metrics_server.status == "deployed"
    vpa_deployed           = helm_release.vpa.status == "deployed"
    test_app_created       = var.create_test_application
    container_insights_enabled = var.enable_container_insights
    cost_dashboard_created = var.enable_cost_dashboard
    cost_alerts_enabled    = var.enable_cost_alerts
    lambda_function_created = true
    total_estimated_cost   = "~$10-50/month (CloudWatch metrics and logging)"
  }
}

output "environment_variables" {
  description = "Environment variables for manual operations"
  value = {
    AWS_REGION      = var.aws_region
    CLUSTER_NAME    = var.cluster_name
    NAMESPACE       = kubernetes_namespace.cost_optimization.metadata[0].name
    RANDOM_SUFFIX   = random_id.suffix.hex
  }
}