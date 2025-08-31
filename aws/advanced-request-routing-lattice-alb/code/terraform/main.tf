# Advanced Request Routing with VPC Lattice and ALB
# This Terraform configuration creates a sophisticated microservices networking solution
# using VPC Lattice for cross-VPC communication and ALB for advanced layer 7 routing

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name_suffix    = var.random_suffix != "" ? var.random_suffix : random_id.suffix.hex
  resource_name  = "${var.project_name}-${local.name_suffix}"
  
  # Get default VPC if not specified
  vpc_id = var.default_vpc_id != "" ? var.default_vpc_id : data.aws_vpc.default.id
  
  common_tags = {
    Project = var.project_name
    Environment = var.environment
  }
}

# Get default VPC if no VPC ID provided
data "aws_vpc" "default" {
  count   = var.default_vpc_id == "" ? 1 : 0
  default = true
}

# Get default subnets for ALB (requires at least 2 AZs)
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

#------------------------------------------------------------------------------
# VPC Lattice Service Network
#------------------------------------------------------------------------------

# Create VPC Lattice Service Network - the foundation for application networking
resource "aws_vpclattice_service_network" "main" {
  name      = "advanced-routing-network-${local.name_suffix}"
  auth_type = var.lattice_auth_type
  
  tags = merge(local.common_tags, {
    Name = "advanced-routing-network-${local.name_suffix}"
    Component = "ServiceNetwork"
  })
}

#------------------------------------------------------------------------------
# Target VPC Infrastructure
#------------------------------------------------------------------------------

# Create additional VPC for multi-VPC demonstration
resource "aws_vpc" "target" {
  cidr_block           = var.target_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(local.common_tags, {
    Name = "lattice-target-vpc-${local.name_suffix}"
    Component = "TargetVPC"
  })
}

# Create subnet in target VPC
resource "aws_subnet" "target" {
  vpc_id                  = aws_vpc.target.id
  cidr_block              = var.target_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false
  
  tags = merge(local.common_tags, {
    Name = "lattice-subnet-${local.name_suffix}"
    Component = "TargetSubnet"
  })
}

# Associate default VPC with service network
resource "aws_vpclattice_service_network_vpc_association" "default" {
  vpc_identifier             = local.vpc_id
  service_network_identifier = aws_vpclattice_service_network.main.id
  
  tags = merge(local.common_tags, {
    Name = "default-vpc-association-${local.name_suffix}"
    Component = "VPCAssociation"
  })
}

# Associate target VPC with service network
resource "aws_vpclattice_service_network_vpc_association" "target" {
  vpc_identifier             = aws_vpc.target.id
  service_network_identifier = aws_vpclattice_service_network.main.id
  
  tags = merge(local.common_tags, {
    Name = "target-vpc-association-${local.name_suffix}"
    Component = "VPCAssociation"
  })
}

#------------------------------------------------------------------------------
# Security Groups
#------------------------------------------------------------------------------

# Security group for ALB - allows traffic from VPC Lattice
resource "aws_security_group" "alb" {
  name_prefix = "lattice-alb-sg-${local.name_suffix}-"
  description = "Security group for VPC Lattice ALB targets"
  vpc_id      = local.vpc_id
  
  # Allow HTTP traffic from specified CIDR blocks
  dynamic "ingress" {
    for_each = var.allowed_cidr_blocks
    content {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
      description = "HTTP from ${ingress.value}"
    }
  }
  
  # Allow HTTPS traffic from specified CIDR blocks
  dynamic "ingress" {
    for_each = var.allowed_cidr_blocks
    content {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
      description = "HTTPS from ${ingress.value}"
    }
  }
  
  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }
  
  tags = merge(local.common_tags, {
    Name = "lattice-alb-sg-${local.name_suffix}"
    Component = "SecurityGroup"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Security group for EC2 instances - allows traffic from ALB
resource "aws_security_group" "instances" {
  name_prefix = "lattice-instances-sg-${local.name_suffix}-"
  description = "Security group for EC2 instances behind ALB"
  vpc_id      = local.vpc_id
  
  # Allow HTTP traffic from ALB security group
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "HTTP from ALB"
  }
  
  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }
  
  tags = merge(local.common_tags, {
    Name = "lattice-instances-sg-${local.name_suffix}"
    Component = "SecurityGroup"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

#------------------------------------------------------------------------------
# Application Load Balancer
#------------------------------------------------------------------------------

# Internal ALB for API services
resource "aws_lb" "api_service" {
  name               = "api-service-alb-${local.name_suffix}"
  load_balancer_type = "application"
  scheme             = "internal"
  
  security_groups = [aws_security_group.alb.id]
  subnets         = data.aws_subnets.default.ids
  
  enable_deletion_protection = var.alb_deletion_protection
  
  dynamic "access_logs" {
    for_each = var.alb_access_logs_enabled ? [1] : []
    content {
      bucket  = aws_s3_bucket.alb_logs[0].bucket
      prefix  = "api-service-alb"
      enabled = true
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "api-service-alb-${local.name_suffix}"
    Component = "LoadBalancer"
  })
}

# S3 bucket for ALB access logs (optional)
resource "aws_s3_bucket" "alb_logs" {
  count  = var.alb_access_logs_enabled ? 1 : 0
  bucket = "alb-logs-${local.resource_name}-${data.aws_caller_identity.current.account_id}"
  
  tags = merge(local.common_tags, {
    Name = "alb-logs-${local.name_suffix}"
    Component = "Storage"
  })
}

resource "aws_s3_bucket_policy" "alb_logs" {
  count  = var.alb_access_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_elb_service_account.main[0].id}:root"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs[0].arn}/api-service-alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs[0].arn}/api-service-alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.alb_logs[0].arn
      }
    ]
  })
}

