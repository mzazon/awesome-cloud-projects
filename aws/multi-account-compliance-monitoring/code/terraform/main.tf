# Cross-Account Compliance Monitoring with Systems Manager and Security Hub
# This Terraform configuration implements automated compliance monitoring across multiple AWS accounts

# Generate random values for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Generate external ID for cross-account role security
resource "random_password" "external_id" {
  length  = 32
  special = true
}

locals {
  # Use provided external ID or generate one
  external_id = var.external_id != "" ? var.external_id : random_password.external_id.result
  
  # Generate unique suffix for resources
  resource_suffix = lower(random_id.suffix.hex)
  
  # Common tags for all resources
  common_tags = {
    Project     = "CrossAccountCompliance"
    Environment = var.environment
    CreatedBy   = "Terraform"
    Recipe      = "implementing-cross-account-compliance-monitoring"
  }
  
  # Combine all member accounts
  all_member_accounts = concat([var.member_account_1, var.member_account_2], var.additional_member_accounts)
}

# Data source to get current AWS account information
data "aws_caller_identity" "current" {}

# Data source to get available AWS regions
data "aws_region" "current" {}

#
# SECURITY HUB CONFIGURATION
#

# Enable Security Hub in the administrator account
resource "aws_securityhub_account" "main" {
  enable_default_standards = true
  
  control_finding_generator = "SECURITY_CONTROL"
  auto_enable_controls      = true
}

# Enable organization administration for Security Hub
resource "aws_securityhub_organization_admin_account" "main" {
  admin_account_id = var.security_account_id
  
  depends_on = [aws_securityhub_account.main]
}

# Configure organization-wide Security Hub settings
resource "aws_securityhub_organization_configuration" "main" {
  auto_enable           = true
  auto_enable_standards = "DEFAULT"
  
  organization_configuration {
    configuration_type = "CENTRAL"
  }
  
  depends_on = [aws_securityhub_organization_admin_account.main]
}

# Create Security Hub member accounts
resource "aws_securityhub_member" "members" {
  for_each = toset(local.all_member_accounts)
  
  account_id = each.value
  email      = "security-${each.value}@example.com" # Replace with actual email addresses
  invite     = true
  
  depends_on = [aws_securityhub_account.main]
}

# Enable Systems Manager integration with Security Hub
resource "aws_securityhub_product_subscription" "systems_manager" {
  product_arn = "arn:aws:securityhub:${data.aws_region.current.name}::product/aws/systems-manager"
  
  depends_on = [aws_securityhub_account.main]
}

#
# KMS KEY FOR ENCRYPTION (Optional)
#

# KMS key for encrypting compliance data
resource "aws_kms_key" "compliance" {
  count = var.enable_kms_encryption ? 1 : 0
  
  description             = "KMS key for compliance monitoring encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudTrail to encrypt logs"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = [
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "compliance-monitoring-key-${local.resource_suffix}"
  })
}

# KMS key alias
resource "aws_kms_alias" "compliance" {
  count = var.enable_kms_encryption ? 1 : 0
  
  name          = "alias/compliance-monitoring-${local.resource_suffix}"
  target_key_id = aws_kms_key.compliance[0].key_id
}

#
# CLOUDTRAIL CONFIGURATION
#

# S3 bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0
  
  bucket        = "${var.s3_bucket_prefix}-${local.resource_suffix}-${data.aws_region.current.name}"
  force_destroy = true
  
  tags = merge(local.common_tags, {
    Name = "compliance-audit-trail-${local.resource_suffix}"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0
  
  bucket = aws_s3_bucket.cloudtrail[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0
  
  bucket = aws_s3_bucket.cloudtrail[0].id
  
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.compliance[0].arn : null
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
    }
    bucket_key_enabled = var.enable_kms_encryption
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0
  
  bucket = aws_s3_bucket.cloudtrail[0].id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket policy for CloudTrail
resource "aws_s3_bucket_policy" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0
  
  bucket = aws_s3_bucket.cloudtrail[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail[0].arn
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/compliance-audit-trail-${local.resource_suffix}"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/compliance-audit-trail-${local.resource_suffix}"
          }
        }
      }
    ]
  })
  
  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]
}

