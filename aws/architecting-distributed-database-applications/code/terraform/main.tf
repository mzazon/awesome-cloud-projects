# main.tf - Multi-Region Distributed Applications with Aurora DSQL
# This configuration deploys Aurora DSQL clusters, Lambda functions, and EventBridge
# across multiple regions to create a highly available distributed application

# ----- Local Values -----

locals {
  # Generate unique suffix for resource names
  name_suffix = random_id.suffix.hex
  
  # Common resource naming
  cluster_name_primary   = "${var.project_name}-primary-${local.name_suffix}"
  cluster_name_secondary = "${var.project_name}-secondary-${local.name_suffix}"
  lambda_function_name   = "${var.project_name}-processor-${local.name_suffix}"
  eventbridge_bus_name   = coalesce(var.eventbridge_bus_name, "${var.project_name}-events-${local.name_suffix}")
  
  # IAM role names
  lambda_role_name = "${var.project_name}-lambda-role-${local.name_suffix}"
  
  # Tags for all resources
  resource_tags = merge(var.common_tags, {
    Environment   = var.environment
    CreatedBy     = "Terraform"
    Recipe        = "aurora-dsql-multiregion"
    LastUpdated   = timestamp()
  })
}

# ----- Random ID Generation -----

resource "random_id" "suffix" {
  byte_length = 4
  
  keepers = {
    project_name = var.project_name
    environment  = var.environment
  }
}

# ----- Aurora DSQL Clusters -----

# Primary Aurora DSQL cluster
resource "aws_dsql_cluster" "primary" {
  provider = aws.primary
  
  # Cluster configuration
  deletion_protection_enabled = var.deletion_protection_enabled
  
  # Multi-region properties for distributed architecture
  multi_region_properties {
    witness_region = var.witness_region
  }
  
  # Resource tagging
  tags = merge(local.resource_tags, {
    Name     = local.cluster_name_primary
    Role     = "Primary"
    Region   = var.primary_region
    Database = var.database_name
  })
  
  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      # Ignore timestamp changes in tags
      tags["LastUpdated"]
    ]
  }
}

# Secondary Aurora DSQL cluster
resource "aws_dsql_cluster" "secondary" {
  provider = aws.secondary
  
  # Cluster configuration
  deletion_protection_enabled = var.deletion_protection_enabled
  
  # Multi-region properties for distributed architecture
  multi_region_properties {
    witness_region = var.witness_region
  }
  
  # Resource tagging
  tags = merge(local.resource_tags, {
    Name     = local.cluster_name_secondary
    Role     = "Secondary"
    Region   = var.secondary_region
    Database = var.database_name
  })
  
  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      tags["LastUpdated"]
    ]
  }
}

# Multi-region cluster peering - Primary to Secondary
resource "aws_dsql_cluster_peering" "primary_to_secondary" {
  provider = aws.primary
  
  identifier     = aws_dsql_cluster.primary.identifier
  clusters       = [aws_dsql_cluster.secondary.arn]
  witness_region = var.witness_region
  
  depends_on = [
    aws_dsql_cluster.primary,
    aws_dsql_cluster.secondary
  ]
}

# Multi-region cluster peering - Secondary to Primary
resource "aws_dsql_cluster_peering" "secondary_to_primary" {
  provider = aws.secondary
  
  identifier     = aws_dsql_cluster.secondary.identifier
  clusters       = [aws_dsql_cluster.primary.arn]
  witness_region = var.witness_region
  
  depends_on = [
    aws_dsql_cluster.primary,
    aws_dsql_cluster.secondary,
    aws_dsql_cluster_peering.primary_to_secondary
  ]
}

# ----- IAM Role for Lambda Functions -----

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}

# Lambda execution role
resource "aws_iam_role" "lambda_role" {
  provider = aws.primary
  
  name        = local.lambda_role_name
  description = "IAM role for Aurora DSQL Lambda functions with multi-region access"
  
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
  
  tags = merge(local.resource_tags, {
    Name = local.lambda_role_name
    Type = "IAM Role"
  })
}

