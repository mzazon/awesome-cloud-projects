# QLDB Ledger outputs
output "qldb_ledger_name" {
  description = "Name of the QLDB ledger"
  value       = aws_qldb_ledger.compliance_ledger.name
}

output "qldb_ledger_arn" {
  description = "ARN of the QLDB ledger"
  value       = aws_qldb_ledger.compliance_ledger.arn
}

output "qldb_ledger_id" {
  description = "ID of the QLDB ledger"
  value       = aws_qldb_ledger.compliance_ledger.id
}

# CloudTrail outputs
output "cloudtrail_name" {
  description = "Name of the CloudTrail"
  value       = aws_cloudtrail.compliance_trail.name
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail"
  value       = aws_cloudtrail.compliance_trail.arn
}

output "cloudtrail_home_region" {
  description = "Home region of the CloudTrail"
  value       = aws_cloudtrail.compliance_trail.home_region
}

# S3 Bucket outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for audit storage"
  value       = aws_s3_bucket.audit_bucket.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for audit storage"
  value       = aws_s3_bucket.audit_bucket.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.audit_bucket.bucket_domain_name
}

output "s3_bucket_hosted_zone_id" {
  description = "Hosted zone ID of the S3 bucket"
  value       = aws_s3_bucket.audit_bucket.hosted_zone_id
}

# Lambda Function outputs
output "lambda_function_name" {
  description = "Name of the Lambda audit processor function"
  value       = aws_lambda_function.audit_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda audit processor function"
  value       = aws_lambda_function.audit_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.audit_processor.invoke_arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# EventBridge outputs
output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.compliance_audit_rule.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.compliance_audit_rule.arn
}

# SNS Topic outputs
output "sns_topic_name" {
  description = "Name of the SNS topic for compliance alerts"
  value       = aws_sns_topic.compliance_alerts.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for compliance alerts"
  value       = aws_sns_topic.compliance_alerts.arn
}

# Kinesis Data Firehose outputs
output "firehose_delivery_stream_name" {
  description = "Name of the Kinesis Data Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.compliance_stream.name
}

output "firehose_delivery_stream_arn" {
  description = "ARN of the Kinesis Data Firehose delivery stream"
  value       = aws_kinesis_firehose_delivery_stream.compliance_stream.arn
}

# Athena outputs
output "athena_workgroup_name" {
  description = "Name of the Athena workgroup for compliance queries"
  value       = aws_athena_workgroup.compliance_workgroup.name
}

output "athena_workgroup_arn" {
  description = "ARN of the Athena workgroup"
  value       = aws_athena_workgroup.compliance_workgroup.arn
}

output "athena_database_name" {
  description = "Name of the Athena database"
  value       = aws_athena_database.compliance_database.name
}

# CloudWatch outputs
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.compliance_dashboard.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.compliance_dashboard.dashboard_name}"
}

output "cloudwatch_alarm_name" {
  description = "Name of the CloudWatch alarm for audit errors"
  value       = aws_cloudwatch_metric_alarm.audit_errors.alarm_name
}

# KMS Key outputs
output "kms_key_id" {
  description = "ID of the KMS key for QLDB encryption"
  value       = aws_kms_key.qldb_key.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key for QLDB encryption"
  value       = aws_kms_key.qldb_key.arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key"
  value       = aws_kms_alias.qldb_key_alias.name
}

# Deployment information
output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "deployment_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_prefix" {
  description = "Common resource prefix used for naming"
  value       = local.name_prefix
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_string.suffix.result
}

# Usage instructions
output "getting_started" {
  description = "Instructions for getting started with the compliance audit system"
  value = <<-EOT
    Compliance Audit System Deployed Successfully!
    
    Next Steps:
    1. Verify QLDB ledger status: aws qldb describe-ledger --name ${aws_qldb_ledger.compliance_ledger.name}
    2. Check CloudTrail logging: aws cloudtrail get-trail-status --name ${aws_cloudtrail.compliance_trail.name}
    3. View CloudWatch dashboard: ${local.dashboard_name}
    4. Test Lambda function with sample events
    5. Query audit data using Athena workgroup: ${aws_athena_workgroup.compliance_workgroup.name}
    
    Important Resources:
    - QLDB Ledger: ${aws_qldb_ledger.compliance_ledger.name}
    - S3 Bucket: ${aws_s3_bucket.audit_bucket.id}
    - Lambda Function: ${aws_lambda_function.audit_processor.function_name}
    - CloudWatch Dashboard: ${local.dashboard_name}
    
    Monitoring:
    - SNS notifications will be sent to: ${var.notification_email}
    - CloudWatch logs: /aws/lambda/${aws_lambda_function.audit_processor.function_name}
    - Metrics namespace: ComplianceAudit
  EOT
}

# Compliance verification commands
output "verification_commands" {
  description = "Commands to verify the compliance audit system"
  value = {
    check_qldb_status = "aws qldb describe-ledger --name ${aws_qldb_ledger.compliance_ledger.name}"
    get_qldb_digest   = "aws qldb get-digest --name ${aws_qldb_ledger.compliance_ledger.name}"
    check_cloudtrail  = "aws cloudtrail get-trail-status --name ${aws_cloudtrail.compliance_trail.name}"
    test_lambda       = "aws lambda invoke --function-name ${aws_lambda_function.audit_processor.function_name} --payload '{\"detail\":{\"eventName\":\"TestEvent\",\"eventSource\":\"test.service\"}}' /tmp/response.json"
    view_logs         = "aws logs describe-log-groups --log-group-name-prefix '/aws/lambda/${aws_lambda_function.audit_processor.function_name}'"
    athena_query      = "aws athena start-query-execution --work-group ${aws_athena_workgroup.compliance_workgroup.name} --query-string 'SELECT COUNT(*) FROM ${aws_athena_database.compliance_database.name}.audit_records LIMIT 10;' --result-configuration OutputLocation=s3://${aws_s3_bucket.audit_bucket.id}/athena-results/"
  }
}