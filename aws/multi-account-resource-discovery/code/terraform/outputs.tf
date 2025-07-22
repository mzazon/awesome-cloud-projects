# Automated Multi-Account Resource Discovery - Terraform Outputs
# This file defines outputs that provide important information about deployed resources

#============================================================================
# PROJECT INFORMATION
#============================================================================

output "project_name" {
  description = "The unique project name used for resource naming"
  value       = local.project_name
}

output "environment" {
  description = "The environment this solution is deployed in"
  value       = var.environment
}

output "deployment_region" {
  description = "The AWS region where the solution is deployed"
  value       = data.aws_region.current.name
}

output "organization_id" {
  description = "AWS Organization ID this solution monitors"
  value       = data.aws_organizations_organization.current.id
}

output "management_account_id" {
  description = "AWS account ID of the Organizations management account"
  value       = data.aws_caller_identity.current.account_id
}

#============================================================================
# AWS RESOURCE EXPLORER OUTPUTS
#============================================================================

output "resource_explorer_index_arn" {
  description = "ARN of the Resource Explorer aggregated index"
  value       = aws_resourceexplorer2_index.main.arn
}

output "resource_explorer_index_type" {
  description = "Type of the Resource Explorer index (AGGREGATOR for management account)"
  value       = aws_resourceexplorer2_index.main.type
}

output "resource_explorer_view_arn" {
  description = "ARN of the Resource Explorer organization view"
  value       = aws_resourceexplorer2_view.organization.arn
}

output "resource_explorer_view_name" {
  description = "Name of the Resource Explorer organization view"
  value       = aws_resourceexplorer2_view.organization.name
}

#============================================================================
# AWS CONFIG OUTPUTS
#============================================================================

output "config_aggregator_arn" {
  description = "ARN of the AWS Config organizational aggregator"
  value       = aws_config_configuration_aggregator.organization.arn
}

output "config_aggregator_name" {
  description = "Name of the AWS Config organizational aggregator"
  value       = aws_config_configuration_aggregator.organization.name
}

output "config_recorder_name" {
  description = "Name of the AWS Config configuration recorder"
  value       = aws_config_configuration_recorder.main.name
}

output "config_delivery_channel_name" {
  description = "Name of the AWS Config delivery channel"
  value       = aws_config_delivery_channel.main.name
}

output "config_bucket_name" {
  description = "Name of the S3 bucket storing Config data"
  value       = aws_s3_bucket.config.bucket
}

output "config_bucket_arn" {
  description = "ARN of the S3 bucket storing Config data"
  value       = aws_s3_bucket.config.arn
}

output "config_rules" {
  description = "Map of deployed Config rules and their ARNs"
  value = {
    s3_bucket_public_access_prohibited = aws_config_config_rule.s3_bucket_public_access_prohibited.arn
    ec2_security_group_attached_to_eni = aws_config_config_rule.ec2_security_group_attached_to_eni.arn
    root_access_key_check              = aws_config_config_rule.root_access_key_check.arn
    encrypted_volumes                  = aws_config_config_rule.encrypted_volumes.arn
    iam_password_policy               = aws_config_config_rule.iam_password_policy.arn
  }
}

#============================================================================
# LAMBDA FUNCTION OUTPUTS
#============================================================================

output "lambda_function_arn" {
  description = "ARN of the resource discovery and compliance processing Lambda function"
  value       = aws_lambda_function.processor.arn
}

output "lambda_function_name" {
  description = "Name of the resource discovery and compliance processing Lambda function"
  value       = aws_lambda_function.processor.function_name
}

output "lambda_function_role_arn" {
  description = "ARN of the Lambda function's execution role"
  value       = aws_iam_role.lambda.arn
}

output "lambda_invoke_arn" {
  description = "ARN to be used for invoking Lambda function from other services"
  value       = aws_lambda_function.processor.invoke_arn
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda.arn
}

#============================================================================
# EVENTBRIDGE OUTPUTS
#============================================================================

output "eventbridge_config_rule_arn" {
  description = "ARN of the EventBridge rule for Config compliance events"
  value       = aws_cloudwatch_event_rule.config_compliance.arn
}

output "eventbridge_config_rule_name" {
  description = "Name of the EventBridge rule for Config compliance events"
  value       = aws_cloudwatch_event_rule.config_compliance.name
}

output "eventbridge_discovery_schedule_rule_arn" {
  description = "ARN of the EventBridge rule for scheduled resource discovery"
  value       = aws_cloudwatch_event_rule.discovery_schedule.arn
}

output "eventbridge_discovery_schedule_rule_name" {
  description = "Name of the EventBridge rule for scheduled resource discovery"
  value       = aws_cloudwatch_event_rule.discovery_schedule.name
}

output "discovery_schedule" {
  description = "Schedule expression for automated resource discovery"
  value       = var.discovery_schedule
}

#============================================================================
# MONITORING OUTPUTS
#============================================================================

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard (if created)"
  value = var.create_dashboard ? "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.main[0].dashboard_name}" : null
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard (if created)"
  value = var.create_dashboard ? aws_cloudwatch_dashboard.main[0].dashboard_name : null
}

#============================================================================
# SECURITY AND COMPLIANCE OUTPUTS
#============================================================================

output "service_linked_role_arn" {
  description = "ARN of the AWS Config service-linked role"
  value       = data.aws_iam_service_linked_role.config.arn
}

output "compliance_monitoring_enabled" {
  description = "Whether compliance monitoring is enabled"
  value       = true
}

output "config_rules_count" {
  description = "Number of Config rules deployed for compliance monitoring"
  value       = length(aws_config_config_rule.s3_bucket_public_access_prohibited.*.arn) + 
                length(aws_config_config_rule.ec2_security_group_attached_to_eni.*.arn) +
                length(aws_config_config_rule.root_access_key_check.*.arn) +
                length(aws_config_config_rule.encrypted_volumes.*.arn) +
                length(aws_config_config_rule.iam_password_policy.*.arn)
}

