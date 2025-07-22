# Main Terraform configuration for QuickSight Business Intelligence Dashboard

# Data sources for existing AWS resources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  suffix     = random_id.suffix.hex
  
  # Resource naming with random suffix
  s3_bucket_name = "${var.project_name}-data-${local.suffix}"
  rds_identifier = "${var.project_name}-db-${local.suffix}"
  
  common_tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

# Generate random password for RDS
resource "random_password" "rds_password" {
  length  = 16
  special = true
}

# Store RDS password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "rds_password" {
  name                    = "${var.project_name}-rds-password-${local.suffix}"
  description             = "RDS password for QuickSight demo database"
  recovery_window_in_days = 7

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "rds_password" {
  secret_id = aws_secretsmanager_secret.rds_password.id
  secret_string = jsonencode({
    username = var.rds_username
    password = random_password.rds_password.result
  })
}

# S3 bucket for sample data storage
resource "aws_s3_bucket" "quicksight_data" {
  bucket        = local.s3_bucket_name
  force_destroy = var.s3_force_destroy

  tags = merge(local.common_tags, {
    Name = "QuickSight Data Bucket"
    Purpose = "Data source for QuickSight analytics"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "quicksight_data" {
  bucket = aws_s3_bucket.quicksight_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "quicksight_data" {
  bucket = aws_s3_bucket.quicksight_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "quicksight_data" {
  bucket = aws_s3_bucket.quicksight_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload sample sales data if enabled
resource "aws_s3_object" "sample_sales_data" {
  count  = var.create_sample_data ? 1 : 0
  bucket = aws_s3_bucket.quicksight_data.id
  key    = "data/sales_data.csv"
  
  content = <<-EOT
date,region,product,sales_amount,quantity
2024-01-01,North,Widget A,1200,10
2024-01-01,South,Widget B,800,8
2024-01-02,North,Widget A,1400,12
2024-01-02,South,Widget B,900,9
2024-01-03,East,Widget C,1100,11
2024-01-03,West,Widget A,1300,13
2024-01-04,North,Widget B,1600,16
2024-01-04,South,Widget C,1000,10
2024-01-05,East,Widget A,1500,15
2024-01-05,West,Widget B,1100,11
2024-01-06,North,Widget C,1700,17
2024-01-06,South,Widget A,1200,12
2024-01-07,East,Widget B,1400,14
2024-01-07,West,Widget C,1600,16
2024-01-08,North,Widget A,1800,18
2024-01-08,South,Widget B,1300,13
2024-01-09,East,Widget C,1500,15
2024-01-09,West,Widget A,1700,17
2024-01-10,North,Widget B,1900,19
2024-01-10,South,Widget C,1400,14
EOT

  content_type = "text/csv"
  
  tags = merge(local.common_tags, {
    Name = "Sample Sales Data"
    DataType = "CSV"
  })
}

# IAM role for QuickSight to access AWS resources
resource "aws_iam_role" "quicksight_service_role" {
  name = "QuickSight-ServiceRole-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "quicksight.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "QuickSight Service Role"
    Purpose = "Allow QuickSight to access AWS resources"
  })
}

# IAM policy for QuickSight S3 access
resource "aws_iam_role_policy" "quicksight_s3_policy" {
  name = "QuickSight-S3-Policy"
  role = aws_iam_role.quicksight_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:ListBucketVersions"
        ]
        Resource = [
          aws_s3_bucket.quicksight_data.arn,
          "${aws_s3_bucket.quicksight_data.arn}/*"
        ]
      }
    ]
  })
}

# VPC for RDS instance
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "QuickSight Demo VPC"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "QuickSight Demo IGW"
  })
}

# Public subnets for RDS (in different AZs for Multi-AZ support)
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "QuickSight Demo Public Subnet 1"
  })
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "QuickSight Demo Public Subnet 2"
  })
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Route table for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "QuickSight Demo Public Route Table"
  })
}

# Route table associations
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# Security group for RDS
resource "aws_security_group" "rds" {
  name_prefix = "quicksight-rds-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for QuickSight RDS instance"

  ingress {
    description = "PostgreSQL access"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Allow QuickSight service access
  ingress {
    description = "QuickSight service access"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["52.23.63.224/27", "52.23.63.0/27"] # QuickSight service IPs for us-east-1
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "QuickSight RDS Security Group"
  })
}

# DB subnet group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group-${local.suffix}"
  subnet_ids = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = merge(local.common_tags, {
    Name = "QuickSight DB Subnet Group"
  })
}

# RDS PostgreSQL instance
resource "aws_db_instance" "postgresql" {
  identifier             = local.rds_identifier
  allocated_storage      = var.rds_allocated_storage
  storage_type          = "gp2"
  engine                = "postgres"
  engine_version        = var.rds_engine_version
  instance_class        = var.rds_instance_class
  db_name               = var.rds_db_name
  username              = var.rds_username
  password              = random_password.rds_password.result
  
  # Network and security
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name
  publicly_accessible    = true # For demo purposes; set to false in production
  
  # Backup and maintenance
  backup_retention_period = var.backup_retention_period
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  # High availability and monitoring
  multi_az               = var.enable_multi_az
  monitoring_interval    = 60
  monitoring_role_arn    = aws_iam_role.rds_monitoring.arn
  
  # Security and compliance
  storage_encrypted      = true
  deletion_protection    = var.enable_deletion_protection
  skip_final_snapshot    = true # For demo purposes; set to false in production
  
  # Performance
  performance_insights_enabled = true
  performance_insights_retention_period = 7

  tags = merge(local.common_tags, {
    Name = "QuickSight Demo PostgreSQL DB"
    Engine = "PostgreSQL"
  })

  depends_on = [aws_iam_role.rds_monitoring]
}

