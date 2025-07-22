# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

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

# Local variables for resource naming and configuration
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Resource names with random suffix
  cluster_name         = var.ecs_cluster_name != "" ? var.ecs_cluster_name : "${local.name_prefix}-${random_string.suffix.result}"
  eks_cluster_name     = var.eks_cluster_name != "" ? var.eks_cluster_name : "${local.name_prefix}-eks-${random_string.suffix.result}"
  database_secret_name = var.database_secret_name != "" ? var.database_secret_name : "${local.name_prefix}-db-${random_string.suffix.result}"
  api_secret_name      = var.api_secret_name != "" ? var.api_secret_name : "${local.name_prefix}-api-${random_string.suffix.result}"
  lambda_function_name = var.lambda_function_name != "" ? var.lambda_function_name : "${local.name_prefix}-rotation-${random_string.suffix.result}"
  
  # VPC and subnet configuration
  vpc_id     = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids
  
  # Tags
  common_tags = merge(var.additional_tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# Random string for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Random password for secret rotation
resource "random_password" "rotation_password" {
  length  = 32
  special = true
}

# ================================
# KMS Key for Secrets Encryption
# ================================

resource "aws_kms_key" "secrets_key" {
  count = var.enable_kms_encryption ? 1 : 0
  
  description             = "KMS key for Secrets Manager encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Secrets Manager to use the key"
        Effect = "Allow"
        Principal = {
          Service = "secretsmanager.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = local.common_tags
}

resource "aws_kms_alias" "secrets_key_alias" {
  count = var.enable_kms_encryption ? 1 : 0
  
  name          = "alias/${local.name_prefix}-secrets-key"
  target_key_id = aws_kms_key.secrets_key[0].key_id
}

# ================================
# Secrets Manager Resources
# ================================

# Database credentials secret
resource "aws_secretsmanager_secret" "database_secret" {
  name                    = local.database_secret_name
  description             = "Database credentials for ${var.project_name} application"
  kms_key_id              = var.enable_kms_encryption ? aws_kms_key.secrets_key[0].arn : null
  recovery_window_in_days = 7
  
  tags = merge(local.common_tags, {
    Name = local.database_secret_name
    Type = "database-credentials"
  })
}

resource "aws_secretsmanager_secret_version" "database_secret_version" {
  secret_id = aws_secretsmanager_secret.database_secret.id
  secret_string = jsonencode({
    username = var.database_credentials.username
    password = var.database_credentials.password
    host     = var.database_credentials.host
    port     = var.database_credentials.port
    database = var.database_credentials.database
  })
}

# API keys secret
resource "aws_secretsmanager_secret" "api_secret" {
  name                    = local.api_secret_name
  description             = "API keys for external services"
  kms_key_id              = var.enable_kms_encryption ? aws_kms_key.secrets_key[0].arn : null
  recovery_window_in_days = 7
  
  tags = merge(local.common_tags, {
    Name = local.api_secret_name
    Type = "api-keys"
  })
}

resource "aws_secretsmanager_secret_version" "api_secret_version" {
  secret_id = aws_secretsmanager_secret.api_secret.id
  secret_string = jsonencode({
    github_token = var.api_credentials.github_token
    stripe_key   = var.api_credentials.stripe_key
    twilio_sid   = var.api_credentials.twilio_sid
  })
}

# ================================
# IAM Roles and Policies
# ================================

# ECS Task Role
resource "aws_iam_role" "ecs_task_role" {
  name = "${local.cluster_name}-ecs-task-role"
  
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
  
  tags = local.common_tags
}

# ECS Task Role Policy
resource "aws_iam_role_policy" "ecs_task_secrets_policy" {
  name = "SecretsManagerAccess"
  role = aws_iam_role.ecs_task_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.database_secret.arn,
          aws_secretsmanager_secret.api_secret.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = var.enable_kms_encryption ? [aws_kms_key.secrets_key[0].arn] : []
      }
    ]
  })
}

