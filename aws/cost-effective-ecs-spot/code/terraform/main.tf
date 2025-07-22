# ==============================================================================
# DATA SOURCES
# ==============================================================================

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get default VPC if not specified
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

# Get VPC information for security group rules
data "aws_vpc" "selected" {
  id = local.vpc_id
}

# Get default subnets if not specified
data "aws_subnets" "default" {
  count = length(var.subnet_ids) == 0 ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

# Get availability zones if not specified
data "aws_availability_zones" "available" {
  count = length(var.availability_zones) == 0 ? 1 : 0
  state = "available"
}

# Get latest ECS-optimized AMI
data "aws_ssm_parameter" "ecs_optimized_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended"
}

# ==============================================================================
# LOCAL VALUES
# ==============================================================================

locals {
  # Determine VPC and subnet configuration
  vpc_id     = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids
  
  # Parse AMI information from SSM parameter
  ecs_ami_info = jsondecode(data.aws_ssm_parameter.ecs_optimized_ami.value)
  ecs_ami_id   = local.ecs_ami_info.image_id
  
  # Generate unique suffix for resource names
  name_suffix = random_string.suffix.result
  
  # Common tags for all resources
  common_tags = merge(
    {
      Project     = "cost-effective-ecs-spot"
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
  
  # User data script for ECS instances
  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh", {
    cluster_name = var.cluster_name
  }))
}

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# ==============================================================================
# CLOUDWATCH LOG GROUP
# ==============================================================================

# CloudWatch log group for ECS container logs
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${var.task_family}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ecs-logs"
  })
}

# ==============================================================================
# IAM ROLES AND POLICIES
# ==============================================================================

# ECS Task Execution Role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.project_name}-ecs-task-execution-role-${local.name_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ecs-task-execution-role"
  })
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Instance Role
resource "aws_iam_role" "ecs_instance_role" {
  name = "${var.project_name}-ecs-instance-role-${local.name_suffix}"
  
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
    Name = "${var.project_name}-ecs-instance-role"
  })
}

# Attach AWS managed policy for ECS container instances
resource "aws_iam_role_policy_attachment" "ecs_instance_role_policy" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Create instance profile for ECS instances
resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "${var.project_name}-ecs-instance-profile-${local.name_suffix}"
  role = aws_iam_role.ecs_instance_role.name
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ecs-instance-profile"
  })
}

# ==============================================================================
# SECURITY GROUP
# ==============================================================================

# Security group for ECS instances
resource "aws_security_group" "ecs_instances" {
  name        = "${var.project_name}-ecs-instances-${local.name_suffix}"
  description = "Security group for ECS instances in ${var.cluster_name}"
  vpc_id      = local.vpc_id
  
  # Allow HTTP traffic
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }
  
  # Allow HTTPS traffic
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }
  
  # Allow dynamic port range for ECS tasks
  ingress {
    description = "ECS Dynamic Port Range"
    from_port   = 32768
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }
  
  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ecs-instances-sg"
  })
}

# ==============================================================================
# LAUNCH TEMPLATE
# ==============================================================================

# Launch template for ECS instances with mixed instance types
resource "aws_launch_template" "main" {
  name_prefix   = "${var.project_name}-ecs-template-"
  image_id      = local.ecs_ami_id
  instance_type = var.instance_types[0]  # Default instance type
  
  vpc_security_group_ids = [aws_security_group.ecs_instances.id]
  
  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }
  
  user_data = local.user_data
  
  monitoring {
    enabled = var.enable_detailed_monitoring
  }
  
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }
  
  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${var.project_name}-ecs-instance"
    })
  }
  
  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name = "${var.project_name}-ecs-volume"
    })
  }
  
  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ecs-launch-template"
  })
}

# ==============================================================================
# AUTO SCALING GROUP
# ==============================================================================

