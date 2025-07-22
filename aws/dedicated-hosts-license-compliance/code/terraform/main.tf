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
  # Common naming convention
  name_prefix = "${var.project_name}-${random_id.suffix.hex}"
  
  # Common tags for all resources
  common_tags = merge(var.additional_tags, {
    LicenseCompliance = "BYOL-Production"
    ProjectName      = var.project_name
    Environment      = var.environment
  })
  
  # Account and region information
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# ========================================
# SNS Topic for Compliance Notifications
# ========================================

resource "aws_sns_topic" "compliance_alerts" {
  name         = "${local.name_prefix}-compliance-alerts"
  display_name = "License Compliance Alerts"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-compliance-alerts"
    Purpose = "compliance-notifications"
  })
}

# SNS topic subscription for email notifications (if email provided)
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.compliance_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ========================================
# License Manager Configurations
# ========================================

# Windows Server license configuration
resource "aws_licensemanager_license_configuration" "windows_server" {
  name                     = "${local.name_prefix}-windows-server"
  description             = "Windows Server BYOL license tracking"
  license_counting_type   = "Socket"
  license_count          = var.windows_license_count
  license_count_hard_limit = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-windows-server"
    Purpose = "WindowsServer"
    LicenseType = "Socket-based"
  })
}

# Oracle Enterprise Edition license configuration
resource "aws_licensemanager_license_configuration" "oracle_enterprise" {
  name                     = "${local.name_prefix}-oracle-enterprise"
  description             = "Oracle Enterprise Edition BYOL license tracking"
  license_counting_type   = "Core"
  license_count          = var.oracle_license_count
  license_count_hard_limit = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-oracle-enterprise"
    Purpose = "OracleDB"
    LicenseType = "Core-based"
  })
}

# ========================================
# S3 Buckets for Reports and Config
# ========================================

# S3 bucket for License Manager reports
resource "aws_s3_bucket" "license_reports" {
  bucket        = "${local.name_prefix}-reports-${local.account_id}"
  force_destroy = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-reports"
    Purpose = "license-manager-reports"
  })
}

resource "aws_s3_bucket_versioning" "license_reports" {
  bucket = aws_s3_bucket.license_reports.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "license_reports" {
  bucket = aws_s3_bucket.license_reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "license_reports" {
  bucket = aws_s3_bucket.license_reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket policy for License Manager access
resource "aws_s3_bucket_policy" "license_reports" {
  bucket = aws_s3_bucket.license_reports.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LicenseManagerReportAccess"
        Effect = "Allow"
        Principal = {
          Service = "license-manager.amazonaws.com"
        }
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          aws_s3_bucket.license_reports.arn,
          "${aws_s3_bucket.license_reports.arn}/*"
        ]
      }
    ]
  })
}

# S3 bucket for AWS Config (if enabled)
resource "aws_s3_bucket" "config_bucket" {
  count         = var.enable_config ? 1 : 0
  bucket        = "${local.name_prefix}-config-${local.account_id}"
  force_destroy = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-config"
    Purpose = "aws-config-delivery"
  })
}

resource "aws_s3_bucket_versioning" "config_bucket" {
  count  = var.enable_config ? 1 : 0
  bucket = aws_s3_bucket.config_bucket[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config_bucket" {
  count  = var.enable_config ? 1 : 0
  bucket = aws_s3_bucket.config_bucket[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "config_bucket" {
  count  = var.enable_config ? 1 : 0
  bucket = aws_s3_bucket.config_bucket[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ========================================
# IAM Roles and Policies
# ========================================

# IAM role for AWS Config
resource "aws_iam_role" "config_role" {
  count = var.enable_config ? 1 : 0
  name  = "${local.name_prefix}-config-role"

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
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-config-role"
    Purpose = "aws-config-service"
  })
}

# Attach AWS managed policy to Config role
resource "aws_iam_role_policy_attachment" "config_role" {
  count      = var.enable_config ? 1 : 0
  role       = aws_iam_role.config_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/ConfigRole"
}

# IAM role for Lambda compliance reporting
resource "aws_iam_role" "lambda_compliance_role" {
  name = "${local.name_prefix}-lambda-compliance-role"

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
    Name = "${local.name_prefix}-lambda-compliance-role"
    Purpose = "lambda-execution"
  })
}

# IAM policy for Lambda compliance function
resource "aws_iam_role_policy" "lambda_compliance_policy" {
  name = "${local.name_prefix}-lambda-compliance-policy"
  role = aws_iam_role.lambda_compliance_role.id

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
          "license-manager:ListLicenseConfigurations",
          "license-manager:ListUsageForLicenseConfiguration",
          "license-manager:GetLicenseConfiguration"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeHosts",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.compliance_alerts.arn
      }
    ]
  })
}

