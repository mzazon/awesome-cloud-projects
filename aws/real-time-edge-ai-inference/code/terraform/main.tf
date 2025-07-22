# =========================================
# Data Sources
# =========================================

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# =========================================
# Local Values
# =========================================

locals {
  # Resource naming convention
  name_prefix = "${var.project_name}-${random_string.suffix.result}"
  
  # Determine Greengrass thing name
  greengrass_thing_name = var.greengrass_thing_name != "" ? var.greengrass_thing_name : "${local.name_prefix}-device"
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      Recipe      = "implementing-real-time-edge-ai-inference-with-sagemaker-edge-manager-and-iot-greengrass"
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
  
  # S3 bucket name
  model_bucket_name = "${local.name_prefix}-models"
  
  # EventBridge bus name
  event_bus_name = var.event_bus_name != "" ? var.event_bus_name : "${local.name_prefix}-monitoring-bus"
}

# =========================================
# S3 Bucket for Model Storage
# =========================================

# S3 bucket for storing ML models and artifacts
resource "aws_s3_bucket" "model_bucket" {
  bucket = local.model_bucket_name

  tags = merge(local.common_tags, {
    Name        = local.model_bucket_name
    Purpose     = "Model Storage"
    Component   = "Storage"
  })
}

# Configure bucket versioning
resource "aws_s3_bucket_versioning" "model_bucket_versioning" {
  bucket = aws_s3_bucket.model_bucket.id
  
  versioning_configuration {
    status = var.model_bucket_versioning ? "Enabled" : "Suspended"
  }
}

# Configure server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "model_bucket_encryption" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.model_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.s3_kms_key_id != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.s3_kms_key_id
    }
    bucket_key_enabled = var.s3_kms_key_id != null ? true : false
  }
}

# Configure bucket public access block
resource "aws_s3_bucket_public_access_block" "model_bucket_pab" {
  bucket = aws_s3_bucket.model_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Configure lifecycle management
resource "aws_s3_bucket_lifecycle_configuration" "model_bucket_lifecycle" {
  count  = var.model_bucket_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.model_bucket.id

  rule {
    id     = "delete_noncurrent_versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = var.model_bucket_noncurrent_version_expiration
    }
  }

  dynamic "rule" {
    for_each = var.s3_intelligent_tiering ? [1] : []
    content {
      id     = "intelligent_tiering"
      status = "Enabled"

      transition {
        days          = 0
        storage_class = "INTELLIGENT_TIERING"
      }
    }
  }
}

# Upload sample model artifacts
resource "aws_s3_object" "sample_model" {
  bucket  = aws_s3_bucket.model_bucket.id
  key     = "models/v${var.model_version}/model.onnx"
  content = "# Placeholder ONNX model file\n# Replace with actual trained model\n"
  
  tags = merge(local.common_tags, {
    ModelVersion = var.model_version
    ModelName    = var.model_name
  })
}

resource "aws_s3_object" "model_config" {
  bucket  = aws_s3_bucket.model_bucket.id
  key     = "models/v${var.model_version}/config.json"
  content = jsonencode({
    model_name     = var.model_name
    model_version  = var.model_version
    input_shape    = [1, 3, 224, 224]
    output_classes = ["normal", "defect"]
    framework      = var.model_framework
    created_at     = timestamp()
  })
  
  tags = merge(local.common_tags, {
    ModelVersion = var.model_version
    ModelName    = var.model_name
  })
}

resource "aws_s3_object" "model_metadata" {
  bucket  = aws_s3_bucket.model_bucket.id
  key     = "models/metadata.json"
  content = jsonencode({
    model_name     = var.model_name
    model_version  = var.model_version
    input_shape    = [1, 3, 224, 224]
    output_classes = ["normal", "defect"]
    framework      = var.model_framework
    created_at     = timestamp()
  })
  
  tags = merge(local.common_tags, {
    Purpose = "Model Metadata"
  })
}

# =========================================
# IAM Roles and Policies for IoT Greengrass
# =========================================

# Trust policy for Greengrass Token Exchange Service
data "aws_iam_policy_document" "greengrass_trust_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["credentials.iot.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# Greengrass Token Exchange Role
resource "aws_iam_role" "greengrass_token_exchange_role" {
  name               = "${local.name_prefix}-GreengrassV2TokenExchangeRole"
  assume_role_policy = data.aws_iam_policy_document.greengrass_trust_policy.json
  
  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-GreengrassV2TokenExchangeRole"
    Purpose   = "Greengrass Token Exchange"
    Component = "Security"
  })
}