# Auto Scaling Group with mixed instances policy for cost optimization
resource "aws_autoscaling_group" "main" {
  name                = "${var.project_name}-ecs-asg-${local.name_suffix}"
  vpc_zone_identifier = local.subnet_ids
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity
  health_check_type   = "ECS"
  health_check_grace_period = 300
  
  # Mixed instances policy for cost optimization
  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.main.id
        version            = "$Latest"
      }
      
      # Define instance type overrides for diversification
      dynamic "override" {
        for_each = var.instance_types
        content {
          instance_type = override.value
        }
      }
    }
    
    instances_distribution {
      on_demand_allocation_strategy            = "prioritized"
      on_demand_base_capacity                  = var.on_demand_base_capacity
      on_demand_percentage_above_base_capacity = var.on_demand_percentage_above_base
      spot_allocation_strategy                 = "diversified"
      spot_instance_pools                      = var.spot_instance_pools
      spot_max_price                           = var.spot_max_price
    }
  }
  
  # Enable instance protection during termination
  protect_from_scale_in = true
  
  # Tags for ASG and instances
  tag {
    key                 = "Name"
    value               = "${var.project_name}-ecs-asg"
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

# ==============================================================================
# ECS CLUSTER
# ==============================================================================

# ECS Cluster with Container Insights enabled
resource "aws_ecs_cluster" "main" {
  name = var.cluster_name
  
  # Enable Container Insights for monitoring
  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }
  
  tags = merge(local.common_tags, {
    Name = var.cluster_name
  })
}

# ==============================================================================
# ECS CAPACITY PROVIDER
# ==============================================================================

# ECS Capacity Provider for intelligent scaling
resource "aws_ecs_capacity_provider" "main" {
  name = var.capacity_provider_name
  
  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.main.arn
    managed_termination_protection = "ENABLED"
    
    managed_scaling {
      status                 = "ENABLED"
      target_capacity        = var.target_capacity
      minimum_scaling_step_size = var.minimum_scaling_step_size
      maximum_scaling_step_size = var.maximum_scaling_step_size
    }
  }
  
  tags = merge(local.common_tags, {
    Name = var.capacity_provider_name
  })
}

# Associate capacity provider with cluster
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name
  
  capacity_providers = [aws_ecs_capacity_provider.main.name]
  
  default_capacity_provider_strategy {
    base              = 0
    weight            = 1
    capacity_provider = aws_ecs_capacity_provider.main.name
  }
}

# ==============================================================================
# ECS TASK DEFINITION
# ==============================================================================

# ECS Task Definition optimized for Spot instances
resource "aws_ecs_task_definition" "main" {
  family                   = var.task_family
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  
  container_definitions = jsonencode([
    {
      name      = "web-server"
      image     = var.container_image
      cpu       = var.task_cpu
      memory    = var.task_memory
      essential = true
      
      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = 0
          protocol      = "tcp"
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_logs.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "ecs"
        }
      }
      
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}/ || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])
  
  tags = merge(local.common_tags, {
    Name = var.task_family
  })
}

# ==============================================================================
# ECS SERVICE
# ==============================================================================

# ECS Service with deployment configuration optimized for Spot instances
resource "aws_ecs_service" "main" {
  name            = var.service_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.service_desired_count
  
  # Use capacity provider strategy
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.main.name
    weight            = 1
    base              = var.service_base_capacity
  }
  
  # Deployment configuration optimized for Spot interruptions
  deployment_configuration {
    maximum_percent         = var.deployment_maximum_percent
    minimum_healthy_percent = var.deployment_minimum_healthy_percent
    
    deployment_circuit_breaker {
      enable   = var.enable_deployment_circuit_breaker
      rollback = var.enable_deployment_rollback
    }
  }
  
  tags = merge(local.common_tags, {
    Name = var.service_name
  })
  
  depends_on = [
    aws_ecs_cluster_capacity_providers.main,
  ]
}

# ==============================================================================
# APPLICATION AUTO SCALING
# ==============================================================================

# Application Auto Scaling target for ECS service
resource "aws_appautoscaling_target" "ecs_service" {
  count              = var.enable_service_auto_scaling ? 1 : 0
  max_capacity       = var.auto_scaling_max_capacity
  min_capacity       = var.auto_scaling_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
  
  tags = merge(local.common_tags, {
    Name = "${var.service_name}-scaling-target"
  })
}

# CPU-based auto scaling policy
resource "aws_appautoscaling_policy" "ecs_service_cpu" {
  count              = var.enable_service_auto_scaling ? 1 : 0
  name               = "${var.service_name}-cpu-target-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service[0].service_namespace
  
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    
    target_value       = var.auto_scaling_target_cpu
    scale_in_cooldown  = var.auto_scaling_scale_in_cooldown
    scale_out_cooldown = var.auto_scaling_scale_out_cooldown
  }
}

# ==============================================================================
# END OF CONFIGURATION
# ==============================================================================

# Note: User data template is located in templates/user_data.sh
# This template is used by the launch template to configure ECS instances