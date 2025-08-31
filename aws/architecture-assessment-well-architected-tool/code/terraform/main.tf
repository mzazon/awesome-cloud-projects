# AWS Well-Architected Tool Assessment Infrastructure
# This Terraform configuration creates a workload for assessment and supporting monitoring resources

# Get current AWS caller identity for workload owner
data "aws_caller_identity" "current" {}

# Get current AWS region
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  workload_name = "${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  
  # Use provided review owner or default to current user ARN
  review_owner = var.review_owner != "" ? var.review_owner : data.aws_caller_identity.current.arn
  
  # Use provided regions or default to current region
  aws_regions = length(var.aws_regions) > 0 ? var.aws_regions : [data.aws_region.current.name]
  
  # Combined tags
  common_tags = merge(
    {
      Name          = local.workload_name
      Environment   = var.environment
      Project       = var.project_name
      WorkloadType  = "assessment"
      Assessment    = "well-architected"
    },
    var.workload_tags
  )
}

# Well-Architected Tool Workload
# This is the primary resource for conducting architectural assessments
resource "aws_wellarchitected_workload" "main" {
  workload_name       = local.workload_name
  description         = var.workload_description
  environment         = upper(var.environment)
  review_owner        = local.review_owner
  industry_type       = var.industry_type
  architectural_design = var.architectural_design
  aws_regions         = local.aws_regions
  lenses              = var.lenses
  
  # Optional notes for the assessment
  notes = var.assessment_notes
  
  tags = local.common_tags
}

# CloudWatch Log Group for assessment-related logging
resource "aws_cloudwatch_log_group" "workload_logs" {
  count = var.enable_cloudwatch_dashboard ? 1 : 0
  
  name              = "/aws/wellarchitected/${local.workload_name}"
  retention_in_days = 30
  
  tags = merge(local.common_tags, {
    Purpose = "well-architected-assessment-logs"
  })
}

# CloudWatch Dashboard for workload monitoring
resource "aws_cloudwatch_dashboard" "workload_dashboard" {
  count = var.enable_cloudwatch_dashboard ? 1 : 0
  
  dashboard_name = "${local.workload_name}-assessment-dashboard"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        
        properties = {
          markdown = "# Well-Architected Assessment Dashboard\n\n**Workload:** ${local.workload_name}\n**Environment:** ${var.environment}\n**Industry:** ${var.industry_type}"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/Logs", "IncomingLogEvents", "LogGroupName", "/aws/wellarchitected/${local.workload_name}"]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Assessment Activity"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 2
        width  = 12
        height = 6
        
        properties = {
          query   = "SOURCE '/aws/wellarchitected/${local.workload_name}'\n| fields @timestamp, @message\n| sort @timestamp desc\n| limit 100"
          region  = data.aws_region.current.name
          title   = "Recent Assessment Logs"
        }
      }
    ]
  })
}

# SNS Topic for assessment notifications (optional)
resource "aws_sns_topic" "assessment_notifications" {
  count = var.enable_notifications ? 1 : 0
  
  name         = "${local.workload_name}-assessment-notifications"
  display_name = "Well-Architected Assessment Notifications"
  
  tags = merge(local.common_tags, {
    Purpose = "assessment-notifications"
  })
}

# SNS Topic Subscription for email notifications
resource "aws_sns_topic_subscription" "email_notifications" {
  count = var.enable_notifications && var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.assessment_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch Metric Alarm for assessment completion tracking
resource "aws_cloudwatch_metric_alarm" "assessment_activity" {
  count = var.enable_cloudwatch_dashboard ? 1 : 0
  
  alarm_name          = "${local.workload_name}-assessment-activity"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "IncomingLogEvents"
  namespace           = "AWS/Logs"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors assessment activity for the workload"
  
  dimensions = {
    LogGroupName = aws_cloudwatch_log_group.workload_logs[0].name
  }
  
  alarm_actions = var.enable_notifications ? [aws_sns_topic.assessment_notifications[0].arn] : []
  
  tags = merge(local.common_tags, {
    Purpose = "assessment-monitoring"
  })
}

# IAM Role for Well-Architected Tool access (example for automation)
resource "aws_iam_role" "wellarchitected_automation" {
  name = "${local.workload_name}-automation-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = data.aws_caller_identity.current.arn
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Purpose = "automation"
  })
}

