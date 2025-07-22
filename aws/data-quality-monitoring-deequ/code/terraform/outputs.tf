# outputs.tf
# Output values for real-time data quality monitoring with Deequ on EMR

# =============================================================================
# EMR CLUSTER OUTPUTS
# =============================================================================

output "emr_cluster_id" {
  description = "ID of the EMR cluster"
  value       = aws_emr_cluster.deequ_cluster.id
}

output "emr_cluster_name" {
  description = "Name of the EMR cluster"
  value       = aws_emr_cluster.deequ_cluster.name
}

output "emr_cluster_arn" {
  description = "ARN of the EMR cluster"
  value       = aws_emr_cluster.deequ_cluster.arn
}

output "emr_master_public_dns" {
  description = "Public DNS name of the EMR master node"
  value       = aws_emr_cluster.deequ_cluster.master_public_dns
}

output "emr_cluster_state" {
  description = "Current state of the EMR cluster"
  value       = aws_emr_cluster.deequ_cluster.cluster_state
}

# =============================================================================
# S3 BUCKET OUTPUTS
# =============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for data storage"
  value       = aws_s3_bucket.data_bucket.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.data_bucket.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.data_bucket.bucket_domain_name
}

output "s3_data_paths" {
  description = "S3 paths for different data types"
  value = {
    raw_data        = "s3://${aws_s3_bucket.data_bucket.id}/raw-data/"
    quality_reports = "s3://${aws_s3_bucket.data_bucket.id}/quality-reports/"
    logs           = "s3://${aws_s3_bucket.data_bucket.id}/logs/"
    scripts        = "s3://${aws_s3_bucket.data_bucket.id}/scripts/"
  }
}

# =============================================================================
# SNS TOPIC OUTPUTS
# =============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for data quality alerts"
  value       = aws_sns_topic.data_quality_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for data quality alerts"
  value       = aws_sns_topic.data_quality_alerts.name
}

# =============================================================================
# IAM ROLE OUTPUTS
# =============================================================================

output "emr_service_role_arn" {
  description = "ARN of the EMR service role"
  value       = aws_iam_role.emr_service_role.arn
}

output "emr_ec2_role_arn" {
  description = "ARN of the EMR EC2 instance role"
  value       = aws_iam_role.emr_ec2_role.arn
}

output "emr_instance_profile_arn" {
  description = "ARN of the EMR EC2 instance profile"
  value       = aws_iam_instance_profile.emr_ec2_instance_profile.arn
}

# =============================================================================
# CLOUDWATCH OUTPUTS
# =============================================================================

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value = var.create_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.data_quality[0].dashboard_name}" : null
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for EMR"
  value       = aws_cloudwatch_log_group.emr_logs.name
}

output "cloudwatch_metrics_namespace" {
  description = "CloudWatch metrics namespace for data quality metrics"
  value       = "DataQuality/Deequ"
}

# =============================================================================
# LAMBDA FUNCTION OUTPUTS
# =============================================================================

output "lambda_function_arn" {
  description = "ARN of the Lambda function for automated monitoring"
  value       = aws_lambda_function.automated_monitoring.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function for automated monitoring"
  value       = aws_lambda_function.automated_monitoring.function_name
}

# =============================================================================
# NETWORK OUTPUTS
# =============================================================================

output "vpc_id" {
  description = "VPC ID used for the EMR cluster"
  value       = local.vpc_id
}

output "subnet_id" {
  description = "Subnet ID used for the EMR cluster"
  value       = local.subnet_id
}

output "security_group_id" {
  description = "Security group ID for the EMR cluster"
  value       = aws_security_group.emr_cluster.id
}

# =============================================================================
# DEPLOYMENT COMMANDS
# =============================================================================

output "sample_spark_submit_command" {
  description = "Sample command to submit data quality monitoring job"
  value = "aws emr add-steps --cluster-id ${aws_emr_cluster.deequ_cluster.id} --steps '[{\"Name\":\"DataQualityMonitoring\",\"ActionOnFailure\":\"CONTINUE\",\"HadoopJarStep\":{\"Jar\":\"command-runner.jar\",\"Args\":[\"spark-submit\",\"--deploy-mode\",\"cluster\",\"--master\",\"yarn\",\"s3://${aws_s3_bucket.data_bucket.id}/scripts/deequ-quality-monitor.py\",\"${aws_s3_bucket.data_bucket.id}\",\"s3://${aws_s3_bucket.data_bucket.id}/raw-data/sample_customer_data.csv\",\"${aws_sns_topic.data_quality_alerts.arn}\"]}}]'"
}

output "aws_cli_upload_sample_data" {
  description = "AWS CLI command to upload sample data"
  value = "aws s3 cp sample_data.csv s3://${aws_s3_bucket.data_bucket.id}/raw-data/"
}

output "emr_ssh_command" {
  description = "Command to SSH into EMR master node (requires key pair)"
  value = "aws emr ssh --cluster-id ${aws_emr_cluster.deequ_cluster.id} --key-pair-file your-key-pair.pem"
}

# =============================================================================
# MONITORING URLS
# =============================================================================

output "emr_console_url" {
  description = "URL to EMR cluster in AWS console"
  value = "https://${data.aws_region.current.name}.console.aws.amazon.com/elasticmapreduce/home?region=${data.aws_region.current.name}#cluster-details:${aws_emr_cluster.deequ_cluster.id}"
}

output "s3_console_url" {
  description = "URL to S3 bucket in AWS console"
  value = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.data_bucket.id}?region=${data.aws_region.current.name}"
}

output "cloudwatch_metrics_url" {
  description = "URL to CloudWatch metrics for data quality"
  value = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#metricsV2:graph=~();namespace=DataQuality/Deequ"
}

# =============================================================================
# CONFIGURATION SUMMARY
# =============================================================================

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    emr_cluster_id    = aws_emr_cluster.deequ_cluster.id
    s3_bucket_name    = aws_s3_bucket.data_bucket.id
    sns_topic_arn     = aws_sns_topic.data_quality_alerts.arn
    dashboard_created = var.create_dashboard
    email_configured  = var.notification_email != ""
    encryption_enabled = var.enable_encryption_at_rest
    spot_instances_enabled = var.enable_spot_instances
    environment       = var.environment
  }
}

# =============================================================================
# NEXT STEPS
# =============================================================================

output "next_steps" {
  description = "Next steps to complete the setup"
  value = [
    "1. Wait for EMR cluster to reach WAITING state: aws emr describe-cluster --cluster-id ${aws_emr_cluster.deequ_cluster.id}",
    "2. Upload sample data: aws s3 cp your-data.csv s3://${aws_s3_bucket.data_bucket.id}/raw-data/",
    "3. Submit monitoring job using the sample_spark_submit_command output",
    "4. Monitor metrics in CloudWatch dashboard: ${var.create_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.data_quality[0].dashboard_name}" : "Dashboard not created"}",
    var.notification_email != "" ? "5. Check email for SNS subscription confirmation" : "5. Configure email notifications by setting notification_email variable"
  ]
}