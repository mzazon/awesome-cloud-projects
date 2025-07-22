# Main Terraform configuration for Redshift Spectrum operational analytics

# Get current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get default VPC if not specified
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

# Get subnets for the VPC
data "aws_subnets" "available" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for computed configurations
locals {
  # Resource naming
  resource_suffix         = random_id.suffix.hex
  s3_bucket_name         = var.s3_bucket_name != "" ? var.s3_bucket_name : "${var.project_name}-data-lake-${local.resource_suffix}"
  redshift_cluster_id    = var.redshift_cluster_identifier != "" ? var.redshift_cluster_identifier : "${var.project_name}-cluster-${local.resource_suffix}"
  glue_database_name     = var.glue_database_name != "" ? var.glue_database_name : "${var.project_name}_db_${local.resource_suffix}"
  
  # Network configuration
  vpc_id     = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.available.ids
  
  # Tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
}

# Generate secure password for Redshift if not provided
resource "random_password" "redshift_password" {
  count   = var.redshift_master_password == "" ? 1 : 0
  length  = 16
  special = true
}

# S3 bucket for data lake storage
resource "aws_s3_bucket" "data_lake" {
  bucket = local.s3_bucket_name

  tags = merge(local.common_tags, {
    Name        = "Data Lake Bucket"
    Purpose     = "Redshift Spectrum data storage"
    DataClass   = "operational-analytics"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "data_lake_versioning" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake_encryption" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "data_lake_pab" {
  bucket = aws_s3_bucket.data_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Sample operational data objects
resource "aws_s3_object" "sales_transactions" {
  count  = var.create_sample_data ? 1 : 0
  bucket = aws_s3_bucket.data_lake.id
  key    = "${var.sample_data_prefix}/sales/year=2024/month=01/sales_transactions.csv"
  content = csvdecode(<<EOF
transaction_id,customer_id,product_id,quantity,unit_price,transaction_date,store_id,region,payment_method
TXN001,CUST001,PROD001,2,29.99,2024-01-15,STORE001,North,credit_card
TXN002,CUST002,PROD002,1,199.99,2024-01-15,STORE002,South,debit_card
TXN003,CUST003,PROD003,3,15.50,2024-01-16,STORE001,North,cash
TXN004,CUST001,PROD004,1,89.99,2024-01-16,STORE003,East,credit_card
TXN005,CUST004,PROD001,2,29.99,2024-01-17,STORE002,South,credit_card
TXN006,CUST002,PROD003,4,15.50,2024-01-17,STORE001,North,debit_card
TXN007,CUST005,PROD002,1,199.99,2024-01-18,STORE003,East,credit_card
TXN008,CUST003,PROD004,2,89.99,2024-01-18,STORE002,South,cash
TXN009,CUST001,PROD005,1,45.00,2024-01-19,STORE001,North,credit_card
TXN010,CUST004,PROD003,3,15.50,2024-01-19,STORE003,East,debit_card
EOF
  )
  storage_class = var.s3_storage_class

  tags = local.common_tags
}

resource "aws_s3_object" "customers_data" {
  count  = var.create_sample_data ? 1 : 0
  bucket = aws_s3_bucket.data_lake.id
  key    = "${var.sample_data_prefix}/customers/customers.csv"
  content = <<EOF
customer_id,first_name,last_name,email,phone,registration_date,tier,city,state
CUST001,John,Doe,john.doe@email.com,555-0101,2023-01-15,premium,New York,NY
CUST002,Jane,Smith,jane.smith@email.com,555-0102,2023-02-20,standard,Los Angeles,CA
CUST003,Bob,Johnson,bob.johnson@email.com,555-0103,2023-03-10,standard,Chicago,IL
CUST004,Alice,Brown,alice.brown@email.com,555-0104,2023-04-05,premium,Miami,FL
CUST005,Charlie,Wilson,charlie.wilson@email.com,555-0105,2023-05-12,standard,Seattle,WA
EOF
  storage_class = var.s3_storage_class

  tags = local.common_tags
}

resource "aws_s3_object" "products_data" {
  count  = var.create_sample_data ? 1 : 0
  bucket = aws_s3_bucket.data_lake.id
  key    = "${var.sample_data_prefix}/products/products.csv"
  content = <<EOF
product_id,product_name,category,brand,cost,retail_price,supplier_id
PROD001,Wireless Headphones,Electronics,TechBrand,20.00,29.99,SUP001
PROD002,Smart Watch,Electronics,TechBrand,120.00,199.99,SUP001
PROD003,Coffee Mug,Home,HomeBrand,8.00,15.50,SUP002
PROD004,Bluetooth Speaker,Electronics,AudioMax,50.00,89.99,SUP003
PROD005,Desk Lamp,Home,HomeBrand,25.00,45.00,SUP002
EOF
  storage_class = var.s3_storage_class

  tags = local.common_tags
}

# IAM policy document for Redshift Spectrum
data "aws_iam_policy_document" "redshift_spectrum_policy" {
  # S3 permissions for data lake access
  statement {
    sid    = "S3DataLakeAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [
      aws_s3_bucket.data_lake.arn,
      "${aws_s3_bucket.data_lake.arn}/*"
    ]
  }

  # Glue catalog permissions for metadata access
  statement {
    sid    = "GlueCatalogAccess"
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartition",
      "glue:GetPartitions"
    ]
    resources = ["*"]
  }
}

# IAM trust policy for Redshift service
data "aws_iam_policy_document" "redshift_trust_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["redshift.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# IAM role for Redshift Spectrum
resource "aws_iam_role" "redshift_spectrum_role" {
  name               = "${var.project_name}-redshift-spectrum-role-${local.resource_suffix}"
  assume_role_policy = data.aws_iam_policy_document.redshift_trust_policy.json

  tags = merge(local.common_tags, {
    Name    = "Redshift Spectrum Role"
    Purpose = "Enable Redshift Spectrum access to S3 and Glue"
  })
}

# IAM policy for Redshift Spectrum
resource "aws_iam_policy" "redshift_spectrum_policy" {
  name        = "${var.project_name}-redshift-spectrum-policy-${local.resource_suffix}"
  description = "IAM policy for Redshift Spectrum to access S3 and Glue"
  policy      = data.aws_iam_policy_document.redshift_spectrum_policy.json

  tags = local.common_tags
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "redshift_spectrum_policy_attachment" {
  role       = aws_iam_role.redshift_spectrum_role.name
  policy_arn = aws_iam_policy.redshift_spectrum_policy.arn
}

# Redshift subnet group
resource "aws_redshift_subnet_group" "main" {
  name       = "${var.project_name}-subnet-group-${local.resource_suffix}"
  subnet_ids = local.subnet_ids

  tags = merge(local.common_tags, {
    Name = "Redshift Subnet Group"
  })
}

# Security group for Redshift cluster
resource "aws_security_group" "redshift" {
  name_prefix = "${var.project_name}-redshift-"
  vpc_id      = local.vpc_id
  description = "Security group for Redshift cluster"

  # Inbound rules for Redshift access
  ingress {
    description = "Redshift access"
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  # Outbound rules
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "Redshift Security Group"
  })
}

# Redshift cluster
resource "aws_redshift_cluster" "main" {
  cluster_identifier = local.redshift_cluster_id
  database_name      = var.redshift_database_name
  master_username    = var.redshift_master_username
  master_password    = var.redshift_master_password != "" ? var.redshift_master_password : random_password.redshift_password[0].result
  
  node_type           = var.redshift_node_type
  cluster_type        = var.redshift_cluster_type
  number_of_nodes     = var.redshift_cluster_type == "multi-node" ? var.redshift_number_of_nodes : null
  
  db_name                = var.redshift_database_name
  port                   = 5439
  publicly_accessible    = var.redshift_publicly_accessible
  skip_final_snapshot    = var.redshift_skip_final_snapshot
  
  # Network configuration
  cluster_subnet_group_name   = aws_redshift_subnet_group.main.name
  vpc_security_group_ids      = [aws_security_group.redshift.id]
  
  # IAM roles for Spectrum
  iam_roles = [aws_iam_role.redshift_spectrum_role.arn]
  
  # Backup and maintenance
  automated_snapshot_retention_period = 7
  preferred_maintenance_window         = "sun:03:00-sun:04:00"
  
  # Encryption
  encrypted = true

  tags = merge(local.common_tags, {
    Name        = "Redshift Cluster"
    Purpose     = "Operational analytics with Spectrum"
    Environment = var.environment
  })

  depends_on = [
    aws_iam_role_policy_attachment.redshift_spectrum_policy_attachment
  ]
}

# Glue Data Catalog database
resource "aws_glue_catalog_database" "main" {
  name        = local.glue_database_name
  description = "Database for Redshift Spectrum operational analytics"

  tags = merge(local.common_tags, {
    Name    = "Glue Catalog Database"
    Purpose = "Metadata for Spectrum queries"
  })
}

# IAM role for Glue crawlers
resource "aws_iam_role" "glue_crawler_role" {
  name = "${var.project_name}-glue-crawler-role-${local.resource_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name    = "Glue Crawler Role"
    Purpose = "Enable Glue crawlers to discover data schemas"
  })
}

