# =============================================================================
# AWS Batch Multi-Node Parallel Jobs Infrastructure
# Implementing Distributed Scientific Computing with AWS Batch
# =============================================================================

# -----------------------------------------------------------------------------
# Provider Configuration
# -----------------------------------------------------------------------------

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

# Get current AWS account and region info
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common tags applied to all resources
  common_tags = {
    Project     = "distributed-scientific-computing"
    Environment = var.environment
    Purpose     = "multi-node-parallel-batch"
    ManagedBy   = "terraform"
  }
  
  # Resource naming prefix
  name_prefix = "${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  
  # VPC CIDR and subnet calculations
  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, min(3, length(data.aws_availability_zones.available.names)))
}

# =============================================================================
# NETWORKING INFRASTRUCTURE
# =============================================================================

# -----------------------------------------------------------------------------
# VPC and Subnets
# -----------------------------------------------------------------------------

# Main VPC for the scientific computing environment
resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# Internet Gateway for public subnet connectivity
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# Public subnets for NAT gateways and bastion hosts
resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(local.vpc_cidr, 8, count.index + 101)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-${local.azs[count.index]}"
    Type = "public"
  })
}

# Private subnets for Batch compute nodes
resource "aws_subnet" "private" {
  count = length(local.azs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(local.vpc_cidr, 8, count.index + 1)
  availability_zone = local.azs[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-${local.azs[count.index]}"
    Type = "private"
  })
}

# Elastic IPs for NAT gateways
resource "aws_eip" "nat" {
  count = var.single_nat_gateway ? 1 : length(aws_subnet.public)

  domain = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-eip-${count.index + 1}"
  })
}

# NAT gateways for private subnet internet access
resource "aws_nat_gateway" "main" {
  count = var.single_nat_gateway ? 1 : length(aws_subnet.public)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# Route Tables and Routes
# -----------------------------------------------------------------------------

# Public route table
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

# Private route tables
resource "aws_route_table" "private" {
  count = var.single_nat_gateway ? 1 : length(aws_subnet.private)

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[var.single_nat_gateway ? 0 : count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-rt-${count.index + 1}"
  })
}

# Associate private subnets with private route tables
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[var.single_nat_gateway ? 0 : count.index].id
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------

# Security group for Batch compute nodes
resource "aws_security_group" "batch_compute" {
  name_prefix = "${local.name_prefix}-batch-compute-"
  description = "Security group for AWS Batch compute environment with MPI support"
  vpc_id      = aws_vpc.main.id

  # Allow all traffic within the security group for MPI communication
  ingress {
    description = "All TCP traffic within security group for MPI"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "All UDP traffic within security group for MPI"
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    self        = true
  }

  # Allow ICMP for network diagnostics
  ingress {
    description = "ICMP for network diagnostics"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    self        = true
  }

  # SSH access from within VPC (for debugging)
  ingress {
    description = "SSH access from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-batch-compute-sg"
  })
}

# Security group for EFS
resource "aws_security_group" "efs" {
  name_prefix = "${local.name_prefix}-efs-"
  description = "Security group for EFS mount targets"
  vpc_id      = aws_vpc.main.id

  # NFS traffic from Batch compute nodes
  ingress {
    description     = "NFS from Batch compute nodes"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.batch_compute.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-efs-sg"
  })
}

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${local.name_prefix}-vpc-endpoints-"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  # HTTPS traffic from Batch compute nodes
  ingress {
    description     = "HTTPS from Batch compute nodes"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.batch_compute.id]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-endpoints-sg"
  })
}

# =============================================================================
# SHARED STORAGE (EFS)
# =============================================================================

# EFS file system for shared storage across compute nodes
resource "aws_efs_file_system" "shared_storage" {
  creation_token = "${local.name_prefix}-shared-storage"
  
  performance_mode                = var.efs_performance_mode
  throughput_mode                 = var.efs_throughput_mode
  provisioned_throughput_in_mibps = var.efs_throughput_mode == "provisioned" ? var.efs_provisioned_throughput : null
  
  encrypted = true

  lifecycle_policy {
    transition_to_ia = var.efs_transition_to_ia
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-shared-storage"
  })
}

# EFS mount targets in each private subnet
resource "aws_efs_mount_target" "shared_storage" {
  count = length(aws_subnet.private)

  file_system_id  = aws_efs_file_system.shared_storage.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.efs.id]
}

