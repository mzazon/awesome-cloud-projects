# Secure Database Access with VPC Lattice Resource Gateway
# This Terraform configuration creates a secure, cross-account database sharing solution
# using AWS VPC Lattice Resource Gateway, RDS, and AWS RAM

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming convention
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Database port based on engine
  db_port_map = {
    mysql    = 3306
    postgres = 5432
    mariadb  = 3306
  }
  
  actual_db_port = lookup(local.db_port_map, var.db_engine, var.db_port)
  
  # Common tags for all resources
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
  })
}

# Generate secure database password if not provided
resource "random_password" "db_password" {
  count   = var.db_password == "" ? 1 : 0
  length  = 16
  special = true
  
  # MySQL/MariaDB/PostgreSQL compatible special characters
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Get VPC information for CIDR blocks
data "aws_vpc" "main" {
  id = var.vpc_id
}

#######################
# Security Groups
#######################

# Security group for RDS database
resource "aws_security_group" "rds" {
  name_prefix = "${local.name_prefix}-rds-"
  description = "Security group for VPC Lattice shared RDS database"
  vpc_id      = var.vpc_id

  # Allow inbound traffic from Resource Gateway security group
  ingress {
    description     = "Database access from VPC Lattice Resource Gateway"
    from_port       = local.actual_db_port
    to_port         = local.actual_db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.resource_gateway.id]
  }

  # Allow inbound traffic from VPC CIDR for management access
  ingress {
    description = "Database access from VPC CIDR"
    from_port   = local.actual_db_port
    to_port     = local.actual_db_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.main.cidr_block]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-sg"
    Type = "Database"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for VPC Lattice Resource Gateway
resource "aws_security_group" "resource_gateway" {
  name_prefix = "${local.name_prefix}-resource-gateway-"
  description = "Security group for VPC Lattice Resource Gateway"
  vpc_id      = var.vpc_id

  # Allow outbound traffic to RDS database
  egress {
    description     = "Database access to RDS"
    from_port       = local.actual_db_port
    to_port         = local.actual_db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.rds.id]
  }

  # Allow all outbound HTTPS traffic for AWS API calls
  egress {
    description = "HTTPS outbound for AWS API"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-resource-gateway-sg"
    Type = "VPC-Lattice"
  })

  lifecycle {
    create_before_destroy = true
  }
}

#######################
# IAM Role for Enhanced Monitoring
#######################

# IAM role for RDS enhanced monitoring
resource "aws_iam_role" "rds_enhanced_monitoring" {
  count = var.enable_enhanced_monitoring ? 1 : 0
  
  name_prefix = "${local.name_prefix}-rds-monitoring-"
  
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
    Name = "${local.name_prefix}-rds-monitoring-role"
  })
}

# Attach the AWS managed policy for RDS enhanced monitoring
resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  count = var.enable_enhanced_monitoring ? 1 : 0
  
  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

#######################
# RDS Subnet Group
#######################

# DB subnet group for RDS instance
resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet-group-${random_id.suffix.hex}"
  subnet_ids = var.subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-subnet-group"
    Type = "Database"
  })
}

#######################
# RDS Database Instance
#######################

# RDS database instance with encryption and security features
resource "aws_db_instance" "main" {
  identifier = "${local.name_prefix}-shared-db-${random_id.suffix.hex}"
  
  # Engine configuration
  engine         = var.db_engine
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class
  
  # Storage configuration
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage * 2  # Enable storage autoscaling
  storage_type          = "gp3"
  storage_encrypted     = true
  
  # Database configuration
  db_name  = "shareddb"
  username = var.db_username
  password = var.db_password != "" ? var.db_password : random_password.db_password[0].result
  port     = local.actual_db_port
  
  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  
  # Backup configuration
  backup_retention_period   = var.backup_retention_period
  backup_window            = "03:00-04:00"
  maintenance_window       = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot    = true
  delete_automated_backups = false
  deletion_protection      = var.enable_deletion_protection
  
  # Monitoring configuration
  monitoring_interval = var.enable_enhanced_monitoring ? var.monitoring_interval : 0
  monitoring_role_arn = var.enable_enhanced_monitoring ? aws_iam_role.rds_enhanced_monitoring[0].arn : null
  
  performance_insights_enabled = var.enable_performance_insights
  performance_insights_retention_period = var.enable_performance_insights ? 7 : null
  
  # Security configuration
  skip_final_snapshot = false
  final_snapshot_identifier = "${local.name_prefix}-final-snapshot-${random_id.suffix.hex}"
  
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-shared-database"
    Type = "Database"
  })
  
  depends_on = [
    aws_security_group.rds,
    aws_db_subnet_group.main
  ]
}

