# Outputs for the real-time streaming analytics infrastructure

#------------------------------------------------------------------------------
# EKS Cluster Outputs
#------------------------------------------------------------------------------

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "The Kubernetes server version for the EKS cluster"
  value       = module.eks.cluster_version
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN of the EKS cluster"
  value       = module.eks.cluster_iam_role_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider for EKS"
  value       = module.eks.oidc_provider_arn
}

#------------------------------------------------------------------------------
# VPC and Networking Outputs
#------------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC where the cluster and associated resources are deployed"
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

output "nat_gateway_ids" {
  description = "List of IDs of the NAT Gateways"
  value       = module.vpc.natgw_ids
}

#------------------------------------------------------------------------------
# EMR on EKS Outputs
#------------------------------------------------------------------------------

output "emr_virtual_cluster_id" {
  description = "ID of the EMR virtual cluster"
  value       = aws_emrcontainers_virtual_cluster.flink_cluster.id
}

output "emr_virtual_cluster_arn" {
  description = "ARN of the EMR virtual cluster"
  value       = aws_emrcontainers_virtual_cluster.flink_cluster.arn
}

output "emr_service_role_arn" {
  description = "ARN of the EMR containers service role"
  value       = aws_iam_role.emr_containers_service_role.arn
}

output "emr_job_execution_role_arn" {
  description = "ARN of the EMR job execution role"
  value       = aws_iam_role.emr_job_execution_role.arn
}

output "emr_namespace" {
  description = "Kubernetes namespace for EMR workloads"
  value       = kubernetes_namespace.emr_namespace.metadata[0].name
}

#------------------------------------------------------------------------------
# Storage Outputs
#------------------------------------------------------------------------------

output "s3_bucket_name" {
  description = "Name of the S3 bucket for Flink checkpoints and results"
  value       = aws_s3_bucket.flink_storage.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for Flink checkpoints and results"
  value       = aws_s3_bucket.flink_storage.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.flink_storage.bucket_domain_name
}

#------------------------------------------------------------------------------
# Kinesis Streams Outputs
#------------------------------------------------------------------------------

output "trading_stream_name" {
  description = "Name of the trading events Kinesis stream"
  value       = aws_kinesis_stream.trading_events.name
}

output "trading_stream_arn" {
  description = "ARN of the trading events Kinesis stream"
  value       = aws_kinesis_stream.trading_events.arn
}

output "trading_stream_shard_count" {
  description = "Number of shards in the trading events stream"
  value       = aws_kinesis_stream.trading_events.shard_count
}

output "market_stream_name" {
  description = "Name of the market data Kinesis stream"
  value       = aws_kinesis_stream.market_data.name
}

output "market_stream_arn" {
  description = "ARN of the market data Kinesis stream"
  value       = aws_kinesis_stream.market_data.arn
}

output "market_stream_shard_count" {
  description = "Number of shards in the market data stream"
  value       = aws_kinesis_stream.market_data.shard_count
}

#------------------------------------------------------------------------------
# Monitoring Outputs
#------------------------------------------------------------------------------

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Flink applications"
  value       = aws_cloudwatch_log_group.flink_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Flink applications"
  value       = aws_cloudwatch_log_group.flink_logs.arn
}

output "prometheus_namespace" {
  description = "Kubernetes namespace where Prometheus is deployed"
  value       = var.enable_monitoring ? kubernetes_namespace.monitoring[0].metadata[0].name : null
}

#------------------------------------------------------------------------------
# Connection Information
#------------------------------------------------------------------------------

output "kubectl_config_command" {
  description = "Command to configure kubectl for the EKS cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "flink_ui_port_forward_command" {
  description = "Command to port forward to the Flink web UI"
  value       = "kubectl port-forward -n ${kubernetes_namespace.emr_namespace.metadata[0].name} service/fraud-detection-rest 8081:8081"
}

output "grafana_port_forward_command" {
  description = "Command to port forward to Grafana (if monitoring is enabled)"
  value       = var.enable_monitoring ? "kubectl port-forward -n ${kubernetes_namespace.monitoring[0].metadata[0].name} service/prometheus-grafana 3000:80" : null
}

#------------------------------------------------------------------------------
# Deployment Status Outputs
#------------------------------------------------------------------------------

output "infrastructure_ready" {
  description = "Indicates if the infrastructure deployment is complete"
  value       = true
  depends_on = [
    module.eks,
    aws_emrcontainers_virtual_cluster.flink_cluster,
    aws_s3_bucket.flink_storage,
    aws_kinesis_stream.trading_events,
    aws_kinesis_stream.market_data,
    helm_release.flink_operator
  ]
}

output "next_steps" {
  description = "Next steps after infrastructure deployment"
  value = <<-EOT
    1. Configure kubectl: ${module.eks.cluster_name != "" ? "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}" : ""}
    2. Check Flink operator: kubectl get pods -n ${kubernetes_namespace.emr_namespace.metadata[0].name}
    3. Access Flink UI: kubectl port-forward -n ${kubernetes_namespace.emr_namespace.metadata[0].name} service/fraud-detection-rest 8081:8081
    ${var.enable_monitoring ? "4. Access Grafana: kubectl port-forward -n monitoring service/prometheus-grafana 3000:80" : ""}
    ${var.enable_data_generator ? "5. Monitor data generation: kubectl logs -n ${kubernetes_namespace.emr_namespace.metadata[0].name} deployment/trading-data-generator" : ""}
  EOT
}

#------------------------------------------------------------------------------
# Cost Information
#------------------------------------------------------------------------------

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    eks_cluster    = "~$73 (EKS control plane)"
    ec2_instances  = "~$200-400 (${var.node_group_desired_size}x ${var.node_group_instance_types[0]} instances)"
    nat_gateway    = var.enable_nat_gateway ? "~$45 (NAT Gateway)" : "$0"
    kinesis_streams = "~$50 (${var.trading_stream_shard_count + var.market_stream_shard_count} shards)"
    s3_storage     = "~$5-25 (depending on usage)"
    cloudwatch     = "~$5-15 (logs and metrics)"
    total_estimated = "~$378-612/month"
    note           = "Costs vary by usage, region, and AWS pricing changes"
  }
}