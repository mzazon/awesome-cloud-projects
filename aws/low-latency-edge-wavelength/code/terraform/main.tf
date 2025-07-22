# ============================================================================
# Low-Latency Edge Applications with AWS Wavelength and CloudFront
# ============================================================================
# This Terraform configuration deploys a complete edge computing architecture
# combining AWS Wavelength for ultra-low latency processing and CloudFront
# for global content delivery. The solution is optimized for mobile gaming,
# AR/VR applications, and other latency-sensitive workloads.
# ============================================================================

# Data sources to fetch dynamic information
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Get the latest Amazon Linux 2 AMI
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

# Get available Wavelength Zones
data "aws_availability_zones" "wavelength" {
  filter {
    name   = "zone-type"
    values = ["wavelength-zone"]
  }

  state = "available"
}

# ============================================================================
# Random ID for unique resource naming
# ============================================================================
resource "random_id" "project" {
  byte_length = 3
}

locals {
  project_name       = "${var.project_name}-${random_id.project.hex}"
  wavelength_zone    = var.wavelength_zone != "" ? var.wavelength_zone : (length(data.aws_availability_zones.wavelength.names) > 0 ? data.aws_availability_zones.wavelength.names[0] : "")
  availability_zone  = "${data.aws_region.current.name}a"

  common_tags = {
    Project     = local.project_name
    Environment = var.environment
    Recipe      = "building-low-latency-edge-applications-with-aws-wavelength-and-cloudfront"
    ManagedBy   = "terraform"
  }
}

# ============================================================================
# VPC and Networking Configuration
# ============================================================================

# Main VPC that will be extended to Wavelength Zone
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-vpc"
  })
}

# Internet Gateway for regional resources
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-igw"
  })
}

# Wavelength subnet for edge computing resources
resource "aws_subnet" "wavelength" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.wavelength_subnet_cidr
  availability_zone = local.wavelength_zone

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-wavelength-subnet"
    Type = "Wavelength"
  })

  # Ensure Wavelength Zone is available before creating subnet
  depends_on = [data.aws_availability_zones.wavelength]
}

# Regional subnet for backend services
resource "aws_subnet" "regional" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.regional_subnet_cidr
  availability_zone       = local.availability_zone
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-regional-subnet"
    Type = "Regional"
  })
}

# Carrier Gateway for Wavelength mobile connectivity
resource "aws_ec2_carrier_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-carrier-gateway"
  })
}

# Route table for Wavelength subnet
resource "aws_route_table" "wavelength" {
  vpc_id = aws_vpc.main.id

  # Route mobile traffic through carrier gateway
  route {
    cidr_block           = "0.0.0.0/0"
    carrier_gateway_id   = aws_ec2_carrier_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-wavelength-rt"
  })
}

# Route table for regional subnet
resource "aws_route_table" "regional" {
  vpc_id = aws_vpc.main.id

  # Route internet traffic through internet gateway
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-regional-rt"
  })
}

# Associate route tables with subnets
resource "aws_route_table_association" "wavelength" {
  subnet_id      = aws_subnet.wavelength.id
  route_table_id = aws_route_table.wavelength.id
}

resource "aws_route_table_association" "regional" {
  subnet_id      = aws_subnet.regional.id
  route_table_id = aws_route_table.regional.id
}

# ============================================================================
# Security Groups
# ============================================================================