# Basic Lambda execution policy attachment
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  provider = aws.primary
  
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# X-Ray tracing policy (conditional)
resource "aws_iam_role_policy_attachment" "lambda_xray_tracing" {
  count    = var.enable_x_ray_tracing ? 1 : 0
  provider = aws.primary
  
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# VPC access policy (conditional)
resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  count    = var.lambda_vpc_config != null ? 1 : 0
  provider = aws.primary
  
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Custom policy for Aurora DSQL and EventBridge access
resource "aws_iam_policy" "lambda_dsql_eventbridge_policy" {
  provider = aws.primary
  
  name        = "${var.project_name}-lambda-dsql-policy-${local.name_suffix}"
  description = "Custom policy for Lambda functions to access Aurora DSQL and EventBridge"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dsql:Connect",
          "dsql:DbConnect",
          "dsql:ExecuteStatement",
          "dsql:BatchExecuteStatement",
          "dsql:BeginTransaction",
          "dsql:CommitTransaction",
          "dsql:RollbackTransaction"
        ]
        Resource = [
          aws_dsql_cluster.primary.arn,
          aws_dsql_cluster.secondary.arn,
          "${aws_dsql_cluster.primary.arn}/*",
          "${aws_dsql_cluster.secondary.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents"
        ]
        Resource = [
          "arn:aws:events:${var.primary_region}:${data.aws_caller_identity.current.account_id}:event-bus/${local.eventbridge_bus_name}",
          "arn:aws:events:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:event-bus/${local.eventbridge_bus_name}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${var.primary_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*",
          "arn:aws:logs:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*"
        ]
      }
    ]
  })
  
  tags = merge(local.resource_tags, {
    Name = "${var.project_name}-lambda-policy"
    Type = "IAM Policy"
  })
}

# Attach custom policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_custom_policy" {
  provider = aws.primary
  
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dsql_eventbridge_policy.arn
}

# ----- Lambda Function Package -----

# Lambda function source code
resource "local_file" "lambda_function_code" {
  filename = "${path.module}/lambda_function.py"
  content  = <<-EOF
import json
import boto3
import os
import logging
from datetime import datetime
import uuid
import psycopg2
from psycopg2.extras import RealDictCursor

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
eventbridge = boto3.client('events')

def lambda_handler(event, context):
    """
    Aurora DSQL processor Lambda function
    Handles database operations and publishes events to EventBridge
    """
    try:
        # Get environment variables
        cluster_endpoint = os.environ.get('DSQL_CLUSTER_ENDPOINT')
        database_name = os.environ.get('DSQL_DATABASE_NAME', 'distributed_app')
        eventbridge_bus_name = os.environ.get('EVENTBRIDGE_BUS_NAME')
        current_region = context.invoked_function_arn.split(':')[3]
        
        logger.info(f"Processing request in region: {current_region}")
        logger.info(f"Event: {json.dumps(event)}")
        
        # Parse the incoming event
        operation = event.get('operation', 'read')
        
        # Establish database connection using Aurora DSQL PostgreSQL endpoint
        conn_params = {
            'host': cluster_endpoint,
            'database': database_name,
            'port': 5432,
            'connect_timeout': 10
        }
        
        # Note: In production, use IAM authentication or AWS Secrets Manager
        # For this demo, Aurora DSQL handles authentication automatically
        
        with psycopg2.connect(**conn_params) as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                
                if operation == 'write':
                    return handle_write_operation(cur, event, eventbridge_bus_name, current_region)
                elif operation == 'read':
                    return handle_read_operation(cur, current_region)
                elif operation == 'init':
                    return handle_init_operation(cur, current_region)
                else:
                    return {
                        'statusCode': 400,
                        'body': json.dumps({
                            'error': 'Invalid operation',
                            'valid_operations': ['read', 'write', 'init']
                        })
                    }
    
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'region': context.invoked_function_arn.split(':')[3]
            })
        }

