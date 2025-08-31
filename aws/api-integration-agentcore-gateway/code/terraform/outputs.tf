# =============================================================================
# Outputs for Enterprise API Integration with AgentCore Gateway
# =============================================================================
# This file defines all output values from the Terraform configuration,
# providing essential information for integration, monitoring, and management
# of the enterprise API integration system.
# =============================================================================

# Core Infrastructure Outputs
# =============================================================================

output "project_name" {
  description = "Name of the deployed project"
  value       = var.project_name
}

output "environment" {
  description = "Environment where resources are deployed"
  value       = var.environment
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.name_suffix
  sensitive   = false
}

# API Gateway Outputs
# =============================================================================

output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.enterprise_integration.id
}

output "api_gateway_name" {
  description = "Name of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.enterprise_integration.name
}

output "api_gateway_arn" {
  description = "ARN of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.enterprise_integration.arn
}

output "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.enterprise_integration.execution_arn
}

output "api_gateway_url" {
  description = "Base URL of the deployed API Gateway"
  value       = "https://${aws_api_gateway_rest_api.enterprise_integration.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}"
}

output "api_gateway_integration_endpoint" {
  description = "Full URL of the integration endpoint"
  value       = "https://${aws_api_gateway_rest_api.enterprise_integration.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_stage_name}/integrate"
}

output "api_gateway_stage_arn" {
  description = "ARN of the API Gateway stage"
  value       = aws_api_gateway_stage.production.arn
}

output "api_gateway_stage_invoke_url" {
  description = "Invoke URL of the API Gateway stage"
  value       = aws_api_gateway_stage.production.invoke_url
}

# Lambda Function Outputs
# =============================================================================

output "api_transformer_function_name" {
  description = "Name of the API transformer Lambda function"
  value       = aws_lambda_function.api_transformer.function_name
}

output "api_transformer_function_arn" {
  description = "ARN of the API transformer Lambda function"
  value       = aws_lambda_function.api_transformer.arn
}

output "api_transformer_function_qualified_arn" {
  description = "Qualified ARN of the API transformer Lambda function"
  value       = aws_lambda_function.api_transformer.qualified_arn
}

output "api_transformer_function_invoke_arn" {
  description = "Invoke ARN of the API transformer Lambda function"
  value       = aws_lambda_function.api_transformer.invoke_arn
}

output "data_validator_function_name" {
  description = "Name of the data validator Lambda function"
  value       = aws_lambda_function.data_validator.function_name
}

output "data_validator_function_arn" {
  description = "ARN of the data validator Lambda function"
  value       = aws_lambda_function.data_validator.arn
}

output "data_validator_function_qualified_arn" {
  description = "Qualified ARN of the data validator Lambda function"
  value       = aws_lambda_function.data_validator.qualified_arn
}

output "data_validator_function_invoke_arn" {
  description = "Invoke ARN of the data validator Lambda function"
  value       = aws_lambda_function.data_validator.invoke_arn
}

# Step Functions Outputs
# =============================================================================

output "stepfunctions_state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.api_orchestrator.arn
}

output "stepfunctions_state_machine_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.api_orchestrator.name
}

output "stepfunctions_state_machine_status" {
  description = "Status of the Step Functions state machine"
  value       = aws_sfn_state_machine.api_orchestrator.status
}

output "stepfunctions_state_machine_creation_date" {
  description = "Creation date of the Step Functions state machine"
  value       = aws_sfn_state_machine.api_orchestrator.creation_date
}

# IAM Role Outputs
# =============================================================================

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

output "stepfunctions_execution_role_arn" {
  description = "ARN of the Step Functions execution role"
  value       = aws_iam_role.stepfunctions_execution_role.arn
}

output "stepfunctions_execution_role_name" {
  description = "Name of the Step Functions execution role"
  value       = aws_iam_role.stepfunctions_execution_role.name
}

output "apigateway_stepfunctions_role_arn" {
  description = "ARN of the API Gateway to Step Functions role"
  value       = aws_iam_role.apigateway_stepfunctions_role.arn
}

output "apigateway_stepfunctions_role_name" {
  description = "Name of the API Gateway to Step Functions role"
  value       = aws_iam_role.apigateway_stepfunctions_role.name
}

# CloudWatch Logs Outputs
# =============================================================================

output "api_transformer_log_group_name" {
  description = "Name of the API transformer CloudWatch log group"
  value       = aws_cloudwatch_log_group.api_transformer_logs.name
}

output "api_transformer_log_group_arn" {
  description = "ARN of the API transformer CloudWatch log group"
  value       = aws_cloudwatch_log_group.api_transformer_logs.arn
}

output "data_validator_log_group_name" {
  description = "Name of the data validator CloudWatch log group"
  value       = aws_cloudwatch_log_group.data_validator_logs.name
}

output "data_validator_log_group_arn" {
  description = "ARN of the data validator CloudWatch log group"
  value       = aws_cloudwatch_log_group.data_validator_logs.arn
}

output "stepfunctions_log_group_name" {
  description = "Name of the Step Functions CloudWatch log group"
  value       = aws_cloudwatch_log_group.stepfunctions_logs.name
}