# CloudWatch Log Group for CloudTrail
resource "aws_cloudwatch_log_group" "cloudtrail" {
  count = var.enable_cloudtrail ? 1 : 0
  
  name              = "/aws/cloudtrail/compliance-audit-trail-${local.resource_suffix}"
  retention_in_days = var.cloudtrail_log_retention_days
  kms_key_id        = var.enable_kms_encryption ? aws_kms_key.compliance[0].arn : null
  
  tags = local.common_tags
}

# IAM role for CloudTrail CloudWatch Logs
resource "aws_iam_role" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0
  
  name = "CloudTrailLogsRole-${local.resource_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# IAM policy for CloudTrail CloudWatch Logs
resource "aws_iam_role_policy" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0
  
  name = "CloudTrailLogsPolicy"
  role = aws_iam_role.cloudtrail_logs[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
          "logs:CreateLogStream"
        ]
        Resource = "${aws_cloudwatch_log_group.cloudtrail[0].arn}:*"
      }
    ]
  })
}

# CloudTrail
resource "aws_cloudtrail" "compliance" {
  count = var.enable_cloudtrail ? 1 : 0
  
  name           = "compliance-audit-trail-${local.resource_suffix}"
  s3_bucket_name = aws_s3_bucket.cloudtrail[0].bucket
  
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail[0].arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_logs[0].arn
  
  kms_key_id = var.enable_kms_encryption ? aws_kms_key.compliance[0].arn : null
  
  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    exclude_management_event_sources = []
    
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::*/"]
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "compliance-audit-trail-${local.resource_suffix}"
  })
  
  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

#
# CROSS-ACCOUNT IAM ROLES
#

# Cross-account role for compliance access (Security Account)
resource "aws_iam_role" "cross_account_compliance" {
  name = "SecurityHubComplianceRole-${local.resource_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = local.external_id
          }
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# IAM policy for cross-account compliance access
resource "aws_iam_role_policy" "cross_account_compliance" {
  name = "ComplianceAccessPolicy"
  role = aws_iam_role.cross_account_compliance.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:ListComplianceItems",
          "ssm:ListResourceComplianceSummaries",
          "ssm:GetComplianceSummary",
          "ssm:DescribeInstanceInformation",
          "ssm:DescribeInstanceAssociations",
          "ssm:ListAssociations",
          "ssm:DescribeAssociationExecutions",
          "securityhub:BatchImportFindings",
          "securityhub:BatchUpdateFindings",
          "securityhub:GetFindings"
        ]
        Resource = "*"
      }
    ]
  })
}

# Cross-account roles in member accounts
resource "aws_iam_role" "member_compliance_role_1" {
  provider = aws.member1
  
  name = "SecurityHubComplianceRole-${local.resource_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.security_account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = local.external_id
          }
        }
      }
    ]
  })
  
  tags = local.common_tags
}

resource "aws_iam_role_policy" "member_compliance_policy_1" {
  provider = aws.member1
  
  name = "ComplianceAccessPolicy"
  role = aws_iam_role.member_compliance_role_1.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:ListComplianceItems",
          "ssm:ListResourceComplianceSummaries",
          "ssm:GetComplianceSummary",
          "ssm:DescribeInstanceInformation",
          "ssm:DescribeInstanceAssociations",
          "securityhub:BatchImportFindings",
          "securityhub:BatchUpdateFindings"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "member_compliance_role_2" {
  provider = aws.member2
  
  name = "SecurityHubComplianceRole-${local.resource_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.security_account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = local.external_id
          }
        }
      }
    ]
  })
  
  tags = local.common_tags
}

resource "aws_iam_role_policy" "member_compliance_policy_2" {
  provider = aws.member2
  
  name = "ComplianceAccessPolicy"
  role = aws_iam_role.member_compliance_role_2.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:ListComplianceItems",
          "ssm:ListResourceComplianceSummaries",
          "ssm:GetComplianceSummary",
          "ssm:DescribeInstanceInformation",
          "ssm:DescribeInstanceAssociations",
          "securityhub:BatchImportFindings",
          "securityhub:BatchUpdateFindings"
        ]
        Resource = "*"
      }
    ]
  })
}

#
# SYSTEMS MANAGER CONFIGURATION
#

