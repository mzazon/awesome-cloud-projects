# AWS Elastic Disaster Recovery (DRS) Automation Infrastructure
# This Terraform configuration deploys a complete cross-region disaster recovery solution
# using AWS Elastic Disaster Recovery with automated failover capabilities

terraform {
  required_version = ">= 1.0"
}

# Data sources for current AWS account and regions
data "aws_caller_identity" "current" {}
data "aws_region" "primary" {}
data "aws_region" "dr" {
  provider = aws.disaster_recovery
}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

locals {
  account_id            = data.aws_caller_identity.current.account_id
  primary_region        = data.aws_region.primary.name
  dr_region            = data.aws_region.dr.name
  project_name         = "enterprise-dr-${random_string.suffix.result}"
  dr_vpc_name          = "disaster-recovery-vpc-${random_string.suffix.result}"
  automation_role_name = "DRAutomationRole-${random_string.suffix.result}"
  
  common_tags = merge(var.tags, {
    Project             = local.project_name
    Purpose             = "DisasterRecovery"
    Environment         = var.environment
    ManagedBy          = "Terraform"
    CreatedDate        = formatdate("YYYY-MM-DD", timestamp())
  })
}

# ===================================================================
# DRS Service Initialization and Configuration
# ===================================================================

# Initialize DRS service in primary region
resource "aws_drs_replication_configuration_template" "primary" {
  associate_default_security_group = true
  bandwidth_throttling             = var.replication_bandwidth_throttling
  create_public_ip                 = var.create_public_ip
  data_plane_routing              = var.data_plane_routing
  default_large_staging_disk_type = var.staging_disk_type
  ebs_encryption                  = var.ebs_encryption
  replication_server_instance_type = var.replication_server_instance_type
  replication_servers_security_groups_ids = [aws_security_group.drs_replication.id]
  staging_area_subnet_id          = aws_subnet.dr_private.id
  use_dedicated_replication_server = var.use_dedicated_replication_server

  staging_area_tags = local.common_tags

  depends_on = [aws_subnet.dr_private, aws_security_group.drs_replication]
}

# ===================================================================
# DR Region VPC Infrastructure
# ===================================================================

# VPC for disaster recovery environment
resource "aws_vpc" "dr_vpc" {
  provider = aws.disaster_recovery
  
  cidr_block           = var.dr_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = local.dr_vpc_name
  })
}

# Public subnet for DR environment
resource "aws_subnet" "dr_public" {
  provider = aws.disaster_recovery
  
  vpc_id                  = aws_vpc.dr_vpc.id
  cidr_block              = var.dr_public_subnet_cidr
  availability_zone       = "${local.dr_region}a"
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "DR-Public-Subnet-${random_string.suffix.result}"
    Type = "Public"
  })
}

# Private subnet for DR environment
resource "aws_subnet" "dr_private" {
  provider = aws.disaster_recovery
  
  vpc_id            = aws_vpc.dr_vpc.id
  cidr_block        = var.dr_private_subnet_cidr
  availability_zone = "${local.dr_region}a"

  tags = merge(local.common_tags, {
    Name = "DR-Private-Subnet-${random_string.suffix.result}"
    Type = "Private"
  })
}

# Internet Gateway for DR VPC
resource "aws_internet_gateway" "dr_igw" {
  provider = aws.disaster_recovery
  
  vpc_id = aws_vpc.dr_vpc.id

  tags = merge(local.common_tags, {
    Name = "DR-IGW-${random_string.suffix.result}"
  })
}

# Route table for public subnet
resource "aws_route_table" "dr_public" {
  provider = aws.disaster_recovery
  
  vpc_id = aws_vpc.dr_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.dr_igw.id
  }

  tags = merge(local.common_tags, {
    Name = "DR-Public-RT-${random_string.suffix.result}"
  })
}

# Route table association for public subnet
resource "aws_route_table_association" "dr_public" {
  provider = aws.disaster_recovery
  
  subnet_id      = aws_subnet.dr_public.id
  route_table_id = aws_route_table.dr_public.id
}

# ===================================================================
# Security Groups
# ===================================================================

# Security group for DRS replication servers
resource "aws_security_group" "drs_replication" {
  provider = aws.disaster_recovery
  
  name_prefix = "drs-replication-${random_string.suffix.result}"
  description = "Security group for DRS replication servers"
  vpc_id      = aws_vpc.dr_vpc.id

  ingress {
    description = "DRS replication traffic"
    from_port   = 1500
    to_port     = 1500
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "DRS-Replication-SG-${random_string.suffix.result}"
  })
}