# Attach AWS managed policy for Greengrass Token Exchange
resource "aws_iam_role_policy_attachment" "greengrass_token_exchange_policy" {
  role       = aws_iam_role.greengrass_token_exchange_role.name
  policy_arn = "arn:aws:iam::aws:policy/GreengrassV2TokenExchangeRoleAccess"
}

# Custom policy for accessing S3 models and EventBridge
data "aws_iam_policy_document" "greengrass_device_policy" {
  # S3 permissions for model access
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion"
    ]
    resources = [
      "${aws_s3_bucket.model_bucket.arn}/*"
    ]
  }
  
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.model_bucket.arn
    ]
  }
  
  # EventBridge permissions
  statement {
    effect = "Allow"
    actions = [
      "events:PutEvents"
    ]
    resources = [
      "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:event-bus/${local.event_bus_name}",
      "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:event-bus/default"
    ]
  }
  
  # CloudWatch Logs permissions
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/greengrass/*",
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/events/*"
    ]
  }
}

resource "aws_iam_policy" "greengrass_device_policy" {
  name        = "${local.name_prefix}-GreengrassDevicePolicy"
  description = "Policy for Greengrass device to access AWS services"
  policy      = data.aws_iam_policy_document.greengrass_device_policy.json
  
  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-GreengrassDevicePolicy"
    Purpose   = "Greengrass Device Access"
    Component = "Security"
  })
}

resource "aws_iam_role_policy_attachment" "greengrass_device_policy_attachment" {
  role       = aws_iam_role.greengrass_token_exchange_role.name
  policy_arn = aws_iam_policy.greengrass_device_policy.arn
}

# =========================================
# IoT Core Resources
# =========================================

# IoT Thing for Greengrass Core device
resource "aws_iot_thing" "greengrass_core" {
  name = local.greengrass_thing_name
  
  attributes = {
    DeviceType    = var.greengrass_core_device_type
    Environment   = var.environment
    Project       = var.project_name
  }
  
  tags = merge(local.common_tags, {
    Name      = local.greengrass_thing_name
    Purpose   = "Greengrass Core Device"
    Component = "IoT"
  })
}

# IoT Policy for Greengrass device
data "aws_iam_policy_document" "iot_device_policy" {
  statement {
    effect = "Allow"
    actions = [
      "iot:Connect",
      "iot:Publish",
      "iot:Subscribe",
      "iot:Receive",
      "greengrass:*"
    ]
    resources = ["*"]
  }
}

resource "aws_iot_policy" "greengrass_device_policy" {
  name   = "${local.name_prefix}-GreengrassV2IoTThingPolicy"
  policy = data.aws_iam_policy_document.iot_device_policy.json
  
  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-GreengrassV2IoTThingPolicy"
    Purpose   = "IoT Device Policy"
    Component = "Security"
  })
}

# IoT Role Alias for Greengrass
resource "aws_iot_role_alias" "greengrass_role_alias" {
  alias    = "${local.name_prefix}-GreengrassV2TokenExchangeRoleAlias"
  role_arn = aws_iam_role.greengrass_token_exchange_role.arn
  
  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-GreengrassV2TokenExchangeRoleAlias"
    Purpose   = "Role Alias"
    Component = "Security"
  })
}

# =========================================
# EventBridge Resources
# =========================================

# Custom EventBridge bus for edge monitoring
resource "aws_cloudwatch_event_bus" "edge_monitoring" {
  name = local.event_bus_name
  
  tags = merge(local.common_tags, {
    Name      = local.event_bus_name
    Purpose   = "Edge Monitoring"
    Component = "EventBridge"
  })
}

# EventBridge rule for inference events
resource "aws_cloudwatch_event_rule" "edge_inference_monitoring" {
  name           = "${local.name_prefix}-edge-inference-monitoring"
  description    = "Capture inference events from edge devices"
  event_bus_name = aws_cloudwatch_event_bus.edge_monitoring.name
  
  event_pattern = jsonencode({
    source        = ["edge.ai.inference"]
    detail-type   = ["InferenceCompleted", "InferenceError", "ModelLoadError"]
  })
  
  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-edge-inference-monitoring"
    Purpose   = "Event Monitoring"
    Component = "EventBridge"
  })
}

# =========================================
# CloudWatch Resources
# =========================================

# CloudWatch Log Group for EventBridge events
resource "aws_cloudwatch_log_group" "edge_events" {
  name              = "/aws/events/edge-inference"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = merge(local.common_tags, {
    Name      = "/aws/events/edge-inference"
    Purpose   = "Event Logging"
    Component = "CloudWatch"
  })
}

# CloudWatch Log Group for Greengrass
resource "aws_cloudwatch_log_group" "greengrass_logs" {
  count             = var.enable_greengrass_logging ? 1 : 0
  name              = "/aws/greengrass/${local.greengrass_thing_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = merge(local.common_tags, {
    Name      = "/aws/greengrass/${local.greengrass_thing_name}"
    Purpose   = "Greengrass Logging"
    Component = "CloudWatch"
  })
}

# EventBridge target to send events to CloudWatch Logs
resource "aws_cloudwatch_event_target" "edge_events_target" {
  rule           = aws_cloudwatch_event_rule.edge_inference_monitoring.name
  event_bus_name = aws_cloudwatch_event_bus.edge_monitoring.name
  arn            = aws_cloudwatch_log_group.edge_events.arn
  target_id      = "EdgeInferenceLogsTarget"
}

# IAM role for EventBridge to write to CloudWatch Logs
data "aws_iam_policy_document" "eventbridge_logs_trust" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eventbridge_logs_role" {
  name               = "${local.name_prefix}-EventBridgeLogsRole"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_logs_trust.json
  
  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-EventBridgeLogsRole"
    Purpose   = "EventBridge Logs"
    Component = "Security"
  })
}

data "aws_iam_policy_document" "eventbridge_logs_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      aws_cloudwatch_log_group.edge_events.arn,
      "${aws_cloudwatch_log_group.edge_events.arn}:*"
    ]
  }
}

resource "aws_iam_policy" "eventbridge_logs_policy" {
  name        = "${local.name_prefix}-EventBridgeLogsPolicy"
  description = "Policy for EventBridge to write to CloudWatch Logs"
  policy      = data.aws_iam_policy_document.eventbridge_logs_policy.json
  
  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-EventBridgeLogsPolicy"
    Purpose   = "EventBridge Logs Policy"
    Component = "Security"
  })
}

resource "aws_iam_role_policy_attachment" "eventbridge_logs_attachment" {
  role       = aws_iam_role.eventbridge_logs_role.name
  policy_arn = aws_iam_policy.eventbridge_logs_policy.arn
}

# =========================================
# IoT Greengrass Components
# =========================================

# Component: ONNX Runtime
resource "aws_greengrassv2_component_version" "onnx_runtime" {
  inline_recipe = jsonencode({
    RecipeFormatVersion = "2020-01-25"
    ComponentName       = "com.${replace(var.project_name, "-", ".")}.OnnxRuntime"
    ComponentVersion    = "1.0.0"
    ComponentDescription = "ONNX Runtime for edge inference"
    ComponentPublisher  = "EdgeAI"
    
    Manifests = [{
      Platform = {
        os = "linux"
      }
      Lifecycle = {
        Install = {
          Script  = "pip3 install onnxruntime==${var.onnx_runtime_version} numpy==1.24.0 opencv-python-headless==4.8.0"
          Timeout = 300
        }
      }
    }]
  })
  
  tags = merge(local.common_tags, {
    Name      = "com.${replace(var.project_name, "-", ".")}.OnnxRuntime"
    Purpose   = "ONNX Runtime Component"
    Component = "Greengrass"
  })
}

# Component: Model Deployment
resource "aws_greengrassv2_component_version" "model_component" {
  inline_recipe = jsonencode({
    RecipeFormatVersion = "2020-01-25"
    ComponentName       = "com.${replace(var.project_name, "-", ".")}.DefectDetectionModel"
    ComponentVersion    = "1.0.0"
    ComponentDescription = "Defect detection model for edge inference"
    ComponentPublisher  = "EdgeAI"
    
    ComponentConfiguration = {
      DefaultConfiguration = {
        ModelPath  = "/greengrass/v2/work/com.${replace(var.project_name, "-", ".")}.DefectDetectionModel"
        ModelS3Uri = "s3://${aws_s3_bucket.model_bucket.id}/models/v${var.model_version}/"
      }
    }
    
    Manifests = [{
      Platform = {
        os = "linux"
      }
      Artifacts = [
        {
          URI       = "s3://${aws_s3_bucket.model_bucket.id}/models/v${var.model_version}/model.onnx"
          Unarchive = "NONE"
        },
        {
          URI       = "s3://${aws_s3_bucket.id}/models/v${var.model_version}/config.json"
          Unarchive = "NONE"
        }
      ]
      Lifecycle = {}
    }]
  })
  
  depends_on = [
    aws_s3_object.sample_model,
    aws_s3_object.model_config
  ]
  
  tags = merge(local.common_tags, {
    Name      = "com.${replace(var.project_name, "-", ".")}.DefectDetectionModel"
    Purpose   = "Model Component"
    Component = "Greengrass"
  })
}

# Local file for inference application
resource "local_file" "inference_app" {
  filename = "${path.module}/inference_app.py"
  content = templatefile("${path.module}/templates/inference_app.py.tpl", {
    event_bus_name         = local.event_bus_name
    confidence_threshold   = var.confidence_threshold
    inference_interval     = var.inference_interval_seconds
    model_name            = var.model_name
    project_name          = var.project_name
  })
}

# Component: Inference Engine
resource "aws_greengrassv2_component_version" "inference_component" {
  inline_recipe = jsonencode({
    RecipeFormatVersion = "2020-01-25"
    ComponentName       = "com.${replace(var.project_name, "-", ".")}.InferenceEngine"
    ComponentVersion    = "1.0.0"
    ComponentDescription = "Real-time inference engine with EventBridge integration"
    ComponentPublisher  = "EdgeAI"
    
    ComponentDependencies = {
      "com.${replace(var.project_name, "-", ".")}.OnnxRuntime" = {
        VersionRequirement = ">=1.0.0 <2.0.0"
      }
      "com.${replace(var.project_name, "-", ".")}.DefectDetectionModel" = {
        VersionRequirement = ">=1.0.0 <2.0.0"
      }
    }
    
    ComponentConfiguration = {
      DefaultConfiguration = {
        EventBusName         = local.event_bus_name
        InferenceInterval    = var.inference_interval_seconds
        ConfidenceThreshold  = var.confidence_threshold
      }
    }
    
    Manifests = [{
      Platform = {
        os = "linux"
      }
      Artifacts = [{
        URI       = "data:text/plain;base64,${base64encode(local_file.inference_app.content)}"
        Unarchive = "NONE"
      }]
      Lifecycle = {
        Run = {
          Script            = "python3 {artifacts:path}/inference_app.py"
          RequiresPrivilege = false
        }
      }
    }]
  })
  
  depends_on = [
    aws_greengrassv2_component_version.onnx_runtime,
    aws_greengrassv2_component_version.model_component,
    local_file.inference_app
  ]
  
  tags = merge(local.common_tags, {
    Name      = "com.${replace(var.project_name, "-", ".")}.InferenceEngine"
    Purpose   = "Inference Component"
    Component = "Greengrass"
  })
}

# Wait for components to be available
resource "time_sleep" "wait_for_components" {
  depends_on = [
    aws_greengrassv2_component_version.onnx_runtime,
    aws_greengrassv2_component_version.model_component,
    aws_greengrassv2_component_version.inference_component
  ]
  
  create_duration = "30s"
}

# =========================================
# Deployment Configuration
# =========================================

# Create deployment for edge device
resource "aws_greengrassv2_deployment" "edge_deployment" {
  deployment_name = "${local.name_prefix}-EdgeAIInferenceDeployment"
  target_arn      = aws_iot_thing.greengrass_core.arn
  
  deployment_policies {
    failure_handling_policy = "ROLLBACK"
    
    component_update_policy {
      timeout_in_seconds = 60
      action            = "NOTIFY_COMPONENTS"
    }
  }
  
  # Component configuration
  component {
    component_name    = aws_greengrassv2_component_version.onnx_runtime.component_name
    component_version = aws_greengrassv2_component_version.onnx_runtime.component_version
  }
  
  component {
    component_name    = aws_greengrassv2_component_version.model_component.component_name
    component_version = aws_greengrassv2_component_version.model_component.component_version
  }
  
  component {
    component_name    = aws_greengrassv2_component_version.inference_component.component_name
    component_version = aws_greengrassv2_component_version.inference_component.component_version
    
    configuration_update {
      merge = jsonencode({
        EventBusName        = local.event_bus_name
        InferenceInterval   = var.inference_interval_seconds
        ConfidenceThreshold = var.confidence_threshold
      })
    }
  }
  
  # Include AWS Greengrass CLI component
  component {
    component_name    = "aws.greengrass.Cli"
    component_version = "2.12.0"
  }
  
  depends_on = [time_sleep.wait_for_components]
  
  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-EdgeAIInferenceDeployment"
    Purpose   = "Edge Deployment"
    Component = "Greengrass"
  })
}

# =========================================
# Optional: CloudTrail for API logging
# =========================================

resource "aws_cloudtrail" "api_logging" {
  count                         = var.enable_cloudtrail_logging ? 1 : 0
  name                          = "${local.name_prefix}-api-trail"
  s3_bucket_name               = aws_s3_bucket.model_bucket.id
  s3_key_prefix               = "cloudtrail-logs/"
  include_global_service_events = false
  
  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    
    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.model_bucket.arn}/*"]
    }
    
    data_resource {
      type   = "AWS::IoT::Thing"
      values = [aws_iot_thing.greengrass_core.arn]
    }
  }
  
  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-api-trail"
    Purpose   = "API Logging"
    Component = "CloudTrail"
  })
}