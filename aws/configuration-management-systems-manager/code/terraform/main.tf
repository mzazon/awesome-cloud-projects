# Main Terraform configuration for AWS Systems Manager State Manager
# This file creates a comprehensive configuration management solution using State Manager

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get the latest Amazon Linux 2 AMI
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

# Get default VPC and subnet for test instances
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ==============================================================================
# CloudWatch Log Group for State Manager
# ==============================================================================

resource "aws_cloudwatch_log_group" "state_manager_logs" {
  name              = "/aws/ssm/state-manager-${random_id.suffix.hex}"
  retention_in_days = 14

  tags = {
    Name        = "State Manager Logs"
    Purpose     = "StateManagerDemo"
    Environment = var.environment
  }
}

# ==============================================================================
# SNS Topic for Configuration Drift Notifications
# ==============================================================================

resource "aws_sns_topic" "config_drift_alerts" {
  name         = "config-drift-alerts-${random_id.suffix.hex}"
  display_name = "Configuration Drift Alerts"

  tags = {
    Name        = "Configuration Drift Alerts"
    Purpose     = "StateManagerDemo"
    Environment = var.environment
  }
}

# SNS Topic Subscription for email notifications
resource "aws_sns_topic_subscription" "config_drift_email" {
  topic_arn = aws_sns_topic.config_drift_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ==============================================================================
# S3 Bucket for State Manager Output
# ==============================================================================

resource "aws_s3_bucket" "state_manager_output" {
  bucket = var.s3_bucket_name != "" ? var.s3_bucket_name : "aws-ssm-${var.aws_region}-${data.aws_caller_identity.current.account_id}-${random_id.suffix.hex}"

  tags = {
    Name        = "State Manager Output"
    Purpose     = "StateManagerDemo"
    Environment = var.environment
  }
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "state_manager_output" {
  bucket = aws_s3_bucket.state_manager_output.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "state_manager_output" {
  bucket = aws_s3_bucket.state_manager_output.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "state_manager_output" {
  bucket = aws_s3_bucket.state_manager_output.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ==============================================================================
# IAM Role and Policies for State Manager
# ==============================================================================

# Trust policy for State Manager role
data "aws_iam_policy_document" "state_manager_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }
  }
}

# IAM role for State Manager
resource "aws_iam_role" "state_manager_role" {
  name               = "SSMStateManagerRole-${random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.state_manager_assume_role.json
  description        = "Role for Systems Manager State Manager operations"

  tags = {
    Name        = "State Manager Role"
    Purpose     = "StateManagerDemo"
    Environment = var.environment
  }
}

# Custom policy for State Manager operations
data "aws_iam_policy_document" "state_manager_policy" {
  statement {
    sid    = "SystemsManagerOperations"
    effect = "Allow"
    actions = [
      "ssm:CreateAssociation",
      "ssm:DescribeAssociation*",
      "ssm:GetAutomationExecution",
      "ssm:ListAssociations",
      "ssm:ListDocuments",
      "ssm:SendCommand",
      "ssm:StartAutomationExecution",
      "ssm:DescribeInstanceInformation",
      "ssm:DescribeDocumentParameters",
      "ssm:ListCommandInvocations",
      "ssm:StartAssociationsOnce",
      "ssm:DescribeAssociationExecutions",
      "ssm:ListComplianceItems"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EC2Operations"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceAttribute",
      "ec2:DescribeImages",
      "ec2:DescribeSnapshots",
      "ec2:DescribeVolumes"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "CloudWatchOperations"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "SNSOperations"
    effect = "Allow"
    actions = [
      "sns:Publish"
    ]
    resources = [aws_sns_topic.config_drift_alerts.arn]
  }

  statement {
    sid    = "S3Operations"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.state_manager_output.arn,
      "${aws_s3_bucket.state_manager_output.arn}/*"
    ]
  }
}

# Create custom policy
resource "aws_iam_policy" "state_manager_policy" {
  name        = "SSMStateManagerPolicy-${random_id.suffix.hex}"
  description = "Policy for State Manager operations"
  policy      = data.aws_iam_policy_document.state_manager_policy.json

  tags = {
    Name        = "State Manager Policy"
    Purpose     = "StateManagerDemo"
    Environment = var.environment
  }
}

# Attach custom policy to role
resource "aws_iam_role_policy_attachment" "state_manager_custom_policy" {
  role       = aws_iam_role.state_manager_role.name
  policy_arn = aws_iam_policy.state_manager_policy.arn
}

# Attach AWS managed policy for SSM
resource "aws_iam_role_policy_attachment" "state_manager_managed_policy" {
  role       = aws_iam_role.state_manager_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ==============================================================================
# SSM Documents
# ==============================================================================

# Custom security configuration document
resource "aws_ssm_document" "security_configuration" {
  name          = "Custom-SecurityConfiguration-${random_id.suffix.hex}"
  document_type = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Configure security settings on Linux instances"
    parameters = {
      enableFirewall = {
        type        = "String"
        description = "Enable firewall"
        default     = tostring(var.enable_firewall)
        allowedValues = ["true", "false"]
      }
      disableRootLogin = {
        type        = "String"
        description = "Disable root SSH login"
        default     = tostring(var.disable_root_login)
        allowedValues = ["true", "false"]
      }
    }
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "configureFirewall"
        precondition = {
          StringEquals = ["platformType", "Linux"]
        }
        inputs = {
          runCommand = [
            "#!/bin/bash",
            "if [ '{{ enableFirewall }}' == 'true' ]; then",
            "  if command -v ufw &> /dev/null; then",
            "    ufw --force enable",
            "    echo 'UFW firewall enabled'",
            "  elif command -v firewall-cmd &> /dev/null; then",
            "    systemctl enable firewalld",
            "    systemctl start firewalld",
            "    echo 'Firewalld enabled'",
            "  fi",
            "fi"
          ]
        }
      },
      {
        action = "aws:runShellScript"
        name   = "configureSshSecurity"
        precondition = {
          StringEquals = ["platformType", "Linux"]
        }
        inputs = {
          runCommand = [
            "#!/bin/bash",
            "if [ '{{ disableRootLogin }}' == 'true' ]; then",
            "  sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config",
            "  if systemctl is-active --quiet sshd; then",
            "    systemctl reload sshd",
            "  fi",
            "  echo 'Root SSH login disabled'",
            "fi"
          ]
        }
      }
    ]
  })

  tags = {
    Name        = "Security Configuration Document"
    Purpose     = "StateManagerDemo"
    Environment = var.environment
  }
}