def handle_write_operation(cursor, event, eventbridge_bus_name, current_region):
    """Handle write operations to Aurora DSQL"""
    
    # Extract transaction details
    transaction_id = event.get('transaction_id', str(uuid.uuid4()))
    amount = event.get('amount', 0.0)
    description = event.get('description', 'Sample transaction')
    
    # Insert transaction into database
    insert_query = """
        INSERT INTO transactions (id, amount, description, timestamp, region, status)
        VALUES (%s, %s, %s, %s, %s, %s)
        RETURNING *
    """
    
    cursor.execute(insert_query, (
        transaction_id,
        float(amount),
        description,
        datetime.now().isoformat(),
        current_region,
        'completed'
    ))
    
    new_transaction = cursor.fetchone()
    
    # Publish event to EventBridge for cross-region coordination
    if eventbridge_bus_name:
        event_detail = {
            'transaction_id': transaction_id,
            'amount': float(amount),
            'description': description,
            'region': current_region,
            'timestamp': datetime.now().isoformat(),
            'operation': 'transaction_created'
        }
        
        eventbridge.put_events(
            Entries=[
                {
                    'Source': 'aurora.dsql.application',
                    'DetailType': 'Transaction Created',
                    'Detail': json.dumps(event_detail),
                    'EventBusName': eventbridge_bus_name
                }
            ]
        )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Transaction created successfully',
            'transaction': dict(new_transaction),
            'region': current_region
        }, default=str)
    }

def handle_read_operation(cursor, current_region):
    """Handle read operations from Aurora DSQL"""
    
    # Get transaction count and recent transactions
    count_query = "SELECT COUNT(*) as total_count FROM transactions"
    cursor.execute(count_query)
    count_result = cursor.fetchone()
    
    # Get recent transactions
    recent_query = """
        SELECT id, amount, description, timestamp, region, status
        FROM transactions
        ORDER BY timestamp DESC
        LIMIT 10
    """
    cursor.execute(recent_query)
    recent_transactions = cursor.fetchall()
    
    # Get regional statistics
    regional_query = """
        SELECT region, COUNT(*) as count, SUM(amount) as total_amount
        FROM transactions
        GROUP BY region
        ORDER BY count DESC
    """
    cursor.execute(regional_query)
    regional_stats = cursor.fetchall()
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'total_transactions': count_result['total_count'],
            'recent_transactions': [dict(row) for row in recent_transactions],
            'regional_statistics': [dict(row) for row in regional_stats],
            'current_region': current_region,
            'timestamp': datetime.now().isoformat()
        }, default=str)
    }

def handle_init_operation(cursor, current_region):
    """Initialize database schema"""
    
    try:
        # Create transactions table if it doesn't exist
        create_table_query = """
            CREATE TABLE IF NOT EXISTS transactions (
                id VARCHAR(255) PRIMARY KEY,
                amount DECIMAL(10,2) NOT NULL,
                description TEXT,
                timestamp TIMESTAMP NOT NULL,
                region VARCHAR(50) NOT NULL,
                status VARCHAR(50) DEFAULT 'pending'
            )
        """
        cursor.execute(create_table_query)
        
        # Create indexes for performance
        create_index_queries = [
            "CREATE INDEX IF NOT EXISTS idx_transactions_timestamp ON transactions(timestamp)",
            "CREATE INDEX IF NOT EXISTS idx_transactions_region ON transactions(region)",
            "CREATE INDEX IF NOT EXISTS idx_transactions_status ON transactions(status)"
        ]
        
        for query in create_index_queries:
            cursor.execute(query)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Database schema initialized successfully',
                'region': current_region,
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'Failed to initialize schema: {str(e)}',
                'region': current_region
            })
        }
EOF
}

# Create Lambda deployment package
data "archive_file" "lambda_package" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content  = local_file.lambda_function_code.content
    filename = "lambda_function.py"
  }
  
  depends_on = [local_file.lambda_function_code]
}

# ----- CloudWatch Log Groups -----

