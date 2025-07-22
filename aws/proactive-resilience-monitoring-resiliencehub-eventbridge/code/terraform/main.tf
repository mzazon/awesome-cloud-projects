# AWS Resilience Hub and EventBridge Proactive Monitoring Infrastructure
# This Terraform configuration creates a comprehensive resilience monitoring solution
# that automatically responds to resilience assessment changes using EventBridge and Lambda

# Local values for consistent naming and tagging
locals {
  name_prefix = var.name_prefix
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = "resilience-monitoring"
    ManagedBy   = "terraform"
  })
}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data sources for existing resources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

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

#------------------------------------------------------------------------------
# VPC and Networking Infrastructure
#------------------------------------------------------------------------------

# VPC for sample application
resource "aws_vpc" "demo_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-resilience-demo-vpc"
  })
}

# Internet Gateway for public subnet access
resource "aws_internet_gateway" "demo_igw" {
  vpc_id = aws_vpc.demo_vpc.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-resilience-demo-igw"
  })
}

# Public subnet in first AZ
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.demo_vpc.id
  cidr_block              = var.public_subnet_1_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-resilience-demo-subnet-1"
    Type = "Public"
  })
}

# Private subnet in second AZ (for RDS Multi-AZ)
resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.demo_vpc.id
  cidr_block        = var.private_subnet_2_cidr
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-resilience-demo-subnet-2"
    Type = "Private"
  })
}

# Route table for public subnet
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.demo_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo_igw.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-route-table"
  })
}

# Associate public subnet with route table
resource "aws_route_table_association" "public_rta_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}

# Security group for demo application
resource "aws_security_group" "demo_sg" {
  name        = "${local.name_prefix}-resilience-demo-sg"
  description = "Security group for resilience monitoring demo"
  vpc_id      = aws_vpc.demo_vpc.id

  # MySQL access from within VPC
  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    self      = true
  }

  # HTTP access for application
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS access for application
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH access (restricted to specific CIDR if provided)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidr != "" ? [var.allowed_ssh_cidr] : []
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-resilience-demo-sg"
  })
}

#------------------------------------------------------------------------------
# IAM Roles and Policies
#------------------------------------------------------------------------------

# IAM role for automation workflows
resource "aws_iam_role" "automation_role" {
  name = "${local.name_prefix}-ResilienceAutomationRole-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "ssm.amazonaws.com",
            "lambda.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# Attach managed policies to automation role
resource "aws_iam_role_policy_attachment" "automation_ssm" {
  role       = aws_iam_role.automation_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMAutomationRole"
}

resource "aws_iam_role_policy_attachment" "automation_lambda" {
  role       = aws_iam_role.automation_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "automation_cloudwatch" {
  role       = aws_iam_role.automation_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Additional custom policy for resilience monitoring
resource "aws_iam_role_policy" "resilience_monitoring_policy" {
  name = "${local.name_prefix}-resilience-monitoring-policy"
  role = aws_iam_role.automation_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "sns:Publish",
          "ssm:StartAutomationExecution",
          "ssm:GetAutomationExecution",
          "ssm:DescribeAutomationExecutions",
          "resiliencehub:DescribeApp",
          "resiliencehub:DescribeAppAssessment",
          "resiliencehub:ListAppAssessments"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM instance profile for EC2 instances
data "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "AmazonSSMRoleForInstancesQuickSetup"
}

#------------------------------------------------------------------------------
# Sample Application Infrastructure
#------------------------------------------------------------------------------

# EC2 instance for demo application
resource "aws_instance" "demo_instance" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public_subnet_1.id
  vpc_security_group_ids = [aws_security_group.demo_sg.id]
  iam_instance_profile   = data.aws_iam_instance_profile.ssm_instance_profile.name

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    region = data.aws_region.current.name
  }))

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-resilience-demo-instance"
    Environment = var.environment
  })

  depends_on = [aws_internet_gateway.demo_igw]
}

# DB subnet group for RDS
resource "aws_db_subnet_group" "demo_subnet_group" {
  name       = "${local.name_prefix}-resilience-demo-subnet-group"
  subnet_ids = [aws_subnet.public_subnet_1.id, aws_subnet.private_subnet_2.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-resilience-demo-subnet-group"
  })
}

