# ============================================================================
# AWS EKS Ingress Controllers with AWS Load Balancer Controller
# Terraform Configuration - Outputs
# ============================================================================

# ============================================================================
# AWS Load Balancer Controller Information
# ============================================================================

output "aws_load_balancer_controller_role_arn" {
  description = "ARN of the IAM role for AWS Load Balancer Controller"
  value       = aws_iam_role.aws_load_balancer_controller.arn
}

output "aws_load_balancer_controller_policy_arn" {
  description = "ARN of the IAM policy for AWS Load Balancer Controller"
  value       = aws_iam_policy.aws_load_balancer_controller.arn
}

output "aws_load_balancer_controller_service_account_name" {
  description = "Name of the Kubernetes service account for AWS Load Balancer Controller"
  value       = kubernetes_service_account.aws_load_balancer_controller.metadata[0].name
}

output "aws_load_balancer_controller_namespace" {
  description = "Namespace where AWS Load Balancer Controller is deployed"
  value       = kubernetes_service_account.aws_load_balancer_controller.metadata[0].namespace
}

output "helm_release_name" {
  description = "Name of the Helm release for AWS Load Balancer Controller"
  value       = helm_release.aws_load_balancer_controller.name
}

output "helm_release_version" {
  description = "Version of the AWS Load Balancer Controller Helm chart"
  value       = helm_release.aws_load_balancer_controller.version
}

output "helm_release_status" {
  description = "Status of the AWS Load Balancer Controller Helm release"
  value       = helm_release.aws_load_balancer_controller.status
}

# ============================================================================
# EKS Cluster Information
# ============================================================================

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = var.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint URL of the EKS cluster"
  value       = data.aws_eks_cluster.cluster.endpoint
}

output "cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = data.aws_eks_cluster.cluster.version
}

output "cluster_platform_version" {
  description = "Platform version of the EKS cluster"
  value       = data.aws_eks_cluster.cluster.platform_version
}

output "cluster_vpc_id" {
  description = "VPC ID where the EKS cluster is deployed"
  value       = data.aws_vpc.cluster_vpc.id
}

output "cluster_security_group_ids" {
  description = "Security group IDs for the EKS cluster"
  value       = data.aws_eks_cluster.cluster.vpc_config[0].security_group_ids
}

output "cluster_subnet_ids" {
  description = "Subnet IDs where the EKS cluster is deployed"
  value       = data.aws_eks_cluster.cluster.vpc_config[0].subnet_ids
}

# ============================================================================
# OIDC Provider Information
# ============================================================================

output "oidc_provider_arn" {
  description = "ARN of the OIDC identity provider for the EKS cluster"
  value       = var.create_oidc_provider ? aws_iam_openid_connect_provider.eks[0].arn : data.aws_iam_openid_connect_provider.existing[0].arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC identity provider for the EKS cluster"
  value       = var.create_oidc_provider ? aws_iam_openid_connect_provider.eks[0].url : data.aws_iam_openid_connect_provider.existing[0].url
}

# ============================================================================
# Application Namespace Information
# ============================================================================

output "demo_namespace" {
  description = "Name of the demo namespace for sample applications"
  value       = kubernetes_namespace.ingress_demo.metadata[0].name
}

output "demo_namespace_labels" {
  description = "Labels applied to the demo namespace"
  value       = kubernetes_namespace.ingress_demo.metadata[0].labels
}

# ============================================================================
# Sample Application Information
# ============================================================================

output "sample_app_v1_service_name" {
  description = "Name of the sample application v1 service"
  value       = kubernetes_service.sample_app_v1.metadata[0].name
}

output "sample_app_v2_service_name" {
  description = "Name of the sample application v2 service"
  value       = kubernetes_service.sample_app_v2.metadata[0].name
}

output "sample_app_v1_deployment_name" {
  description = "Name of the sample application v1 deployment"
  value       = kubernetes_deployment.sample_app_v1.metadata[0].name
}

output "sample_app_v2_deployment_name" {
  description = "Name of the sample application v2 deployment"
  value       = kubernetes_deployment.sample_app_v2.metadata[0].name
}

# ============================================================================
# Load Balancer Information
# ============================================================================

output "basic_alb_ingress_hostname" {
  description = "Hostname of the basic ALB ingress (if created)"
  value       = var.create_sample_ingresses ? try(kubernetes_ingress_v1.basic_alb[0].status[0].load_balancer[0].ingress[0].hostname, "Not available yet") : "Not created"
}

