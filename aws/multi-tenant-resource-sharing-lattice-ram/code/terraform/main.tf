# Data sources for AWS account information and existing resources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate unique resource names using random suffix
  resource_prefix    = "${var.project_name}-${var.environment}"
  resource_suffix    = lower(random_id.suffix.hex)
  service_network_name = var.service_network_name != "" ? var.service_network_name : "${local.resource_prefix}-network-${local.resource_suffix}"
  rds_identifier     = "${local.resource_prefix}-db-${local.resource_suffix}"
  ram_share_name     = "${local.resource_prefix}-share-${local.resource_suffix}"
  
  # Default tags for all resources
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Purpose     = "VPCLattice-RAM-MultiTenant"
    },
    var.additional_tags
  )
  
  # Determine database port based on engine
  db_port = var.db_port != 3306 ? var.db_port : (
    var.db_engine == "postgres" || var.db_engine == "aurora-postgresql" ? 5432 : 3306
  )
}

# Get default VPC if not specified
data "aws_vpc" "selected" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

data "aws_vpc" "existing" {
  count = var.vpc_id != "" ? 1 : 0
  id    = var.vpc_id
}

locals {
  vpc_id = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.selected[0].id
}

# Get subnets for RDS deployment
data "aws_subnets" "selected" {
  count = length(var.subnet_ids) == 0 ? 1 : 0
  
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  
  filter {
    name   = "availability-zone"
    values = data.aws_availability_zones.available.names
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.selected[0].ids
}

#------------------------------------------------------------------------------
# VPC Lattice Service Network
#------------------------------------------------------------------------------

# VPC Lattice Service Network
resource "aws_vpclattice_service_network" "main" {
  name      = local.service_network_name
  auth_type = var.auth_type
  
  tags = merge(
    local.common_tags,
    {
      Name = local.service_network_name
      Type = "ServiceNetwork"
    }
  )
}

# Associate VPC with Service Network
resource "aws_vpclattice_service_network_vpc_association" "main" {
  vpc_identifier             = local.vpc_id
  service_network_identifier = aws_vpclattice_service_network.main.id
  
  tags = merge(
    local.common_tags,
    {
      Name = "${local.service_network_name}-vpc-association"
      Type = "VPCAssociation"
    }
  )
}

#------------------------------------------------------------------------------
# RDS Database Instance and Related Resources
#------------------------------------------------------------------------------

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${local.rds_identifier}-subnet-group"
  subnet_ids = slice(local.subnet_ids, 0, min(2, length(local.subnet_ids)))
  
  tags = merge(
    local.common_tags,
    {
      Name = "${local.rds_identifier}-subnet-group"
      Type = "DBSubnetGroup"
    }
  )
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name        = "${local.rds_identifier}-sg"
  description = "Security group for shared RDS database"
  vpc_id      = local.vpc_id
  
  # Allow database access from within the VPC
  ingress {
    description = "Database access from VPC"
    from_port   = local.db_port
    to_port     = local.db_port
    protocol    = "tcp"
    cidr_blocks = var.vpc_id != "" ? [data.aws_vpc.existing[0].cidr_block] : [data.aws_vpc.selected[0].cidr_block]
  }
  
  # Allow self-referencing for security group rules
  ingress {
    description = "Self-referencing rule"
    from_port   = local.db_port
    to_port     = local.db_port
    protocol    = "tcp"
    self        = true
  }
  
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(
    local.common_tags,
    {
      Name = "${local.rds_identifier}-sg"
      Type = "SecurityGroup"
    }
  )
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier = local.rds_identifier
  
  # Engine configuration
  engine                = var.db_engine
  engine_version       = var.db_engine_version != "" ? var.db_engine_version : null
  instance_class       = var.db_instance_class
  allocated_storage    = var.db_allocated_storage
  storage_encrypted    = var.db_storage_encrypted
  
  # Database configuration
  db_name  = replace(local.resource_prefix, "-", "")
  username = var.db_master_username
  port     = local.db_port
  
  # Password management
  manage_master_user_password = var.db_manage_master_user_password
  password                   = var.db_manage_master_user_password ? null : var.db_master_user_password
  
  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = var.db_publicly_accessible
  multi_az              = var.db_multi_az
  
  # Backup configuration
  backup_retention_period = var.db_backup_retention_period
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  # Deletion protection and final snapshot
  deletion_protection       = false
  skip_final_snapshot      = true
  delete_automated_backups = true
  
  tags = merge(
    local.common_tags,
    {
      Name        = local.rds_identifier
      Type        = "Database"
      Purpose     = "SharedResource"
      Environment = "Multi-Tenant"
    }
  )
  
  depends_on = [aws_db_subnet_group.main, aws_security_group.rds]
}

#------------------------------------------------------------------------------
# VPC Lattice Resource Configuration
#------------------------------------------------------------------------------

# Resource Configuration for RDS Database
resource "aws_vpclattice_resource_configuration" "database" {
  name                                          = "${local.rds_identifier}-config"
  type                                         = "SINGLE"
  resource_gateway_identifier                  = local.vpc_id
  allow_association_to_shareable_service_network = true
  port_ranges                                  = var.resource_config_port_ranges
  protocol                                     = var.resource_config_protocol
  
  resource_configuration_definition {
    ip_resource {
      ip_address = aws_db_instance.main.address
    }
  }
  
  tags = merge(
    local.common_tags,
    {
      Name = "${local.rds_identifier}-config"
      Type = "ResourceConfiguration"
    }
  )
  
  depends_on = [aws_db_instance.main]
}

