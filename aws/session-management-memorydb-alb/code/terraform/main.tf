# Main Terraform configuration for distributed session management infrastructure
# This configuration deploys a complete session management solution using AWS services

# Data sources for current AWS context
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get available AZs for the current region
data "aws_availability_zones" "available" {
  state = "available"
}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming prefix
  name_prefix = "${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  
  # Common tags to be applied to all resources
  common_tags = merge({
    Project     = "distributed-session-management"
    Environment = var.environment
    ManagedBy   = "terraform"
    Recipe      = "memorydb-alb-session-management"
  }, var.additional_tags)

  # Use provided AZs or fall back to available AZs
  availability_zones = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 2)
}

# =============================================================================
# VPC AND NETWORKING
# =============================================================================

# Create VPC for the session management infrastructure
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# Create Internet Gateway for public subnet access
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# Create public subnets for ALB (across multiple AZs for high availability)
resource "aws_subnet" "public" {
  count = length(local.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-subnet-${count.index + 1}"
    Type = "public"
  })
}

# Create private subnets for ECS tasks and MemoryDB
resource "aws_subnet" "private" {
  count = length(local.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = local.availability_zones[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-subnet-${count.index + 1}"
    Type = "private"
  })
}

# Create route table for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

# Associate public subnets with public route table
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Create NAT Gateway for private subnet internet access
resource "aws_eip" "nat" {
  count = length(aws_subnet.private)

  domain = "vpc"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-eip-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count = length(aws_subnet.private)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-gateway-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.main]
}

# Create route tables for private subnets
resource "aws_route_table" "private" {
  count = length(aws_subnet.private)

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-rt-${count.index + 1}"
  })
}

# Associate private subnets with their respective route tables
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# =============================================================================
# SECURITY GROUPS
# =============================================================================

# Security group for Application Load Balancer
resource "aws_security_group" "alb" {
  name_prefix = "${local.name_prefix}-alb-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for Application Load Balancer"

  # Allow HTTP traffic from the internet
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS traffic from the internet
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
    Name = "${local.name_prefix}-alb-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for ECS tasks
resource "aws_security_group" "ecs_tasks" {
  name_prefix = "${local.name_prefix}-ecs-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for ECS tasks"

  # Allow traffic from ALB on container port
  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Allow traffic from ALB on application port
  ingress {
    description     = "Application port from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
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
    Name = "${local.name_prefix}-ecs-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for MemoryDB cluster
resource "aws_security_group" "memorydb" {
  name_prefix = "${local.name_prefix}-memorydb-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for MemoryDB cluster"

  # Allow Redis traffic from ECS tasks
  ingress {
    description     = "Redis from ECS tasks"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  # Allow all outbound traffic (for cluster communication)
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-memorydb-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# MEMORYDB FOR REDIS
# =============================================================================

# Create MemoryDB subnet group
resource "aws_memorydb_subnet_group" "main" {
  name       = "${local.name_prefix}-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  description = "Subnet group for MemoryDB cluster"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-memorydb-subnet-group"
  })
}

# Create MemoryDB cluster for session storage
resource "aws_memorydb_cluster" "session_store" {
  name               = "${local.name_prefix}-cluster"
  description        = "MemoryDB cluster for session management"
  node_type          = var.memorydb_node_type
  num_shards         = var.memorydb_num_shards
  num_replicas_per_shard = var.memorydb_num_replicas_per_shard
  
  # Security and networking
  subnet_group_name  = aws_memorydb_subnet_group.main.name
  security_group_ids = [aws_security_group.memorydb.id]
  
  # Configuration
  parameter_group_name = var.memorydb_parameter_group
  engine_version      = var.memorydb_engine_version
  port               = 6379
  
  # Maintenance and backup
  maintenance_window      = "sun:03:00-sun:05:00"
  snapshot_retention_limit = 5
  snapshot_window         = "05:00-09:00"
  
  # Enable at-rest encryption
  at_rest_encryption_enabled = true
  
  # Enable in-transit encryption
  transit_encryption_enabled = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-memorydb-cluster"
  })

  depends_on = [
    aws_memorydb_subnet_group.main,
    aws_security_group.memorydb
  ]
}

# =============================================================================
# SYSTEMS MANAGER PARAMETER STORE
# =============================================================================

# Store MemoryDB endpoint configuration
resource "aws_ssm_parameter" "memorydb_endpoint" {
  name        = "/session-app/memorydb/endpoint"
  description = "MemoryDB cluster endpoint for session storage"
  type        = "String"
  value       = aws_memorydb_cluster.session_store.cluster_endpoint[0].address

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-memorydb-endpoint"
  })
}

resource "aws_ssm_parameter" "memorydb_port" {
  name        = "/session-app/memorydb/port"
  description = "MemoryDB port for Redis connections"
  type        = "String"
  value       = tostring(aws_memorydb_cluster.session_store.cluster_endpoint[0].port)

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-memorydb-port"
  })
}

resource "aws_ssm_parameter" "session_timeout" {
  name        = "/session-app/config/session-timeout"
  description = "Session timeout in seconds"
  type        = "String"
  value       = tostring(var.session_timeout_seconds)

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-session-timeout"
  })
}

resource "aws_ssm_parameter" "redis_database" {
  name        = "/session-app/config/redis-db"
  description = "Redis database number for session storage"
  type        = "String"
  value       = tostring(var.redis_database_number)

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-redis-db"
  })
}

# =============================================================================
# CLOUDWATCH LOG GROUP
# =============================================================================

# Create CloudWatch log group for ECS tasks
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${local.name_prefix}-session-app"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-logs"
  })
}

# =============================================================================
# IAM ROLES AND POLICIES
# =============================================================================

