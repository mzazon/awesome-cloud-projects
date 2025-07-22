# Outputs for decentralized identity management blockchain infrastructure

# Network and Blockchain Outputs
output "blockchain_network_id" {
  description = "ID of the Managed Blockchain network"
  value       = aws_managedblockchain_network.identity_network.id
}

output "blockchain_network_name" {
  description = "Name of the Managed Blockchain network"
  value       = aws_managedblockchain_network.identity_network.name
}

output "blockchain_network_arn" {
  description = "ARN of the Managed Blockchain network"
  value       = aws_managedblockchain_network.identity_network.arn
}

output "blockchain_member_id" {
  description = "ID of the blockchain network member"
  value       = data.aws_managedblockchain_network.identity_network.member_blocks[0].id
}

output "blockchain_member_name" {
  description = "Name of the blockchain network member"
  value       = local.member_name
}

output "blockchain_peer_node_id" {
  description = "ID of the blockchain peer node"
  value       = aws_managedblockchain_node.identity_peer.id
}

output "blockchain_peer_endpoint" {
  description = "Endpoint of the blockchain peer node"
  value       = aws_managedblockchain_node.identity_peer.node_configuration[0].availability_zone
}

# QLDB Outputs
output "qldb_ledger_name" {
  description = "Name of the QLDB ledger"
  value       = aws_qldb_ledger.identity_ledger.name
}

output "qldb_ledger_arn" {
  description = "ARN of the QLDB ledger"
  value       = aws_qldb_ledger.identity_ledger.arn
}

output "qldb_ledger_id" {
  description = "ID of the QLDB ledger"
  value       = aws_qldb_ledger.identity_ledger.id
}

output "qldb_kms_key_id" {
  description = "KMS key ID used for QLDB encryption"
  value       = aws_kms_key.qldb_key.key_id
}

output "qldb_kms_key_arn" {
  description = "KMS key ARN used for QLDB encryption"
  value       = aws_kms_key.qldb_key.arn
}

# DynamoDB Outputs
output "dynamodb_table_name" {
  description = "Name of the DynamoDB credentials table"
  value       = aws_dynamodb_table.identity_credentials.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB credentials table"
  value       = aws_dynamodb_table.identity_credentials.arn
}

output "dynamodb_table_id" {
  description = "ID of the DynamoDB credentials table"
  value       = aws_dynamodb_table.identity_credentials.id
}

output "dynamodb_global_secondary_indexes" {
  description = "Global secondary indexes of the DynamoDB table"
  value       = aws_dynamodb_table.identity_credentials.global_secondary_index
}

# Lambda Function Outputs
output "lambda_function_name" {
  description = "Name of the identity management Lambda function"
  value       = aws_lambda_function.identity_management.function_name
}

output "lambda_function_arn" {
  description = "ARN of the identity management Lambda function"
  value       = aws_lambda_function.identity_management.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the identity management Lambda function"
  value       = aws_lambda_function.identity_management.invoke_arn
}

output "lambda_function_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_function_version" {
  description = "Version of the Lambda function"
  value       = aws_lambda_function.identity_management.version
}

# API Gateway Outputs
output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.identity_api.id
}

output "api_gateway_arn" {
  description = "ARN of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.identity_api.arn
}

output "api_gateway_url" {
  description = "URL of the API Gateway"
  value       = "https://${aws_api_gateway_rest_api.identity_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}"
}

output "api_gateway_invoke_url" {
  description = "Invoke URL for the identity endpoint"
  value       = "https://${aws_api_gateway_rest_api.identity_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}/identity"
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway"
  value       = aws_api_gateway_rest_api.identity_api.execution_arn
}

# S3 Bucket Outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for blockchain assets"
  value       = aws_s3_bucket.blockchain_assets.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.blockchain_assets.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.blockchain_assets.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.blockchain_assets.bucket_regional_domain_name
}

# Cognito Outputs
output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.identity_users.id
}

output "cognito_user_pool_arn" {
  description = "ARN of the Cognito User Pool"
  value       = aws_cognito_user_pool.identity_users.arn
}

output "cognito_user_pool_client_id" {
  description = "ID of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.identity_client.id
}

output "cognito_user_pool_domain" {
  description = "Domain name of the Cognito User Pool"
  value       = aws_cognito_user_pool.identity_users.domain
}

# CloudWatch Outputs
output "lambda_log_group_name" {
  description = "Name of the Lambda function CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the Lambda function CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "api_gateway_log_group_name" {
  description = "Name of the API Gateway CloudWatch log group"
  value       = var.enable_detailed_monitoring ? aws_cloudwatch_log_group.api_gateway_logs[0].name : null
}

