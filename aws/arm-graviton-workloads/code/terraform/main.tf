# AWS Graviton Workload Infrastructure
# This file deploys the complete ARM-based workload infrastructure with Graviton processors

# Data sources for existing resources and dynamic values
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Get the latest Amazon Linux 2 AMI for x86
data "aws_ami" "amazon_linux_x86" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get the latest Amazon Linux 2 AMI for ARM
data "aws_ami" "amazon_linux_arm" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-arm64-gp2"]
  }
  
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get default subnets
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Random string for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  name_prefix = "${var.project_name}-${var.environment}-${random_string.suffix.result}"
  
  # Common tags for all resources
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      CreatedBy   = "aws-graviton-recipe"
    },
    var.additional_tags
  )
  
  # User data script for x86 instances
  x86_user_data = base64encode(templatefile("${path.module}/user_data_x86.sh", {
    project_name = var.project_name
    environment  = var.environment
  }))
  
  # User data script for ARM instances
  arm_user_data = base64encode(templatefile("${path.module}/user_data_arm.sh", {
    project_name = var.project_name
    environment  = var.environment
  }))
}

# Create user data scripts as local files
resource "local_file" "x86_user_data_script" {
  filename = "${path.module}/user_data_x86.sh"
  content  = <<-EOF
#!/bin/bash
yum update -y
yum install -y httpd stress-ng htop

# Start and enable Apache
systemctl start httpd
systemctl enable httpd

# Install CloudWatch agent for x86
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U amazon-cloudwatch-agent.rpm

# Create web page showing architecture
cat > /var/www/html/index.html << 'HTML'
<html>
<head>
    <title>x86 Architecture Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }
        .info { margin: 20px 0; }
        .metric { background-color: #e8f4ff; padding: 10px; margin: 10px 0; border-radius: 3px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>x86 Architecture Server</h1>
        <p>Project: ${project_name}</p>
        <p>Environment: ${environment}</p>
    </div>
    <div class="info">
        <div class="metric">
            <strong>Instance ID:</strong> $(curl -s http://169.254.169.254/latest/meta-data/instance-id)
        </div>
        <div class="metric">
            <strong>Architecture:</strong> $(uname -m)
        </div>
        <div class="metric">
            <strong>Instance Type:</strong> $(curl -s http://169.254.169.254/latest/meta-data/instance-type)
        </div>
        <div class="metric">
            <strong>Availability Zone:</strong> $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
        </div>
    </div>
</body>
</html>
HTML

# Create benchmark script
cat > /home/ec2-user/benchmark.sh << 'SCRIPT'
#!/bin/bash
echo "=========================================="
echo "Starting CPU benchmark on x86 architecture"
echo "Instance Type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type)"
echo "Architecture: $(uname -m)"
echo "CPU Info: $(lscpu | grep 'Model name' | head -1)"
echo "=========================================="
echo "Running stress test..."
stress-ng --cpu 4 --timeout 60s --metrics-brief
echo "Benchmark completed"
echo "=========================================="
SCRIPT

chmod +x /home/ec2-user/benchmark.sh

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CONFIG'
{
    "metrics": {
        "namespace": "GravitonDemo/EC2",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    }
}
CONFIG

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
EOF
}

resource "local_file" "arm_user_data_script" {
  filename = "${path.module}/user_data_arm.sh"
  content  = <<-EOF
#!/bin/bash
yum update -y
yum install -y httpd stress-ng htop

# Start and enable Apache
systemctl start httpd
systemctl enable httpd

# Install CloudWatch agent for ARM
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/arm64/latest/amazon-cloudwatch-agent.rpm
rpm -U amazon-cloudwatch-agent.rpm

# Create web page showing architecture
cat > /var/www/html/index.html << 'HTML'
<html>
<head>
    <title>ARM64 Graviton Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background-color: #ff9900; color: white; padding: 20px; border-radius: 5px; }
        .info { margin: 20px 0; }
        .metric { background-color: #e8f4ff; padding: 10px; margin: 10px 0; border-radius: 3px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>ARM64 Graviton Server</h1>
        <p>Project: ${project_name}</p>
        <p>Environment: ${environment}</p>
    </div>
    <div class="info">
        <div class="metric">
            <strong>Instance ID:</strong> $(curl -s http://169.254.169.254/latest/meta-data/instance-id)
        </div>
        <div class="metric">
            <strong>Architecture:</strong> $(uname -m)
        </div>
        <div class="metric">
            <strong>Instance Type:</strong> $(curl -s http://169.254.169.254/latest/meta-data/instance-type)
        </div>
        <div class="metric">
            <strong>Availability Zone:</strong> $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
        </div>
    </div>
</body>
</html>
HTML

# Create benchmark script
cat > /home/ec2-user/benchmark.sh << 'SCRIPT'
#!/bin/bash
echo "=========================================="
echo "Starting CPU benchmark on ARM64 architecture"
echo "Instance Type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type)"
echo "Architecture: $(uname -m)"
echo "CPU Info: $(lscpu | grep 'Model name' | head -1)"
echo "=========================================="
echo "Running stress test..."
stress-ng --cpu 4 --timeout 60s --metrics-brief
echo "Benchmark completed"
echo "=========================================="
SCRIPT

chmod +x /home/ec2-user/benchmark.sh

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CONFIG'
{
    "metrics": {
        "namespace": "GravitonDemo/EC2",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    }
}
CONFIG

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
EOF
}

# Create EC2 Key Pair if not provided
resource "aws_key_pair" "graviton_demo" {
  count      = var.key_pair_name == "" ? 1 : 0
  key_name   = "${local.name_prefix}-keypair"
  public_key = tls_private_key.graviton_demo[0].public_key_openssh
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-keypair"
  })
}

# Generate private key for new key pair
resource "tls_private_key" "graviton_demo" {
  count     = var.key_pair_name == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Save private key to local file
resource "local_file" "private_key" {
  count    = var.key_pair_name == "" ? 1 : 0
  filename = "${path.module}/${local.name_prefix}-keypair.pem"
  content  = tls_private_key.graviton_demo[0].private_key_pem
  
  file_permission = "0600"
}

# Security Group for EC2 instances
resource "aws_security_group" "graviton_demo" {
  name        = "${local.name_prefix}-sg"
  description = "Security group for Graviton workload demo"
  vpc_id      = data.aws_vpc.default.id

  # HTTP access
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "HTTP access for web server"
  }

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "SSH access for administration"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-sg"
  })
}

# IAM Role for EC2 instances
resource "aws_iam_role" "ec2_graviton_role" {
  name = "${local.name_prefix}-ec2-role"

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

  tags = local.common_tags
}

# IAM Policy for CloudWatch and SSM
resource "aws_iam_role_policy" "ec2_graviton_policy" {
  name = "${local.name_prefix}-ec2-policy"
  role = aws_iam_role.ec2_graviton_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "ec2:DescribeVolumes",
          "ec2:DescribeTags",
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach AWS managed policies for SSM
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  count      = var.enable_ssm_session_manager ? 1 : 0
  role       = aws_iam_role.ec2_graviton_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_server_policy" {
  role       = aws_iam_role.ec2_graviton_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "ec2_graviton_profile" {
  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2_graviton_role.name

  tags = local.common_tags
}

# x86 Baseline Instance
resource "aws_instance" "x86_baseline" {
  ami                    = var.instance_ami_id != "" ? var.instance_ami_id : data.aws_ami.amazon_linux_x86.id
  instance_type          = var.x86_instance_type
  key_name               = var.key_pair_name != "" ? var.key_pair_name : aws_key_pair.graviton_demo[0].key_name
  vpc_security_group_ids = [aws_security_group.graviton_demo.id]
  subnet_id              = data.aws_subnets.default.ids[0]
  iam_instance_profile   = aws_iam_instance_profile.ec2_graviton_profile.name
  
  user_data = local.x86_user_data
  
  monitoring = var.enable_detailed_monitoring

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  tags = merge(local.common_tags, {
    Name         = "${local.name_prefix}-x86-baseline"
    Architecture = "x86_64"
    Purpose      = "baseline-comparison"
  })
  
  depends_on = [local_file.x86_user_data_script]
}

# ARM Graviton Instance
resource "aws_instance" "arm_graviton" {
  ami                    = var.instance_ami_id != "" ? var.instance_ami_id : data.aws_ami.amazon_linux_arm.id
  instance_type          = var.arm_instance_type
  key_name               = var.key_pair_name != "" ? var.key_pair_name : aws_key_pair.graviton_demo[0].key_name
  vpc_security_group_ids = [aws_security_group.graviton_demo.id]
  subnet_id              = data.aws_subnets.default.ids[0]
  iam_instance_profile   = aws_iam_instance_profile.ec2_graviton_profile.name
  
  user_data = local.arm_user_data
  
  monitoring = var.enable_detailed_monitoring

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  tags = merge(local.common_tags, {
    Name         = "${local.name_prefix}-arm-graviton"
    Architecture = "arm64"
    Purpose      = "graviton-demo"
  })
  
  depends_on = [local_file.arm_user_data_script]
}

# Application Load Balancer
resource "aws_lb" "graviton_demo" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.graviton_demo.id]
  subnets            = data.aws_subnets.default.ids

  enable_deletion_protection = false

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb"
  })
}