output "advanced_alb_ingress_hostname" {
  description = "Hostname of the advanced ALB ingress (if created)"
  value       = var.create_sample_ingresses && var.domain_name != "" ? try(kubernetes_ingress_v1.advanced_alb[0].status[0].load_balancer[0].ingress[0].hostname, "Not available yet") : "Not created"
}

output "nlb_service_hostname" {
  description = "Hostname of the NLB service (if created)"
  value       = var.create_sample_ingresses ? try(kubernetes_service.sample_app_nlb[0].status[0].load_balancer[0].ingress[0].hostname, "Not available yet") : "Not created"
}

output "nlb_service_ip" {
  description = "IP address of the NLB service (if available)"
  value       = var.create_sample_ingresses ? try(kubernetes_service.sample_app_nlb[0].status[0].load_balancer[0].ingress[0].ip, "Not available") : "Not created"
}

# ============================================================================
# SSL Certificate Information
# ============================================================================

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate (if created)"
  value       = var.domain_name != "" ? try(aws_acm_certificate.ingress_cert[0].arn, "Not created") : "Domain not provided"
}

output "acm_certificate_domain_name" {
  description = "Domain name of the ACM certificate (if created)"
  value       = var.domain_name != "" ? try(aws_acm_certificate.ingress_cert[0].domain_name, "Not created") : "Domain not provided"
}

output "acm_certificate_status" {
  description = "Validation status of the ACM certificate (if created)"
  value       = var.domain_name != "" ? try(aws_acm_certificate.ingress_cert[0].status, "Not created") : "Domain not provided"
}

output "acm_certificate_validation_records" {
  description = "DNS validation records for the ACM certificate (if created)"
  value       = var.domain_name != "" ? try(aws_acm_certificate.ingress_cert[0].domain_validation_options, []) : []
  sensitive   = false
}

# ============================================================================
# S3 Access Logs Information
# ============================================================================

output "access_logs_bucket_name" {
  description = "Name of the S3 bucket for ALB access logs (if created)"
  value       = var.enable_access_logs ? aws_s3_bucket.alb_access_logs[0].bucket : "Not created"
}

output "access_logs_bucket_arn" {
  description = "ARN of the S3 bucket for ALB access logs (if created)"
  value       = var.enable_access_logs ? aws_s3_bucket.alb_access_logs[0].arn : "Not created"
}

output "access_logs_bucket_region" {
  description = "Region of the S3 bucket for ALB access logs (if created)"
  value       = var.enable_access_logs ? aws_s3_bucket.alb_access_logs[0].region : "Not created"
}

# ============================================================================
# Ingress Class Information
# ============================================================================

output "custom_ingress_class_name" {
  description = "Name of the custom ingress class (if created)"
  value       = var.create_sample_ingresses ? "custom-alb" : "Not created"
}

output "default_ingress_class" {
  description = "Default ingress class for the cluster"
  value       = "alb"
}

# ============================================================================
# Connection Information and Commands
# ============================================================================

output "kubectl_config_command" {
  description = "Command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}"
}

output "verify_controller_command" {
  description = "Command to verify AWS Load Balancer Controller deployment"
  value       = "kubectl get deployment -n kube-system aws-load-balancer-controller"
}

output "check_ingress_command" {
  description = "Command to check ingress resources"
  value       = "kubectl get ingress -n ${kubernetes_namespace.ingress_demo.metadata[0].name}"
}

output "view_controller_logs_command" {
  description = "Command to view AWS Load Balancer Controller logs"
  value       = "kubectl logs -n kube-system deployment/aws-load-balancer-controller"
}

# ============================================================================
# Testing URLs and Information
# ============================================================================

output "basic_alb_test_url" {
  description = "Test URL for basic ALB ingress (once DNS propagates)"
  value = var.create_sample_ingresses && var.domain_name != "" ? "http://basic.${var.domain_name}/" : (
    var.create_sample_ingresses ? "Use ALB hostname: http://<basic-alb-hostname>/" : "Not created"
  )
}

output "advanced_alb_test_urls" {
  description = "Test URLs for advanced ALB ingress with path-based routing"
  value = var.create_sample_ingresses && var.domain_name != "" ? {
    v1_endpoint = "https://advanced.${var.domain_name}/v1"
    v2_endpoint = "https://advanced.${var.domain_name}/v2"
  } : (
    var.create_sample_ingresses ? {
      v1_endpoint = "Use ALB hostname: https://<advanced-alb-hostname>/v1"
      v2_endpoint = "Use ALB hostname: https://<advanced-alb-hostname>/v2"
    } : { message = "Not created" }
  )
}

