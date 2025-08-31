# Simple Resource Monitoring with CloudWatch and SNS
# This Terraform configuration creates a complete monitoring solution for EC2 instances
# including CloudWatch alarms and SNS notifications

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# Data source to get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Data source to get default VPC if not creating a new one
data "aws_vpc" "default" {
  count   = var.create_vpc ? 0 : 1
  default = true
}

# Data source to get default subnet if using default VPC
data "aws_subnets" "default" {
  count = var.create_vpc ? 0 : 1

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }

  filter {
    name   = "availability-zone"
    values = ["${data.aws_region.current.name}a"]
  }
}

# Create VPC if requested
resource "aws_vpc" "monitoring_vpc" {
  count = var.create_vpc ? 1 : 0

  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.resource_name_prefix}-vpc-${random_string.suffix.result}"
  })
}

# Create Internet Gateway for new VPC
resource "aws_internet_gateway" "monitoring_igw" {
  count = var.create_vpc ? 1 : 0

  vpc_id = aws_vpc.monitoring_vpc[0].id

  tags = merge(var.tags, {
    Name = "${var.resource_name_prefix}-igw-${random_string.suffix.result}"
  })
}

# Create public subnet for new VPC
resource "aws_subnet" "monitoring_subnet" {
  count = var.create_vpc ? 1 : 0

  vpc_id                  = aws_vpc.monitoring_vpc[0].id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = "${data.aws_region.current.name}a"
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.resource_name_prefix}-subnet-${random_string.suffix.result}"
  })
}

# Create route table for new VPC
resource "aws_route_table" "monitoring_rt" {
  count = var.create_vpc ? 1 : 0

  vpc_id = aws_vpc.monitoring_vpc[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.monitoring_igw[0].id
  }

  tags = merge(var.tags, {
    Name = "${var.resource_name_prefix}-rt-${random_string.suffix.result}"
  })
}

# Associate route table with subnet
resource "aws_route_table_association" "monitoring_rta" {
  count = var.create_vpc ? 1 : 0

  subnet_id      = aws_subnet.monitoring_subnet[0].id
  route_table_id = aws_route_table.monitoring_rt[0].id
}

# Create Security Group for EC2 instance
resource "aws_security_group" "monitoring_sg" {
  name_prefix = "${var.resource_name_prefix}-sg-"
  description = "Security group for monitoring demo EC2 instance"
  vpc_id      = var.create_vpc ? aws_vpc.monitoring_vpc[0].id : data.aws_vpc.default[0].id

  # SSH access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # ICMP for ping tests
  ingress {
    description = "ICMP"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
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

  tags = merge(var.tags, {
    Name = "${var.resource_name_prefix}-sg-${random_string.suffix.result}"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Create Key Pair if requested
resource "aws_key_pair" "monitoring_key" {
  count = var.create_key_pair ? 1 : 0

  key_name   = "${var.resource_name_prefix}-key-${random_string.suffix.result}"
  public_key = var.public_key

  tags = merge(var.tags, {
    Name = "${var.resource_name_prefix}-key-${random_string.suffix.result}"
  })
}

# Create IAM role for EC2 instance (for SSM access)
resource "aws_iam_role" "ec2_monitoring_role" {
  name_prefix = "${var.resource_name_prefix}-ec2-role-"

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

  tags = merge(var.tags, {
    Name = "${var.resource_name_prefix}-ec2-role-${random_string.suffix.result}"
  })
}

# Attach SSM managed policy to EC2 role
resource "aws_iam_role_policy_attachment" "ec2_ssm_policy" {
  role       = aws_iam_role.ec2_monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create IAM instance profile
resource "aws_iam_instance_profile" "ec2_monitoring_profile" {
  name_prefix = "${var.resource_name_prefix}-ec2-profile-"
  role        = aws_iam_role.ec2_monitoring_role.name

  tags = merge(var.tags, {
    Name = "${var.resource_name_prefix}-ec2-profile-${random_string.suffix.result}"
  })
}

# Create KMS key for SNS encryption
resource "aws_kms_key" "sns_key" {
  count = var.enable_sns_encryption ? 1 : 0

  description             = "KMS key for SNS topic encryption"
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch to use the key"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow SNS to use the key"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.resource_name_prefix}-sns-key-${random_string.suffix.result}"
  })
}

# Create KMS key alias
resource "aws_kms_alias" "sns_key_alias" {
  count = var.enable_sns_encryption ? 1 : 0

  name          = "alias/${var.resource_name_prefix}-sns-key-${random_string.suffix.result}"
  target_key_id = aws_kms_key.sns_key[0].key_id
}

# Create SNS Topic for CloudWatch Alarms
resource "aws_sns_topic" "cpu_alerts" {
  name_prefix = "${var.resource_name_prefix}-cpu-alerts-"
  
  # Enable encryption if requested
  kms_master_key_id = var.enable_sns_encryption ? aws_kms_key.sns_key[0].arn : null

  # Configure delivery policy for better reliability
  delivery_policy = jsonencode({
    "http" = {
      "defaultHealthyRetryPolicy" = {
        "minDelayTarget"     = 20
        "maxDelayTarget"     = 20
        "numRetries"         = 3
        "numMaxDelayRetries" = 0
        "numNoDelayRetries"  = 0
        "numMinDelayRetries" = 0
        "backoffFunction"    = "linear"
      }
      "disableSubscriptionOverrides" = false
    }
  })

  tags = merge(var.tags, {
    Name = "${var.resource_name_prefix}-cpu-alerts-${random_string.suffix.result}"
  })
}

# Create SNS Topic Subscription for Email Notifications
resource "aws_sns_topic_subscription" "email_notification" {
  topic_arn = aws_sns_topic.cpu_alerts.arn
  protocol  = "email"
  endpoint  = var.email_address

  # The subscription will be pending until confirmed via email
}

# Create CloudWatch Log Group for custom metrics (optional)
resource "aws_cloudwatch_log_group" "monitoring_logs" {
  name_prefix       = "/aws/ec2/${var.resource_name_prefix}-"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(var.tags, {
    Name = "${var.resource_name_prefix}-logs-${random_string.suffix.result}"
  })
}

# Create EC2 Instance for Monitoring
resource "aws_instance" "monitoring_demo" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  # Use created or default subnet
  subnet_id = var.create_vpc ? aws_subnet.monitoring_subnet[0].id : data.aws_subnets.default[0].ids[0]

  # Security group
  vpc_security_group_ids = [aws_security_group.monitoring_sg.id]

  # Key pair (if created)
  key_name = var.create_key_pair ? aws_key_pair.monitoring_key[0].key_name : null

  # IAM instance profile for SSM access
  iam_instance_profile = aws_iam_instance_profile.ec2_monitoring_profile.name

  # Enable detailed monitoring if requested
  monitoring = var.enable_detailed_monitoring

  # User data script to install monitoring tools
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    log_group_name = aws_cloudwatch_log_group.monitoring_logs.name
  }))

  # Root block device configuration
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
    encrypted             = true

    tags = merge(var.tags, {
      Name = "${var.resource_name_prefix}-root-volume-${random_string.suffix.result}"
    })
  }

  # Metadata options for security
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  tags = merge(var.tags, {
    Name        = "${var.resource_name_prefix}-${random_string.suffix.result}"
    Monitoring  = "enabled"
    Environment = var.environment
  })

  # Ensure SNS topic is created first
  depends_on = [aws_sns_topic.cpu_alerts]
}

