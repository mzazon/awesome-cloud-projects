# Aurora Global Database Multi-Master Replication Infrastructure
# This configuration creates a global Aurora database with write forwarding capabilities
# across multiple AWS regions for high availability and low-latency access

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent resource naming and tagging
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  
  # Global database and cluster identifiers
  global_db_identifier       = "${local.name_prefix}-global-${random_string.suffix.result}"
  primary_cluster_id         = "${local.name_prefix}-primary-${random_string.suffix.result}"
  secondary_cluster_eu_id    = "${local.name_prefix}-eu-${random_string.suffix.result}"
  secondary_cluster_asia_id  = "${local.name_prefix}-asia-${random_string.suffix.result}"
  
  # Dashboard name
  dashboard_name = var.dashboard_name != null ? var.dashboard_name : "Aurora-Global-Database-${random_string.suffix.result}"
  
  # Common tags for all resources
  common_tags = merge(
    {
      Project           = var.project_name
      Environment       = var.environment
      GlobalDatabaseId  = local.global_db_identifier
      ManagedBy         = "terraform"
      CreatedDate       = formatdate("YYYY-MM-DD", timestamp())
    },
    var.additional_tags
  )
}

# Data source to get current caller identity
data "aws_caller_identity" "current" {}

# Data source to get availability zones for each region
data "aws_availability_zones" "primary" {
  provider = aws.primary
  state    = "available"
}

data "aws_availability_zones" "secondary_eu" {
  provider = aws.secondary_eu
  state    = "available"
}

data "aws_availability_zones" "secondary_asia" {
  provider = aws.secondary_asia
  state    = "available"
}

# Aurora Global Database
# This is the foundational resource that enables cross-region replication
resource "aws_rds_global_cluster" "global_database" {
  provider = aws.primary
  
  global_cluster_identifier = local.global_db_identifier
  engine                   = var.db_engine
  engine_version           = var.engine_version
  deletion_protection      = var.deletion_protection
  storage_encrypted        = var.storage_encrypted
  
  tags = merge(
    local.common_tags,
    {
      Name        = local.global_db_identifier
      Component   = "global-database"
      Description = "Aurora Global Database for multi-region replication"
    }
  )
}

# Primary Aurora Cluster (us-east-1)
# The primary cluster handles all write operations and serves as the source of truth
resource "aws_rds_cluster" "primary" {
  provider = aws.primary
  
  cluster_identifier              = local.primary_cluster_id
  global_cluster_identifier       = aws_rds_global_cluster.global_database.id
  engine                         = var.db_engine
  engine_version                 = var.engine_version
  database_name                  = var.db_engine == "aurora-mysql" ? "ecommerce" : "ecommerce"
  master_username                = var.master_username
  master_password                = var.master_password
  manage_master_user_password    = var.manage_master_user_password
  
  backup_retention_period        = var.backup_retention_period
  preferred_backup_window        = var.preferred_backup_window
  preferred_maintenance_window   = var.preferred_maintenance_window
  
  storage_encrypted              = var.storage_encrypted
  kms_key_id                    = var.kms_key_id
  deletion_protection           = var.deletion_protection
  
  db_subnet_group_name          = var.db_subnet_group_name
  vpc_security_group_ids        = var.vpc_security_group_ids
  
  skip_final_snapshot           = false
  final_snapshot_identifier     = "${local.primary_cluster_id}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  
  tags = merge(
    local.common_tags,
    {
      Name        = local.primary_cluster_id
      Component   = "primary-cluster"
      Region      = var.primary_region
      ClusterType = "primary"
      Description = "Primary Aurora cluster for global database"
    }
  )
  
  depends_on = [aws_rds_global_cluster.global_database]
}

