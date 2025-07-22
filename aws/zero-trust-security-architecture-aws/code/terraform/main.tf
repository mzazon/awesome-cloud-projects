# ==============================================================================
# ZERO TRUST SECURITY ARCHITECTURE - MAIN TERRAFORM CONFIGURATION
# ==============================================================================

# Data sources for AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  account_id        = data.aws_caller_identity.current.account_id
  region           = data.aws_region.current.name
  resource_prefix  = "${var.prefix}-${random_id.suffix.hex}"
  
  common_tags = merge(var.additional_tags, {
    Project     = "ZeroTrustSecurityArchitecture"
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# ==============================================================================
# KMS KEY FOR ZERO TRUST ENCRYPTION
# ==============================================================================

resource "aws_kms_key" "zero_trust" {
  description              = "Zero Trust Security Architecture encryption key"
  key_usage               = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  deletion_window_in_days = var.kms_key_deletion_window
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Zero Trust Services"
        Effect = "Allow"
        Principal = {
          Service = [
            "s3.amazonaws.com",
            "secretsmanager.amazonaws.com",
            "rds.amazonaws.com",
            "logs.amazonaws.com",
            "sns.amazonaws.com"
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:ReEncrypt*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = [
              "s3.${local.region}.amazonaws.com",
              "secretsmanager.${local.region}.amazonaws.com",
              "rds.${local.region}.amazonaws.com",
              "logs.${local.region}.amazonaws.com",
              "sns.${local.region}.amazonaws.com"
            ]
          }
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-key"
  })
}

resource "aws_kms_alias" "zero_trust" {
  name          = "alias/${local.resource_prefix}-key"
  target_key_id = aws_kms_key.zero_trust.key_id
}

# ==============================================================================
# S3 BUCKETS FOR SECURITY LOGS AND DATA
# ==============================================================================

# Security logs bucket
resource "aws_s3_bucket" "security_logs" {
  bucket        = "${local.resource_prefix}-security-logs-${local.account_id}"
  force_destroy = var.s3_force_destroy
  
  tags = merge(local.common_tags, {
    Name    = "${local.resource_prefix}-security-logs"
    Purpose = "SecurityLogsStorage"
  })
}

resource "aws_s3_bucket_versioning" "security_logs" {
  bucket = aws_s3_bucket.security_logs.id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_encryption" "security_logs" {
  bucket = aws_s3_bucket.security_logs.id
  
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.zero_trust.arn
        sse_algorithm     = "aws:kms"
      }
      bucket_key_enabled = true
    }
  }
}

resource "aws_s3_bucket_public_access_block" "security_logs" {
  bucket = aws_s3_bucket.security_logs.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "security_logs" {
  bucket = aws_s3_bucket.security_logs.id
  
  rule {
    id     = "security_logs_lifecycle"
    status = "Enabled"
    
    expiration {
      days = 2555  # 7 years retention for security logs
    }
    
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
    
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Secure data bucket
resource "aws_s3_bucket" "secure_data" {
  bucket        = "${local.resource_prefix}-secure-data-${local.account_id}"
  force_destroy = var.s3_force_destroy
  
  tags = merge(local.common_tags, {
    Name    = "${local.resource_prefix}-secure-data"
    Purpose = "SecureDataStorage"
  })
}

resource "aws_s3_bucket_versioning" "secure_data" {
  bucket = aws_s3_bucket.secure_data.id
  versioning_configuration {
    status = var.s3_versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_encryption" "secure_data" {
  bucket = aws_s3_bucket.secure_data.id
  
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = aws_kms_key.zero_trust.arn
        sse_algorithm     = "aws:kms"
      }
      bucket_key_enabled = true
    }
  }
}

resource "aws_s3_bucket_public_access_block" "secure_data" {
  bucket = aws_s3_bucket.secure_data.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ==============================================================================
# VPC AND NETWORK SECURITY (ZERO TRUST NETWORK)
# ==============================================================================

resource "aws_vpc" "zero_trust" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(local.common_tags, {
    Name    = "${local.resource_prefix}-vpc"
    Purpose = "ZeroTrustNetwork"
  })
}

# Private subnets only (no public subnets in zero trust design)
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)
  
  vpc_id            = aws_vpc.zero_trust.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-private-${count.index + 1}"
    Type = "Private"
  })
}

# Route table for private subnets
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.zero_trust.id
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)
  
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Zero trust security group with minimal access
resource "aws_security_group" "zero_trust" {
  name_prefix = "${local.resource_prefix}-zero-trust-"
  description = "Zero Trust Security Group with minimal access"
  vpc_id      = aws_vpc.zero_trust.id
  
  # Only allow HTTPS within the security group
  ingress {
    description     = "HTTPS within security group"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    self            = true
  }
  
  # Allow outbound HTTPS to trusted networks only
  egress {
    description = "HTTPS to trusted networks"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.trusted_ip_ranges
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-zero-trust-sg"
  })
}