# Default patch baseline for Linux
resource "aws_ssm_patch_baseline" "linux" {
  count = contains(var.patch_baseline_operating_systems, "AMAZON_LINUX_2") ? 1 : 0
  
  name             = "ComplianceMonitoring-Linux-Baseline-${local.resource_suffix}"
  description      = "Default patch baseline for Linux systems compliance monitoring"
  operating_system = "AMAZON_LINUX_2"
  
  approval_rule {
    approve_after_days = 0
    
    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security", "Critical"]
    }
    
    patch_filter {
      key    = "SEVERITY"
      values = ["Critical", "Important"]
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "compliance-linux-baseline-${local.resource_suffix}"
  })
}

# Default patch baseline for Windows
resource "aws_ssm_patch_baseline" "windows" {
  count = contains(var.patch_baseline_operating_systems, "WINDOWS") ? 1 : 0
  
  name             = "ComplianceMonitoring-Windows-Baseline-${local.resource_suffix}"
  description      = "Default patch baseline for Windows systems compliance monitoring"
  operating_system = "WINDOWS"
  
  approval_rule {
    approve_after_days = 0
    
    patch_filter {
      key    = "CLASSIFICATION"
      values = ["SecurityUpdates", "CriticalUpdates", "Updates"]
    }
    
    patch_filter {
      key    = "SEVERITY"
      values = ["Critical", "Important"]
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "compliance-windows-baseline-${local.resource_suffix}"
  })
}

# Systems Manager association for patch compliance scanning
resource "aws_ssm_association" "patch_compliance" {
  name             = "AWS-RunPatchBaseline"
  association_name = "CompliancePatching-${local.resource_suffix}"
  
  schedule_expression = var.compliance_check_schedule
  
  targets {
    key    = "tag:Environment"
    values = [var.environment]
  }
  
  parameters = {
    Operation = "Scan"
  }
  
  compliance_severity = "HIGH"
  
  output_location {
    s3_bucket_name = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail[0].bucket : null
    s3_key_prefix  = "ssm-associations/"
  }
  
  tags = local.common_tags
  
  depends_on = [
    aws_ssm_patch_baseline.linux,
    aws_ssm_patch_baseline.windows
  ]
}

# Custom compliance document for organizational policies
resource "aws_ssm_document" "custom_compliance" {
  count = var.enable_custom_compliance ? 1 : 0
  
  name          = "CustomComplianceCheck-${local.resource_suffix}"
  document_type = "Command"
  document_format = "YAML"
  
  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Custom compliance check for organizational policies"
    parameters = {
      complianceType = {
        type        = "String"
        description = "Type of compliance check to perform"
        default     = "Custom:OrganizationalPolicy"
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "runComplianceCheck"
        inputs = {
          runCommand = [
            "#!/bin/bash",
            "# Custom compliance check implementation",
            "INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)",
            "COMPLIANCE_TYPE=\"Custom:OrganizationalPolicy\"",
            "COMPLIANCE_STATUS=\"COMPLIANT\"",
            "COMPLIANCE_DETAILS=\"\"",
            "",
            "# Check for required tags",
            join("", [for tag in var.required_tags : "TAG_VALUE=$(aws ec2 describe-tags --filters \"Name=resource-id,Values=$${INSTANCE_ID}\" \"Name=key,Values=${tag}\" --query \"Tags[0].Value\" --output text)\nif [ \"$TAG_VALUE\" = \"None\" ]; then\n  COMPLIANCE_STATUS=\"NON_COMPLIANT\"\n  COMPLIANCE_DETAILS=\"$${COMPLIANCE_DETAILS}Missing required tag: ${tag}; \"\nfi\n"]),
            "",
            "# Report compliance status to Systems Manager",
            "aws ssm put-compliance-items \\",
            "  --resource-id $${INSTANCE_ID} \\",
            "  --resource-type \"ManagedInstance\" \\",
            "  --compliance-type $${COMPLIANCE_TYPE} \\",
            "  --execution-summary \"ExecutionTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)\" \\",
            "  --items \"Id=TagCompliance,Title=Required Tags Check,Severity=HIGH,Status=$${COMPLIANCE_STATUS},Details={\\\"Details\\\":\\\"$${COMPLIANCE_DETAILS}\\\"}\"",
            "",
            "echo \"Custom compliance check completed: $${COMPLIANCE_STATUS}\""
          ]
        }
      }
    ]
  })
  
  tags = local.common_tags
}

