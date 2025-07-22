# Generate unique identifier for resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Get current AWS caller identity for account ID
data "aws_caller_identity" "current" {}

# Get available availability zones in the region
data "aws_availability_zones" "available" {
  state = "available"
}

# Get default VPC if not creating new one and no VPC ID provided
data "aws_vpc" "default" {
  count   = var.create_vpc == false && var.vpc_id == "" ? 1 : 0
  default = true
}

# Get existing VPC if VPC ID provided
data "aws_vpc" "existing" {
  count = var.create_vpc == false && var.vpc_id != "" ? 1 : 0
  id    = var.vpc_id
}

# Get subnets for existing VPC
data "aws_subnets" "existing" {
  count = var.create_vpc == false && length(var.subnet_ids) == 0 ? 1 : 0
  
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  
  filter {
    name   = "state"
    values = ["available"]
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
  # Resource naming
  name_prefix = "${var.project_name}-${var.environment}-${random_string.suffix.result}"
  
  # VPC configuration
  vpc_id = var.create_vpc ? aws_vpc.main[0].id : (
    var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  )
  
  # Subnet configuration
  subnet_ids = var.create_vpc ? aws_subnet.main[*].id : (
    length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.existing[0].ids
  )
  
  # Availability zones
  azs = var.create_vpc ? (
    length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 3)
  ) : []
  
  # Combined tags
  common_tags = merge(
    {
      Name        = local.name_prefix
      Environment = var.environment
      Project     = var.project_name
    },
    var.additional_tags
  )
}

# VPC (optional - only created if create_vpc is true)
resource "aws_vpc" "main" {
  count = var.create_vpc ? 1 : 0
  
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# Internet Gateway (only created with new VPC)
resource "aws_internet_gateway" "main" {
  count = var.create_vpc ? 1 : 0
  
  vpc_id = aws_vpc.main[0].id
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# Public subnets (only created with new VPC)
resource "aws_subnet" "main" {
  count = var.create_vpc ? length(local.azs) : 0
  
  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = var.associate_public_ip_address
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-subnet-${count.index + 1}"
    Type = "public"
  })
}

# Route table for public subnets (only created with new VPC)
resource "aws_route_table" "main" {
  count = var.create_vpc ? 1 : 0
  
  vpc_id = aws_vpc.main[0].id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rt"
  })
}

# Route table associations (only created with new VPC)
resource "aws_route_table_association" "main" {
  count = var.create_vpc ? length(aws_subnet.main) : 0
  
  subnet_id      = aws_subnet.main[count.index].id
  route_table_id = aws_route_table.main[0].id
}

# Security Group for Auto Scaling Group instances
resource "aws_security_group" "asg_instances" {
  name_prefix = "${local.name_prefix}-asg-sg"
  description = "Security group for mixed instances Auto Scaling group"
  vpc_id      = local.vpc_id
  
  # HTTP access
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }
  
  # HTTPS access
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }
  
  # SSH access (optional)
  dynamic "ingress" {
    for_each = var.enable_ssh_access ? [1] : []
    
    content {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
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
    Name = "${local.name_prefix}-asg-sg"
  })
}

# Security Group for Application Load Balancer
resource "aws_security_group" "alb" {
  count = var.enable_load_balancer ? 1 : 0
  
  name_prefix = "${local.name_prefix}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = local.vpc_id
  
  # HTTP access
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }
  
  # HTTPS access
  ingress {
    description = "HTTPS"
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
    Name = "${local.name_prefix}-alb-sg"
  })
}

# IAM role for EC2 instances
resource "aws_iam_role" "ec2_instance_role" {
  name_prefix = "${local.name_prefix}-ec2-role"
  
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

# Attach AWS managed policies to the IAM role
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM instance profile
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name_prefix = "${local.name_prefix}-ec2-profile"
  role        = aws_iam_role.ec2_instance_role.name
  
  tags = local.common_tags
}

# User data script for instance initialization
locals {
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    cloudwatch_config = jsonencode({
      metrics = {
        namespace = "AutoScaling/MixedInstances"
        metrics_collected = {
          cpu = {
            measurement                = ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"]
            metrics_collection_interval = 60
          }
          disk = {
            measurement                = ["used_percent"]
            metrics_collection_interval = 60
            resources                   = ["*"]
          }
          mem = {
            measurement                = ["mem_used_percent"]
            metrics_collection_interval = 60
          }
        }
      }
    })
  }))
}

