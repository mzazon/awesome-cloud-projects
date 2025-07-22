# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC and Networking Resources
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-vpc-${random_string.suffix.result}"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-igw-${random_string.suffix.result}"
  })
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-public-subnet-${count.index + 1}-${random_string.suffix.result}"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-public-rt-${random_string.suffix.result}"
  })
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Groups
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg-${random_string.suffix.result}"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-alb-sg-${random_string.suffix.result}"
  })
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-ecs-tasks-sg-${random_string.suffix.result}"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-ecs-tasks-sg-${random_string.suffix.result}"
  })
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.alb_name}-${random_string.suffix.result}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = merge(var.tags, {
    Name = "${var.alb_name}-${random_string.suffix.result}"
  })
}

resource "aws_lb_target_group" "main" {
  name        = "${var.target_group_name}-${random_string.suffix.result}"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    timeout             = var.health_check_timeout
    interval            = var.health_check_interval
    path                = var.health_check_path
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  tags = merge(var.tags, {
    Name = "${var.target_group_name}-${random_string.suffix.result}"
  })
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.ecs_cluster_name}-${random_string.suffix.result}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(var.tags, {
    Name = "${var.ecs_cluster_name}-${random_string.suffix.result}"
  })
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-ecs-task-execution-role-${random_string.suffix.result}"

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

  tags = merge(var.tags, {
    Name = "${var.project_name}-ecs-task-execution-role-${random_string.suffix.result}"
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# CloudWatch Log Group for ECS
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}-app"
  retention_in_days = 7

  tags = merge(var.tags, {
    Name = "${var.project_name}-ecs-logs"
  })
}

# ECS Task Definition
resource "aws_ecs_task_definition" "main" {
  family                   = "${var.project_name}-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name  = "${var.project_name}-container"
      image = var.container_image
      essential = true
      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]
      healthCheck = {
        command = [
          "CMD-SHELL",
          "curl -f http://localhost${var.health_check_path} || exit 1"
        ]
        interval    = var.health_check_interval
        timeout     = var.health_check_timeout
        retries     = var.health_check_unhealthy_threshold
        startPeriod = 60
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      environment = [
        {
          name  = "NGINX_PORT"
          value = tostring(var.container_port)
        }
      ]
      command = [
        "sh",
        "-c",
        "echo 'server { listen ${var.container_port}; location / { return 200 \"Healthy Application\"; } location ${var.health_check_path} { return 200 \"OK\"; } }' > /etc/nginx/conf.d/default.conf && nginx -g 'daemon off;'"
      ]
    }
  ])

  tags = merge(var.tags, {
    Name = "${var.project_name}-task-definition"
  })
}

# ECS Service
resource "aws_ecs_service" "main" {
  name            = "${var.ecs_service_name}-${random_string.suffix.result}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = "${var.project_name}-container"
    container_port   = var.container_port
  }

  health_check_grace_period_seconds = var.health_check_grace_period

  depends_on = [
    aws_lb_listener.main
  ]

  tags = merge(var.tags, {
    Name = "${var.ecs_service_name}-${random_string.suffix.result}"
  })
}

# Auto Scaling Target for ECS Service
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = var.ecs_max_capacity
  min_capacity       = var.ecs_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  tags = merge(var.tags, {
    Name = "${var.project_name}-ecs-autoscaling-target"
  })
}

# Auto Scaling Policy for CPU
resource "aws_appautoscaling_policy" "ecs_cpu_policy" {
  name               = "${var.project_name}-cpu-scaling-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.cpu_target_value
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

# Auto Scaling Policy for Memory
resource "aws_appautoscaling_policy" "ecs_memory_policy" {
  name               = "${var.project_name}-memory-scaling-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = var.memory_target_value
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown
  }
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  alarm_name          = "UnhealthyTargets-${random_string.suffix.result}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = var.unhealthy_host_threshold
  alarm_description   = "This metric monitors unhealthy targets"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup    = aws_lb_target_group.main.arn_suffix
    LoadBalancer   = aws_lb.main.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = merge(var.tags, {
    Name = "UnhealthyTargets-${random_string.suffix.result}"
  })
}

resource "aws_cloudwatch_metric_alarm" "high_response_time" {
  alarm_name          = "HighResponseTime-${random_string.suffix.result}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = var.high_response_time_threshold
  alarm_description   = "This metric monitors target response time"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup    = aws_lb_target_group.main.arn_suffix
    LoadBalancer   = aws_lb.main.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = merge(var.tags, {
    Name = "HighResponseTime-${random_string.suffix.result}"
  })
}

resource "aws_cloudwatch_metric_alarm" "low_running_tasks" {
  alarm_name          = "ECSServiceRunningTasks-${random_string.suffix.result}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RunningTaskCount"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.low_running_tasks_threshold
  alarm_description   = "This metric monitors ECS service running tasks"
  treat_missing_data  = "breaching"

  dimensions = {
    ServiceName = aws_ecs_service.main.name
    ClusterName = aws_ecs_cluster.main.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = merge(var.tags, {
    Name = "ECSServiceRunningTasks-${random_string.suffix.result}"
  })
}

# SNS Topic for Alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts-${random_string.suffix.result}"

  tags = merge(var.tags, {
    Name = "${var.project_name}-alerts-${random_string.suffix.result}"
  })
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-lambda-role-${random_string.suffix.result}"
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_ecs_full_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}

