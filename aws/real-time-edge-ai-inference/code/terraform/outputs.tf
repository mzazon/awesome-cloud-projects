# =========================================
# Core Infrastructure Outputs
# =========================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "project_name" {
  description = "Project name with random suffix for unique resource naming"
  value       = local.name_prefix
}

# =========================================
# S3 Storage Outputs
# =========================================

output "model_bucket_name" {
  description = "Name of the S3 bucket storing ML models"
  value       = aws_s3_bucket.model_bucket.id
}

output "model_bucket_arn" {
  description = "ARN of the S3 bucket storing ML models"
  value       = aws_s3_bucket.model_bucket.arn
}

output "model_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.model_bucket.bucket_domain_name
}

output "model_s3_uri" {
  description = "S3 URI for the current model version"
  value       = "s3://${aws_s3_bucket.model_bucket.id}/models/v${var.model_version}/"
}

# =========================================
# IoT Core Outputs
# =========================================

output "greengrass_thing_name" {
  description = "Name of the IoT Greengrass thing"
  value       = aws_iot_thing.greengrass_core.name
}

output "greengrass_thing_arn" {
  description = "ARN of the IoT Greengrass thing"
  value       = aws_iot_thing.greengrass_core.arn
}

output "iot_policy_name" {
  description = "Name of the IoT policy for Greengrass device"
  value       = aws_iot_policy.greengrass_device_policy.name
}

output "iot_role_alias_name" {
  description = "Name of the IoT role alias"
  value       = aws_iot_role_alias.greengrass_role_alias.alias
}

output "iot_role_alias_arn" {
  description = "ARN of the IoT role alias"
  value       = aws_iot_role_alias.greengrass_role_alias.arn
}

# =========================================
# IAM Role Outputs
# =========================================

output "greengrass_token_exchange_role_name" {
  description = "Name of the Greengrass token exchange role"
  value       = aws_iam_role.greengrass_token_exchange_role.name
}

output "greengrass_token_exchange_role_arn" {
  description = "ARN of the Greengrass token exchange role"
  value       = aws_iam_role.greengrass_token_exchange_role.arn
}

output "greengrass_device_policy_arn" {
  description = "ARN of the Greengrass device policy"
  value       = aws_iam_policy.greengrass_device_policy.arn
}

# =========================================
# EventBridge Outputs
# =========================================

output "event_bus_name" {
  description = "Name of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.edge_monitoring.name
}

output "event_bus_arn" {
  description = "ARN of the custom EventBridge bus"
  value       = aws_cloudwatch_event_bus.edge_monitoring.arn
}

output "event_rule_name" {
  description = "Name of the EventBridge rule for inference monitoring"
  value       = aws_cloudwatch_event_rule.edge_inference_monitoring.name
}

output "event_rule_arn" {
  description = "ARN of the EventBridge rule for inference monitoring"
  value       = aws_cloudwatch_event_rule.edge_inference_monitoring.arn
}

# =========================================
# CloudWatch Outputs
# =========================================

output "edge_events_log_group_name" {
  description = "Name of the CloudWatch log group for edge events"
  value       = aws_cloudwatch_log_group.edge_events.name
}

output "edge_events_log_group_arn" {
  description = "ARN of the CloudWatch log group for edge events"
  value       = aws_cloudwatch_log_group.edge_events.arn
}

output "greengrass_log_group_name" {
  description = "Name of the CloudWatch log group for Greengrass (if enabled)"
  value       = var.enable_greengrass_logging ? aws_cloudwatch_log_group.greengrass_logs[0].name : null
}

output "greengrass_log_group_arn" {
  description = "ARN of the CloudWatch log group for Greengrass (if enabled)"
  value       = var.enable_greengrass_logging ? aws_cloudwatch_log_group.greengrass_logs[0].arn : null
}

# =========================================
# Greengrass Component Outputs
# =========================================

output "onnx_runtime_component_name" {
  description = "Name of the ONNX Runtime Greengrass component"
  value       = aws_greengrassv2_component_version.onnx_runtime.component_name
}

output "onnx_runtime_component_version" {
  description = "Version of the ONNX Runtime Greengrass component"
  value       = aws_greengrassv2_component_version.onnx_runtime.component_version
}

output "model_component_name" {
  description = "Name of the Model Greengrass component"
  value       = aws_greengrassv2_component_version.model_component.component_name
}