# S3 Bucket for ALB Access Logs
resource "aws_s3_bucket" "alb_logs" {
  bucket = "${local.name_prefix}-alb-logs"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-logs"
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "delete_old_logs"
    status = "Enabled"

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Get ALB service account for the region
data "aws_elb_service_account" "main" {}

# S3 Bucket Policy for ALB Access Logs
resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = data.aws_elb_service_account.main.arn
        }
        Action = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      }
    ]
  })
}

# Target Group for Load Balancer
resource "aws_lb_target_group" "graviton_demo" {
  name     = "${local.name_prefix}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
    protocol            = "HTTP"
    port                = "traffic-port"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-tg"
  })
}

# Target Group Attachments
resource "aws_lb_target_group_attachment" "x86_baseline" {
  target_group_arn = aws_lb_target_group.graviton_demo.arn
  target_id        = aws_instance.x86_baseline.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "arm_graviton" {
  target_group_arn = aws_lb_target_group.graviton_demo.arn
  target_id        = aws_instance.arm_graviton.id
  port             = 80
}

# Load Balancer Listener
resource "aws_lb_listener" "graviton_demo" {
  load_balancer_arn = aws_lb.graviton_demo.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.graviton_demo.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-listener"
  })
}

# Launch Template for ARM Auto Scaling Group
resource "aws_launch_template" "arm_graviton" {
  name_prefix   = "${local.name_prefix}-arm-"
  image_id      = var.instance_ami_id != "" ? var.instance_ami_id : data.aws_ami.amazon_linux_arm.id
  instance_type = var.arm_instance_type
  key_name      = var.key_pair_name != "" ? var.key_pair_name : aws_key_pair.graviton_demo[0].key_name
  
  user_data = local.arm_user_data
  
  vpc_security_group_ids = [aws_security_group.graviton_demo.id]
  
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_graviton_profile.name
  }
  
  monitoring {
    enabled = var.enable_detailed_monitoring
  }
  
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = 8
      delete_on_termination = true
      encrypted             = true
    }
  }
  
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }
  
  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name         = "${local.name_prefix}-asg-arm"
      Architecture = "arm64"
      Purpose      = "auto-scaling-demo"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-arm-template"
  })
  
  depends_on = [local_file.arm_user_data_script]
}