# Remediation automation document
resource "aws_ssm_document" "remediation_automation" {
  name          = "AutoRemediation-${random_id.suffix.hex}"
  document_type = "Automation"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "0.3"
    description   = "Automated remediation for configuration drift"
    assumeRole    = "{{ AutomationAssumeRole }}"
    parameters = {
      AutomationAssumeRole = {
        type        = "String"
        description = "The ARN of the role for automation"
      }
      InstanceId = {
        type        = "String"
        description = "The ID of the non-compliant instance"
      }
      AssociationId = {
        type        = "String"
        description = "The ID of the failed association"
      }
    }
    mainSteps = [
      {
        name   = "RerunAssociation"
        action = "aws:executeAwsApi"
        inputs = {
          Service = "ssm"
          Api     = "StartAssociationsOnce"
          AssociationIds = ["{{ AssociationId }}"]
        }
      },
      {
        name   = "WaitForCompletion"
        action = "aws:waitForAwsResourceProperty"
        inputs = {
          Service          = "ssm"
          Api              = "DescribeAssociationExecutions"
          AssociationId    = "{{ AssociationId }}"
          PropertySelector = "$.AssociationExecutions[0].Status"
          DesiredValues    = ["Success"]
        }
        timeoutSeconds = 300
      },
      {
        name   = "SendNotification"
        action = "aws:executeAwsApi"
        inputs = {
          Service  = "sns"
          Api      = "Publish"
          TopicArn = aws_sns_topic.config_drift_alerts.arn
          Message  = "Configuration drift remediation completed for instance {{ InstanceId }}"
        }
      }
    ]
  })

  tags = {
    Name        = "Remediation Automation Document"
    Purpose     = "StateManagerDemo"
    Environment = var.environment
  }
}

# Compliance report document
resource "aws_ssm_document" "compliance_report" {
  name          = "ComplianceReport-${random_id.suffix.hex}"
  document_type = "Automation"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "0.3"
    description   = "Generate compliance report"
    mainSteps = [
      {
        name   = "GenerateReport"
        action = "aws:executeAwsApi"
        inputs = {
          Service       = "ssm"
          Api           = "ListComplianceItems"
          ResourceTypes = ["ManagedInstance"]
          Filters = [
            {
              Key    = "ComplianceType"
              Values = ["Association"]
            }
          ]
        }
      }
    ]
  })

  tags = {
    Name        = "Compliance Report Document"
    Purpose     = "StateManagerDemo"
    Environment = var.environment
  }
}

# ==============================================================================
# State Manager Associations
# ==============================================================================

# Association for SSM Agent updates
resource "aws_ssm_association" "agent_update" {
  name                = "AWS-UpdateSSMAgent"
  association_name    = "ConfigManagement-SSMAgent-${random_id.suffix.hex}"
  schedule_expression = var.agent_update_schedule

  targets {
    key    = "tag:${var.target_tag_key}"
    values = [var.target_tag_value]
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.state_manager_output.bucket
    s3_key_prefix  = "agent-updates/"
    s3_region      = var.aws_region
  }

  depends_on = [
    aws_iam_role_policy_attachment.state_manager_custom_policy,
    aws_iam_role_policy_attachment.state_manager_managed_policy
  ]
}

