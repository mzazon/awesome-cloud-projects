# Data sources for AWS account information
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for resource naming and configuration
locals {
  account_id          = var.aws_account_id != "" ? var.aws_account_id : data.aws_caller_identity.current.account_id
  region              = var.aws_region
  random_suffix       = random_id.suffix.hex
  
  # Resource names with fallback to auto-generated names
  thing_group_name    = var.thing_group_name != "" ? var.thing_group_name : "${var.resource_prefix}-devices-${local.random_suffix}"
  iot_policy_name     = var.iot_policy_name != "" ? var.iot_policy_name : "${var.resource_prefix}-policy-${local.random_suffix}"
  s3_bucket_name      = var.s3_bucket_name != "" ? var.s3_bucket_name : "${var.resource_prefix}-firmware-${local.random_suffix}"
  
  # Merged tags
  common_tags = merge(var.default_tags, var.additional_tags, {
    Environment = var.environment
  })
}

# ==============================================================================
# S3 BUCKET FOR FIRMWARE STORAGE
# ==============================================================================

# S3 bucket for storing firmware update packages
resource "aws_s3_bucket" "firmware_bucket" {
  bucket = local.s3_bucket_name
  tags   = local.common_tags
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "firmware_bucket_versioning" {
  bucket = aws_s3_bucket.firmware_bucket.id
  versioning_configuration {
    status = var.s3_bucket_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "firmware_bucket_encryption" {
  count  = var.s3_bucket_encryption ? 1 : 0
  bucket = aws_s3_bucket.firmware_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block (security best practice)
resource "aws_s3_bucket_public_access_block" "firmware_bucket_pab" {
  bucket = aws_s3_bucket.firmware_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload sample firmware file
resource "aws_s3_object" "firmware_file" {
  bucket  = aws_s3_bucket.firmware_bucket.id
  key     = "firmware/firmware-${var.firmware_version}.bin"
  content = var.firmware_content
  
  content_type = "application/octet-stream"
  
  tags = merge(local.common_tags, {
    FirmwareVersion = var.firmware_version
  })
}

# ==============================================================================
# IOT POLICY FOR DEVICE FLEET ACCESS
# ==============================================================================

# IoT policy document for device fleet management
data "aws_iam_policy_document" "iot_device_policy" {
  statement {
    sid    = "AllowDeviceConnection"
    effect = "Allow"
    actions = [
      "iot:Connect"
    ]
    resources = [
      "arn:aws:iot:${local.region}:${local.account_id}:client/$${iot:Connection.Thing.ThingName}"
    ]
  }

  statement {
    sid    = "AllowJobOperations"
    effect = "Allow"
    actions = [
      "iot:Publish",
      "iot:Subscribe",
      "iot:Receive"
    ]
    resources = [
      "arn:aws:iot:${local.region}:${local.account_id}:topic/$$aws/things/$${iot:Connection.Thing.ThingName}/jobs/*",
      "arn:aws:iot:${local.region}:${local.account_id}:topicfilter/$$aws/things/$${iot:Connection.Thing.ThingName}/jobs/*"
    ]
  }
}

# Create IoT policy for device fleet
resource "aws_iot_policy" "device_policy" {
  name   = local.iot_policy_name
  policy = data.aws_iam_policy_document.iot_device_policy.json
  
  tags = local.common_tags
}

# ==============================================================================
# IOT THING GROUP FOR FLEET ORGANIZATION
# ==============================================================================

# Create IoT Thing Group for fleet organization
resource "aws_iot_thing_group" "device_fleet" {
  name = local.thing_group_name
  
  properties {
    description = "Production IoT devices for OTA updates - managed by Terraform"
    
    attribute_payload {
      attributes = {
        environment         = var.environment
        updatePolicy       = "automatic"
        firmwareVersion    = var.initial_firmware_version
        managedBy          = "terraform"
        lastFleetUpdate    = timestamp()
      }
    }
  }
  
  tags = local.common_tags
}

# ==============================================================================
# IOT DEVICES (THINGS) REGISTRATION
# ==============================================================================

# Create IoT Things (devices) for the fleet
resource "aws_iot_thing" "devices" {
  count = var.device_count
  name  = "${var.resource_prefix}-device-${local.random_suffix}-${count.index + 1}"
  
  attributes = {
    deviceType       = var.device_type
    firmwareVersion  = var.initial_firmware_version
    location         = "${var.device_location_prefix}-${count.index + 1}"
    deviceIndex      = tostring(count.index + 1)
    managedBy        = "terraform"
  }
  
  tags = merge(local.common_tags, {
    DeviceIndex = tostring(count.index + 1)
  })
}

# Add devices to the thing group
resource "aws_iot_thing_group_membership" "device_membership" {
  count            = var.device_count
  thing_name       = aws_iot_thing.devices[count.index].name
  thing_group_name = aws_iot_thing_group.device_fleet.name
}

# ==============================================================================
# IOT CERTIFICATES FOR DEVICE AUTHENTICATION
# ==============================================================================

# Create certificates for device authentication
resource "aws_iot_certificate" "device_certificates" {
  count  = var.device_count
  active = true
  
  tags = merge(local.common_tags, {
    DeviceIndex = tostring(count.index + 1)
    DeviceName  = aws_iot_thing.devices[count.index].name
  })
}

# Attach IoT policy to certificates
resource "aws_iot_policy_attachment" "device_policy_attachment" {
  count  = var.device_count
  policy = aws_iot_policy.device_policy.name
  target = aws_iot_certificate.device_certificates[count.index].arn
}

# Attach certificates to things
resource "aws_iot_thing_principal_attachment" "device_certificate_attachment" {
  count     = var.device_count
  thing     = aws_iot_thing.devices[count.index].name
  principal = aws_iot_certificate.device_certificates[count.index].arn
}

# ==============================================================================
# CLOUDWATCH LOGS FOR MONITORING
# ==============================================================================

# CloudWatch Log Group for IoT operations
resource "aws_cloudwatch_log_group" "iot_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/iot/${var.resource_prefix}-${local.random_suffix}"
  retention_in_days = var.log_retention_days
  
  tags = local.common_tags
}

# ==============================================================================
# SAMPLE FIRMWARE UPDATE JOB DOCUMENT
# ==============================================================================

# Local file for job document template
locals {
  job_document = {
    operation     = "firmwareUpdate"
    firmwareVersion = var.firmware_version
    downloadUrl   = "https://${aws_s3_bucket.firmware_bucket.bucket_domain_name}/firmware/firmware-${var.firmware_version}.bin"
    checksumAlgorithm = "SHA256"
    checksum      = "placeholder-checksum-for-demo"
    installationSteps = [
      "Download firmware package from specified URL",
      "Validate package integrity using checksum",
      "Backup current firmware version",
      "Install new firmware version",
      "Restart device and validate functionality",
      "Report installation status to AWS IoT"
    ]
    rollbackInstructions = {
      enabled         = true
      maxAttempts     = 3
      fallbackVersion = var.initial_firmware_version
    }
    timeoutConfig = {
      inProgressTimeoutInMinutes = 30
      stepTimeoutInMinutes      = 10
    }
  }
}

# Store job document in S3 for reference
resource "aws_s3_object" "job_document" {
  bucket  = aws_s3_bucket.firmware_bucket.id
  key     = "job-documents/firmware-update-${var.firmware_version}.json"
  content = jsonencode(local.job_document)
  
  content_type = "application/json"
  
  tags = merge(local.common_tags, {
    DocumentType    = "job-document"
    FirmwareVersion = var.firmware_version
  })
}

# ==============================================================================
# IOT JOB FOR FIRMWARE UPDATE DEPLOYMENT
# ==============================================================================

# Create IoT Job for firmware update deployment
resource "aws_iot_job" "firmware_update" {
  job_id = "firmware-update-${var.firmware_version}-${local.random_suffix}"
  
  # Target the thing group for fleet-wide deployment
  targets = [aws_iot_thing_group.device_fleet.arn]
  
  # Job document with firmware update instructions
  document = jsonencode(local.job_document)
  
  description = "Deploy firmware version ${var.firmware_version} to production devices"
  
  # Job execution rollout configuration
  job_executions_rollout_config {
    maximum_per_minute = var.job_rollout_max_per_minute
    
    exponential_rate {
      base_rate_per_minute     = 5
      increment_factor         = 2
      rate_increase_criteria {
        number_of_notified_things  = 5
        number_of_succeeded_things = 3
      }
    }
  }
  
  # Abort configuration for failed deployments
  abort_config {
    criteria_list {
      failure_type                = "FAILED"
      action                     = "CANCEL"
      threshold_percentage       = var.job_abort_threshold_percentage
      min_number_of_executed_things = 3
    }
  }
  
  # Timeout configuration
  timeout_config {
    in_progress_timeout_in_minutes = var.job_timeout_minutes
  }
  
  tags = merge(local.common_tags, {
    JobType         = "firmware-update"
    FirmwareVersion = var.firmware_version
  })
  
  # Ensure dependencies are created first
  depends_on = [
    aws_iot_thing_group_membership.device_membership,
    aws_iot_policy_attachment.device_policy_attachment,
    aws_iot_thing_principal_attachment.device_certificate_attachment,
    aws_s3_object.firmware_file
  ]
}

# ==============================================================================
# OPTIONAL: IOT DEVICE CERTIFICATE AUTHORITY (for auto-registration)
# ==============================================================================

# CA certificate for device auto-registration (optional)
resource "aws_iot_ca_certificate" "device_ca" {
  count                         = var.enable_certificate_auto_registration ? 1 : 0
  active                        = true
  ca_certificate_pem            = var.certificate_ca_certificate_pem
  allow_auto_registration       = true
  auto_registration_status      = "ENABLE"
  
  tags = merge(local.common_tags, {
    Purpose = "device-auto-registration"
  })
}

# ==============================================================================
# OUTPUTS SECTION
# ==============================================================================

# Output important resource information for verification and integration