# RDS instance with Multi-AZ deployment
resource "aws_db_instance" "demo_db" {
  identifier                = "${local.name_prefix}-resilience-demo-db"
  engine                    = "mysql"
  engine_version            = var.mysql_version
  instance_class            = var.db_instance_class
  allocated_storage         = 20
  storage_encrypted         = true
  multi_az                  = true
  auto_minor_version_upgrade = true

  db_name  = var.database_name
  username = var.database_username
  password = var.database_password

  vpc_security_group_ids = [aws_security_group.demo_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.demo_subnet_group.name

  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"

  skip_final_snapshot = true
  deletion_protection = false

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-resilience-demo-db"
    Purpose     = "resilience-testing"
    Environment = var.environment
  })
}

#------------------------------------------------------------------------------
# AWS Resilience Hub Configuration
#------------------------------------------------------------------------------

# Resilience policy with mission-critical requirements
resource "aws_resiliencehub_resiliency_policy" "demo_policy" {
  name        = "${local.name_prefix}-resilience-policy-${random_id.suffix.hex}"
  description = "Mission-critical resilience policy for demo application monitoring"
  tier        = "MissionCritical"

  data_location_constraint = "AnyLocation"

  policy {
    # Availability Zone failures - 5 minutes RTO, 1 minute RPO
    az {
      rto = "5m"
      rpo = "1m"
    }

    # Hardware failures - 10 minutes RTO, 5 minutes RPO
    hardware {
      rto = "10m"
      rpo = "5m"
    }

    # Software failures - 5 minutes RTO, 1 minute RPO
    software {
      rto = "5m"
      rpo = "1m"
    }

    # Region failures - 1 hour RTO, 30 minutes RPO
    region {
      rto = "1h"
      rpo = "30m"
    }
  }

  tags = merge(local.common_tags, {
    Purpose = "resilience-monitoring"
  })
}

# Note: AWS Resilience Hub application registration would typically be done
# through the console or AWS CLI as it requires CloudFormation template
# or Terraform state analysis. For production use, consider using:
# aws resiliencehub create-app and aws resiliencehub import-resources-to-draft-app-version

#------------------------------------------------------------------------------
# Lambda Function for Event Processing
#------------------------------------------------------------------------------

# Lambda function code
resource "local_file" "lambda_code" {
  content = templatefile("${path.module}/lambda_function.py", {
    region = data.aws_region.current.name
  })
  filename = "${path.module}/lambda_function.py"
}

# Create ZIP file for Lambda deployment
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_code.filename
  output_path = "${path.module}/lambda_function.zip"
  depends_on  = [local_file.lambda_code]
}

# Lambda function for resilience event processing
resource "aws_lambda_function" "resilience_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.name_prefix}-resilience-processor-${random_id.suffix.hex}"
  role            = aws_iam_role.automation_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = 60
  memory_size     = 256

  environment {
    variables = {
      LOG_LEVEL = "INFO"
      SNS_TOPIC_ARN = aws_sns_topic.resilience_alerts.arn
    }
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-resilience-processor"
    Purpose = "event-processing"
  })

  depends_on = [
    aws_iam_role_policy_attachment.automation_lambda,
    aws_cloudwatch_log_group.lambda_logs
  ]
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.name_prefix}-resilience-processor-${random_id.suffix.hex}"
  retention_in_days = var.log_retention_days

  tags = local.common_tags
}

#------------------------------------------------------------------------------
# EventBridge Configuration
#------------------------------------------------------------------------------

# EventBridge rule for Resilience Hub events
resource "aws_cloudwatch_event_rule" "resilience_assessment_rule" {
  name        = "${local.name_prefix}-ResilienceHubAssessmentRule"
  description = "Comprehensive rule for Resilience Hub assessment events"
  state       = "ENABLED"

  event_pattern = jsonencode({
    source = ["aws.resiliencehub"]
    detail-type = [
      "Resilience Assessment State Change",
      "Application Assessment Completed",
      "Policy Compliance Change"
    ]
    detail = {
      state = [
        "ASSESSMENT_COMPLETED",
        "ASSESSMENT_FAILED",
        "ASSESSMENT_IN_PROGRESS"
      ]
    }
  })

  tags = local.common_tags
}