# IAM role for EC2 instances with Systems Manager
resource "aws_iam_role" "ec2_ssm_role" {
  name = "${local.name_prefix}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ec2-ssm-role"
    Purpose = "ec2-systems-manager"
  })
}

# Attach AWS managed policy for Systems Manager
resource "aws_iam_role_policy_attachment" "ec2_ssm_role" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile for EC2 instances
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2_ssm_role.name
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ec2-profile"
    Purpose = "ec2-instance-profile"
  })
}

# ========================================
# Security Groups
# ========================================

# Default VPC security group for BYOL instances
resource "aws_security_group" "byol_instances" {
  name        = "${local.name_prefix}-byol-instances"
  description = "Security group for BYOL instances on Dedicated Hosts"

  # Allow RDP access for Windows instances
  ingress {
    description = "RDP access"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  # Allow SSH access for Linux instances
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  # Allow SQL Server access
  ingress {
    description = "SQL Server access"
    from_port   = 1433
    to_port     = 1433
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  # Allow Oracle Database access
  ingress {
    description = "Oracle Database access"
    from_port   = 1521
    to_port     = 1521
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-byol-instances"
    Purpose = "byol-instance-security"
  })
}

# ========================================
# Dedicated Hosts
# ========================================

# Dedicated Hosts for different license types
resource "aws_ec2_host" "dedicated_hosts" {
  for_each = var.dedicated_host_configs

  instance_family   = each.value.instance_family
  availability_zone = "${local.region}${each.value.availability_zone}"
  auto_placement    = each.value.auto_placement
  host_recovery     = each.value.host_recovery

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${each.key}"
    LicenseType = each.value.license_type
    Purpose = each.value.purpose
  })
}

# ========================================
# Launch Templates for BYOL Instances
# ========================================

# Get latest Windows Server AMI
data "aws_ami" "windows_server" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get latest Amazon Linux AMI for Oracle (placeholder - use Oracle AMI in production)
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

# Launch template for Windows Server with SQL Server
resource "aws_launch_template" "windows_sql" {
  name_prefix   = "${local.name_prefix}-windows-sql-"
  description   = "Launch template for Windows Server with SQL Server BYOL"
  image_id      = data.aws_ami.windows_server.id
  instance_type = var.instance_configs.windows_instance.instance_type
  key_name      = var.key_pair_name != "" ? var.key_pair_name : null

  vpc_security_group_ids = [aws_security_group.byol_instances.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  user_data = base64encode(<<-EOF
    <powershell>
    # Install IIS for basic web server capability
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools
    
    # Create a simple test page
    $content = @"
    <html>
    <head><title>BYOL Windows Server</title></head>
    <body>
    <h1>BYOL Windows Server on Dedicated Host</h1>
    <p>This instance is running on a Dedicated Host for license compliance.</p>
    <p>Instance ID: $(Invoke-RestMethod -Uri 'http://169.254.169.254/latest/meta-data/instance-id')</p>
    <p>Server Time: $(Get-Date)</p>
    </body>
    </html>
"@
    $content | Out-File -FilePath "C:\inetpub\wwwroot\index.html" -Encoding UTF8
    </powershell>
    EOF
  )

  placement {
    tenancy = "host"
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-windows-sql"
      LicenseType = "WindowsServer"
      Application = "SQLServer"
      BYOLCompliance = "true"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-windows-sql-template"
    Purpose = "byol-launch-template"
  })
}

# Launch template for Oracle Database
resource "aws_launch_template" "oracle_db" {
  name_prefix   = "${local.name_prefix}-oracle-db-"
  description   = "Launch template for Oracle Database BYOL"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_configs.oracle_instance.instance_type
  key_name      = var.key_pair_name != "" ? var.key_pair_name : null

  vpc_security_group_ids = [aws_security_group.byol_instances.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    
    # Create a simple test page
    cat <<HTML > /var/www/html/index.html
    <html>
    <head><title>BYOL Oracle Database Server</title></head>
    <body>
    <h1>BYOL Oracle Database Server on Dedicated Host</h1>
    <p>This instance is running on a Dedicated Host for license compliance.</p>
    <p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>
    <p>Server Time: $(date)</p>
    <p>Note: Install Oracle Database Enterprise Edition here for production use.</p>
    </body>
    </html>
HTML
    EOF
  )

  placement {
    tenancy = "host"
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-oracle-db"
      LicenseType = "Oracle"
      Application = "Database"
      BYOLCompliance = "true"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-oracle-db-template"
    Purpose = "byol-launch-template"
  })
}

# ========================================
# BYOL Instances on Dedicated Hosts
# ========================================

