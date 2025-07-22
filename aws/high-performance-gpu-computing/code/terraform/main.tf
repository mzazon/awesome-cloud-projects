# Main Terraform configuration for GPU-accelerated workloads on AWS
# This infrastructure supports both P4 instances for ML training and G4 instances for inference
# with comprehensive monitoring, cost optimization, and security features

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming and tagging
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  common_tags = {
    Name        = "${local.name_prefix}-gpu-workload"
    Project     = var.project_name
    Environment = var.environment
    Purpose     = "GPU-Computing"
    ManagedBy   = "Terraform"
  }
}

# Data sources for existing AWS resources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get default VPC if not specified
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

# Get default subnet if not specified
data "aws_subnets" "default" {
  count = var.subnet_id == "" ? 1 : 0
  
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Get latest Deep Learning AMI
data "aws_ami" "deep_learning" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["Deep Learning AMI (Ubuntu 20.04)*"]
  }
  
  filter {
    name   = "state"
    values = ["available"]
  }
  
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Local values for computed resources
locals {
  vpc_id    = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_id = var.subnet_id != "" ? var.subnet_id : data.aws_subnets.default[0].ids[0]
}

# =============================================================================
# Security Group for GPU Instances
# =============================================================================

resource "aws_security_group" "gpu_instances" {
  name_prefix = "${local.name_prefix}-gpu-sg-"
  description = "Security group for GPU-accelerated workloads"
  vpc_id      = local.vpc_id

  # SSH access
  ingress {
    description = "SSH access for GPU instance management"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Jupyter Notebook access (internal only)
  ingress {
    description = "Jupyter Notebook access"
    from_port   = 8888
    to_port     = 8888
    protocol    = "tcp"
    self        = true
  }

  # TensorBoard access (internal only)
  ingress {
    description = "TensorBoard access"
    from_port   = 6006
    to_port     = 6006
    protocol    = "tcp"
    self        = true
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Additional security group rules
  dynamic "ingress" {
    for_each = var.additional_security_group_rules
    content {
      description = ingress.value.description
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-gpu-sg-${local.name_suffix}"
  })
}

# =============================================================================
# Key Pair for SSH Access
# =============================================================================

resource "aws_key_pair" "gpu_workload" {
  count = var.ssh_key_name == "" ? 1 : 0
  
  key_name   = "${local.name_prefix}-gpu-key-${local.name_suffix}"
  public_key = tls_private_key.gpu_workload[0].public_key_openssh

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-gpu-key-${local.name_suffix}"
  })
}

resource "tls_private_key" "gpu_workload" {
  count = var.ssh_key_name == "" ? 1 : 0
  
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Store private key in AWS Secrets Manager for secure access
resource "aws_secretsmanager_secret" "ssh_private_key" {
  count = var.ssh_key_name == "" ? 1 : 0
  
  name        = "${local.name_prefix}-gpu-ssh-key-${local.name_suffix}"
  description = "Private SSH key for GPU workload instances"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-gpu-ssh-key-${local.name_suffix}"
  })
}

resource "aws_secretsmanager_secret_version" "ssh_private_key" {
  count = var.ssh_key_name == "" ? 1 : 0
  
  secret_id     = aws_secretsmanager_secret.ssh_private_key[0].id
  secret_string = tls_private_key.gpu_workload[0].private_key_pem
}

# =============================================================================
# IAM Role and Instance Profile for GPU Instances
# =============================================================================

# IAM role for GPU instances with necessary permissions
resource "aws_iam_role" "gpu_instance_role" {
  name_prefix = "${local.name_prefix}-gpu-role-"
  
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
    Name = "${local.name_prefix}-gpu-role-${local.name_suffix}"
  })
}

# Attach AWS managed policies
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  count = var.enable_ssm_access ? 1 : 0
  
  role       = aws_iam_role.gpu_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_server_policy" {
  count = var.enable_gpu_monitoring ? 1 : 0
  
  role       = aws_iam_role.gpu_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Custom policy for GPU monitoring and S3 access
resource "aws_iam_role_policy" "gpu_custom_policy" {
  name_prefix = "${local.name_prefix}-gpu-custom-"
  role        = aws_iam_role.gpu_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::ec2-linux-nvidia-drivers",
          "arn:aws:s3:::ec2-linux-nvidia-drivers/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeTags",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance profile for GPU instances
resource "aws_iam_instance_profile" "gpu_instance_profile" {
  name_prefix = "${local.name_prefix}-gpu-profile-"
  role        = aws_iam_role.gpu_instance_role.name

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-gpu-profile-${local.name_suffix}"
  })
}

# =============================================================================
# User Data Script for GPU Instance Setup
# =============================================================================

