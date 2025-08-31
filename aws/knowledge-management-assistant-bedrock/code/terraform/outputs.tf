# =============================================================================
# Outputs for Knowledge Management Assistant with Bedrock Agents
# =============================================================================
# This file defines outputs that provide important information after deployment.
# These outputs help with testing, integration, and ongoing management.
# =============================================================================

# =============================================================================
# General Deployment Information
# =============================================================================

output "deployment_region" {
  description = "AWS region where resources were deployed"
  value       = data.aws_region.current.name
}

output "account_id" {
  description = "AWS account ID where resources were deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "project_name" {
  description = "Project name used for resource naming and tagging"
  value       = var.project_name
}

output "environment" {
  description = "Environment where resources were deployed"
  value       = var.environment
}

# =============================================================================
# S3 Bucket Information
# =============================================================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket storing enterprise documents"
  value       = aws_s3_bucket.knowledge_docs.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket storing enterprise documents"
  value       = aws_s3_bucket.knowledge_docs.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.knowledge_docs.bucket_domain_name
}

output "s3_bucket_website_endpoint" {
  description = "Website endpoint of the S3 bucket"
  value       = aws_s3_bucket.knowledge_docs.website_endpoint
}

output "sample_documents_uploaded" {
  description = "List of sample documents uploaded to S3"
  value = [
    aws_s3_object.company_policies.key,
    aws_s3_object.technical_guide.key
  ]
}

# =============================================================================
# IAM Role Information
# =============================================================================

output "bedrock_agent_role_arn" {
  description = "ARN of the IAM role for Bedrock Agent"
  value       = aws_iam_role.bedrock_agent_role.arn
}

output "bedrock_agent_role_name" {
  description = "Name of the IAM role for Bedrock Agent"
  value       = aws_iam_role.bedrock_agent_role.name
}

output "lambda_role_arn" {
  description = "ARN of the IAM role for Lambda function"
  value       = aws_iam_role.lambda_bedrock_role.arn
}

output "lambda_role_name" {
  description = "Name of the IAM role for Lambda function"
  value       = aws_iam_role.lambda_bedrock_role.name
}

# =============================================================================
# OpenSearch Serverless Information
# =============================================================================

output "opensearch_collection_arn" {
  description = "ARN of the OpenSearch Serverless collection"
  value       = aws_opensearchserverless_collection.knowledge_base.arn
}

output "opensearch_collection_id" {
  description = "ID of the OpenSearch Serverless collection"
  value       = aws_opensearchserverless_collection.knowledge_base.id
}

output "opensearch_collection_name" {
  description = "Name of the OpenSearch Serverless collection"
  value       = aws_opensearchserverless_collection.knowledge_base.name
}

output "opensearch_collection_endpoint" {
  description = "Endpoint of the OpenSearch Serverless collection"
  value       = aws_opensearchserverless_collection.knowledge_base.collection_endpoint
}

output "opensearch_dashboard_endpoint" {
  description = "Dashboard endpoint of the OpenSearch Serverless collection"
  value       = aws_opensearchserverless_collection.knowledge_base.dashboard_endpoint
}

# =============================================================================
# Bedrock Knowledge Base Information
# =============================================================================

output "knowledge_base_id" {
  description = "ID of the Bedrock Knowledge Base"
  value       = aws_bedrockagent_knowledge_base.enterprise_kb.id
}

output "knowledge_base_arn" {
  description = "ARN of the Bedrock Knowledge Base"
  value       = aws_bedrockagent_knowledge_base.enterprise_kb.arn
}

output "knowledge_base_name" {
  description = "Name of the Bedrock Knowledge Base"
  value       = aws_bedrockagent_knowledge_base.enterprise_kb.name
}

output "knowledge_base_status" {
  description = "Status of the Bedrock Knowledge Base"
  value       = aws_bedrockagent_knowledge_base.enterprise_kb.status
}

output "data_source_id" {
  description = "ID of the Knowledge Base data source"
  value       = aws_bedrockagent_data_source.s3_documents.id
}

output "data_source_name" {
  description = "Name of the Knowledge Base data source"
  value       = aws_bedrockagent_data_source.s3_documents.name
}

output "data_source_status" {
  description = "Status of the Knowledge Base data source"
  value       = aws_bedrockagent_data_source.s3_documents.status
}

