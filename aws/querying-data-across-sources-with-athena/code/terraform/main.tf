# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  suffix = random_id.suffix.hex
}

# S3 Buckets for Athena Spill and Results
resource "aws_s3_bucket" "athena_spill" {
  bucket        = "${var.project_name}-spill-${local.suffix}"
  force_destroy = var.force_destroy_s3_buckets

  tags = merge(var.common_tags, {
    Name = "Athena Spill Bucket"
  })
}

resource "aws_s3_bucket" "athena_results" {
  bucket        = "${var.project_name}-results-${local.suffix}"
  force_destroy = var.force_destroy_s3_buckets

  tags = merge(var.common_tags, {
    Name = "Athena Results Bucket"
  })
}

# S3 Bucket configurations for security and lifecycle
resource "aws_s3_bucket_server_side_encryption_configuration" "athena_spill" {
  bucket = aws_s3_bucket.athena_spill.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "athena_spill" {
  bucket = aws_s3_bucket.athena_spill.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "athena_spill" {
  bucket = aws_s3_bucket.athena_spill.id

  rule {
    id     = "cleanup_spill_data"
    status = "Enabled"

    expiration {
      days = 1
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}

# VPC and Networking for RDS
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-private-subnet-${count.index + 1}"
  })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS MySQL instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-rds-sg"
  })
}

# DB Subnet Group for RDS
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-db-subnet-group"
  })
}

# RDS MySQL Instance
resource "aws_db_instance" "mysql" {
  identifier           = "${var.project_name}-mysql-${local.suffix}"
  engine               = "mysql"
  engine_version       = var.rds_engine_version
  instance_class       = var.rds_instance_class
  allocated_storage    = var.rds_allocated_storage
  storage_type         = "gp2"
  storage_encrypted    = true
  
  db_name  = var.database_name
  username = var.rds_master_username
  password = var.rds_master_password

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  backup_retention_period = var.rds_backup_retention_period
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"

  skip_final_snapshot = true
  deletion_protection = false

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-mysql"
  })
}

# DynamoDB Table for Order Tracking
resource "aws_dynamodb_table" "orders" {
  name           = "${var.project_name}-orders-${local.suffix}"
  billing_mode   = "PROVISIONED"
  read_capacity  = var.dynamodb_read_capacity
  write_capacity = var.dynamodb_write_capacity
  hash_key       = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-orders"
  })
}

# Sample data for DynamoDB
resource "aws_dynamodb_table_item" "order_1001" {
  count      = var.create_sample_data ? 1 : 0
  table_name = aws_dynamodb_table.orders.name
  hash_key   = aws_dynamodb_table.orders.hash_key

  item = jsonencode({
    order_id = {
      S = "1001"
    }
    status = {
      S = "shipped"
    }
    tracking_number = {
      S = "TRK123456"
    }
    carrier = {
      S = "FedEx"
    }
  })
}

resource "aws_dynamodb_table_item" "order_1002" {
  count      = var.create_sample_data ? 1 : 0
  table_name = aws_dynamodb_table.orders.name
  hash_key   = aws_dynamodb_table.orders.hash_key

  item = jsonencode({
    order_id = {
      S = "1002"
    }
    status = {
      S = "processing"
    }
    tracking_number = {
      S = "TRK789012"
    }
    carrier = {
      S = "UPS"
    }
  })
}

resource "aws_dynamodb_table_item" "order_1003" {
  count      = var.create_sample_data ? 1 : 0
  table_name = aws_dynamodb_table.orders.name
  hash_key   = aws_dynamodb_table.orders.hash_key

  item = jsonencode({
    order_id = {
      S = "1003"
    }
    status = {
      S = "delivered"
    }
    tracking_number = {
      S = "TRK345678"
    }
    carrier = {
      S = "USPS"
    }
  })
}

# IAM Role for Lambda Functions
resource "aws_iam_role" "lambda_connector" {
  name = "${var.project_name}-lambda-connector-role"

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

  tags = var.common_tags
}

# IAM Policy for Lambda Functions
resource "aws_iam_role_policy" "lambda_connector" {
  name = "${var.project_name}-lambda-connector-policy"
  role = aws_iam_role.lambda_connector.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.athena_spill.arn,
          "${aws_s3_bucket.athena_spill.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:BatchGetItem"
        ]
        Resource = [
          aws_dynamodb_table.orders.arn,
          "${aws_dynamodb_table.orders.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters"
        ]
        Resource = "*"
      }
    ]
  })
}

# CloudFormation Stack for MySQL Connector
resource "aws_cloudformation_stack" "mysql_connector" {
  name = "${var.project_name}-mysql-connector"

  parameters = {
    LambdaFunctionName        = "${var.project_name}-mysql-connector"
    DefaultConnectionString   = "mysql://jdbc:mysql://${aws_db_instance.mysql.endpoint}:${aws_db_instance.mysql.port}/${aws_db_instance.mysql.db_name}?user=${aws_db_instance.mysql.username}&password=${aws_db_instance.mysql.password}"
    SpillBucket              = aws_s3_bucket.athena_spill.id
    LambdaMemory             = var.lambda_memory_size
    LambdaTimeout            = var.lambda_timeout
    SecurityGroupIds         = aws_security_group.rds.id
    SubnetIds                = join(",", aws_subnet.private[*].id)
  }

  template_url = "https://s3.amazonaws.com/athena-downloads/drivers/JDBC/SimbaAthenaJDBC-2.0.32.1000/AthenaMySQLConnector.yaml"

  capabilities = ["CAPABILITY_IAM"]

  tags = var.common_tags

  depends_on = [
    aws_db_instance.mysql,
    aws_s3_bucket.athena_spill
  ]
}

