# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data sources for existing resources
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Get default VPC if vpc_id is not provided
data "aws_vpc" "default" {
  count   = var.vpc_id == null ? 1 : 0
  default = true
}

# Get default subnets if subnet_ids is not provided
data "aws_subnets" "default" {
  count = length(var.subnet_ids) == 0 ? 1 : 0
  
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  
  filter {
    name   = "default-for-az"
    values = ["true"]
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
    name   = "state"
    values = ["available"]
  }
}

# Local values for computed configurations
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  vpc_id      = var.vpc_id != null ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_ids  = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids
  
  # User data script for web server setup
  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    project_name = var.project_name
    environment  = var.environment
  }))
  
  common_tags = merge(
    {
      Name        = local.name_prefix
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
}

# Security Group for Web Application
resource "aws_security_group" "web_app" {
  name_prefix = "${local.name_prefix}-web-"
  description = "Security group for auto-scaled web application"
  vpc_id      = local.vpc_id

  # HTTP traffic
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # HTTPS traffic
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # SSH access (for troubleshooting)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  # All outbound traffic
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-web-sg"
  })
}

# Launch Template for Auto Scaling Group
resource "aws_launch_template" "web_app" {
  name_prefix   = "${local.name_prefix}-template-"
  description   = "Launch template for auto-scaled web application"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  user_data     = local.user_data

  vpc_security_group_ids = [aws_security_group.web_app.id]

  # Enable detailed monitoring
  monitoring {
    enabled = var.enable_detailed_monitoring
  }

  # Instance metadata options (IMDSv2)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = var.enable_imds_v2 ? "required" : "optional"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  # Instance tags
  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-web-instance"
    })
  }

  # Volume tags
  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-web-volume"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-launch-template"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Application Load Balancer
resource "aws_lb" "web_app" {
  name                       = "${local.name_prefix}-alb-${random_string.suffix.result}"
  load_balancer_type         = var.load_balancer_type
  internal                   = var.internal_load_balancer
  security_groups            = [aws_security_group.web_app.id]
  subnets                    = local.subnet_ids
  enable_deletion_protection = var.enable_deletion_protection
  enable_http2               = var.enable_http2

  # Access logs configuration
  dynamic "access_logs" {
    for_each = var.enable_access_logs ? [1] : []
    content {
      bucket  = var.access_logs_bucket
      prefix  = var.access_logs_prefix
      enabled = true
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb"
  })
}

# Target Group for Load Balancer
resource "aws_lb_target_group" "web_app" {
  name                 = "${local.name_prefix}-tg-${random_string.suffix.result}"
  port                 = 80
  protocol             = "HTTP"
  vpc_id               = local.vpc_id
  target_type          = "instance"
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = var.health_check_enabled
    healthy_threshold   = var.healthy_threshold
    unhealthy_threshold = var.unhealthy_threshold
    timeout             = var.health_check_timeout
    interval            = var.health_check_interval
    path                = var.health_check_path
    matcher             = "200"
    protocol            = "HTTP"
    port                = "traffic-port"
  }

  # Disable session stickiness for better load distribution
  stickiness {
    enabled = false
    type    = "lb_cookie"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-target-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Load Balancer Listener
resource "aws_lb_listener" "web_app" {
  load_balancer_arn = aws_lb.web_app.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_app.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-listener"
  })
}

