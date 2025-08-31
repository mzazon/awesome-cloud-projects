# Cross-Account Database Sharing with VPC Lattice and RDS
# This Terraform configuration creates a complete infrastructure for sharing
# RDS databases across AWS accounts using VPC Lattice resource configurations

# Data sources
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Random resources for unique naming
resource "random_id" "suffix" {
  byte_length = 3
}

resource "random_password" "db_password" {
  count   = var.create_random_password ? 1 : 0
  length  = 16
  special = true
}

# Local values for resource naming and configuration
locals {
  name_suffix = random_id.suffix.hex
  
  # Database configuration
  db_instance_id = "shared-database-${local.name_suffix}"
  db_port = var.db_engine == "mysql" ? 3306 : (var.db_engine == "postgres" ? 5432 : 3306)
  db_password = var.create_random_password ? random_password.db_password[0].result : var.db_master_password
  
  # VPC Lattice configuration
  service_network_name = "database-sharing-network-${local.name_suffix}"
  resource_config_name = "rds-resource-config-${local.name_suffix}"
  resource_gateway_name = "rds-gateway-${local.name_suffix}"
  
  # IAM and sharing configuration
  cross_account_role_name = "DatabaseAccessRole-${local.name_suffix}"
  resource_share_name = var.resource_share_name != null ? var.resource_share_name : "DatabaseResourceShare-${local.name_suffix}"
  
  # Common tags
  common_tags = merge(
    {
      Name        = "database-sharing-${local.name_suffix}"
      Environment = var.environment
      Project     = "cross-account-database-sharing"
      ManagedBy   = "terraform"
    },
    var.additional_tags
  )
}

# VPC and Networking Resources
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "database-owner-vpc-${local.name_suffix}"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "database-igw-${local.name_suffix}"
  })
}

# Subnets for RDS (minimum 2 AZs required)
resource "aws_subnet" "database_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = merge(local.common_tags, {
    Name = "database-subnet-a-${local.name_suffix}"
    Type = "Database"
  })
}

resource "aws_subnet" "database_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 2)
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = merge(local.common_tags, {
    Name = "database-subnet-b-${local.name_suffix}"
    Type = "Database"
  })
}

# Subnet for VPC Lattice resource gateway (/28 required)
resource "aws_subnet" "gateway" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 12, 48) # Creates a /28 subnet
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = merge(local.common_tags, {
    Name = "gateway-subnet-${local.name_suffix}"
    Type = "VPCLatticeGateway"
  })
}

# Route table and association
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "main-route-table-${local.name_suffix}"
  })
}

resource "aws_route_table_association" "database_a" {
  subnet_id      = aws_subnet.database_a.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "database_b" {
  subnet_id      = aws_subnet.database_b.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "gateway" {
  subnet_id      = aws_subnet.gateway.id
  route_table_id = aws_route_table.main.id
}

# Security Groups
resource "aws_security_group" "database" {
  name_prefix = "${local.db_instance_id}-sg-"
  description = "Security group for shared RDS database"
  vpc_id      = aws_vpc.main.id

  # Allow inbound traffic from VPC CIDR
  ingress {
    description = "Database access from VPC"
    from_port   = local.db_port
    to_port     = local.db_port
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  # Allow outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "database-sg-${local.name_suffix}"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "gateway" {
  name_prefix = "${local.resource_gateway_name}-sg-"
  description = "Security group for VPC Lattice resource gateway"
  vpc_id      = aws_vpc.main.id

  # Allow all traffic within VPC for resource gateway
  ingress {
    description = "All traffic from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  # Allow outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "gateway-sg-${local.name_suffix}"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# RDS Resources
resource "aws_db_subnet_group" "main" {
  name       = "${local.db_instance_id}-subnet-group"
  subnet_ids = [aws_subnet.database_a.id, aws_subnet.database_b.id]

  tags = merge(local.common_tags, {
    Name = "database-subnet-group-${local.name_suffix}"
  })
}

# Enhanced monitoring role for RDS
resource "aws_iam_role" "rds_enhanced_monitoring" {
  count = var.enable_monitoring && var.monitoring_interval > 0 ? 1 : 0
  name  = "rds-monitoring-role-${local.name_suffix}"

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

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  count      = var.enable_monitoring && var.monitoring_interval > 0 ? 1 : 0
  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# RDS Database Instance
resource "aws_db_instance" "main" {
  identifier = local.db_instance_id

  # Engine configuration
  engine         = var.db_engine
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  # Storage configuration
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage * 2
  storage_type          = "gp3"
  storage_encrypted     = var.enable_storage_encryption

  # Database configuration
  db_name  = var.db_engine == "postgres" ? "shared_db" : "shareddb"
  username = var.db_master_username
  password = local.db_password

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false

  # High availability and backup
  multi_az               = var.enable_multi_az
  backup_retention_period = var.db_backup_retention_period
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"

  # Monitoring
  monitoring_interval = var.enable_monitoring ? var.monitoring_interval : 0
  monitoring_role_arn = var.enable_monitoring && var.monitoring_interval > 0 ? aws_iam_role.rds_enhanced_monitoring[0].arn : null

  # Deletion protection
  deletion_protection = var.enable_deletion_protection
  skip_final_snapshot = !var.enable_deletion_protection

  # Performance insights
  performance_insights_enabled = true
  performance_insights_retention_period = 7

  tags = merge(local.common_tags, {
    Name = local.db_instance_id
  })

  lifecycle {
    ignore_changes = [
      password, # Ignore password changes after initial creation
    ]
  }
}

# VPC Lattice Resources

# VPC Lattice Resource Gateway
resource "aws_vpclattice_resource_gateway" "main" {
  name               = local.resource_gateway_name
  vpc_identifier     = aws_vpc.main.id
  subnet_ids         = [aws_subnet.gateway.id]
  security_group_ids = [aws_security_group.gateway.id]

  tags = merge(local.common_tags, {
    Name = local.resource_gateway_name
  })
}

# VPC Lattice Service Network
resource "aws_vpclattice_service_network" "main" {
  name      = local.service_network_name
  auth_type = "AWS_IAM"

  tags = merge(local.common_tags, {
    Name = local.service_network_name
  })
}

# Associate VPC with Service Network
resource "aws_vpclattice_service_network_vpc_association" "main" {
  vpc_identifier             = aws_vpc.main.id
  service_network_identifier = aws_vpclattice_service_network.main.id

  tags = merge(local.common_tags, {
    Name = "vpc-association-${local.name_suffix}"
  })
}

# VPC Lattice Resource Configuration
resource "aws_vpclattice_resource_configuration" "main" {
  name                                      = local.resource_config_name
  type                                      = "SINGLE"
  resource_gateway_identifier              = aws_vpclattice_resource_gateway.main.id
  protocol                                  = "TCP"
  port_ranges                              = [tostring(local.db_port)]
  allow_association_to_shareable_service_network = true

  resource_configuration_definition {
    ip_resource {
      ip_address = aws_db_instance.main.address
    }
  }

  tags = merge(local.common_tags, {
    Name = local.resource_config_name
  })

  depends_on = [aws_db_instance.main]
}

# Associate Resource Configuration with Service Network
resource "aws_vpclattice_resource_configuration_association" "main" {
  resource_configuration_identifier = aws_vpclattice_resource_configuration.main.id
  service_network_identifier        = aws_vpclattice_service_network.main.id

  tags = merge(local.common_tags, {
    Name = "resource-config-association-${local.name_suffix}"
  })
}

# IAM Resources for Cross-Account Access

# Cross-account IAM role for database access
resource "aws_iam_role" "cross_account_database_access" {
  name = local.cross_account_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.consumer_account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.external_id
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = local.cross_account_role_name
  })
}

# IAM policy for database access
resource "aws_iam_role_policy" "database_access" {
  name = "DatabaseAccessPolicy"
  role = aws_iam_role.cross_account_database_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "vpc-lattice:Invoke"
        ]
        Resource = "*"
      }
    ]
  })
}

