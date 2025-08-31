# Main Terraform configuration for Network Troubleshooting with VPC Lattice

# Data sources for AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  random_suffix = random_string.suffix.result
  
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    RandomId    = local.random_suffix
  })
}

# =====================================
# VPC Infrastructure
# =====================================

# VPC for the network troubleshooting environment
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-${local.random_suffix}"
  })
}

# Internet Gateway for public subnet connectivity
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw-${local.random_suffix}"
  })
}

# Public subnets for test instances
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)
  
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-subnet-${count.index + 1}-${local.random_suffix}"
    Type = "public"
  })
}

# Private subnets for internal resources
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)
  
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-subnet-${count.index + 1}-${local.random_suffix}"
    Type = "private"
  })
}

# Route table for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt-${local.random_suffix}"
  })
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)
  
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# =====================================
# Security Groups
# =====================================

# Security group for test instances
resource "aws_security_group" "test_instances" {
  name_prefix = "${local.name_prefix}-test-sg-${local.random_suffix}"
  description = "Security group for VPC Lattice test instances"
  vpc_id      = aws_vpc.main.id
  
  # Allow HTTP traffic within the security group
  ingress {
    description     = "HTTP from same security group"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    self            = true
  }
  
  # Allow SSH from VPC CIDR
  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
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
    Name = "${local.name_prefix}-test-sg-${local.random_suffix}"
  })
}

# =====================================
# EC2 Test Instances
# =====================================

# Latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  
  filter {
    name   = "state"
    values = ["available"]
  }
}

# Test instance for network analysis
resource "aws_instance" "test_instance" {
  ami                     = data.aws_ami.amazon_linux.id
  instance_type           = var.instance_type
  subnet_id               = aws_subnet.public[0].id
  vpc_security_group_ids  = [aws_security_group.test_instances.id]
  monitoring              = var.enable_detailed_monitoring
  
  # User data script to set up basic web server for testing
  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "<h1>VPC Lattice Test Instance</h1>" > /var/www/html/index.html
    echo "<p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>" >> /var/www/html/index.html
    echo "<p>Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>" >> /var/www/html/index.html
  EOF
  )
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-test-instance-${local.random_suffix}"
  })
}

# =====================================
# VPC Lattice Service Network
# =====================================

# VPC Lattice service network
resource "aws_vpclattice_service_network" "main" {
  name      = "${local.name_prefix}-service-network-${local.random_suffix}"
  auth_type = "AWS_IAM"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-service-network-${local.random_suffix}"
  })
}

# Associate VPC with service network
resource "aws_vpclattice_service_network_vpc_association" "main" {
  vpc_identifier             = aws_vpc.main.id
  service_network_identifier = aws_vpclattice_service_network.main.id
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-association-${local.random_suffix}"
  })
}

# =====================================
# IAM Roles and Policies
# =====================================

# IAM role for Systems Manager automation
resource "aws_iam_role" "ssm_automation" {
  name = "${local.name_prefix}-ssm-automation-role-${local.random_suffix}"
  
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

# Attach policies to SSM automation role
resource "aws_iam_role_policy_attachment" "ssm_automation_role" {
  role       = aws_iam_role.ssm_automation.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMAutomationRole"
}

resource "aws_iam_role_policy_attachment" "ssm_automation_vpc" {
  role       = aws_iam_role.ssm_automation.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonVPCFullAccess"
}

resource "aws_iam_role_policy_attachment" "ssm_automation_cloudwatch" {
  role       = aws_iam_role.ssm_automation.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_execution" {
  name = "${local.name_prefix}-lambda-execution-role-${local.random_suffix}"
  
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
  
  tags = local.common_tags
}

# Attach policies to Lambda execution role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_ssm_access" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMFullAccess"
}

# =====================================
# Systems Manager Automation Document
# =====================================