# Auto Scaling Group
resource "aws_autoscaling_group" "web_app" {
  name                      = "${local.name_prefix}-asg-${random_string.suffix.result}"
  min_size                  = var.min_size
  max_size                  = var.max_size
  desired_capacity          = var.desired_capacity
  health_check_grace_period = var.health_check_grace_period
  health_check_type         = "ELB"
  default_cooldown          = var.default_cooldown
  vpc_zone_identifier       = local.subnet_ids
  target_group_arns         = [aws_lb_target_group.web_app.arn]

  launch_template {
    id      = aws_launch_template.web_app.id
    version = "$Latest"
  }

  # Enable metrics collection for detailed monitoring
  dynamic "enabled_metrics" {
    for_each = var.enable_detailed_monitoring ? [1] : []
    content {
      metrics = [
        "GroupMinSize",
        "GroupMaxSize",
        "GroupDesiredCapacity",
        "GroupInServiceInstances",
        "GroupPendingInstances",
        "GroupStandbyInstances",
        "GroupTerminatingInstances",
        "GroupTotalInstances"
      ]
      granularity = "1Minute"
    }
  }

  # Instance refresh configuration for rolling updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = var.health_check_grace_period
    }
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-asg-instance"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# CPU Target Tracking Scaling Policy
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "${local.name_prefix}-cpu-target-tracking"
  scaling_adjustment     = 0
  adjustment_type        = "ChangeInCapacity"
  cooldown               = var.scale_out_cooldown
  autoscaling_group_name = aws_autoscaling_group.web_app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value         = var.cpu_target_value
    scale_out_cooldown   = var.scale_out_cooldown
    scale_in_cooldown    = var.scale_in_cooldown
    disable_scale_in     = false
  }

  depends_on = [aws_autoscaling_group.web_app]
}

# ALB Request Count Target Tracking Scaling Policy
resource "aws_autoscaling_policy" "alb_request_count_tracking" {
  name                   = "${local.name_prefix}-alb-request-count-tracking"
  scaling_adjustment     = 0
  adjustment_type        = "ChangeInCapacity"
  cooldown               = var.scale_out_cooldown
  autoscaling_group_name = aws_autoscaling_group.web_app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.web_app.arn_suffix}/${aws_lb_target_group.web_app.arn_suffix}"
    }
    target_value         = var.alb_request_count_target
    scale_out_cooldown   = var.scale_out_cooldown
    scale_in_cooldown    = var.scale_in_cooldown
    disable_scale_in     = false
  }

  depends_on = [aws_autoscaling_group.web_app]
}

# Scheduled Scaling Actions (Optional)
resource "aws_autoscaling_schedule" "scale_up_business_hours" {
  count                  = var.enable_scheduled_scaling ? 1 : 0
  scheduled_action_name  = "${local.name_prefix}-scale-up-business-hours"
  min_size               = var.business_hours_min_size
  max_size               = var.business_hours_max_size
  desired_capacity       = var.business_hours_desired_capacity
  recurrence             = var.business_hours_scale_up_recurrence
  autoscaling_group_name = aws_autoscaling_group.web_app.name
}

resource "aws_autoscaling_schedule" "scale_down_after_hours" {
  count                  = var.enable_scheduled_scaling ? 1 : 0
  scheduled_action_name  = "${local.name_prefix}-scale-down-after-hours"
  min_size               = var.after_hours_min_size
  max_size               = var.after_hours_max_size
  desired_capacity       = var.after_hours_desired_capacity
  recurrence             = var.business_hours_scale_down_recurrence
  autoscaling_group_name = aws_autoscaling_group.web_app.name
}

# CloudWatch Alarms for Monitoring (Optional)
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  count               = var.create_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${local.name_prefix}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = var.high_cpu_threshold
  alarm_description   = "This metric monitors ec2 cpu utilization across Auto Scaling Group"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web_app.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-high-cpu-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  count               = var.create_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${local.name_prefix}-unhealthy-targets"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors unhealthy targets in the target group"

  dimensions = {
    TargetGroup    = aws_lb_target_group.web_app.arn_suffix
    LoadBalancer   = aws_lb.web_app.arn_suffix
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-unhealthy-targets-alarm"
  })
}

# Create user data file for launch template
resource "local_file" "user_data" {
  filename = "${path.module}/user-data.sh"
  content  = templatefile("${path.module}/user-data.tpl", {
    project_name = var.project_name
    environment  = var.environment
  })
}