# Auto Scaling Group for ARM instances
resource "aws_autoscaling_group" "arm_graviton" {
  name                = "${local.name_prefix}-asg-arm"
  vpc_zone_identifier = data.aws_subnets.default.ids
  target_group_arns   = [aws_lb_target_group.graviton_demo.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  launch_template {
    id      = aws_launch_template.arm_graviton.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-asg-arm"
    propagate_at_launch = false
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false
    }
  }
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "graviton_performance" {
  dashboard_name = "${local.name_prefix}-performance-comparison"

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
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.x86_baseline.id],
            [".", ".", ".", aws_instance.arm_graviton.id]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "CPU Utilization Comparison"
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
            ["AWS/EC2", "NetworkIn", "InstanceId", aws_instance.x86_baseline.id],
            [".", ".", ".", aws_instance.arm_graviton.id]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Network In Comparison"
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
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.x86_baseline.id],
            [".", ".", ".", aws_instance.arm_graviton.id]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Network Out Comparison"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["GravitonDemo/EC2", "cpu_usage_user", "InstanceId", aws_instance.x86_baseline.id],
            [".", ".", ".", aws_instance.arm_graviton.id]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "CPU Usage (User) Comparison"
        }
      }
    ]
  })
}

# CloudWatch Alarm for Cost Monitoring
resource "aws_cloudwatch_metric_alarm" "cost_alert" {
  alarm_name          = "${local.name_prefix}-cost-alert"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = "86400"
  statistic           = "Maximum"
  threshold           = var.cost_alert_threshold
  alarm_description   = "This metric monitors estimated charges for the Graviton demo"
  alarm_actions       = [aws_sns_topic.cost_alerts.arn]

  dimensions = {
    Currency = "USD"
  }

  tags = local.common_tags
}

# SNS Topic for Cost Alerts
resource "aws_sns_topic" "cost_alerts" {
  name = "${local.name_prefix}-cost-alerts"
  
  tags = local.common_tags
}

# CloudWatch Log Group for application logs
resource "aws_cloudwatch_log_group" "graviton_demo" {
  name              = "/aws/ec2/${local.name_prefix}"
  retention_in_days = 7
  
  tags = local.common_tags
}