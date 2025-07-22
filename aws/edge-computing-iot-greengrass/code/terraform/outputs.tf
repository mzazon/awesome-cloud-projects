# ===================================================================
# Core Infrastructure Outputs
# ===================================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# ===================================================================
# IoT Core Resources Outputs
# ===================================================================

output "greengrass_core_thing_name" {
  description = "Name of the Greengrass Core IoT Thing"
  value       = aws_iot_thing.greengrass_core.name
}

output "greengrass_core_thing_arn" {
  description = "ARN of the Greengrass Core IoT Thing"
  value       = aws_iot_thing.greengrass_core.arn
}

output "thing_group_name" {
  description = "Name of the IoT Thing Group for device management"
  value       = aws_iot_thing_group.greengrass_things.name
}

output "thing_group_arn" {
  description = "ARN of the IoT Thing Group"
  value       = aws_iot_thing_group.greengrass_things.arn
}

output "iot_policy_name" {
  description = "Name of the IoT policy for Greengrass permissions"
  value       = aws_iot_policy.greengrass_policy.name
}

output "iot_policy_arn" {
  description = "ARN of the IoT policy"
  value       = aws_iot_policy.greengrass_policy.arn
}

# ===================================================================
# Security and Authentication Outputs
# ===================================================================

output "iot_certificate_arn" {
  description = "ARN of the IoT certificate for device authentication"
  value       = aws_iot_certificate.greengrass_cert.arn
}

output "iot_certificate_id" {
  description = "ID of the IoT certificate"
  value       = aws_iot_certificate.greengrass_cert.id
}

output "iot_certificate_pem" {
  description = "PEM-encoded certificate data for device authentication"
  value       = aws_iot_certificate.greengrass_cert.certificate_pem
  sensitive   = true
}

output "iot_private_key" {
  description = "PEM-encoded private key for device authentication"
  value       = aws_iot_certificate.greengrass_cert.private_key
  sensitive   = true
}

output "iot_public_key" {
  description = "PEM-encoded public key"
  value       = aws_iot_certificate.greengrass_cert.public_key
}

output "greengrass_core_role_name" {
  description = "Name of the IAM role for Greengrass Core"
  value       = aws_iam_role.greengrass_core_role.name
}

output "greengrass_core_role_arn" {
  description = "ARN of the IAM role for Greengrass Core"
  value       = aws_iam_role.greengrass_core_role.arn
}

output "iot_role_alias_name" {
  description = "Name of the IoT Role Alias for token exchange"
  value       = aws_iot_role_alias.greengrass_role_alias.alias
}

output "iot_role_alias_arn" {
  description = "ARN of the IoT Role Alias for token exchange"
  value       = aws_iot_role_alias.greengrass_role_alias.arn
}

# ===================================================================
# Lambda Function Outputs
# ===================================================================

output "edge_processor_function_name" {
  description = "Name of the edge processing Lambda function"
  value       = aws_lambda_function.edge_processor.function_name
}

output "edge_processor_function_arn" {
  description = "ARN of the edge processing Lambda function"
  value       = aws_lambda_function.edge_processor.arn
}

output "edge_processor_function_version" {
  description = "Version of the edge processing Lambda function"
  value       = aws_lambda_function.edge_processor.version
}

output "edge_processor_alias_name" {
  description = "Name of the Lambda function alias"
  value       = aws_lambda_alias.edge_processor_alias.name
}

output "edge_processor_alias_arn" {
  description = "ARN of the Lambda function alias"
  value       = aws_lambda_alias.edge_processor_alias.arn
}

# ===================================================================
# Greengrass Deployment Outputs
# ===================================================================

output "greengrass_deployment_id" {
  description = "ID of the Greengrass deployment"
  value       = aws_greengrassv2_deployment.main_deployment.deployment_id
}

output "greengrass_deployment_arn" {
  description = "ARN of the Greengrass deployment"
  value       = aws_greengrassv2_deployment.main_deployment.arn
}

output "greengrass_deployment_name" {
  description = "Name of the Greengrass deployment"
  value       = aws_greengrassv2_deployment.main_deployment.deployment_name
}

# ===================================================================
# IoT Core Endpoints
# ===================================================================

