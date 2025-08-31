# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  suffix            = random_id.suffix.hex
  account_id        = data.aws_caller_identity.current.account_id
  region            = data.aws_region.current.name
  config_bucket_name = "aws-config-bucket-${local.account_id}-${local.region}-${local.suffix}"
}

#######################
# S3 Bucket for AWS Config
#######################

resource "aws_s3_bucket" "config_bucket" {
  bucket        = local.config_bucket_name
  force_destroy = true

  tags = {
    Name        = "AWS Config Delivery Bucket"
    Purpose     = "Config service configuration history and snapshots"
    Component   = "aws-config"
  }
}

resource "aws_s3_bucket_versioning" "config_bucket_versioning" {
  bucket = aws_s3_bucket.config_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config_bucket_encryption" {
  bucket = aws_s3_bucket.config_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "config_bucket_pab" {
  bucket = aws_s3_bucket.config_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "config_bucket_policy" {
  bucket = aws_s3_bucket.config_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config_bucket.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = local.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketExistenceCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.config_bucket.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = local.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketDelivery"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config_bucket.arn}/AWSLogs/${local.account_id}/Config/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "AWS:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

#######################
# IAM Roles and Policies
#######################

# AWS Config Service Role
resource "aws_iam_role" "config_service_role" {
  name = "ConfigServiceRole-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name      = "AWS Config Service Role"
    Component = "aws-config"
  }
}

resource "aws_iam_role_policy_attachment" "config_service_role_policy" {
  role       = aws_iam_role.config_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/ConfigRole"
}

resource "aws_iam_role_policy" "config_s3_delivery_policy" {
  name = "ConfigS3DeliveryRolePolicy"
  role = aws_iam_role.config_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketAcl",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.config_bucket.arn
      },
      {
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config_bucket.arn}/AWSLogs/${local.account_id}/Config/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# Lambda Execution Role for Compliance Functions
resource "aws_iam_role" "lambda_compliance_role" {
  name = "LatticeComplianceRole-${local.suffix}"

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

  tags = {
    Name      = "Lambda Compliance Execution Role"
    Component = "lambda"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_compliance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_compliance_policy" {
  name = "LatticeCompliancePolicy"
  role = aws_iam_role.lambda_compliance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "vpc-lattice:*",
          "config:PutEvaluations",
          "config:StartConfigRulesEvaluation",
          "sns:Publish",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

#######################
# SNS Topic for Notifications
#######################

resource "aws_sns_topic" "compliance_alerts" {
  name = "${var.project_name}-compliance-alerts-${local.suffix}"

  display_name = "VPC Lattice Compliance Alerts"

  delivery_policy = jsonencode({
    http = {
      defaultHealthyRetryPolicy = {
        minDelayTarget = 20
        maxDelayTarget = 20
        numRetries     = 3
      }
    }
  })

  tags = {
    Name      = "VPC Lattice Compliance Alerts"
    Component = "sns"
  }
}

resource "aws_sns_topic_subscription" "email_notification" {
  topic_arn = aws_sns_topic.compliance_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

#######################
# Lambda Functions
#######################

# Compliance Evaluator Lambda Function
resource "aws_lambda_function" "compliance_evaluator" {
  filename         = data.archive_file.compliance_evaluator_zip.output_path
  function_name    = "${var.project_name}-compliance-evaluator-${local.suffix}"
  role            = aws_iam_role.lambda_compliance_role.arn
  handler         = "compliance_evaluator.lambda_handler"
  source_code_hash = data.archive_file.compliance_evaluator_zip.output_base64sha256
  runtime         = "python3.12"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.compliance_alerts.arn
    }
  }

  tags = {
    Name      = "VPC Lattice Compliance Evaluator"
    Component = "lambda"
    Purpose   = "Evaluate VPC Lattice resources for compliance"
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_compliance_policy,
    aws_cloudwatch_log_group.compliance_evaluator_logs
  ]
}

# Auto-Remediation Lambda Function
resource "aws_lambda_function" "auto_remediation" {
  count = var.enable_auto_remediation ? 1 : 0

  filename         = data.archive_file.auto_remediation_zip[0].output_path
  function_name    = "${var.project_name}-auto-remediation-${local.suffix}"
  role            = aws_iam_role.lambda_compliance_role.arn
  handler         = "auto_remediation.lambda_handler"
  source_code_hash = data.archive_file.auto_remediation_zip[0].output_base64sha256
  runtime         = "python3.12"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      CONFIG_RULE_NAME = aws_config_config_rule.vpc_lattice_compliance.name
      AWS_ACCOUNT_ID   = local.account_id
    }
  }

  tags = {
    Name      = "VPC Lattice Auto Remediation"
    Component = "lambda"
    Purpose   = "Automatically remediate compliance violations"
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_compliance_policy,
    aws_cloudwatch_log_group.auto_remediation_logs[0]
  ]
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "compliance_evaluator_logs" {
  name              = "/aws/lambda/${var.project_name}-compliance-evaluator-${local.suffix}"
  retention_in_days = 14

  tags = {
    Name      = "Compliance Evaluator Logs"
    Component = "cloudwatch"
  }
}

resource "aws_cloudwatch_log_group" "auto_remediation_logs" {
  count = var.enable_auto_remediation ? 1 : 0

  name              = "/aws/lambda/${var.project_name}-auto-remediation-${local.suffix}"
  retention_in_days = 14

  tags = {
    Name      = "Auto Remediation Logs"
    Component = "cloudwatch"
  }
}

# Lambda function source code archives
data "archive_file" "compliance_evaluator_zip" {
  type        = "zip"
  output_path = "${path.module}/compliance_evaluator.zip"
  source {
    content = templatefile("${path.module}/lambda_code/compliance_evaluator.py", {
      sns_topic_arn = aws_sns_topic.compliance_alerts.arn
    })
    filename = "compliance_evaluator.py"
  }
}

data "archive_file" "auto_remediation_zip" {
  count = var.enable_auto_remediation ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/auto_remediation.zip"
  source {
    content = templatefile("${path.module}/lambda_code/auto_remediation.py", {
      account_id = local.account_id
    })
    filename = "auto_remediation.py"
  }
}

# SNS Topic Subscription for Auto-Remediation
resource "aws_sns_topic_subscription" "auto_remediation" {
  count = var.enable_auto_remediation ? 1 : 0

  topic_arn = aws_sns_topic.compliance_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.auto_remediation[0].arn
}

# Lambda permission for SNS to invoke auto-remediation function
resource "aws_lambda_permission" "allow_sns_invoke_remediation" {
  count = var.enable_auto_remediation ? 1 : 0

  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_remediation[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.compliance_alerts.arn
}

#######################
# AWS Config Setup
#######################

# AWS Config Delivery Channel
resource "aws_config_delivery_channel" "compliance_delivery_channel" {
  name           = "default"
  s3_bucket_name = aws_s3_bucket.config_bucket.bucket

  snapshot_delivery_properties {
    delivery_frequency = var.config_delivery_frequency
  }

  depends_on = [aws_s3_bucket_policy.config_bucket_policy]
}

# AWS Config Configuration Recorder
resource "aws_config_configuration_recorder" "compliance_recorder" {
  name     = "default"
  role_arn = aws_iam_role.config_service_role.arn

  recording_group {
    all_supported                 = false
    include_global_resource_types = false
    resource_types = [
      "AWS::VpcLattice::ServiceNetwork",
      "AWS::VpcLattice::Service"
    ]
  }

  depends_on = [aws_config_delivery_channel.compliance_delivery_channel]
}

# Start the Configuration Recorder
resource "aws_config_configuration_recorder_status" "compliance_recorder_status" {
  name       = aws_config_configuration_recorder.compliance_recorder.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.compliance_delivery_channel]
}

# AWS Config Rule for VPC Lattice Compliance
resource "aws_config_config_rule" "vpc_lattice_compliance" {
  name = "${var.project_name}-policy-compliance-${local.suffix}"

  source {
    owner             = "AWS_LAMBDA"
    source_identifier = aws_lambda_function.compliance_evaluator.arn

    source_detail {
      event_source = "aws.config"
      message_type = "ConfigurationItemChangeNotification"
    }

    source_detail {
      event_source = "aws.config"
      message_type = "OversizedConfigurationItemChangeNotification"
    }
  }

  input_parameters = jsonencode({
    requireAuthPolicy = tostring(var.require_auth_policy)
    namePrefix        = var.service_name_prefix
    requireAuth       = tostring(var.require_service_auth)
  })

  depends_on = [
    aws_config_configuration_recorder.compliance_recorder,
    aws_lambda_permission.allow_config_invoke
  ]

  tags = {
    Name      = "VPC Lattice Policy Compliance Rule"
    Component = "aws-config"
  }
}

# Lambda permission for AWS Config to invoke the compliance evaluator
resource "aws_lambda_permission" "allow_config_invoke" {
  statement_id  = "AllowExecutionFromConfig"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.compliance_evaluator.function_name
  principal     = "config.amazonaws.com"
  source_account = local.account_id
}

#######################
# Demo VPC Lattice Resources (Optional)
#######################

# Demo VPC
resource "aws_vpc" "demo_vpc" {
  count = var.create_demo_resources ? 1 : 0

  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name      = "${var.project_name}-demo-vpc-${local.suffix}"
    Component = "demo"
    Purpose   = "Demo VPC for VPC Lattice testing"
  }
}

# Demo VPC Lattice Service Network (Non-compliant name for testing)
resource "aws_vpclattice_service_network" "demo_service_network" {
  count = var.create_demo_resources ? 1 : 0

  name      = "${var.demo_service_name}-network-${local.suffix}"
  auth_type = "AWS_IAM"

  tags = {
    Name      = "Demo Service Network"
    Component = "demo"
    Purpose   = "Non-compliant service network for testing"
  }
}

# Demo VPC Lattice Service Network VPC Association
resource "aws_vpclattice_service_network_vpc_association" "demo_association" {
  count = var.create_demo_resources ? 1 : 0

  vpc_identifier             = aws_vpc.demo_vpc[0].id
  service_network_identifier = aws_vpclattice_service_network.demo_service_network[0].id

  tags = {
    Name      = "Demo VPC Association"
    Component = "demo"
  }
}

# Demo VPC Lattice Service (Non-compliant auth type for testing)
resource "aws_vpclattice_service" "demo_service" {
  count = var.create_demo_resources ? 1 : 0

  name      = "${var.demo_service_name}-${local.suffix}"
  auth_type = "NONE"

  tags = {
    Name      = "Demo Service"
    Component = "demo"
    Purpose   = "Non-compliant service for testing"
  }
}