#
# LAMBDA FUNCTION FOR COMPLIANCE PROCESSING
#

# Lambda execution role
resource "aws_iam_role" "lambda_compliance_processor" {
  name = "ComplianceProcessingRole-${local.resource_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Lambda execution policy
resource "aws_iam_role_policy" "lambda_compliance_processor" {
  name = "ComplianceProcessingPolicy"
  role = aws_iam_role.lambda_compliance_processor.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = [
          "arn:aws:iam::${var.member_account_1}:role/SecurityHubComplianceRole-${local.resource_suffix}",
          "arn:aws:iam::${var.member_account_2}:role/SecurityHubComplianceRole-${local.resource_suffix}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "securityhub:BatchImportFindings",
          "securityhub:BatchUpdateFindings",
          "securityhub:GetFindings",
          "ssm:ListComplianceItems",
          "ssm:GetComplianceSummary"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda function code archive
data "archive_file" "compliance_processor" {
  type        = "zip"
  output_path = "${path.module}/compliance_processor.zip"
  
  source {
    content = templatefile("${path.module}/compliance_processor.py", {
      external_id         = local.external_id
      security_account_id = var.security_account_id
      member_accounts     = jsonencode(local.all_member_accounts)
      aws_region         = data.aws_region.current.name
    })
    filename = "compliance_processor.py"
  }
}

# Lambda function
resource "aws_lambda_function" "compliance_processor" {
  filename         = data.archive_file.compliance_processor.output_path
  function_name    = "ComplianceAutomation-${local.resource_suffix}"
  role            = aws_iam_role.lambda_compliance_processor.arn
  handler         = "compliance_processor.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  source_code_hash = data.archive_file.compliance_processor.output_base64sha256
  
  description = "Automated compliance processing for Security Hub"
  
  environment {
    variables = {
      EXTERNAL_ID         = local.external_id
      SECURITY_ACCOUNT_ID = var.security_account_id
      MEMBER_ACCOUNTS     = jsonencode(local.all_member_accounts)
      AWS_REGION         = data.aws_region.current.name
    }
  }
  
  kms_key_arn = var.enable_kms_encryption ? aws_kms_key.compliance[0].arn : null
  
  tags = merge(local.common_tags, {
    Name = "compliance-processor-${local.resource_suffix}"
  })
  
  depends_on = [
    aws_iam_role_policy.lambda_compliance_processor,
    aws_cloudwatch_log_group.lambda_compliance_processor
  ]
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_compliance_processor" {
  name              = "/aws/lambda/ComplianceAutomation-${local.resource_suffix}"
  retention_in_days = 14
  kms_key_id        = var.enable_kms_encryption ? aws_kms_key.compliance[0].arn : null
  
  tags = local.common_tags
}

#
# EVENTBRIDGE CONFIGURATION
#

# EventBridge rule for Systems Manager compliance events
resource "aws_cloudwatch_event_rule" "compliance_monitoring" {
  name        = "ComplianceMonitoringRule-${local.resource_suffix}"
  description = "Trigger compliance processing on SSM compliance changes"
  
  event_pattern = jsonencode({
    source      = ["aws.ssm"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["PutComplianceItems", "DeleteComplianceItems"]
    }
  })
  
  state = "ENABLED"
  
  tags = local.common_tags
}

# EventBridge target for Lambda
resource "aws_cloudwatch_event_target" "lambda_compliance" {
  rule      = aws_cloudwatch_event_rule.compliance_monitoring.name
  target_id = "ComplianceLambdaTarget"
  arn       = aws_lambda_function.compliance_processor.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "eventbridge_compliance" {
  statement_id  = "ComplianceEventBridgePermission"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.compliance_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.compliance_monitoring.arn
}

# EventBridge rule for Security Hub findings
resource "aws_cloudwatch_event_rule" "security_hub_findings" {
  name        = "SecurityHubFindingsRule-${local.resource_suffix}"
  description = "Process Security Hub compliance findings"
  
  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        ProductArn = [{
          prefix = "arn:aws:securityhub"
        }]
        Compliance = {
          Status = ["FAILED"]
        }
      }
    }
  })
  
  state = "ENABLED"
  
  tags = local.common_tags
}

