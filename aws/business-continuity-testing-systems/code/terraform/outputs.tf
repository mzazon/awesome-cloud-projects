# General Outputs
output "project_id" {
  description = "Unique project identifier for this BC testing framework"
  value       = local.project_id
}

output "common_name" {
  description = "Common name prefix used for all resources"
  value       = local.common_name
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# Security Outputs
output "kms_key_id" {
  description = "KMS key ID for encryption (if enabled)"
  value       = var.enable_encryption ? aws_kms_key.bc_testing[0].id : null
}

output "kms_key_arn" {
  description = "KMS key ARN for encryption (if enabled)"
  value       = var.enable_encryption ? aws_kms_key.bc_testing[0].arn : null
}

output "automation_role_arn" {
  description = "IAM role ARN for business continuity testing automation"
  value       = aws_iam_role.bc_automation.arn
}

output "automation_role_name" {
  description = "IAM role name for business continuity testing automation"
  value       = aws_iam_role.bc_automation.name
}

# Storage Outputs
output "test_results_bucket_name" {
  description = "S3 bucket name for storing test results and compliance reports"
  value       = aws_s3_bucket.test_results.bucket
}

output "test_results_bucket_arn" {
  description = "S3 bucket ARN for storing test results and compliance reports"
  value       = aws_s3_bucket.test_results.arn
}

output "test_results_bucket_domain_name" {
  description = "S3 bucket domain name for test results storage"
  value       = aws_s3_bucket.test_results.bucket_domain_name
}

# Notification Outputs
output "sns_topic_arn" {
  description = "SNS topic ARN for business continuity testing notifications"
  value       = aws_sns_topic.bc_alerts.arn
}

output "sns_topic_name" {
  description = "SNS topic name for business continuity testing notifications"
  value       = aws_sns_topic.bc_alerts.name
}

output "notification_email" {
  description = "Email address configured for BC testing notifications"
  value       = var.notification_email
  sensitive   = true
}

# Systems Manager Outputs
output "ssm_documents" {
  description = "Systems Manager automation documents created for BC testing"
  value = {
    backup_validation = {
      name = aws_ssm_document.backup_validation.name
      arn  = aws_ssm_document.backup_validation.arn
    }
    database_recovery = {
      name = aws_ssm_document.database_recovery.name
      arn  = aws_ssm_document.database_recovery.arn
    }
    application_failover = {
      name = aws_ssm_document.application_failover.name
      arn  = aws_ssm_document.application_failover.arn
    }
  }
}

# Lambda Function Outputs
output "lambda_functions" {
  description = "Lambda functions created for BC testing framework"
  value = {
    orchestrator = {
      function_name = aws_lambda_function.orchestrator.function_name
      arn          = aws_lambda_function.orchestrator.arn
      invoke_arn   = aws_lambda_function.orchestrator.invoke_arn
    }
    compliance_reporter = {
      function_name = aws_lambda_function.compliance_reporter.function_name
      arn          = aws_lambda_function.compliance_reporter.arn
      invoke_arn   = aws_lambda_function.compliance_reporter.invoke_arn
    }
    manual_executor = {
      function_name = aws_lambda_function.manual_executor.function_name
      arn          = aws_lambda_function.manual_executor.arn
      invoke_arn   = aws_lambda_function.manual_executor.invoke_arn
    }
  }
}

# EventBridge Outputs
output "eventbridge_rules" {
  description = "EventBridge rules for scheduled BC testing"
  value = {
    daily_tests = {
      name = aws_cloudwatch_event_rule.daily_tests.name
      arn  = aws_cloudwatch_event_rule.daily_tests.arn
    }
    weekly_tests = {
      name = aws_cloudwatch_event_rule.weekly_tests.name
      arn  = aws_cloudwatch_event_rule.weekly_tests.arn
    }
    monthly_tests = {
      name = aws_cloudwatch_event_rule.monthly_tests.name
      arn  = aws_cloudwatch_event_rule.monthly_tests.arn
    }
    compliance_reporting = {
      name = aws_cloudwatch_event_rule.compliance_reporting.name
      arn  = aws_cloudwatch_event_rule.compliance_reporting.arn
    }
  }
}

# Monitoring Outputs
output "cloudwatch_dashboard_url" {
  description = "CloudWatch dashboard URL for BC testing monitoring"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=BC-Testing-${local.project_id}"
}

output "cloudwatch_dashboard_name" {
  description = "CloudWatch dashboard name for BC testing monitoring"
  value       = aws_cloudwatch_dashboard.bc_testing.dashboard_name
}

output "log_groups" {
  description = "CloudWatch log groups for Lambda functions"
  value = {
    orchestrator        = aws_cloudwatch_log_group.orchestrator.name
    compliance_reporter = aws_cloudwatch_log_group.compliance_reporter.name
    manual_executor     = aws_cloudwatch_log_group.manual_executor.name
  }
}

# Testing Configuration Outputs
output "test_schedules" {
  description = "Configured test schedules for different BC testing types"
  value       = var.test_schedules
}

output "test_configuration" {
  description = "Test configuration parameters"
  value = {
    test_instance_id         = var.test_instance_id != "" ? var.test_instance_id : "Not configured"
    backup_vault_name        = var.backup_vault_name
    db_instance_identifier   = var.db_instance_identifier != "" ? var.db_instance_identifier : "Not configured"
    primary_alb_arn         = var.primary_alb_arn != "" ? var.primary_alb_arn : "Not configured"
    secondary_alb_arn       = var.secondary_alb_arn != "" ? var.secondary_alb_arn : "Not configured"
    route53_hosted_zone_id  = var.route53_hosted_zone_id != "" ? var.route53_hosted_zone_id : "Not configured"
    domain_name             = var.domain_name != "" ? var.domain_name : "Not configured"
  }
}

# Manual Testing Commands
output "manual_testing_commands" {
  description = "Commands for manual testing execution"
  value = {
    trigger_backup_test = "aws lambda invoke --function-name ${aws_lambda_function.manual_executor.function_name} --payload '{\"testType\":\"manual\",\"components\":[\"backup\"]}' response.json"
    trigger_database_test = "aws lambda invoke --function-name ${aws_lambda_function.manual_executor.function_name} --payload '{\"testType\":\"manual\",\"components\":[\"database\"]}' response.json"
    trigger_application_test = "aws lambda invoke --function-name ${aws_lambda_function.manual_executor.function_name} --payload '{\"testType\":\"manual\",\"components\":[\"application\"]}' response.json"
    trigger_comprehensive_test = "aws lambda invoke --function-name ${aws_lambda_function.manual_executor.function_name} --payload '{\"testType\":\"comprehensive\",\"components\":[\"backup\",\"database\",\"application\"]}' response.json"
  }
}

# Security and Compliance
output "security_features" {
  description = "Security features enabled in the BC testing framework"
  value = {
    encryption_enabled      = var.enable_encryption
    s3_versioning_enabled   = var.enable_s3_versioning
    s3_public_access_blocked = true
    iam_least_privilege     = true
    kms_key_rotation       = var.enable_encryption
  }
}

output "compliance_features" {
  description = "Compliance features available in the BC testing framework"
  value = {
    automated_reporting     = true
    audit_trail_logs       = true
    test_result_retention   = "${var.s3_lifecycle_rules.expiration_days} days"
    scheduled_testing       = true
    notification_alerts     = true
  }
}

# Cost Optimization
output "cost_optimization_features" {
  description = "Cost optimization features implemented"
  value = {
    s3_lifecycle_policies = {
      transition_to_ia_days      = var.s3_lifecycle_rules.transition_to_ia_days
      transition_to_glacier_days = var.s3_lifecycle_rules.transition_to_glacier_days
      expiration_days           = var.s3_lifecycle_rules.expiration_days
    }
    lambda_timeout_optimization = "${var.lambda_timeout} seconds"
    log_retention_optimization  = "${var.log_retention_days} days"
    test_resource_cleanup      = "Automated cleanup after testing"
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Confirm email subscription to SNS topic: ${aws_sns_topic.bc_alerts.arn}",
    "2. Configure test resource parameters in variables if not done during deployment",
    "3. Review CloudWatch dashboard: https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=BC-Testing-${local.project_id}",
    "4. Test manual execution using the provided Lambda invoke commands",
    "5. Verify scheduled tests are running according to configured schedules",
    "6. Review S3 bucket for test results and compliance reports: ${aws_s3_bucket.test_results.bucket}",
    "7. Customize automation documents based on your specific infrastructure requirements"
  ]
}