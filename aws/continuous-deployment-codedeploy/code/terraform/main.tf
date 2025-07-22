# Data sources for existing resources and dynamic lookups
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get default VPC if not specified
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

locals {
  vpc_id = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
}

# Get subnets if not specified
data "aws_subnets" "default" {
  count = length(var.subnet_ids) == 0 ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

data "aws_availability_zones" "available" {
  count = length(var.availability_zones) == 0 ? 1 : 0
  state = "available"
}

locals {
  subnet_ids         = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids
  availability_zones = length(var.availability_zones) > 0 ? var.availability_zones : data.aws_availability_zones.available[0].names
  
  # Resource naming with random suffix
  name_prefix        = "${var.project_name}-${var.environment}"
  repository_name    = var.repository_name != "" ? var.repository_name : "${local.name_prefix}-repo-${random_id.suffix.hex}"
  build_project_name = var.build_project_name != "" ? var.build_project_name : "${local.name_prefix}-build-${random_id.suffix.hex}"
  app_name          = "${local.name_prefix}-app-${random_id.suffix.hex}"
  deployment_group_name = "${local.name_prefix}-depgroup-${random_id.suffix.hex}"
  key_pair_name     = var.key_pair_name != "" ? var.key_pair_name : "${local.name_prefix}-keypair-${random_id.suffix.hex}"
}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Generate random password for secrets
resource "random_password" "random_suffix" {
  length  = 6
  special = false
  upper   = false
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

#===============================================================================
# IAM ROLES AND POLICIES
#===============================================================================

# CodeDeploy Service Role
resource "aws_iam_role" "codedeploy_service_role" {
  name = "${local.name_prefix}-codedeploy-service-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
      }
    ]
  })
  
  tags = {
    Name = "${local.name_prefix}-codedeploy-service-role"
  }
}

# Attach AWS managed policy for CodeDeploy
resource "aws_iam_role_policy_attachment" "codedeploy_service_role_policy" {
  role       = aws_iam_role.codedeploy_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

# EC2 Instance Role for CodeDeploy
resource "aws_iam_role" "ec2_codedeploy_role" {
  name = "${local.name_prefix}-ec2-codedeploy-role"
  
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
  
  tags = {
    Name = "${local.name_prefix}-ec2-codedeploy-role"
  }
}

# Attach policies for EC2 instances
resource "aws_iam_role_policy_attachment" "ec2_codedeploy_policy" {
  role       = aws_iam_role.ec2_codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforAWSCodeDeploy"
}

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_policy" {
  role       = aws_iam_role.ec2_codedeploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Instance Profile for EC2 instances
resource "aws_iam_instance_profile" "ec2_codedeploy_profile" {
  name = "${local.name_prefix}-ec2-codedeploy-profile"
  role = aws_iam_role.ec2_codedeploy_role.name
  
  tags = {
    Name = "${local.name_prefix}-ec2-codedeploy-profile"
  }
}

# CodeBuild Service Role
resource "aws_iam_role" "codebuild_service_role" {
  name = "${local.name_prefix}-codebuild-service-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })
  
  tags = {
    Name = "${local.name_prefix}-codebuild-service-role"
  }
}

# CodeBuild Service Policy
resource "aws_iam_role_policy" "codebuild_service_policy" {
  name = "${local.name_prefix}-codebuild-service-policy"
  role = aws_iam_role.codebuild_service_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "codecommit:GitPull",
          "s3:GetObject",
          "s3:PutObject",
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = "*"
      }
    ]
  })
}

#===============================================================================
# KEY PAIR (Optional)
#===============================================================================

# Create EC2 Key Pair if requested
resource "aws_key_pair" "webapp_keypair" {
  count      = var.create_key_pair ? 1 : 0
  key_name   = local.key_pair_name
  public_key = tls_private_key.webapp_key[0].public_key_openssh
  
  tags = {
    Name = local.key_pair_name
  }
}

# Generate private key for EC2 instances
resource "tls_private_key" "webapp_key" {
  count     = var.create_key_pair ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

#===============================================================================
# SECURITY GROUPS
#===============================================================================

# Security Group for Application Load Balancer
resource "aws_security_group" "alb_sg" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = local.vpc_id
  
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${local.name_prefix}-alb-sg"
  }
}