output "nlb_test_command" {
  description = "Command to test NLB connectivity"
  value = var.create_sample_ingresses ? "curl http://<nlb-hostname>/" : "NLB not created"
}

# ============================================================================
# Monitoring and Observability
# ============================================================================

output "cloudwatch_log_group" {
  description = "CloudWatch log group for EKS cluster (if configured)"
  value       = "/aws/eks/${var.cluster_name}/cluster"
}

output "load_balancer_metrics_namespace" {
  description = "CloudWatch namespace for Application Load Balancer metrics"
  value       = "AWS/ApplicationELB"
}

output "target_group_metrics_namespace" {
  description = "CloudWatch namespace for Target Group metrics"
  value       = "AWS/ApplicationELB"
}

# ============================================================================
# Security and Compliance Information
# ============================================================================

output "security_group_tags" {
  description = "Security groups created by the AWS Load Balancer Controller will have these tag patterns"
  value = {
    "elbv2.k8s.aws/cluster" = var.cluster_name
    Environment             = "demo"
    ManagedBy              = "aws-load-balancer-controller"
  }
}

output "load_balancer_tags" {
  description = "Tags applied to load balancers created by the controller"
  value = merge(var.tags, {
    "elbv2.k8s.aws/cluster" = var.cluster_name
  })
}

# ============================================================================
# Troubleshooting Information
# ============================================================================

output "troubleshooting_commands" {
  description = "Useful commands for troubleshooting the AWS Load Balancer Controller"
  value = {
    check_controller_status = "kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller"
    view_controller_events  = "kubectl get events -n kube-system --field-selector involvedObject.name=aws-load-balancer-controller"
    describe_ingress        = "kubectl describe ingress -n ${kubernetes_namespace.ingress_demo.metadata[0].name}"
    list_target_groups      = "aws elbv2 describe-target-groups --query 'TargetGroups[?contains(TargetGroupName, \\`k8s-\\`)].{Name:TargetGroupName,ARN:TargetGroupArn}' --output table"
    list_load_balancers     = "aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, \\`k8s-\\`)].{Name:LoadBalancerName,DNS:DNSName,Type:Type}' --output table"
  }
}

# ============================================================================
# Resource Summary
# ============================================================================

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    cluster_name                    = var.cluster_name
    aws_region                     = var.aws_region
    controller_version             = var.alb_controller_version
    controller_image_tag           = var.controller_image_tag
    demo_namespace                 = kubernetes_namespace.ingress_demo.metadata[0].name
    sample_ingresses_created       = var.create_sample_ingresses
    ssl_certificate_created        = var.domain_name != ""
    access_logs_enabled           = var.enable_access_logs
    nlb_service_created           = var.create_sample_ingresses && var.create_nlb_service
    custom_ingress_class_created  = var.create_sample_ingresses
    oidc_provider_created         = var.create_oidc_provider
    pod_readiness_gate_enabled    = var.enable_pod_readiness_gate
    efa_support_enabled           = var.enable_efa_support
    deployment_mode               = var.deployment_mode
  }
}

# ============================================================================
# Quick Start Commands
# ============================================================================

output "quick_start_commands" {
  description = "Commands to quickly validate the deployment"
  value = {
    configure_kubectl = "aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}"
    check_controller  = "kubectl get deployment -n kube-system aws-load-balancer-controller"
    check_pods        = "kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller"
    view_logs         = "kubectl logs -n kube-system deployment/aws-load-balancer-controller"
    list_ingresses    = "kubectl get ingress -A"
    list_services     = "kubectl get services -A --field-selector spec.type=LoadBalancer"
  }
}

# ============================================================================
# Advanced Configuration Information
# ============================================================================

output "controller_configuration" {
  description = "AWS Load Balancer Controller configuration details"
  value = {
    helm_chart_version     = var.alb_controller_version
    image_tag             = var.controller_image_tag
    log_level             = var.controller_log_level
    wait_for_load_balancer = var.wait_for_load_balancer
    pod_readiness_gate     = var.enable_pod_readiness_gate
    efa_support           = var.enable_efa_support
    target_type           = var.target_type
    load_balancer_scheme  = var.load_balancer_scheme
  }
}