# ECS Task Execution Role (for pulling images and writing logs)
resource "aws_iam_role" "ecs_task_execution" {
  name_prefix = "${local.name_prefix}-ecs-exec-"

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
    Name = "${local.name_prefix}-ecs-execution-role"
  })
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Role (for application-level permissions)
resource "aws_iam_role" "ecs_task" {
  name_prefix = "${local.name_prefix}-ecs-task-"

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
    Name = "${local.name_prefix}-ecs-task-role"
  })
}

# Policy for ECS tasks to access Systems Manager parameters
resource "aws_iam_role_policy" "ecs_task_ssm_policy" {
  name_prefix = "${local.name_prefix}-ecs-ssm-"
  role        = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          aws_ssm_parameter.memorydb_endpoint.arn,
          aws_ssm_parameter.memorydb_port.arn,
          aws_ssm_parameter.session_timeout.arn,
          aws_ssm_parameter.redis_database.arn
        ]
      }
    ]
  })
}

# =============================================================================
# APPLICATION LOAD BALANCER
# =============================================================================

# Create Application Load Balancer
resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets           = aws_subnet.public[*].id

  enable_deletion_protection = var.alb_enable_deletion_protection
  idle_timeout              = var.alb_idle_timeout

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb"
  })
}

# Create target group for ECS tasks
resource "aws_lb_target_group" "ecs_tasks" {
  name        = "${local.name_prefix}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = var.healthy_threshold
    interval            = var.health_check_interval
    matcher             = "200"
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = var.health_check_timeout
    unhealthy_threshold = var.unhealthy_threshold
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-target-group"
  })

  depends_on = [aws_lb.main]
}

# Create ALB listener
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_tasks.arn
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-listener"
  })
}

# =============================================================================
# ECS CLUSTER AND SERVICE
# =============================================================================

# Create ECS cluster
resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  # Enable Container Insights for enhanced monitoring
  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-cluster"
  })
}

# Create ECS cluster capacity provider (Fargate)
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = var.enable_spot_instances ? ["FARGATE", "FARGATE_SPOT"] : ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = var.enable_spot_instances ? 50 : 100
    capacity_provider = "FARGATE"
  }

  dynamic "default_capacity_provider_strategy" {
    for_each = var.enable_spot_instances ? [1] : []
    content {
      base              = 0
      weight            = 50
      capacity_provider = "FARGATE_SPOT"
    }
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "session_app" {
  family                   = "${local.name_prefix}-session-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn           = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "session-app"
      image = var.ecs_container_image

      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "REDIS_ENDPOINT"
          value = aws_memorydb_cluster.session_store.cluster_endpoint[0].address
        },
        {
          name  = "REDIS_PORT"
          value = tostring(aws_memorydb_cluster.session_store.cluster_endpoint[0].port)
        },
        {
          name  = "SESSION_TIMEOUT"
          value = tostring(var.session_timeout_seconds)
        },
        {
          name  = "REDIS_DATABASE"
          value = tostring(var.redis_database_number)
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

      essential = true
    }
  ])

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-task-definition"
  })

  depends_on = [
    aws_cloudwatch_log_group.ecs_logs,
    aws_memorydb_cluster.session_store
  ]
}

# Create ECS Service
resource "aws_ecs_service" "session_app" {
  name            = "${local.name_prefix}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.session_app.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  # Enable ECS Exec for debugging if specified
  enable_execute_command = var.enable_execute_command

  network_configuration {
    security_groups  = [aws_security_group.ecs_tasks.id]
    subnets         = aws_subnet.private[*].id
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_tasks.arn
    container_name   = "session-app"
    container_port   = 80
  }

  # Health check grace period
  health_check_grace_period_seconds = 300

  # Service deployment configuration
  deployment_configuration {
    maximum_percent         = 200
    minimum_healthy_percent = 100
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-service"
  })

  depends_on = [
    aws_lb_listener.main,
    aws_iam_role_policy.ecs_task_ssm_policy
  ]
}

# =============================================================================
# AUTO SCALING
# =============================================================================

# Auto scaling target
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = var.autoscaling_max_capacity
  min_capacity       = var.autoscaling_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.session_app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-autoscaling-target"
  })

  depends_on = [aws_ecs_service.session_app]
}

# Auto scaling policy based on CPU utilization
resource "aws_appautoscaling_policy" "ecs_cpu_policy" {
  name               = "${local.name_prefix}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = var.autoscaling_target_cpu
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }

  depends_on = [aws_appautoscaling_target.ecs_target]
}

# =============================================================================
# CLOUDWATCH ALARMS (OPTIONAL)
# =============================================================================

# CloudWatch alarm for high CPU utilization
resource "aws_cloudwatch_metric_alarm" "ecs_high_cpu" {
  count = var.enable_enhanced_monitoring ? 1 : 0

  alarm_name          = "${local.name_prefix}-ecs-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ECS CPU utilization"
  alarm_actions       = [] # Add SNS topic ARN if you want notifications

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.session_app.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-cpu-alarm"
  })
}

# CloudWatch alarm for MemoryDB CPU utilization
resource "aws_cloudwatch_metric_alarm" "memorydb_cpu" {
  count = var.enable_enhanced_monitoring ? 1 : 0

  alarm_name          = "${local.name_prefix}-memorydb-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/MemoryDB"
  period              = "300"
  statistic           = "Average"
  threshold           = "75"
  alarm_description   = "This metric monitors MemoryDB CPU utilization"
  alarm_actions       = [] # Add SNS topic ARN if you want notifications

  dimensions = {
    ClusterName = aws_memorydb_cluster.session_store.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-memorydb-cpu-alarm"
  })
}