#######################
# VPC Lattice Service Network
#######################

# VPC Lattice service network for cross-account resource sharing
resource "aws_vpclattice_service_network" "main" {
  name      = "${local.name_prefix}-service-network-${random_id.suffix.hex}"
  auth_type = "AWS_IAM"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-service-network"
    Type = "VPC-Lattice"
  })
}

# Associate the service network with the database owner VPC
resource "aws_vpclattice_service_network_vpc_association" "main" {
  vpc_identifier             = var.vpc_id
  service_network_identifier = aws_vpclattice_service_network.main.id
  security_group_ids         = [aws_security_group.resource_gateway.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc-association"
    Type = "VPC-Lattice"
  })
}

#######################
# VPC Lattice Resource Gateway
#######################

# VPC Lattice Resource Gateway for database access
resource "aws_vpclattice_resource_gateway" "main" {
  name               = "${local.name_prefix}-db-gateway-${random_id.suffix.hex}"
  vpc_identifier     = var.vpc_id
  subnet_ids         = var.subnet_ids
  security_group_ids = [aws_security_group.resource_gateway.id]
  ip_address_type    = "IPV4"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-resource-gateway"
    Type = "VPC-Lattice"
  })
  
  depends_on = [
    aws_security_group.resource_gateway
  ]
}

#######################
# VPC Lattice Resource Configuration
#######################

# Resource configuration for RDS database access through VPC Lattice
resource "aws_vpclattice_resource_configuration" "main" {
  name                        = "${local.name_prefix}-rds-config-${random_id.suffix.hex}"
  type                        = "SINGLE"
  resource_gateway_identifier = aws_vpclattice_resource_gateway.main.id
  protocol                    = "TCP"
  port_ranges                 = [tostring(local.actual_db_port)]
  
  resource_configuration_definition {
    dns_resource {
      domain_name      = aws_db_instance.main.endpoint
      ip_address_type  = "IPV4"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-resource-configuration"
    Type = "VPC-Lattice"
  })
  
  depends_on = [
    aws_db_instance.main,
    aws_vpclattice_resource_gateway.main
  ]
}

# Associate resource configuration with service network
resource "aws_vpclattice_service_network_resource_association" "main" {
  resource_configuration_identifier = aws_vpclattice_resource_configuration.main.id
  service_network_identifier        = aws_vpclattice_service_network.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-resource-association"
    Type = "VPC-Lattice"
  })
}

#######################
# IAM Policy for Cross-Account Access
#######################

# IAM policy document for cross-account VPC Lattice access
data "aws_iam_policy_document" "cross_account_access" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.consumer_account_id}:root"]
    }
    
    actions = [
      "vpc-lattice-svcs:Invoke"
    ]
    
    resources = ["*"]
    
    condition {
      test     = "StringEquals"
      variable = "vpc-lattice-svcs:SourceAccount"
      values   = [var.consumer_account_id]
    }
  }
}

# Apply the IAM policy to the service network
resource "aws_vpclattice_auth_policy" "service_network" {
  resource_identifier = aws_vpclattice_service_network.main.arn
  policy              = data.aws_iam_policy_document.cross_account_access.json
}