# Primary Cluster Writer Instance
resource "aws_rds_cluster_instance" "primary_writer" {
  provider = aws.primary
  
  identifier              = "${local.primary_cluster_id}-writer"
  cluster_identifier      = aws_rds_cluster.primary.id
  instance_class          = var.db_instance_class
  engine                  = var.db_engine
  engine_version          = var.engine_version
  
  performance_insights_enabled          = var.enable_performance_insights
  performance_insights_retention_period = var.performance_insights_retention_period
  monitoring_interval                   = var.enable_enhanced_monitoring ? var.monitoring_interval : 0
  monitoring_role_arn                  = var.enable_enhanced_monitoring ? aws_iam_role.rds_enhanced_monitoring[0].arn : null
  
  tags = merge(
    local.common_tags,
    {
      Name        = "${local.primary_cluster_id}-writer"
      Component   = "primary-writer"
      Region      = var.primary_region
      InstanceType = "writer"
      Description = "Primary writer instance for global database"
    }
  )
}

# Primary Cluster Reader Instance(s)
resource "aws_rds_cluster_instance" "primary_reader" {
  provider = aws.primary
  count    = var.create_reader_instances ? var.reader_instance_count : 0
  
  identifier              = "${local.primary_cluster_id}-reader-${count.index + 1}"
  cluster_identifier      = aws_rds_cluster.primary.id
  instance_class          = var.db_instance_class
  engine                  = var.db_engine
  engine_version          = var.engine_version
  
  performance_insights_enabled          = var.enable_performance_insights
  performance_insights_retention_period = var.performance_insights_retention_period
  monitoring_interval                   = var.enable_enhanced_monitoring ? var.monitoring_interval : 0
  monitoring_role_arn                  = var.enable_enhanced_monitoring ? aws_iam_role.rds_enhanced_monitoring[0].arn : null
  
  tags = merge(
    local.common_tags,
    {
      Name        = "${local.primary_cluster_id}-reader-${count.index + 1}"
      Component   = "primary-reader"
      Region      = var.primary_region
      InstanceType = "reader"
      Description = "Primary reader instance for global database"
    }
  )
}

# Secondary Aurora Cluster (eu-west-1)
# European cluster with write forwarding enabled
resource "aws_rds_cluster" "secondary_eu" {
  provider = aws.secondary_eu
  
  cluster_identifier              = local.secondary_cluster_eu_id
  global_cluster_identifier       = aws_rds_global_cluster.global_database.id
  engine                         = var.db_engine
  engine_version                 = var.engine_version
  
  enable_global_write_forwarding = var.enable_global_write_forwarding
  
  storage_encrypted              = var.storage_encrypted
  kms_key_id                    = var.kms_key_id
  deletion_protection           = var.deletion_protection
  
  db_subnet_group_name          = var.db_subnet_group_name
  vpc_security_group_ids        = var.vpc_security_group_ids
  
  skip_final_snapshot           = false
  final_snapshot_identifier     = "${local.secondary_cluster_eu_id}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  
  tags = merge(
    local.common_tags,
    {
      Name        = local.secondary_cluster_eu_id
      Component   = "secondary-cluster-eu"
      Region      = var.secondary_region_eu
      ClusterType = "secondary"
      WriteForwarding = var.enable_global_write_forwarding
      Description = "European secondary Aurora cluster with write forwarding"
    }
  )
  
  depends_on = [aws_rds_cluster.primary]
}

# Secondary EU Cluster Writer Instance
resource "aws_rds_cluster_instance" "secondary_eu_writer" {
  provider = aws.secondary_eu
  
  identifier              = "${local.secondary_cluster_eu_id}-writer"
  cluster_identifier      = aws_rds_cluster.secondary_eu.id
  instance_class          = var.db_instance_class
  engine                  = var.db_engine
  engine_version          = var.engine_version
  
  performance_insights_enabled          = var.enable_performance_insights
  performance_insights_retention_period = var.performance_insights_retention_period
  monitoring_interval                   = var.enable_enhanced_monitoring ? var.monitoring_interval : 0
  monitoring_role_arn                  = var.enable_enhanced_monitoring ? aws_iam_role.rds_enhanced_monitoring_eu[0].arn : null
  
  tags = merge(
    local.common_tags,
    {
      Name        = "${local.secondary_cluster_eu_id}-writer"
      Component   = "secondary-writer-eu"
      Region      = var.secondary_region_eu
      InstanceType = "writer"
      WriteForwarding = var.enable_global_write_forwarding
      Description = "European writer instance with write forwarding"
    }
  )
}

