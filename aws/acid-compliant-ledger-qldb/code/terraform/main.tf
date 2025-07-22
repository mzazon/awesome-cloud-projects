# Amazon QLDB Infrastructure for ACID-Compliant Distributed Databases

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}

# Data source for current AWS region
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed configurations
locals {
  random_suffix          = random_id.suffix.hex
  ledger_name           = "${var.ledger_name_prefix}-${local.random_suffix}"
  s3_bucket_name        = "${var.s3_bucket_name_prefix}-${local.random_suffix}"
  kinesis_stream_name   = "${var.kinesis_stream_name_prefix}-${local.random_suffix}"
  iam_role_name         = "qldb-stream-role-${local.random_suffix}"
  
  # Common tags
  common_tags = {
    Project     = "QLDB-Financial-System"
    Environment = var.environment
    CreatedBy   = "Terraform"
  }
}

# S3 bucket for QLDB journal exports
resource "aws_s3_bucket" "qldb_exports" {
  bucket        = local.s3_bucket_name
  force_destroy = true # Allow destruction even with objects (for testing)

  tags = merge(local.common_tags, {
    Name        = "QLDB Journal Exports"
    Purpose     = "Store QLDB journal exports for compliance and archival"
    DataClass   = "Financial"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "qldb_exports_versioning" {
  bucket = aws_s3_bucket.qldb_exports.id
  
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "qldb_exports_encryption" {
  bucket = aws_s3_bucket.qldb_exports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "qldb_exports_pab" {
  bucket = aws_s3_bucket.qldb_exports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "qldb_exports_lifecycle" {
  count  = var.s3_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.qldb_exports.id

  rule {
    id     = "financial_data_lifecycle"
    status = "Enabled"

    # Transition to Infrequent Access
    transition {
      days          = var.s3_transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier
    transition {
      days          = var.s3_transition_to_glacier_days
      storage_class = "GLACIER"
    }

    # Expire incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Kinesis Data Stream for real-time journal streaming
resource "aws_kinesis_stream" "qldb_journal_stream" {
  name             = local.kinesis_stream_name
  shard_count      = var.kinesis_shard_count
  retention_period = 24 # hours

  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  shard_level_metrics = [
    "IncomingRecords",
    "OutgoingRecords",
  ]

  tags = merge(local.common_tags, {
    Name    = "QLDB Journal Stream"
    Purpose = "Real-time streaming of QLDB journal entries"
  })
}

# IAM trust policy for QLDB service
data "aws_iam_policy_document" "qldb_trust_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["qldb.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# IAM permissions policy for QLDB streaming
data "aws_iam_policy_document" "qldb_permissions_policy" {
  # S3 permissions for journal exports
  statement {
    effect = "Allow"
    
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    
    resources = [
      aws_s3_bucket.qldb_exports.arn,
      "${aws_s3_bucket.qldb_exports.arn}/*",
    ]
  }

  # Kinesis permissions for journal streaming
  statement {
    effect = "Allow"
    
    actions = [
      "kinesis:PutRecord",
      "kinesis:PutRecords",
      "kinesis:DescribeStream",
      "kinesis:ListStreams",
    ]
    
    resources = [
      aws_kinesis_stream.qldb_journal_stream.arn,
    ]
  }

  # KMS permissions for encryption
  statement {
    effect = "Allow"
    
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey",
    ]
    
    resources = ["*"]
    
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["kinesis.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
}

# IAM role for QLDB streaming operations
resource "aws_iam_role" "qldb_stream_role" {
  name               = local.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.qldb_trust_policy.json

  tags = merge(local.common_tags, {
    Name        = "QLDB Stream Role"
    Purpose     = "Service role for QLDB journal streaming"
    ServiceType = "QLDB"
  })
}

# IAM policy attachment for QLDB streaming
resource "aws_iam_role_policy" "qldb_stream_policy" {
  name   = "QLDBStreamPolicy"
  role   = aws_iam_role.qldb_stream_role.id
  policy = data.aws_iam_policy_document.qldb_permissions_policy.json
}

# CloudWatch Log Group for QLDB monitoring (optional)
resource "aws_cloudwatch_log_group" "qldb_monitoring" {
  count             = var.enable_cloudwatch_logs ? 1 : 0
  name              = "/aws/qldb/${local.ledger_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name    = "QLDB Monitoring Logs"
    Purpose = "Centralized logging for QLDB operations"
  })
}

# Amazon QLDB Ledger - The core immutable database
resource "aws_qldb_ledger" "financial_ledger" {
  name                = local.ledger_name
  permissions_mode    = "STANDARD"
  deletion_protection = var.enable_deletion_protection

  tags = merge(local.common_tags, {
    Name            = "Financial Transactions Ledger"
    Purpose         = "Immutable ledger for financial transaction records"
    DataClass       = "Financial"
    ComplianceLevel = "High"
    AuditRequired   = "true"
  })
}

# QLDB Journal Stream to Kinesis for real-time processing
resource "aws_qldb_stream" "journal_to_kinesis" {
  ledger_name      = aws_qldb_ledger.financial_ledger.name
  role_arn         = aws_iam_role.qldb_stream_role.arn
  stream_name      = "${local.ledger_name}-journal-stream"
  inclusive_start_time = "2024-01-01T00:00:00Z"

  kinesis_configuration {
    stream_arn           = aws_kinesis_stream.qldb_journal_stream.arn
    aggregation_enabled  = var.enable_kinesis_aggregation
  }

  tags = merge(local.common_tags, {
    Name    = "QLDB Journal Stream"
    Purpose = "Stream journal entries to Kinesis for real-time processing"
  })

  depends_on = [
    aws_iam_role_policy.qldb_stream_policy
  ]
}

# CloudWatch Alarms for monitoring QLDB operations
resource "aws_cloudwatch_metric_alarm" "qldb_read_io_high" {
  count               = var.enable_cloudwatch_logs ? 1 : 0
  alarm_name          = "qldb-${local.ledger_name}-high-read-io"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReadIOs"
  namespace           = "AWS/QLDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1000"
  alarm_description   = "This metric monitors QLDB read I/O operations"
  alarm_actions       = [] # Add SNS topic ARN if needed

  dimensions = {
    LedgerName = aws_qldb_ledger.financial_ledger.name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "qldb_write_io_high" {
  count               = var.enable_cloudwatch_logs ? 1 : 0
  alarm_name          = "qldb-${local.ledger_name}-high-write-io"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "WriteIOs"
  namespace           = "AWS/QLDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "500"
  alarm_description   = "This metric monitors QLDB write I/O operations"
  alarm_actions       = [] # Add SNS topic ARN if needed

  dimensions = {
    LedgerName = aws_qldb_ledger.financial_ledger.name
  }

  tags = local.common_tags
}

# CloudWatch Alarm for Kinesis stream incoming records
resource "aws_cloudwatch_metric_alarm" "kinesis_incoming_records" {
  count               = var.enable_cloudwatch_logs ? 1 : 0
  alarm_name          = "kinesis-${local.kinesis_stream_name}-incoming-records"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "IncomingRecords"
  namespace           = "AWS/Kinesis"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors if Kinesis stream is receiving records"
  treat_missing_data  = "breaching"

  dimensions = {
    StreamName = aws_kinesis_stream.qldb_journal_stream.name
  }

  tags = local.common_tags
}

# Example PartiQL scripts for table creation (stored as local file content)
locals {
  partiql_scripts = {
    create_tables = <<-EOF
      -- Create tables for financial data structure
      CREATE TABLE Accounts;
      CREATE TABLE Transactions;
      CREATE TABLE AuditLog;
      
      -- Create indexes for efficient querying
      CREATE INDEX ON Accounts (accountId);
      CREATE INDEX ON Transactions (transactionId);
      CREATE INDEX ON Transactions (fromAccountId);
      CREATE INDEX ON Transactions (toAccountId);
      CREATE INDEX ON AuditLog (timestamp);
    EOF
    
    sample_data = <<-EOF
      -- Sample account data
      INSERT INTO Accounts VALUE {
        'accountId': 'ACC-001',
        'accountNumber': '1234567890',
        'accountType': 'CHECKING',
        'balance': 10000.00,
        'currency': 'USD',
        'customerId': 'CUST-001',
        'createdAt': '2024-01-01T00:00:00Z',
        'status': 'ACTIVE'
      };
      
      -- Sample transaction data
      INSERT INTO Transactions VALUE {
        'transactionId': 'TXN-001',
        'fromAccountId': 'ACC-001',
        'toAccountId': 'ACC-002',
        'amount': 500.00,
        'currency': 'USD',
        'transactionType': 'TRANSFER',
        'timestamp': '2024-01-15T10:30:00Z',
        'description': 'Monthly transfer',
        'status': 'COMPLETED'
      };
    EOF
    
    audit_queries = <<-EOF
      -- Query all transactions for a specific account
      SELECT * FROM Transactions 
      WHERE fromAccountId = 'ACC-001' OR toAccountId = 'ACC-001';
      
      -- Query transactions within a date range
      SELECT * FROM Transactions 
      WHERE timestamp BETWEEN '2024-01-01T00:00:00Z' AND '2024-01-31T23:59:59Z';
      
      -- Query account balance history using QLDB's history function
      SELECT accountId, balance, metadata.txTime 
      FROM history(Accounts) AS a
      WHERE a.data.accountId = 'ACC-001';
      
      -- Query transaction history with metadata
      SELECT t.*, metadata.txTime, metadata.txId
      FROM history(Transactions) AS t
      WHERE t.data.transactionId = 'TXN-001';
    EOF
  }
}

# Store PartiQL scripts as local files for reference
resource "local_file" "partiql_create_tables" {
  content  = local.partiql_scripts.create_tables
  filename = "${path.module}/scripts/create-tables.sql"
}

resource "local_file" "partiql_sample_data" {
  content  = local.partiql_scripts.sample_data
  filename = "${path.module}/scripts/sample-data.sql"
}

resource "local_file" "partiql_audit_queries" {
  content  = local.partiql_scripts.audit_queries
  filename = "${path.module}/scripts/audit-queries.sql"
}