# Security Group for EC2 instances
resource "aws_security_group" "ec2_sg" {
  name        = "${local.name_prefix}-ec2-sg"
  description = "Security group for EC2 instances"
  vpc_id      = local.vpc_id
  
  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  
  dynamic "ingress" {
    for_each = var.enable_ssh_access ? [1] : []
    content {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_cidr_blocks
    }
  }
  
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${local.name_prefix}-ec2-sg"
  }
}

#===============================================================================
# S3 BUCKET FOR ARTIFACTS
#===============================================================================

# S3 bucket for storing build artifacts
resource "aws_s3_bucket" "artifacts" {
  bucket = "${local.name_prefix}-artifacts-${random_id.suffix.hex}"
  
  tags = {
    Name = "${local.name_prefix}-artifacts-bucket"
  }
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "artifacts_versioning" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts_encryption" {
  bucket = aws_s3_bucket.artifacts.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "artifacts_pab" {
  bucket = aws_s3_bucket.artifacts.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#===============================================================================
# APPLICATION LOAD BALANCER
#===============================================================================

# Application Load Balancer
resource "aws_lb" "webapp_alb" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = slice(local.subnet_ids, 0, min(2, length(local.subnet_ids)))
  
  enable_deletion_protection = false
  
  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

# Target Group for Blue Environment
resource "aws_lb_target_group" "blue_tg" {
  name     = "${local.name_prefix}-tg-blue"
  port     = 80
  protocol = "HTTP"
  vpc_id   = local.vpc_id
  
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
  
  tags = {
    Name        = "${local.name_prefix}-tg-blue"
    Environment = "blue"
  }
}

# Target Group for Green Environment
resource "aws_lb_target_group" "green_tg" {
  name     = "${local.name_prefix}-tg-green"
  port     = 80
  protocol = "HTTP"
  vpc_id   = local.vpc_id
  
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
  
  tags = {
    Name        = "${local.name_prefix}-tg-green"
    Environment = "green"
  }
}

# ALB Listener
resource "aws_lb_listener" "webapp_listener" {
  load_balancer_arn = aws_lb.webapp_alb.arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue_tg.arn
  }
  
  tags = {
    Name = "${local.name_prefix}-listener"
  }
}

#===============================================================================
# LAUNCH TEMPLATE AND AUTO SCALING GROUP
#===============================================================================

# User data script for EC2 instances
locals {
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    region = data.aws_region.current.name
  }))
}

# Create user data script file
resource "local_file" "user_data_script" {
  filename = "${path.module}/user_data.sh"
  content  = <<-EOF
#!/bin/bash
yum update -y
yum install -y ruby wget httpd
systemctl start httpd
systemctl enable httpd
echo "<h1>Blue Environment - Version 1.0</h1>" > /var/www/html/index.html
cd /home/ec2-user
wget https://aws-codedeploy-${data.aws_region.current.name}.s3.${data.aws_region.current.name}.amazonaws.com/latest/install
chmod +x ./install
./install auto
systemctl start codedeploy-agent
systemctl enable codedeploy-agent
EOF
}

# Launch Template for EC2 instances
resource "aws_launch_template" "webapp_lt" {
  name_prefix   = "${local.name_prefix}-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  key_name      = var.create_key_pair ? aws_key_pair.webapp_keypair[0].key_name : var.key_pair_name
  
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_codedeploy_profile.name
  }
  
  user_data = local.user_data
  
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${local.name_prefix}-instance"
      Environment = "blue"
    }
  }
  
  tags = {
    Name = "${local.name_prefix}-launch-template"
  }
  
  depends_on = [local_file.user_data_script]
}

