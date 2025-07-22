# =============================================================================
# AUTOMATED SECURITY SCANNING WITH INSPECTOR AND SECURITY HUB - MAIN TERRAFORM
# =============================================================================
# This Terraform configuration implements an automated security scanning pipeline
# using Amazon Inspector for vulnerability assessment and AWS Security Hub for
# centralized security findings management, complete with automated response
# and notification capabilities.
# =============================================================================

# -----------------------------------------------------------------------------
# DATA SOURCES
# -----------------------------------------------------------------------------

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Get current AWS region
data "aws_region" "current" {}

# Get default VPC for test instance deployment
data "aws_vpc" "default" {
  default = true
}

# Get default subnet for test instance deployment
data "aws_subnet" "default" {
  vpc_id            = data.aws_vpc.default.id
  availability_zone = data.aws_availability_zones.available.names[0]
}

# Get available availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Get latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -----------------------------------------------------------------------------
# SECURITY HUB CONFIGURATION
# -----------------------------------------------------------------------------

# Enable AWS Security Hub
resource "aws_securityhub_account" "main" {
  enable_default_standards = var.enable_default_standards

  depends_on = [aws_securityhub_organization_configuration.main]
}

# Configure Security Hub organization settings (if organizational management is enabled)
resource "aws_securityhub_organization_configuration" "main" {
  count = var.enable_organization_management ? 1 : 0

  auto_enable                = true
  auto_enable_standards      = "DEFAULT"
  organization_configuration {
    configuration_type = "CENTRAL"
  }
}

# Enable AWS Foundational Security Best Practices standard
resource "aws_securityhub_standards_subscription" "aws_foundational" {
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:standard/aws-foundational-security-best-practices/v/1.0.0"
  
  depends_on = [aws_securityhub_account.main]
}

# Enable CIS AWS Foundations Benchmark standard
resource "aws_securityhub_standards_subscription" "cis_benchmark" {
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:standard/cis-aws-foundations-benchmark/v/1.2.0"
  
  depends_on = [aws_securityhub_account.main]
}

# Create custom Security Hub insights for critical vulnerabilities
resource "aws_securityhub_insight" "critical_vulnerabilities" {
  name      = "Critical Vulnerabilities by Resource Type"
  group_by_attribute = "ResourceType"

  filters {
    severity_label {
      comparison = "EQUALS"
      value      = "CRITICAL"
    }
    record_state {
      comparison = "EQUALS"
      value      = "ACTIVE"
    }
  }

  depends_on = [aws_securityhub_account.main]
}

# Create insight for unpatched EC2 instances
resource "aws_securityhub_insight" "unpatched_ec2" {
  name      = "Unpatched EC2 Instances"
  group_by_attribute = "ResourceId"

  filters {
    resource_type {
      comparison = "EQUALS"
      value      = "AwsEc2Instance"
    }
    compliance_status {
      comparison = "EQUALS"
      value      = "FAILED"
    }
  }

  depends_on = [aws_securityhub_account.main]
}

# -----------------------------------------------------------------------------
# AMAZON INSPECTOR CONFIGURATION
# -----------------------------------------------------------------------------

# Enable Amazon Inspector V2
resource "aws_inspector2_enabler" "main" {
  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = var.inspector_resource_types
}

# Configure Inspector scan settings
resource "aws_inspector2_organization_configuration" "main" {
  count = var.enable_organization_management ? 1 : 0

  auto_enable {
    ec2 = true
    ecr = true
    lambda = true
  }
}

# -----------------------------------------------------------------------------
# SNS TOPIC FOR SECURITY ALERTS
# -----------------------------------------------------------------------------

# Create SNS topic for security notifications
resource "aws_sns_topic" "security_alerts" {
  name = "${var.resource_prefix}-security-alerts"

  tags = merge(var.common_tags, {
    Name        = "${var.resource_prefix}-security-alerts"
    Purpose     = "Security Alert Notifications"
    Component   = "SNS"
  })
}

