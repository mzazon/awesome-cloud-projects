# main.tf
# EC2 Launch Templates and Auto Scaling Group Infrastructure

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  name_prefix = "${var.environment}-autoscaling-${random_id.suffix.hex}"
  
  # Merge default and additional tags
  common_tags = merge(
    {
      Name        = local.name_prefix
      Environment = var.environment
      Project     = "EC2-Auto-Scaling-Demo"
    },
    var.additional_tags
  )
}

# Data source to get the default VPC
data "aws_vpc" "default" {
  default = true
}

# Data source to get subnets in the default VPC
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

# Data source to get the latest Amazon Linux 2 AMI
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
  
  filter {
    name   = "state"
    values = ["available"]
  }
}

# Security Group for EC2 instances
resource "aws_security_group" "web_server" {
  name_prefix = "${local.name_prefix}-sg-"
  description = "Security group for Auto Scaling demo web servers"
  vpc_id      = data.aws_vpc.default.id

  # HTTP access
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-security-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# IAM role for EC2 instances (optional but recommended for CloudWatch and Systems Manager)
resource "aws_iam_role" "ec2_role" {
  name_prefix = "${local.name_prefix}-ec2-role-"
  
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

# Attach CloudWatch Agent Server Policy to IAM role
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Attach Systems Manager Core Policy to IAM role (for Session Manager access)
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile for the IAM role
resource "aws_iam_instance_profile" "ec2_profile" {
  name_prefix = "${local.name_prefix}-ec2-profile-"
  role        = aws_iam_role.ec2_role.name
  
  tags = local.common_tags
}

# User data script for web server setup
locals {
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    environment = var.environment
  }))
}