# =============================================================================
# Bedrock Agent Information
# =============================================================================

output "bedrock_agent_id" {
  description = "ID of the Bedrock Agent"
  value       = aws_bedrockagent_agent.knowledge_assistant.id
}

output "bedrock_agent_arn" {
  description = "ARN of the Bedrock Agent"
  value       = aws_bedrockagent_agent.knowledge_assistant.arn
}

output "bedrock_agent_name" {
  description = "Name of the Bedrock Agent"
  value       = aws_bedrockagent_agent.knowledge_assistant.agent_name
}

output "bedrock_agent_status" {
  description = "Status of the Bedrock Agent"
  value       = aws_bedrockagent_agent.knowledge_assistant.agent_status
}

output "bedrock_agent_version" {
  description = "Version of the Bedrock Agent"
  value       = aws_bedrockagent_agent.knowledge_assistant.agent_version
}

output "bedrock_agent_alias_id" {
  description = "ID of the Bedrock Agent alias"
  value       = aws_bedrockagent_agent_alias.knowledge_assistant_alias.agent_alias_id
}

output "bedrock_agent_alias_arn" {
  description = "ARN of the Bedrock Agent alias"
  value       = aws_bedrockagent_agent_alias.knowledge_assistant_alias.agent_alias_arn
}

output "foundation_model" {
  description = "Foundation model used by the Bedrock Agent"
  value       = var.foundation_model
}

# =============================================================================
# Lambda Function Information
# =============================================================================

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.bedrock_agent_proxy.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.bedrock_agent_proxy.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.bedrock_agent_proxy.invoke_arn
}

output "lambda_function_version" {
  description = "Version of the Lambda function"
  value       = aws_lambda_function.bedrock_agent_proxy.version
}

output "lambda_function_runtime" {
  description = "Runtime of the Lambda function"
  value       = aws_lambda_function.bedrock_agent_proxy.runtime
}

output "lambda_log_group_name" {
  description = "Name of the Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

# =============================================================================
# API Gateway Information
# =============================================================================

output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.knowledge_management_api.id
}

output "api_gateway_arn" {
  description = "ARN of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.knowledge_management_api.arn
}

output "api_gateway_name" {
  description = "Name of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.knowledge_management_api.name
}

output "api_gateway_root_resource_id" {
  description = "Root resource ID of the API Gateway"
  value       = aws_api_gateway_rest_api.knowledge_management_api.root_resource_id
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway"
  value       = aws_api_gateway_rest_api.knowledge_management_api.execution_arn
}

output "api_gateway_deployment_id" {
  description = "Deployment ID of the API Gateway"
  value       = aws_api_gateway_deployment.prod.id
}

output "api_gateway_stage_name" {
  description = "Stage name of the API Gateway deployment"
  value       = aws_api_gateway_stage.prod.stage_name
}

output "api_gateway_stage_arn" {
  description = "ARN of the API Gateway stage"
  value       = aws_api_gateway_stage.prod.arn
}

output "api_gateway_invoke_url" {
  description = "Invoke URL of the API Gateway"
  value       = aws_api_gateway_stage.prod.invoke_url
}

# =============================================================================
# API Endpoints
# =============================================================================

output "api_endpoint_base_url" {
  description = "Base URL of the Knowledge Management API"
  value       = "https://${aws_api_gateway_rest_api.knowledge_management_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/prod"
}

output "api_endpoint_query_url" {
  description = "Full URL for the query endpoint"
  value       = "https://${aws_api_gateway_rest_api.knowledge_management_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/prod/query"
}

output "api_gateway_log_group_name" {
  description = "Name of the API Gateway CloudWatch log group"
  value       = aws_cloudwatch_log_group.api_gateway_logs.name
}

output "api_gateway_log_group_arn" {
  description = "ARN of the API Gateway CloudWatch log group"
  value       = aws_cloudwatch_log_group.api_gateway_logs.arn
}

# =============================================================================
# Monitoring Information
# =============================================================================

output "lambda_error_alarm_name" {
  description = "Name of the Lambda error CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
}

output "lambda_error_alarm_arn" {
  description = "ARN of the Lambda error CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.arn
}

