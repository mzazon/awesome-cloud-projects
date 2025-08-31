# Cross-Account Service Discovery with VPC Lattice and ECS - Main Infrastructure

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Data sources for existing AWS resources
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Get default VPC if not specified
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

# Get default subnets if not specified
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

# Local values for resource naming and configuration
locals {
  # Resource naming with random suffix
  suffix              = random_id.suffix.hex
  cluster_name        = var.cluster_name != "" ? var.cluster_name : "${var.project_name}-cluster-${local.suffix}"
  service_name        = var.service_name != "" ? var.service_name : "${var.project_name}-service-${local.suffix}"
  lattice_service     = var.lattice_service_name != "" ? var.lattice_service_name : "lattice-${var.project_name}-${local.suffix}"
  service_network     = var.service_network_name != "" ? var.service_network_name : "${var.project_name}-network-${local.suffix}"
  resource_share_name = var.resource_share_name != "" ? var.resource_share_name : "lattice-share-${local.suffix}"

  # VPC and subnet configuration
  vpc_id     = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids

  # Common tags
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Recipe      = "vpc-lattice-ecs-cross-account"
  }
}

# CloudWatch Log Groups for ECS and EventBridge
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${local.service_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "ECS Log Group - ${local.service_name}"
  })
}

resource "aws_cloudwatch_log_group" "vpc_lattice_events" {
  count             = var.enable_monitoring ? 1 : 0
  name              = "/aws/events/vpc-lattice"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "VPC Lattice Events Log Group"
  })
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${local.service_name}-execution-role"

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
    Name = "ECS Task Execution Role - ${local.service_name}"
  })
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM Role for EventBridge to write to CloudWatch Logs
resource "aws_iam_role" "eventbridge_logs_role" {
  count = var.enable_monitoring ? 1 : 0
  name  = "${var.project_name}-eventbridge-logs-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "EventBridge Logs Role"
  })
}

# IAM Policy for EventBridge to write logs
resource "aws_iam_role_policy" "eventbridge_logs_policy" {
  count = var.enable_monitoring ? 1 : 0
  name  = "${var.project_name}-eventbridge-logs-policy"
  role  = aws_iam_role.eventbridge_logs_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.vpc_lattice_events[0].arn}:*"
      }
    ]
  })
}

# Security Group for ECS Tasks
resource "aws_security_group" "ecs_tasks" {
  count       = var.create_security_groups ? 1 : 0
  name        = "${local.service_name}-ecs-tasks"
  description = "Security group for ECS tasks"
  vpc_id      = local.vpc_id

  ingress {
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Allow inbound traffic on container port"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(local.common_tags, {
    Name = "ECS Tasks Security Group - ${local.service_name}"
  })
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = local.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(local.common_tags, {
    Name = "ECS Cluster - ${local.cluster_name}"
  })
}

# ECS Cluster Capacity Providers
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "producer" {
  family                   = "${local.service_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "${local.service_name}-container"
      image     = var.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      # Health check configuration
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}${var.health_check_path} || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = merge(local.common_tags, {
    Name = "ECS Task Definition - ${local.service_name}"
  })
}

# VPC Lattice Service Network
resource "aws_vpclattice_service_network" "main" {
  name      = local.service_network
  auth_type = var.lattice_auth_type

  tags = merge(local.common_tags, {
    Name = "VPC Lattice Service Network - ${local.service_network}"
  })
}

# VPC Lattice Target Group
resource "aws_vpclattice_target_group" "producer" {
  name = "${local.service_name}-targets"
  type = "IP"
  port = var.container_port

  protocol = var.target_group_protocol
  vpc_identifier = local.vpc_id

  config {
    protocol_version      = "HTTP1"
    port                 = var.container_port
    protocol             = var.target_group_protocol
    vpc_identifier       = local.vpc_id
    ip_address_type      = "IPV4"
    lambda_event_structure_version = null
    health_check {
      enabled                       = true
      health_check_grace_period_seconds = null
      health_check_interval_seconds = var.health_check_interval
      health_check_timeout_seconds  = var.health_check_timeout
      healthy_threshold_count       = var.healthy_threshold_count
      matcher {
        value = "200"
      }
      path                         = var.health_check_path
      port                         = var.container_port
      protocol                     = var.target_group_protocol
      protocol_version             = "HTTP1"
      unhealthy_threshold_count    = var.unhealthy_threshold_count
    }
  }

  tags = merge(local.common_tags, {
    Name = "VPC Lattice Target Group - ${local.service_name}"
  })
}

# VPC Lattice Service
resource "aws_vpclattice_service" "producer" {
  name               = local.lattice_service
  auth_type          = var.lattice_auth_type
  certificate_arn    = null
  custom_domain_name = null

  tags = merge(local.common_tags, {
    Name = "VPC Lattice Service - ${local.lattice_service}"
  })
}