# Windows Server instance
resource "aws_instance" "windows_sql" {
  launch_template {
    id      = aws_launch_template.windows_sql.id
    version = "$Latest"
  }

  placement_group = null
  host_id         = aws_ec2_host.dedicated_hosts["windows_host"].id
  tenancy         = "host"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-windows-sql"
    LicenseType = "WindowsServer"
    Application = "SQLServer"
    BYOLCompliance = "true"
  })

  depends_on = [aws_ec2_host.dedicated_hosts]
}

# Oracle Database instance
resource "aws_instance" "oracle_db" {
  launch_template {
    id      = aws_launch_template.oracle_db.id
    version = "$Latest"
  }

  placement_group = null
  host_id         = aws_ec2_host.dedicated_hosts["oracle_host"].id
  tenancy         = "host"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-oracle-db"
    LicenseType = "Oracle"
    Application = "Database"
    BYOLCompliance = "true"
  })

  depends_on = [aws_ec2_host.dedicated_hosts]
}

# ========================================
# License Configuration Associations
# ========================================

# Associate Windows license with instance
resource "aws_licensemanager_license_configuration_association" "windows_instance" {
  license_configuration_arn = aws_licensemanager_license_configuration.windows_server.arn
  resource_arn             = aws_instance.windows_sql.arn
}

# Associate Oracle license with instance
resource "aws_licensemanager_license_configuration_association" "oracle_instance" {
  license_configuration_arn = aws_licensemanager_license_configuration.oracle_enterprise.arn
  resource_arn             = aws_instance.oracle_db.arn
}

# ========================================
# AWS Config Configuration (Optional)
# ========================================

# AWS Config Configuration Recorder
resource "aws_config_configuration_recorder" "recorder" {
  count    = var.enable_config ? 1 : 0
  name     = "${local.name_prefix}-recorder"
  role_arn = aws_iam_role.config_role[0].arn

  recording_group {
    all_supported                 = false
    include_global_resource_types = false
    resource_types                = ["AWS::EC2::Host", "AWS::EC2::Instance"]
  }

  depends_on = [aws_config_delivery_channel.channel]
}

# AWS Config Delivery Channel
resource "aws_config_delivery_channel" "channel" {
  count           = var.enable_config ? 1 : 0
  name            = "${local.name_prefix}-delivery-channel"
  s3_bucket_name  = aws_s3_bucket.config_bucket[0].id

  snapshot_delivery_properties {
    delivery_frequency = var.config_delivery_frequency
  }
}

# AWS Config Rule for Dedicated Host Compliance
resource "aws_config_config_rule" "host_compliance" {
  count = var.enable_config ? 1 : 0
  name  = "${local.name_prefix}-host-compliance"

  source {
    owner             = "AWS"
    source_identifier = "EC2_DEDICATED_HOST_COMPLIANCE"
  }

  scope {
    compliance_resource_types = ["AWS::EC2::Instance"]
  }

  depends_on = [aws_config_configuration_recorder.recorder]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-host-compliance"
    Purpose = "compliance-monitoring"
  })
}

# ========================================
# CloudWatch Alarms
# ========================================

# CloudWatch alarm for Windows license utilization
resource "aws_cloudwatch_metric_alarm" "windows_license_utilization" {
  alarm_name          = "${local.name_prefix}-windows-license-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "LicenseUtilization"
  namespace           = "AWS/LicenseManager"
  period              = "3600"
  statistic           = "Average"
  threshold           = var.license_utilization_threshold
  alarm_description   = "Monitor Windows Server license utilization threshold"
  alarm_actions       = [aws_sns_topic.compliance_alerts.arn]

  dimensions = {
    LicenseConfigurationArn = aws_licensemanager_license_configuration.windows_server.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-windows-license-alarm"
    Purpose = "license-monitoring"
  })
}

# CloudWatch alarm for Oracle license utilization
resource "aws_cloudwatch_metric_alarm" "oracle_license_utilization" {
  alarm_name          = "${local.name_prefix}-oracle-license-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "LicenseUtilization"
  namespace           = "AWS/LicenseManager"
  period              = "3600"
  statistic           = "Average"
  threshold           = var.license_utilization_threshold
  alarm_description   = "Monitor Oracle Enterprise Edition license utilization threshold"
  alarm_actions       = [aws_sns_topic.compliance_alerts.arn]

  dimensions = {
    LicenseConfigurationArn = aws_licensemanager_license_configuration.oracle_enterprise.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-oracle-license-alarm"
    Purpose = "license-monitoring"
  })
}

# ========================================
# Systems Manager Associations (Optional)
# ========================================