# Security group for recovery instances
resource "aws_security_group" "dr_instances" {
  provider = aws.disaster_recovery
  
  name_prefix = "dr-instances-${random_string.suffix.result}"
  description = "Security group for DR recovery instances"
  vpc_id      = aws_vpc.dr_vpc.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.dr_vpc_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "DR-Instances-SG-${random_string.suffix.result}"
  })
}

# ===================================================================
# IAM Roles and Policies
# ===================================================================

# Trust policy document for automation services
data "aws_iam_policy_document" "dr_automation_trust" {
  statement {
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = [
        "lambda.amazonaws.com",
        "ssm.amazonaws.com",
        "states.amazonaws.com"
      ]
    }
    actions = ["sts:AssumeRole"]
  }
}

# IAM role for DR automation
resource "aws_iam_role" "dr_automation" {
  name               = local.automation_role_name
  assume_role_policy = data.aws_iam_policy_document.dr_automation_trust.json
  description        = "Role for disaster recovery automation"

  tags = local.common_tags
}

# Policy document for DR automation permissions
data "aws_iam_policy_document" "dr_automation_policy" {
  statement {
    effect = "Allow"
    actions = [
      "drs:*",
      "ec2:*",
      "iam:PassRole",
      "route53:*",
      "sns:*",
      "ssm:*",
      "lambda:*",
      "logs:*",
      "cloudwatch:*",
      "states:*"
    ]
    resources = ["*"]
  }
}

# IAM policy for DR automation
resource "aws_iam_role_policy" "dr_automation" {
  name   = "DRAutomationPolicy"
  role   = aws_iam_role.dr_automation.id
  policy = data.aws_iam_policy_document.dr_automation_policy.json
}

# ===================================================================
# SNS Topic for Notifications
# ===================================================================