# Get ELB service account for ALB logs
data "aws_elb_service_account" "main" {
  count = var.alb_access_logs_enabled ? 1 : 0
}

#------------------------------------------------------------------------------
# EC2 Instances
#------------------------------------------------------------------------------

# User data script for web servers
locals {
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    environment = var.environment
    project     = var.project_name
  }))
}

# Launch EC2 instances for ALB targets
resource "aws_instance" "api_service" {
  count = var.instance_count
  
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[count.index % length(data.aws_subnets.default.ids)]
  vpc_security_group_ids = [aws_security_group.instances.id]
  
  user_data = local.user_data
  
  monitoring = var.enable_detailed_monitoring
  
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    http_put_response_hop_limit = 1
  }
  
  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }
  
  tags = merge(local.common_tags, {
    Name = "api-service-${local.name_suffix}-${count.index + 1}"
    Component = "WebServer"
  })
}

#------------------------------------------------------------------------------
# ALB Target Groups and Listeners
#------------------------------------------------------------------------------

# Target group for API services
resource "aws_lb_target_group" "api_service" {
  name     = "api-tg-${local.name_suffix}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = local.vpc_id
  
  health_check {
    enabled             = true
    healthy_threshold   = var.target_group_healthy_threshold
    interval            = var.target_group_health_check_interval
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }
  
  tags = merge(local.common_tags, {
    Name = "api-tg-${local.name_suffix}"
    Component = "TargetGroup"
  })
}

# Register instances with target group
resource "aws_lb_target_group_attachment" "api_service" {
  count = var.instance_count
  
  target_group_arn = aws_lb_target_group.api_service.arn
  target_id        = aws_instance.api_service[count.index].id
  port             = 80
}

# ALB HTTP listener
resource "aws_lb_listener" "api_service_http" {
  load_balancer_arn = aws_lb.api_service.arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_service.arn
  }
  
  tags = merge(local.common_tags, {
    Name = "api-service-http-listener"
    Component = "Listener"
  })
}

# ALB HTTPS listener (optional)
resource "aws_lb_listener" "api_service_https" {
  count = var.enable_https ? 1 : 0
  
  load_balancer_arn = aws_lb.api_service.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.certificate_arn
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_service.arn
  }
  
  tags = merge(local.common_tags, {
    Name = "api-service-https-listener"
    Component = "Listener"
  })
}

#------------------------------------------------------------------------------
# VPC Lattice Service and Target Groups
#------------------------------------------------------------------------------

# Create VPC Lattice service
resource "aws_vpclattice_service" "api_gateway" {
  name      = "api-gateway-service-${local.name_suffix}"
  auth_type = var.lattice_auth_type
  
  tags = merge(local.common_tags, {
    Name = "api-gateway-service-${local.name_suffix}"
    Component = "LatticeService"
  })
}

# Associate service with service network
resource "aws_vpclattice_service_network_service_association" "api_gateway" {
  service_network_identifier = aws_vpclattice_service_network.main.id
  service_identifier         = aws_vpclattice_service.api_gateway.id
  
  tags = merge(local.common_tags, {
    Name = "api-gateway-association-${local.name_suffix}"
    Component = "ServiceAssociation"
  })
}