# Secondary EU Cluster Reader Instance(s)
resource "aws_rds_cluster_instance" "secondary_eu_reader" {
  provider = aws.secondary_eu
  count    = var.create_reader_instances ? var.reader_instance_count : 0
  
  identifier              = "${local.secondary_cluster_eu_id}-reader-${count.index + 1}"
  cluster_identifier      = aws_rds_cluster.secondary_eu.id
  instance_class          = var.db_instance_class
  engine                  = var.db_engine
  engine_version          = var.engine_version
  
  performance_insights_enabled          = var.enable_performance_insights
  performance_insights_retention_period = var.performance_insights_retention_period
  monitoring_interval                   = var.enable_enhanced_monitoring ? var.monitoring_interval : 0
  monitoring_role_arn                  = var.enable_enhanced_monitoring ? aws_iam_role.rds_enhanced_monitoring_eu[0].arn : null
  
  tags = merge(
    local.common_tags,
    {
      Name        = "${local.secondary_cluster_eu_id}-reader-${count.index + 1}"
      Component   = "secondary-reader-eu"
      Region      = var.secondary_region_eu
      InstanceType = "reader"
      Description = "European reader instance for global database"
    }
  )
}

# Secondary Aurora Cluster (ap-southeast-1)
# Asian cluster with write forwarding enabled
resource "aws_rds_cluster" "secondary_asia" {
  provider = aws.secondary_asia
  
  cluster_identifier              = local.secondary_cluster_asia_id
  global_cluster_identifier       = aws_rds_global_cluster.global_database.id
  engine                         = var.db_engine
  engine_version                 = var.engine_version
  
  enable_global_write_forwarding = var.enable_global_write_forwarding
  
  storage_encrypted              = var.storage_encrypted
  kms_key_id                    = var.kms_key_id
  deletion_protection           = var.deletion_protection
  
  db_subnet_group_name          = var.db_subnet_group_name
  vpc_security_group_ids        = var.vpc_security_group_ids
  
  skip_final_snapshot           = false
  final_snapshot_identifier     = "${local.secondary_cluster_asia_id}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  
  tags = merge(
    local.common_tags,
    {
      Name        = local.secondary_cluster_asia_id
      Component   = "secondary-cluster-asia"
      Region      = var.secondary_region_asia
      ClusterType = "secondary"
      WriteForwarding = var.enable_global_write_forwarding
      Description = "Asian secondary Aurora cluster with write forwarding"
    }
  )
  
  depends_on = [aws_rds_cluster.primary]
}

# Secondary Asia Cluster Writer Instance
resource "aws_rds_cluster_instance" "secondary_asia_writer" {
  provider = aws.secondary_asia
  
  identifier              = "${local.secondary_cluster_asia_id}-writer"
  cluster_identifier      = aws_rds_cluster.secondary_asia.id
  instance_class          = var.db_instance_class
  engine                  = var.db_engine
  engine_version          = var.engine_version
  
  performance_insights_enabled          = var.enable_performance_insights
  performance_insights_retention_period = var.performance_insights_retention_period
  monitoring_interval                   = var.enable_enhanced_monitoring ? var.monitoring_interval : 0
  monitoring_role_arn                  = var.enable_enhanced_monitoring ? aws_iam_role.rds_enhanced_monitoring_asia[0].arn : null
  
  tags = merge(
    local.common_tags,
    {
      Name        = "${local.secondary_cluster_asia_id}-writer"
      Component   = "secondary-writer-asia"
      Region      = var.secondary_region_asia
      InstanceType = "writer"
      WriteForwarding = var.enable_global_write_forwarding
      Description = "Asian writer instance with write forwarding"
    }
  )
}