output "api_4xx_error_alarm_name" {
  description = "Name of the API Gateway 4XX error CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.api_4xx_errors.alarm_name
}

output "api_4xx_error_alarm_arn" {
  description = "ARN of the API Gateway 4XX error CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.api_4xx_errors.arn
}

# =============================================================================
# Testing and Validation Information
# =============================================================================

output "test_query_command" {
  description = "Example curl command to test the API"
  value = <<EOF
curl -X POST ${aws_api_gateway_stage.prod.invoke_url}/query \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What is our company remote work policy?",
    "sessionId": "test-session-1"
  }'
EOF
}

output "aws_cli_bedrock_test_command" {
  description = "AWS CLI command to test Bedrock Agent directly"
  value = <<EOF
aws bedrock-agent-runtime invoke-agent \
  --agent-id ${aws_bedrockagent_agent.knowledge_assistant.id} \
  --agent-alias-id ${aws_bedrockagent_agent_alias.knowledge_assistant_alias.agent_alias_id} \
  --session-id test-session \
  --input-text "What are the meal expense limits for business travel?" \
  --region ${data.aws_region.current.name} \
  response.json
EOF
}

output "knowledge_base_sync_command" {
  description = "AWS CLI command to start knowledge base ingestion"
  value = <<EOF
aws bedrock-agent start-ingestion-job \
  --knowledge-base-id ${aws_bedrockagent_knowledge_base.enterprise_kb.id} \
  --data-source-id ${aws_bedrockagent_data_source.s3_documents.id} \
  --region ${data.aws_region.current.name}
EOF
}

# =============================================================================
# Cost and Resource Summary
# =============================================================================

output "estimated_monthly_cost_breakdown" {
  description = "Estimated monthly cost breakdown for deployed resources"
  value = {
    s3_storage          = "~$0.02 per GB stored"
    opensearch_serverless = "~$0.24 per OCU-hour"
    lambda_invocations  = "~$0.20 per 1M requests + compute time"
    api_gateway         = "~$3.50 per 1M requests"
    bedrock_agent       = "Pay per request (varies by model)"
    cloudwatch_logs     = "~$0.50 per GB ingested"
    note               = "Costs vary by usage and region. See AWS pricing for exact rates."
  }
}

output "deployed_resources_summary" {
  description = "Summary of all deployed AWS resources"
  value = {
    s3_bucket                    = aws_s3_bucket.knowledge_docs.id
    opensearch_collection        = aws_opensearchserverless_collection.knowledge_base.name
    bedrock_knowledge_base       = aws_bedrockagent_knowledge_base.enterprise_kb.id
    bedrock_agent               = aws_bedrockagent_agent.knowledge_assistant.id
    lambda_function             = aws_lambda_function.bedrock_agent_proxy.function_name
    api_gateway                 = aws_api_gateway_rest_api.knowledge_management_api.name
    iam_roles_created           = 2
    cloudwatch_alarms           = 2
    total_resources_approximate = "15+ AWS resources"
  }
}

# =============================================================================
# Next Steps and Documentation
# =============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = <<EOF
1. Wait for Knowledge Base ingestion to complete (check status with AWS CLI)
2. Test the API endpoint using the provided curl command
3. Upload additional enterprise documents to the S3 bucket
4. Monitor CloudWatch alarms and logs for performance insights
5. Customize the agent instructions based on your use case
6. Set up additional security measures if needed for production use
EOF
}

output "useful_aws_console_links" {
  description = "Useful AWS Console links for managing the deployment"
  value = {
    s3_bucket           = "https://console.aws.amazon.com/s3/buckets/${aws_s3_bucket.knowledge_docs.id}"
    bedrock_agents      = "https://console.aws.amazon.com/bedrock/home?region=${data.aws_region.current.name}#/agents"
    lambda_function     = "https://console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions/${aws_lambda_function.bedrock_agent_proxy.function_name}"
    api_gateway         = "https://console.aws.amazon.com/apigateway/home?region=${data.aws_region.current.name}#/apis/${aws_api_gateway_rest_api.knowledge_management_api.id}"
    cloudwatch_logs     = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#logsV2:log-groups"
    opensearch_serverless = "https://console.aws.amazon.com/aos/home?region=${data.aws_region.current.name}#opensearch/collections"
  }
}