# IAM Policy for Well-Architected Tool operations
resource "aws_iam_role_policy" "wellarchitected_policy" {
  name = "${local.workload_name}-wellarchitected-policy"
  role = aws_iam_role.wellarchitected_automation.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "wellarchitected:GetWorkload",
          "wellarchitected:UpdateWorkload",
          "wellarchitected:ListWorkloads",
          "wellarchitected:GetLensReview",
          "wellarchitected:UpdateLensReview",
          "wellarchitected:ListAnswers",
          "wellarchitected:GetAnswer",
          "wellarchitected:UpdateAnswer",
          "wellarchitected:ListLensReviewImprovements",
          "wellarchitected:CreateMilestone",
          "wellarchitected:ListMilestones"
        ]
        Resource = [
          aws_wellarchitected_workload.main.arn,
          "${aws_wellarchitected_workload.main.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = var.enable_cloudwatch_dashboard ? [
          "${aws_cloudwatch_log_group.workload_logs[0].arn}:*"
        ] : ["*"]
      }
    ]
  })
}

# Sample resources to demonstrate assessment capabilities (optional)
# VPC for sample infrastructure
resource "aws_vpc" "sample" {
  count = var.create_sample_resources ? 1 : 0
  
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(local.common_tags, {
    Name    = "${local.workload_name}-vpc"
    Purpose = "sample-infrastructure"
  })
}

# Internet Gateway for sample VPC
resource "aws_internet_gateway" "sample" {
  count = var.create_sample_resources ? 1 : 0
  
  vpc_id = aws_vpc.sample[0].id
  
  tags = merge(local.common_tags, {
    Name    = "${local.workload_name}-igw"
    Purpose = "sample-infrastructure"
  })
}

# Public subnet for sample infrastructure
resource "aws_subnet" "sample_public" {
  count = var.create_sample_resources ? 1 : 0
  
  vpc_id                  = aws_vpc.sample[0].id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available[0].names[0]
  map_public_ip_on_launch = true
  
  tags = merge(local.common_tags, {
    Name    = "${local.workload_name}-public-subnet"
    Type    = "public"
    Purpose = "sample-infrastructure"
  })
}

# Route table for public subnet
resource "aws_route_table" "sample_public" {
  count = var.create_sample_resources ? 1 : 0
  
  vpc_id = aws_vpc.sample[0].id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.sample[0].id
  }
  
  tags = merge(local.common_tags, {
    Name    = "${local.workload_name}-public-rt"
    Purpose = "sample-infrastructure"
  })
}

# Associate route table with public subnet
resource "aws_route_table_association" "sample_public" {
  count = var.create_sample_resources ? 1 : 0
  
  subnet_id      = aws_subnet.sample_public[0].id
  route_table_id = aws_route_table.sample_public[0].id
}

# Security group for sample resources
resource "aws_security_group" "sample_web" {
  count = var.create_sample_resources ? 1 : 0
  
  name_prefix = "${local.workload_name}-web-"
  vpc_id      = aws_vpc.sample[0].id
  description = "Security group for sample web application"
  
  # HTTP access
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP access"
  }
  
  # HTTPS access
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS access"
  }
  
  # Outbound access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }
  
  tags = merge(local.common_tags, {
    Name    = "${local.workload_name}-web-sg"
    Purpose = "sample-infrastructure"
  })
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  count = var.create_sample_resources ? 1 : 0
  state = "available"
}

# Well-Architected Milestone to capture initial assessment state
resource "aws_wellarchitected_milestone" "initial" {
  workload_id   = aws_wellarchitected_workload.main.id
  milestone_name = "initial-assessment"
  
  # Create milestone after a short delay to ensure workload is fully configured
  depends_on = [aws_wellarchitected_workload.main]
}