# CloudFormation Stack for DynamoDB Connector
resource "aws_cloudformation_stack" "dynamodb_connector" {
  name = "${var.project_name}-dynamodb-connector"

  parameters = {
    LambdaFunctionName = "${var.project_name}-dynamodb-connector"
    SpillBucket        = aws_s3_bucket.athena_spill.id
    LambdaMemory       = var.lambda_memory_size
    LambdaTimeout      = var.lambda_timeout
  }

  template_url = "https://s3.amazonaws.com/athena-downloads/drivers/JDBC/SimbaAthenaJDBC-2.0.32.1000/AthenaDynamoDBConnector.yaml"

  capabilities = ["CAPABILITY_IAM"]

  tags = var.common_tags

  depends_on = [
    aws_dynamodb_table.orders,
    aws_s3_bucket.athena_spill
  ]
}

# Athena Data Catalog for MySQL
resource "aws_athena_data_catalog" "mysql" {
  name        = "mysql_catalog"
  description = "MySQL data source for federated queries"
  type        = "LAMBDA"

  parameters = {
    function = "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-mysql-connector"
  }

  depends_on = [aws_cloudformation_stack.mysql_connector]

  tags = var.common_tags
}

# Athena Data Catalog for DynamoDB
resource "aws_athena_data_catalog" "dynamodb" {
  name        = "dynamodb_catalog"
  description = "DynamoDB data source for federated queries"
  type        = "LAMBDA"

  parameters = {
    function = "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-dynamodb-connector"
  }

  depends_on = [aws_cloudformation_stack.dynamodb_connector]

  tags = var.common_tags
}

# Athena Workgroup for Federated Queries
resource "aws_athena_workgroup" "federated_analytics" {
  name = var.athena_workgroup_name

  configuration {
    enforce_workgroup_configuration = var.athena_enforce_workgroup_config
    publish_cloudwatch_metrics      = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = merge(var.common_tags, {
    Name = var.athena_workgroup_name
  })
}

# Lambda function for creating sample data in RDS
resource "aws_lambda_function" "rds_sample_data" {
  count            = var.create_sample_data ? 1 : 0
  filename         = "${path.module}/rds_sample_data.zip"
  function_name    = "${var.project_name}-rds-sample-data"
  role            = aws_iam_role.lambda_connector.arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 60

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.rds.id]
  }

  environment {
    variables = {
      RDS_ENDPOINT = aws_db_instance.mysql.endpoint
      RDS_PORT     = aws_db_instance.mysql.port
      DB_NAME      = aws_db_instance.mysql.db_name
      DB_USER      = aws_db_instance.mysql.username
      DB_PASSWORD  = aws_db_instance.mysql.password
      TABLE_NAME   = var.sample_orders_table
    }
  }

  depends_on = [
    aws_db_instance.mysql,
    data.archive_file.rds_sample_data
  ]

  tags = var.common_tags
}

# Archive file for RDS sample data Lambda function
data "archive_file" "rds_sample_data" {
  count       = var.create_sample_data ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/rds_sample_data.zip"
  
  source {
    content = <<EOF
import json
import pymysql
import os

def handler(event, context):
    try:
        # Connect to RDS MySQL
        connection = pymysql.connect(
            host=os.environ['RDS_ENDPOINT'],
            port=int(os.environ['RDS_PORT']),
            user=os.environ['DB_USER'],
            password=os.environ['DB_PASSWORD'],
            database=os.environ['DB_NAME']
        )
        
        with connection.cursor() as cursor:
            # Create sample table
            create_table_sql = f"""
            CREATE TABLE IF NOT EXISTS {os.environ['TABLE_NAME']} (
                order_id INT PRIMARY KEY,
                customer_id INT,
                product_name VARCHAR(255),
                quantity INT,
                price DECIMAL(10,2),
                order_date DATE
            )
            """
            cursor.execute(create_table_sql)
            
            # Insert sample data
            sample_data = [
                (1, 101, "Laptop", 1, 999.99, "2024-01-15"),
                (2, 102, "Mouse", 2, 29.99, "2024-01-16"),
                (3, 103, "Keyboard", 1, 79.99, "2024-01-17"),
                (4, 101, "Monitor", 1, 299.99, "2024-01-18"),
                (5, 104, "Headphones", 3, 149.99, "2024-01-19")
            ]
            
            insert_sql = f"""
            INSERT IGNORE INTO {os.environ['TABLE_NAME']} 
            (order_id, customer_id, product_name, quantity, price, order_date) 
            VALUES (%s, %s, %s, %s, %s, %s)
            """
            
            cursor.executemany(insert_sql, sample_data)
            connection.commit()
        
        connection.close()
        
        return {
            'statusCode': 200,
            'body': json.dumps('Sample data created successfully')
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
EOF
    filename = "index.py"
  }
}

# Lambda function invocation to create sample data
resource "aws_lambda_invocation" "rds_sample_data" {
  count         = var.create_sample_data ? 1 : 0
  function_name = aws_lambda_function.rds_sample_data[0].function_name
  
  input = jsonencode({
    action = "create_sample_data"
  })

  depends_on = [aws_lambda_function.rds_sample_data]
}