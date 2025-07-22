# Amazon Redshift Data Warehouse Infrastructure
# This Terraform configuration creates a complete data warehousing solution using Amazon Redshift Serverless

# Data source to get current AWS account information
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  # Generate unique names if not provided
  namespace_name = var.namespace_name != "" ? var.namespace_name : "data-warehouse-ns-${random_id.suffix.hex}"
  workgroup_name = var.workgroup_name != "" ? var.workgroup_name : "data-warehouse-wg-${random_id.suffix.hex}"
  s3_bucket_name = var.s3_bucket_name != "" ? var.s3_bucket_name : "redshift-data-${random_id.suffix.hex}"
  iam_role_name  = var.iam_role_name != "" ? var.iam_role_name : "RedshiftServerlessRole-${random_id.suffix.hex}"

  # Sample data for demonstration
  sales_data = <<-EOT
order_id,customer_id,product_id,quantity,price,order_date
1001,501,2001,2,29.99,2024-01-15
1002,502,2002,1,49.99,2024-01-15
1003,503,2001,3,29.99,2024-01-16
1004,501,2003,1,79.99,2024-01-16
1005,504,2002,2,49.99,2024-01-17
1006,505,2001,1,29.99,2024-01-18
1007,502,2003,2,79.99,2024-01-18
1008,506,2002,3,49.99,2024-01-19
1009,507,2001,1,29.99,2024-01-19
1010,501,2004,1,99.99,2024-01-20
EOT

  customer_data = <<-EOT
customer_id,first_name,last_name,email,city,state
501,John,Doe,john.doe@email.com,Seattle,WA
502,Jane,Smith,jane.smith@email.com,Portland,OR
503,Mike,Johnson,mike.johnson@email.com,San Francisco,CA
504,Sarah,Wilson,sarah.wilson@email.com,Los Angeles,CA
505,David,Brown,david.brown@email.com,Denver,CO
506,Lisa,Davis,lisa.davis@email.com,Phoenix,AZ
507,Tom,Miller,tom.miller@email.com,Austin,TX
EOT

  # SQL commands for table creation
  create_tables_sql = <<-EOT
-- Create sales table
CREATE TABLE sales (
    order_id INTEGER,
    customer_id INTEGER,
    product_id INTEGER,
    quantity INTEGER,
    price DECIMAL(10,2),
    order_date DATE
)
DISTSTYLE AUTO
SORTKEY (order_date, customer_id);

-- Create customers table
CREATE TABLE customers (
    customer_id INTEGER,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email VARCHAR(100),
    city VARCHAR(50),
    state VARCHAR(2)
)
DISTSTYLE AUTO
SORTKEY (customer_id);
EOT

  # SQL commands for data loading
  load_data_sql = <<-EOT
-- Load sales data from S3
COPY sales FROM 's3://${local.s3_bucket_name}/data/sales_data.csv'
IAM_ROLE '${aws_iam_role.redshift_role.arn}'
CSV
IGNOREHEADER 1
REGION '${data.aws_region.current.name}';

-- Load customer data from S3
COPY customers FROM 's3://${local.s3_bucket_name}/data/customer_data.csv'
IAM_ROLE '${aws_iam_role.redshift_role.arn}'
CSV
IGNOREHEADER 1
REGION '${data.aws_region.current.name}';
EOT

  # Sample analytical queries
  sample_queries_sql = <<-EOT
-- Sales summary by customer
SELECT 
    c.first_name,
    c.last_name,
    c.city,
    c.state,
    COUNT(s.order_id) as total_orders,
    SUM(s.quantity * s.price) as total_revenue
FROM sales s
JOIN customers c ON s.customer_id = c.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name, c.city, c.state
ORDER BY total_revenue DESC;

-- Daily sales trend
SELECT 
    order_date,
    COUNT(order_id) as daily_orders,
    SUM(quantity * price) as daily_revenue,
    AVG(quantity * price) as avg_order_value
FROM sales
GROUP BY order_date
ORDER BY order_date;