# VPC Endpoints for AWS services (avoid internet gateway)
resource "aws_vpc_endpoint" "s3" {
  vpc_id              = aws_vpc.zero_trust.id
  service_name        = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type   = "Gateway"
  route_table_ids     = [aws_route_table.private.id]
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.security_logs.arn}",
          "${aws_s3_bucket.security_logs.arn}/*",
          "${aws_s3_bucket.secure_data.arn}",
          "${aws_s3_bucket.secure_data.arn}/*"
        ]
        Condition = {
          StringEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-s3-endpoint"
  })
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.zero_trust.id
  service_name        = "com.amazonaws.${local.region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.zero_trust.id]
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-logs-endpoint"
  })
}

# VPC Flow Logs
resource "aws_flow_log" "zero_trust" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  
  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.zero_trust.id
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-flow-logs"
  })
}

# ==============================================================================
# AWS SECURITY HUB
# ==============================================================================

resource "aws_securityhub_account" "main" {
  count                        = var.enable_security_hub ? 1 : 0
  enable_default_standards     = true
  control_finding_generator    = "SECURITY_CONTROL"
  auto_enable_controls         = true
  
  tags = local.common_tags
}

# Enable Security Hub standards
resource "aws_securityhub_standards_subscription" "aws_foundational" {
  count         = var.enable_security_hub ? 1 : 0
  standards_arn = "arn:aws:securityhub:${local.region}::standard/aws-foundational-security/v/1.0.0"
  
  depends_on = [aws_securityhub_account.main]
}

resource "aws_securityhub_standards_subscription" "cis" {
  count         = var.enable_security_hub ? 1 : 0
  standards_arn = "arn:aws:securityhub:${local.region}::standard/cis-aws-foundations-benchmark/v/1.2.0"
  
  depends_on = [aws_securityhub_account.main]
}

# Security Hub custom insight for zero trust findings
resource "aws_securityhub_insight" "zero_trust_high_risk" {
  count = var.enable_security_hub ? 1 : 0
  
  filters {
    severity_label {
      comparison = "EQUALS"
      value      = "HIGH"
    }
    
    resource_type {
      comparison = "EQUALS"
      value      = "AwsIamRole"
    }
    
    compliance_status {
      comparison = "EQUALS"
      value      = "FAILED"
    }
  }
  
  group_by_attribute = "ResourceType"
  name              = "Zero Trust High Risk Findings"
  
  depends_on = [aws_securityhub_account.main]
}

# ==============================================================================
# AMAZON GUARDDUTY
# ==============================================================================

resource "aws_guardduty_detector" "main" {
  count                        = var.enable_guardduty ? 1 : 0
  enable                       = true
  finding_publishing_frequency = var.guardduty_finding_frequency
  
  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }
  
  tags = local.common_tags
}

# GuardDuty threat intelligence set
resource "aws_s3_object" "threat_intel" {
  count = var.enable_guardduty ? 1 : 0
  
  bucket  = aws_s3_bucket.security_logs.id
  key     = "threat-intel/malicious-ips.txt"
  content = "# Threat Intelligence Feed\n# Add malicious IP addresses here\n"
  
  server_side_encryption = "aws:kms"
  kms_key_id            = aws_kms_key.zero_trust.arn
}

resource "aws_guardduty_threatintelset" "main" {
  count = var.enable_guardduty ? 1 : 0
  
  activate    = true
  detector_id = aws_guardduty_detector.main[0].id
  format      = "TXT"
  location    = "https://${aws_s3_bucket.security_logs.id}.s3.${local.region}.amazonaws.com/${aws_s3_object.threat_intel[0].key}"
  name        = "${local.resource_prefix}-threat-intel"
  
  tags = local.common_tags
}

# ==============================================================================
# AWS CONFIG
# ==============================================================================