# VPC Lattice Listener
resource "aws_vpclattice_listener" "producer" {
  name               = "http-listener"
  protocol           = var.target_group_protocol
  port               = var.container_port
  service_identifier = aws_vpclattice_service.producer.id

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.producer.id
        weight                  = 100
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "VPC Lattice Listener - ${local.lattice_service}"
  })
}

# Associate VPC Lattice Service with Service Network
resource "aws_vpclattice_service_network_service_association" "producer" {
  service_identifier         = aws_vpclattice_service.producer.id
  service_network_identifier = aws_vpclattice_service_network.main.id

  tags = merge(local.common_tags, {
    Name = "Service Network Association - ${local.lattice_service}"
  })
}

# Associate VPC with Service Network
resource "aws_vpclattice_service_network_vpc_association" "main" {
  vpc_identifier             = local.vpc_id
  service_network_identifier = aws_vpclattice_service_network.main.id

  tags = merge(local.common_tags, {
    Name = "VPC Association - ${local.service_network}"
  })
}

# ECS Service with VPC Lattice integration
resource "aws_ecs_service" "producer" {
  name            = local.service_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.producer.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.subnet_ids
    security_groups  = var.create_security_groups ? [aws_security_group.ecs_tasks[0].id] : []
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_vpclattice_target_group.producer.arn
    container_name   = "${local.service_name}-container"
    container_port   = var.container_port
  }

  depends_on = [
    aws_vpclattice_target_group.producer,
    aws_vpclattice_listener.producer
  ]

  tags = merge(local.common_tags, {
    Name = "ECS Service - ${local.service_name}"
  })
}

# AWS RAM Resource Share for cross-account sharing
resource "aws_ram_resource_share" "lattice_share" {
  count                     = var.enable_resource_sharing ? 1 : 0
  name                      = local.resource_share_name
  allow_external_principals = var.allow_external_principals

  tags = merge(local.common_tags, {
    Name = "RAM Resource Share - ${local.resource_share_name}"
  })
}

# Associate VPC Lattice Service Network with RAM Resource Share
resource "aws_ram_resource_association" "lattice_share" {
  count              = var.enable_resource_sharing ? 1 : 0
  resource_arn       = aws_vpclattice_service_network.main.arn
  resource_share_arn = aws_ram_resource_share.lattice_share[0].arn
}

# Share with Account B
resource "aws_ram_principal_association" "account_b" {
  count              = var.enable_resource_sharing ? 1 : 0
  principal          = var.account_b_id
  resource_share_arn = aws_ram_resource_share.lattice_share[0].arn
}

# EventBridge Rule for VPC Lattice Events
resource "aws_cloudwatch_event_rule" "vpc_lattice_events" {
  count       = var.enable_monitoring ? 1 : 0
  name        = "vpc-lattice-events"
  description = "Capture VPC Lattice service discovery events"

  event_pattern = jsonencode({
    source      = ["aws.vpc-lattice"]
    detail-type = [
      "VPC Lattice Service Network State Change",
      "VPC Lattice Service State Change"
    ]
  })

  tags = merge(local.common_tags, {
    Name = "VPC Lattice Events Rule"
  })
}

# EventBridge Target for CloudWatch Logs
resource "aws_cloudwatch_event_target" "vpc_lattice_logs" {
  count     = var.enable_monitoring ? 1 : 0
  rule      = aws_cloudwatch_event_rule.vpc_lattice_events[0].name
  target_id = "VPCLatticeLogsTarget"
  arn       = aws_cloudwatch_log_group.vpc_lattice_events[0].arn
  role_arn  = aws_iam_role.eventbridge_logs_role[0].arn
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  count          = var.enable_dashboard ? 1 : 0
  dashboard_name = "${var.project_name}-cross-account-discovery"

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
            ["AWS/VpcLattice", "ActiveConnectionCount", "ServiceName", local.lattice_service],
            [".", "NewConnectionCount", ".", "."],
            [".", "ProcessedBytes", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "VPC Lattice Service Metrics"
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
            ["AWS/ECS", "CPUUtilization", "ServiceName", local.service_name, "ClusterName", local.cluster_name],
            [".", "MemoryUtilization", ".", ".", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "ECS Service Metrics"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          query  = "SOURCE '${var.enable_monitoring ? aws_cloudwatch_log_group.vpc_lattice_events[0].name : "/aws/events/vpc-lattice"}'\n| fields @timestamp, source, detail-type, detail\n| sort @timestamp desc\n| limit 100"
          region = var.aws_region
          title  = "VPC Lattice Events"
          view   = "table"
        }
      }
    ]
  })
}