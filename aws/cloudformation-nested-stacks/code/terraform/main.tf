# ==============================================================================
# Terraform Infrastructure for Modular Multi-Tier Architecture
# This implementation recreates the CloudFormation nested stacks pattern using
# Terraform modules to achieve the same layered architecture and separation
# of concerns demonstrated in the recipe.
# ==============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Configure AWS provider
provider "aws" {
  region = var.aws_region

  # Default tags for all resources
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "CloudFormation-Nested-Stacks-Demo"
    }
  }
}

# ==============================================================================
# Data Sources
# ==============================================================================

# Get current AWS caller identity
data "aws_caller_identity" "current" {}

# Get available availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Get latest Amazon Linux 2 AMI
data "aws_ssm_parameter" "amazon_linux_ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

# ==============================================================================
# Random Resource for Unique Naming
# ==============================================================================

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# ==============================================================================
# Local Values
# ==============================================================================

locals {
  # Common naming prefix
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Unique identifier for resources
  unique_suffix = random_string.suffix.result
  
  # Environment-specific configurations
  environment_config = {
    development = {
      instance_type         = "t3.micro"
      min_size             = 1
      max_size             = 2
      desired_capacity     = 1
      db_instance_class    = "db.t3.micro"
      db_allocated_storage = 20
      multi_az             = false
      deletion_protection  = false
    }
    staging = {
      instance_type         = "t3.small"
      min_size             = 2
      max_size             = 4
      desired_capacity     = 2
      db_instance_class    = "db.t3.small"
      db_allocated_storage = 50
      multi_az             = false
      deletion_protection  = false
    }
    production = {
      instance_type         = "t3.medium"
      min_size             = 2
      max_size             = 6
      desired_capacity     = 3
      db_instance_class    = "db.t3.medium"
      db_allocated_storage = 100
      multi_az             = true
      deletion_protection  = true
    }
  }
  
  # Current environment configuration
  current_config = local.environment_config[var.environment]
}

# ==============================================================================
# NETWORK LAYER (Equivalent to Network Nested Stack)
# ==============================================================================

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-vpc"
    Type = "Network"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
    Type = "Network"
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-subnet-${count.index + 1}"
    Type = "Public"
  }
}

# Private Subnets
resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${local.name_prefix}-private-subnet-${count.index + 1}"
    Type = "Private"
  }
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count = 2

  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${local.name_prefix}-nat-eip-${count.index + 1}"
    Type = "Network"
  }
}

# NAT Gateways
resource "aws_nat_gateway" "main" {
  count = 2

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${local.name_prefix}-nat-gateway-${count.index + 1}"
    Type = "Network"
  }

  depends_on = [aws_internet_gateway.main]
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-public-routes"
    Type = "Network"
  }
}

# Public Route Table Associations
resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Route Tables
resource "aws_route_table" "private" {
  count = 2

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "${local.name_prefix}-private-routes-${count.index + 1}"
    Type = "Network"
  }
}

# Private Route Table Associations
resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ==============================================================================
# SECURITY LAYER (Equivalent to Security Nested Stack)
# ==============================================================================

# Application Load Balancer Security Group
resource "aws_security_group" "alb" {
  name_prefix = "${local.name_prefix}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTP traffic from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS traffic from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "${local.name_prefix}-alb-sg"
    Component = "LoadBalancer"
  }
}

# Bastion Host Security Group
resource "aws_security_group" "bastion" {
  name_prefix = "${local.name_prefix}-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow SSH access from internet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "${local.name_prefix}-bastion-sg"
    Component = "Bastion"
  }
}

# Application Security Group
resource "aws_security_group" "application" {
  name_prefix = "${local.name_prefix}-app-sg"
  description = "Security group for application instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow HTTP traffic from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Allow SSH from bastion host"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "${local.name_prefix}-app-sg"
    Component = "Application"
  }
}

# Database Security Group
resource "aws_security_group" "database" {
  name_prefix = "${local.name_prefix}-db-sg"
  description = "Security group for database"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow MySQL access from application"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.application.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "${local.name_prefix}-db-sg"
    Component = "Database"
  }
}

