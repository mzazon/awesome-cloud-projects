# Outputs for AWS Resilience Hub and EventBridge Monitoring Infrastructure

#------------------------------------------------------------------------------
# General Information
#------------------------------------------------------------------------------

output "region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_prefix" {
  description = "Prefix used for all resource names"
  value       = local.name_prefix
}

output "deployment_id" {
  description = "Unique deployment identifier"
  value       = random_id.suffix.hex
}

#------------------------------------------------------------------------------
# Network Infrastructure
#------------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC created for the demo application"
  value       = aws_vpc.demo_vpc.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.demo_vpc.cidr_block
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public_subnet_1.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = aws_subnet.private_subnet_2.id
}

output "security_group_id" {
  description = "ID of the security group for demo application"
  value       = aws_security_group.demo_sg.id
}

#------------------------------------------------------------------------------
# Application Infrastructure
#------------------------------------------------------------------------------

output "ec2_instance_id" {
  description = "ID of the EC2 instance running the demo application"
  value       = aws_instance.demo_instance.id
}

output "ec2_instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.demo_instance.public_ip
}

output "ec2_instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.demo_instance.private_ip
}

output "rds_instance_id" {
  description = "ID of the RDS database instance"
  value       = aws_db_instance.demo_db.id
}

output "rds_endpoint" {
  description = "RDS instance endpoint for application connections"
  value       = aws_db_instance.demo_db.endpoint
  sensitive   = true
}

output "rds_port" {
  description = "Port number for RDS database connections"
  value       = aws_db_instance.demo_db.port
}

output "database_name" {
  description = "Name of the database created in RDS"
  value       = aws_db_instance.demo_db.db_name
}

#------------------------------------------------------------------------------
# Resilience Hub Configuration
#------------------------------------------------------------------------------

output "resilience_policy_arn" {
  description = "ARN of the Resilience Hub policy"
  value       = aws_resiliencehub_resiliency_policy.demo_policy.arn
}

output "resilience_policy_name" {
  description = "Name of the Resilience Hub policy"
  value       = aws_resiliencehub_resiliency_policy.demo_policy.name
}

output "resilience_policy_tier" {
  description = "Tier of the Resilience Hub policy"
  value       = aws_resiliencehub_resiliency_policy.demo_policy.tier
}

output "estimated_cost_tier" {
  description = "Estimated cost tier for the resilience policy"
  value       = aws_resiliencehub_resiliency_policy.demo_policy.estimated_cost_tier
}

#------------------------------------------------------------------------------
# Event Processing Infrastructure
#------------------------------------------------------------------------------

output "lambda_function_arn" {
  description = "ARN of the Lambda function for resilience event processing"
  value       = aws_lambda_function.resilience_processor.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.resilience_processor.function_name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for Resilience Hub events"
  value       = aws_cloudwatch_event_rule.resilience_assessment_rule.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.resilience_assessment_rule.name
}

#------------------------------------------------------------------------------
# Monitoring and Alerting
#------------------------------------------------------------------------------

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard for resilience monitoring"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.resilience_dashboard.dashboard_name}"
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.resilience_dashboard.dashboard_name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for resilience alerts"
  value       = aws_sns_topic.resilience_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for alerts"
  value       = aws_sns_topic.resilience_alerts.name
}

output "critical_alarm_name" {
  description = "Name of the critical resilience score alarm"
  value       = aws_cloudwatch_metric_alarm.critical_low_resilience.alarm_name
}

output "warning_alarm_name" {
  description = "Name of the warning resilience score alarm"
  value       = aws_cloudwatch_metric_alarm.warning_low_resilience.alarm_name
}

output "assessment_failure_alarm_name" {
  description = "Name of the assessment failure alarm"
  value       = aws_cloudwatch_metric_alarm.assessment_failures.alarm_name
}

#------------------------------------------------------------------------------
# IAM Resources
#------------------------------------------------------------------------------

output "automation_role_arn" {
  description = "ARN of the IAM role used for automation workflows"
  value       = aws_iam_role.automation_role.arn
}

output "automation_role_name" {
  description = "Name of the IAM role used for automation"
  value       = aws_iam_role.automation_role.name
}

#------------------------------------------------------------------------------
# Connection Information
#------------------------------------------------------------------------------

