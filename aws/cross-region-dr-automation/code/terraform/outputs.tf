# Outputs for AWS Elastic Disaster Recovery (DRS) Automation Infrastructure
# These outputs provide important information about the deployed resources
# and can be used for integration with other systems or verification

# ===================================================================
# Project Information
# ===================================================================

output "project_name" {
  description = "The generated project name with unique suffix"
  value       = local.project_name
}

output "deployment_region" {
  description = "Primary deployment region"
  value       = local.primary_region
}

output "disaster_recovery_region" {
  description = "Disaster recovery region"
  value       = local.dr_region
}

output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = local.account_id
}

# ===================================================================
# DRS Configuration
# ===================================================================

output "drs_replication_template_id" {
  description = "DRS replication configuration template ID"
  value       = aws_drs_replication_configuration_template.primary.id
}

output "drs_staging_subnet_id" {
  description = "Subnet ID used for DRS staging area"
  value       = aws_subnet.dr_private.id
}

output "drs_replication_security_group_id" {
  description = "Security group ID for DRS replication servers"
  value       = aws_security_group.drs_replication.id
}

# ===================================================================
# Network Infrastructure
# ===================================================================

output "dr_vpc_id" {
  description = "VPC ID for disaster recovery environment"
  value       = aws_vpc.dr_vpc.id
}

output "dr_vpc_cidr" {
  description = "CIDR block of the DR VPC"
  value       = aws_vpc.dr_vpc.cidr_block
}

output "dr_public_subnet_id" {
  description = "Public subnet ID in DR region"
  value       = aws_subnet.dr_public.id
}

output "dr_private_subnet_id" {
  description = "Private subnet ID in DR region"
  value       = aws_subnet.dr_private.id
}

output "dr_internet_gateway_id" {
  description = "Internet Gateway ID for DR VPC"
  value       = aws_internet_gateway.dr_igw.id
}

output "dr_instances_security_group_id" {
  description = "Security group ID for DR recovery instances"
  value       = aws_security_group.dr_instances.id
}

# ===================================================================
# IAM Resources
# ===================================================================

output "automation_role_arn" {
  description = "ARN of the IAM role used for DR automation"
  value       = aws_iam_role.dr_automation.arn
}

output "automation_role_name" {
  description = "Name of the IAM role used for DR automation"
  value       = aws_iam_role.dr_automation.name
}

# ===================================================================
# Notification Resources
# ===================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for DR alerts"
  value       = aws_sns_topic.dr_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for DR alerts"
  value       = aws_sns_topic.dr_alerts.name
}

# ===================================================================
# Lambda Functions
# ===================================================================

output "failover_lambda_arn" {
  description = "ARN of the automated failover Lambda function"
  value       = aws_lambda_function.automated_failover.arn
}

output "failover_lambda_name" {
  description = "Name of the automated failover Lambda function"
  value       = aws_lambda_function.automated_failover.function_name
}

output "testing_lambda_arn" {
  description = "ARN of the DR testing Lambda function"
  value       = aws_lambda_function.dr_testing.arn
}

output "testing_lambda_name" {
  description = "Name of the DR testing Lambda function"
  value       = aws_lambda_function.dr_testing.function_name
}

output "failback_lambda_arn" {
  description = "ARN of the automated failback Lambda function"
  value       = aws_lambda_function.automated_failback.arn
}

output "failback_lambda_name" {
  description = "Name of the automated failback Lambda function"
  value       = aws_lambda_function.automated_failback.function_name
}

# ===================================================================
# Step Functions
# ===================================================================

output "step_functions_state_machine_arn" {
  description = "ARN of the Step Functions state machine for DR orchestration"
  value       = aws_sfn_state_machine.dr_orchestration.arn
}

output "step_functions_state_machine_name" {
  description = "Name of the Step Functions state machine for DR orchestration"
  value       = aws_sfn_state_machine.dr_orchestration.name
}

# ===================================================================
# Monitoring Resources
# ===================================================================

output "application_health_alarm_name" {
  description = "Name of the CloudWatch alarm for application health"
  value       = aws_cloudwatch_metric_alarm.application_health.alarm_name
}

output "replication_lag_alarm_name" {
  description = "Name of the CloudWatch alarm for DRS replication lag"
  value       = aws_cloudwatch_metric_alarm.drs_replication_lag.alarm_name
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard for DR monitoring"
  value       = aws_cloudwatch_dashboard.dr_monitoring.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://${local.primary_region}.console.aws.amazon.com/cloudwatch/home?region=${local.primary_region}#dashboards:name=${aws_cloudwatch_dashboard.dr_monitoring.dashboard_name}"
}

# ===================================================================
# Automation Resources
# ===================================================================

output "monthly_dr_drill_rule_name" {
  description = "Name of the EventBridge rule for monthly DR drills"
  value       = aws_cloudwatch_event_rule.monthly_dr_drill.name
}

output "monthly_dr_drill_rule_arn" {
  description = "ARN of the EventBridge rule for monthly DR drills"
  value       = aws_cloudwatch_event_rule.monthly_dr_drill.arn
}

