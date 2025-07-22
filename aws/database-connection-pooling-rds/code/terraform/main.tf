# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  name_suffix = random_id.suffix.hex
  common_name = "${var.project_name}-${var.environment}-${local.name_suffix}"
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}

# Data source for current AWS region
data "aws_region" "current" {}

#######################
# VPC and Networking  #
#######################

# Create VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name = "${local.common_name}-vpc"
  })
}

# Create private subnets for RDS
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(var.common_tags, {
    Name = "${local.common_name}-private-subnet-${count.index + 1}"
    Type = "Private"
  })
}

# Create DB subnet group
resource "aws_db_subnet_group" "main" {
  name       = "${local.common_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(var.common_tags, {
    Name = "${local.common_name}-db-subnet-group"
  })
}

# Security group for RDS instance
resource "aws_security_group" "rds" {
  name_prefix = "${local.common_name}-rds-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for RDS instance"

  # Allow inbound MySQL traffic from RDS Proxy security group
  ingress {
    description     = "MySQL from RDS Proxy"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.rds_proxy.id]
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${local.common_name}-rds-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for RDS Proxy
resource "aws_security_group" "rds_proxy" {
  name_prefix = "${local.common_name}-rds-proxy-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for RDS Proxy"

  # Allow inbound MySQL traffic from VPC CIDR
  ingress {
    description = "MySQL from VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${local.common_name}-rds-proxy-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

#########################
# Secrets Manager       #
#########################

# Create secret for database credentials
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${local.common_name}-db-credentials"
  description             = "Database credentials for RDS Proxy demo"
  recovery_window_in_days = 7

  tags = merge(var.common_tags, {
    Name = "${local.common_name}-db-credentials"
  })
}

# Store database credentials in secret
resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
  })
}

#########################
# IAM Role for RDS Proxy #
#########################

# IAM role for RDS Proxy
resource "aws_iam_role" "rds_proxy" {
  name = "${local.common_name}-rds-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${local.common_name}-rds-proxy-role"
  })
}

# IAM policy for RDS Proxy to access Secrets Manager
resource "aws_iam_policy" "rds_proxy_secrets" {
  name        = "${local.common_name}-rds-proxy-secrets-policy"
  description = "Policy for RDS Proxy to access Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.db_credentials.arn
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${local.common_name}-rds-proxy-secrets-policy"
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "rds_proxy_secrets" {
  role       = aws_iam_role.rds_proxy.name
  policy_arn = aws_iam_policy.rds_proxy_secrets.arn
}

#########################
# RDS Instance          #
#########################

# Create RDS MySQL instance
resource "aws_db_instance" "main" {
  identifier = "${local.common_name}-db"

  # Engine configuration
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.db_instance_class

  # Storage configuration
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage * 2
  storage_type          = "gp2"
  storage_encrypted     = true

  # Database configuration
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Backup configuration
  backup_retention_period   = var.db_backup_retention_period
  backup_window            = "03:00-04:00"
  maintenance_window       = "sun:04:00-sun:05:00"
  auto_minor_version_upgrade = true

  # Performance and monitoring
  performance_insights_enabled = true
  monitoring_interval         = 60
  monitoring_role_arn         = aws_iam_role.rds_monitoring.arn

  # Deletion protection
  deletion_protection = false
  skip_final_snapshot = true

  tags = merge(var.common_tags, {
    Name = "${local.common_name}-db"
  })

  depends_on = [
    aws_db_subnet_group.main,
    aws_security_group.rds
  ]
}

# IAM role for RDS enhanced monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "${local.common_name}-rds-monitoring-role"

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

  tags = merge(var.common_tags, {
    Name = "${local.common_name}-rds-monitoring-role"
  })
}

# Attach AWS managed policy for RDS enhanced monitoring
resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

#########################
# RDS Proxy             #
#########################