output "model_component_version" {
  description = "Version of the Model Greengrass component"
  value       = aws_greengrassv2_component_version.model_component.component_version
}

output "inference_component_name" {
  description = "Name of the Inference Engine Greengrass component"
  value       = aws_greengrassv2_component_version.inference_component.component_name
}

output "inference_component_version" {
  description = "Version of the Inference Engine Greengrass component"
  value       = aws_greengrassv2_component_version.inference_component.component_version
}

# =========================================
# Deployment Outputs
# =========================================

output "deployment_id" {
  description = "ID of the Greengrass deployment"
  value       = aws_greengrassv2_deployment.edge_deployment.deployment_id
}

output "deployment_name" {
  description = "Name of the Greengrass deployment"
  value       = aws_greengrassv2_deployment.edge_deployment.deployment_name
}

output "deployment_arn" {
  description = "ARN of the Greengrass deployment"
  value       = aws_greengrassv2_deployment.edge_deployment.arn
}

# =========================================
# Model Configuration Outputs
# =========================================

output "model_name" {
  description = "Name of the machine learning model"
  value       = var.model_name
}

output "model_version" {
  description = "Version of the machine learning model"
  value       = var.model_version
}

output "model_framework" {
  description = "Framework of the machine learning model"
  value       = var.model_framework
}

# =========================================
# Security Outputs
# =========================================

output "cloudtrail_name" {
  description = "Name of the CloudTrail (if enabled)"
  value       = var.enable_cloudtrail_logging ? aws_cloudtrail.api_logging[0].name : null
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail (if enabled)"
  value       = var.enable_cloudtrail_logging ? aws_cloudtrail.api_logging[0].arn : null
}

# =========================================
# Configuration Outputs for Device Setup
# =========================================

output "greengrass_configuration_yaml" {
  description = "Greengrass configuration YAML for edge device setup"
  value = yamlencode({
    system = {
      certificateFilePath = "/greengrass/v2/certificates/cert.pem"
      privateKeyPath      = "/greengrass/v2/certificates/private.key"
      rootCaPath          = "/greengrass/v2/certificates/AmazonRootCA1.pem"
      thingName           = aws_iot_thing.greengrass_core.name
    }
    services = {
      "aws.greengrass.Nucleus" = {
        configuration = {
          awsRegion     = data.aws_region.current.name
          iotRoleAlias  = aws_iot_role_alias.greengrass_role_alias.alias
          mqtt = {
            port = 8883
          }
        }
      }
    }
  })
  sensitive = false
}

# =========================================
# Monitoring Commands
# =========================================

output "monitoring_commands" {
  description = "Useful commands for monitoring the edge AI system"
  value = {
    check_deployment_status = "aws greengrassv2 get-deployment --deployment-id ${aws_greengrassv2_deployment.edge_deployment.deployment_id}"
    view_edge_events       = "aws logs tail ${aws_cloudwatch_log_group.edge_events.name} --follow --format short"
    list_components        = "aws greengrassv2 list-components"
    describe_thing         = "aws iot describe-thing --thing-name ${aws_iot_thing.greengrass_core.name}"
  }
}

# =========================================
# Cost Estimation Outputs
# =========================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    s3_storage_gb       = "~$0.023 per GB stored (Standard storage class)"
    eventbridge_events  = "~$1.00 per million events"
    cloudwatch_logs_gb  = "~$0.50 per GB ingested"
    iot_core_messages   = "~$1.20 per million messages"
    greengrass_core     = "Free tier: 3 devices, $2.00 per device per month after"
    total_estimate_low  = "$5-10 per month for typical usage"
    total_estimate_high = "$20-50 per month for high-volume scenarios"
  }
}

# =========================================
# Next Steps Outputs
# =========================================

output "next_steps" {
  description = "Next steps to complete the edge AI setup"
  value = [
    "1. Install AWS IoT Greengrass Core software on your edge device",
    "2. Use the greengrass_configuration_yaml output to configure the device",
    "3. Monitor deployment status with: ${aws_greengrassv2_deployment.edge_deployment.deployment_id}",
    "4. Check EventBridge events in CloudWatch Logs: ${aws_cloudwatch_log_group.edge_events.name}",
    "5. Upload your trained ONNX model to: s3://${aws_s3_bucket.model_bucket.id}/models/v${var.model_version}/",
    "6. Test inference by placing sample images on the edge device"
  ]
}