locals {
  user_data_script = base64encode(templatefile("${path.module}/user_data.sh", {
    region            = data.aws_region.current.name
    enable_monitoring = var.enable_gpu_monitoring
  }))
}

# =============================================================================
# EFS for Shared Storage (Optional)
# =============================================================================

resource "aws_efs_file_system" "gpu_shared_storage" {
  count = var.create_efs_storage ? 1 : 0
  
  creation_token   = "${local.name_prefix}-gpu-efs-${local.name_suffix}"
  performance_mode = "generalPurpose"
  throughput_mode  = "provisioned"
  provisioned_throughput_in_mibps = 100

  encrypted = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-gpu-efs-${local.name_suffix}"
  })
}

resource "aws_efs_mount_target" "gpu_shared_storage" {
  count = var.create_efs_storage ? 1 : 0
  
  file_system_id  = aws_efs_file_system.gpu_shared_storage[0].id
  subnet_id       = local.subnet_id
  security_groups = [aws_security_group.efs_mount_target[0].id]
}

resource "aws_security_group" "efs_mount_target" {
  count = var.create_efs_storage ? 1 : 0
  
  name_prefix = "${local.name_prefix}-efs-sg-"
  description = "Security group for EFS mount targets"
  vpc_id      = local.vpc_id

  ingress {
    description     = "NFS access from GPU instances"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.gpu_instances.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-efs-sg-${local.name_suffix}"
  })
}

# =============================================================================
# P4 Instance for ML Training
# =============================================================================

resource "aws_instance" "p4_training" {
  count = var.enable_p4_instance ? 1 : 0
  
  ami                     = data.aws_ami.deep_learning.id
  instance_type           = var.p4_instance_type
  key_name                = var.ssh_key_name != "" ? var.ssh_key_name : aws_key_pair.gpu_workload[0].key_name
  vpc_security_group_ids  = [aws_security_group.gpu_instances.id]
  subnet_id               = local.subnet_id
  iam_instance_profile    = aws_iam_instance_profile.gpu_instance_profile.name
  monitoring              = var.enable_detailed_monitoring
  
  user_data_base64 = local.user_data_script

  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
    http_tokens                 = var.enable_imdsv2 ? "required" : "optional"
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    volume_type = var.root_volume_type
    volume_size = var.root_volume_size
    encrypted   = true
    
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-p4-root-${local.name_suffix}"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-p4-training-${local.name_suffix}"
    Type = "P4-ML-Training"
  })

  lifecycle {
    ignore_changes = [ami]
  }
}

# =============================================================================
# G4 Instances for Inference (with optional Spot pricing)
# =============================================================================

# Launch Template for G4 instances
resource "aws_launch_template" "g4_inference" {
  count = var.enable_g4_instances ? 1 : 0
  
  name_prefix   = "${local.name_prefix}-g4-template-"
  image_id      = data.aws_ami.deep_learning.id
  instance_type = var.g4_instance_type
  key_name      = var.ssh_key_name != "" ? var.ssh_key_name : aws_key_pair.gpu_workload[0].key_name
  
  vpc_security_group_ids = [aws_security_group.gpu_instances.id]
  
  user_data = local.user_data_script

  iam_instance_profile {
    name = aws_iam_instance_profile.gpu_instance_profile.name
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_type = var.root_volume_type
      volume_size = var.root_volume_size
      encrypted   = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
    http_tokens                 = var.enable_imdsv2 ? "required" : "optional"
    instance_metadata_tags      = "enabled"
  }

  monitoring {
    enabled = var.enable_detailed_monitoring
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-g4-inference-${local.name_suffix}"
      Type = "G4-Inference"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-g4-template-${local.name_suffix}"
  })
}

# G4 instances using Spot pricing (if enabled)
resource "aws_spot_instance_request" "g4_inference_spot" {
  count = var.enable_g4_instances && var.use_spot_instances ? var.g4_instance_count : 0
  
  ami                     = data.aws_ami.deep_learning.id
  instance_type           = var.g4_instance_type
  key_name                = var.ssh_key_name != "" ? var.ssh_key_name : aws_key_pair.gpu_workload[0].key_name
  vpc_security_group_ids  = [aws_security_group.gpu_instances.id]
  subnet_id               = local.subnet_id
  iam_instance_profile    = aws_iam_instance_profile.gpu_instance_profile.name
  monitoring              = var.enable_detailed_monitoring
  
  spot_price                      = var.spot_max_price
  wait_for_fulfillment           = true
  spot_type                      = "one-time"
  instance_interruption_behavior = "terminate"
  
  user_data_base64 = local.user_data_script

  root_block_device {
    volume_type = var.root_volume_type
    volume_size = var.root_volume_size
    encrypted   = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-g4-spot-${count.index + 1}-${local.name_suffix}"
    Type = "G4-Inference-Spot"
  })

  lifecycle {
    ignore_changes = [ami]
  }
}