output "application_endpoints" {
  description = "Connection endpoints for the demo application"
  value = {
    web_server    = "http://${aws_instance.demo_instance.public_ip}"
    ssh_command   = var.allowed_ssh_cidr != "" ? "ssh -i your-key.pem ec2-user@${aws_instance.demo_instance.public_ip}" : "SSH access disabled"
    database_host = aws_db_instance.demo_db.endpoint
    database_port = aws_db_instance.demo_db.port
  }
  sensitive = true
}

#------------------------------------------------------------------------------
# Next Steps Information
#------------------------------------------------------------------------------

output "post_deployment_steps" {
  description = "Next steps to complete the resilience monitoring setup"
  value = {
    step_1 = "Register application with Resilience Hub using AWS CLI or Console"
    step_2 = "Import application resources using: aws resiliencehub import-resources-to-draft-app-version"
    step_3 = "Associate resilience policy with application"
    step_4 = "Run initial resilience assessment"
    step_5 = "Configure email notifications by confirming SNS subscription"
    step_6 = "Monitor resilience events in CloudWatch dashboard"
  }
}

output "useful_commands" {
  description = "Useful AWS CLI commands for managing the resilience monitoring solution"
  value = {
    view_lambda_logs     = "aws logs tail /aws/lambda/${aws_lambda_function.resilience_processor.function_name} --follow"
    check_alarms        = "aws cloudwatch describe-alarms --alarm-names ${aws_cloudwatch_metric_alarm.critical_low_resilience.alarm_name}"
    test_sns_topic      = "aws sns publish --topic-arn ${aws_sns_topic.resilience_alerts.arn} --message 'Test message'"
    view_resilience_policies = "aws resiliencehub list-resiliency-policies"
    view_eventbridge_rules   = "aws events list-rules --name-prefix ${aws_cloudwatch_event_rule.resilience_assessment_rule.name}"
  }
}

#------------------------------------------------------------------------------
# Cost Information
#------------------------------------------------------------------------------

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown for deployed resources (USD)"
  value = {
    ec2_instance     = "~$8.50 (t3.micro in us-east-1)"
    rds_instance     = "~$15.00 (db.t3.micro Multi-AZ)"
    lambda_function  = "~$0.20 (based on 1000 invocations/month)"
    cloudwatch_logs  = "~$1.00 (based on 1GB/month)"
    cloudwatch_metrics = "~$3.00 (custom metrics and alarms)"
    sns_notifications = "~$0.50 (based on 100 notifications/month)"
    data_transfer    = "~$1.00 (minimal inter-AZ transfer)"
    total_estimated  = "~$29.20/month"
    note            = "Costs vary by region and usage patterns. Monitor AWS Cost Explorer for actual costs."
  }
}

#------------------------------------------------------------------------------
# Security Information
#------------------------------------------------------------------------------

output "security_considerations" {
  description = "Important security considerations for the deployed infrastructure"
  value = {
    database_password   = "Change the default database password immediately"
    ssh_access         = var.allowed_ssh_cidr != "" ? "SSH access is enabled - ensure proper key management" : "SSH access is disabled"
    vpc_security       = "Resources are deployed in a dedicated VPC with security groups"
    encryption         = "RDS storage is encrypted at rest"
    iam_roles          = "IAM roles follow least privilege principle"
    monitoring         = "All activities are logged to CloudWatch"
    recommendations    = "Consider enabling VPC Flow Logs and AWS Config for enhanced security monitoring"
  }
}

#------------------------------------------------------------------------------
# Troubleshooting Information
#------------------------------------------------------------------------------

output "troubleshooting_resources" {
  description = "Resources and URLs for troubleshooting common issues"
  value = {
    lambda_logs_group    = aws_cloudwatch_log_group.lambda_logs.name
    eventbridge_metrics  = "AWS/Events namespace in CloudWatch metrics"
    resilience_hub_docs  = "https://docs.aws.amazon.com/resilience-hub/"
    eventbridge_docs    = "https://docs.aws.amazon.com/eventbridge/"
    cloudwatch_console  = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/"
    lambda_console      = "https://${data.aws_region.current.name}.console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions/${aws_lambda_function.resilience_processor.function_name}"
  }
}