# EKS Cluster Service Role
resource "aws_iam_role" "eks_cluster_role" {
  name = "${local.eks_cluster_name}-cluster-role"
  
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
  
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# EKS Node Group Role
resource "aws_iam_role" "eks_node_role" {
  name = "${local.eks_cluster_name}-node-role"
  
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

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

# OIDC Identity Provider for EKS
data "tls_certificate" "eks_cluster" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks_oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  
  tags = local.common_tags
}

# IRSA Role for EKS Pods
resource "aws_iam_role" "eks_pod_role" {
  name = "${local.eks_cluster_name}-pod-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks_oidc.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks_oidc.url, "https://", "")}:sub" = "system:serviceaccount:default:secrets-demo-sa"
            "${replace(aws_iam_openid_connect_provider.eks_oidc.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# IRSA Role Policy for Secrets Access
resource "aws_iam_role_policy" "eks_pod_secrets_policy" {
  name = "SecretsManagerAccess"
  role = aws_iam_role.eks_pod_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.database_secret.arn,
          aws_secretsmanager_secret.api_secret.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = var.enable_kms_encryption ? [aws_kms_key.secrets_key[0].arn] : []
      }
    ]
  })
}

# ================================
# ECS Cluster and Task Definition
# ================================

resource "aws_ecs_cluster" "main" {
  name = local.cluster_name
  
  capacity_providers = ["FARGATE"]
  
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
  
  tags = merge(local.common_tags, {
    Name = local.cluster_name
  })
}

# CloudWatch Log Group for ECS
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${local.cluster_name}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = local.common_tags
}

# ECS Task Definition
resource "aws_ecs_task_definition" "main" {
  family                   = "${local.cluster_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  
  container_definitions = jsonencode([
    {
      name  = "demo-app"
      image = "nginx:latest"
      
      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]
      
      secrets = [
        {
          name      = "DB_USERNAME"
          valueFrom = "${aws_secretsmanager_secret.database_secret.arn}:username::"
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.database_secret.arn}:password::"
        },
        {
          name      = "DB_HOST"
          valueFrom = "${aws_secretsmanager_secret.database_secret.arn}:host::"
        },
        {
          name      = "GITHUB_TOKEN"
          valueFrom = "${aws_secretsmanager_secret.api_secret.arn}:github_token::"
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
  
  tags = local.common_tags
}

# ECS Execution Role
resource "aws_iam_role" "ecs_execution_role" {
  name = "${local.cluster_name}-execution-role"
  
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
  
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.ecs_execution_role.name
}

# ================================
# EKS Cluster
# ================================

resource "aws_eks_cluster" "main" {
  name     = local.eks_cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.eks_cluster_version
  
  vpc_config {
    subnet_ids = local.subnet_ids
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
  
  tags = merge(local.common_tags, {
    Name = local.eks_cluster_name
  })
}

# EKS Node Group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.eks_cluster_name}-nodes"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = local.subnet_ids
  instance_types  = [var.eks_node_instance_type]
  
  scaling_config {
    desired_size = var.eks_node_group_desired_size
    max_size     = var.eks_node_group_max_size
    min_size     = var.eks_node_group_min_size
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy
  ]
  
  tags = merge(local.common_tags, {
    Name = "${local.eks_cluster_name}-nodes"
  })
}

# ================================
# Lambda Function for Secret Rotation
# ================================

# Lambda function code
data "archive_file" "lambda_rotation_zip" {
  count = var.enable_secret_rotation ? 1 : 0
  
  type        = "zip"
  output_path = "${path.module}/lambda_rotation.zip"
  source {
    content = templatefile("${path.module}/lambda_rotation.py.tpl", {
      region = data.aws_region.current.name
    })
    filename = "lambda_rotation.py"
  }
}

# Lambda function
resource "aws_lambda_function" "rotation" {
  count = var.enable_secret_rotation ? 1 : 0
  
  filename         = data.archive_file.lambda_rotation_zip[0].output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_role[0].arn
  handler         = "lambda_rotation.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  source_code_hash = data.archive_file.lambda_rotation_zip[0].output_base64sha256
  
  tags = merge(local.common_tags, {
    Name = local.lambda_function_name
  })
}

# Lambda IAM Role
resource "aws_iam_role" "lambda_role" {
  count = var.enable_secret_rotation ? 1 : 0
  
  name = "${local.lambda_function_name}-role"
  
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

# Lambda basic execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  count = var.enable_secret_rotation ? 1 : 0
  
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role[0].name
}

# Lambda secrets access policy
resource "aws_iam_role_policy" "lambda_secrets_policy" {
  count = var.enable_secret_rotation ? 1 : 0
  
  name = "SecretsManagerRotation"
  role = aws_iam_role.lambda_role[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:UpdateSecret",
          "secretsmanager:GetRandomPassword"
        ]
        Resource = [
          aws_secretsmanager_secret.database_secret.arn,
          aws_secretsmanager_secret.api_secret.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.enable_kms_encryption ? [aws_kms_key.secrets_key[0].arn] : []
      }
    ]
  })
}