# Create CloudWatch Alarm for High CPU Utilization
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.resource_name_prefix}-high-cpu-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = var.metric_period
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "This metric monitors ec2 cpu utilization for instance ${aws_instance.monitoring_demo.id}"
  
  # Actions to take when alarm triggers
  alarm_actions = [aws_sns_topic.cpu_alerts.arn]
  ok_actions    = [aws_sns_topic.cpu_alerts.arn]

  # Configure alarm to trigger only if we have sufficient data
  insufficient_data_actions = []
  treat_missing_data        = "notBreaching"

  # Dimensions to specify which instance to monitor
  dimensions = {
    InstanceId = aws_instance.monitoring_demo.id
  }

  tags = merge(var.tags, {
    Name = "${var.resource_name_prefix}-high-cpu-alarm-${random_string.suffix.result}"
  })

  # Ensure instance is created first
  depends_on = [aws_instance.monitoring_demo]
}

# Create CloudWatch Alarm for Instance Status Check
resource "aws_cloudwatch_metric_alarm" "instance_status_check" {
  alarm_name          = "${var.resource_name_prefix}-instance-status-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed_Instance"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "This metric monitors instance status check for instance ${aws_instance.monitoring_demo.id}"
  
  # Actions to take when alarm triggers
  alarm_actions = [aws_sns_topic.cpu_alerts.arn]
  ok_actions    = [aws_sns_topic.cpu_alerts.arn]

  # Dimensions to specify which instance to monitor
  dimensions = {
    InstanceId = aws_instance.monitoring_demo.id
  }

  tags = merge(var.tags, {
    Name = "${var.resource_name_prefix}-instance-status-alarm-${random_string.suffix.result}"
  })

  # Ensure instance is created first
  depends_on = [aws_instance.monitoring_demo]
}

# Create CloudWatch Alarm for System Status Check
resource "aws_cloudwatch_metric_alarm" "system_status_check" {
  alarm_name          = "${var.resource_name_prefix}-system-status-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed_System"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "This metric monitors system status check for instance ${aws_instance.monitoring_demo.id}"
  
  # Actions to take when alarm triggers
  alarm_actions = [aws_sns_topic.cpu_alerts.arn]
  ok_actions    = [aws_sns_topic.cpu_alerts.arn]

  # Dimensions to specify which instance to monitor
  dimensions = {
    InstanceId = aws_instance.monitoring_demo.id
  }

  tags = merge(var.tags, {
    Name = "${var.resource_name_prefix}-system-status-alarm-${random_string.suffix.result}"
  })

  # Ensure instance is created first
  depends_on = [aws_instance.monitoring_demo]
}