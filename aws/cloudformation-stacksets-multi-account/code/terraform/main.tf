# Generate random suffix for unique naming
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get organization information
data "aws_organizations_organization" "current" {
  count = var.organization_id == "" ? 1 : 0
}

# Get organizational units if specified
data "aws_organizations_organizational_units" "current" {
  count     = length(var.target_organizational_units) > 0 ? 1 : 0
  parent_id = data.aws_organizations_organization.current[0].roots[0].id
}

# Local values for computed configurations
locals {
  # Compute organization ID
  organization_id = var.organization_id != "" ? var.organization_id : (
    length(data.aws_organizations_organization.current) > 0 ? 
    data.aws_organizations_organization.current[0].id : ""
  )

  # Compute unique resource names
  stackset_name = "${var.stackset_name_prefix}-${random_string.suffix.result}"
  execution_role_stackset_name = "execution-roles-${random_string.suffix.result}"
  template_bucket_name = "${var.project_name}-templates-${random_string.suffix.result}"
  
  # Compute target accounts (use provided or discover from organization)
  target_accounts = length(var.target_accounts) > 0 ? var.target_accounts : []
  
  # Compute target organizational units
  target_ou_ids = length(var.target_organizational_units) > 0 ? var.target_organizational_units : []

  # Common tags
  common_tags = merge(var.additional_tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "Organization-Wide-Governance"
  })
}

# Enable trusted access for CloudFormation StackSets in AWS Organizations
resource "aws_organizations_delegated_administrator" "stacksets" {
  count          = local.organization_id != "" ? 1 : 0
  account_id     = data.aws_caller_identity.current.account_id
  service_principal = "stacksets.cloudformation.amazonaws.com"
}

# S3 bucket for storing CloudFormation templates
resource "aws_s3_bucket" "templates" {
  bucket = local.template_bucket_name

  tags = merge(local.common_tags, {
    Purpose = "StackSet-Templates"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "templates" {
  bucket = aws_s3_bucket.templates.id
  versioning_configuration {
    status = var.s3_bucket_configuration.versioning_enabled ? "Enabled" : "Disabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "templates" {
  bucket = aws_s3_bucket.templates.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.s3_bucket_configuration.encryption_algorithm
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "templates" {
  bucket = aws_s3_bucket.templates.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "templates" {
  count  = var.s3_bucket_configuration.lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.templates.id

  rule {
    id     = "template_lifecycle"
    status = "Enabled"

    expiration {
      days = var.s3_bucket_configuration.log_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.s3_bucket_configuration.noncurrent_version_expiration_days
    }

    transition {
      days          = var.s3_bucket_configuration.transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_bucket_configuration.transition_to_glacier_days
      storage_class = "GLACIER"
    }
  }
}

# IAM role for StackSet administrator
resource "aws_iam_role" "stackset_administrator" {
  name = "AWSCloudFormationStackSetAdministrator"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudformation.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Purpose = "StackSet-Administrator"
  })
}

# IAM policy for StackSet administrator
resource "aws_iam_policy" "stackset_administrator" {
  name        = "AWSCloudFormationStackSetAdministratorPolicy"
  description = "Policy for CloudFormation StackSet Administrator"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = [
          "arn:aws:iam::*:role/AWSCloudFormationStackSetExecutionRole"
        ]
      }
    ]
  })

  tags = merge(local.common_tags, {
    Purpose = "StackSet-Administrator"
  })
}

# Attach policy to StackSet administrator role
resource "aws_iam_role_policy_attachment" "stackset_administrator" {
  role       = aws_iam_role.stackset_administrator.name
  policy_arn = aws_iam_policy.stackset_administrator.arn
}

# CloudFormation template for execution role in target accounts
resource "aws_s3_object" "execution_role_template" {
  bucket = aws_s3_bucket.templates.id
  key    = "stackset-execution-role-template.yaml"
  content = templatefile("${path.module}/templates/execution-role-template.yaml", {
    administrator_account_id = data.aws_caller_identity.current.account_id
  })
  content_type = "application/x-yaml"

  tags = merge(local.common_tags, {
    Purpose = "Execution-Role-Template"
  })
}