# =============================================================================
# CONTAINER REGISTRY (ECR)
# =============================================================================

# ECR repository for MPI container images
resource "aws_ecr_repository" "batch_app" {
  name                 = "${local.name_prefix}-mpi-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mpi-app"
  })
}

# ECR lifecycle policy to manage image retention
resource "aws_ecr_lifecycle_policy" "batch_app" {
  repository = aws_ecr_repository.batch_app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep only 1 untagged image"
        selection = {
          tagStatus   = "untagged"
          countType   = "imageCountMoreThan"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# =============================================================================
# IAM ROLES AND POLICIES
# =============================================================================

# -----------------------------------------------------------------------------
# AWS Batch Service Role
# -----------------------------------------------------------------------------

# Trust policy for AWS Batch service
data "aws_iam_policy_document" "batch_service_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["batch.amazonaws.com"]
    }
  }
}

# AWS Batch service role
resource "aws_iam_role" "batch_service_role" {
  name               = "${local.name_prefix}-batch-service-role"
  assume_role_policy = data.aws_iam_policy_document.batch_service_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-batch-service-role"
  })
}

# Attach AWS managed policy for Batch service
resource "aws_iam_role_policy_attachment" "batch_service_role" {
  role       = aws_iam_role.batch_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}

# -----------------------------------------------------------------------------
# ECS Instance Role
# -----------------------------------------------------------------------------

# Trust policy for EC2 instances
data "aws_iam_policy_document" "ecs_instance_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ECS instance role
resource "aws_iam_role" "ecs_instance_role" {
  name               = "${local.name_prefix}-ecs-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_instance_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-instance-role"
  })
}

# Attach AWS managed policy for ECS instance
resource "aws_iam_role_policy_attachment" "ecs_instance_role" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Additional policy for EFS access
data "aws_iam_policy_document" "ecs_efs_policy" {
  statement {
    effect = "Allow"
    actions = [
      "elasticfilesystem:CreateFileSystem",
      "elasticfilesystem:CreateMountTarget",
      "elasticfilesystem:DescribeFileSystems",
      "elasticfilesystem:DescribeMountTargets",
      "elasticfilesystem:DescribeAccessPoints",
      "elasticfilesystem:CreateAccessPoint",
      "elasticfilesystem:DeleteAccessPoint"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ecs_efs_policy" {
  name   = "ECSEFSPolicy"
  role   = aws_iam_role.ecs_instance_role.id
  policy = data.aws_iam_policy_document.ecs_efs_policy.json
}

# Instance profile for ECS instances
resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "${local.name_prefix}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance_role.name

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecs-instance-profile"
  })
}

# -----------------------------------------------------------------------------
# Job Execution Role
# -----------------------------------------------------------------------------

# Trust policy for ECS tasks
data "aws_iam_policy_document" "job_execution_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Job execution role
resource "aws_iam_role" "job_execution_role" {
  name               = "${local.name_prefix}-job-execution-role"
  assume_role_policy = data.aws_iam_policy_document.job_execution_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-job-execution-role"
  })
}

# Attach AWS managed policy for task execution
resource "aws_iam_role_policy_attachment" "job_execution_role" {
  role       = aws_iam_role.job_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy for enhanced job execution permissions
data "aws_iam_policy_document" "job_execution_enhanced" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "job_execution_enhanced" {
  name   = "EnhancedJobExecutionPolicy"
  role   = aws_iam_role.job_execution_role.id
  policy = data.aws_iam_policy_document.job_execution_enhanced.json
}

# =============================================================================
# PLACEMENT GROUP FOR ENHANCED NETWORKING
# =============================================================================

# Cluster placement group for high-performance networking
resource "aws_placement_group" "hpc_cluster" {
  name         = "${local.name_prefix}-hpc-cluster"
  strategy     = "cluster"
  spread_level = "rack"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-hpc-cluster"
  })
}

# =============================================================================
# AWS BATCH INFRASTRUCTURE
# =============================================================================

# -----------------------------------------------------------------------------
# Compute Environment
# -----------------------------------------------------------------------------