output "stepfunctions_log_group_arn" {
  description = "ARN of the Step Functions CloudWatch log group"
  value       = aws_cloudwatch_log_group.stepfunctions_logs.arn
}

output "api_gateway_log_group_name" {
  description = "Name of the API Gateway CloudWatch log group"
  value       = aws_cloudwatch_log_group.api_gateway_logs.name
}

output "api_gateway_log_group_arn" {
  description = "ARN of the API Gateway CloudWatch log group"
  value       = aws_cloudwatch_log_group.api_gateway_logs.arn
}

# Generated Files Outputs
# =============================================================================

output "openapi_spec_file_path" {
  description = "Path to the generated OpenAPI specification file"
  value       = local_file.openapi_spec.filename
}

output "lambda_transformer_package_path" {
  description = "Path to the API transformer Lambda deployment package"
  value       = data.archive_file.api_transformer_zip.output_path
}

output "lambda_validator_package_path" {
  description = "Path to the data validator Lambda deployment package"
  value       = data.archive_file.data_validator_zip.output_path
}

# Integration and Testing Outputs
# =============================================================================

output "curl_test_command" {
  description = "Sample curl command to test the API endpoint"
  value = <<-EOF
curl -X POST ${aws_api_gateway_stage.production.invoke_url}/integrate \
  -H "Content-Type: application/json" \
  -d '{
    "id": "test-001",
    "type": "erp",
    "data": {
      "transaction_type": "purchase_order",
      "amount": 1500.00,
      "vendor": "Acme Corp"
    },
    "validation_type": "financial"
  }'
EOF
}

output "aws_cli_test_commands" {
  description = "AWS CLI commands for testing individual components"
  value = {
    test_api_transformer = "aws lambda invoke --function-name ${aws_lambda_function.api_transformer.function_name} --payload '{\"api_type\":\"erp\",\"payload\":{\"id\":\"test-123\",\"data\":{\"amount\":100.00}},\"target_url\":\"https://example.com\"}' response.json"
    test_data_validator = "aws lambda invoke --function-name ${aws_lambda_function.data_validator.function_name} --payload '{\"data\":{\"id\":\"test-123\",\"type\":\"financial\",\"amount\":250.50,\"email\":\"test@example.com\"},\"validation_type\":\"financial\"}' response.json"
    list_executions = "aws stepfunctions list-executions --state-machine-arn ${aws_sfn_state_machine.api_orchestrator.arn} --max-items 5"
    start_execution = "aws stepfunctions start-execution --state-machine-arn ${aws_sfn_state_machine.api_orchestrator.arn} --input '{\"id\":\"test-execution\",\"type\":\"erp\",\"data\":{\"amount\":100},\"validation_type\":\"financial\"}'"
  }
}

# Monitoring and Observability Outputs
# =============================================================================

output "cloudwatch_dashboard_url" {
  description = "URL to CloudWatch dashboard for monitoring (manual creation required)"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:"
}

output "xray_service_map_url" {
  description = "URL to X-Ray service map for distributed tracing"
  value       = var.enable_xray_tracing ? "https://${data.aws_region.current.name}.console.aws.amazon.com/xray/home?region=${data.aws_region.current.name}#/service-map" : "X-Ray tracing is disabled"
}

output "stepfunctions_console_url" {
  description = "URL to Step Functions console for the state machine"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/states/home?region=${data.aws_region.current.name}#/statemachines/view/${aws_sfn_state_machine.api_orchestrator.arn}"
}

output "api_gateway_console_url" {
  description = "URL to API Gateway console for the REST API"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/apigateway/home?region=${data.aws_region.current.name}#/apis/${aws_api_gateway_rest_api.enterprise_integration.id}/resources"
}

# AgentCore Gateway Configuration Outputs
# =============================================================================

output "agentcore_gateway_configuration" {
  description = "Configuration details for setting up Amazon Bedrock AgentCore Gateway"
  value = {
    gateway_name = "${var.project_name}-gateway-${local.name_suffix}"
    openapi_target = {
      name        = "enterprise-api-integration"
      spec_file   = local_file.openapi_spec.filename
      base_url    = aws_api_gateway_stage.production.invoke_url
      description = "Enterprise API integration endpoint for workflow orchestration"
    }
    lambda_targets = [
      {
        name          = "api-transformer"
        function_name = aws_lambda_function.api_transformer.function_name
        description   = "Transform API requests for enterprise system integration"
      },
      {
        name          = "data-validator"
        function_name = aws_lambda_function.data_validator.function_name
        description   = "Validate API request data according to enterprise rules"
      }
    ]
    setup_instructions = [
      "1. Navigate to AWS Bedrock AgentCore Gateway console",
      "2. Create a new Gateway named: ${var.project_name}-gateway-${local.name_suffix}",
      "3. Add OpenAPI target using the generated specification file",
      "4. Add Lambda targets for transformer and validator functions",
      "5. Configure OAuth authorizer for agent authentication",
      "6. Test gateway connectivity with enterprise systems"
    ]
  }
}