-- Product performance analysis
SELECT 
    product_id,
    SUM(quantity) as total_quantity_sold,
    SUM(quantity * price) as total_revenue,
    AVG(price) as average_price,
    COUNT(DISTINCT customer_id) as unique_customers
FROM sales
GROUP BY product_id
ORDER BY total_revenue DESC;

-- Customer state analysis
SELECT 
    c.state,
    COUNT(DISTINCT c.customer_id) as customer_count,
    COUNT(s.order_id) as total_orders,
    SUM(s.quantity * s.price) as total_revenue
FROM customers c
LEFT JOIN sales s ON c.customer_id = s.customer_id
GROUP BY c.state
ORDER BY total_revenue DESC;
EOT
}

# KMS Key for encryption (optional)
resource "aws_kms_key" "redshift_key" {
  count = var.enable_encryption ? 1 : 0

  description             = "KMS key for Redshift Serverless encryption"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true

  tags = {
    Name = "redshift-serverless-key"
  }
}

resource "aws_kms_alias" "redshift_key_alias" {
  count = var.enable_encryption ? 1 : 0

  name          = "alias/redshift-serverless-${random_id.suffix.hex}"
  target_key_id = aws_kms_key.redshift_key[0].key_id
}

# S3 Bucket for data storage
resource "aws_s3_bucket" "data_bucket" {
  bucket        = local.s3_bucket_name
  force_destroy = var.s3_force_destroy

  tags = {
    Name = "redshift-data-bucket"
  }
}

# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "data_bucket_versioning" {
  bucket = aws_s3_bucket.data_bucket.id
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Suspended"
  }
}

# S3 Bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "data_bucket_encryption" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.data_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.redshift_key[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket public access block
resource "aws_s3_bucket_public_access_block" "data_bucket_pab" {
  bucket = aws_s3_bucket.data_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload sample data files to S3
resource "aws_s3_object" "sales_data" {
  count = var.create_sample_data ? 1 : 0

  bucket       = aws_s3_bucket.data_bucket.bucket
  key          = "data/sales_data.csv"
  content      = local.sales_data
  content_type = "text/csv"

  tags = {
    Name = "sales-sample-data"
    Type = "sample-data"
  }
}

resource "aws_s3_object" "customer_data" {
  count = var.create_sample_data ? 1 : 0

  bucket       = aws_s3_bucket.data_bucket.bucket
  key          = "data/customer_data.csv"
  content      = local.customer_data
  content_type = "text/csv"

  tags = {
    Name = "customer-sample-data"
    Type = "sample-data"
  }
}

# IAM Trust Policy for Redshift
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

# IAM Policy for Redshift to access S3
data "aws_iam_policy_document" "redshift_s3_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [
      aws_s3_bucket.data_bucket.arn,
      "${aws_s3_bucket.data_bucket.arn}/*"
    ]
  }

  # KMS permissions if encryption is enabled
  dynamic "statement" {
    for_each = var.enable_encryption ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ]
      resources = [aws_kms_key.redshift_key[0].arn]
    }
  }
}

# IAM Role for Redshift Serverless
resource "aws_iam_role" "redshift_role" {
  name               = local.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.redshift_trust_policy.json

  tags = {
    Name = "redshift-serverless-role"
  }
}

# IAM Policy for S3 access
resource "aws_iam_role_policy" "redshift_s3_policy" {
  name   = "redshift-s3-access"
  role   = aws_iam_role.redshift_role.id
  policy = data.aws_iam_policy_document.redshift_s3_policy.json
}

# Attach AWS managed policy for Redshift
resource "aws_iam_role_policy_attachment" "redshift_managed_policy" {
  role       = aws_iam_role.redshift_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRedshiftAllCommandsFullAccess"
}

# CloudWatch Log Group for Redshift logs
resource "aws_cloudwatch_log_group" "redshift_logs" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name              = "/aws/redshift/serverless/${local.workgroup_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "redshift-serverless-logs"
  }
}

