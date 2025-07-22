# Data sources for existing resources
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Get the latest Amazon Linux 2 AMI that supports hibernation
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Get default VPC if not specified
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

# Get default subnet if not specified
data "aws_subnets" "default" {
  count = var.subnet_id == "" ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Local values for resource naming and configuration
locals {
  # Resource naming
  name_suffix      = random_string.suffix.result
  key_pair_name    = var.key_pair_name != "" ? var.key_pair_name : "${var.name_prefix}-key-${local.name_suffix}"
  instance_name    = var.instance_name != "" ? var.instance_name : "${var.name_prefix}-instance-${local.name_suffix}"
  sns_topic_name   = var.sns_topic_name != "" ? var.sns_topic_name : "${var.name_prefix}-notifications-${local.name_suffix}"
  security_group_name = "${var.name_prefix}-sg-${local.name_suffix}"
  
  # Network configuration
  vpc_id    = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_id = var.subnet_id != "" ? var.subnet_id : data.aws_subnets.default[0].ids[0]
  
  # Common tags
  common_tags = merge(
    {
      Name        = var.name_prefix
      Environment = var.environment
      Project     = "EC2-Hibernation-Demo"
      ManagedBy   = "Terraform"
      Purpose     = "Cost-Optimization"
    },
    var.additional_tags
  )
}

# Create TLS private key for EC2 key pair
resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create EC2 key pair
resource "aws_key_pair" "ec2_key_pair" {
  key_name   = local.key_pair_name
  public_key = tls_private_key.ec2_key.public_key_openssh

  tags = merge(local.common_tags, {
    Name = local.key_pair_name
  })
}

# Store private key in AWS Systems Manager Parameter Store
resource "aws_ssm_parameter" "ec2_private_key" {
  name  = "/ec2/hibernation-demo/${local.key_pair_name}/private-key"
  type  = "SecureString"
  value = tls_private_key.ec2_key.private_key_pem

  tags = merge(local.common_tags, {
    Name = "${local.key_pair_name}-private-key"
  })
}

# Security group for EC2 instance
resource "aws_security_group" "ec2_sg" {
  name        = local.security_group_name
  description = "Security group for EC2 hibernation demo instance"
  vpc_id      = local.vpc_id

  # SSH access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = local.security_group_name
  })
}

# IAM role for EC2 instance
resource "aws_iam_role" "ec2_hibernation_role" {
  name = "${var.name_prefix}-ec2-hibernation-role-${local.name_suffix}"

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

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ec2-hibernation-role-${local.name_suffix}"
  })
}

# IAM policy for CloudWatch monitoring
resource "aws_iam_role_policy" "ec2_cloudwatch_policy" {
  name = "${var.name_prefix}-ec2-cloudwatch-policy"
  role = aws_iam_role.ec2_hibernation_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach SSM managed policy for Systems Manager access
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_hibernation_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM instance profile for EC2
resource "aws_iam_instance_profile" "ec2_hibernation_profile" {
  name = "${var.name_prefix}-ec2-hibernation-profile-${local.name_suffix}"
  role = aws_iam_role.ec2_hibernation_role.name

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ec2-hibernation-profile-${local.name_suffix}"
  })
}