output "iot_data_endpoint" {
  description = "IoT Core data endpoint for MQTT communication"
  value       = data.aws_iot_endpoint.data.endpoint_address
}

output "iot_credential_endpoint" {
  description = "IoT Core credential provider endpoint for token exchange"
  value       = data.aws_iot_endpoint.credential.endpoint_address
}

output "iot_data_endpoint_url" {
  description = "Complete IoT Core data endpoint URL"
  value       = "https://${data.aws_iot_endpoint.data.endpoint_address}"
}

output "iot_credential_endpoint_url" {
  description = "Complete IoT Core credential provider endpoint URL"
  value       = "https://${data.aws_iot_endpoint.credential.endpoint_address}"
}

# ===================================================================
# CloudWatch Logs Outputs
# ===================================================================

output "cloudwatch_logs_enabled" {
  description = "Whether CloudWatch Logs is enabled for Greengrass"
  value       = var.enable_cloudwatch_logs
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group for Greengrass Core logs"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.greengrass_logs[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for Greengrass Core logs"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.greengrass_logs[0].arn : null
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch Log Group for Lambda function logs"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.lambda_logs[0].name : null
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch Log Group for Lambda function logs"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.lambda_logs[0].arn : null
}

# ===================================================================
# Stream Manager Configuration Outputs
# ===================================================================

output "stream_manager_enabled" {
  description = "Whether Stream Manager is enabled"
  value       = var.enable_stream_manager
}

output "stream_manager_version" {
  description = "Version of Stream Manager component deployed"
  value       = var.enable_stream_manager ? var.stream_manager_version : null
}

# ===================================================================
# Installation and Configuration Outputs
# ===================================================================

output "amazon_root_ca_url" {
  description = "URL to download Amazon Root CA certificate"
  value       = "https://www.amazontrust.com/repository/AmazonRootCA1.pem"
}

output "greengrass_nucleus_version" {
  description = "Version of Greengrass Nucleus component"
  value       = var.greengrass_nucleus_version
}

output "installation_summary" {
  description = "Summary of key information needed for Greengrass Core installation"
  value = {
    thing_name          = local.thing_name
    thing_group_name    = local.thing_group_name
    role_name           = local.iam_role_name
    role_alias_name     = aws_iot_role_alias.greengrass_role_alias.alias
    certificate_arn     = aws_iot_certificate.greengrass_cert.arn
    iot_data_endpoint   = data.aws_iot_endpoint.data.endpoint_address
    iot_cred_endpoint   = data.aws_iot_endpoint.credential.endpoint_address
    aws_region          = data.aws_region.current.name
  }
}

# ===================================================================
# Verification Commands Output
# ===================================================================

output "verification_commands" {
  description = "Commands to verify the Greengrass deployment"
  value = {
    check_thing_status = "aws iot describe-thing --thing-name ${local.thing_name}"
    check_certificate  = "aws iot describe-certificate --certificate-id ${aws_iot_certificate.greengrass_cert.id}"
    check_deployment   = "aws greengrassv2 get-deployment --deployment-id ${aws_greengrassv2_deployment.main_deployment.deployment_id}"
    list_core_devices  = "aws greengrassv2 list-core-devices --thing-group-arn ${aws_iot_thing_group.greengrass_things.arn}"
    test_lambda        = "aws lambda invoke --function-name ${local.lambda_name} --payload '{\"device_id\": \"test-sensor\", \"temperature\": 25.5}' response.json && cat response.json"
  }
}

# ===================================================================
# Next Steps Output
# ===================================================================

output "next_steps" {
  description = "Next steps to complete the Greengrass Core setup"
  value = [
    "1. Save the certificate and private key from the sensitive outputs to your device",
    "2. Download Amazon Root CA from: https://www.amazontrust.com/repository/AmazonRootCA1.pem",
    "3. Install Greengrass Core software using the installation_instructions output",
    "4. Verify installation with: sudo systemctl status greengrass",
    "5. Check deployment status in AWS Console or using verification commands",
    "6. Test Lambda function execution on the edge device",
    "7. Monitor logs in CloudWatch (if enabled) or local device logs"
  ]
}