# Log group for primary region Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs_primary" {
  count    = var.enable_cloudwatch_logs ? 1 : 0
  provider = aws.primary
  
  name              = "/aws/lambda/${local.lambda_function_name}-primary"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.resource_tags, {
    Name   = "${local.lambda_function_name}-primary-logs"
    Region = var.primary_region
  })
}

# Log group for secondary region Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs_secondary" {
  count    = var.enable_cloudwatch_logs ? 1 : 0
  provider = aws.secondary
  
  name              = "/aws/lambda/${local.lambda_function_name}-secondary"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.resource_tags, {
    Name   = "${local.lambda_function_name}-secondary-logs"
    Region = var.secondary_region
  })
}

# ----- Lambda Functions -----

# Primary region Lambda function
resource "aws_lambda_function" "primary" {
  provider = aws.primary
  
  function_name = "${local.lambda_function_name}-primary"
  description   = "Aurora DSQL processor function in primary region (${var.primary_region})"
  
  # Function configuration
  runtime          = var.lambda_runtime
  handler          = "lambda_function.lambda_handler"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
  
  # Function package
  filename = data.archive_file.lambda_package.output_path
  
  # IAM role
  role = aws_iam_role.lambda_role.arn
  
  # Environment variables
  environment {
    variables = {
      DSQL_CLUSTER_ENDPOINT  = aws_dsql_cluster.primary.endpoint
      DSQL_DATABASE_NAME     = var.database_name
      EVENTBRIDGE_BUS_NAME   = local.eventbridge_bus_name
      REGION                 = var.primary_region
      CLUSTER_IDENTIFIER     = aws_dsql_cluster.primary.identifier
    }
  }
  
  # VPC configuration (optional)
  dynamic "vpc_config" {
    for_each = var.lambda_vpc_config != null ? [var.lambda_vpc_config] : []
    content {
      subnet_ids         = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }
  
  # X-Ray tracing configuration
  tracing_config {
    mode = var.enable_x_ray_tracing ? "Active" : "PassThrough"
  }
  
  # Resource tags
  tags = merge(local.resource_tags, {
    Name   = "${local.lambda_function_name}-primary"
    Region = var.primary_region
    Role   = "Primary"
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_custom_policy,
    aws_cloudwatch_log_group.lambda_logs_primary,
    aws_dsql_cluster.primary
  ]
}

# Secondary region Lambda function
resource "aws_lambda_function" "secondary" {
  provider = aws.secondary
  
  function_name = "${local.lambda_function_name}-secondary"
  description   = "Aurora DSQL processor function in secondary region (${var.secondary_region})"
  
  # Function configuration
  runtime          = var.lambda_runtime
  handler          = "lambda_function.lambda_handler"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
  
  # Function package
  filename = data.archive_file.lambda_package.output_path
  
  # IAM role (cross-region reference)
  role = aws_iam_role.lambda_role.arn
  
  # Environment variables
  environment {
    variables = {
      DSQL_CLUSTER_ENDPOINT  = aws_dsql_cluster.secondary.endpoint
      DSQL_DATABASE_NAME     = var.database_name
      EVENTBRIDGE_BUS_NAME   = local.eventbridge_bus_name
      REGION                 = var.secondary_region
      CLUSTER_IDENTIFIER     = aws_dsql_cluster.secondary.identifier
    }
  }
  
  # VPC configuration (optional)
  dynamic "vpc_config" {
    for_each = var.lambda_vpc_config != null ? [var.lambda_vpc_config] : []
    content {
      subnet_ids         = vpc_config.value.subnet_ids
      security_group_ids = vpc_config.value.security_group_ids
    }
  }
  
  # X-Ray tracing configuration
  tracing_config {
    mode = var.enable_x_ray_tracing ? "Active" : "PassThrough"
  }
  
  # Resource tags
  tags = merge(local.resource_tags, {
    Name   = "${local.lambda_function_name}-secondary"
    Region = var.secondary_region
    Role   = "Secondary"
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_custom_policy,
    aws_cloudwatch_log_group.lambda_logs_secondary,
    aws_dsql_cluster.secondary
  ]
}

# ----- EventBridge Configuration -----

# Custom EventBridge bus in primary region
resource "aws_cloudwatch_event_bus" "primary" {
  provider = aws.primary
  
  name = local.eventbridge_bus_name
  
  tags = merge(local.resource_tags, {
    Name   = local.eventbridge_bus_name
    Region = var.primary_region
    Role   = "Primary"
  })
}

# Custom EventBridge bus in secondary region
resource "aws_cloudwatch_event_bus" "secondary" {
  provider = aws.secondary
  
  name = local.eventbridge_bus_name
  
  tags = merge(local.resource_tags, {
    Name   = local.eventbridge_bus_name
    Region = var.secondary_region
    Role   = "Secondary"
  })
}

# EventBridge rule for transaction events in primary region
resource "aws_cloudwatch_event_rule" "transaction_events_primary" {
  provider = aws.primary
  
  name           = "aurora-dsql-transaction-events"
  description    = "Captures Aurora DSQL transaction events"
  event_bus_name = aws_cloudwatch_event_bus.primary.name
  
  event_pattern = jsonencode({
    source      = ["aurora.dsql.application"]
    detail-type = ["Transaction Created"]
  })
  
  tags = merge(local.resource_tags, {
    Name   = "transaction-events-primary"
    Region = var.primary_region
  })
}

# EventBridge rule for transaction events in secondary region
resource "aws_cloudwatch_event_rule" "transaction_events_secondary" {
  provider = aws.secondary
  
  name           = "aurora-dsql-transaction-events"
  description    = "Captures Aurora DSQL transaction events"
  event_bus_name = aws_cloudwatch_event_bus.secondary.name
  
  event_pattern = jsonencode({
    source      = ["aurora.dsql.application"]
    detail-type = ["Transaction Created"]
  })
  
  tags = merge(local.resource_tags, {
    Name   = "transaction-events-secondary"
    Region = var.secondary_region
  })
}

# EventBridge targets for cross-region coordination
resource "aws_cloudwatch_event_target" "lambda_target_primary" {
  provider = aws.primary
  
  rule           = aws_cloudwatch_event_rule.transaction_events_primary.name
  event_bus_name = aws_cloudwatch_event_bus.primary.name
  target_id      = "LambdaTarget"
  arn            = aws_lambda_function.primary.arn
}

resource "aws_cloudwatch_event_target" "lambda_target_secondary" {
  provider = aws.secondary
  
  rule           = aws_cloudwatch_event_rule.transaction_events_secondary.name
  event_bus_name = aws_cloudwatch_event_bus.secondary.name
  target_id      = "LambdaTarget"
  arn            = aws_lambda_function.secondary.arn
}

# Lambda permissions for EventBridge invocation
resource "aws_lambda_permission" "allow_eventbridge_primary" {
  provider = aws.primary
  
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.primary.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.transaction_events_primary.arn
}

resource "aws_lambda_permission" "allow_eventbridge_secondary" {
  provider = aws.secondary
  
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.secondary.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.transaction_events_secondary.arn
}

# ----- Database Initialization -----

# Lambda invocation to initialize database schema in primary region
resource "aws_lambda_invocation" "init_schema_primary" {
  count = var.create_sample_schema ? 1 : 0
  provider = aws.primary
  
  function_name = aws_lambda_function.primary.function_name
  
  input = jsonencode({
    operation = "init"
  })
  
  depends_on = [
    aws_dsql_cluster_peering.primary_to_secondary,
    aws_dsql_cluster_peering.secondary_to_primary
  ]
}

# Lambda invocation to initialize database schema in secondary region
resource "aws_lambda_invocation" "init_schema_secondary" {
  count = var.create_sample_schema ? 1 : 0
  provider = aws.secondary
  
  function_name = aws_lambda_function.secondary.function_name
  
  input = jsonencode({
    operation = "init"
  })
  
  depends_on = [
    aws_lambda_invocation.init_schema_primary,
    aws_dsql_cluster_peering.secondary_to_primary
  ]
}