# Create VPC Lattice target group for ALB
resource "aws_vpclattice_target_group" "alb_targets" {
  name = "alb-targets-${local.name_suffix}"
  type = "ALB"
  
  config {
    vpc_identifier = local.vpc_id
    port           = 80
    protocol       = "HTTP"
  }
  
  tags = merge(local.common_tags, {
    Name = "alb-targets-${local.name_suffix}"
    Component = "LatticeTargetGroup"
  })
}

# Register ALB as target in VPC Lattice target group
resource "aws_vpclattice_target_group_attachment" "alb" {
  target_group_identifier = aws_vpclattice_target_group.alb_targets.id
  
  target {
    id = aws_lb.api_service.arn
  }
}

#------------------------------------------------------------------------------
# VPC Lattice Listener and Routing Rules
#------------------------------------------------------------------------------

# Create HTTP listener for VPC Lattice service
resource "aws_vpclattice_listener" "http" {
  name               = "http-listener"
  protocol           = "HTTP"
  port               = 80
  service_identifier = aws_vpclattice_service.api_gateway.id
  
  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.alb_targets.id
        weight                  = 100
      }
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "http-listener"
    Component = "LatticeListener"
  })
}

# Header-based routing rule for service versioning (highest priority)
resource "aws_vpclattice_listener_rule" "beta_header" {
  count = var.enable_header_routing ? 1 : 0
  
  service_identifier  = aws_vpclattice_service.api_gateway.id
  listener_identifier = aws_vpclattice_listener.http.listener_id
  name                = "beta-header-rule"
  priority            = 5
  
  match {
    http_match {
      header_matches {
        name            = var.beta_header_name
        case_sensitive  = false
        match {
          exact = var.beta_header_value
        }
      }
    }
  }
  
  action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.alb_targets.id
        weight                  = 100
      }
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "beta-header-rule"
    Component = "RoutingRule"
  })
}

# Path-based routing rule for API v1
resource "aws_vpclattice_listener_rule" "api_v1_path" {
  count = var.enable_path_routing ? 1 : 0
  
  service_identifier  = aws_vpclattice_service.api_gateway.id
  listener_identifier = aws_vpclattice_listener.http.listener_id
  name                = "api-v1-path-rule"
  priority            = 10
  
  match {
    http_match {
      path_match {
        case_sensitive = false
        match {
          prefix = var.api_path_prefix
        }
      }
    }
  }
  
  action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.alb_targets.id
        weight                  = 100
      }
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "api-v1-path-rule"
    Component = "RoutingRule"
  })
}

# Method-based routing rule for POST requests
resource "aws_vpclattice_listener_rule" "post_method" {
  count = var.enable_method_routing ? 1 : 0
  
  service_identifier  = aws_vpclattice_service.api_gateway.id
  listener_identifier = aws_vpclattice_listener.http.listener_id
  name                = "post-method-rule"
  priority            = 15
  
  match {
    http_match {
      method = "POST"
    }
  }
  
  action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.alb_targets.id
        weight                  = 100
      }
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "post-method-rule"
    Component = "RoutingRule"
  })
}

# Security rule - block admin endpoints with fixed response
resource "aws_vpclattice_listener_rule" "admin_block" {
  service_identifier  = aws_vpclattice_service.api_gateway.id
  listener_identifier = aws_vpclattice_listener.http.listener_id
  name                = "admin-path-rule"
  priority            = 20
  
  match {
    http_match {
      path_match {
        case_sensitive = false
        match {
          exact = "/admin"
        }
      }
    }
  }
  
  action {
    fixed_response {
      status_code = 403
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "admin-block-rule"
    Component = "SecurityRule"
  })
}

#------------------------------------------------------------------------------
# IAM Authentication Policy for VPC Lattice
#------------------------------------------------------------------------------

# IAM auth policy for VPC Lattice service
resource "aws_vpclattice_auth_policy" "api_gateway" {
  count = var.enable_lattice_auth_policy && var.lattice_auth_type == "AWS_IAM" ? 1 : 0
  
  resource_identifier = aws_vpclattice_service.api_gateway.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = "vpc-lattice-svcs:Invoke"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:PrincipalAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Effect = "Deny"
        Principal = "*"
        Action = "vpc-lattice-svcs:Invoke"
        Resource = "*"
        Condition = {
          StringEquals = {
            "vpc-lattice-svcs:RequestPath" = "/admin"
          }
        }
      }
    ]
  })
}