# Secondary Asia Cluster Reader Instance(s)
resource "aws_rds_cluster_instance" "secondary_asia_reader" {
  provider = aws.secondary_asia
  count    = var.create_reader_instances ? var.reader_instance_count : 0
  
  identifier              = "${local.secondary_cluster_asia_id}-reader-${count.index + 1}"
  cluster_identifier      = aws_rds_cluster.secondary_asia.id
  instance_class          = var.db_instance_class
  engine                  = var.db_engine
  engine_version          = var.engine_version
  
  performance_insights_enabled          = var.enable_performance_insights
  performance_insights_retention_period = var.performance_insights_retention_period
  monitoring_interval                   = var.enable_enhanced_monitoring ? var.monitoring_interval : 0
  monitoring_role_arn                  = var.enable_enhanced_monitoring ? aws_iam_role.rds_enhanced_monitoring_asia[0].arn : null
  
  tags = merge(
    local.common_tags,
    {
      Name        = "${local.secondary_cluster_asia_id}-reader-${count.index + 1}"
      Component   = "secondary-reader-asia"
      Region      = var.secondary_region_asia
      InstanceType = "reader"
      Description = "Asian reader instance for global database"
    }
  )
}

# Enhanced Monitoring IAM Role for Primary Region
resource "aws_iam_role" "rds_enhanced_monitoring" {
  provider = aws.primary
  count    = var.enable_enhanced_monitoring ? 1 : 0
  
  name = "${local.name_prefix}-rds-enhanced-monitoring-${var.primary_region}"
  
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
  
  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-rds-enhanced-monitoring-${var.primary_region}"
      Component   = "iam-role"
      Region      = var.primary_region
      Description = "IAM role for RDS enhanced monitoring in primary region"
    }
  )
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  provider   = aws.primary
  count      = var.enable_enhanced_monitoring ? 1 : 0
  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Enhanced Monitoring IAM Role for EU Region
