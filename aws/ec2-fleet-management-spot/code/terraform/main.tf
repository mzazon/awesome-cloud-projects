# Data sources for existing resources
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Get default VPC and subnets if using default VPC
data "aws_vpc" "default" {
  count   = var.use_default_vpc ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = var.use_default_vpc ? 1 : 0
  
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }
}

# Get latest Amazon Linux 2 AMI
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

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for computed resources
locals {
  vpc_id     = var.use_default_vpc ? data.aws_vpc.default[0].id : var.vpc_id
  subnet_ids = var.use_default_vpc ? data.aws_subnets.default[0].ids : var.subnet_ids
  
  # Generate availability zones from subnet IDs
  availability_zones = [for subnet_id in local.subnet_ids : 
    data.aws_subnet.fleet_subnets[subnet_id].availability_zone
  ]
  
  # Resource naming
  resource_prefix = "${var.project_name}-${random_string.suffix.result}"
  
  # Default user data script
  default_user_data = base64encode(templatefile("${path.module}/templates/user_data.sh", {
    project_name = var.project_name
  }))
  
  # Use custom user data if provided, otherwise use default
  user_data = var.user_data_script != "" ? base64encode(var.user_data_script) : local.default_user_data
  
  # Common tags
  common_tags = merge(var.resource_tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# Get subnet information for availability zones
data "aws_subnet" "fleet_subnets" {
  for_each = toset(local.subnet_ids)
  id       = each.value
}

# Create key pair if specified
resource "aws_key_pair" "fleet_key" {
  count      = var.create_key_pair ? 1 : 0
  key_name   = var.key_pair_name != "" ? var.key_pair_name : "${local.resource_prefix}-key"
  public_key = file("${path.module}/key.pub")
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-key"
  })
}

# Security group for fleet instances
resource "aws_security_group" "fleet_sg" {
  name        = "${local.resource_prefix}-sg"
  description = "Security group for EC2 Fleet demo instances"
  vpc_id      = local.vpc_id
  
  # SSH access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }
  
  # HTTP access
  ingress {
    description = "HTTP access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }
  
  # HTTPS access
  ingress {
    description = "HTTPS access"
    from_port   = 443
    to_port     = 443
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
    Name = "${local.resource_prefix}-sg"
  })
}

# Additional security group rules if specified
resource "aws_security_group_rule" "additional_rules" {
  count = length(var.additional_security_group_rules)
  
  security_group_id = aws_security_group.fleet_sg.id
  type              = var.additional_security_group_rules[count.index].type
  from_port         = var.additional_security_group_rules[count.index].from_port
  to_port           = var.additional_security_group_rules[count.index].to_port
  protocol          = var.additional_security_group_rules[count.index].protocol
  cidr_blocks       = var.additional_security_group_rules[count.index].cidr_blocks
  description       = var.additional_security_group_rules[count.index].description
}

# IAM role for Spot Fleet
resource "aws_iam_role" "spot_fleet_role" {
  name = "${local.resource_prefix}-spot-fleet-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "spotfleet.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-spot-fleet-role"
  })
}

# Attach AWS managed policy to Spot Fleet role
resource "aws_iam_role_policy_attachment" "spot_fleet_policy" {
  role       = aws_iam_role.spot_fleet_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetRequestRole"
}

# IAM role for EC2 instances (for CloudWatch monitoring)
resource "aws_iam_role" "ec2_role" {
  name = "${local.resource_prefix}-ec2-role"
  
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
    Name = "${local.resource_prefix}-ec2-role"
  })
}

# Attach CloudWatch agent policy to EC2 role
resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Instance profile for EC2 instances
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${local.resource_prefix}-ec2-profile"
  role = aws_iam_role.ec2_role.name
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-ec2-profile"
  })
}

# Launch template for EC2 Fleet
resource "aws_launch_template" "fleet_template" {
  name_prefix   = "${local.resource_prefix}-template-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_types[0]
  key_name      = var.create_key_pair ? aws_key_pair.fleet_key[0].key_name : var.key_pair_name
  
  vpc_security_group_ids = [aws_security_group.fleet_sg.id]
  
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }
  
  user_data = local.user_data
  
  monitoring {
    enabled = var.enable_detailed_monitoring
  }
  
  disable_api_termination = var.enable_termination_protection
  
  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.resource_prefix}-fleet-instance"
    })
  }
  
  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name = "${local.resource_prefix}-fleet-volume"
    })
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-launch-template"
  })
}

