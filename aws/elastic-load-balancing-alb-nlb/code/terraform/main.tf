# main.tf - Main configuration for Elastic Load Balancing infrastructure

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source for current AWS caller identity
data "aws_caller_identity" "current" {}

# Data source for current AWS region
data "aws_region" "current" {}

# Data source for default VPC (if vpc_id not provided)
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

# Data source for specified VPC (if vpc_id provided)
data "aws_vpc" "selected" {
  count = var.vpc_id != "" ? 1 : 0
  id    = var.vpc_id
}

# Data source for subnets (if subnet_ids not provided)
data "aws_subnets" "default" {
  count = length(var.subnet_ids) == 0 ? 1 : 0
  
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  
  filter {
    name   = "availability-zone"
    values = data.aws_availability_zones.available.names
  }
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Data source for latest Amazon Linux 2 AMI
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

# Local values for resource configuration
locals {
  vpc_id          = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_ids      = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids
  project_name    = var.project_name != "" ? var.project_name : "elb-demo"
  random_suffix   = random_id.suffix.hex
  alb_name        = var.alb_name != "" ? var.alb_name : "${local.project_name}-alb-${local.random_suffix}"
  nlb_name        = var.nlb_name != "" ? var.nlb_name : "${local.project_name}-nlb-${local.random_suffix}"
  
  common_tags = merge(
    {
      Environment = var.environment
      Project     = local.project_name
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# Security Group for Application Load Balancer
resource "aws_security_group" "alb" {
  name_prefix = "${local.project_name}-alb-"
  description = "Security group for Application Load Balancer"
  vpc_id      = local.vpc_id

  # HTTP traffic
  ingress {
    description = "HTTP traffic from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS traffic
  ingress {
    description = "HTTPS traffic from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-alb-sg"
    Type = "ALB-SecurityGroup"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security Group for Network Load Balancer
resource "aws_security_group" "nlb" {
  name_prefix = "${local.project_name}-nlb-"
  description = "Security group for Network Load Balancer"
  vpc_id      = local.vpc_id

  # TCP traffic on port 80
  ingress {
    description = "TCP traffic from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-nlb-sg"
    Type = "NLB-SecurityGroup"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security Group for EC2 instances
resource "aws_security_group" "ec2" {
  name_prefix = "${local.project_name}-ec2-"
  description = "Security group for EC2 instances behind load balancers"
  vpc_id      = local.vpc_id

  # HTTP traffic from ALB
  ingress {
    description     = "HTTP traffic from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # HTTP traffic from NLB
  ingress {
    description     = "HTTP traffic from NLB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.nlb.id]
  }

  # SSH access (conditional)
  dynamic "ingress" {
    for_each = var.allow_ssh_access ? [1] : []
    content {
      description = "SSH access"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_cidr_blocks
    }
  }

  # Outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-ec2-sg"
    Type = "EC2-SecurityGroup"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# User data script for EC2 instances
locals {
  user_data = base64encode(<<-EOF
#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd

# Create a simple web page with instance information
cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Load Balancer Demo</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 600px; margin: 0 auto; }
        .info { background: #f0f0f0; padding: 20px; margin: 20px 0; border-radius: 5px; }
        .header { color: #333; }
    </style>
</head>
<body>
    <div class="container">
        <h1 class="header">Load Balancer Demo Server</h1>
        <div class="info">
            <h2>Server Information</h2>
            <p><strong>Hostname:</strong> $(hostname -f)</p>
            <p><strong>Instance ID:</strong> $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>
            <p><strong>Availability Zone:</strong> $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>
            <p><strong>Instance Type:</strong> $(curl -s http://169.254.169.254/latest/meta-data/instance-type)</p>
            <p><strong>Local IP:</strong> $(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)</p>
            <p><strong>Public IP:</strong> $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)</p>
        </div>
        <div class="info">
            <h2>Load Balancer Test</h2>
            <p>This page is served by one of the instances behind the load balancer.</p>
            <p>Refresh the page multiple times to see traffic distribution across instances.</p>
        </div>
    </div>
</body>
</html>
HTML

# Replace placeholders with actual values
sed -i "s/\$(hostname -f)/$(hostname -f)/g" /var/www/html/index.html
sed -i "s/\$(curl -s http:\/\/169.254.169.254\/latest\/meta-data\/instance-id)/$(curl -s http://169.254.169.254/latest/meta-data/instance-id)/g" /var/www/html/index.html
sed -i "s/\$(curl -s http:\/\/169.254.169.254\/latest\/meta-data\/placement\/availability-zone)/$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)/g" /var/www/html/index.html
sed -i "s/\$(curl -s http:\/\/169.254.169.254\/latest\/meta-data\/instance-type)/$(curl -s http://169.254.169.254/latest/meta-data/instance-type)/g" /var/www/html/index.html
sed -i "s/\$(curl -s http:\/\/169.254.169.254\/latest\/meta-data\/local-ipv4)/$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)/g" /var/www/html/index.html
sed -i "s/\$(curl -s http:\/\/169.254.169.254\/latest\/meta-data\/public-ipv4)/$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)/g" /var/www/html/index.html

# Create health check endpoint
echo "OK" > /var/www/html/health

# Configure Apache to serve the content
chkconfig httpd on
EOF
  )
}

# EC2 instances
resource "aws_instance" "web" {
  count                  = var.instance_count
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = element(local.subnet_ids, count.index)
  vpc_security_group_ids = [aws_security_group.ec2.id]
  user_data              = local.user_data

  # Enable detailed monitoring
  monitoring = true

  # Root block device configuration
  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
    
    tags = merge(local.common_tags, {
      Name = "${local.project_name}-web-${count.index + 1}-root"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-web-${count.index + 1}"
    Type = "WebServer"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Application Load Balancer Target Group
resource "aws_lb_target_group" "alb" {
  name     = "${local.project_name}-alb-tg-${local.random_suffix}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = local.vpc_id

  # Health check configuration
  health_check {
    enabled             = true
    healthy_threshold   = var.healthy_threshold
    unhealthy_threshold = var.unhealthy_threshold
    timeout             = var.health_check_timeout
    interval            = var.health_check_interval
    path                = "/"
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  # Stickiness configuration
  stickiness {
    enabled         = var.enable_stickiness
    type            = "lb_cookie"
    cookie_duration = var.stickiness_duration
  }

  # Deregistration delay
  deregistration_delay = var.deregistration_delay

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-alb-target-group"
    Type = "ALB-TargetGroup"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Network Load Balancer Target Group
resource "aws_lb_target_group" "nlb" {
  name     = "${local.project_name}-nlb-tg-${local.random_suffix}"
  port     = 80
  protocol = "TCP"
  vpc_id   = local.vpc_id

  # Health check configuration for NLB
  health_check {
    enabled             = true
    healthy_threshold   = var.healthy_threshold
    unhealthy_threshold = var.unhealthy_threshold
    timeout             = var.health_check_timeout
    interval            = var.health_check_interval
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  # Deregistration delay
  deregistration_delay = var.deregistration_delay

  # Preserve client IP
  preserve_client_ip = true

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-nlb-target-group"
    Type = "NLB-TargetGroup"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Target group attachments for ALB
resource "aws_lb_target_group_attachment" "alb" {
  count            = var.instance_count
  target_group_arn = aws_lb_target_group.alb.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

# Target group attachments for NLB
resource "aws_lb_target_group_attachment" "nlb" {
  count            = var.instance_count
  target_group_arn = aws_lb_target_group.nlb.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

# Application Load Balancer
resource "aws_lb" "alb" {
  name               = local.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.subnet_ids

  # Load balancer configuration
  enable_deletion_protection = var.enable_deletion_protection
  idle_timeout               = var.alb_idle_timeout
  enable_http2               = true
  enable_waf_fail_open       = false

  # Access logs (optional - requires S3 bucket)
  # access_logs {
  #   bucket  = aws_s3_bucket.alb_logs.bucket
  #   prefix  = "alb-logs"
  #   enabled = true
  # }

  tags = merge(local.common_tags, {
    Name = local.alb_name
    Type = "ApplicationLoadBalancer"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Network Load Balancer
resource "aws_lb" "nlb" {
  name               = local.nlb_name
  internal           = false
  load_balancer_type = "network"
  subnets            = local.subnet_ids

  # Load balancer configuration
  enable_deletion_protection     = var.enable_deletion_protection
  enable_cross_zone_load_balancing = var.enable_cross_zone_load_balancing

  # Access logs (optional - requires S3 bucket)
  # access_logs {
  #   bucket  = aws_s3_bucket.nlb_logs.bucket
  #   prefix  = "nlb-logs"
  #   enabled = true
  # }

  tags = merge(local.common_tags, {
    Name = local.nlb_name
    Type = "NetworkLoadBalancer"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ALB Listener
resource "aws_lb_listener" "alb_http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-alb-listener-http"
    Type = "ALB-Listener"
  })
}

# NLB Listener
resource "aws_lb_listener" "nlb_tcp" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-nlb-listener-tcp"
    Type = "NLB-Listener"
  })
}

# Optional: ALB Listener Rule for health checks
resource "aws_lb_listener_rule" "alb_health" {
  listener_arn = aws_lb_listener.alb_http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb.arn
  }

  condition {
    path_pattern {
      values = ["/health"]
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-alb-health-rule"
    Type = "ALB-ListenerRule"
  })
}