resource "aws_iam_role" "rds_enhanced_monitoring_eu" {
  provider = aws.secondary_eu
  count    = var.enable_enhanced_monitoring ? 1 : 0
  
  name = "${local.name_prefix}-rds-enhanced-monitoring-${var.secondary_region_eu}"
  
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
  
  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-rds-enhanced-monitoring-${var.secondary_region_eu}"
      Component   = "iam-role"
      Region      = var.secondary_region_eu
      Description = "IAM role for RDS enhanced monitoring in EU region"
    }
  )
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring_eu" {
  provider   = aws.secondary_eu
  count      = var.enable_enhanced_monitoring ? 1 : 0
  role       = aws_iam_role.rds_enhanced_monitoring_eu[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Enhanced Monitoring IAM Role for Asia Region
resource "aws_iam_role" "rds_enhanced_monitoring_asia" {
  provider = aws.secondary_asia
  count    = var.enable_enhanced_monitoring ? 1 : 0
  
  name = "${local.name_prefix}-rds-enhanced-monitoring-${var.secondary_region_asia}"
  
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
  
  tags = merge(
    local.common_tags,
    {
      Name        = "${local.name_prefix}-rds-enhanced-monitoring-${var.secondary_region_asia}"
      Component   = "iam-role"
      Region      = var.secondary_region_asia
      Description = "IAM role for RDS enhanced monitoring in Asia region"
    }
  )
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring_asia" {
  provider   = aws.secondary_asia
  count      = var.enable_enhanced_monitoring ? 1 : 0
  role       = aws_iam_role.rds_enhanced_monitoring_asia[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Auto Scaling Target for Primary Cluster
resource "aws_appautoscaling_target" "primary_cluster" {
  provider = aws.primary
  count    = var.enable_auto_scaling ? 1 : 0
  
  service_namespace  = "rds"
  resource_id        = "cluster:${aws_rds_cluster.primary.cluster_identifier}"
  scalable_dimension = "rds:cluster:ReadReplicaCount"
  min_capacity       = var.auto_scaling_min_capacity
  max_capacity       = var.auto_scaling_max_capacity
  
  tags = merge(
    local.common_tags,
    {
      Name        = "${local.primary_cluster_id}-autoscaling-target"
      Component   = "auto-scaling"
      Region      = var.primary_region
      Description = "Auto scaling target for primary cluster"
    }
  )
}

# Auto Scaling Policy for Primary Cluster
resource "aws_appautoscaling_policy" "primary_cluster" {
  provider = aws.primary
  count    = var.enable_auto_scaling ? 1 : 0
  
  name               = "${local.primary_cluster_id}-autoscaling-policy"
  service_namespace  = aws_appautoscaling_target.primary_cluster[0].service_namespace
  resource_id        = aws_appautoscaling_target.primary_cluster[0].resource_id
  scalable_dimension = aws_appautoscaling_target.primary_cluster[0].scalable_dimension
  policy_type        = "TargetTrackingScaling"
  
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "RDSReaderAverageCPUUtilization"
    }
    target_value = var.auto_scaling_target_cpu
  }
}

# CloudWatch Dashboard for Global Database Monitoring
resource "aws_cloudwatch_dashboard" "global_database" {
  provider = aws.primary
  count    = var.create_cloudwatch_dashboard ? 1 : 0
  
  dashboard_name = local.dashboard_name
  
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
            ["AWS/RDS", "DatabaseConnections", "DBClusterIdentifier", aws_rds_cluster.primary.cluster_identifier],
            ["AWS/RDS", "DatabaseConnections", "DBClusterIdentifier", aws_rds_cluster.secondary_eu.cluster_identifier],
            ["AWS/RDS", "DatabaseConnections", "DBClusterIdentifier", aws_rds_cluster.secondary_asia.cluster_identifier]
          ]
          period = 300
          stat   = "Average"
          region = var.primary_region
          title  = "Global Database Connections"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/RDS", "AuroraGlobalDBReplicationLag", "DBClusterIdentifier", aws_rds_cluster.secondary_eu.cluster_identifier],
            ["AWS/RDS", "AuroraGlobalDBReplicationLag", "DBClusterIdentifier", aws_rds_cluster.secondary_asia.cluster_identifier]
          ]
          period = 300
          stat   = "Average"
          region = var.primary_region
          title  = "Global Database Replication Lag (ms)"
          yAxis = {
            left = {
              min = 0
            }
          }
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
            ["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", aws_rds_cluster.primary.cluster_identifier],
            ["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", aws_rds_cluster.secondary_eu.cluster_identifier],
            ["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", aws_rds_cluster.secondary_asia.cluster_identifier]
          ]
          period = 300
          stat   = "Average"
          region = var.primary_region
          title  = "CPU Utilization (%)"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/RDS", "ReadLatency", "DBClusterIdentifier", aws_rds_cluster.primary.cluster_identifier],
            ["AWS/RDS", "WriteLatency", "DBClusterIdentifier", aws_rds_cluster.primary.cluster_identifier],
            ["AWS/RDS", "ReadLatency", "DBClusterIdentifier", aws_rds_cluster.secondary_eu.cluster_identifier],
            ["AWS/RDS", "ReadLatency", "DBClusterIdentifier", aws_rds_cluster.secondary_asia.cluster_identifier]
          ]
          period = 300
          stat   = "Average"
          region = var.primary_region
          title  = "Database Latency (ms)"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      }
    ]
  })
  
  tags = merge(
    local.common_tags,
    {
      Name        = local.dashboard_name
      Component   = "cloudwatch-dashboard"
      Region      = var.primary_region
      Description = "CloudWatch dashboard for Aurora Global Database monitoring"
    }
  )
}