# Lambda Function for Self-Healing
resource "aws_lambda_function" "self_healing" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.lambda_function_name}-${random_string.suffix.result}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "self_healing.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      CLUSTER_NAME = aws_ecs_cluster.main.name
      SERVICE_NAME = aws_ecs_service.main.name
    }
  }

  tags = merge(var.tags, {
    Name = "${var.lambda_function_name}-${random_string.suffix.result}"
  })
}

# Lambda function source code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/self_healing.zip"
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      cluster_name = aws_ecs_cluster.main.name
      service_name = aws_ecs_service.main.name
    })
    filename = "self_healing.py"
  }
}

# Lambda function source code template
resource "local_file" "lambda_function_template" {
  content = <<-EOF
import json
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ecs = boto3.client('ecs')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    try:
        # Parse CloudWatch alarm
        message = json.loads(event['Records'][0]['Sns']['Message'])
        alarm_name = message['AlarmName']
        
        logger.info(f"Processing alarm: {alarm_name}")
        
        cluster_name = os.environ.get('CLUSTER_NAME', '${cluster_name}')
        service_name = os.environ.get('SERVICE_NAME', '${service_name}')
        
        if 'ECSServiceRunningTasks' in alarm_name:
            # Handle ECS service health issues
            logger.info(f"Forcing new deployment for service {service_name}")
            
            # Force new deployment to restart unhealthy tasks
            response = ecs.update_service(
                cluster=cluster_name,
                service=service_name,
                forceNewDeployment=True
            )
            
            logger.info(f"Successfully forced new deployment for service {service_name}")
            
        elif 'UnhealthyTargets' in alarm_name:
            # Handle load balancer health issues
            logger.info("Unhealthy targets detected, ECS will handle automatically")
            
        elif 'HighResponseTime' in alarm_name:
            # Handle high response time issues
            logger.info("High response time detected, monitoring for auto-scaling")
            
        return {
            'statusCode': 200,
            'body': json.dumps('Self-healing action completed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error in self-healing function: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
EOF
  filename = "${path.module}/lambda_function.py.tpl"
}

# SNS Topic Subscription for Lambda
resource "aws_sns_topic_subscription" "lambda_alerts" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.self_healing.arn
}

# Lambda permission for SNS
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.self_healing.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}

# EKS Cluster (optional)
resource "aws_eks_cluster" "main" {
  count   = var.enable_eks ? 1 : 0
  name    = "${var.eks_cluster_name}-${random_string.suffix.result}"
  role_arn = aws_iam_role.eks_cluster[0].arn

  vpc_config {
    subnet_ids              = aws_subnet.public[*].id
    security_group_ids      = [aws_security_group.eks_cluster[0].id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
  ]

  tags = merge(var.tags, {
    Name = "${var.eks_cluster_name}-${random_string.suffix.result}"
  })
}

# EKS Cluster IAM Role (optional)
resource "aws_iam_role" "eks_cluster" {
  count = var.enable_eks ? 1 : 0
  name  = "${var.project_name}-eks-cluster-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name}-eks-cluster-role-${random_string.suffix.result}"
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  count      = var.enable_eks ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster[0].name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  count      = var.enable_eks ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster[0].name
}

# EKS Security Group (optional)
resource "aws_security_group" "eks_cluster" {
  count       = var.enable_eks ? 1 : 0
  name        = "${var.project_name}-eks-cluster-sg-${random_string.suffix.result}"
  description = "Security group for EKS cluster"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-eks-cluster-sg-${random_string.suffix.result}"
  })
}

# EKS Node Group (optional)
resource "aws_eks_node_group" "main" {
  count           = var.enable_eks ? 1 : 0
  cluster_name    = aws_eks_cluster.main[0].name
  node_group_name = "${var.eks_node_group_name}-${random_string.suffix.result}"
  node_role_arn   = aws_iam_role.eks_node_group[0].arn
  subnet_ids      = aws_subnet.public[*].id
  instance_types  = var.eks_node_instance_types

  scaling_config {
    desired_size = var.eks_node_desired_size
    max_size     = var.eks_node_max_size
    min_size     = var.eks_node_min_size
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
  ]

  tags = merge(var.tags, {
    Name = "${var.eks_node_group_name}-${random_string.suffix.result}"
  })
}

# EKS Node Group IAM Role (optional)
resource "aws_iam_role" "eks_node_group" {
  count = var.enable_eks ? 1 : 0
  name  = "${var.project_name}-eks-node-group-role-${random_string.suffix.result}"

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

  tags = merge(var.tags, {
    Name = "${var.project_name}-eks-node-group-role-${random_string.suffix.result}"
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  count      = var.enable_eks ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group[0].name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  count      = var.enable_eks ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group[0].name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  count      = var.enable_eks ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group[0].name
}