# Associate Resource Configuration with Service Network
resource "aws_vpclattice_resource_configuration_association" "database" {
  resource_configuration_identifier = aws_vpclattice_resource_configuration.database.id
  service_network_identifier       = aws_vpclattice_service_network.main.id
  
  tags = merge(
    local.common_tags,
    {
      Name = "${local.rds_identifier}-association"
      Type = "ResourceConfigurationAssociation"
    }
  )
}

#------------------------------------------------------------------------------
# AWS RAM Resource Share
#------------------------------------------------------------------------------

# RAM Resource Share for Service Network
resource "aws_ram_resource_share" "main" {
  count = length(var.ram_share_principals) > 0 ? 1 : 0
  
  name                      = local.ram_share_name
  allow_external_principals = var.ram_allow_external_principals
  
  tags = merge(
    local.common_tags,
    {
      Name    = local.ram_share_name
      Type    = "ResourceShare"
      Purpose = "MultiTenantSharing"
    }
  )
}

# Associate Service Network with RAM Resource Share
resource "aws_ram_resource_association" "service_network" {
  count = length(var.ram_share_principals) > 0 ? 1 : 0
  
  resource_arn       = aws_vpclattice_service_network.main.arn
  resource_share_arn = aws_ram_resource_share.main[0].arn
}

# Associate principals with RAM Resource Share
resource "aws_ram_principal_association" "main" {
  count = length(var.ram_share_principals)
  
  principal          = var.ram_share_principals[count.index]
  resource_share_arn = aws_ram_resource_share.main[0].arn
}

#------------------------------------------------------------------------------
# VPC Lattice Authentication Policy
#------------------------------------------------------------------------------

# Authentication Policy for Service Network
resource "aws_vpclattice_auth_policy" "main" {
  resource_identifier = aws_vpclattice_service_network.main.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = "vpc-lattice-svcs:Invoke"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:PrincipalTag/Team" = var.tenant_teams
          }
          DateGreaterThan = {
            "aws:CurrentTime" = "2025-01-01T00:00:00Z"
          }
          IpAddress = {
            "aws:SourceIp" = var.allowed_ip_ranges
          }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "vpc-lattice-svcs:Invoke"
        Resource = "*"
      }
    ]
  })
  
  depends_on = [aws_vpclattice_service_network.main]
}

#------------------------------------------------------------------------------
# IAM Roles for Tenant Teams
#------------------------------------------------------------------------------

# IAM Trust Policy Document for Team Roles
data "aws_iam_policy_document" "team_trust_policy" {
  count = length(var.tenant_teams)
  
  statement {
    effect = "Allow"
    
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    
    actions = ["sts:AssumeRole"]
    
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = ["${var.tenant_teams[count.index]}-Access"]
    }
  }
}

# IAM Roles for each tenant team
resource "aws_iam_role" "team_roles" {
  count = length(var.tenant_teams)
  
  name               = "${var.tenant_teams[count.index]}-DatabaseAccess-${local.resource_suffix}"
  assume_role_policy = data.aws_iam_policy_document.team_trust_policy[count.index].json
  
  tags = merge(
    local.common_tags,
    {
      Name    = "${var.tenant_teams[count.index]}-DatabaseAccess-${local.resource_suffix}"
      Team    = var.tenant_teams[count.index]
      Purpose = "DatabaseAccess"
      Type    = "IAMRole"
    }
  )
}

# Attach VPC Lattice invoke policy to team roles
resource "aws_iam_role_policy_attachment" "team_roles_lattice_policy" {
  count = length(var.tenant_teams)
  
  role       = aws_iam_role.team_roles[count.index].name
  policy_arn = "arn:aws:iam::aws:policy/VPCLatticeServicesInvokeAccess"
}

# VPC Lattice Service Role
resource "aws_iam_role" "vpc_lattice_service_role" {
  name = "VPCLatticeServiceRole-${local.resource_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-lattice.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = merge(
    local.common_tags,
    {
      Name = "VPCLatticeServiceRole-${local.resource_suffix}"
      Type = "ServiceRole"
    }
  )
}

#------------------------------------------------------------------------------
# CloudTrail for Audit Logging
#------------------------------------------------------------------------------

# S3 Bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail_logs" {
  count = var.enable_cloudtrail ? 1 : 0
  
  bucket = var.cloudtrail_s3_bucket_name != "" ? var.cloudtrail_s3_bucket_name : "lattice-audit-logs-${local.resource_suffix}"
  
  tags = merge(
    local.common_tags,
    {
      Name = "CloudTrail Audit Logs"
      Type = "AuditBucket"
    }
  )
}

# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 Bucket public access block
resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket policy for CloudTrail
data "aws_iam_policy_document" "cloudtrail_bucket_policy" {
  count = var.enable_cloudtrail ? 1 : 0
  
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail_logs[0].arn]
    
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = ["arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/VPCLatticeAuditTrail-${local.resource_suffix}"]
    }
  }
  
  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail_logs[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = ["arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/VPCLatticeAuditTrail-${local.resource_suffix}"]
    }
  }
}

# Apply bucket policy
resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id
  policy = data.aws_iam_policy_document.cloudtrail_bucket_policy[0].json
}

# CloudTrail
resource "aws_cloudtrail" "main" {
  count = var.enable_cloudtrail ? 1 : 0
  
  name           = "VPCLatticeAuditTrail-${local.resource_suffix}"
  s3_bucket_name = aws_s3_bucket.cloudtrail_logs[0].bucket
  
  include_global_service_events = var.cloudtrail_include_global_service_events
  is_multi_region_trail        = var.cloudtrail_is_multi_region_trail
  enable_log_file_validation   = var.cloudtrail_enable_log_file_validation
  
  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    exclude_management_event_sources = []
  }
  
  tags = merge(
    local.common_tags,
    {
      Name = "VPCLatticeAuditTrail-${local.resource_suffix}"
      Type = "AuditTrail"
    }
  )
  
  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
}