# SNS topic for DR alerts and notifications
resource "aws_sns_topic" "dr_alerts" {
  name = "dr-alerts-${random_string.suffix.result}"

  tags = local.common_tags
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "dr_email" {
  count = var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.dr_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ===================================================================
# Lambda Functions for DR Automation
# ===================================================================

# Lambda function package for automated failover
data "archive_file" "failover_lambda" {
  type        = "zip"
  output_path = "${path.module}/failover_lambda.zip"
  source {
    content = templatefile("${path.module}/lambda_functions/automated_failover.py", {
      dr_region       = local.dr_region
      sns_topic_arn   = aws_sns_topic.dr_alerts.arn
    })
    filename = "lambda_function.py"
  }
}

# Automated failover Lambda function
resource "aws_lambda_function" "automated_failover" {
  filename         = data.archive_file.failover_lambda.output_path
  function_name    = "dr-automated-failover-${random_string.suffix.result}"
  role            = aws_iam_role.dr_automation.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = 300
  source_code_hash = data.archive_file.failover_lambda.output_base64sha256

  environment {
    variables = {
      DR_REGION     = local.dr_region
      SNS_TOPIC_ARN = aws_sns_topic.dr_alerts.arn
    }
  }

  tags = local.common_tags

  depends_on = [aws_iam_role_policy.dr_automation]
}

# Lambda function package for DR testing
data "archive_file" "testing_lambda" {
  type        = "zip"
  output_path = "${path.module}/testing_lambda.zip"
  source {
    content = templatefile("${path.module}/lambda_functions/dr_testing.py", {
      dr_region = local.dr_region
    })
    filename = "lambda_function.py"
  }
}

# DR testing Lambda function
resource "aws_lambda_function" "dr_testing" {
  filename         = data.archive_file.testing_lambda.output_path
  function_name    = "dr-testing-${random_string.suffix.result}"
  role            = aws_iam_role.dr_automation.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = 300
  source_code_hash = data.archive_file.testing_lambda.output_base64sha256

  environment {
    variables = {
      DR_REGION = local.dr_region
    }
  }

  tags = local.common_tags

  depends_on = [aws_iam_role_policy.dr_automation]
}

# Lambda function package for automated failback
data "archive_file" "failback_lambda" {
  type        = "zip"
  output_path = "${path.module}/failback_lambda.zip"
  source {
    content = templatefile("${path.module}/lambda_functions/automated_failback.py", {
      primary_region = local.primary_region
    })
    filename = "lambda_function.py"
  }
}

# Automated failback Lambda function (deployed in DR region)
resource "aws_lambda_function" "automated_failback" {
  provider = aws.disaster_recovery
  
  filename         = data.archive_file.failback_lambda.output_path
  function_name    = "dr-automated-failback-${random_string.suffix.result}"
  role            = "arn:aws:iam::${local.account_id}:role/${local.automation_role_name}"
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = 300
  source_code_hash = data.archive_file.failback_lambda.output_base64sha256

  environment {
    variables = {
      PRIMARY_REGION = local.primary_region
    }
  }

  tags = local.common_tags

  depends_on = [aws_iam_role_policy.dr_automation]
}

# ===================================================================
# Step Functions State Machine for DR Orchestration
# ===================================================================

# Step Functions state machine definition
data "aws_iam_policy_document" "dr_state_machine" {
  statement {
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = [
      aws_lambda_function.automated_failover.arn,
      aws_lambda_function.dr_testing.arn
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "drs:*",
      "route53:*",
      "sns:Publish"
    ]
    resources = ["*"]
  }
}

# Step Functions state machine for DR orchestration
resource "aws_sfn_state_machine" "dr_orchestration" {
  name     = "dr-orchestration-${random_string.suffix.result}"
  role_arn = aws_iam_role.dr_automation.arn

  definition = templatefile("${path.module}/step_functions/dr_orchestration.json", {
    failover_lambda_arn = aws_lambda_function.automated_failover.arn
    sns_topic_arn      = aws_sns_topic.dr_alerts.arn
    primary_region     = local.primary_region
    account_id         = local.account_id
    project_id         = random_string.suffix.result
  })

  tags = local.common_tags

  depends_on = [aws_iam_role_policy.dr_automation]
}

# ===================================================================
# CloudWatch Alarms and Monitoring
# ===================================================================

# CloudWatch alarm for application health monitoring
resource "aws_cloudwatch_metric_alarm" "application_health" {
  alarm_name          = "Application-Health-${random_string.suffix.result}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_description   = "Monitor application health for DR trigger"
  alarm_actions       = [aws_sns_topic.dr_alerts.arn]
  treat_missing_data  = "breaching"

  tags = local.common_tags
}

# CloudWatch alarm for DRS replication lag monitoring
resource "aws_cloudwatch_metric_alarm" "drs_replication_lag" {
  alarm_name          = "DRS-Replication-Lag-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReplicationLag"
  namespace           = "Custom/DRS"
  period              = "300"
  statistic           = "Average"
  threshold           = "300"
  alarm_description   = "Monitor DRS replication lag"
  alarm_actions       = [aws_sns_topic.dr_alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = local.common_tags
}

# CloudWatch dashboard for DR monitoring
resource "aws_cloudwatch_dashboard" "dr_monitoring" {
  dashboard_name = "DR-Monitoring-${random_string.suffix.result}"

  dashboard_body = templatefile("${path.module}/cloudwatch/dashboard.json", {
    primary_region = local.primary_region
    project_id     = random_string.suffix.result
  })
}

# ===================================================================
# EventBridge Rules for Automated DR Testing
# ===================================================================

# EventBridge rule for monthly DR testing
resource "aws_cloudwatch_event_rule" "monthly_dr_drill" {
  name                = "monthly-dr-drill-${random_string.suffix.result}"
  description         = "Monthly automated DR drill"
  schedule_expression = var.dr_test_schedule

  tags = local.common_tags
}

# EventBridge target for DR testing Lambda
resource "aws_cloudwatch_event_target" "dr_testing_target" {
  rule      = aws_cloudwatch_event_rule.monthly_dr_drill.name
  target_id = "DRTestingTarget"
  arn       = aws_lambda_function.dr_testing.arn
}

# Lambda permission for EventBridge to invoke DR testing function
resource "aws_lambda_permission" "allow_eventbridge_dr_testing" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dr_testing.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.monthly_dr_drill.arn
}

# ===================================================================
# SSM Parameters for Configuration Management
# ===================================================================

# SSM parameter for DR project configuration
resource "aws_ssm_parameter" "dr_project_config" {
  name  = "/dr/${local.project_name}/config"
  type  = "String"
  value = jsonencode({
    project_name    = local.project_name
    primary_region  = local.primary_region
    dr_region       = local.dr_region
    dr_vpc_id       = aws_vpc.dr_vpc.id
    automation_role = aws_iam_role.dr_automation.arn
    sns_topic       = aws_sns_topic.dr_alerts.arn
  })
  description = "DR project configuration parameters"

  tags = local.common_tags
}

# SSM parameter for DRS replication template ID
resource "aws_ssm_parameter" "drs_template_id" {
  name        = "/dr/${local.project_name}/drs-template-id"
  type        = "String"
  value       = aws_drs_replication_configuration_template.primary.id
  description = "DRS replication configuration template ID"

  tags = local.common_tags
}