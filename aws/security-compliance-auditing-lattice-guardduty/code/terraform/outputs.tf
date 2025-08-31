# outputs.tf
# Outputs for Security Compliance Auditing with VPC Lattice and GuardDuty

# ==============================================================================
# GENERAL OUTPUTS
# ==============================================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.random_suffix
}

# ==============================================================================
# S3 BUCKET OUTPUTS
# ==============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for compliance reports"
  value       = aws_s3_bucket.compliance_reports.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for compliance reports"
  value       = aws_s3_bucket.compliance_reports.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.compliance_reports.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.compliance_reports.bucket_regional_domain_name
}

# ==============================================================================
# GUARDDUTY OUTPUTS
# ==============================================================================

output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector"
  value       = aws_guardduty_detector.security_monitoring.id
}

output "guardduty_detector_arn" {
  description = "ARN of the GuardDuty detector"
  value       = aws_guardduty_detector.security_monitoring.arn
}

output "guardduty_finding_frequency" {
  description = "GuardDuty finding publication frequency"
  value       = aws_guardduty_detector.security_monitoring.finding_publishing_frequency
}

# ==============================================================================
# SNS OUTPUTS
# ==============================================================================

output "sns_topic_name" {
  description = "Name of the SNS topic for security alerts"
  value       = aws_sns_topic.security_alerts.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for security alerts"
  value       = aws_sns_topic.security_alerts.arn
}

output "sns_topic_display_name" {
  description = "Display name of the SNS topic"
  value       = aws_sns_topic.security_alerts.display_name
}

output "email_subscription_arn" {
  description = "ARN of the email subscription (if created)"
  value       = var.notification_email != "" ? aws_sns_topic_subscription.security_alerts_email[0].arn : null
}

# ==============================================================================
# CLOUDWATCH LOGS OUTPUTS
# ==============================================================================

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for VPC Lattice logs"
  value       = aws_cloudwatch_log_group.vpc_lattice_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for VPC Lattice logs"
  value       = aws_cloudwatch_log_group.vpc_lattice_logs.arn
}

output "cloudwatch_log_group_retention_days" {
  description = "Retention period in days for CloudWatch logs"
  value       = aws_cloudwatch_log_group.vpc_lattice_logs.retention_in_days
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

# ==============================================================================
# LAMBDA FUNCTION OUTPUTS
# ==============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda security processor function"
  value       = aws_lambda_function.security_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda security processor function"
  value       = aws_lambda_function.security_processor.arn
}

output "lambda_function_qualified_arn" {
  description = "Qualified ARN of the Lambda function (includes version)"
  value       = aws_lambda_function.security_processor.qualified_arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.security_processor.invoke_arn
}

output "lambda_function_runtime" {
  description = "Runtime environment of the Lambda function"
  value       = aws_lambda_function.security_processor.runtime
}

output "lambda_function_timeout" {
  description = "Timeout configuration of the Lambda function"
  value       = aws_lambda_function.security_processor.timeout
}

output "lambda_function_memory_size" {
  description = "Memory size configuration of the Lambda function"
  value       = aws_lambda_function.security_processor.memory_size
}

output "lambda_role_name" {
  description = "Name of the IAM role for the Lambda function"
  value       = aws_iam_role.lambda_security_processor.name
}

output "lambda_role_arn" {
  description = "ARN of the IAM role for the Lambda function"
  value       = aws_iam_role.lambda_security_processor.arn
}

# ==============================================================================
# CLOUDWATCH DASHBOARD OUTPUTS
# ==============================================================================

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.security_compliance.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.security_compliance.dashboard_name}"
}

# ==============================================================================
# VPC LATTICE OUTPUTS (if created)
# ==============================================================================

output "vpc_lattice_service_network_id" {
  description = "ID of the VPC Lattice service network (if created)"
  value       = var.create_demo_vpc_lattice ? aws_vpclattice_service_network.security_demo[0].id : null
}

output "vpc_lattice_service_network_arn" {
  description = "ARN of the VPC Lattice service network (if created)"
  value       = var.create_demo_vpc_lattice ? aws_vpclattice_service_network.security_demo[0].arn : null
}

output "vpc_lattice_service_network_name" {
  description = "Name of the VPC Lattice service network (if created)"
  value       = var.create_demo_vpc_lattice ? aws_vpclattice_service_network.security_demo[0].name : null
}

output "vpc_lattice_access_log_subscription_id" {
  description = "ID of the VPC Lattice access log subscription (if created)"
  value       = var.create_demo_vpc_lattice ? aws_vpclattice_access_log_subscription.security_demo[0].id : null
}