# CloudFormation template for governance policies
resource "aws_s3_object" "governance_template" {
  bucket = aws_s3_bucket.templates.id
  key    = "governance-template.yaml"
  content = templatefile("${path.module}/templates/governance-template.yaml", {
    compliance_level = var.compliance_level
    password_policy  = var.password_policy
    cloudtrail_config = var.cloudtrail_config
    s3_config        = var.s3_bucket_configuration
    guardduty_config = var.guardduty_config
    config_configuration = var.config_configuration
  })
  content_type = "application/x-yaml"

  tags = merge(local.common_tags, {
    Purpose = "Governance-Template"
  })
}

# StackSet for execution roles
resource "aws_cloudformation_stack_set" "execution_roles" {
  name         = local.execution_role_stackset_name
  description  = "Deploy StackSet execution roles to target accounts"
  capabilities = ["CAPABILITY_NAMED_IAM"]

  template_url = "https://${aws_s3_bucket.templates.bucket}.s3.${data.aws_region.current.name}.amazonaws.com/${aws_s3_object.execution_role_template.key}"

  parameters = {
    AdministratorAccountId = data.aws_caller_identity.current.account_id
  }

  permission_model = "SELF_MANAGED"

  tags = merge(local.common_tags, {
    Purpose = "Execution-Roles"
  })

  depends_on = [
    aws_iam_role_policy_attachment.stackset_administrator,
    aws_s3_object.execution_role_template
  ]
}

# Deploy execution roles to target accounts
resource "aws_cloudformation_stack_instances" "execution_roles" {
  count = length(local.target_accounts) > 0 ? 1 : 0

  stack_set_name = aws_cloudformation_stack_set.execution_roles.name
  accounts       = local.target_accounts
  regions        = [data.aws_region.current.name]

  operation_preferences {
    region_concurrency_type      = var.operation_preferences.region_concurrency_type
    max_concurrent_percentage    = var.operation_preferences.max_concurrent_percentage
    failure_tolerance_percentage = var.operation_preferences.failure_tolerance_percentage
  }

  depends_on = [aws_cloudformation_stack_set.execution_roles]
}

# Main governance StackSet
resource "aws_cloudformation_stack_set" "governance" {
  name         = local.stackset_name
  description  = "Organization-wide governance and security policies"
  capabilities = ["CAPABILITY_IAM"]

  template_url = "https://${aws_s3_bucket.templates.bucket}.s3.${data.aws_region.current.name}.amazonaws.com/${aws_s3_object.governance_template.key}"

  parameters = {
    Environment      = var.environment
    OrganizationId   = local.organization_id
    ComplianceLevel  = var.compliance_level
  }

  permission_model = "SERVICE_MANAGED"

  auto_deployment {
    enabled                          = var.enable_auto_deployment
    retain_stacks_on_account_removal = var.retain_stacks_on_account_removal
  }

  operation_preferences {
    region_concurrency_type      = var.operation_preferences.region_concurrency_type
    max_concurrent_percentage    = var.operation_preferences.max_concurrent_percentage
    failure_tolerance_percentage = var.operation_preferences.failure_tolerance_percentage
  }

  tags = merge(local.common_tags, {
    Purpose = "Governance-Policies"
  })

  depends_on = [
    aws_cloudformation_stack_instances.execution_roles,
    aws_s3_object.governance_template,
    aws_organizations_delegated_administrator.stacksets
  ]
}

# Deploy governance StackSet to organizational units
resource "aws_cloudformation_stack_instances" "governance_ou" {
  count = length(local.target_ou_ids) > 0 ? 1 : 0

  stack_set_name = aws_cloudformation_stack_set.governance.name
  regions        = var.target_regions

  deployment_targets {
    organizational_unit_ids = local.target_ou_ids
  }

  operation_preferences {
    region_concurrency_type      = var.operation_preferences.region_concurrency_type
    max_concurrent_percentage    = var.operation_preferences.max_concurrent_percentage
    failure_tolerance_percentage = var.operation_preferences.failure_tolerance_percentage
  }

  depends_on = [aws_cloudformation_stack_set.governance]
}