# Auto Scaling Group
resource "aws_autoscaling_group" "webapp_asg" {
  name                = "${local.name_prefix}-asg"
  vpc_zone_identifier = local.subnet_ids
  target_group_arns   = [aws_lb_target_group.blue_tg.arn]
  health_check_type   = "ELB"
  health_check_grace_period = var.health_check_grace_period
  
  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity
  
  launch_template {
    id      = aws_launch_template.webapp_lt.id
    version = "$Latest"
  }
  
  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-asg"
    propagate_at_launch = false
  }
  
  tag {
    key                 = "Environment"
    value               = "blue"
    propagate_at_launch = true
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

#===============================================================================
# CODECOMMIT REPOSITORY
#===============================================================================

# CodeCommit Repository
resource "aws_codecommit_repository" "webapp_repo" {
  repository_name   = local.repository_name
  repository_description = var.repository_description
  
  tags = {
    Name = local.repository_name
  }
}

#===============================================================================
# CODEBUILD PROJECT
#===============================================================================

# CodeBuild Project
resource "aws_codebuild_project" "webapp_build" {
  name          = local.build_project_name
  description   = "Build project for webapp continuous deployment"
  service_role  = aws_iam_role.codebuild_service_role.arn
  
  artifacts {
    type     = "S3"
    location = "${aws_s3_bucket.artifacts.bucket}/artifacts"
  }
  
  environment {
    compute_type                = var.build_compute_type
    image                      = var.build_image
    type                       = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }
  
  source {
    type     = "CODECOMMIT"
    location = aws_codecommit_repository.webapp_repo.clone_url_http
  }
  
  tags = {
    Name = local.build_project_name
  }
}

#===============================================================================
# CODEDEPLOY APPLICATION AND DEPLOYMENT GROUP
#===============================================================================

# CodeDeploy Application
resource "aws_codedeploy_app" "webapp_app" {
  compute_platform = "EC2/On-Premises"
  name             = local.app_name
  
  tags = {
    Name = local.app_name
  }
}

# CodeDeploy Deployment Group
resource "aws_codedeploy_deployment_group" "webapp_deployment_group" {
  app_name              = aws_codedeploy_app.webapp_app.name
  deployment_group_name = local.deployment_group_name
  service_role_arn      = aws_iam_role.codedeploy_service_role.arn
  deployment_config_name = var.deployment_config_name
  
  auto_scaling_groups = [aws_autoscaling_group.webapp_asg.name]
  
  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }
    
    terminate_blue_instances_on_deployment_success {
      action                         = "TERMINATE"
      termination_wait_time_in_minutes = var.termination_wait_time
    }
    
    green_fleet_provisioning_option {
      action = "COPY_AUTO_SCALING_GROUP"
    }
  }
  
  load_balancer_info {
    target_group_info {
      name = aws_lb_target_group.blue_tg.name
    }
  }
  
  dynamic "auto_rollback_configuration" {
    for_each = var.enable_auto_rollback ? [1] : []
    content {
      enabled = true
      events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM", "DEPLOYMENT_STOP_ON_INSTANCE_FAILURE"]
    }
  }
  
  dynamic "alarm_configuration" {
    for_each = var.enable_cloudwatch_alarms && var.enable_auto_rollback ? [1] : []
    content {
      enabled = true
      alarms  = [aws_cloudwatch_metric_alarm.deployment_failure[0].name, aws_cloudwatch_metric_alarm.target_health[0].name]
    }
  }
  
  tags = {
    Name = local.deployment_group_name
  }
}

#===============================================================================
# CLOUDWATCH ALARMS (Optional)
#===============================================================================

# CloudWatch Alarm for Deployment Failures
resource "aws_cloudwatch_metric_alarm" "deployment_failure" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${local.app_name}-deployment-failure"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "FailedDeployments"
  namespace           = "AWS/CodeDeploy"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors codedeploy deployment failures"
  
  dimensions = {
    ApplicationName     = aws_codedeploy_app.webapp_app.name
    DeploymentGroupName = aws_codedeploy_deployment_group.webapp_deployment_group.deployment_group_name
  }
  
  tags = {
    Name = "${local.app_name}-deployment-failure-alarm"
  }
}

# CloudWatch Alarm for Target Group Health
resource "aws_cloudwatch_metric_alarm" "target_health" {
  count = var.enable_cloudwatch_alarms ? 1 : 0
  
  alarm_name          = "${local.app_name}-target-health"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "This metric monitors target group health"
  
  dimensions = {
    TargetGroup    = aws_lb_target_group.blue_tg.arn_suffix
    LoadBalancer   = aws_lb.webapp_alb.arn_suffix
  }
  
  tags = {
    Name = "${local.app_name}-target-health-alarm"
  }
}