#============================================================================
# NOTIFICATION OUTPUTS
#============================================================================

output "notification_topic_arn" {
  description = "ARN of the SNS topic for notifications (if configured)"
  value       = var.notification_topic_arn
  sensitive   = false
}

output "dlq_arn" {
  description = "ARN of the Dead Letter Queue for failed invocations (if configured)"
  value       = var.dlq_arn
  sensitive   = false
}

#============================================================================
# OPERATIONAL OUTPUTS
#============================================================================

output "aws_console_urls" {
  description = "Useful AWS console URLs for managing and monitoring the solution"
  value = {
    config_console = "https://console.aws.amazon.com/config/home?region=${data.aws_region.current.name}#/dashboard"
    
    config_aggregator = "https://console.aws.amazon.com/config/home?region=${data.aws_region.current.name}#/aggregators/details/${aws_config_configuration_aggregator.organization.name}"
    
    resource_explorer = "https://console.aws.amazon.com/resource-explorer/home?region=${data.aws_region.current.name}#/search"
    
    lambda_function = "https://console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions/${aws_lambda_function.processor.function_name}"
    
    lambda_logs = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.lambda.name, "/", "%252F")}"
    
    eventbridge_rules = "https://console.aws.amazon.com/events/home?region=${data.aws_region.current.name}#/rules"
    
    s3_config_bucket = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.config.bucket}"
  }
}

#============================================================================
# VALIDATION AND TESTING OUTPUTS
#============================================================================

output "validation_commands" {
  description = "CLI commands for validating the deployed solution"
  value = {
    # Test Resource Explorer search
    resource_explorer_search = "aws resource-explorer-2 search --query-string 'service:ec2' --max-results 10 --region ${data.aws_region.current.name}"
    
    # Check Config aggregator status
    config_aggregator_status = "aws configservice describe-configuration-aggregators --configuration-aggregator-names ${aws_config_configuration_aggregator.organization.name} --region ${data.aws_region.current.name}"
    
    # Get compliance summary
    compliance_summary = "aws configservice get-aggregate-compliance-summary --configuration-aggregator-name ${aws_config_configuration_aggregator.organization.name} --region ${data.aws_region.current.name}"
    
    # Test Lambda function
    lambda_test = "aws lambda invoke --function-name ${aws_lambda_function.processor.function_name} --payload '{\"source\":\"test\"}' --region ${data.aws_region.current.name} /tmp/lambda-response.json && cat /tmp/lambda-response.json"
    
    # Check EventBridge rules
    eventbridge_rules = "aws events list-rules --name-prefix ${local.project_name} --region ${data.aws_region.current.name}"
    
    # View Lambda logs
    lambda_logs = "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.lambda.name} --region ${data.aws_region.current.name}"
  }
}

#============================================================================
# RESOURCE DISCOVERY GUIDANCE
#============================================================================

output "resource_discovery_queries" {
  description = "Example Resource Explorer queries for different resource types"
  value = {
    all_ec2_instances     = "resourcetype:AWS::EC2::Instance"
    all_s3_buckets       = "service:s3"
    all_rds_databases    = "service:rds"
    all_lambda_functions = "service:lambda"
    all_iam_roles        = "resourcetype:AWS::IAM::Role"
    resources_by_account = "accountid:${data.aws_caller_identity.current.account_id}"
    resources_by_region  = "region:${data.aws_region.current.name}"
    untagged_resources   = "-tag:*"
  }
}

#============================================================================
# DEPLOYMENT INFORMATION
#============================================================================

output "deployment_summary" {
  description = "Summary of deployed resources and their purposes"
  value = {
    solution_name = "Automated Multi-Account Resource Discovery"
    components_deployed = [
      "AWS Resource Explorer (Aggregated Index)",
      "AWS Config (Organization Aggregator)",
      "Lambda Function (Event Processor)",
      "EventBridge Rules (Automation)",
      "CloudWatch Dashboard (Monitoring)",
      "S3 Bucket (Config Storage)",
      "IAM Roles and Policies",
      "Config Compliance Rules"
    ]
    
    key_capabilities = [
      "Cross-account resource search and discovery",
      "Automated compliance monitoring",
      "Real-time compliance violation detection",
      "Scheduled resource inventory updates",
      "Centralized governance and reporting"
    ]
    
    next_steps = [
      "1. Configure trusted access in AWS Organizations (if not already done)",
      "2. Deploy Resource Explorer local indexes in member accounts",
      "3. Set up SNS topic for notifications (optional)",
      "4. Customize Config rules based on your compliance requirements",
      "5. Review CloudWatch dashboard and set up additional alerts"
    ]
  }
}

#============================================================================
# COST ESTIMATION
#============================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the solution (USD, approximate)"
  value = {
    config_rules = "~$2 per Config rule per region"
    config_configuration_items = "~$0.003 per configuration item recorded"
    config_aggregator = "No additional charge for organizational aggregator"
    resource_explorer = "No additional charge for Resource Explorer"
    lambda_execution = "~$0.20 per million requests + compute time"
    cloudwatch_logs = "~$0.50 per GB ingested"
    s3_storage = "~$0.023 per GB stored"
    eventbridge = "No additional charge for rules, ~$1.00 per million custom events"
    
    estimated_total_range = "$5-25 per month (varies by organization size and activity)"
    
    cost_optimization_tips = [
      "Enable S3 lifecycle policies for Config data",
      "Adjust log retention periods based on requirements", 
      "Use Lambda reserved concurrency if needed",
      "Monitor and optimize Config rule frequency"
    ]
  }
}