# Monitoring Outputs
output "lambda_error_alarm_name" {
  description = "Name of the Lambda error CloudWatch alarm"
  value       = var.enable_detailed_monitoring ? aws_cloudwatch_metric_alarm.lambda_errors[0].alarm_name : null
}

output "dynamodb_throttle_alarm_name" {
  description = "Name of the DynamoDB throttle CloudWatch alarm"
  value       = var.enable_detailed_monitoring ? aws_cloudwatch_metric_alarm.dynamodb_throttle[0].alarm_name : null
}

# Security and IAM Outputs
output "lambda_execution_role_name" {
  description = "Name of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_policy_arn" {
  description = "ARN of the Lambda custom IAM policy"
  value       = aws_iam_policy.lambda_policy.arn
}

# System Configuration Outputs
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.suffix
}

# Integration Endpoints
output "identity_creation_endpoint" {
  description = "Complete endpoint URL for identity creation"
  value       = "POST https://${aws_api_gateway_rest_api.identity_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}/identity"
}

output "curl_example_create_identity" {
  description = "Example curl command to create an identity"
  value = <<-EOF
curl -X POST \
  https://${aws_api_gateway_rest_api.identity_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}/identity \
  -H "Content-Type: application/json" \
  -d '{
    "action": "createIdentity",
    "publicKey": "YOUR_PUBLIC_KEY_HERE",
    "metadata": {
      "name": "Example User",
      "email": "user@example.com"
    }
  }'
EOF
}

output "curl_example_issue_credential" {
  description = "Example curl command to issue a credential"
  value = <<-EOF
curl -X POST \
  https://${aws_api_gateway_rest_api.identity_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}/identity \
  -H "Content-Type: application/json" \
  -d '{
    "action": "issueCredential",
    "did": "did:fabric:YOUR_DID_HERE",
    "credentialType": "UniversityDegree",
    "claims": {
      "degree": "Bachelor of Science",
      "university": "Example University",
      "graduationYear": 2023
    }
  }'
EOF
}

output "curl_example_verify_credential" {
  description = "Example curl command to verify a credential"
  value = <<-EOF
curl -X POST \
  https://${aws_api_gateway_rest_api.identity_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}/identity \
  -H "Content-Type: application/json" \
  -d '{
    "action": "verifyCredential",
    "credentialId": "YOUR_CREDENTIAL_ID_HERE"
  }'
EOF
}

# Deployment Information
output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    blockchain_network    = aws_managedblockchain_network.identity_network.name
    qldb_ledger          = aws_qldb_ledger.identity_ledger.name
    dynamodb_table       = aws_dynamodb_table.identity_credentials.name
    lambda_function      = aws_lambda_function.identity_management.function_name
    api_gateway          = aws_api_gateway_rest_api.identity_api.name
    s3_bucket           = aws_s3_bucket.blockchain_assets.bucket
    cognito_user_pool   = aws_cognito_user_pool.identity_users.name
    region              = data.aws_region.current.name
    environment         = var.environment
  }
}

# Cost Information
output "estimated_monthly_costs" {
  description = "Estimated monthly costs for resources (USD)"
  value = {
    blockchain_network = "~$30-50 (peer node bc.t3.small)"
    qldb_ledger       = "~$1-5 (based on usage)"
    dynamodb_table    = "~$2-10 (provisioned capacity)"
    lambda_function   = "~$0-5 (based on invocations)"
    api_gateway       = "~$0-10 (based on requests)"
    s3_bucket         = "~$0-5 (based on storage)"
    cloudwatch_logs   = "~$0-2 (based on log volume)"
    kms_key           = "~$1 (monthly key cost)"
    total_estimated   = "~$34-87 per month"
  }
}

# Next Steps
output "next_steps" {
  description = "Next steps for using the deployed infrastructure"
  value = [
    "1. Test the API endpoints using the provided curl examples",
    "2. Generate cryptographic key pairs for identity creation",
    "3. Configure client applications to use the API Gateway endpoint",
    "4. Set up monitoring and alerting for the blockchain network",
    "5. Implement additional security measures as needed",
    "6. Review and adjust DynamoDB and Lambda scaling settings",
    "7. Configure backup and disaster recovery procedures"
  ]
}

# Security Considerations
output "security_recommendations" {
  description = "Important security recommendations"
  value = [
    "1. Enable API Gateway authentication (Cognito or custom authorizers)",
    "2. Implement rate limiting and throttling on API endpoints",
    "3. Enable VPC endpoints for enhanced network security",
    "4. Regularly rotate KMS keys and monitor key usage",
    "5. Implement proper key management for blockchain operations",
    "6. Enable AWS CloudTrail for audit logging",
    "7. Use least privilege principles for all IAM roles",
    "8. Enable AWS Config for compliance monitoring",
    "9. Implement proper backup and recovery procedures",
    "10. Monitor all resources using CloudWatch and set up alerts"
  ]
}