# EventBridge target for Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.resilience_assessment_rule.name
  target_id = "ResilienceLambdaTarget"
  arn       = aws_lambda_function.resilience_processor.arn

  input_transformer {
    input_paths = {
      app    = "$.detail.applicationName"
      status = "$.detail.state"
      score  = "$.detail.resilienceScore"
    }
    input_template = jsonencode({
      applicationName  = "<app>"
      assessmentStatus = "<status>"
      resilienceScore  = "<score>"
    })
  }
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.resilience_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.resilience_assessment_rule.arn
}

#------------------------------------------------------------------------------
# SNS Topic for Alerts
#------------------------------------------------------------------------------

# SNS topic for resilience alerts
resource "aws_sns_topic" "resilience_alerts" {
  name = "${local.name_prefix}-resilience-alerts"

  tags = merge(local.common_tags, {
    Purpose = "alerting"
  })
}

# SNS topic policy for EventBridge access
resource "aws_sns_topic_policy" "resilience_alerts_policy" {
  arn = aws_sns_topic.resilience_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.resilience_alerts.arn
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.resilience_alerts.arn
      }
    ]
  })
}

# Optional email subscription for alerts (if email provided)
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.resilience_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

#------------------------------------------------------------------------------
# CloudWatch Dashboard and Alarms
#------------------------------------------------------------------------------

# CloudWatch dashboard for resilience monitoring
resource "aws_cloudwatch_dashboard" "resilience_dashboard" {
  dashboard_name = "${local.name_prefix}-Application-Resilience-Monitoring"

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
            ["ResilienceHub/Monitoring", "ResilienceScore", "ApplicationName", var.app_name]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Application Resilience Score Trend"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
          annotations = {
            horizontal = [
              {
                value = 80
                label = "Critical Threshold"
              }
            ]
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
            ["ResilienceHub/Monitoring", "AssessmentEvents", "ApplicationName", var.app_name, "Status", "ASSESSMENT_COMPLETED"],
            [".", ".", ".", ".", ".", "ASSESSMENT_FAILED"],
            [".", "ProcessingErrors"]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Assessment Events and Processing Status"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          query  = "SOURCE '/aws/lambda/${aws_lambda_function.resilience_processor.function_name}' | fields @timestamp, @message\n| filter @message like /resilience/\n| sort @timestamp desc\n| limit 50"
          region = data.aws_region.current.name
          title  = "Recent Resilience Events and Processing Logs"
        }
      }
    ]
  })
}

# CloudWatch alarms for resilience monitoring
resource "aws_cloudwatch_metric_alarm" "critical_low_resilience" {
  alarm_name          = "${local.name_prefix}-Critical-Low-Resilience-Score"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ResilienceScore"
  namespace           = "ResilienceHub/Monitoring"
  period              = "300"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "Critical alert when resilience score drops below 70%"
  alarm_actions       = [aws_sns_topic.resilience_alerts.arn]
  ok_actions          = [aws_sns_topic.resilience_alerts.arn]

  dimensions = {
    ApplicationName = var.app_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "warning_low_resilience" {
  alarm_name          = "${local.name_prefix}-Warning-Low-Resilience-Score"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  datapoints_to_alarm = "2"
  metric_name         = "ResilienceScore"
  namespace           = "ResilienceHub/Monitoring"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Warning when resilience score drops below 80%"
  alarm_actions       = [aws_sns_topic.resilience_alerts.arn]

  dimensions = {
    ApplicationName = var.app_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "assessment_failures" {
  alarm_name          = "${local.name_prefix}-Resilience-Assessment-Failures"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "AssessmentEvents"
  namespace           = "ResilienceHub/Monitoring"
  period              = "300"
  statistic           = "Sum"
  threshold           = "2"
  alarm_description   = "Alert when resilience assessments fail repeatedly"
  alarm_actions       = [aws_sns_topic.resilience_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApplicationName = var.app_name
    Status         = "ASSESSMENT_FAILED"
  }

  tags = local.common_tags
}