# Deploy governance StackSet to specific accounts (if no OUs specified)
resource "aws_cloudformation_stack_instances" "governance_accounts" {
  count = length(local.target_accounts) > 0 && length(local.target_ou_ids) == 0 ? 1 : 0

  stack_set_name = aws_cloudformation_stack_set.governance.name
  accounts       = local.target_accounts
  regions        = var.target_regions

  operation_preferences {
    region_concurrency_type      = var.operation_preferences.region_concurrency_type
    max_concurrent_percentage    = var.operation_preferences.max_concurrent_percentage
    failure_tolerance_percentage = var.operation_preferences.failure_tolerance_percentage
  }

  depends_on = [aws_cloudformation_stack_set.governance]
}

# SNS topic for StackSet alerts
resource "aws_sns_topic" "stackset_alerts" {
  count = var.enable_monitoring ? 1 : 0
  name  = "StackSetAlerts-${random_string.suffix.result}"

  tags = merge(local.common_tags, {
    Purpose = "StackSet-Alerts"
  })
}

# SNS topic subscription for email alerts
resource "aws_sns_topic_subscription" "stackset_alerts_email" {
  count     = var.enable_monitoring && var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.stackset_alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# CloudWatch log group for StackSet operations
resource "aws_cloudwatch_log_group" "stackset_operations" {
  count             = var.enable_monitoring ? 1 : 0
  name              = "/aws/cloudformation/stackset-operations"
  retention_in_days = var.lambda_config.log_retention

  tags = merge(local.common_tags, {
    Purpose = "StackSet-Operations"
  })
}

# CloudWatch alarm for failed StackSet operations
resource "aws_cloudwatch_metric_alarm" "stackset_operation_failure" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "StackSetOperationFailure-${local.stackset_name}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "StackSetOperationFailureCount"
  namespace           = "AWS/CloudFormation"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alert when StackSet operations fail"
  alarm_actions       = [aws_sns_topic.stackset_alerts[0].arn]

  dimensions = {
    StackSetName = local.stackset_name
  }

  tags = merge(local.common_tags, {
    Purpose = "StackSet-Monitoring"
  })
}

# Lambda function for drift detection
resource "aws_lambda_function" "drift_detection" {
  count = var.enable_monitoring ? 1 : 0

  filename         = data.archive_file.drift_detection_lambda[0].output_path
  function_name    = "stackset-drift-detection-${random_string.suffix.result}"
  role            = aws_iam_role.drift_detection_lambda[0].arn
  handler         = "drift_detection.lambda_handler"
  runtime         = var.lambda_config.runtime
  timeout         = var.lambda_config.timeout
  memory_size     = var.lambda_config.memory_size
  source_code_hash = data.archive_file.drift_detection_lambda[0].output_base64sha256

  environment {
    variables = {
      STACKSET_NAME    = local.stackset_name
      SNS_TOPIC_ARN    = aws_sns_topic.stackset_alerts[0].arn
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "Drift-Detection"
  })
}

# Lambda function source code
data "archive_file" "drift_detection_lambda" {
  count = var.enable_monitoring ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/drift_detection_lambda.zip"
  source {
    content = templatefile("${path.module}/lambda/drift_detection.py", {
      stackset_name = local.stackset_name
    })
    filename = "drift_detection.py"
  }
}

# IAM role for Lambda function
resource "aws_iam_role" "drift_detection_lambda" {
  count = var.enable_monitoring ? 1 : 0
  name  = "StackSetDriftDetectionRole-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Purpose = "Drift-Detection-Lambda"
  })
}