# SSM automation document for network reachability analysis
resource "aws_ssm_document" "network_analysis" {
  name          = "${local.name_prefix}-network-analysis-${local.random_suffix}"
  document_type = "Automation"
  document_format = "JSON"
  
  content = jsonencode({
    schemaVersion = "0.3"
    description   = "Automated VPC Reachability Analysis for Network Troubleshooting"
    assumeRole    = "{{ AutomationAssumeRole }}"
    
    parameters = {
      SourceId = {
        type        = "String"
        description = "Source instance ID or ENI ID"
      }
      DestinationId = {
        type        = "String"
        description = "Destination instance ID or ENI ID"
      }
      AutomationAssumeRole = {
        type        = "String"
        description = "IAM role for automation execution"
      }
    }
    
    mainSteps = [
      {
        name        = "CreateNetworkInsightsPath"
        action      = "aws:executeAwsApi"
        description = "Create a network insights path for reachability analysis"
        inputs = {
          Service     = "ec2"
          Api         = "CreateNetworkInsightsPath"
          Source      = "{{ SourceId }}"
          Destination = "{{ DestinationId }}"
          Protocol    = "tcp"
          DestinationPort = 80
          TagSpecifications = [
            {
              ResourceType = "network-insights-path"
              Tags = [
                {
                  Key   = "Name"
                  Value = "AutomatedTroubleshooting"
                }
              ]
            }
          ]
        }
        outputs = [
          {
            Name     = "NetworkInsightsPathId"
            Selector = "$.NetworkInsightsPath.NetworkInsightsPathId"
            Type     = "String"
          }
        ]
      },
      {
        name        = "StartNetworkInsightsAnalysis"
        action      = "aws:executeAwsApi"
        description = "Start the network insights analysis"
        inputs = {
          Service               = "ec2"
          Api                   = "StartNetworkInsightsAnalysis"
          NetworkInsightsPathId = "{{ CreateNetworkInsightsPath.NetworkInsightsPathId }}"
          TagSpecifications = [
            {
              ResourceType = "network-insights-analysis"
              Tags = [
                {
                  Key   = "Name"
                  Value = "AutomatedAnalysis"
                }
              ]
            }
          ]
        }
        outputs = [
          {
            Name     = "NetworkInsightsAnalysisId"
            Selector = "$.NetworkInsightsAnalysis.NetworkInsightsAnalysisId"
            Type     = "String"
          }
        ]
      },
      {
        name        = "WaitForAnalysisCompletion"
        action      = "aws:waitForAwsResourceProperty"
        description = "Wait for the analysis to complete"
        inputs = {
          Service    = "ec2"
          Api        = "DescribeNetworkInsightsAnalyses"
          NetworkInsightsAnalysisIds = [
            "{{ StartNetworkInsightsAnalysis.NetworkInsightsAnalysisId }}"
          ]
          PropertySelector = "$.NetworkInsightsAnalyses[0].Status"
          DesiredValues = [
            "succeeded",
            "failed"
          ]
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-network-analysis-${local.random_suffix}"
  })
}

# =====================================
# SNS Topic for Notifications
# =====================================

# SNS topic for network alerts
resource "aws_sns_topic" "network_alerts" {
  name = "${local.name_prefix}-network-alerts-${local.random_suffix}"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-network-alerts-${local.random_suffix}"
  })
}

# SNS topic policy
resource "aws_sns_topic_policy" "network_alerts" {
  arn = aws_sns_topic.network_alerts.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "default"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarmsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = [
          "SNS:Publish"
        ]
        Resource = aws_sns_topic.network_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Email subscription (optional)
resource "aws_sns_topic_subscription" "email_notification" {
  count = var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.network_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# =====================================
# CloudWatch Resources
# =====================================

# CloudWatch log group for VPC Lattice
resource "aws_cloudwatch_log_group" "vpc_lattice" {
  name              = "/aws/vpclattice/servicenetwork/${aws_vpclattice_service_network.main.id}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-lattice-logs-${local.random_suffix}"
  })
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name_prefix}-network-troubleshooting-${local.random_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-logs-${local.random_suffix}"
  })
}

# CloudWatch dashboard for network monitoring
resource "aws_cloudwatch_dashboard" "network_monitoring" {
  dashboard_name = "${local.name_prefix}-network-troubleshooting-${local.random_suffix}"
  
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
            ["AWS/VpcLattice", "RequestCount", "ServiceNetwork", aws_vpclattice_service_network.main.id],
            [".", "TargetResponseTime", ".", "."],
            [".", "ActiveConnectionCount", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "VPC Lattice Performance Metrics"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/VpcLattice", "HTTPCode_Target_2XX_Count", "ServiceNetwork", aws_vpclattice_service_network.main.id],
            [".", "HTTPCode_Target_4XX_Count", ".", "."],
            [".", "HTTPCode_Target_5XX_Count", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "VPC Lattice Response Codes"
        }
      }
    ]
  })
}

# CloudWatch alarm for high error rate
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  alarm_name          = "${local.name_prefix}-high-error-rate-${local.random_suffix}"
  alarm_description   = "Alarm for high VPC Lattice 5XX error rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/VpcLattice"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.alarm_error_threshold
  alarm_actions       = [aws_sns_topic.network_alerts.arn]
  
  dimensions = {
    ServiceNetwork = aws_vpclattice_service_network.main.id
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-high-error-rate-${local.random_suffix}"
  })
}

# CloudWatch alarm for high latency
resource "aws_cloudwatch_metric_alarm" "high_latency" {
  alarm_name          = "${local.name_prefix}-high-latency-${local.random_suffix}"
  alarm_description   = "Alarm for high VPC Lattice response time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/VpcLattice"
  period              = "300"
  statistic           = "Average"
  threshold           = var.alarm_latency_threshold_ms
  alarm_actions       = [aws_sns_topic.network_alerts.arn]
  
  dimensions = {
    ServiceNetwork = aws_vpclattice_service_network.main.id
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-high-latency-${local.random_suffix}"
  })
}

# =====================================
# Lambda Function
# =====================================

# Lambda function code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "troubleshooting_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      automation_document_name = aws_ssm_document.network_analysis.name
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for automated network troubleshooting
resource "aws_lambda_function" "network_troubleshooting" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${local.name_prefix}-network-troubleshooting-${local.random_suffix}"
  role            = aws_iam_role.lambda_execution.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.12"
  timeout         = var.lambda_timeout
  
  environment {
    variables = {
      AUTOMATION_ROLE_ARN        = aws_iam_role.ssm_automation.arn
      DEFAULT_INSTANCE_ID        = aws_instance.test_instance.id
      AUTOMATION_DOCUMENT_NAME   = aws_ssm_document.network_analysis.name
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda,
  ]
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-network-troubleshooting-${local.random_suffix}"
  })
}

# Lambda permission for SNS to invoke the function
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.network_troubleshooting.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.network_alerts.arn
}

# SNS subscription for Lambda
resource "aws_sns_topic_subscription" "lambda_notification" {
  topic_arn = aws_sns_topic.network_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.network_troubleshooting.arn
}