# EKS cluster outputs
output "cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks.cluster_arn
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "The Kubernetes version for the EKS cluster"
  value       = module.eks.cluster_version
}

output "cluster_platform_version" {
  description = "Platform version for the EKS cluster"
  value       = module.eks.cluster_platform_version
}

output "cluster_status" {
  description = "Status of the EKS cluster. One of `CREATING`, `ACTIVE`, `DELETING`, `FAILED`"
  value       = module.eks.cluster_status
}

output "cluster_security_group_id" {
  description = "Cluster security group that was created by Amazon EKS for the cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = module.eks.cluster_oidc_issuer_url
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

# Node group outputs
output "eks_managed_node_groups" {
  description = "Map of attribute maps for all EKS managed node groups created"
  value       = module.eks.eks_managed_node_groups
}

output "eks_managed_node_groups_autoscaling_group_names" {
  description = "List of the autoscaling group names created by EKS managed node groups"
  value       = module.eks.eks_managed_node_groups_autoscaling_group_names
}

# VPC outputs
output "vpc_id" {
  description = "ID of the VPC where the cluster and its nodes will be provisioned"
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

# ECR outputs
output "ecr_repository_urls" {
  description = "Map of ECR repository URLs for microservices"
  value = {
    for k, v in aws_ecr_repository.microservices : k => v.repository_url
  }
}

output "ecr_repository_arns" {
  description = "Map of ECR repository ARNs for microservices"
  value = {
    for k, v in aws_ecr_repository.microservices : k => v.arn
  }
}

# App Mesh outputs
output "app_mesh_name" {
  description = "Name of the App Mesh"
  value       = local.mesh_name
}

output "mesh_namespace" {
  description = "Kubernetes namespace for the mesh"
  value       = var.mesh_namespace
}

# Load balancer outputs
output "load_balancer_dns_name" {
  description = "DNS name of the load balancer (available after ALB is provisioned)"
  value       = "Use 'kubectl get ingress service-a-ingress -n ${var.mesh_namespace}' to get the load balancer DNS name"
}

output "load_balancer_hosted_zone_id" {
  description = "The canonical hosted zone ID of the load balancer (to be used in a Route 53 Alias record)"
  value       = "Available after ALB is provisioned - check AWS console or use AWS CLI"
}

# IAM role outputs
output "aws_load_balancer_controller_role_arn" {
  description = "ARN of the AWS Load Balancer Controller IAM role"
  value       = aws_iam_role.aws_load_balancer_controller.arn
}

output "appmesh_controller_role_arn" {
  description = "ARN of the App Mesh Controller IAM role"
  value       = aws_iam_role.appmesh_controller.arn
}

output "xray_daemon_role_arn" {
  description = "ARN of the X-Ray daemon IAM role"
  value       = var.enable_xray_tracing ? aws_iam_role.xray_daemon[0].arn : null
}

# Security outputs
output "node_security_group_id" {
  description = "ID of the node shared security group"
  value       = module.eks.node_security_group_id
}

output "kms_key_id" {
  description = "The globally unique identifier for the KMS key used for EKS encryption"
  value       = var.enable_encryption_at_rest ? aws_kms_key.eks[0].key_id : null
}

output "kms_key_arn" {
  description = "The Amazon Resource Name (ARN) of the KMS key used for EKS encryption"
  value       = var.enable_encryption_at_rest ? aws_kms_key.eks[0].arn : null
}

# CloudWatch outputs
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Container Insights"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.container_insights[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Container Insights"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.container_insights[0].arn : null
}

# Useful kubectl commands
output "configure_kubectl" {
  description = "Command to configure kubectl for this cluster"
  value       = "aws eks --region ${var.aws_region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "useful_commands" {
  description = "Useful commands for managing the deployment"
  value = {
    configure_kubectl = "aws eks --region ${var.aws_region} update-kubeconfig --name ${module.eks.cluster_name}"
    check_pods = "kubectl get pods -n ${var.mesh_namespace}"
    check_services = "kubectl get services -n ${var.mesh_namespace}"
    check_ingress = "kubectl get ingress -n ${var.mesh_namespace}"
    check_virtual_nodes = "kubectl get virtualnodes -n ${var.mesh_namespace}"
    check_virtual_services = "kubectl get virtualservices -n ${var.mesh_namespace}"
    check_mesh = "kubectl get mesh"
    get_load_balancer_url = "kubectl get ingress service-a-ingress -n ${var.mesh_namespace} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
    test_service_a = "curl -s http://$(kubectl get ingress service-a-ingress -n ${var.mesh_namespace} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/"
    test_service_chain = "curl -s http://$(kubectl get ingress service-a-ingress -n ${var.mesh_namespace} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/call-b"
  }
}

# Environment information
output "environment_info" {
  description = "Environment information for this deployment"
  value = {
    aws_region      = var.aws_region
    environment     = var.environment
    project_name    = var.project_name
    cluster_name    = local.cluster_name
    mesh_name       = local.mesh_name
    random_suffix   = random_id.suffix.hex
    account_id      = data.aws_caller_identity.current.account_id
  }
}

# Resource counts
output "resource_summary" {
  description = "Summary of resources created"
  value = {
    microservices_count = length(var.microservices)
    ecr_repositories    = length(aws_ecr_repository.microservices)
    availability_zones  = length(local.azs)
    private_subnets     = length(module.vpc.private_subnets)
    public_subnets      = length(module.vpc.public_subnets)
  }
}