# Create user data script file
resource "local_file" "user_data_script" {
  filename = "${path.module}/user_data.sh"
  content  = <<-EOF
#!/bin/bash
# User data script for EC2 instances in Auto Scaling group

# Update system packages
yum update -y

# Install and configure Apache web server
yum install -y httpd

# Create a simple web page with instance information
cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Auto Scaling Demo</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { background-color: #232F3E; color: white; padding: 20px; border-radius: 5px; }
        .content { margin: 20px 0; }
        .info-box { background-color: #E7F3FF; padding: 15px; border-radius: 5px; margin: 10px 0; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🚀 Auto Scaling Demo Server</h1>
        <p>Environment: ${environment}</p>
    </div>
    
    <div class="content">
        <div class="info-box">
            <h3>Instance Information</h3>
            <p><strong>Hostname:</strong> $(hostname -f)</p>
            <p><strong>Instance ID:</strong> $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>
            <p><strong>Availability Zone:</strong> $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>
            <p><strong>Instance Type:</strong> $(curl -s http://169.254.169.254/latest/meta-data/instance-type)</p>
            <p><strong>Launch Time:</strong> $(date)</p>
        </div>
        
        <div class="info-box">
            <h3>Server Status</h3>
            <p>✅ Apache HTTP Server is running</p>
            <p>✅ Auto Scaling Group is managing this instance</p>
            <p>✅ CloudWatch monitoring is enabled</p>
        </div>
    </div>
</body>
</html>
HTML

# Replace template variables in the HTML
sed -i "s/\${environment}/${environment}/g" /var/www/html/index.html

# Update the dynamic information that couldn't be templated
sed -i "s/\$(hostname -f)/$(hostname -f)/g" /var/www/html/index.html
sed -i "s/\$(curl -s http:\/\/169.254.169.254\/latest\/meta-data\/instance-id)/$(curl -s http://169.254.169.254/latest/meta-data/instance-id)/g" /var/www/html/index.html
sed -i "s/\$(curl -s http:\/\/169.254.169.254\/latest\/meta-data\/placement\/availability-zone)/$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)/g" /var/www/html/index.html
sed -i "s/\$(curl -s http:\/\/169.254.169.254\/latest\/meta-data\/instance-type)/$(curl -s http://169.254.169.254/latest/meta-data/instance-type)/g" /var/www/html/index.html
sed -i "s/\$(date)/$(date)/g" /var/www/html/index.html

# Start and enable Apache service
systemctl start httpd
systemctl enable httpd

# Configure CloudWatch agent (optional)
if command -v amazon-cloudwatch-agent-ctl &> /dev/null; then
    echo "CloudWatch agent is available for configuration"
fi

# Log successful completion
echo "$(date): User data script completed successfully" >> /var/log/user-data.log
EOF
}

# Launch Template for EC2 instances
resource "aws_launch_template" "web_server" {
  name_prefix   = "${local.name_prefix}-lt-"
  description   = "Launch template for Auto Scaling demo web servers"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  
  # Associate public IP address based on variable
  network_interfaces {
    associate_public_ip_address = var.enable_public_ip
    security_groups             = [aws_security_group.web_server.id]
    delete_on_termination       = true
  }
  
  # IAM instance profile for CloudWatch and Systems Manager access
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }
  
  # User data for web server setup
  user_data = local.user_data
  
  # Enable detailed monitoring if specified
  monitoring {
    enabled = var.enable_detailed_monitoring
  }
  
  # Instance tags (applied to launched instances)
  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-instance"
    })
  }
  
  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-volume"
    })
  }
  
  # Launch template tags
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-launch-template"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "web_servers" {
  name                = "${local.name_prefix}-asg"
  vpc_zone_identifier = data.aws_subnets.default.ids
  
  # Capacity configuration
  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity
  
  # Health check configuration
  health_check_type         = "EC2"
  health_check_grace_period = var.health_check_grace_period
  
  # Launch template configuration
  launch_template {
    id      = aws_launch_template.web_server.id
    version = "$Latest"
  }
  
  # Enable instance refresh for rolling updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }
  
  # Tags for the Auto Scaling Group
  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-asg"
    propagate_at_launch = false
  }
  
  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
  
  tag {
    key                 = "Project"
    value               = "EC2-Auto-Scaling-Demo"
    propagate_at_launch = true
  }
  
  # Dynamic tags from variables
  dynamic "tag" {
    for_each = var.additional_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
  
  lifecycle {
    create_before_destroy = true
    ignore_changes       = [desired_capacity]
  }
  
  depends_on = [
    aws_launch_template.web_server
  ]
}

# Target Tracking Scaling Policy for CPU Utilization
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name               = "${local.name_prefix}-cpu-target-tracking"
  scaling_adjustment = 4
  adjustment_type    = "ChangeInCapacity"
  cooldown           = var.scale_out_cooldown
  autoscaling_group_name = aws_autoscaling_group.web_servers.name
  policy_type       = "TargetTrackingScaling"
  
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    
    target_value     = var.target_cpu_utilization
    scale_out_cooldown = var.scale_out_cooldown
    scale_in_cooldown  = var.scale_in_cooldown
  }
  
  depends_on = [aws_autoscaling_group.web_servers]
}

# CloudWatch metric collection for Auto Scaling Group
resource "aws_autoscaling_group_metrics_collection" "web_servers" {
  autoscaling_group_name = aws_autoscaling_group.web_servers.name
  
  metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances"
  ]
  
  granularity = "1Minute"
}

# CloudWatch Dashboard for monitoring (optional)
resource "aws_cloudwatch_dashboard" "auto_scaling_dashboard" {
  dashboard_name = "${local.name_prefix}-dashboard"
  
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
            ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", aws_autoscaling_group.web_servers.name],
            [".", "GroupInServiceInstances", ".", "."],
            [".", "GroupMinSize", ".", "."],
            [".", "GroupMaxSize", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Auto Scaling Group Metrics"
          yAxis = {
            left = {
              min = 0
            }
          }
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
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.web_servers.name]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Average CPU Utilization"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      }
    ]
  })
}