# Association for security configuration
resource "aws_ssm_association" "security_configuration" {
  name                = aws_ssm_document.security_configuration.name
  association_name    = "ConfigManagement-Security-${random_id.suffix.hex}"
  schedule_expression = var.association_schedule
  compliance_severity = var.compliance_severity

  targets {
    key    = "tag:${var.target_tag_key}"
    values = [var.target_tag_value]
  }

  parameters = {
    enableFirewall   = tostring(var.enable_firewall)
    disableRootLogin = tostring(var.disable_root_login)
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.state_manager_output.bucket
    s3_key_prefix  = "security-config/"
    s3_region      = var.aws_region
  }

  depends_on = [
    aws_iam_role_policy_attachment.state_manager_custom_policy,
    aws_iam_role_policy_attachment.state_manager_managed_policy
  ]
}

# ==============================================================================
# CloudWatch Alarms for Monitoring
# ==============================================================================

# CloudWatch alarm for association failures
resource "aws_cloudwatch_metric_alarm" "association_failures" {
  alarm_name          = "SSM-Association-Failures-${random_id.suffix.hex}"
  alarm_description   = "Monitor SSM association failures"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "AssociationExecutionsFailed"
  namespace           = "AWS/SSM"
  period              = var.cloudwatch_alarm_period
  statistic           = "Sum"
  threshold           = var.cloudwatch_alarm_threshold
  alarm_actions       = [aws_sns_topic.config_drift_alerts.arn]

  dimensions = {
    AssociationName = aws_ssm_association.security_configuration.association_name
  }

  tags = {
    Name        = "Association Failures Alarm"
    Purpose     = "StateManagerDemo"
    Environment = var.environment
  }
}

# CloudWatch alarm for compliance violations
resource "aws_cloudwatch_metric_alarm" "compliance_violations" {
  alarm_name          = "SSM-Compliance-Violations-${random_id.suffix.hex}"
  alarm_description   = "Monitor compliance violations"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ComplianceByConfigRule"
  namespace           = "AWS/SSM"
  period              = var.cloudwatch_alarm_period
  statistic           = "Sum"
  threshold           = var.cloudwatch_alarm_threshold
  alarm_actions       = [aws_sns_topic.config_drift_alerts.arn]

  tags = {
    Name        = "Compliance Violations Alarm"
    Purpose     = "StateManagerDemo"
    Environment = var.environment
  }
}

# ==============================================================================
# CloudWatch Dashboard
# ==============================================================================

resource "aws_cloudwatch_dashboard" "state_manager_dashboard" {
  dashboard_name = "SSM-StateManager-${random_id.suffix.hex}"

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
            ["AWS/SSM", "AssociationExecutionsSucceeded", "AssociationName", aws_ssm_association.security_configuration.association_name],
            [".", "AssociationExecutionsFailed", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Association Execution Status"
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
            ["AWS/SSM", "ComplianceByConfigRule", "RuleName", aws_ssm_association.security_configuration.association_name, "ComplianceType", "Association"]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Compliance Status"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          query   = "SOURCE '${aws_cloudwatch_log_group.state_manager_logs.name}' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          region  = var.aws_region
          title   = "State Manager Logs"
          view    = "table"
        }
      }
    ]
  })
}

# ==============================================================================
# Test EC2 Instances (Optional)
# ==============================================================================

# Security group for test instances
resource "aws_security_group" "test_instances" {
  count = var.create_test_instances ? 1 : 0

  name_prefix = "ssm-test-instances-${random_id.suffix.hex}"
  description = "Security group for SSM test instances"
  vpc_id      = data.aws_vpc.default.id

  # Allow SSM traffic
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow DNS
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP/HTTPS for package updates
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "SSM Test Instances Security Group"
    Purpose     = "StateManagerDemo"
    Environment = var.environment
  }
}

# IAM role for test instances
resource "aws_iam_role" "test_instance_role" {
  count = var.create_test_instances ? 1 : 0

  name = "SSMTestInstanceRole-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "SSM Test Instance Role"
    Purpose     = "StateManagerDemo"
    Environment = var.environment
  }
}

# Instance profile for test instances
resource "aws_iam_instance_profile" "test_instance_profile" {
  count = var.create_test_instances ? 1 : 0

  name = "SSMTestInstanceProfile-${random_id.suffix.hex}"
  role = aws_iam_role.test_instance_role[0].name
}

# Attach SSM managed policy to test instance role
resource "aws_iam_role_policy_attachment" "test_instance_ssm_policy" {
  count = var.create_test_instances ? 1 : 0

  role       = aws_iam_role.test_instance_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Test EC2 instances
resource "aws_instance" "test_instances" {
  count = var.create_test_instances ? var.test_instance_count : 0

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.test_instance_type
  subnet_id              = data.aws_subnets.default.ids[count.index % length(data.aws_subnets.default.ids)]
  vpc_security_group_ids = [aws_security_group.test_instances[0].id]
  iam_instance_profile   = aws_iam_instance_profile.test_instance_profile[0].name

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
  EOF
  )

  tags = {
    Name                    = "SSM-Test-Instance-${count.index + 1}-${random_id.suffix.hex}"
    Purpose                 = "StateManagerDemo"
    Environment             = var.environment
    "${var.target_tag_key}" = var.target_tag_value
  }
}