#######################
# AWS RAM Resource Share
#######################

# AWS RAM resource share for cross-account access
resource "aws_ram_resource_share" "main" {
  name                      = "${local.name_prefix}-db-access-${random_id.suffix.hex}"
  allow_external_principals = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-resource-share"
    Type = "AWS-RAM"
  })
}

# Associate the resource configuration with the RAM share
resource "aws_ram_resource_association" "resource_config" {
  resource_arn       = aws_vpclattice_resource_configuration.main.arn
  resource_share_arn = aws_ram_resource_share.main.arn
}

# Invite the consumer account to the resource share
resource "aws_ram_principal_association" "consumer_account" {
  principal          = var.consumer_account_id
  resource_share_arn = aws_ram_resource_share.main.arn
}

#######################
# S3 Bucket for Access Logs (Optional)
#######################

# S3 bucket for VPC Lattice access logs (created only if needed)
resource "aws_s3_bucket" "access_logs" {
  count = var.enable_access_logs && var.access_logs_s3_bucket == "" ? 1 : 0
  
  bucket        = "${local.name_prefix}-vpc-lattice-logs-${random_id.suffix.hex}"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-access-logs-bucket"
    Type = "Storage"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "access_logs" {
  count = var.enable_access_logs && var.access_logs_s3_bucket == "" ? 1 : 0
  
  bucket = aws_s3_bucket.access_logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  count = var.enable_access_logs && var.access_logs_s3_bucket == "" ? 1 : 0
  
  bucket = aws_s3_bucket.access_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "access_logs" {
  count = var.enable_access_logs && var.access_logs_s3_bucket == "" ? 1 : 0
  
  bucket = aws_s3_bucket.access_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Data source for VPC Lattice service principal
data "aws_iam_policy_document" "vpc_lattice_logs" {
  count = var.enable_access_logs ? 1 : 0
  
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    
    actions = [
      "s3:PutObject",
      "s3:GetBucketAcl"
    ]
    
    resources = [
      var.access_logs_s3_bucket != "" ? "arn:aws:s3:::${var.access_logs_s3_bucket}" : aws_s3_bucket.access_logs[0].arn,
      var.access_logs_s3_bucket != "" ? "arn:aws:s3:::${var.access_logs_s3_bucket}/*" : "${aws_s3_bucket.access_logs[0].arn}/*"
    ]
  }
}

# S3 bucket policy for VPC Lattice access logs
resource "aws_s3_bucket_policy" "access_logs" {
  count = var.enable_access_logs && var.access_logs_s3_bucket == "" ? 1 : 0
  
  bucket = aws_s3_bucket.access_logs[0].id
  policy = data.aws_iam_policy_document.vpc_lattice_logs[0].json
}

#######################
# VPC Lattice Access Log Subscription
#######################

# VPC Lattice access log subscription to S3
resource "aws_vpclattice_access_log_subscription" "main" {
  count = var.enable_access_logs ? 1 : 0
  
  resource_identifier = aws_vpclattice_service_network.main.arn
  
  destination_arn = var.access_logs_s3_bucket != "" ? "arn:aws:s3:::${var.access_logs_s3_bucket}" : aws_s3_bucket.access_logs[0].arn

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-access-log-subscription"
    Type = "VPC-Lattice"
  })
  
  depends_on = [
    aws_s3_bucket_policy.access_logs
  ]
}

#######################
# Consumer VPC Association (Optional)
#######################

# Optional: Associate consumer VPC with service network
# Note: This requires the Terraform execution to have access to the consumer account
resource "aws_vpclattice_service_network_vpc_association" "consumer" {
  count = var.create_consumer_vpc_association ? 1 : 0
  
  vpc_identifier             = var.consumer_vpc_id
  service_network_identifier = aws_vpclattice_service_network.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-consumer-vpc-association"
    Type = "VPC-Lattice"
  })
  
  # Use an alias provider for consumer account if needed
  # provider = aws.consumer
}