# Redshift Serverless Namespace (Storage Layer)
resource "aws_redshiftserverless_namespace" "main" {
  namespace_name      = local.namespace_name
  admin_username      = var.admin_username
  admin_user_password = random_password.admin_password.result
  db_name             = var.database_name
  default_iam_role_arn = aws_iam_role.redshift_role.arn

  # Enable logging if CloudWatch logs are enabled
  dynamic "log_exports" {
    for_each = var.enable_cloudwatch_logs ? ["userlog", "connectionlog", "useractivitylog"] : []
    content {
      log_type = log_exports.value
    }
  }

  # Enable encryption if specified
  kms_key_id = var.enable_encryption ? aws_kms_key.redshift_key[0].arn : null

  tags = {
    Name = "redshift-serverless-namespace"
  }
}

# Generate a random password for the admin user
resource "random_password" "admin_password" {
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true
}

# Store the admin password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "admin_password" {
  name        = "redshift-serverless-admin-password-${random_id.suffix.hex}"
  description = "Admin password for Redshift Serverless namespace ${local.namespace_name}"

  tags = {
    Name = "redshift-admin-password"
  }
}

resource "aws_secretsmanager_secret_version" "admin_password" {
  secret_id = aws_secretsmanager_secret.admin_password.id
  secret_string = jsonencode({
    username = var.admin_username
    password = random_password.admin_password.result
    engine   = "redshift"
    host     = aws_redshiftserverless_workgroup.main.endpoint[0].address
    port     = aws_redshiftserverless_workgroup.main.endpoint[0].port
    dbname   = var.database_name
  })
}

# Redshift Serverless Workgroup (Compute Layer)
resource "aws_redshiftserverless_workgroup" "main" {
  namespace_name   = aws_redshiftserverless_namespace.main.namespace_name
  workgroup_name   = local.workgroup_name
  base_capacity    = var.base_capacity
  max_capacity     = var.max_capacity
  publicly_accessible = var.publicly_accessible

  # Network configuration for private access
  dynamic "config_parameter" {
    for_each = length(var.subnet_ids) > 0 ? ["enable_user_activity_logging"] : []
    content {
      parameter_key   = config_parameter.value
      parameter_value = "true"
    }
  }

  # Subnet and security group configuration for private access
  subnet_ids         = length(var.subnet_ids) > 0 ? var.subnet_ids : null
  security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : null

  tags = {
    Name = "redshift-serverless-workgroup"
  }

  depends_on = [aws_redshiftserverless_namespace.main]
}

# Usage Limit for cost control
resource "aws_redshiftserverless_usage_limit" "main" {
  count = var.enable_usage_limits ? 1 : 0

  resource_arn    = aws_redshiftserverless_workgroup.main.arn
  usage_type      = "serverless-compute"
  amount          = var.usage_limit_amount
  breach_action   = var.usage_limit_breach_action
  period          = "monthly"

  tags = {
    Name = "redshift-usage-limit"
  }
}

# CloudWatch Dashboard for monitoring (optional)
resource "aws_cloudwatch_dashboard" "redshift_dashboard" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  dashboard_name = "redshift-serverless-${random_id.suffix.hex}"

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
            ["AWS/Redshift-Serverless", "DatabaseConnections", "WorkgroupName", aws_redshiftserverless_workgroup.main.workgroup_name],
            [".", "ServerlessDatabaseCapacity", ".", "."],
            [".", "QueryDuration", ".", "."],
            [".", "QueriesCompleted", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Redshift Serverless Metrics"
        }
      }
    ]
  })
}

# CloudWatch Alarms for monitoring
resource "aws_cloudwatch_metric_alarm" "high_capacity_usage" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  alarm_name          = "redshift-high-capacity-usage-${random_id.suffix.hex}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ServerlessDatabaseCapacity"
  namespace           = "AWS/Redshift-Serverless"
  period              = "300"
  statistic           = "Average"
  threshold           = var.base_capacity * 0.8
  alarm_description   = "This metric monitors redshift serverless capacity usage"
  alarm_actions       = []

  dimensions = {
    WorkgroupName = aws_redshiftserverless_workgroup.main.workgroup_name
  }

  tags = {
    Name = "redshift-high-capacity-alarm"
  }
}