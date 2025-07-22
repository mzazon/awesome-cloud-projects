# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Data sources for existing resources
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

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
}

# Get latest Amazon Linux 2 AMI if not specified
data "aws_ami" "amazon_linux" {
  count       = var.ami_id == "" ? 1 : 0
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

# Local values for resource naming and configuration
locals {
  project_name_with_suffix = "${var.project_name}-${random_string.suffix.result}"
  
  # Use provided VPC/subnets or default ones
  vpc_id     = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids
  
  # Use provided AMI or latest Amazon Linux 2
  ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux[0].id
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Recipe      = "fault-tolerant-hpc-workflows-step-functions-spot-fleet"
    },
    var.additional_tags
  )
}

# S3 bucket for checkpoints and workflow data
resource "aws_s3_bucket" "checkpoints" {
  bucket        = "${local.project_name_with_suffix}-checkpoints-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.s3_force_destroy

  tags = local.common_tags
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "checkpoints" {
  bucket = aws_s3_bucket.checkpoints.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "checkpoints" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.checkpoints.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "checkpoints" {
  bucket = aws_s3_bucket.checkpoints.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create folder structure in S3
resource "aws_s3_object" "checkpoints_folder" {
  bucket = aws_s3_bucket.checkpoints.id
  key    = "checkpoints/"
  content = ""
}

resource "aws_s3_object" "workflows_folder" {
  bucket = aws_s3_bucket.checkpoints.id
  key    = "workflows/"
  content = ""
}

resource "aws_s3_object" "results_folder" {
  bucket = aws_s3_bucket.checkpoints.id
  key    = "results/"
  content = ""
}

# DynamoDB table for workflow state
resource "aws_dynamodb_table" "workflow_state" {
  name           = "${local.project_name_with_suffix}-workflow-state"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "WorkflowId"
  range_key      = "TaskId"

  attribute {
    name = "WorkflowId"
    type = "S"
  }

  attribute {
    name = "TaskId"
    type = "S"
  }

  dynamic "server_side_encryption" {
    for_each = var.enable_encryption ? [1] : []
    content {
      enabled = true
    }
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = local.common_tags
}

# Security group for EC2 instances
resource "aws_security_group" "hpc_instances" {
  name        = "${local.project_name_with_suffix}-hpc-instances"
  description = "Security group for HPC instances"
  vpc_id      = local.vpc_id

  # Allow SSH access if key pair is provided
  dynamic "ingress" {
    for_each = var.key_name != "" ? [1] : []
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/8"]
    }
  }

  # Allow inter-instance communication for MPI
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.project_name_with_suffix}-hpc-instances"
  })
}

