# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming conventions
  thing_name         = "${var.thing_name_prefix}-${random_id.suffix.hex}"
  thing_group_name   = "${var.thing_group_name_prefix}-${random_id.suffix.hex}"
  lambda_name        = "${var.lambda_function_name_prefix}-${random_id.suffix.hex}"
  iam_role_name      = "greengrass-core-role-${random_id.suffix.hex}"
  iot_policy_name    = "greengrass-policy-${random_id.suffix.hex}"
  
  # Common tags for all resources
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      ThingName   = local.thing_name
    },
    var.additional_tags
  )
}

# ===================================================================
# IAM Resources for Greengrass Core
# ===================================================================

# IAM role for Greengrass Core device
resource "aws_iam_role" "greengrass_core_role" {
  name = local.iam_role_name
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "credentials.iot.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach AWS managed policy for Greengrass resource access
resource "aws_iam_role_policy_attachment" "greengrass_resource_access" {
  role       = aws_iam_role.greengrass_core_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGreengrassResourceAccessRolePolicy"
}

# Additional IAM policy for CloudWatch Logs access
resource "aws_iam_role_policy" "greengrass_cloudwatch_policy" {
  count = var.enable_cloudwatch_logs ? 1 : 0
  name  = "greengrass-cloudwatch-policy-${random_id.suffix.hex}"
  role  = aws_iam_role.greengrass_core_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/greengrass/*"
      }
    ]
  })
}

# IAM role alias for token exchange
resource "aws_iot_role_alias" "greengrass_role_alias" {
  alias    = "GreengrassV2TokenExchangeRoleAlias-${random_id.suffix.hex}"
  role_arn = aws_iam_role.greengrass_core_role.arn
  
  tags = local.common_tags
}

# ===================================================================
# IoT Core Resources
# ===================================================================

# IoT Thing for Greengrass Core device
resource "aws_iot_thing" "greengrass_core" {
  name = local.thing_name
  
  attributes = {
    environment = var.environment
    purpose     = "edge-computing"
    type        = "greengrass-core"
  }
  
  tags = local.common_tags
}

# IoT Thing Group for device management
resource "aws_iot_thing_group" "greengrass_things" {
  name = local.thing_group_name
  
  properties {
    description = "Greengrass core devices group for ${var.environment} environment"
    
    attribute_payload {
      attributes = {
        environment = var.environment
        purpose     = "edge-computing"
        managed_by  = "terraform"
      }
    }
  }
  
  tags = local.common_tags
}

# Add Thing to Thing Group
resource "aws_iot_thing_group_membership" "greengrass_core_membership" {
  thing_name       = aws_iot_thing.greengrass_core.name
  thing_group_name = aws_iot_thing_group.greengrass_things.name
}

# IoT Certificate for device authentication
resource "aws_iot_certificate" "greengrass_cert" {
  active = true
  
  tags = local.common_tags
}

# IoT Policy for Greengrass Core permissions
resource "aws_iot_policy" "greengrass_policy" {
  name = local.iot_policy_name
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = var.iot_policy_actions
        Resource = "*"
      }
    ]
  })
  
  tags = local.common_tags
}

# Attach policy to certificate
resource "aws_iot_policy_attachment" "greengrass_policy_attachment" {
  policy = aws_iot_policy.greengrass_policy.name
  target = aws_iot_certificate.greengrass_cert.arn
}

# Attach certificate to thing
resource "aws_iot_thing_principal_attachment" "greengrass_cert_attachment" {
  thing     = aws_iot_thing.greengrass_core.name
  principal = aws_iot_certificate.greengrass_cert.arn
}

# ===================================================================
# Lambda Function for Edge Processing
# ===================================================================

# Lambda function source code
locals {
  lambda_source_code = <<EOF
import json
import logging
import time

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process sensor data at the edge
    """
    logger.info(f"Processing edge data: {event}")
    
    # Simulate sensor data processing
    processed_data = {
        "timestamp": int(time.time()),
        "device_id": event.get("device_id", "unknown"),
        "temperature": event.get("temperature", 0),
        "status": "processed_at_edge",
        "processing_time": 0.1,
        "location": event.get("location", "edge-device")
    }
    
    # Add some basic validation and processing logic
    if processed_data["temperature"] > 30:
        processed_data["alert"] = "high_temperature"
    elif processed_data["temperature"] < 5:
        processed_data["alert"] = "low_temperature"
    else:
        processed_data["alert"] = "normal"
    
    logger.info(f"Processed data: {processed_data}")
    
    return {
        "statusCode": 200,
        "body": json.dumps(processed_data)
    }
EOF
}

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/edge-processor.zip"
  
  source {
    content  = local.lambda_source_code
    filename = "lambda_function.py"
  }
}

# Lambda function for edge processing
resource "aws_lambda_function" "edge_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_name
  role            = aws_iam_role.greengrass_core_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  
  description = "Edge processing Lambda function for Greengrass deployment"
  
  environment {
    variables = {
      ENVIRONMENT = var.environment
      THING_NAME  = local.thing_name
    }
  }
  
  tags = local.common_tags
}

# Lambda function version for Greengrass deployment
resource "aws_lambda_alias" "edge_processor_alias" {
  name             = "PROD"
  description      = "Production alias for edge processor function"
  function_name    = aws_lambda_function.edge_processor.function_name
  function_version = aws_lambda_function.edge_processor.version
}

# ===================================================================
# CloudWatch Logs for Greengrass
# ===================================================================

# CloudWatch Log Group for Greengrass Core logs
resource "aws_cloudwatch_log_group" "greengrass_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/greengrass/core/${local.thing_name}"
  retention_in_days = var.log_retention_days
  
  tags = local.common_tags
}

# CloudWatch Log Group for Lambda function logs
resource "aws_cloudwatch_log_group" "lambda_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/lambda/${local.lambda_name}"
  retention_in_days = var.log_retention_days
  
  tags = local.common_tags
}

# ===================================================================
# Greengrass V2 Components and Deployment
# ===================================================================

# Greengrass Core Device (requires manual installation of Greengrass software)
# This creates the device registration but the actual software must be installed manually

# Component definition for custom Lambda function
locals {
  lambda_component_recipe = {
    RecipeFormatVersion = "2020-01-25"
    ComponentName       = "com.example.EdgeProcessor"
    ComponentVersion    = var.custom_component_version
    ComponentDescription = "Edge processing Lambda component"
    ComponentPublisher  = "Custom"
    ComponentConfiguration = {
      DefaultConfiguration = {
        accessControl = {
          "aws.greengrass.ipc.mqttproxy" = {
            "com.example.EdgeProcessor:mqttproxy:1" = {
              policyDescription = "Allows access to MQTT proxy"
              operations = [
                "aws.greengrass#PublishToIoTCore",
                "aws.greengrass#SubscribeToIoTCore"
              ]
              resources = ["*"]
            }
          }
        }
        lambdaExecutionParameters = {
          EnvironmentVariables = {
            ENVIRONMENT = var.environment
            THING_NAME  = local.thing_name
          }
        }
      }
    }
    Manifests = [
      {
        Platform = {
          os = "linux"
        }
        Lifecycle = {
          Run = "python3 -u {artifacts:decompressedPath}/lambda_function.py"
        }
        Artifacts = [
          {
            URI = "lambda://${aws_lambda_function.edge_processor.function_name}:${aws_lambda_alias.edge_processor_alias.name}"
          }
        ]
      }
    ]
  }
  
  # Stream Manager configuration
  stream_manager_config = var.enable_stream_manager ? {
    streams = [
      {
        name                = "sensor-data-stream"
        maxSize             = 1000
        streamSegmentSize   = 100
        timeToLiveMillis    = 3600000
        strategyOnFull      = "OverwriteOldestData"
        exportDefinition = {
          iotAnalytics = [
            {
              identifier    = "sensor-data-export"
              batchSize     = 10
              batchIntervalMillis = 5000
            }
          ]
        }
      }
    ]
  } : null
}

# Greengrass Deployment for Thing Group
resource "aws_greengrassv2_deployment" "main_deployment" {
  target_arn     = aws_iot_thing_group.greengrass_things.arn
  deployment_name = "main-deployment-${random_id.suffix.hex}"
  
  component {
    component_name    = "aws.greengrass.Nucleus"
    component_version = var.greengrass_nucleus_version
    
    configuration_update {
      merge = jsonencode({
        logging = {
          level = "INFO"
          format = "TEXT"
          outputDirectory = "/greengrass/v2/logs"
          fileSizeKB = 1024
          totalLogsSizeKB = 10240
        }
        telemetry = {
          enabled = true
          periodicAggregateMetricsIntervalSeconds = 3600
          periodicPublishMetricsIntervalSeconds = 86400
        }
      })
    }
  }
  
  # Stream Manager component (conditional)
  dynamic "component" {
    for_each = var.enable_stream_manager ? [1] : []
    
    content {
      component_name    = "aws.greengrass.StreamManager"
      component_version = var.stream_manager_version
      
      configuration_update {
        merge = jsonencode(local.stream_manager_config)
      }
    }
  }
  
  # CloudWatch Logs component (conditional)
  dynamic "component" {
    for_each = var.enable_cloudwatch_logs ? [1] : []
    
    content {
      component_name    = "aws.greengrass.LogManager"
      component_version = "2.3.7"
      
      configuration_update {
        merge = jsonencode({
          logsUploaderConfiguration = {
            systemLogsConfiguration = {
              uploadToCloudWatch = "true"
              logGroupName = "/aws/greengrass/core/${local.thing_name}"
              logStreamName = "system"
            }
            componentLogsConfigurationMap = {
              "com.example.EdgeProcessor" = {
                logGroupName = "/aws/greengrass/UserComponent/${local.thing_name}/com.example.EdgeProcessor"
                logStreamName = "edge-processor"
              }
            }
          }
          periodicUploadIntervalSec = "300"
        })
      }
    }
  }
  
  deployment_policies {
    timeout_config {
      timeout_in_seconds = 300
    }
    
    failure_handling_policy = "ROLLBACK"
    
    component_update_policy {
      timeout_in_seconds = 300
      action             = "NOTIFY_COMPONENTS"
    }
  }
  
  tags = local.common_tags
}

# ===================================================================
# Output Values for Integration and Verification
# ===================================================================

# Core device information
output "greengrass_core_thing_name" {
  description = "Name of the Greengrass Core IoT Thing"
  value       = aws_iot_thing.greengrass_core.name
}

output "greengrass_core_thing_arn" {
  description = "ARN of the Greengrass Core IoT Thing"
  value       = aws_iot_thing.greengrass_core.arn
}

output "thing_group_name" {
  description = "Name of the IoT Thing Group"
  value       = aws_iot_thing_group.greengrass_things.name
}

output "thing_group_arn" {
  description = "ARN of the IoT Thing Group"
  value       = aws_iot_thing_group.greengrass_things.arn
}

# Security and authentication
output "iot_certificate_arn" {
  description = "ARN of the IoT certificate for device authentication"
  value       = aws_iot_certificate.greengrass_cert.arn
}

output "iot_certificate_pem" {
  description = "PEM-encoded certificate data"
  value       = aws_iot_certificate.greengrass_cert.certificate_pem
  sensitive   = true
}

output "iot_private_key" {
  description = "PEM-encoded private key"
  value       = aws_iot_certificate.greengrass_cert.private_key
  sensitive   = true
}

output "iot_public_key" {
  description = "PEM-encoded public key"
  value       = aws_iot_certificate.greengrass_cert.public_key
}

output "iot_role_alias_arn" {
  description = "ARN of the IoT Role Alias for token exchange"
  value       = aws_iot_role_alias.greengrass_role_alias.arn
}

# Lambda function information
output "edge_processor_function_name" {
  description = "Name of the edge processing Lambda function"
  value       = aws_lambda_function.edge_processor.function_name
}

output "edge_processor_function_arn" {
  description = "ARN of the edge processing Lambda function"
  value       = aws_lambda_function.edge_processor.arn
}

# Deployment information
output "greengrass_deployment_id" {
  description = "ID of the Greengrass deployment"
  value       = aws_greengrassv2_deployment.main_deployment.deployment_id
}

output "greengrass_deployment_arn" {
  description = "ARN of the Greengrass deployment"
  value       = aws_greengrassv2_deployment.main_deployment.arn
}

# IoT Core endpoints
output "iot_data_endpoint" {
  description = "IoT Core data endpoint for MQTT communication"
  value       = "https://${data.aws_iot_endpoint.data.endpoint_address}"
}

output "iot_credential_endpoint" {
  description = "IoT Core credential provider endpoint"
  value       = "https://${data.aws_iot_endpoint.credential.endpoint_address}"
}

# CloudWatch information
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group for Greengrass logs"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.greengrass_logs[0].name : null
}

# ===================================================================
# Additional Data Sources
# ===================================================================

# IoT Core endpoints
data "aws_iot_endpoint" "data" {
  endpoint_type = "iot:Data-ATS"
}

data "aws_iot_endpoint" "credential" {
  endpoint_type = "iot:CredentialProvider"
}

# Download URL for Amazon Root CA
data "aws_partition" "current" {}

locals {
  amazon_root_ca_url = "https://www.amazontrust.com/repository/AmazonRootCA1.pem"
}

# ===================================================================
# Installation Instructions Output
# ===================================================================

output "installation_instructions" {
  description = "Instructions for installing Greengrass Core software"
  value = <<-EOT
    To complete the Greengrass Core installation:
    
    1. Download and install Greengrass Core software:
       curl -s https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip -o greengrass-nucleus-latest.zip
       unzip greengrass-nucleus-latest.zip -d GreengrassCore
    
    2. Create certificates directory:
       sudo mkdir -p /greengrass/v2
       
    3. Save the following files to /greengrass/v2/:
       - device.pem.crt (from iot_certificate_pem output)
       - private.pem.key (from iot_private_key output)
       - AmazonRootCA1.pem (download from ${local.amazon_root_ca_url})
    
    4. Install Greengrass Core:
       sudo -E java -Droot="/greengrass/v2" -Dlog.store=FILE \
         -jar GreengrassCore/lib/Greengrass.jar \
         --thing-name ${local.thing_name} \
         --thing-group-name ${local.thing_group_name} \
         --tes-role-name ${local.iam_role_name} \
         --tes-role-alias-name GreengrassV2TokenExchangeRoleAlias-${random_id.suffix.hex} \
         --component-default-user ggc_user:ggc_group \
         --provision false \
         --setup-system-service true \
         --deploy-dev-tools true
    
    5. Verify installation:
       sudo systemctl status greengrass
       
    For detailed installation instructions, visit:
    https://docs.aws.amazon.com/greengrass/v2/developerguide/install-greengrass-core-v2.html
  EOT
}