# Create user data script file
resource "local_file" "user_data_script" {
  filename = "${path.module}/user_data.sh"
  content  = <<-EOF
#!/bin/bash
yum update -y
yum install -y httpd

# Get instance metadata to display on the web page
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type)
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
SPOT_TERMINATION=$(curl -s http://169.254.169.254/latest/meta-data/spot/instance-action 2>/dev/null || echo "On-Demand")

# Create informative web page showing instance details
cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Mixed Instance Auto Scaling Demo</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .info { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .spot { color: green; }
        .ondemand { color: blue; }
    </style>
</head>
<body>
    <h1>Mixed Instance Auto Scaling Demo</h1>
    <div class="info">
        <h2>Instance Information</h2>
        <p><strong>Instance ID:</strong> INSTANCE_ID_PLACEHOLDER</p>
        <p><strong>Instance Type:</strong> INSTANCE_TYPE_PLACEHOLDER</p>
        <p><strong>Availability Zone:</strong> AZ_PLACEHOLDER</p>
        <p><strong>Purchase Type:</strong> 
            <span class="PURCHASE_CLASS_PLACEHOLDER">
                PURCHASE_TYPE_PLACEHOLDER
            </span>
        </p>
        <p><strong>Timestamp:</strong> TIMESTAMP_PLACEHOLDER</p>
    </div>
    
    <h2>Auto Scaling Group Benefits</h2>
    <ul>
        <li>Cost optimization with Spot Instances</li>
        <li>High availability across multiple AZs</li>
        <li>Automatic scaling based on demand</li>
        <li>Instance type diversification</li>
    </ul>
</body>
</html>
HTML

# Replace placeholders with actual values
sed -i "s/INSTANCE_ID_PLACEHOLDER/$INSTANCE_ID/g" /var/www/html/index.html
sed -i "s/INSTANCE_TYPE_PLACEHOLDER/$INSTANCE_TYPE/g" /var/www/html/index.html
sed -i "s/AZ_PLACEHOLDER/$AZ/g" /var/www/html/index.html
sed -i "s/TIMESTAMP_PLACEHOLDER/$(date)/g" /var/www/html/index.html

if [ "$SPOT_TERMINATION" = "On-Demand" ]; then
    sed -i "s/PURCHASE_CLASS_PLACEHOLDER/ondemand/g" /var/www/html/index.html
    sed -i "s/PURCHASE_TYPE_PLACEHOLDER/On-Demand/g" /var/www/html/index.html
else
    sed -i "s/PURCHASE_CLASS_PLACEHOLDER/spot/g" /var/www/html/index.html
    sed -i "s/PURCHASE_TYPE_PLACEHOLDER/Spot Instance/g" /var/www/html/index.html
fi

# Start and enable Apache web server
systemctl start httpd
systemctl enable httpd

# Install and configure CloudWatch agent for custom metrics
yum install -y amazon-cloudwatch-agent

# Create CloudWatch agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'JSON'
${cloudwatch_config}
JSON

# Start CloudWatch agent with the configuration
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
EOF
}

# Launch Template for the Auto Scaling Group
resource "aws_launch_template" "main" {
  name_prefix   = "${local.name_prefix}-lt"
  description   = "Launch template for mixed instances Auto Scaling group"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_types[0].instance_type
  key_name      = var.key_pair_name != "" ? var.key_pair_name : null
  
  # Security groups
  vpc_security_group_ids = [aws_security_group.asg_instances.id]
  
  # IAM instance profile
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_instance_profile.name
  }
  
  # User data for instance initialization
  user_data = local.user_data
  
  # Enable detailed monitoring
  monitoring {
    enabled = var.instance_monitoring
  }
  
  # EBS optimization
  ebs_optimized = var.ebs_optimized
  
  # Instance metadata options for security
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }
  
  # Tag specifications for instances
  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name              = "${local.name_prefix}-instance"
      AutoScalingGroup  = "${local.name_prefix}-asg"
    })
  }
  
  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-volume"
    })
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lt"
  })
}