# Create RDS Proxy
resource "aws_db_proxy" "main" {
  name                   = "${local.common_name}-proxy"
  engine_family         = "MYSQL"
  auth {
    auth_scheme = "SECRETS"
    secret_arn  = aws_secretsmanager_secret.db_credentials.arn
  }
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_subnet_ids         = aws_subnet.private[*].id
  vpc_security_group_ids = [aws_security_group.rds_proxy.id]

  # Connection pooling configuration
  idle_client_timeout          = var.proxy_idle_client_timeout
  max_connections_percent       = var.proxy_max_connections_percent
  max_idle_connections_percent  = var.proxy_max_idle_connections_percent
  require_tls                  = false
  debug_logging                = var.proxy_debug_logging

  tags = merge(var.common_tags, {
    Name = "${local.common_name}-proxy"
  })

  depends_on = [
    aws_db_instance.main,
    aws_iam_role_policy_attachment.rds_proxy_secrets
  ]
}

# Register RDS instance as target with RDS Proxy
resource "aws_db_proxy_default_target_group" "main" {
  db_proxy_name = aws_db_proxy.main.name

  connection_pool_config {
    connection_borrow_timeout    = 120
    init_query                  = ""
    max_connections_percent      = var.proxy_max_connections_percent
    max_idle_connections_percent = var.proxy_max_idle_connections_percent
    session_pinning_filters      = []
  }
}

# Add RDS instance as target
resource "aws_db_proxy_target" "main" {
  db_instance_identifier = aws_db_instance.main.id
  db_proxy_name          = aws_db_proxy.main.name
  target_group_name      = aws_db_proxy_default_target_group.main.name
}

#########################
# Lambda Test Function  #
#########################

# IAM role for Lambda function
resource "aws_iam_role" "lambda" {
  count = var.create_lambda_test_function ? 1 : 0
  name  = "${local.common_name}-lambda-role"

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

  tags = merge(var.common_tags, {
    Name = "${local.common_name}-lambda-role"
  })
}

# Attach AWS managed policy for Lambda VPC access
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  count      = var.create_lambda_test_function ? 1 : 0
  role       = aws_iam_role.lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Create Lambda function package
data "archive_file" "lambda_zip" {
  count       = var.create_lambda_test_function ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      proxy_endpoint = aws_db_proxy.main.endpoint
      db_username    = var.db_username
      db_password    = var.db_password
      db_name        = var.db_name
    })
    filename = "lambda_function.py"
  }
}

# Create Lambda function
resource "aws_lambda_function" "test" {
  count            = var.create_lambda_test_function ? 1 : 0
  filename         = data.archive_file.lambda_zip[0].output_path
  function_name    = "${local.common_name}-test-function"
  role            = aws_iam_role.lambda[0].arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.rds_proxy.id]
  }

  environment {
    variables = {
      PROXY_ENDPOINT = aws_db_proxy.main.endpoint
      DB_USER        = var.db_username
      DB_PASSWORD    = var.db_password
      DB_NAME        = var.db_name
    }
  }

  tags = merge(var.common_tags, {
    Name = "${local.common_name}-test-function"
  })

  depends_on = [
    aws_db_proxy_target.main,
    aws_iam_role_policy_attachment.lambda_vpc
  ]
}

# Create Lambda function code template
resource "local_file" "lambda_template" {
  count    = var.create_lambda_test_function ? 1 : 0
  filename = "${path.module}/lambda_function.py.tpl"
  content  = <<-EOT
import json
import pymysql
import os

def lambda_handler(event, context):
    try:
        # Connect to database through RDS Proxy
        connection = pymysql.connect(
            host=os.environ['PROXY_ENDPOINT'],
            user=os.environ['DB_USER'],
            password=os.environ['DB_PASSWORD'],
            database=os.environ['DB_NAME'],
            port=3306,
            cursorclass=pymysql.cursors.DictCursor
        )
        
        with connection.cursor() as cursor:
            # Execute a simple query
            cursor.execute("SELECT 1 as connection_test, CONNECTION_ID() as connection_id")
            result = cursor.fetchone()
            
        connection.close()
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Successfully connected through RDS Proxy',
                'result': result
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
EOT
}

#########################
# CloudWatch Log Groups #
#########################

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda" {
  count             = var.create_lambda_test_function ? 1 : 0
  name              = "/aws/lambda/${aws_lambda_function.test[0].function_name}"
  retention_in_days = 14

  tags = merge(var.common_tags, {
    Name = "${local.common_name}-lambda-logs"
  })
}