# IAM role for Step Functions
resource "aws_iam_role" "stepfunctions_role" {
  name = "${local.project_name_with_suffix}-stepfunctions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for Step Functions
resource "aws_iam_role_policy" "stepfunctions_policy" {
  name = "StepFunctionsExecutionPolicy"
  role = aws_iam_role.stepfunctions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction",
          "batch:SubmitJob",
          "batch:DescribeJobs",
          "batch:TerminateJob",
          "ec2:DescribeSpotFleetRequests",
          "ec2:ModifySpotFleetRequest",
          "ec2:CancelSpotFleetRequests",
          "ec2:CreateSpotFleetRequest",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "cloudwatch:PutMetricData",
          "sns:Publish"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "${local.project_name_with_suffix}-lambda-role"

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

  tags = local.common_tags
}

# IAM policy attachments for Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_ec2" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_batch" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSBatchFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_s3" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# IAM role for Spot Fleet
resource "aws_iam_role" "spot_fleet_role" {
  name = "${local.project_name_with_suffix}-spot-fleet-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "spotfleet.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "spot_fleet_policy" {
  role       = aws_iam_role.spot_fleet_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetTaggingRole"
}

# IAM role for EC2 instances
resource "aws_iam_role" "ec2_instance_role" {
  name = "${local.project_name_with_suffix}-ec2-instance-role"

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

resource "aws_iam_role_policy_attachment" "ec2_instance_policy" {
  role       = aws_iam_role.ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "${local.project_name_with_suffix}-ec2-instance-profile"
  role = aws_iam_role.ec2_instance_role.name
}

# IAM role for Batch service
resource "aws_iam_role" "batch_service_role" {
  name = "${local.project_name_with_suffix}-batch-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "batch.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "batch_service_policy" {
  role       = aws_iam_role.batch_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}

# CloudWatch log groups for Lambda functions
resource "aws_cloudwatch_log_group" "lambda_logs" {
  for_each = toset([
    "spot-fleet-manager",
    "checkpoint-manager",
    "workflow-parser",
    "spot-interruption-handler"
  ])

  name              = "/aws/lambda/${local.project_name_with_suffix}-${each.key}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = local.common_tags
}

# Lambda function: Spot Fleet Manager
resource "aws_lambda_function" "spot_fleet_manager" {
  filename         = "spot_fleet_manager.zip"
  function_name    = "${local.project_name_with_suffix}-spot-fleet-manager"
  role            = aws_iam_role.lambda_role.arn
  handler         = "spot_fleet_manager.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  source_code_hash = data.archive_file.spot_fleet_manager.output_base64sha256

  environment {
    variables = {
      PROJECT_NAME = local.project_name_with_suffix
      REGION       = data.aws_region.current.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_logs]
  
  tags = local.common_tags
}

# Lambda function: Checkpoint Manager
resource "aws_lambda_function" "checkpoint_manager" {
  filename         = "checkpoint_manager.zip"
  function_name    = "${local.project_name_with_suffix}-checkpoint-manager"
  role            = aws_iam_role.lambda_role.arn
  handler         = "checkpoint_manager.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  source_code_hash = data.archive_file.checkpoint_manager.output_base64sha256

  environment {
    variables = {
      PROJECT_NAME = local.project_name_with_suffix
      REGION       = data.aws_region.current.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_logs]
  
  tags = local.common_tags
}

# Lambda function: Workflow Parser
resource "aws_lambda_function" "workflow_parser" {
  filename         = "workflow_parser.zip"
  function_name    = "${local.project_name_with_suffix}-workflow-parser"
  role            = aws_iam_role.lambda_role.arn
  handler         = "workflow_parser.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  source_code_hash = data.archive_file.workflow_parser.output_base64sha256

  environment {
    variables = {
      PROJECT_NAME = local.project_name_with_suffix
      REGION       = data.aws_region.current.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_logs]
  
  tags = local.common_tags
}

# Lambda function: Spot Interruption Handler
resource "aws_lambda_function" "spot_interruption_handler" {
  filename         = "spot_interruption_handler.zip"
  function_name    = "${local.project_name_with_suffix}-spot-interruption-handler"
  role            = aws_iam_role.lambda_role.arn
  handler         = "spot_interruption_handler.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = 60
  memory_size     = 256

  source_code_hash = data.archive_file.spot_interruption_handler.output_base64sha256

  environment {
    variables = {
      PROJECT_NAME = local.project_name_with_suffix
      REGION       = data.aws_region.current.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_logs]
  
  tags = local.common_tags
}

# Step Functions state machine
resource "aws_sfn_state_machine" "hpc_workflow" {
  name     = "${local.project_name_with_suffix}-orchestrator"
  role_arn = aws_iam_role.stepfunctions_role.arn
  type     = "STANDARD"

  definition = jsonencode({
    Comment = "Fault-tolerant HPC workflow orchestrator with Spot Fleet management"
    StartAt = "ParseWorkflow"
    States = {
      ParseWorkflow = {
        Type        = "Task"
        Resource    = aws_lambda_function.workflow_parser.arn
        ResultPath  = "$.parsed_workflow"
        Retry = [{
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 2
          MaxAttempts     = 3
          BackoffRate     = 2.0
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "WorkflowFailed"
          ResultPath  = "$.error"
        }]
        Next = "InitializeResources"
      }
      InitializeResources = {
        Type = "Pass"
        Parameters = {
          spot_fleet = {
            fleet_id = "placeholder-fleet-id"
            status   = "active"
          }
          batch_queue = {
            queue_name = "${local.project_name_with_suffix}-queue"
            status     = "initialized"
          }
        }
        ResultPath = "$.resources"
        Next       = "WorkflowCompleted"
      }
      WorkflowCompleted = {
        Type = "Pass"
        Parameters = {
          status         = "completed"
          workflow_id    = "$.parsed_workflow.workflow_id"
          completion_time = "$$.State.EnteredTime"
        }
        End = true
      }
      WorkflowFailed = {
        Type  = "Fail"
        Cause = "Workflow execution failed"
      }
    }
  })

  tags = local.common_tags
}

# AWS Batch compute environment
resource "aws_batch_compute_environment" "hpc_compute" {
  compute_environment_name = "${local.project_name_with_suffix}-compute"
  type                    = var.batch_compute_environment_type
  state                   = "ENABLED"
  service_role           = aws_iam_role.batch_service_role.arn

  compute_resources {
    type                = "EC2"
    allocation_strategy = "BEST_FIT_PROGRESSIVE"
    min_vcpus          = 0
    max_vcpus          = 256
    desired_vcpus      = 0
    
    instance_types = var.instance_types
    
    subnets            = local.subnet_ids
    security_group_ids = [aws_security_group.hpc_instances.id]
    
    instance_role = aws_iam_instance_profile.ec2_instance_profile.arn
    
    dynamic "ec2_key_pair" {
      for_each = var.key_name != "" ? [var.key_name] : []
      content {
        key_name = ec2_key_pair.value
      }
    }
    
    tags = local.common_tags
  }

  tags = local.common_tags
}

# AWS Batch job queue
resource "aws_batch_job_queue" "hpc_queue" {
  name                 = "${local.project_name_with_suffix}-queue"
  state                = "ENABLED"
  priority            = 1
  compute_environments = [aws_batch_compute_environment.hpc_compute.arn]

  tags = local.common_tags
}

# AWS Batch job definition
resource "aws_batch_job_definition" "hpc_job" {
  name = "${local.project_name_with_suffix}-job-definition"
  type = "container"

  container_properties = jsonencode({
    image  = "amazonlinux:2"
    vcpus  = 1
    memory = 1024
    jobRoleArn = aws_iam_role.ec2_instance_role.arn
    
    environment = [
      {
        name  = "PROJECT_NAME"
        value = local.project_name_with_suffix
      }
    ]
  })

  tags = local.common_tags
}

# SNS topic for notifications
resource "aws_sns_topic" "alerts" {
  count = var.enable_alerts ? 1 : 0
  name  = "${local.project_name_with_suffix}-alerts"

  tags = local.common_tags
}

# SNS topic subscription
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.enable_alerts && var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# EventBridge rule for Spot interruption warnings
resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name        = "${local.project_name_with_suffix}-spot-interruption-warning"
  description = "Detect Spot instance interruption warnings"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
    detail = {
      instance-action = ["terminate"]
    }
  })

  tags = local.common_tags
}

# EventBridge target for Spot interruption handler
resource "aws_cloudwatch_event_target" "spot_interruption_handler" {
  rule      = aws_cloudwatch_event_rule.spot_interruption.name
  target_id = "SpotInterruptionHandler"
  arn       = aws_lambda_function.spot_interruption_handler.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.spot_interruption_handler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.spot_interruption.arn
}

# CloudWatch dashboard
resource "aws_cloudwatch_dashboard" "hpc_monitoring" {
  count          = var.enable_monitoring ? 1 : 0
  dashboard_name = "${local.project_name_with_suffix}-monitoring"

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
            ["AWS/StepFunctions", "ExecutionTime", "StateMachineArn", aws_sfn_state_machine.hpc_workflow.arn],
            [".", "ExecutionsFailed", ".", "."],
            [".", "ExecutionsSucceeded", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "HPC Workflow Metrics"
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
            ["AWS/Batch", "RunningJobs", "JobQueue", aws_batch_job_queue.hpc_queue.name],
            [".", "SubmittedJobs", ".", "."],
            [".", "RunnableJobs", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Batch Job Metrics"
        }
      }
    ]
  })
}

# CloudWatch alarms
resource "aws_cloudwatch_metric_alarm" "workflow_failures" {
  count               = var.enable_alerts ? 1 : 0
  alarm_name          = "${local.project_name_with_suffix}-workflow-failures"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/StepFunctions"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors workflow failures"
  alarm_actions       = var.enable_alerts ? [aws_sns_topic.alerts[0].arn] : []

  dimensions = {
    StateMachineArn = aws_sfn_state_machine.hpc_workflow.arn
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "spot_interruptions" {
  count               = var.enable_alerts ? 1 : 0
  alarm_name          = "${local.project_name_with_suffix}-spot-interruptions"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "SpotInstanceInterruptions"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors spot instance interruptions"
  alarm_actions       = var.enable_alerts ? [aws_sns_topic.alerts[0].arn] : []

  tags = local.common_tags
}

# Sample workflow file in S3
resource "aws_s3_object" "sample_workflow" {
  bucket = aws_s3_bucket.checkpoints.id
  key    = "workflows/molecular-dynamics-sample.json"
  content = jsonencode({
    name        = "Molecular Dynamics Simulation"
    description = "Multi-stage molecular dynamics workflow with checkpointing"
    global_config = {
      checkpoint_interval = 600
      max_retry_attempts  = 3
      spot_strategy      = "diversified"
    }
    tasks = [
      {
        id               = "data-preprocessing"
        name             = "Data Preprocessing"
        type             = "batch"
        container_image  = "scientific-computing:preprocessing"
        command          = ["python", "/app/preprocess.py"]
        vcpus            = 2
        memory           = 4096
        nodes            = 1
        checkpoint_enabled = true
        spot_enabled     = true
        environment = {
          INPUT_PATH  = "/mnt/efs/raw_data"
          OUTPUT_PATH = "/mnt/efs/processed_data"
        }
      },
      {
        id               = "equilibration"
        name             = "System Equilibration"
        type             = "batch"
        container_image  = "scientific-computing:md-simulation"
        command          = ["mpirun", "gromacs", "equilibrate"]
        vcpus            = 8
        memory           = 16384
        nodes            = 4
        depends_on       = ["data-preprocessing"]
        checkpoint_enabled = true
        spot_enabled     = true
        retry_attempts   = 2
        environment = {
          INPUT_PATH  = "/mnt/efs/processed_data"
          OUTPUT_PATH = "/mnt/efs/equilibration"
        }
      },
      {
        id               = "production-run"
        name             = "Production MD Run"
        type             = "batch"
        container_image  = "scientific-computing:md-simulation"
        command          = ["mpirun", "gromacs", "mdrun"]
        vcpus            = 16
        memory           = 32768
        nodes            = 8
        depends_on       = ["equilibration"]
        checkpoint_enabled = true
        spot_enabled     = true
        retry_attempts   = 3
        backoff_multiplier = 2.5
        environment = {
          INPUT_PATH      = "/mnt/efs/equilibration"
          OUTPUT_PATH     = "/mnt/efs/production"
          SIMULATION_TIME = "1000000"
        }
      },
      {
        id               = "analysis"
        name             = "Trajectory Analysis"
        type             = "batch"
        container_image  = "scientific-computing:analysis"
        command          = ["python", "/app/analyze.py"]
        vcpus            = 4
        memory           = 8192
        nodes            = 2
        depends_on       = ["production-run"]
        checkpoint_enabled = false
        spot_enabled     = true
        environment = {
          INPUT_PATH  = "/mnt/efs/production"
          OUTPUT_PATH = "/mnt/efs/results"
        }
      }
    ]
  })
  content_type = "application/json"

  tags = local.common_tags
}

# Archive files for Lambda functions
data "archive_file" "spot_fleet_manager" {
  type        = "zip"
  output_path = "spot_fleet_manager.zip"
  source {
    content = templatefile("${path.module}/lambda_code/spot_fleet_manager.py", {
      project_name = local.project_name_with_suffix
      region       = data.aws_region.current.name
    })
    filename = "spot_fleet_manager.py"
  }
}

data "archive_file" "checkpoint_manager" {
  type        = "zip"
  output_path = "checkpoint_manager.zip"
  source {
    content = templatefile("${path.module}/lambda_code/checkpoint_manager.py", {
      project_name = local.project_name_with_suffix
      region       = data.aws_region.current.name
    })
    filename = "checkpoint_manager.py"
  }
}

data "archive_file" "workflow_parser" {
  type        = "zip"
  output_path = "workflow_parser.zip"
  source {
    content = templatefile("${path.module}/lambda_code/workflow_parser.py", {
      project_name = local.project_name_with_suffix
      region       = data.aws_region.current.name
    })
    filename = "workflow_parser.py"
  }
}

data "archive_file" "spot_interruption_handler" {
  type        = "zip"
  output_path = "spot_interruption_handler.zip"
  source {
    content = templatefile("${path.module}/lambda_code/spot_interruption_handler.py", {
      project_name = local.project_name_with_suffix
      region       = data.aws_region.current.name
    })
    filename = "spot_interruption_handler.py"
  }
}