# G4 instances using On-Demand pricing (if Spot is disabled)
resource "aws_instance" "g4_inference_ondemand" {
  count = var.enable_g4_instances && !var.use_spot_instances ? var.g4_instance_count : 0
  
  ami                     = data.aws_ami.deep_learning.id
  instance_type           = var.g4_instance_type
  key_name                = var.ssh_key_name != "" ? var.ssh_key_name : aws_key_pair.gpu_workload[0].key_name
  vpc_security_group_ids  = [aws_security_group.gpu_instances.id]
  subnet_id               = local.subnet_id
  iam_instance_profile    = aws_iam_instance_profile.gpu_instance_profile.name
  monitoring              = var.enable_detailed_monitoring
  
  user_data_base64 = local.user_data_script

  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
    http_tokens                 = var.enable_imdsv2 ? "required" : "optional"
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    volume_type = var.root_volume_type
    volume_size = var.root_volume_size
    encrypted   = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-g4-ondemand-${count.index + 1}-${local.name_suffix}"
    Type = "G4-Inference-OnDemand"
  })

  lifecycle {
    ignore_changes = [ami]
  }
}

# =============================================================================
# SNS Topic for Monitoring Alerts
# =============================================================================

resource "aws_sns_topic" "gpu_monitoring_alerts" {
  count = var.enable_gpu_monitoring && var.notification_email != "" ? 1 : 0
  
  name         = "${local.name_prefix}-gpu-alerts-${local.name_suffix}"
  display_name = "GPU Workload Monitoring Alerts"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-gpu-alerts-${local.name_suffix}"
  })
}

resource "aws_sns_topic_subscription" "email_alerts" {
  count = var.enable_gpu_monitoring && var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.gpu_monitoring_alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# =============================================================================
# CloudWatch Dashboard for GPU Monitoring
# =============================================================================

resource "aws_cloudwatch_dashboard" "gpu_monitoring" {
  count = var.enable_gpu_monitoring ? 1 : 0
  
  dashboard_name = "${local.name_prefix}-gpu-monitoring-${local.name_suffix}"

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
            ["GPU/EC2", "utilization_gpu", "InstanceId", var.enable_p4_instance ? aws_instance.p4_training[0].id : ""]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "GPU Utilization - P4 Training Instance"
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
            ["GPU/EC2", "utilization_memory", "InstanceId", var.enable_p4_instance ? aws_instance.p4_training[0].id : ""]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "GPU Memory Utilization - P4 Training Instance"
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
            ["GPU/EC2", "temperature_gpu", "InstanceId", var.enable_p4_instance ? aws_instance.p4_training[0].id : ""]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "GPU Temperature - P4 Training Instance"
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
            ["GPU/EC2", "power_draw", "InstanceId", var.enable_p4_instance ? aws_instance.p4_training[0].id : ""]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "GPU Power Consumption - P4 Training Instance"
        }
      }
    ]
  })
}

# =============================================================================
# CloudWatch Alarms for GPU Monitoring
# =============================================================================

# High temperature alarm for P4 instance
resource "aws_cloudwatch_metric_alarm" "gpu_high_temperature" {
  count = var.enable_gpu_monitoring && var.enable_p4_instance && var.notification_email != "" ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-gpu-high-temperature-${local.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "temperature_gpu"
  namespace           = "GPU/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = var.temperature_threshold
  alarm_description   = "This metric monitors GPU temperature for P4 instance"
  alarm_actions       = [aws_sns_topic.gpu_monitoring_alerts[0].arn]

  dimensions = {
    InstanceId = aws_instance.p4_training[0].id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-gpu-temp-alarm-${local.name_suffix}"
  })
}

# Low utilization alarm for P4 instance (cost optimization)
resource "aws_cloudwatch_metric_alarm" "gpu_low_utilization" {
  count = var.enable_cost_monitoring && var.enable_p4_instance && var.notification_email != "" ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-gpu-low-utilization-${local.name_suffix}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "utilization_gpu"
  namespace           = "GPU/EC2"
  period              = "1800"
  statistic           = "Average"
  threshold           = var.gpu_utilization_threshold
  alarm_description   = "This metric monitors GPU utilization for cost optimization"
  alarm_actions       = [aws_sns_topic.gpu_monitoring_alerts[0].arn]

  dimensions = {
    InstanceId = aws_instance.p4_training[0].id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-gpu-util-alarm-${local.name_suffix}"
  })
}