# Config service role
resource "aws_iam_role" "config" {
  count = var.enable_config ? 1 : 0
  
  name = "${local.resource_prefix}-config-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "config" {
  count = var.enable_config ? 1 : 0
  
  role       = aws_iam_role.config[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/ConfigRole"
}

# Config delivery channel
resource "aws_config_delivery_channel" "main" {
  count = var.enable_config ? 1 : 0
  
  name           = "${local.resource_prefix}-config-channel"
  s3_bucket_name = aws_s3_bucket.security_logs.bucket
  s3_key_prefix  = "config/"
  
  snapshot_delivery_properties {
    delivery_frequency = var.config_delivery_frequency
  }
  
  depends_on = [aws_config_configuration_recorder.main]
}

# Config configuration recorder
resource "aws_config_configuration_recorder" "main" {
  count = var.enable_config ? 1 : 0
  
  name     = "${local.resource_prefix}-config-recorder"
  role_arn = aws_iam_role.config[0].arn
  
  recording_group {
    all_supported                 = true
    include_global_resource_types = true
    
    recording_mode_override {
      resource_types = [
        "AWS::IAM::Role",
        "AWS::IAM::Policy"
      ]
      recording_mode {
        recording_frequency = "CONTINUOUS"
      }
    }
  }
}

# Config rules for zero trust compliance
resource "aws_config_config_rule" "mfa_enabled" {
  count = var.enable_config ? 1 : 0
  
  name = "${local.resource_prefix}-mfa-enabled"
  
  source {
    owner             = "AWS"
    source_identifier = "MFA_ENABLED_FOR_IAM_CONSOLE_ACCESS"
  }
  
  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_config_rule" "s3_ssl_requests_only" {
  count = var.enable_config ? 1 : 0
  
  name = "${local.resource_prefix}-s3-ssl-requests-only"
  
  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_SSL_REQUESTS_ONLY"
  }
  
  depends_on = [aws_config_configuration_recorder.main]
}

# ==============================================================================
# AMAZON INSPECTOR
# ==============================================================================

resource "aws_inspector2_enabler" "main" {
  count          = var.enable_inspector ? 1 : 0
  account_ids    = [local.account_id]
  resource_types = ["ECR", "EC2"]
}

# ==============================================================================
# IAM ROLES AND POLICIES
# ==============================================================================