# Service Network Authentication Policy
resource "aws_vpclattice_auth_policy" "service_network" {
  resource_identifier = aws_vpclattice_service_network.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.cross_account_database_access.arn
        }
        Action   = "vpc-lattice:Invoke"
        Resource = "*"
      }
    ]
  })
}

# AWS RAM Resource Share
resource "aws_ram_resource_share" "main" {
  name                   = local.resource_share_name
  description            = "Share VPC Lattice resource configuration for cross-account database access"
  allow_external_principals = true

  tags = merge(local.common_tags, {
    Name = local.resource_share_name
  })
}

# Associate Resource Configuration with RAM Share
resource "aws_ram_resource_association" "resource_configuration" {
  resource_arn       = aws_vpclattice_resource_configuration.main.arn
  resource_share_arn = aws_ram_resource_share.main.arn
}

# Associate Consumer Account with RAM Share
resource "aws_ram_principal_association" "consumer_account" {
  principal          = var.consumer_account_id
  resource_share_arn = aws_ram_resource_share.main.arn
}

# CloudWatch Resources

# CloudWatch Log Group for VPC Lattice
resource "aws_cloudwatch_log_group" "vpc_lattice" {
  name              = "/aws/vpc-lattice/servicenetwork/${aws_vpclattice_service_network.main.id}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "vpc-lattice-logs-${local.name_suffix}"
  })
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "database_sharing" {
  dashboard_name = "DatabaseSharingMonitoring-${local.name_suffix}"

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
            ["AWS/VpcLattice", "RequestCount", "ServiceNetwork", aws_vpclattice_service_network.main.id],
            [".", "ResponseTime", ".", "."],
            [".", "ActiveConnectionCount", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Database Access Metrics"
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
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.main.identifier],
            [".", "CPUUtilization", ".", "."],
            [".", "ReadLatency", ".", "."],
            [".", "WriteLatency", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "RDS Database Metrics"
        }
      }
    ]
  })

  depends_on = [
    aws_vpclattice_service_network.main,
    aws_db_instance.main
  ]
}

# Store database password in AWS Secrets Manager (if randomly generated)
resource "aws_secretsmanager_secret" "db_password" {
  count                   = var.create_random_password ? 1 : 0
  name                    = "rds-master-password-${local.name_suffix}"
  description             = "Master password for RDS database ${local.db_instance_id}"
  recovery_window_in_days = 7

  tags = merge(local.common_tags, {
    Name = "rds-password-${local.name_suffix}"
  })
}

resource "aws_secretsmanager_secret_version" "db_password" {
  count     = var.create_random_password ? 1 : 0
  secret_id = aws_secretsmanager_secret.db_password[0].id
  secret_string = jsonencode({
    username = aws_db_instance.main.username
    password = random_password.db_password[0].result
    engine   = aws_db_instance.main.engine
    host     = aws_db_instance.main.endpoint
    port     = aws_db_instance.main.port
    dbname   = aws_db_instance.main.db_name
  })
}