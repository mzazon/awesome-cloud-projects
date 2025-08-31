# Enterprise Oracle Database Connectivity with VPC Lattice and S3
# Main Terraform configuration for implementing managed Oracle Database@AWS integration

# =============================================================================
# DATA SOURCES
# =============================================================================

# Get current AWS account information
data "aws_caller_identity" "current" {}

# Get current AWS region
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
  
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# =============================================================================
# LOCAL VALUES
# =============================================================================

locals {
  # Resource naming
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Networking
  vpc_id     = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids
  
  # Resource names
  s3_bucket_name = var.s3_bucket_name != "" ? var.s3_bucket_name : "${local.name_prefix}-oracle-backup-${local.name_suffix}"
  redshift_cluster_id = var.redshift_cluster_identifier != "" ? var.redshift_cluster_identifier : "${local.name_prefix}-analytics-${local.name_suffix}"
  
  # Common tags
  common_tags = merge(
    {
      Name        = "${local.name_prefix}-oracle-integration"
      Environment = var.environment
      Project     = var.project_name
      Recipe      = "enterprise-oracle-connectivity-lattice-s3"
    },
    var.additional_tags
  )
}

# =============================================================================
# S3 BUCKET FOR ORACLE DATABASE BACKUPS
# =============================================================================

# S3 bucket for Oracle Database@AWS backups with enterprise features
resource "aws_s3_bucket" "oracle_backup" {
  bucket = local.s3_bucket_name
  
  tags = merge(local.common_tags, {
    Purpose = "Oracle Database Backup Storage"
    Service = "S3"
  })
}

# Enable versioning for backup protection
resource "aws_s3_bucket_versioning" "oracle_backup" {
  bucket = aws_s3_bucket.oracle_backup.id
  
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# Server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "oracle_backup" {
  bucket = aws_s3_bucket.oracle_backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.s3_encryption_algorithm
    }
    bucket_key_enabled = true
  }
}

# Public access block for security
resource "aws_s3_bucket_public_access_block" "oracle_backup" {
  bucket = aws_s3_bucket.oracle_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "oracle_backup" {
  bucket = aws_s3_bucket.oracle_backup.id

  rule {
    id     = "OracleBackupLifecycle"
    status = "Enabled"

    transition {
      days          = var.s3_lifecycle_transition_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_lifecycle_transition_glacier_days
      storage_class = "GLACIER"
    }

    noncurrent_version_transition {
      noncurrent_days = var.s3_lifecycle_transition_ia_days
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

# S3 bucket policy for Oracle Database@AWS access (if enabled)
resource "aws_s3_bucket_policy" "oracle_backup" {
  count  = var.enable_s3_bucket_policy ? 1 : 0
  bucket = aws_s3_bucket.oracle_backup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "OracleDBAccessPolicy"
        Effect = "Allow"
        Principal = {
          Service = "odb.amazonaws.com"
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.oracle_backup.arn,
          "${aws_s3_bucket.oracle_backup.arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# =============================================================================
# IAM ROLES AND POLICIES
# =============================================================================

# IAM role for Redshift cluster
resource "aws_iam_role" "redshift_role" {
  name = "${local.name_prefix}-redshift-role-${local.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "redshift.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Purpose = "Redshift Cluster Service Role"
    Service = "IAM"
  })
}

# Attach S3 read-only access policy to Redshift role
resource "aws_iam_role_policy_attachment" "redshift_s3_access" {
  role       = aws_iam_role.redshift_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# Attach Redshift full access policy to Redshift role
resource "aws_iam_role_policy_attachment" "redshift_full_access" {
  role       = aws_iam_role.redshift_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRedshiftAllCommandsFullAccess"
}

# Custom IAM policy for enhanced S3 access
resource "aws_iam_role_policy" "redshift_s3_custom" {
  name = "${local.name_prefix}-redshift-s3-policy"
  role = aws_iam_role.redshift_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.oracle_backup.arn,
          "${aws_s3_bucket.oracle_backup.arn}/*"
        ]
      }
    ]
  })
}

# =============================================================================
# REDSHIFT CLUSTER
# =============================================================================

# Redshift subnet group
resource "aws_redshift_subnet_group" "oracle_analytics" {
  name       = "${local.name_prefix}-redshift-subnet-group"
  subnet_ids = local.subnet_ids

  tags = merge(local.common_tags, {
    Purpose = "Redshift Cluster Subnet Group"
    Service = "Redshift"
  })
}

# Security group for Redshift cluster
resource "aws_security_group" "redshift" {
  name_prefix = "${local.name_prefix}-redshift-"
  vpc_id      = local.vpc_id

  ingress {
    description = "Redshift access"
    from_port   = var.redshift_port
    to_port     = var.redshift_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Purpose = "Redshift Cluster Security Group"
    Service = "EC2"
  })
}

