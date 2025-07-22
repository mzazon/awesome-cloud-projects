# Outputs for EKS Auto Scaling Infrastructure

# Cluster Information
output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = module.eks.cluster_arn
}

output "cluster_endpoint" {
  description = "The endpoint for the EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "The Kubernetes version of the cluster"
  value       = module.eks.cluster_version
}

output "cluster_platform_version" {
  description = "The platform version for the EKS cluster"
  value       = module.eks.cluster_platform_version
}

output "cluster_status" {
  description = "Status of the EKS cluster"
  value       = module.eks.cluster_status
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

# OIDC Information
output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider"
  value       = module.eks.oidc_provider_arn
}

# Node Group Information
output "eks_managed_node_groups" {
  description = "Map of attribute maps for all EKS managed node groups"
  value       = module.eks.eks_managed_node_groups
}

output "eks_managed_node_groups_autoscaling_group_names" {
  description = "List of the autoscaling group names"
  value       = module.eks.eks_managed_node_groups_autoscaling_group_names
}

# VPC Information
output "vpc_id" {
  description = "ID of the VPC where the cluster is deployed"
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

# IAM Role Information
output "cluster_autoscaler_role_arn" {
  description = "ARN of the IAM role for Cluster Autoscaler"
  value       = aws_iam_role.cluster_autoscaler.arn
}

output "cluster_autoscaler_role_name" {
  description = "Name of the IAM role for Cluster Autoscaler"
  value       = aws_iam_role.cluster_autoscaler.name
}

# Monitoring Information
output "prometheus_endpoint" {
  description = "Prometheus server endpoint URL"
  value       = var.enable_prometheus ? "http://prometheus-server.monitoring.svc.cluster.local:80" : null
}

output "grafana_endpoint" {
  description = "Grafana dashboard endpoint URL"
  value       = var.enable_grafana ? "http://grafana.monitoring.svc.cluster.local:80" : null
}

output "grafana_admin_password" {
  description = "Grafana admin password"
  value       = var.enable_grafana ? var.grafana_admin_password : null
  sensitive   = true
}

# KEDA Information
output "keda_namespace" {
  description = "Namespace where KEDA is installed"
  value       = var.enable_keda ? var.keda_namespace : null
}

output "keda_webhook_endpoint" {
  description = "KEDA webhook endpoint URL"
  value       = var.enable_keda ? "http://keda-admission-webhooks.${var.keda_namespace}.svc.cluster.local:9443" : null
}

# Demo Applications Information
output "demo_namespace" {
  description = "Namespace where demo applications are deployed"
  value       = var.deploy_demo_applications ? var.demo_namespace : null
}

output "demo_applications_endpoints" {
  description = "Endpoints for demo applications"
  value = var.deploy_demo_applications ? {
    cpu_demo              = "http://cpu-demo-service.${var.demo_namespace}.svc.cluster.local"
    memory_demo           = "http://memory-demo-service.${var.demo_namespace}.svc.cluster.local"
    custom_metrics_demo   = "http://custom-metrics-demo-service.${var.demo_namespace}.svc.cluster.local"
  } : null
}

# Kubectl Commands
output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.name} --name ${module.eks.cluster_name}"
}

output "cluster_autoscaler_logs_command" {
  description = "Command to view cluster autoscaler logs"
  value       = "kubectl logs -n kube-system -l app=cluster-autoscaler"
}

output "metrics_server_logs_command" {
  description = "Command to view metrics server logs"
  value       = "kubectl logs -n kube-system -l k8s-app=metrics-server"
}

# Scaling Commands
output "hpa_status_command" {
  description = "Command to check HPA status"
  value       = var.deploy_demo_applications ? "kubectl get hpa -n ${var.demo_namespace}" : null
}

output "node_scaling_test_command" {
  description = "Command to test node scaling"
  value       = "kubectl get nodes -w"
}

output "pod_scaling_test_command" {
  description = "Command to test pod scaling"
  value       = var.deploy_demo_applications ? "kubectl get pods -n ${var.demo_namespace} -w" : null
}

# Load Testing Commands
output "load_test_cpu_command" {
  description = "Command to generate CPU load for testing"
  value = var.deploy_demo_applications ? "kubectl run load-generator --rm -i --tty --image=busybox --restart=Never -n ${var.demo_namespace} -- /bin/sh -c \"while true; do wget -q -O- http://cpu-demo-service/; done\"" : null
}

output "load_test_memory_command" {
  description = "Command to generate memory load for testing"
  value = var.deploy_demo_applications ? "kubectl run memory-load --rm -i --tty --image=busybox --restart=Never -n ${var.demo_namespace} -- /bin/sh -c \"while true; do wget -q -O- http://memory-demo-service/; done\"" : null
}

# Monitoring Commands
output "top_nodes_command" {
  description = "Command to view node resource usage"
  value       = "kubectl top nodes"
}

output "top_pods_command" {
  description = "Command to view pod resource usage"
  value       = var.deploy_demo_applications ? "kubectl top pods -n ${var.demo_namespace}" : null
}

output "scaling_events_command" {
  description = "Command to view scaling events"
  value       = var.deploy_demo_applications ? "kubectl get events --sort-by=.metadata.creationTimestamp -n ${var.demo_namespace}" : null
}

# Cleanup Commands
output "cleanup_demo_command" {
  description = "Command to cleanup demo applications"
  value       = var.deploy_demo_applications ? "kubectl delete namespace ${var.demo_namespace}" : null
}

output "cleanup_monitoring_command" {
  description = "Command to cleanup monitoring stack"
  value       = var.enable_prometheus || var.enable_grafana ? "kubectl delete namespace monitoring" : null
}

# Additional Information
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

output "tags" {
  description = "Tags applied to all resources"
  value       = local.common_tags
}

# Cluster Autoscaler Configuration
output "cluster_autoscaler_settings" {
  description = "Cluster Autoscaler configuration settings"
  value       = var.cluster_autoscaler_settings
}

# Cost Optimization Information
output "cost_optimization_notes" {
  description = "Notes for cost optimization"
  value = [
    "Monitor cluster usage and adjust node group sizes accordingly",
    "Consider using Spot instances for non-critical workloads",
    "Review and optimize HPA scaling thresholds",
    "Use cluster autoscaler scale-down delays to prevent unnecessary node churn",
    "Implement proper resource requests and limits for all applications",
    "Monitor and analyze scaling patterns to optimize configurations"
  ]
}

# Troubleshooting Information
output "troubleshooting_commands" {
  description = "Common troubleshooting commands"
  value = {
    cluster_info           = "kubectl cluster-info"
    cluster_autoscaler_describe = "kubectl describe deployment cluster-autoscaler -n kube-system"
    metrics_server_describe = "kubectl describe deployment metrics-server -n kube-system"
    node_conditions        = "kubectl describe nodes"
    pod_conditions         = var.deploy_demo_applications ? "kubectl describe pods -n ${var.demo_namespace}" : null
    autoscaling_events     = "kubectl get events --field-selector reason=SuccessfulCreate,reason=SuccessfulDelete --all-namespaces"
  }
}