# Zero Trust boundary policy
resource "aws_iam_policy" "zero_trust_boundary" {
  name        = "${local.resource_prefix}-boundary-policy"
  description = "Zero Trust Security Boundary Policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnforceMFAForAllActions"
        Effect = "Deny"
        Action = "*"
        Resource = "*"
        Condition = {
          BoolIfExists = {
            "aws:MultiFactorAuthPresent" = "false"
          }
          NumericLessThan = {
            "aws:MultiFactorAuthAge" = "3600"
          }
        }
      },
      {
        Sid    = "RestrictToTrustedNetworks"
        Effect = "Deny"
        Action = "*"
        Resource = "*"
        Condition = {
          IpAddressIfExists = {
            "aws:SourceIp" = "0.0.0.0/0"
          }
          ForAllValues:StringNotEquals = {
            "aws:SourceIp" = var.trusted_ip_ranges
          }
        }
      },
      {
        Sid    = "EnforceSSLRequests"
        Effect = "Deny"
        Action = "s3:*"
        Resource = "*"
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "RestrictHighRiskActions"
        Effect = "Deny"
        Action = [
          "iam:CreateUser",
          "iam:DeleteUser",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachUserPolicy",
          "iam:DetachUserPolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = [local.region]
          }
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# ABAC (Attribute-Based Access Control) policy
resource "aws_iam_policy" "abac" {
  name        = "${local.resource_prefix}-abac-policy"
  description = "Zero Trust Attribute-Based Access Control Policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccessBasedOnDepartment"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::*/$${saml:Department}/*"
        Condition = {
          StringEquals = {
            "saml:Department" = ["Finance", "HR", "Engineering"]
          }
        }
      },
      {
        Sid    = "AllowAdminAccessBasedOnRole"
        Effect = "Allow"
        Action = [
          "s3:DeleteObject",
          "s3:GetObjectVersion"
        ]
        Resource = "arn:aws:s3:::*/$${saml:Department}/*"
        Condition = {
          StringEquals = {
            "saml:Role" = "Admin"
          }
          DateGreaterThan = {
            "aws:CurrentTime" = "2024-01-01T00:00:00Z"
          }
        }
      },
      {
        Sid    = "TimeBasedAccess"
        Effect = "Deny"
        Action = "*"
        Resource = "*"
        Condition = {
          DateGreaterThan = {
            "aws:CurrentTime" = "18:00:00Z"
          }
          DateLessThan = {
            "aws:CurrentTime" = "08:00:00Z"
          }
          StringNotEquals = {
            "saml:Role" = "OnCallEngineer"
          }
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Security role with zero trust principles
resource "aws_iam_role" "security" {
  name                 = "${local.resource_prefix}-security-role"
  permissions_boundary = aws_iam_policy.zero_trust_boundary.arn
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = "${local.resource_prefix}-security-automation"
          }
        }
      }
    ]
  })
  
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "security_basic" {
  role       = aws_iam_role.security.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ==============================================================================
# CLOUDWATCH MONITORING AND ALERTING
# ==============================================================================

# CloudWatch log groups
resource "aws_cloudwatch_log_group" "zero_trust" {
  name              = "/aws/zero-trust/${local.resource_prefix}"
  retention_in_days = var.cloudwatch_retention_days
  kms_key_id        = aws_kms_key.zero_trust.arn
  
  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  
  name              = "/aws/vpc/flowlogs/${local.resource_prefix}"
  retention_in_days = var.cloudwatch_retention_days
  kms_key_id        = aws_kms_key.zero_trust.arn
  
  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "session_logs" {
  name              = "/aws/zero-trust/${local.resource_prefix}/sessions"
  retention_in_days = var.cloudwatch_retention_days
  kms_key_id        = aws_kms_key.zero_trust.arn
  
  tags = local.common_tags
}

# IAM role for VPC Flow Logs
resource "aws_iam_role" "flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  
  name = "${local.resource_prefix}-flow-logs-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  
  name = "${local.resource_prefix}-flow-logs-policy"
  role = aws_iam_role.flow_logs[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# SNS topic for security alerts
resource "aws_sns_topic" "security_alerts" {
  name         = "${local.resource_prefix}-security-alerts"
  display_name = "Zero Trust Security Alerts"
  
  kms_master_key_id = aws_kms_key.zero_trust.id
  
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# CloudWatch alarms
resource "aws_cloudwatch_metric_alarm" "failed_logins" {
  alarm_name          = "${local.resource_prefix}-failed-logins"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ConsoleLogin"
  namespace           = "AWS/CloudTrail"
  period              = "300"
  statistic           = "Sum"
  threshold           = "3"
  alarm_description   = "Zero Trust: Multiple failed login attempts"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  
  tags = local.common_tags
}

# CloudWatch dashboard
resource "aws_cloudwatch_dashboard" "zero_trust" {
  dashboard_name = "${local.resource_prefix}-security-dashboard"
  
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
            ["AWS/SecurityHub", "Findings", "ComplianceType", "FAILED"],
            ["AWS/GuardDuty", "Findings", "Severity", "HIGH"]
          ]
          period = 300
          stat   = "Sum"
          region = local.region
          title  = "Zero Trust Security Findings"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        
        properties = {
          query   = "SOURCE '/aws/zero-trust/${local.resource_prefix}' | fields @timestamp, sourceIPAddress, userIdentity.type, eventName | filter eventName like /AssumeRole/ | stats count() by userIdentity.type"
          region  = local.region
          title   = "Zero Trust Access Patterns"
        }
      }
    ]
  })
}

# ==============================================================================
# LAMBDA FUNCTION FOR SESSION VERIFICATION
# ==============================================================================

# Lambda function code
locals {
  lambda_code = base64encode(templatefile("${path.module}/session_verification.py", {
    prefix = local.resource_prefix
  }))
}

# Create the Lambda function code file
resource "local_file" "session_verification" {
  content = templatefile("${path.module}/session_verification.py", {
    prefix = local.resource_prefix
  })
  filename = "${path.module}/session_verification.py"
}

# ZIP the Lambda function
data "archive_file" "session_verification" {
  type        = "zip"
  output_path = "${path.module}/session_verification.zip"
  
  source {
    content = templatefile("${path.module}/session_verification.py", {
      prefix = local.resource_prefix
    })
    filename = "session_verification.py"
  }
  
  depends_on = [local_file.session_verification]
}

resource "aws_lambda_function" "session_verification" {
  filename         = data.archive_file.session_verification.output_path
  function_name    = "${local.resource_prefix}-session-verification"
  role            = aws_iam_role.security.arn
  handler         = "session_verification.lambda_handler"
  source_code_hash = data.archive_file.session_verification.output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  description = "Zero Trust Session Verification"
  
  environment {
    variables = {
      KMS_KEY_ID = aws_kms_key.zero_trust.arn
      LOG_GROUP  = aws_cloudwatch_log_group.zero_trust.name
    }
  }
  
  tags = local.common_tags
}

# ==============================================================================
# COST MONITORING
# ==============================================================================

resource "aws_ce_anomaly_detector" "zero_trust" {
  count = var.enable_cost_anomaly_detection ? 1 : 0
  
  name         = "${local.resource_prefix}-cost-anomaly"
  monitor_type = "DIMENSIONAL"
  
  specification = jsonencode({
    Dimension = "SERVICE"
    MatchOptions = ["EQUALS"]
    Values = [
      "Amazon GuardDuty",
      "AWS Security Hub",
      "AWS Config",
      "Amazon Inspector"
    ]
  })
  
  tags = local.common_tags
}

resource "aws_ce_anomaly_subscription" "zero_trust" {
  count = var.enable_cost_anomaly_detection ? 1 : 0
  
  name      = "${local.resource_prefix}-cost-alerts"
  frequency = "DAILY"
  
  monitor_arn_list = [
    aws_ce_anomaly_detector.zero_trust[0].arn
  ]
  
  subscriber {
    type    = "EMAIL"
    address = var.alert_email
  }
  
  threshold_expression {
    and {
      dimension {
        key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
        values        = ["100"]
        match_options = ["GREATER_THAN_OR_EQUAL"]
      }
    }
  }
  
  tags = local.common_tags
}