# Redshift cluster for Oracle analytics
resource "aws_redshift_cluster" "oracle_analytics" {
  cluster_identifier = local.redshift_cluster_id
  database_name      = var.redshift_database_name
  master_username    = var.redshift_master_username
  master_password    = var.redshift_master_password
  node_type          = var.redshift_node_type
  cluster_type       = var.redshift_cluster_type
  
  # Only set number_of_nodes for multi-node clusters
  number_of_nodes = var.redshift_cluster_type == "multi-node" ? var.redshift_number_of_nodes : null

  # Security and networking
  db_subnet_group_name   = aws_redshift_subnet_group.oracle_analytics.name
  vpc_security_group_ids = [aws_security_group.redshift.id]
  publicly_accessible    = var.redshift_publicly_accessible
  port                   = var.redshift_port
  encrypted              = var.redshift_encrypted

  # IAM roles
  iam_roles = [aws_iam_role.redshift_role.arn]

  # Backup and maintenance
  automated_snapshot_retention_period = 7
  preferred_maintenance_window        = "sun:05:00-sun:06:00"
  
  # Monitoring
  enable_logging = var.enable_cloudwatch_monitoring

  # Skip final snapshot for testing/dev environments
  skip_final_snapshot = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${local.redshift_cluster_id}-final-snapshot" : null

  tags = merge(local.common_tags, {
    Purpose = "Oracle Analytics Data Warehouse"
    Service = "Redshift"
  })

  depends_on = [
    aws_iam_role_policy_attachment.redshift_s3_access,
    aws_iam_role_policy_attachment.redshift_full_access
  ]
}

# =============================================================================
# CLOUDWATCH MONITORING
# =============================================================================

# CloudWatch log group for Oracle operations
resource "aws_cloudwatch_log_group" "oracle_operations" {
  count             = var.enable_cloudwatch_monitoring ? 1 : 0
  name              = "/aws/oracle-database/enterprise-integration"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Purpose = "Oracle Database Operations Logging"
    Service = "CloudWatch"
  })
}

# CloudWatch dashboard for monitoring Oracle integration
resource "aws_cloudwatch_dashboard" "oracle_integration" {
  count          = var.enable_cloudwatch_monitoring ? 1 : 0
  dashboard_name = "${local.name_prefix}-oracle-integration-${local.name_suffix}"

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
            ["AWS/S3", "BucketRequests", "BucketName", aws_s3_bucket.oracle_backup.bucket, "FilterId", "EntireBucket"],
            ["AWS/S3", "NumberOfObjects", "BucketName", aws_s3_bucket.oracle_backup.bucket, "StorageType", "AllStorageTypes"],
            ["AWS/Redshift", "CPUUtilization", "ClusterIdentifier", aws_redshift_cluster.oracle_analytics.cluster_identifier],
            ["AWS/Redshift", "DatabaseConnections", "ClusterIdentifier", aws_redshift_cluster.oracle_analytics.cluster_identifier]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Oracle Database@AWS Integration Metrics"
          view   = "timeSeries"
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
            ["AWS/S3", "BucketSizeBytes", "BucketName", aws_s3_bucket.oracle_backup.bucket, "StorageType", "StandardStorage"],
            ["AWS/Redshift", "PercentageDiskSpaceUsed", "ClusterIdentifier", aws_redshift_cluster.oracle_analytics.cluster_identifier]
          ]
          period = 3600
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Storage Utilization Metrics"
          view   = "timeSeries"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Purpose = "Oracle Integration Monitoring Dashboard"
    Service = "CloudWatch"
  })
}

# =============================================================================
# VPC LATTICE INTEGRATION (Reference Configuration)
# =============================================================================

# Note: VPC Lattice service network and resource gateway configuration
# is typically managed by Oracle Database@AWS service. The following
# are data sources to reference existing VPC Lattice resources.

# Data source to find VPC Lattice service networks
data "aws_vpclattice_service_network" "odb_default" {
  count = 1

  tags = {
    Name = "*default-odb-network*"
  }
}

# Output VPC Lattice service network information for reference
output "vpc_lattice_service_network_info" {
  description = "VPC Lattice service network information"
  value = length(data.aws_vpclattice_service_network.odb_default) > 0 ? {
    id   = data.aws_vpclattice_service_network.odb_default[0].id
    name = data.aws_vpclattice_service_network.odb_default[0].name
    arn  = data.aws_vpclattice_service_network.odb_default[0].arn
  } : null
}

# =============================================================================
# OUTPUTS REFERENCE
# =============================================================================

# Note: Additional outputs are defined in outputs.tf for better organization