# Batch compute environment for multi-node parallel jobs
resource "aws_batch_compute_environment" "multi_node" {
  compute_environment_name = "${local.name_prefix}-multi-node-compute"
  type                     = "MANAGED"
  state                    = "ENABLED"

  compute_resources {
    type          = "EC2"
    min_vcpus     = var.batch_min_vcpus
    max_vcpus     = var.batch_max_vcpus
    desired_vcpus = var.batch_desired_vcpus

    # Instance types optimized for HPC workloads
    instance_types = var.batch_instance_types

    # Networking configuration
    subnets            = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.batch_compute.id]

    # Instance configuration
    instance_role = aws_iam_instance_profile.ecs_instance_profile.arn

    # Placement group for enhanced networking (Note: requires manual association via AWS CLI/API)
    # placement_group = aws_placement_group.hpc_cluster.name  # Not yet supported in Terraform

    tags = merge(local.common_tags, {
      Name = "${local.name_prefix}-batch-compute-instances"
    })
  }

  service_role = aws_iam_role.batch_service_role.arn

  depends_on = [
    aws_iam_role_policy_attachment.batch_service_role,
    aws_iam_role_policy_attachment.ecs_instance_role
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-multi-node-compute"
  })
}

# -----------------------------------------------------------------------------
# Job Queue
# -----------------------------------------------------------------------------

# Job queue for scientific computing workloads
resource "aws_batch_job_queue" "scientific_queue" {
  name     = "${local.name_prefix}-scientific-queue"
  state    = "ENABLED"
  priority = 1

  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.multi_node.arn
  }

  depends_on = [aws_batch_compute_environment.multi_node]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-scientific-queue"
  })
}

# -----------------------------------------------------------------------------
# Job Definitions
# -----------------------------------------------------------------------------

# Basic multi-node parallel job definition
resource "aws_batch_job_definition" "mpi_job" {
  name = "${local.name_prefix}-mpi-job"
  type = "multinode"

  node_properties = jsonencode({
    mainNode = 0
    numNodes = var.default_num_nodes
    nodeRangeProperties = [
      {
        targetNodes = "0:"
        container = {
          image  = "${aws_ecr_repository.batch_app.repository_url}:latest"
          vcpus  = var.default_vcpus_per_node
          memory = var.default_memory_per_node

          # Job execution role for enhanced permissions
          jobRoleArn = aws_iam_role.job_execution_role.arn

          # Environment variables for MPI and EFS configuration
          environment = [
            {
              name  = "EFS_DNS_NAME"
              value = aws_efs_file_system.shared_storage.dns_name
            },
            {
              name  = "EFS_MOUNT_POINT"
              value = "/mnt/efs"
            },
            {
              name  = "OMPI_ALLOW_RUN_AS_ROOT"
              value = "1"
            },
            {
              name  = "OMPI_ALLOW_RUN_AS_ROOT_CONFIRM"
              value = "1"
            }
          ]

          # Mount points for shared storage
          mountPoints = [
            {
              sourceVolume  = "shared-data"
              containerPath = "/mnt/efs"
              readOnly      = false
            },
            {
              sourceVolume  = "tmp"
              containerPath = "/tmp"
              readOnly      = false
            }
          ]

          # Volume definitions
          volumes = [
            {
              name = "shared-data"
              efsVolumeConfiguration = {
                fileSystemId      = aws_efs_file_system.shared_storage.id
                rootDirectory     = "/"
                transitEncryption = "ENABLED"
              }
            },
            {
              name = "tmp"
              host = {
                sourcePath = "/tmp"
              }
            }
          ]

          # Enable privileged mode for enhanced networking and system operations
          privileged = true

          # Enhanced logging configuration
          logConfiguration = {
            logDriver = "awslogs"
            options = {
              "awslogs-group"         = "/aws/batch/job"
              "awslogs-region"        = data.aws_region.current.name
              "awslogs-stream-prefix" = "mpi-job"
            }
          }
        }
      }
    ]
  })

  retry_strategy {
    attempts = var.job_retry_attempts
  }

  timeout {
    attempt_duration_seconds = var.job_timeout_seconds
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mpi-job"
  })
}