output "vpc_lattice_access_log_subscription_arn" {
  description = "ARN of the VPC Lattice access log subscription (if created)"
  value       = var.create_demo_vpc_lattice ? aws_vpclattice_access_log_subscription.security_demo[0].arn : null
}

# ==============================================================================
# CLOUDWATCH ALARMS OUTPUTS
# ==============================================================================

output "high_error_rate_alarm_name" {
  description = "Name of the high error rate CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_error_rate.alarm_name
}

output "high_error_rate_alarm_arn" {
  description = "ARN of the high error rate CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.high_error_rate.arn
}

output "lambda_errors_alarm_name" {
  description = "Name of the Lambda errors CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
}

output "lambda_errors_alarm_arn" {
  description = "ARN of the Lambda errors CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.arn
}

# ==============================================================================
# SUBSCRIPTION FILTER OUTPUTS
# ==============================================================================

output "log_subscription_filter_name" {
  description = "Name of the CloudWatch log subscription filter"
  value       = aws_cloudwatch_log_subscription_filter.security_compliance_filter.name
}

output "log_subscription_filter_arn" {
  description = "ARN of the CloudWatch log subscription filter"
  value       = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:destination:${aws_cloudwatch_log_subscription_filter.security_compliance_filter.name}"
}

# ==============================================================================
# SECURITY AND COMPLIANCE OUTPUTS
# ==============================================================================

output "compliance_report_s3_path" {
  description = "S3 path where compliance reports are stored"
  value       = "s3://${aws_s3_bucket.compliance_reports.bucket}/compliance-reports/"
}

output "encryption_at_rest_enabled" {
  description = "Whether encryption at rest is enabled for S3 bucket"
  value       = true
}

output "encryption_in_transit_enabled" {
  description = "Whether encryption in transit is enabled"
  value       = var.enable_encryption_in_transit
}

# ==============================================================================
# OPERATIONAL OUTPUTS
# ==============================================================================

output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

output "terraform_workspace" {
  description = "Terraform workspace used for deployment"
  value       = terraform.workspace
}

# ==============================================================================
# INTEGRATION OUTPUTS
# ==============================================================================

output "integration_guide" {
  description = "Guide for integrating with existing VPC Lattice service networks"
  value = {
    log_group_arn = aws_cloudwatch_log_group.vpc_lattice_logs.arn
    instructions = "To integrate with existing VPC Lattice service networks, create access log subscriptions pointing to the log group ARN above. Use the AWS CLI command: aws vpc-lattice create-access-log-subscription --resource-identifier <service-network-id> --destination-arn ${aws_cloudwatch_log_group.vpc_lattice_logs.arn}"
  }
}

output "testing_guide" {
  description = "Guide for testing the security monitoring system"
  value = {
    test_lambda_command = "aws lambda invoke --function-name ${aws_lambda_function.security_processor.function_name} --payload file://test-payload.json response.json"
    check_logs_command  = "aws logs tail ${aws_cloudwatch_log_group.lambda_logs.name} --follow"
    check_metrics_command = "aws cloudwatch get-metric-statistics --namespace Security/VPCLattice --metric-name RequestCount --start-time $(date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%SZ') --end-time $(date -u '+%Y-%m-%dT%H:%M:%SZ') --period 300 --statistics Sum"
    dashboard_url = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.security_compliance.dashboard_name}"
  }
}

# ==============================================================================
# COST ESTIMATION OUTPUTS
# ==============================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the security monitoring infrastructure"
  value = {
    guardduty     = "~$4.64 per month (based on AWS CloudTrail events, DNS logs, and VPC Flow Logs)"
    lambda        = "~$2-5 per month (based on 100,000 invocations)"
    cloudwatch    = "~$2-3 per month (logs ingestion and storage)"
    s3            = "~$1-2 per month (compliance reports storage)"
    sns           = "~$0.50 per month (100 notifications)"
    total         = "~$10-15 per month (varies based on usage)"
    note          = "Costs may vary based on region, usage patterns, and data volume. GuardDuty offers 30-day free trial for new accounts."
  }
}

# ==============================================================================
# NEXT STEPS OUTPUTS
# ==============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    "1_configure_email" = "Confirm the email subscription for SNS alerts if notification_email was provided"
    "2_test_system"     = "Use the testing commands in testing_guide output to verify the system is working"
    "3_integrate_vpc_lattice" = "Configure existing VPC Lattice service networks to send logs to the created log group"
    "4_customize_alerts" = "Adjust CloudWatch alarm thresholds based on your security requirements"
    "5_review_dashboard" = "Access the CloudWatch dashboard to monitor security metrics"
    "6_setup_automation" = "Consider implementing automated responses to security violations"
  }
}