# EventBridge target for Security Hub findings
resource "aws_cloudwatch_event_target" "security_hub_findings" {
  rule      = aws_cloudwatch_event_rule.security_hub_findings.name
  target_id = "SecurityHubFindingsTarget"
  arn       = aws_lambda_function.compliance_processor.arn
}

# Lambda permission for Security Hub EventBridge
resource "aws_lambda_permission" "eventbridge_security_hub" {
  statement_id  = "SecurityHubEventBridgePermission"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.compliance_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.security_hub_findings.arn
}

#
# SNS TOPIC FOR NOTIFICATIONS (Optional)
#

# SNS topic for compliance violations
resource "aws_sns_topic" "compliance_violations" {
  count = var.notification_email != "" ? 1 : 0
  
  name              = "compliance-violations-${local.resource_suffix}"
  display_name      = "Compliance Violations"
  kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.compliance[0].arn : null
  
  tags = local.common_tags
}

# SNS topic subscription
resource "aws_sns_topic_subscription" "compliance_email" {
  count = var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.compliance_violations[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# SNS topic policy
resource "aws_sns_topic_policy" "compliance_violations" {
  count = var.notification_email != "" ? 1 : 0
  
  arn = aws_sns_topic.compliance_violations[0].arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sns:Publish"
        Resource = aws_sns_topic.compliance_violations[0].arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Write Lambda function source code
resource "local_file" "compliance_processor_py" {
  content = <<-EOT
import json
import boto3
import uuid
import os
from datetime import datetime
from typing import Dict, List, Any

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process Systems Manager compliance events and create Security Hub findings
    """
    
    # Initialize AWS clients
    sts = boto3.client('sts')
    securityhub = boto3.client('securityhub')
    
    # Get environment variables
    external_id = os.environ.get('EXTERNAL_ID')
    security_account_id = os.environ.get('SECURITY_ACCOUNT_ID')
    member_accounts = json.loads(os.environ.get('MEMBER_ACCOUNTS', '[]'))
    aws_region = os.environ.get('AWS_REGION')
    
    print(f"Processing event: {json.dumps(event, default=str)}")
    
    # Parse the EventBridge event
    detail = event.get('detail', {})
    account_id = event.get('account')
    region = event.get('region', aws_region)
    
    findings = []
    
    try:
        # Process compliance change event
        if detail.get('eventName') in ['PutComplianceItems', 'DeleteComplianceItems']:
            print(f"Processing compliance event for account {account_id}")
            
            # Assume role in member account to get detailed compliance data
            compliance_data = get_compliance_data(sts, account_id, external_id)
            
            # Create Security Hub findings based on compliance data
            for item in compliance_data:
                finding = create_security_hub_finding(
                    item, account_id, region, aws_region
                )
                if finding:
                    findings.append(finding)
        
        # Process Security Hub findings events
        elif event.get('source') == 'aws.securityhub':
            print("Processing Security Hub findings event")
            
            # Extract findings from event
            event_findings = detail.get('findings', [])
            
            for finding_data in event_findings:
                if finding_data.get('Compliance', {}).get('Status') == 'FAILED':
                    # Process failed compliance findings
                    process_failed_compliance_finding(finding_data)
        
        # Import findings into Security Hub
        if findings:
            response = securityhub.batch_import_findings(Findings=findings)
            print(f"Imported {len(findings)} findings to Security Hub")
            print(f"Response: {response}")
            
            # Check for failures
            if response.get('FailedCount', 0) > 0:
                print(f"Failed to import {response['FailedCount']} findings")
                for failure in response.get('FailedFindings', []):
                    print(f"Failed finding: {failure}")
        
    except Exception as e:
        print(f"Error processing compliance event: {str(e)}")
        import traceback
        print(f"Traceback: {traceback.format_exc()}")
        raise
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Compliance event processed successfully',
            'findingsImported': len(findings)
        })
    }

def get_compliance_data(sts: Any, account_id: str, external_id: str) -> List[Dict[str, Any]]:
    """
    Assume role in member account and retrieve compliance data
    """
    
    try:
        # Assume role in member account
        role_arn = f"arn:aws:iam::{account_id}:role/SecurityHubComplianceRole-${local.resource_suffix}"
        
        response = sts.assume_role(
            RoleArn=role_arn,
            RoleSessionName='ComplianceDataRetrieval',
            ExternalId=external_id
        )
        
        # Create SSM client with assumed role credentials
        credentials = response['Credentials']
        ssm = boto3.client(
            'ssm',
            aws_access_key_id=credentials['AccessKeyId'],
            aws_secret_access_key=credentials['SecretAccessKey'],
            aws_session_token=credentials['SessionToken']
        )
        
        # Get compliance summary
        compliance_items = []
        
        # List compliance items
        paginator = ssm.get_paginator('list_compliance_items')
        
        for page in paginator.paginate():
            compliance_items.extend(page.get('ComplianceItems', []))
        
        return compliance_items
        
    except Exception as e:
        print(f"Error retrieving compliance data from account {account_id}: {str(e)}")
        return []

def create_security_hub_finding(
    compliance_item: Dict[str, Any], 
    account_id: str, 
    region: str, 
    aws_region: str
) -> Dict[str, Any]:
    """
    Create a Security Hub finding from compliance data
    """
    
    try:
        # Determine severity based on compliance status and type
        severity = 'MEDIUM'
        if compliance_item.get('Status') == 'NON_COMPLIANT':
            if 'CRITICAL' in str(compliance_item.get('Severity', '')).upper():
                severity = 'HIGH'
            elif 'HIGH' in str(compliance_item.get('Severity', '')).upper():
                severity = 'HIGH'
            else:
                severity = 'MEDIUM'
        elif compliance_item.get('Status') == 'COMPLIANT':
            severity = 'INFORMATIONAL'
        
        # Create finding
        finding = {
            'SchemaVersion': '2018-10-08',
            'Id': f"compliance-{account_id}-{compliance_item.get('Id', uuid.uuid4())}",
            'ProductArn': f"arn:aws:securityhub:{aws_region}::product/aws/systems-manager",
            'GeneratorId': 'ComplianceMonitoring',
            'AwsAccountId': account_id,
            'Types': ['Software and Configuration Checks/Vulnerabilities/CVE'],
            'CreatedAt': datetime.utcnow().isoformat() + 'Z',
            'UpdatedAt': datetime.utcnow().isoformat() + 'Z',
            'Severity': {
                'Label': severity
            },
            'Title': f"Systems Manager Compliance: {compliance_item.get('Title', 'Compliance Check')}",
            'Description': f"Compliance item {compliance_item.get('Id')} in account {account_id} has status: {compliance_item.get('Status')}",
            'Resources': [
                {
                    'Type': 'AwsAccount',
                    'Id': f"AWS::::Account:{account_id}",
                    'Region': region
                }
            ],
            'Compliance': {
                'Status': 'PASSED' if compliance_item.get('Status') == 'COMPLIANT' else 'FAILED'
            },
            'WorkflowState': 'NEW' if compliance_item.get('Status') != 'COMPLIANT' else 'RESOLVED'
        }
        
        # Add resource details if available
        if compliance_item.get('ResourceId'):
            finding['Resources'][0]['Id'] = compliance_item['ResourceId']
            finding['Resources'][0]['Type'] = compliance_item.get('ResourceType', 'Other')
        
        # Add additional details
        if compliance_item.get('Details'):
            finding['Description'] += f" Details: {compliance_item['Details']}"
        
        return finding
        
    except Exception as e:
        print(f"Error creating Security Hub finding: {str(e)}")
        return None

def process_failed_compliance_finding(finding_data: Dict[str, Any]) -> None:
    """
    Process a failed compliance finding for additional actions
    """
    
    try:
        print(f"Processing failed compliance finding: {finding_data.get('Id')}")
        
        # Here you could add additional processing logic such as:
        # - Triggering automated remediation
        # - Sending notifications
        # - Creating tickets in ITSM systems
        # - Escalating to security teams
        
        # For now, just log the finding
        print(f"Failed finding details: {json.dumps(finding_data, default=str, indent=2)}")
        
    except Exception as e:
        print(f"Error processing failed compliance finding: {str(e)}")
EOT
  
  filename = "${path.module}/compliance_processor.py"
}