# SNS topic policy to allow EventBridge to publish
resource "aws_sns_topic_policy" "security_alerts" {
  arn = aws_sns_topic.security_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "SNS:Publish"
        Resource = aws_sns_topic.security_alerts.arn
      },
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "SNS:GetTopicAttributes",
          "SNS:SetTopicAttributes",
          "SNS:AddPermission",
          "SNS:RemovePermission",
          "SNS:DeleteTopic",
          "SNS:Subscribe",
          "SNS:ListSubscriptionsByTopic",
          "SNS:Publish"
        ]
        Resource = aws_sns_topic.security_alerts.arn
      }
    ]
  })
}

# Email subscription to SNS topic (if email provided)
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# -----------------------------------------------------------------------------
# IAM ROLES AND POLICIES
# -----------------------------------------------------------------------------

# IAM role for Lambda security response function
resource "aws_iam_role" "lambda_security_response" {
  name = "${var.resource_prefix}-lambda-security-response-role"

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

  tags = merge(var.common_tags, {
    Name      = "${var.resource_prefix}-lambda-security-response-role"
    Purpose   = "Lambda Security Response Execution"
    Component = "IAM"
  })
}

# IAM policy for Lambda security response function
resource "aws_iam_role_policy" "lambda_security_response" {
  name = "${var.resource_prefix}-lambda-security-response-policy"
  role = aws_iam_role.lambda_security_response.id

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
          "securityhub:BatchImportFindings",
          "securityhub:BatchUpdateFindings",
          "securityhub:GetFindings"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "inspector2:ListFindings",
          "inspector2:BatchGetFindings"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.security_alerts.arn
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach basic Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_security_response.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM role for compliance reporting Lambda
resource "aws_iam_role" "lambda_compliance_reporting" {
  name = "${var.resource_prefix}-lambda-compliance-reporting-role"

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

  tags = merge(var.common_tags, {
    Name      = "${var.resource_prefix}-lambda-compliance-reporting-role"
    Purpose   = "Lambda Compliance Reporting Execution"
    Component = "IAM"
  })
}

# IAM policy for compliance reporting Lambda
resource "aws_iam_role_policy" "lambda_compliance_reporting" {
  name = "${var.resource_prefix}-lambda-compliance-reporting-policy"
  role = aws_iam_role.lambda_compliance_reporting.id

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
          "securityhub:GetFindings",
          "securityhub:BatchGetFindings"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.compliance_reports.arn}/*"
      }
    ]
  })
}

# Attach basic Lambda execution role to compliance reporting function
resource "aws_iam_role_policy_attachment" "lambda_compliance_basic_execution" {
  role       = aws_iam_role.lambda_compliance_reporting.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# -----------------------------------------------------------------------------
# S3 BUCKET FOR COMPLIANCE REPORTS
# -----------------------------------------------------------------------------

# S3 bucket for storing compliance reports
resource "aws_s3_bucket" "compliance_reports" {
  bucket = "${var.resource_prefix}-compliance-reports-${random_id.bucket_suffix.hex}"

  tags = merge(var.common_tags, {
    Name      = "${var.resource_prefix}-compliance-reports"
    Purpose   = "Security Compliance Reports Storage"
    Component = "S3"
  })
}

# Random ID for bucket suffix to ensure uniqueness
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "compliance_reports" {
  bucket = aws_s3_bucket.compliance_reports.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "compliance_reports" {
  bucket = aws_s3_bucket.compliance_reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "compliance_reports" {
  bucket = aws_s3_bucket.compliance_reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "compliance_reports" {
  bucket = aws_s3_bucket.compliance_reports.id

  rule {
    id     = "compliance_reports_lifecycle"
    status = "Enabled"

    expiration {
      days = var.compliance_reports_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# -----------------------------------------------------------------------------
# LAMBDA FUNCTIONS
# -----------------------------------------------------------------------------

# Lambda function for automated security response
resource "aws_lambda_function" "security_response_handler" {
  filename         = data.archive_file.security_response_handler.output_path
  function_name    = "${var.resource_prefix}-security-response-handler"
  role            = aws_iam_role.lambda_security_response.arn
  handler         = "security-response-handler.lambda_handler"
  source_code_hash = data.archive_file.security_response_handler.output_base64sha256
  runtime         = "python3.9"
  timeout         = 300

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.security_alerts.arn
    }
  }

  tags = merge(var.common_tags, {
    Name      = "${var.resource_prefix}-security-response-handler"
    Purpose   = "Automated Security Response Processing"
    Component = "Lambda"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.security_response_handler
  ]
}

# CloudWatch log group for security response Lambda
resource "aws_cloudwatch_log_group" "security_response_handler" {
  name              = "/aws/lambda/${var.resource_prefix}-security-response-handler"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(var.common_tags, {
    Name      = "/aws/lambda/${var.resource_prefix}-security-response-handler"
    Purpose   = "Lambda Security Response Logs"
    Component = "CloudWatch"
  })
}

# Lambda function for compliance reporting
resource "aws_lambda_function" "compliance_report_generator" {
  filename         = data.archive_file.compliance_report_generator.output_path
  function_name    = "${var.resource_prefix}-compliance-report-generator"
  role            = aws_iam_role.lambda_compliance_reporting.arn
  handler         = "compliance-report-generator.lambda_handler"
  source_code_hash = data.archive_file.compliance_report_generator.output_base64sha256
  runtime         = "python3.9"
  timeout         = 300

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.compliance_reports.id
    }
  }

  tags = merge(var.common_tags, {
    Name      = "${var.resource_prefix}-compliance-report-generator"
    Purpose   = "Automated Compliance Reporting"
    Component = "Lambda"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_compliance_basic_execution,
    aws_cloudwatch_log_group.compliance_report_generator
  ]
}

# CloudWatch log group for compliance reporting Lambda
resource "aws_cloudwatch_log_group" "compliance_report_generator" {
  name              = "/aws/lambda/${var.resource_prefix}-compliance-report-generator"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(var.common_tags, {
    Name      = "/aws/lambda/${var.resource_prefix}-compliance-report-generator"
    Purpose   = "Lambda Compliance Reporting Logs"
    Component = "CloudWatch"
  })
}

# -----------------------------------------------------------------------------
# LAMBDA FUNCTION CODE ARCHIVES
# -----------------------------------------------------------------------------

# Create security response handler Python code
data "archive_file" "security_response_handler" {
  type        = "zip"
  output_path = "${path.module}/security-response-handler.zip"

  source {
    content = templatefile("${path.module}/lambda_functions/security-response-handler.py", {
      sns_topic_arn = aws_sns_topic.security_alerts.arn
    })
    filename = "security-response-handler.py"
  }
}

# Create compliance report generator Python code
data "archive_file" "compliance_report_generator" {
  type        = "zip"
  output_path = "${path.module}/compliance-report-generator.zip"

  source {
    content = templatefile("${path.module}/lambda_functions/compliance-report-generator.py", {
      s3_bucket = aws_s3_bucket.compliance_reports.id
    })
    filename = "compliance-report-generator.py"
  }
}

# -----------------------------------------------------------------------------
# EVENTBRIDGE RULES AND TARGETS
# -----------------------------------------------------------------------------

# EventBridge rule for high-severity Security Hub findings
resource "aws_cloudwatch_event_rule" "security_findings" {
  name        = "${var.resource_prefix}-security-findings-rule"
  description = "Route high severity security findings to Lambda"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = var.alert_severity_levels
        }
      }
    }
  })

  tags = merge(var.common_tags, {
    Name      = "${var.resource_prefix}-security-findings-rule"
    Purpose   = "Security Findings Event Processing"
    Component = "EventBridge"
  })
}

# EventBridge target for security findings rule
resource "aws_cloudwatch_event_target" "security_findings_lambda" {
  rule      = aws_cloudwatch_event_rule.security_findings.name
  target_id = "SecurityFindingsLambdaTarget"
  arn       = aws_lambda_function.security_response_handler.arn
}

# Lambda permission for EventBridge to invoke security response function
resource "aws_lambda_permission" "allow_eventbridge_security" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_response_handler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.security_findings.arn
}

# EventBridge rule for weekly compliance reporting
resource "aws_cloudwatch_event_rule" "weekly_compliance_report" {
  name                = "${var.resource_prefix}-weekly-compliance-report"
  description         = "Generate weekly compliance report"
  schedule_expression = var.compliance_report_schedule

  tags = merge(var.common_tags, {
    Name      = "${var.resource_prefix}-weekly-compliance-report"
    Purpose   = "Automated Compliance Reporting Schedule"
    Component = "EventBridge"
  })
}

# EventBridge target for weekly compliance report
resource "aws_cloudwatch_event_target" "weekly_compliance_report_lambda" {
  rule      = aws_cloudwatch_event_rule.weekly_compliance_report.name
  target_id = "WeeklyComplianceReportLambdaTarget"
  arn       = aws_lambda_function.compliance_report_generator.arn
}

# Lambda permission for EventBridge to invoke compliance reporting function
resource "aws_lambda_permission" "allow_eventbridge_compliance" {
  statement_id  = "AllowExecutionFromEventBridgeCompliance"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.compliance_report_generator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weekly_compliance_report.arn
}

# -----------------------------------------------------------------------------
# TEST EC2 INSTANCE (OPTIONAL)
# -----------------------------------------------------------------------------

# Security group for test EC2 instance
resource "aws_security_group" "test_instance" {
  count       = var.create_test_instance ? 1 : 0
  name        = "${var.resource_prefix}-test-instance-sg"
  description = "Security group for test EC2 instance used for vulnerability scanning"
  vpc_id      = data.aws_vpc.default.id

  # Allow SSH access (for testing purposes only)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Note: Restrict this in production
  }

  # Allow HTTP access (for testing purposes only)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name      = "${var.resource_prefix}-test-instance-sg"
    Purpose   = "Test Instance Security Group"
    Component = "EC2"
  })
}

# Test EC2 instance for scanning demonstration
resource "aws_instance" "test_instance" {
  count                  = var.create_test_instance ? 1 : 0
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.test_instance_type
  subnet_id              = data.aws_subnet.default.id
  vpc_security_group_ids = [aws_security_group.test_instance[0].id]

  # User data to install some packages for vulnerability testing
  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Security Test Instance</h1>" > /var/www/html/index.html
              EOF
  )

  tags = merge(var.common_tags, {
    Name              = "${var.resource_prefix}-security-test-instance"
    Purpose           = "Security Vulnerability Testing"
    Component         = "EC2"
    SecurityStatus    = "Testing"
    Environment       = "Test"
    LastSecurityScan  = timestamp()
  })
}

# -----------------------------------------------------------------------------
# CLOUDWATCH DASHBOARD
# -----------------------------------------------------------------------------

# CloudWatch dashboard for security monitoring
resource "aws_cloudwatch_dashboard" "security_monitoring" {
  dashboard_name = "${var.resource_prefix}-security-monitoring"

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
            ["AWS/Events", "MatchedEvents", "RuleName", aws_cloudwatch_event_rule.security_findings.name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.security_response_handler.function_name],
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.security_response_handler.function_name],
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.security_response_handler.function_name]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Security Response Metrics"
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/SNS", "NumberOfMessagesPublished", "TopicName", aws_sns_topic.security_alerts.name],
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.compliance_report_generator.function_name]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Notification and Reporting Metrics"
          period  = 300
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name      = "${var.resource_prefix}-security-monitoring"
    Purpose   = "Security Monitoring Dashboard"
    Component = "CloudWatch"
  })
}