# Auto Scaling Group with Mixed Instance Policy
resource "aws_autoscaling_group" "main" {
  name             = "${local.name_prefix}-asg"
  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity
  
  # Health check configuration
  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period
  default_cooldown          = var.scale_cooldown
  
  # VPC and subnet configuration
  vpc_zone_identifier = local.subnet_ids
  
  # Enable capacity rebalancing for Spot instance management
  capacity_rebalance = var.enable_capacity_rebalance
  
  # Target group integration (if load balancer is enabled)
  target_group_arns = var.enable_load_balancer ? [aws_lb_target_group.main[0].arn] : []
  
  # Mixed instance policy for cost optimization
  mixed_instances_policy {
    # Launch template configuration
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.main.id
        version            = "$Latest"
      }
      
      # Instance type overrides with weighted capacity
      dynamic "override" {
        for_each = var.instance_types
        
        content {
          instance_type     = override.value.instance_type
          weighted_capacity = tostring(override.value.weighted_capacity)
        }
      }
    }
    
    # Instance distribution configuration
    instances_distribution {
      on_demand_allocation_strategy            = "prioritized"
      on_demand_base_capacity                  = var.on_demand_base_capacity
      on_demand_percentage_above_base_capacity = var.on_demand_percentage_above_base_capacity
      spot_allocation_strategy                 = var.spot_allocation_strategy
      spot_instance_pools                      = var.spot_instance_pools
      spot_max_price                           = var.spot_max_price
    }
  }
  
  # Tags
  dynamic "tag" {
    for_each = local.common_tags
    
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
  
  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-asg"
    propagate_at_launch = false
  }
  
  # Instance refresh configuration for rolling updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 300
    }
  }
  
  depends_on = [
    aws_launch_template.main,
    aws_iam_instance_profile.ec2_instance_profile
  ]
}

# CPU-based Auto Scaling Policy
resource "aws_autoscaling_policy" "cpu_scale" {
  name                   = "${local.name_prefix}-cpu-scale"
  autoscaling_group_name = aws_autoscaling_group.main.name
  policy_type            = "TargetTrackingScaling"
  
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value         = var.cpu_target_value
    scale_out_cooldown   = var.scale_cooldown
    scale_in_cooldown    = var.scale_cooldown
  }
}

# Network-based Auto Scaling Policy
resource "aws_autoscaling_policy" "network_scale" {
  name                   = "${local.name_prefix}-network-scale"
  autoscaling_group_name = aws_autoscaling_group.main.name
  policy_type            = "TargetTrackingScaling"
  
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageNetworkIn"
    }
    target_value         = var.network_target_value
    scale_out_cooldown   = var.scale_cooldown
    scale_in_cooldown    = var.scale_cooldown
  }
}

# SNS Topic for Auto Scaling notifications
resource "aws_sns_topic" "asg_notifications" {
  count = var.enable_notifications ? 1 : 0
  
  name_prefix = "${local.name_prefix}-asg-notifications"
  
  tags = local.common_tags
}

# SNS Topic subscription (if email provided)
resource "aws_sns_topic_subscription" "asg_notifications_email" {
  count = var.enable_notifications && var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.asg_notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# Auto Scaling notification configuration
resource "aws_autoscaling_notification" "asg_notifications" {
  count = var.enable_notifications ? 1 : 0
  
  group_names = [aws_autoscaling_group.main.name]
  
  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR",
  ]
  
  topic_arn = aws_sns_topic.asg_notifications[0].arn
}

# Application Load Balancer (optional)
resource "aws_lb" "main" {
  count = var.enable_load_balancer ? 1 : 0
  
  name_prefix        = substr("${local.name_prefix}-alb", 0, 6)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[0].id]
  subnets            = local.subnet_ids
  
  enable_deletion_protection = false
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb"
  })
}

# Target Group for the Load Balancer
resource "aws_lb_target_group" "main" {
  count = var.enable_load_balancer ? 1 : 0
  
  name_prefix = substr("${local.name_prefix}-tg", 0, 6)
  port        = 80
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  
  # Health check configuration
  health_check {
    enabled             = true
    healthy_threshold   = var.load_balancer_healthy_threshold
    unhealthy_threshold = var.load_balancer_unhealthy_threshold
    timeout             = var.load_balancer_health_check_timeout
    interval            = var.load_balancer_health_check_interval
    path                = "/"
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-tg"
  })
}

# Load Balancer Listener
resource "aws_lb_listener" "main" {
  count = var.enable_load_balancer ? 1 : 0
  
  load_balancer_arn = aws_lb.main[0].arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main[0].arn
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-listener"
  })
}