# Systems Manager association for inventory collection
resource "aws_ssm_association" "inventory_collection" {
  count = var.enable_ssm_inventory ? 1 : 0
  name  = "AWS-GatherSoftwareInventory"

  schedule_expression = var.ssm_inventory_schedule

  targets {
    key    = "tag:BYOLCompliance"
    values = ["true"]
  }

  parameters = {
    applications     = "Enabled"
    awsComponents    = "Enabled"
    customInventory  = "Enabled"
    files           = "Enabled"
    networkConfig   = "Enabled"
    services        = "Enabled"
    windowsRegistry = "Enabled"
    windowsRoles    = "Enabled"
    windowsUpdates  = "Enabled"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-inventory-collection"
    Purpose = "systems-manager-inventory"
  })
}

# ========================================
# Lambda Function for Compliance Reporting
# ========================================

# Lambda function for compliance reporting
data "archive_file" "compliance_report_zip" {
  type        = "zip"
  output_path = "/tmp/compliance-report.zip"
  source {
    content = <<EOF
import json
import boto3
import os
from datetime import datetime, timedelta

def lambda_handler(event, context):
    license_manager = boto3.client('license-manager')
    ec2 = boto3.client('ec2')
    sns = boto3.client('sns')
    
    try:
        # Get license configurations
        license_configs = license_manager.list_license_configurations()
        
        compliance_report = {
            'report_date': datetime.now().isoformat(),
            'license_utilization': []
        }
        
        for config in license_configs['LicenseConfigurations']:
            try:
                usage = license_manager.list_usage_for_license_configuration(
                    LicenseConfigurationArn=config['LicenseConfigurationArn']
                )
                
                utilized_count = len(usage['LicenseConfigurationUsageList'])
                total_count = config['LicenseCount']
                utilization_percentage = (utilized_count / total_count) * 100 if total_count > 0 else 0
                
                compliance_report['license_utilization'].append({
                    'license_name': config['Name'],
                    'license_count': total_count,
                    'consumed_licenses': utilized_count,
                    'utilization_percentage': round(utilization_percentage, 2)
                })
            except Exception as e:
                print(f"Error processing license config {config['Name']}: {str(e)}")
        
        # Send compliance report via SNS
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=json.dumps(compliance_report, indent=2),
            Subject='Weekly License Compliance Report'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps('Compliance report generated successfully')
        }
        
    except Exception as e:
        print(f"Error generating compliance report: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
EOF
    filename = "compliance-report-function.py"
  }
}

resource "aws_lambda_function" "compliance_report" {
  filename         = data.archive_file.compliance_report_zip.output_path
  function_name    = "${local.name_prefix}-compliance-report"
  role            = aws_iam_role.lambda_compliance_role.arn
  handler         = "compliance-report-function.lambda_handler"
  source_code_hash = data.archive_file.compliance_report_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = 60

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.compliance_alerts.arn
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-compliance-report"
    Purpose = "compliance-automation"
  })
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.compliance_report.function_name}"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-logs"
    Purpose = "lambda-logging"
  })
}

# EventBridge rule for weekly compliance reports
resource "aws_cloudwatch_event_rule" "weekly_report" {
  name                = "${local.name_prefix}-weekly-compliance-report"
  description         = "Trigger weekly compliance report generation"
  schedule_expression = "cron(0 9 ? * MON *)" # Every Monday at 9 AM UTC

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-weekly-report-rule"
    Purpose = "compliance-scheduling"
  })
}

# EventBridge target for Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.weekly_report.name
  target_id = "ComplianceReportLambdaTarget"
  arn       = aws_lambda_function.compliance_report.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.compliance_report.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weekly_report.arn
}

# ========================================
# CloudWatch Dashboard
# ========================================

resource "aws_cloudwatch_dashboard" "compliance_dashboard" {
  dashboard_name = "${local.name_prefix}-compliance-dashboard"

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
            ["AWS/LicenseManager", "LicenseUtilization", "LicenseConfigurationArn", aws_licensemanager_license_configuration.windows_server.arn],
            ["AWS/LicenseManager", "LicenseUtilization", "LicenseConfigurationArn", aws_licensemanager_license_configuration.oracle_enterprise.arn]
          ]
          period = 3600
          stat   = "Average"
          region = local.region
          title  = "License Utilization"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
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
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.windows_sql.id],
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.oracle_db.id]
          ]
          period = 300
          stat   = "Average"
          region = local.region
          title  = "Instance CPU Utilization"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          metrics = [
            ["AWS/EC2", "NetworkIn", "InstanceId", aws_instance.windows_sql.id],
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.windows_sql.id],
            ["AWS/EC2", "NetworkIn", "InstanceId", aws_instance.oracle_db.id],
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.oracle_db.id]
          ]
          period = 300
          stat   = "Average"
          region = local.region
          title  = "Network Utilization"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-compliance-dashboard"
    Purpose = "compliance-monitoring"
  })
}