# EC2 instance with hibernation enabled
resource "aws_instance" "hibernation_demo" {
  ami                  = data.aws_ami.amazon_linux.id
  instance_type        = var.instance_type
  key_name            = aws_key_pair.ec2_key_pair.key_name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  subnet_id           = local.subnet_id
  iam_instance_profile = aws_iam_instance_profile.ec2_hibernation_profile.name
  
  # Enable hibernation
  hibernation = true
  
  # Enable detailed monitoring if specified
  monitoring = var.enable_detailed_monitoring

  # Root volume configuration for hibernation
  root_block_device {
    volume_type           = var.ebs_volume_type
    volume_size           = var.ebs_volume_size
    encrypted             = true
    delete_on_termination = true
    
    tags = merge(local.common_tags, {
      Name = "${local.instance_name}-root-volume"
    })
  }

  # User data script for initial setup
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    instance_name = local.instance_name
    environment   = var.environment
  }))

  tags = merge(local.common_tags, {
    Name    = local.instance_name
    Purpose = "HibernationDemo"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Create user data script file
resource "local_file" "user_data_script" {
  content = templatefile("${path.module}/user_data.tpl", {
    instance_name = local.instance_name
    environment   = var.environment
  })
  filename = "${path.module}/user_data.sh"
}

# SNS topic for notifications
resource "aws_sns_topic" "hibernation_notifications" {
  name = local.sns_topic_name

  tags = merge(local.common_tags, {
    Name = local.sns_topic_name
  })
}

# SNS topic policy
resource "aws_sns_topic_policy" "hibernation_notifications_policy" {
  arn = aws_sns_topic.hibernation_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = "SNS:Publish"
        Resource = aws_sns_topic.hibernation_notifications.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# SNS email subscription (optional)
resource "aws_sns_topic_subscription" "hibernation_email_notification" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.hibernation_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch alarm for low CPU utilization
resource "aws_cloudwatch_metric_alarm" "low_cpu_utilization" {
  alarm_name          = "LowCPU-${local.instance_name}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.cpu_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = var.cpu_alarm_period
  statistic           = "Average"
  threshold           = var.cpu_threshold
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_sns_topic.hibernation_notifications.arn]

  dimensions = {
    InstanceId = aws_instance.hibernation_demo.id
  }

  tags = merge(local.common_tags, {
    Name = "LowCPU-${local.instance_name}"
  })
}

# CloudWatch alarm for instance state changes
resource "aws_cloudwatch_metric_alarm" "instance_state_change" {
  alarm_name          = "InstanceStateChange-${local.instance_name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "This metric monitors instance state changes"
  alarm_actions       = [aws_sns_topic.hibernation_notifications.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = aws_instance.hibernation_demo.id
  }

  tags = merge(local.common_tags, {
    Name = "InstanceStateChange-${local.instance_name}"
  })
}

# CloudWatch Log Group for custom metrics
resource "aws_cloudwatch_log_group" "hibernation_logs" {
  name              = "/aws/ec2/hibernation-demo/${local.instance_name}"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    Name = "/aws/ec2/hibernation-demo/${local.instance_name}"
  })
}

# Lambda function for automated hibernation (optional)
resource "aws_lambda_function" "hibernation_scheduler" {
  count = var.environment == "dev" ? 1 : 0
  
  filename         = "hibernation_scheduler.zip"
  function_name    = "${var.name_prefix}-hibernation-scheduler-${local.name_suffix}"
  role            = aws_iam_role.lambda_hibernation_role[0].arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 60

  environment {
    variables = {
      INSTANCE_ID = aws_instance.hibernation_demo.id
      SNS_TOPIC_ARN = aws_sns_topic.hibernation_notifications.arn
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-hibernation-scheduler-${local.name_suffix}"
  })
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_hibernation_role" {
  count = var.environment == "dev" ? 1 : 0
  
  name = "${var.name_prefix}-lambda-hibernation-role-${local.name_suffix}"

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

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-lambda-hibernation-role-${local.name_suffix}"
  })
}

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_hibernation_policy" {
  count = var.environment == "dev" ? 1 : 0
  
  name = "${var.name_prefix}-lambda-hibernation-policy"
  role = aws_iam_role.lambda_hibernation_role[0].id

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
          "ec2:DescribeInstances",
          "ec2:StopInstances",
          "ec2:StartInstances"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.hibernation_notifications.arn
      }
    ]
  })
}

# Create Lambda deployment package
data "archive_file" "lambda_hibernation_zip" {
  count = var.environment == "dev" ? 1 : 0
  
  type        = "zip"
  output_path = "hibernation_scheduler.zip"
  source {
    content = templatefile("${path.module}/hibernation_scheduler.py.tpl", {
      instance_id = aws_instance.hibernation_demo.id
      sns_topic_arn = aws_sns_topic.hibernation_notifications.arn
    })
    filename = "index.py"
  }
}