# IAM Role for EC2 instances
resource "aws_iam_role" "ec2_instance_role" {
  name = "${local.name_prefix}-ec2-role-${local.unique_suffix}"

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

  # S3 access policy for application-specific buckets
  inline_policy {
    name = "S3AccessPolicy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "s3:GetObject",
            "s3:PutObject"
          ]
          Resource = "arn:aws:s3:::${var.project_name}-${var.environment}-*/*"
        },
        {
          Effect = "Allow"
          Action = [
            "s3:ListBucket"
          ]
          Resource = "arn:aws:s3:::${var.project_name}-${var.environment}-*"
        }
      ]
    })
  }

  tags = {
    Component = "Compute"
  }
}

# Attach AWS managed policies to EC2 role
resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_agent" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_managed_instance" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance Profile for EC2 role
resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "${local.name_prefix}-ec2-profile-${local.unique_suffix}"
  role = aws_iam_role.ec2_instance_role.name

  tags = {
    Component = "Compute"
  }
}

# IAM Role for RDS Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring_role" {
  name = "${local.name_prefix}-rds-monitoring-role-${local.unique_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Component = "Database"
  }
}

# Attach AWS managed policy for RDS monitoring
resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ==============================================================================
# APPLICATION LAYER (Equivalent to Application Nested Stack)
# ==============================================================================

# Application Load Balancer
resource "aws_lb" "application" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = local.current_config.deletion_protection

  tags = {
    Component = "LoadBalancer"
  }
}

# Target Group
resource "aws_lb_target_group" "application" {
  name     = "${local.name_prefix}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  # Deregistration delay
  deregistration_delay = 300

  tags = {
    Component = "LoadBalancer"
  }
}

# Load Balancer Listener
resource "aws_lb_listener" "application" {
  load_balancer_arn = aws_lb.application.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.application.arn
  }
}

# Launch Template
resource "aws_launch_template" "application" {
  name_prefix   = "${local.name_prefix}-template"
  image_id      = data.aws_ssm_parameter.amazon_linux_ami.value
  instance_type = local.current_config.instance_type

  vpc_security_group_ids = [aws_security_group.application.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_instance_profile.name
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    environment    = var.environment
    project_name   = var.project_name
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name      = "${local.name_prefix}-instance"
      Component = "Application"
    }
  }

  tags = {
    Component = "Application"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "application" {
  name                = "${local.name_prefix}-asg"
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = [aws_lb_target_group.application.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300

  min_size         = local.current_config.min_size
  max_size         = local.current_config.max_size
  desired_capacity = local.current_config.desired_capacity

  launch_template {
    id      = aws_launch_template.application.id
    version = "$Latest"
  }

  # Instance refresh configuration
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-asg"
    propagate_at_launch = false
  }

  tag {
    key                 = "Component"
    value               = "Application"
    propagate_at_launch = true
  }
}

# Database Subnet Group
resource "aws_db_subnet_group" "database" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name      = "${local.name_prefix}-db-subnet-group"
    Component = "Database"
  }
}

# Database Secret
resource "aws_secretsmanager_secret" "database" {
  name                    = "${local.name_prefix}-db-secret-${local.unique_suffix}"
  description             = "Database credentials"
  recovery_window_in_days = var.environment == "production" ? 30 : 0

  tags = {
    Component = "Database"
  }
}

# Database Secret Version
resource "aws_secretsmanager_secret_version" "database" {
  secret_id = aws_secretsmanager_secret.database.id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.database.result
  })
}

# Generate random password for database
resource "random_password" "database" {
  length  = 16
  special = true
}

# RDS Database Instance
resource "aws_db_instance" "database" {
  identifier = "${local.name_prefix}-db"

  # Engine configuration
  engine         = "mysql"
  engine_version = "8.0.35"
  instance_class = local.current_config.db_instance_class

  # Storage configuration
  allocated_storage     = local.current_config.db_allocated_storage
  storage_type          = "gp2"
  storage_encrypted     = true

  # Database configuration
  db_name  = "webapp"
  username = "admin"
  password = random_password.database.result

  # Network configuration
  vpc_security_group_ids = [aws_security_group.database.id]
  db_subnet_group_name   = aws_db_subnet_group.database.name

  # Backup configuration
  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"

  # High availability
  multi_az = local.current_config.multi_az

  # Monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring_role.arn
  performance_insights_enabled = true

  # Protection
  deletion_protection = local.current_config.deletion_protection
  skip_final_snapshot = var.environment != "production"

  tags = {
    Component = "Database"
  }
}

# CloudWatch Log Group for application logs
resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/ec2/${var.project_name}-${var.environment}/httpd/access"
  retention_in_days = var.environment == "production" ? 30 : 7

  tags = {
    Component = "Monitoring"
  }
}