# Lambda permission for Secrets Manager
resource "aws_lambda_permission" "secrets_manager_invoke" {
  count = var.enable_secret_rotation ? 1 : 0
  
  statement_id  = "AllowSecretsManagerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotation[0].function_name
  principal     = "secretsmanager.amazonaws.com"
}

# Configure secret rotation
resource "aws_secretsmanager_secret_rotation" "database_rotation" {
  count = var.enable_secret_rotation ? 1 : 0
  
  secret_id           = aws_secretsmanager_secret.database_secret.id
  rotation_lambda_arn = aws_lambda_function.rotation[0].arn
  
  rotation_rules {
    automatically_after_days = var.rotation_days
  }
  
  depends_on = [aws_lambda_permission.secrets_manager_invoke]
}

# ================================
# CloudWatch Monitoring
# ================================

# CloudWatch alarm for unauthorized access
resource "aws_cloudwatch_metric_alarm" "unauthorized_access" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "${local.database_secret_name}-unauthorized-access"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "UnauthorizedAPICallsCount"
  namespace           = "AWS/SecretsManager"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alert on unauthorized secret access attempts"
  
  tags = local.common_tags
}

# CloudWatch log group for Secrets Manager audit
resource "aws_cloudwatch_log_group" "secrets_audit" {
  count = var.enable_monitoring ? 1 : 0
  
  name              = "/aws/secretsmanager/${local.database_secret_name}"
  retention_in_days = 90
  
  tags = local.common_tags
}

# ================================
# Lambda Rotation Function Template
# ================================

# Create Lambda function template file
resource "local_file" "lambda_rotation_template" {
  count = var.enable_secret_rotation ? 1 : 0
  
  filename = "${path.module}/lambda_rotation.py.tpl"
  content  = <<-EOF
import boto3
import json
import logging
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to rotate secrets in AWS Secrets Manager
    """
    client = boto3.client('secretsmanager', region_name='${region}')
    
    # Get the secret ARN from the event
    secret_arn = event.get('Step', event.get('SecretId'))
    
    if not secret_arn:
        logger.error("No secret ARN provided in event")
        return {'statusCode': 400, 'body': 'No secret ARN provided'}
    
    try:
        # Generate new random password
        new_password_response = client.get_random_password(
            PasswordLength=32,
            ExcludeCharacters='"@/\\'
        )
        new_password = new_password_response['RandomPassword']
        
        # Get current secret
        current_secret = client.get_secret_value(SecretId=secret_arn)
        secret_dict = json.loads(current_secret['SecretString'])
        
        # Update password (only for database secrets)
        if 'password' in secret_dict:
            secret_dict['password'] = new_password
            
            # Update secret with new password
            client.update_secret(
                SecretId=secret_arn,
                SecretString=json.dumps(secret_dict)
            )
            
            logger.info(f"Successfully rotated secret: {secret_arn}")
            return {
                'statusCode': 200, 
                'body': json.dumps({
                    'message': 'Secret rotated successfully',
                    'secretArn': secret_arn,
                    'timestamp': datetime.utcnow().isoformat()
                })
            }
        else:
            logger.info(f"Secret {secret_arn} does not contain a password field, skipping rotation")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Secret does not require rotation',
                    'secretArn': secret_arn
                })
            }
            
    except Exception as e:
        logger.error(f"Error rotating secret {secret_arn}: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Failed to rotate secret: {str(e)}',
                'secretArn': secret_arn
            })
        }
EOF
}