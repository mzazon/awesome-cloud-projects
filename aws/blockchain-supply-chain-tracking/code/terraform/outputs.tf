# Blockchain Network Outputs
output "blockchain_network_id" {
  description = "ID of the Amazon Managed Blockchain network"
  value       = aws_managedblockchain_network.supply_chain.id
}

output "blockchain_network_name" {
  description = "Name of the blockchain network"
  value       = aws_managedblockchain_network.supply_chain.name
}

output "blockchain_member_id" {
  description = "ID of the blockchain network member"
  value       = data.aws_managedblockchain_member.manufacturer.id
}

output "blockchain_member_name" {
  description = "Name of the blockchain network member"
  value       = data.aws_managedblockchain_member.manufacturer.name
}

output "blockchain_node_id" {
  description = "ID of the blockchain node"
  value       = aws_managedblockchain_node.manufacturer_node.id
}

output "blockchain_node_status" {
  description = "Status of the blockchain node"
  value       = aws_managedblockchain_node.manufacturer_node.status
}

output "blockchain_network_framework_attributes" {
  description = "Framework attributes of the blockchain network"
  value       = aws_managedblockchain_network.supply_chain.framework_attributes
  sensitive   = true
}

# Storage Outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for chaincode and data storage"
  value       = aws_s3_bucket.supply_chain_data.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.supply_chain_data.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.supply_chain_data.bucket_domain_name
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for supply chain metadata"
  value       = aws_dynamodb_table.supply_chain_metadata.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.supply_chain_metadata.arn
}

output "dynamodb_table_stream_arn" {
  description = "ARN of the DynamoDB table stream"
  value       = aws_dynamodb_table.supply_chain_metadata.stream_arn
}

# Lambda Function Outputs
output "lambda_function_name" {
  description = "Name of the Lambda function for processing sensor data"
  value       = aws_lambda_function.process_supply_chain_data.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.process_supply_chain_data.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.process_supply_chain_data.invoke_arn
}

output "lambda_function_version" {
  description = "Version of the Lambda function"
  value       = aws_lambda_function.process_supply_chain_data.version
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# IoT Core Outputs
output "iot_thing_name" {
  description = "Name of the IoT thing for supply chain tracking"
  value       = aws_iot_thing.supply_chain_tracker.name
}

output "iot_thing_arn" {
  description = "ARN of the IoT thing"
  value       = aws_iot_thing.supply_chain_tracker.arn
}

output "iot_thing_type_name" {
  description = "Name of the IoT thing type"
  value       = aws_iot_thing_type.supply_chain_tracker.name
}

output "iot_thing_type_arn" {
  description = "ARN of the IoT thing type"
  value       = aws_iot_thing_type.supply_chain_tracker.arn
}

output "iot_policy_name" {
  description = "Name of the IoT policy"
  value       = aws_iot_policy.supply_chain_tracker.name
}

output "iot_policy_arn" {
  description = "ARN of the IoT policy"
  value       = aws_iot_policy.supply_chain_tracker.arn
}

output "iot_topic_rule_name" {
  description = "Name of the IoT topic rule"
  value       = aws_iot_topic_rule.supply_chain_sensor_rule.name
}

output "iot_topic_rule_arn" {
  description = "ARN of the IoT topic rule"
  value       = aws_iot_topic_rule.supply_chain_sensor_rule.arn
}

output "iot_endpoint" {
  description = "IoT Core endpoint for device connections"
  value       = "https://iot.${var.aws_region}.amazonaws.com"
}

# EventBridge and SNS Outputs
output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.supply_chain_tracking.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.supply_chain_tracking.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic for notifications"
  value       = aws_sns_topic.supply_chain_notifications.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic"
  value       = aws_sns_topic.supply_chain_notifications.arn
}

output "sns_topic_subscriptions" {
  description = "List of SNS topic subscription ARNs"
  value       = aws_sns_topic_subscription.email_notifications[*].arn
}

# CloudWatch Outputs
output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.supply_chain_tracking.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.supply_chain_tracking.dashboard_name}"
}

output "lambda_error_alarm_name" {
  description = "Name of the Lambda error alarm (if enabled)"
  value       = var.enable_alarms ? aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name : null
}

output "dynamodb_throttle_alarm_name" {
  description = "Name of the DynamoDB throttle alarm (if enabled)"
  value       = var.enable_alarms ? aws_cloudwatch_metric_alarm.dynamodb_throttles[0].alarm_name : null
}

# Security Outputs
output "kms_key_id" {
  description = "ID of the KMS key (if encryption is enabled)"
  value       = var.enable_encryption ? aws_kms_key.supply_chain[0].key_id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key (if encryption is enabled)"
  value       = var.enable_encryption ? aws_kms_key.supply_chain[0].arn : null
}

output "kms_alias_name" {
  description = "Name of the KMS key alias (if encryption is enabled)"
  value       = var.enable_encryption ? aws_kms_alias.supply_chain[0].name : null
}

# Network and Connectivity Outputs
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

# Configuration Outputs
output "project_name" {
  description = "Name of the project"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "name_prefix" {
  description = "Common name prefix used for resources"
  value       = local.name_prefix
}

output "name_suffix" {
  description = "Random suffix used for unique naming"
  value       = local.name_suffix
}

# Testing and Validation Outputs
output "test_iot_topic" {
  description = "IoT topic for publishing test sensor data"
  value       = "supply-chain/sensor-data"
}

output "sample_sensor_data" {
  description = "Sample JSON payload for testing sensor data"
  value = jsonencode({
    productId   = "TEST-PROD-001"
    location    = "Factory"
    temperature = 22.5
    humidity    = 48.2
    timestamp   = 1672531200
  })
}

# Deployment Instructions
output "deployment_instructions" {
  description = "Next steps for completing the deployment"
  value = <<EOF
Deployment Complete! Next steps:

1. Verify blockchain network status:
   aws managedblockchain get-network --network-id ${aws_managedblockchain_network.supply_chain.id}

2. Test IoT sensor data publishing:
   aws iot-data publish --topic "supply-chain/sensor-data" --payload '${jsonencode({
     productId   = "TEST-PROD-001"
     location    = "Factory"
     temperature = 22.5
     humidity    = 48.2
     timestamp   = 1672531200
   })}'

3. Check CloudWatch dashboard:
   ${aws_cloudwatch_dashboard.supply_chain_tracking.dashboard_name}

4. Monitor DynamoDB table:
   aws dynamodb scan --table-name ${aws_dynamodb_table.supply_chain_metadata.name} --limit 5

5. Subscribe to SNS notifications (if emails were provided):
   Check your email for subscription confirmations

6. View CloudWatch logs:
   aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/${aws_lambda_function.process_supply_chain_data.function_name}"

For blockchain operations, you'll need to set up chaincode deployment and client applications separately.
EOF
}

# Cost Estimation
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed resources"
  value = <<EOF
Estimated Monthly Costs (US East 1):

Blockchain Network (STARTER): ~$30/month base + $0.0025 per request
DynamoDB (5 RCU/WCU): ~$3.50/month + usage
Lambda: ~$0.20 per 1M requests + compute time
S3 Storage: ~$0.023 per GB/month
CloudWatch: ~$0.30 per alarm + dashboard usage
IoT Core: ~$1.20 per 1M messages
SNS: ~$0.50 per 1M notifications
KMS: ~$1.00/month per key + usage

Total estimated base cost: ~$36-40/month (excluding actual usage)

Note: Costs will vary based on actual usage patterns, data transfer, and additional features.
EOF
}