# Security group for Wavelength edge servers
resource "aws_security_group" "wavelength" {
  name_prefix = "${local.project_name}-wavelength-"
  description = "Security group for Wavelength edge applications"
  vpc_id      = aws_vpc.main.id

  # HTTP access for edge applications
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS access for edge applications
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Custom application port (e.g., game server)
  ingress {
    description = "Custom Application Port"
    from_port   = var.application_port
    to_port     = var.application_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Health check port for ALB
  ingress {
    description = "Health Check"
    from_port   = var.health_check_port
    to_port     = var.health_check_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # SSH access for management (optional, restricted to VPC)
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Outbound internet access
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-wavelength-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for regional backend services
resource "aws_security_group" "regional" {
  name_prefix = "${local.project_name}-regional-"
  description = "Security group for regional backend services"
  vpc_id      = aws_vpc.main.id

  # HTTP access from Wavelength subnet
  ingress {
    description     = "HTTP from Wavelength"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.wavelength.id]
  }

  # HTTPS access from Wavelength subnet
  ingress {
    description     = "HTTPS from Wavelength"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.wavelength.id]
  }

  # Database access from Wavelength subnet
  ingress {
    description     = "Database access from Wavelength"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wavelength.id]
  }

  # SSH access for management
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Outbound internet access
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-regional-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# IAM Roles and Policies
# ============================================================================

# IAM role for EC2 instances
resource "aws_iam_role" "ec2_role" {
  name_prefix = "${local.project_name}-ec2-"

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

# IAM policy for CloudWatch monitoring
resource "aws_iam_policy" "cloudwatch_policy" {
  name_prefix = "${local.project_name}-cloudwatch-"
  description = "Policy for CloudWatch monitoring and logging"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
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

  tags = local.common_tags
}

# Attach policies to IAM role
resource "aws_iam_role_policy_attachment" "cloudwatch_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.cloudwatch_policy.arn
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# IAM instance profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name_prefix = "${local.project_name}-ec2-"
  role        = aws_iam_role.ec2_role.name

  tags = local.common_tags
}

# ============================================================================
# User Data Scripts
# ============================================================================

# User data script for Wavelength edge application
locals {
  wavelength_user_data = base64encode(templatefile("${path.module}/user_data/wavelength_app.sh", {
    application_port  = var.application_port
    health_check_port = var.health_check_port
    project_name      = local.project_name
  }))
}

# ============================================================================
# EC2 Instances
# ============================================================================

# Wavelength edge application server
resource "aws_instance" "wavelength_server" {
  ami                     = data.aws_ami.amazon_linux.id
  instance_type           = var.wavelength_instance_type
  subnet_id               = aws_subnet.wavelength.id
  vpc_security_group_ids  = [aws_security_group.wavelength.id]
  iam_instance_profile    = aws_iam_instance_profile.ec2_profile.name
  user_data               = local.wavelength_user_data

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
    
    tags = merge(local.common_tags, {
      Name = "${local.project_name}-wavelength-root"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-wavelength-server"
    Type = "EdgeApplication"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Optional regional backend server
resource "aws_instance" "regional_server" {
  count = var.deploy_regional_backend ? 1 : 0

  ami                     = data.aws_ami.amazon_linux.id
  instance_type           = var.regional_instance_type
  subnet_id               = aws_subnet.regional.id
  vpc_security_group_ids  = [aws_security_group.regional.id]
  iam_instance_profile    = aws_iam_instance_profile.ec2_profile.name

  user_data = base64encode(templatefile("${path.module}/user_data/regional_app.sh", {
    project_name = local.project_name
  }))

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
    
    tags = merge(local.common_tags, {
      Name = "${local.project_name}-regional-root"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-regional-server"
    Type = "BackendApplication"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# Application Load Balancer
# ============================================================================

# Application Load Balancer in Wavelength Zone
resource "aws_lb" "wavelength_alb" {
  name               = "${local.project_name}-wl-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.wavelength.id]
  subnets            = [aws_subnet.wavelength.id]

  enable_deletion_protection = false

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-wavelength-alb"
  })
}

# Target group for Wavelength instances
resource "aws_lb_target_group" "wavelength_targets" {
  name     = "${local.project_name}-wl-tg"
  port     = var.application_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = var.health_check_path
    matcher             = "200"
    port                = var.health_check_port
    protocol            = "HTTP"
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-wavelength-targets"
  })
}

# Register Wavelength instance with target group
resource "aws_lb_target_group_attachment" "wavelength_server" {
  target_group_arn = aws_lb_target_group.wavelength_targets.arn
  target_id        = aws_instance.wavelength_server.id
  port             = var.application_port
}

# ALB listener
resource "aws_lb_listener" "wavelength_http" {
  load_balancer_arn = aws_lb.wavelength_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wavelength_targets.arn
  }

  tags = local.common_tags
}

# ============================================================================
# S3 Bucket for Static Assets
# ============================================================================

# S3 bucket for static assets served by CloudFront
resource "aws_s3_bucket" "static_assets" {
  bucket        = "${local.project_name}-static-assets"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-static-assets"
    Type = "StaticContent"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Sample static content
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.static_assets.id
  key          = "index.html"
  content_type = "text/html"
  content = templatefile("${path.module}/static_content/index.html", {
    project_name = local.project_name
    alb_dns_name = aws_lb.wavelength_alb.dns_name
  })

  tags = local.common_tags
}

# ============================================================================
# CloudFront Distribution
# ============================================================================

# CloudFront Origin Access Control for S3
resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "${local.project_name}-s3-oac"
  description                       = "OAC for S3 static assets"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "main" {
  # S3 origin for static content
  origin {
    domain_name              = aws_s3_bucket.static_assets.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.static_assets.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
  }

  # ALB origin for dynamic content (API calls)
  origin {
    domain_name = aws_lb.wavelength_alb.dns_name
    origin_id   = "ALB-${aws_lb.wavelength_alb.name}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "Edge application with Wavelength and S3 origins"

  # Default cache behavior for static content
  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.static_assets.id}"
    compress               = true
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  # Cache behavior for API calls to Wavelength
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "ALB-${aws_lb.wavelength_alb.name}"
    compress               = true
    viewer_protocol_policy = "https-only"

    forwarded_values {
      query_string = true
      headers      = ["*"]

      cookies {
        forward = "all"
      }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  # Geographic restrictions (none by default)
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # SSL/TLS configuration
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # Price class for global distribution
  price_class = var.cloudfront_price_class

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-cloudfront"
  })
}

# S3 bucket policy for CloudFront access
resource "aws_s3_bucket_policy" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.static_assets.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.static_assets]
}

# ============================================================================
# Route 53 DNS (Optional)
# ============================================================================

# Hosted zone for custom domain (optional)
resource "aws_route53_zone" "main" {
  count = var.domain_name != "" ? 1 : 0

  name = var.domain_name

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-zone"
  })
}

# CNAME record pointing to CloudFront
resource "aws_route53_record" "app" {
  count = var.domain_name != "" ? 1 : 0

  zone_id = aws_route53_zone.main[0].zone_id
  name    = "app.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [aws_cloudfront_distribution.main.domain_name]
}

# ============================================================================
# CloudWatch Monitoring
# ============================================================================

# CloudWatch Log Group for application logs
resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/ec2/${local.project_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.project_name}-logs"
  })
}

# CloudWatch Dashboard for monitoring
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.project_name}-dashboard"

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
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.wavelength_alb.arn_suffix],
            [".", "TargetResponseTime", ".", "."],
            [".", "HTTPCode_Target_2XX_Count", ".", "."],
            [".", "HTTPCode_Target_4XX_Count", ".", "."],
            [".", "HTTPCode_Target_5XX_Count", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Application Load Balancer Metrics"
          period  = 300
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
            ["AWS/CloudFront", "Requests", "DistributionId", aws_cloudfront_distribution.main.id],
            [".", "BytesDownloaded", ".", "."],
            [".", "BytesUploaded", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"  # CloudFront metrics are always in us-east-1
          title   = "CloudFront Distribution Metrics"
          period  = 300
        }
      }
    ]
  })
}