# Enterprise System Configuration Outputs
# =============================================================================

output "enterprise_systems_configuration" {
  description = "Configuration for enterprise systems integration"
  value = {
    supported_systems = var.enterprise_systems
    validation_rules  = var.validation_rules
    integration_patterns = {
      erp = {
        description = "Enterprise Resource Planning system integration"
        data_format = "JSON with transaction_type, data, and metadata fields"
        timeout     = "${var.lambda_timeout}s"
      }
      crm = {
        description = "Customer Relationship Management system integration"
        data_format = "JSON with operation, entity, attributes, and source_system fields"
        timeout     = "${var.lambda_timeout}s"
      }
      inventory = {
        description = "Inventory Management system integration"
        data_format = "JSON with item_id, quantity, location, and operation fields"
        timeout     = "${var.lambda_timeout}s"
      }
    }
  }
}

# Cost Estimation Outputs
# =============================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed infrastructure"
  value = {
    lambda_functions = {
      description = "Lambda function execution costs"
      estimate    = "~$5-15/month for moderate usage (100-1000 requests/day)"
    }
    step_functions = {
      description = "Step Functions workflow execution costs"
      estimate    = "~$2-8/month for moderate usage (100-500 executions/day)"
    }
    api_gateway = {
      description = "API Gateway request and data transfer costs"
      estimate    = "~$3-10/month for moderate usage (1000-5000 requests/day)"
    }
    cloudwatch_logs = {
      description = "CloudWatch Logs storage and retention costs"
      estimate    = "~$2-5/month for moderate logging volume"
    }
    total_estimate = "~$12-38/month for moderate usage across all services"
    notes = [
      "Costs vary based on actual usage patterns",
      "Free tier benefits may apply to some services",
      "Consider using Reserved Capacity for predictable workloads",
      "Monitor costs using AWS Cost Explorer and billing alerts"
    ]
  }
}

# Security and Compliance Outputs
# =============================================================================

output "security_considerations" {
  description = "Important security considerations and recommendations"
  value = {
    iam_roles = {
      lambda_execution    = aws_iam_role.lambda_execution_role.arn
      stepfunctions      = aws_iam_role.stepfunctions_execution_role.arn
      apigateway         = aws_iam_role.apigateway_stepfunctions_role.arn
      principle          = "All roles follow least privilege principle"
    }
    encryption = {
      logs_encrypted     = "CloudWatch Logs encrypted at rest by default"
      lambda_encrypted   = "Lambda environment variables can be encrypted with KMS"
      stepfunctions      = "Step Functions supports encryption at rest and in transit"
      recommendation     = "Consider enabling KMS encryption for sensitive data"
    }
    network_security = {
      api_gateway_type   = "Regional endpoint with HTTPS enforcement"
      vpc_integration    = length(var.vpc_config.subnet_ids) > 0 ? "Enabled" : "Disabled"
      cors_configured    = "CORS enabled for cross-origin requests"
    }
    monitoring = {
      xray_tracing      = var.enable_xray_tracing ? "Enabled" : "Disabled"
      cloudwatch_logs   = "Comprehensive logging across all services"
      access_logging    = "API Gateway access logging enabled"
    }
    recommendations = [
      "Enable AWS CloudTrail for API auditing",
      "Configure AWS Config for compliance monitoring",
      "Set up CloudWatch alarms for error rates and latencies",
      "Consider implementing API rate limiting and throttling",
      "Use AWS Secrets Manager for storing sensitive credentials",
      "Implement proper authentication for production deployments"
    ]
  }
}

# Troubleshooting and Support Outputs
# =============================================================================

output "troubleshooting_guide" {
  description = "Common troubleshooting steps and support resources"
  value = {
    common_issues = {
      lambda_timeouts = {
        description = "Lambda functions timing out"
        solution    = "Check CloudWatch logs and increase timeout if needed"
        log_group   = aws_cloudwatch_log_group.api_transformer_logs.name
      }
      stepfunctions_failures = {
        description = "Step Functions executions failing"
        solution    = "Review execution history and error details in console"
        console_url = "https://${data.aws_region.current.name}.console.aws.amazon.com/states/home"
      }
      api_gateway_errors = {
        description = "API Gateway returning 5xx errors"
        solution    = "Check integration configuration and IAM permissions"
        log_group   = aws_cloudwatch_log_group.api_gateway_logs.name
      }
    }
    support_resources = {
      aws_documentation = "https://docs.aws.amazon.com/"
      cloudwatch_insights = "Use CloudWatch Insights for log analysis"
      xray_traces        = var.enable_xray_tracing ? "X-Ray traces available for distributed debugging" : "Enable X-Ray for distributed tracing"
    }
    log_locations = {
      api_transformer = aws_cloudwatch_log_group.api_transformer_logs.name
      data_validator  = aws_cloudwatch_log_group.data_validator_logs.name
      step_functions  = aws_cloudwatch_log_group.stepfunctions_logs.name
      api_gateway     = aws_cloudwatch_log_group.api_gateway_logs.name
    }
  }
}