# Advanced parameterized job definition for flexible workloads
resource "aws_batch_job_definition" "parameterized_mpi_job" {
  name = "${local.name_prefix}-parameterized-mpi-job"
  type = "multinode"

  # Job parameters for runtime customization
  parameters = {
    inputDataPath    = "/mnt/efs/input"
    outputDataPath   = "/mnt/efs/output"
    computeIntensity = "medium"
    mpiProcesses     = "4"
  }

  node_properties = jsonencode({
    mainNode = 0
    numNodes = var.default_num_nodes
    nodeRangeProperties = [
      {
        targetNodes = "0:"
        container = {
          image  = "${aws_ecr_repository.batch_app.repository_url}:latest"
          vcpus  = var.default_vcpus_per_node
          memory = var.default_memory_per_node

          jobRoleArn = aws_iam_role.job_execution_role.arn

          # Parameterized environment variables
          environment = [
            {
              name  = "EFS_DNS_NAME"
              value = aws_efs_file_system.shared_storage.dns_name
            },
            {
              name  = "EFS_MOUNT_POINT"
              value = "/mnt/efs"
            },
            {
              name  = "INPUT_PATH"
              value = "Ref::inputDataPath"
            },
            {
              name  = "OUTPUT_PATH"
              value = "Ref::outputDataPath"
            },
            {
              name  = "COMPUTE_INTENSITY"
              value = "Ref::computeIntensity"
            },
            {
              name  = "MPI_PROCESSES"
              value = "Ref::mpiProcesses"
            },
            {
              name  = "OMPI_ALLOW_RUN_AS_ROOT"
              value = "1"
            },
            {
              name  = "OMPI_ALLOW_RUN_AS_ROOT_CONFIRM"
              value = "1"
            }
          ]

          mountPoints = [
            {
              sourceVolume  = "shared-data"
              containerPath = "/mnt/efs"
              readOnly      = false
            }
          ]

          volumes = [
            {
              name = "shared-data"
              efsVolumeConfiguration = {
                fileSystemId      = aws_efs_file_system.shared_storage.id
                rootDirectory     = "/"
                transitEncryption = "ENABLED"
              }
            }
          ]

          privileged = true

          logConfiguration = {
            logDriver = "awslogs"
            options = {
              "awslogs-group"         = "/aws/batch/job"
              "awslogs-region"        = data.aws_region.current.name
              "awslogs-stream-prefix" = "parameterized-mpi-job"
            }
          }
        }
      }
    ]
  })

  retry_strategy {
    attempts = var.job_retry_attempts
  }

  timeout {
    attempt_duration_seconds = var.job_timeout_seconds * 2  # Longer timeout for parameterized jobs
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-parameterized-mpi-job"
  })
}

# =============================================================================
# CLOUDWATCH MONITORING
# =============================================================================

# CloudWatch log group for Batch jobs
resource "aws_cloudwatch_log_group" "batch_jobs" {
  name              = "/aws/batch/job"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-batch-logs"
  })
}

# CloudWatch dashboard for monitoring
resource "aws_cloudwatch_dashboard" "batch_monitoring" {
  dashboard_name = "${local.name_prefix}-batch-monitoring"

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
            ["AWS/Batch", "SubmittedJobs", "JobQueue", aws_batch_job_queue.scientific_queue.name],
            [".", "RunnableJobs", ".", "."],
            [".", "RunningJobs", ".", "."],
            [".", "CompletedJobs", ".", "."],
            [".", "FailedJobs", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Batch Job Status - ${aws_batch_job_queue.scientific_queue.name}"
          period  = 300
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          query   = "SOURCE '${aws_cloudwatch_log_group.batch_jobs.name}' | fields @timestamp, @message | filter @message like /MPI/ | sort @timestamp desc | limit 100"
          region  = data.aws_region.current.name
          title   = "MPI Job Logs"
          view    = "table"
        }
      }
    ]
  })
}

# CloudWatch alarms for monitoring job failures
resource "aws_cloudwatch_metric_alarm" "failed_jobs" {
  alarm_name          = "${local.name_prefix}-failed-jobs"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "FailedJobs"
  namespace           = "AWS/Batch"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors failed batch jobs"
  alarm_actions       = var.sns_topic_arn != null ? [var.sns_topic_arn] : []

  dimensions = {
    JobQueue = aws_batch_job_queue.scientific_queue.name
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-failed-jobs-alarm"
  })
}

# =============================================================================
# VPC ENDPOINTS (OPTIONAL - FOR COST OPTIMIZATION)
# =============================================================================

# VPC endpoint for ECR API (reduces NAT gateway costs)
resource "aws_vpc_endpoint" "ecr_api" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecr-api-endpoint"
  })
}

# VPC endpoint for ECR Docker registry
resource "aws_vpc_endpoint" "ecr_dkr" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-ecr-dkr-endpoint"
  })
}

# VPC endpoint for S3 (Gateway endpoint - no additional charges)
resource "aws_vpc_endpoint" "s3" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-s3-endpoint"
  })
}