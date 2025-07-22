# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for resource naming and configuration
locals {
  suffix = random_id.suffix.hex
  
  # Resource names
  vpc_name          = "${var.project_name}-vpc-${local.suffix}"
  public_subnet_name = "${var.project_name}-public-${local.suffix}"
  private_subnet_name = "${var.project_name}-private-${local.suffix}"
  security_group_name = "${var.project_name}-sg-${local.suffix}"
  
  # Common tags
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    Suffix      = local.suffix
  })
}

# Data sources for AWS account information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Initialize AWS Migration Hub home region
resource "aws_migrationhub_config" "migration_hub_config" {
  home_region = var.aws_region
  target      = data.aws_caller_identity.current.account_id
}

# VPC for migration infrastructure
resource "aws_vpc" "migration_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = local.vpc_name
  })
}

# Internet Gateway for public connectivity
resource "aws_internet_gateway" "migration_igw" {
  vpc_id = aws_vpc.migration_vpc.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-igw-${local.suffix}"
  })
}

# Public subnet for NAT gateway and public resources
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.migration_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = local.public_subnet_name
    Type = "Public"
  })
}

# Private subnet for migration targets
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.migration_vpc.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zones[1]

  tags = merge(local.common_tags, {
    Name = local.private_subnet_name
    Type = "Private"
  })
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nat-eip-${local.suffix}"
  })

  depends_on = [aws_internet_gateway.migration_igw]
}

# NAT Gateway for private subnet internet access
resource "aws_nat_gateway" "migration_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nat-${local.suffix}"
  })

  depends_on = [aws_internet_gateway.migration_igw]
}

# Route table for public subnet
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.migration_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.migration_igw.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-rt-${local.suffix}"
  })
}

# Route table for private subnet
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.migration_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.migration_nat.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-rt-${local.suffix}"
  })
}

# Route table associations
resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_subnet_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# Security group for migration infrastructure
resource "aws_security_group" "migration_sg" {
  name        = local.security_group_name
  description = "Security group for migration infrastructure"
  vpc_id      = aws_vpc.migration_vpc.id

  # SSH access from within VPC
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS access from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # MGN replication traffic
  ingress {
    from_port   = 1500
    to_port     = 1500
    protocol    = "tcp"
    cidr_blocks = [var.allowed_source_cidr]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = local.security_group_name
  })
}

# IAM role for MGN service
resource "aws_iam_role" "mgn_service_role" {
  name = "MGNServiceRole-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "mgn.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for MGN service
resource "aws_iam_role_policy" "mgn_service_policy" {
  name = "MGNServicePolicy-${local.suffix}"
  role = aws_iam_role.mgn_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:*",
          "iam:PassRole",
          "logs:*",
          "ssm:*",
          "cloudwatch:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM role for Systems Manager automation
resource "aws_iam_role" "ssm_automation_role" {
  name = "SSMAutomationRole-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for Systems Manager automation
resource "aws_iam_role_policy" "ssm_automation_policy" {
  name = "SSMAutomationPolicy-${local.suffix}"
  role = aws_iam_role.ssm_automation_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:*",
          "ec2:*",
          "logs:*",
          "cloudwatch:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudWatch Log Group for migration monitoring
resource "aws_cloudwatch_log_group" "migration_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/migration/${var.project_name}-${local.suffix}"
  retention_in_days = var.log_retention_in_days

  tags = local.common_tags
}

# CloudWatch Log Group for Migration Hub Orchestrator
resource "aws_cloudwatch_log_group" "orchestrator_logs" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/migrationhub-orchestrator/${var.project_name}-${local.suffix}"
  retention_in_days = var.log_retention_in_days

  tags = local.common_tags
}

# CloudWatch Dashboard for migration monitoring
resource "aws_cloudwatch_dashboard" "migration_dashboard" {
  dashboard_name = "Migration-Dashboard-${local.suffix}"

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
            ["AWS/MGN", "TotalSourceServers"],
            ["AWS/MGN", "HealthySourceServers"],
            ["AWS/MGN", "ReplicationProgress"]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "MGN Migration Status"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          query = "SOURCE '/aws/migrationhub-orchestrator' | fields @timestamp, message\n| filter message like /ERROR/\n| sort @timestamp desc\n| limit 20"
          region = var.aws_region
          title  = "Migration Errors"
        }
      }
    ]
  })
}

# CloudWatch Alarm for MGN replication health
resource "aws_cloudwatch_metric_alarm" "mgn_replication_health" {
  alarm_name          = "MGN-Replication-Health-${local.suffix}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthySourceServers"
  namespace           = "AWS/MGN"
  period              = "300"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors MGN replication health"
  treat_missing_data  = "breaching"

  tags = local.common_tags
}

# Systems Manager document for post-migration automation
resource "aws_ssm_document" "post_migration_automation" {
  name            = "PostMigrationAutomation-${local.suffix}"
  document_type   = "Automation"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "0.3"
    description   = "Post-migration automation tasks"
    assumeRole    = "{{ AutomationAssumeRole }}"
    parameters = {
      InstanceId = {
        type        = "String"
        description = "EC2 Instance ID for post-migration tasks"
      }
      AutomationAssumeRole = {
        type        = "String"
        description = "IAM role for automation execution"
      }
    }
    mainSteps = [
      {
        name   = "WaitForInstanceReady"
        action = "aws:waitForAwsResourceProperty"
        inputs = {
          Service          = "ec2"
          Api              = "DescribeInstanceStatus"
          InstanceIds      = ["{{ InstanceId }}"]
          PropertySelector = "$.InstanceStatuses[0].InstanceStatus.Status"
          DesiredValues    = ["ok"]
        }
      },
      {
        name   = "ConfigureCloudWatchAgent"
        action = "aws:runCommand"
        inputs = {
          DocumentName = "AWS-ConfigureAWSPackage"
          InstanceIds  = ["{{ InstanceId }}"]
          Parameters = {
            action = "Install"
            name   = "AmazonCloudWatchAgent"
          }
        }
      },
      {
        name   = "ValidateServices"
        action = "aws:runCommand"
        inputs = {
          DocumentName = "AWS-RunShellScript"
          InstanceIds  = ["{{ InstanceId }}"]
          Parameters = {
            commands = [
              "#!/bin/bash",
              "systemctl status sshd",
              "curl -f http://localhost/health || echo 'Application health check failed'"
            ]
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

# VPC Endpoints for secure communication (optional but recommended)
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.migration_vpc.id
  service_name = "com.amazonaws.${var.aws_region}.s3"
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-s3-endpoint-${local.suffix}"
  })
}

resource "aws_vpc_endpoint" "ec2" {
  vpc_id              = aws_vpc.migration_vpc.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_subnet.id]
  security_group_ids  = [aws_security_group.migration_sg.id]
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "ec2:*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ec2-endpoint-${local.suffix}"
  })
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.migration_vpc.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_subnet.id]
  security_group_ids  = [aws_security_group.migration_sg.id]
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "ssm:*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ssm-endpoint-${local.suffix}"
  })
}