# ===================================================================
# SSM Parameters
# ===================================================================

output "dr_project_config_parameter" {
  description = "SSM parameter name containing DR project configuration"
  value       = aws_ssm_parameter.dr_project_config.name
}

output "drs_template_parameter" {
  description = "SSM parameter name containing DRS template ID"
  value       = aws_ssm_parameter.drs_template_id.name
}

# ===================================================================
# Agent Installation Information
# ===================================================================

output "drs_agent_installation_commands" {
  description = "Commands to install DRS agent on source servers"
  value = {
    linux = {
      rhel_centos = "sudo yum update -y && wget https://aws-elastic-disaster-recovery-${local.primary_region}.s3.amazonaws.com/latest/linux/aws-replication-installer-init.py && sudo python3 aws-replication-installer-init.py --region ${local.primary_region} --aws-access-key-id $AWS_ACCESS_KEY_ID --aws-secret-access-key $AWS_SECRET_ACCESS_KEY --no-prompt"
      ubuntu_debian = "sudo apt-get update -y && wget https://aws-elastic-disaster-recovery-${local.primary_region}.s3.amazonaws.com/latest/linux/aws-replication-installer-init.py && sudo python3 aws-replication-installer-init.py --region ${local.primary_region} --aws-access-key-id $AWS_ACCESS_KEY_ID --aws-secret-access-key $AWS_SECRET_ACCESS_KEY --no-prompt"
    }
    windows = "Download from https://aws-elastic-disaster-recovery-${local.primary_region}.s3.amazonaws.com/latest/windows/AwsReplicationWindowsInstaller.exe and run with appropriate credentials"
  }
}

# ===================================================================
# Validation Commands
# ===================================================================

output "validation_commands" {
  description = "AWS CLI commands to validate the DR setup"
  value = {
    check_drs_service = "aws drs describe-replication-configuration-templates --region ${local.primary_region}"
    list_source_servers = "aws drs describe-source-servers --region ${local.primary_region}"
    test_failover_function = "aws lambda invoke --function-name ${aws_lambda_function.automated_failover.function_name} --payload '{\"test\": true}' --region ${local.primary_region} failover-test-output.json"
    start_dr_orchestration = "aws stepfunctions start-execution --state-machine-arn ${aws_sfn_state_machine.dr_orchestration.arn} --input '{\"testMode\": true}' --region ${local.primary_region}"
    view_dashboard = "https://${local.primary_region}.console.aws.amazon.com/cloudwatch/home?region=${local.primary_region}#dashboards:name=${aws_cloudwatch_dashboard.dr_monitoring.dashboard_name}"
  }
}

# ===================================================================
# Cleanup Commands
# ===================================================================

output "cleanup_commands" {
  description = "Commands to clean up DR resources"
  value = {
    terminate_drill_instances = "aws drs terminate-recovery-instances --recovery-instance-ids $(aws drs describe-recovery-instances --query 'recoveryInstances[?isDrill==`true`].recoveryInstanceID' --output text --region ${local.dr_region}) --region ${local.dr_region}"
    stop_replication = "aws drs stop-replication --source-server-ids $(aws drs describe-source-servers --query 'sourceServers[].sourceServerID' --output text --region ${local.primary_region}) --region ${local.primary_region}"
    terraform_destroy = "terraform destroy -auto-approve"
  }
}

# ===================================================================
# Cost Information
# ===================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for DR infrastructure"
  value = {
    base_infrastructure = "DR VPC, subnets, and security groups: ~$5-10/month"
    drs_replication = "DRS staging storage and data transfer: ~$50-200/month (varies by data volume)"
    lambda_functions = "Lambda executions: ~$1-5/month (depends on frequency)"
    cloudwatch = "CloudWatch alarms and dashboard: ~$5-15/month"
    sns_notifications = "SNS notifications: ~$1-3/month"
    total_estimate = "$62-233/month (excluding recovery instance costs during actual failover)"
  }
}

# ===================================================================
# Next Steps
# ===================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Install DRS agents on source servers using the provided installation commands",
    "2. Configure source servers for replication using the DRS console",
    "3. Test the automated failover function using the validation commands",
    "4. Set up Route 53 health checks for your applications",
    "5. Subscribe to the SNS topic for DR notifications",
    "6. Schedule regular DR drills using the testing Lambda function",
    "7. Review and customize CloudWatch alarms for your specific applications",
    "8. Document your DR procedures and train your team"
  ]
}

# ===================================================================
# Important Notes
# ===================================================================

output "important_notes" {
  description = "Important notes about the DR deployment"
  value = {
    security = "Ensure IAM permissions follow least privilege principles in production"
    costs = "DRS charges are based on staged storage and data transfer - monitor costs regularly"
    testing = "Regular DR testing is crucial - automate testing with the provided Lambda functions"
    networking = "Verify network connectivity between source servers and AWS before agent installation"
    compliance = "Review security group rules and encryption settings for compliance requirements"
    monitoring = "Set up custom metrics for your applications in the CloudWatch dashboard"
  }
}