# Attach AWS managed policy for Glue service
resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue_crawler_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Attach S3 access policy to Glue role
resource "aws_iam_role_policy_attachment" "glue_s3_access" {
  role       = aws_iam_role.glue_crawler_role.name
  policy_arn = aws_iam_policy.redshift_spectrum_policy.arn
}

# Glue crawler for sales data
resource "aws_glue_crawler" "sales_crawler" {
  database_name = aws_glue_catalog_database.main.name
  name          = "${var.project_name}-sales-crawler-${local.resource_suffix}"
  role          = aws_iam_role.glue_crawler_role.arn
  schedule      = var.glue_crawler_schedule

  s3_target {
    path = "s3://${aws_s3_bucket.data_lake.bucket}/${var.sample_data_prefix}/sales/"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = {
        AddOrUpdateBehavior = "InheritFromTable"
      }
      Tables = {
        AddOrUpdateBehavior = "MergeNewColumns"
      }
    }
  })

  tags = merge(local.common_tags, {
    Name       = "Sales Data Crawler"
    DataSource = "sales-transactions"
  })

  depends_on = [
    aws_iam_role_policy_attachment.glue_service_role,
    aws_iam_role_policy_attachment.glue_s3_access
  ]
}

# Glue crawler for customers data
resource "aws_glue_crawler" "customers_crawler" {
  database_name = aws_glue_catalog_database.main.name
  name          = "${var.project_name}-customers-crawler-${local.resource_suffix}"
  role          = aws_iam_role.glue_crawler_role.arn
  schedule      = var.glue_crawler_schedule

  s3_target {
    path = "s3://${aws_s3_bucket.data_lake.bucket}/${var.sample_data_prefix}/customers/"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = {
        AddOrUpdateBehavior = "InheritFromTable"
      }
      Tables = {
        AddOrUpdateBehavior = "MergeNewColumns"
      }
    }
  })

  tags = merge(local.common_tags, {
    Name       = "Customers Data Crawler"
    DataSource = "customers"
  })

  depends_on = [
    aws_iam_role_policy_attachment.glue_service_role,
    aws_iam_role_policy_attachment.glue_s3_access
  ]
}

# Glue crawler for products data
resource "aws_glue_crawler" "products_crawler" {
  database_name = aws_glue_catalog_database.main.name
  name          = "${var.project_name}-products-crawler-${local.resource_suffix}"
  role          = aws_iam_role.glue_crawler_role.arn
  schedule      = var.glue_crawler_schedule

  s3_target {
    path = "s3://${aws_s3_bucket.data_lake.bucket}/${var.sample_data_prefix}/products/"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = {
        AddOrUpdateBehavior = "InheritFromTable"
      }
      Tables = {
        AddOrUpdateBehavior = "MergeNewColumns"
      }
    }
  })

  tags = merge(local.common_tags, {
    Name       = "Products Data Crawler"
    DataSource = "products"
  })

  depends_on = [
    aws_iam_role_policy_attachment.glue_service_role,
    aws_iam_role_policy_attachment.glue_s3_access
  ]
}