# EC2 Fleet
resource "aws_ec2_fleet" "main_fleet" {
  launch_template_config {
    launch_template_specification {
      launch_template_id = aws_launch_template.fleet_template.id
      version            = "$Latest"
    }
    
    # Create overrides for each instance type and AZ combination
    dynamic "override" {
      for_each = [
        for pair in setproduct(var.instance_types, local.availability_zones) : {
          instance_type     = pair[0]
          availability_zone = pair[1]
        }
      ]
      content {
        instance_type     = override.value.instance_type
        availability_zone = override.value.availability_zone
      }
    }
  }
  
  target_capacity_specification {
    total_target_capacity   = var.ec2_fleet_target_capacity
    on_demand_target_capacity = var.ec2_fleet_on_demand_capacity
    spot_target_capacity    = var.ec2_fleet_spot_capacity
    default_target_capacity_type = "spot"
  }
  
  on_demand_options {
    allocation_strategy = "diversified"
  }
  
  spot_options {
    allocation_strategy                = "capacity-optimized"
    instance_interruption_behavior    = "terminate"
    replace_unhealthy_instances       = var.replace_unhealthy_instances
  }
  
  type                         = "maintain"
  excess_capacity_termination_policy = "termination"
  replace_unhealthy_instances = var.replace_unhealthy_instances
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-ec2-fleet"
  })
}

# Spot Fleet Request
resource "aws_spot_fleet_request" "main_spot_fleet" {
  iam_fleet_role      = aws_iam_role.spot_fleet_role.arn
  allocation_strategy = var.fleet_allocation_strategy
  target_capacity     = var.spot_fleet_target_capacity
  spot_price          = var.spot_max_price
  
  # Launch specifications for each instance type
  dynamic "launch_specification" {
    for_each = var.instance_types
    content {
      ami                    = data.aws_ami.amazon_linux.id
      instance_type          = launch_specification.value
      key_name               = var.create_key_pair ? aws_key_pair.fleet_key[0].key_name : var.key_pair_name
      security_groups        = [aws_security_group.fleet_sg.id]
      user_data              = local.user_data
      iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
      
      tags = merge(local.common_tags, {
        Name = "${local.resource_prefix}-spot-fleet-instance"
      })
    }
  }
  
  fleet_type                      = "maintain"
  replace_unhealthy_instances     = var.replace_unhealthy_instances
  terminate_instances_with_expiration = true
  
  depends_on = [aws_iam_role_policy_attachment.spot_fleet_policy]
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-spot-fleet"
  })
}

# CloudWatch Dashboard for monitoring
resource "aws_cloudwatch_dashboard" "fleet_dashboard" {
  count          = var.create_cloudwatch_dashboard ? 1 : 0
  dashboard_name = "${local.resource_prefix}-dashboard"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "FleetRequestId", aws_ec2_fleet.main_fleet.id],
            ["AWS/EC2Spot", "AvailableInstancePoolsCount", "FleetRequestId", aws_spot_fleet_request.main_spot_fleet.id]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Fleet Monitoring"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/EC2", "NetworkIn", "FleetRequestId", aws_ec2_fleet.main_fleet.id],
            ["AWS/EC2", "NetworkOut", "FleetRequestId", aws_ec2_fleet.main_fleet.id]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Network Utilization"
          view   = "timeSeries"
        }
      }
    ]
  })
}

# Create user data template file
resource "local_file" "user_data_template" {
  content = templatefile("${path.module}/templates/user_data.sh.tpl", {
    project_name = var.project_name
  })
  filename = "${path.module}/templates/user_data.sh"
}

# CloudWatch Log Group for fleet instances
resource "aws_cloudwatch_log_group" "fleet_logs" {
  name              = "/aws/ec2/fleet/${local.resource_prefix}"
  retention_in_days = 7
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-logs"
  })
}

# SNS Topic for fleet notifications (optional)
resource "aws_sns_topic" "fleet_notifications" {
  name = "${local.resource_prefix}-notifications"
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-notifications"
  })
}

# CloudWatch Alarms for fleet monitoring
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${local.resource_prefix}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ec2 fleet cpu utilization"
  alarm_actions       = [aws_sns_topic.fleet_notifications.arn]
  
  dimensions = {
    FleetRequestId = aws_ec2_fleet.main_fleet.id
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-high-cpu-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "spot_fleet_capacity" {
  alarm_name          = "${local.resource_prefix}-spot-fleet-capacity"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "AvailableInstancePoolsCount"
  namespace           = "AWS/EC2Spot"
  period              = "300"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors spot fleet available capacity"
  alarm_actions       = [aws_sns_topic.fleet_notifications.arn]
  
  dimensions = {
    FleetRequestId = aws_spot_fleet_request.main_spot_fleet.id
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.resource_prefix}-spot-capacity-alarm"
  })
}