# IAM policy for Lambda function
resource "aws_iam_policy" "drift_detection_lambda" {
  count = var.enable_monitoring ? 1 : 0
  name  = "StackSetDriftDetectionPolicy-${random_string.suffix.result}"

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
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudformation:DetectStackSetDrift",
          "cloudformation:DescribeStackSetOperation",
          "cloudformation:ListStackInstances",
          "cloudformation:DescribeStackInstance"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.stackset_alerts[0].arn
      }
    ]
  })

  tags = merge(local.common_tags, {
    Purpose = "Drift-Detection-Lambda"
  })
}

# Attach policy to Lambda role
resource "aws_iam_role_policy_attachment" "drift_detection_lambda" {
  count      = var.enable_monitoring ? 1 : 0
  role       = aws_iam_role.drift_detection_lambda[0].name
  policy_arn = aws_iam_policy.drift_detection_lambda[0].arn
}

# CloudWatch log group for Lambda
resource "aws_cloudwatch_log_group" "drift_detection_lambda" {
  count             = var.enable_monitoring ? 1 : 0
  name              = "/aws/lambda/stackset-drift-detection-${random_string.suffix.result}"
  retention_in_days = var.lambda_config.log_retention

  tags = merge(local.common_tags, {
    Purpose = "Drift-Detection-Lambda"
  })
}

# CloudWatch Event rule for scheduled drift detection
resource "aws_cloudwatch_event_rule" "drift_detection_schedule" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "stackset-drift-detection-schedule-${random_string.suffix.result}"
  description         = "Schedule for automated StackSet drift detection"
  schedule_expression = var.drift_detection_schedule

  tags = merge(local.common_tags, {
    Purpose = "Drift-Detection-Schedule"
  })
}

# CloudWatch Event target for Lambda
resource "aws_cloudwatch_event_target" "drift_detection_lambda" {
  count = var.enable_monitoring ? 1 : 0
  rule  = aws_cloudwatch_event_rule.drift_detection_schedule[0].name
  arn   = aws_lambda_function.drift_detection[0].arn

  input = jsonencode({
    stackset_name   = local.stackset_name
    sns_topic_arn   = aws_sns_topic.stackset_alerts[0].arn
  })
}

# Lambda permission for CloudWatch Events
resource "aws_lambda_permission" "drift_detection_schedule" {
  count         = var.enable_monitoring ? 1 : 0
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.drift_detection[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.drift_detection_schedule[0].arn
}

# CloudWatch dashboard for StackSet monitoring
resource "aws_cloudwatch_dashboard" "stackset_monitoring" {
  count          = var.enable_monitoring ? 1 : 0
  dashboard_name = "StackSet-Monitoring-${random_string.suffix.result}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/CloudFormation", "StackSetOperationSuccessCount", "StackSetName", local.stackset_name],
            [".", "StackSetOperationFailureCount", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "StackSet Operation Results"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          query = "SOURCE '/aws/cloudformation/stackset-operations'\n| fields @timestamp, stackSetName, operationType, operationStatus\n| filter stackSetName like /${local.stackset_name}/\n| sort @timestamp desc\n| limit 20"
          region = data.aws_region.current.name
          title  = "Recent StackSet Operations"
        }
      }
    ]
  })
}

# Create template files in the templates directory
resource "local_file" "execution_role_template" {
  content = templatefile("${path.module}/templates/execution-role-template.yaml.tpl", {
    administrator_account_id = data.aws_caller_identity.current.account_id
  })
  filename = "${path.module}/templates/execution-role-template.yaml"
}

resource "local_file" "governance_template" {
  content = templatefile("${path.module}/templates/governance-template.yaml.tpl", {
    compliance_level = var.compliance_level
    password_policy  = var.password_policy
    cloudtrail_config = var.cloudtrail_config
    s3_config        = var.s3_bucket_configuration
    guardduty_config = var.guardduty_config
    config_configuration = var.config_configuration
  })
  filename = "${path.module}/templates/governance-template.yaml"
}

resource "local_file" "drift_detection_lambda" {
  count = var.enable_monitoring ? 1 : 0
  content = templatefile("${path.module}/lambda/drift_detection.py.tpl", {
    stackset_name = local.stackset_name
  })
  filename = "${path.module}/lambda/drift_detection.py"
}