# IAM role for RDS enhanced monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "rds-monitoring-role-${local.suffix}"

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

  tags = merge(local.common_tags, {
    Name = "RDS Monitoring Role"
  })
}

# Attach the AWS managed policy for RDS monitoring
resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# QuickSight data source for S3
resource "aws_quicksight_data_source" "s3_source" {
  data_source_id = "s3-sales-data-${local.suffix}"
  name           = "Sales Data S3 Source"
  type           = "S3"
  
  parameters {
    s3 {
      manifest_file_location {
        bucket = aws_s3_bucket.quicksight_data.bucket
        key    = var.create_sample_data ? aws_s3_object.sample_sales_data[0].key : "data/sales_data.csv"
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "QuickSight S3 Data Source"
    DataSourceType = "S3"
  })

  depends_on = [aws_s3_object.sample_sales_data]
}

# QuickSight data source for RDS PostgreSQL
resource "aws_quicksight_data_source" "rds_source" {
  data_source_id = "rds-postgresql-${local.suffix}"
  name           = "PostgreSQL Database Source"
  type           = "POSTGRESQL"
  
  parameters {
    rds {
      instance_id = aws_db_instance.postgresql.id
      database    = var.rds_db_name
    }
  }

  credentials {
    credential_pair {
      username = var.rds_username
      password = random_password.rds_password.result
    }
  }

  vpc_connection_properties {
    vpc_connection_arn = aws_quicksight_vpc_connection.rds_connection.arn
  }

  tags = merge(local.common_tags, {
    Name = "QuickSight RDS Data Source"
    DataSourceType = "PostgreSQL"
  })

  depends_on = [aws_db_instance.postgresql, aws_quicksight_vpc_connection.rds_connection]
}

# VPC connection for QuickSight to access RDS
resource "aws_quicksight_vpc_connection" "rds_connection" {
  vpc_connection_id = "rds-vpc-connection-${local.suffix}"
  name              = "RDS VPC Connection"
  role_arn          = aws_iam_role.quicksight_vpc_role.arn
  security_group_ids = [aws_security_group.rds.id]
  subnet_ids        = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = merge(local.common_tags, {
    Name = "QuickSight VPC Connection"
  })
}

# IAM role for QuickSight VPC connection
resource "aws_iam_role" "quicksight_vpc_role" {
  name = "QuickSight-VPC-Role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "quicksight.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "QuickSight VPC Connection Role"
  })
}

# IAM policy for QuickSight VPC access
resource "aws_iam_role_policy" "quicksight_vpc_policy" {
  name = "QuickSight-VPC-Policy"
  role = aws_iam_role.quicksight_vpc_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# QuickSight dataset for S3 data
resource "aws_quicksight_data_set" "sales_dataset" {
  data_set_id = "sales-dataset-${local.suffix}"
  name        = "Sales Dataset"
  import_mode = "SPICE"

  physical_table_map {
    physical_table_id = "SalesTable"
    s3_source {
      data_source_arn = aws_quicksight_data_source.s3_source.arn
      upload_settings {
        format                = "CSV"
        start_from_row        = 1
        contains_header       = true
        delimiter             = ","
        text_qualifier        = "DOUBLE_QUOTE"
      }
      input_columns {
        name = "date"
        type = "DATETIME"
      }
      input_columns {
        name = "region"
        type = "STRING"
      }
      input_columns {
        name = "product"
        type = "STRING"
      }
      input_columns {
        name = "sales_amount"
        type = "DECIMAL"
      }
      input_columns {
        name = "quantity"
        type = "INTEGER"
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "QuickSight Sales Dataset"
    DataSource = "S3"
  })

  depends_on = [aws_quicksight_data_source.s3_source]
}

# Output key information for reference
output "s3_bucket_name" {
  description = "Name of the S3 bucket containing sample data"
  value       = aws_s3_bucket.quicksight_data.bucket
}

output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.postgresql.endpoint
  sensitive   = true
}

output "rds_database_name" {
  description = "RDS database name"
  value       = aws_db_instance.postgresql.db_name
}

output "quicksight_s3_data_source_id" {
  description = "QuickSight S3 data source ID"
  value       = aws_quicksight_data_source.s3_source.data_source_id
}

output "quicksight_rds_data_source_id" {
  description = "QuickSight RDS data source ID"
  value       = aws_quicksight_data_source.rds_source.data_source_id
}

output "quicksight_dataset_id" {
  description = "QuickSight dataset ID"
  value       = aws_quicksight_data_set.sales_dataset.data_set_id
}

output "secrets_manager_secret_name" {
  description = "Name of the Secrets Manager secret containing RDS credentials"
  value       = aws_secretsmanager_secret.rds_password.name
}