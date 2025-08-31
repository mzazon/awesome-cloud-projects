# =========================================================================
# Terraform configuration for TCP Resource Connectivity with VPC Lattice 
# and CloudWatch
# =========================================================================

# ---------------------------------------------------------------------------
# Data Sources for Existing Resources
# ---------------------------------------------------------------------------

# Get current AWS region
data "aws_region" "current" {}

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Get default VPC for demonstration purposes
data "aws_vpc" "default" {
  default = true
}

# Get subnets from default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Get default security group
data "aws_security_group" "default" {
  name   = "default"
  vpc_id = data.aws_vpc.default.id
}

# ---------------------------------------------------------------------------
# Random Resources for Unique Naming
# ---------------------------------------------------------------------------

resource "random_id" "suffix" {
  byte_length = 3
}

# ---------------------------------------------------------------------------
# IAM Role for VPC Lattice Service
# ---------------------------------------------------------------------------

resource "aws_iam_role" "vpc_lattice_service_role" {
  name = "VPCLatticeServiceRole-${random_id.suffix.hex}"

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

  tags = var.common_tags
}

# ---------------------------------------------------------------------------
# VPC Lattice Service Network
# ---------------------------------------------------------------------------

# Create VPC Lattice service network for cross-VPC database connectivity
resource "aws_vpclattice_service_network" "database_service_network" {
  name      = "${var.service_network_name}-${random_id.suffix.hex}"
  auth_type = "AWS_IAM"

  tags = merge(var.common_tags, {
    Name        = "${var.service_network_name}-${random_id.suffix.hex}"
    Description = "Service network for cross-VPC database connectivity"
  })
}

# ---------------------------------------------------------------------------
# RDS Database Setup
# ---------------------------------------------------------------------------

# Create DB subnet group for RDS instance placement
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "${var.rds_instance_id}-${random_id.suffix.hex}-subnet-group"
  subnet_ids = data.aws_subnets.default.ids

  tags = merge(var.common_tags, {
    Name = "${var.rds_instance_id}-${random_id.suffix.hex}-subnet-group"
  })
}

# Create RDS MySQL instance for TCP connectivity testing
resource "aws_db_instance" "mysql_instance" {
  identifier             = "${var.rds_instance_id}-${random_id.suffix.hex}"
  instance_class         = var.db_instance_class
  engine                 = "mysql"
  engine_version         = var.mysql_engine_version
  username               = var.db_username
  password               = var.db_password
  allocated_storage      = var.db_allocated_storage
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [data.aws_security_group.default.id]
  publicly_accessible    = false
  port                   = var.mysql_port
  backup_retention_period = 1
  storage_encrypted      = true
  skip_final_snapshot    = true

  tags = merge(var.common_tags, {
    Name = "${var.rds_instance_id}-${random_id.suffix.hex}"
  })

  depends_on = [aws_db_subnet_group.rds_subnet_group]
}

# ---------------------------------------------------------------------------
# VPC Lattice Target Group
# ---------------------------------------------------------------------------

# Create TCP target group for database connections
resource "aws_vpclattice_target_group" "rds_tcp_targets" {
  name = "${var.target_group_name}-${random_id.suffix.hex}"
  type = "IP"

  config {
    port               = var.mysql_port
    protocol           = "TCP"
    vpc_identifier     = data.aws_vpc.default.id
    
    health_check {
      enabled                       = true
      protocol                     = "TCP"
      port                         = var.mysql_port
      health_check_interval_seconds = 30
      health_check_timeout_seconds  = 5
      healthy_threshold_count       = 2
      unhealthy_threshold_count     = 2
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.target_group_name}-${random_id.suffix.hex}"
  })
}

# Register RDS instance IP as target in the TCP target group
resource "aws_vpclattice_target_group_attachment" "rds_target_attachment" {
  target_group_identifier = aws_vpclattice_target_group.rds_tcp_targets.id

  target {
    id   = aws_db_instance.mysql_instance.address
    port = var.mysql_port
  }

  depends_on = [aws_db_instance.mysql_instance]
}

# ---------------------------------------------------------------------------
# VPC Lattice Service
# ---------------------------------------------------------------------------

# Create VPC Lattice service for database access
resource "aws_vpclattice_service" "database_service" {
  name      = "${var.database_service_name}-${random_id.suffix.hex}"
  auth_type = "AWS_IAM"

  tags = merge(var.common_tags, {
    Name = "${var.database_service_name}-${random_id.suffix.hex}"
  })
}

# Create TCP listener for MySQL connections (port 3306)
resource "aws_vpclattice_listener" "mysql_tcp_listener" {
  name               = "mysql-tcp-listener"
  protocol           = "TCP"
  port               = var.mysql_port
  service_identifier = aws_vpclattice_service.database_service.id

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.rds_tcp_targets.id
        weight                  = 100
      }
    }
  }

  tags = var.common_tags
}

# ---------------------------------------------------------------------------
# VPC Lattice Associations
# ---------------------------------------------------------------------------

# Associate database service with the service network
resource "aws_vpclattice_service_network_service_association" "database_service_association" {
  service_identifier         = aws_vpclattice_service.database_service.id
  service_network_identifier = aws_vpclattice_service_network.database_service_network.id

  tags = var.common_tags
}

# Associate VPC with service network for both application and database access
resource "aws_vpclattice_service_network_vpc_association" "vpc_association" {
  vpc_identifier             = data.aws_vpc.default.id
  service_network_identifier = aws_vpclattice_service_network.database_service_network.id
  security_group_ids         = [data.aws_security_group.default.id]

  tags = var.common_tags
}

# ---------------------------------------------------------------------------
# CloudWatch Monitoring and Alarms
# ---------------------------------------------------------------------------

# Create CloudWatch dashboard for VPC Lattice metrics
resource "aws_cloudwatch_dashboard" "vpc_lattice_dashboard" {
  dashboard_name = "VPCLattice-Database-Monitoring-${random_id.suffix.hex}"

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
            ["AWS/VpcLattice", "NewConnectionCount", "TargetGroup", aws_vpclattice_target_group.rds_tcp_targets.id],
            [".", "ActiveConnectionCount", ".", "."],
            [".", "ConnectionErrorCount", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Database Connection Metrics"
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
            ["AWS/VpcLattice", "ProcessedBytes", "TargetGroup", aws_vpclattice_target_group.rds_tcp_targets.id]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Database Traffic Volume"
        }
      }
    ]
  })
}

# Create CloudWatch alarm for connection errors
resource "aws_cloudwatch_metric_alarm" "database_connection_errors" {
  alarm_name          = "VPCLattice-Database-Connection-Errors-${random_id.suffix.hex}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ConnectionErrorCount"
  namespace           = "AWS/VpcLattice"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors vpc lattice database connection errors"
  insufficient_data_actions = []

  dimensions = {
    TargetGroup = aws_vpclattice_target_group.rds_tcp_targets.id
  }

  tags = var.common_tags
}

# Create CloudWatch alarm for high connection count
resource "aws_cloudwatch_metric_alarm" "database_high_connections" {
  alarm_name          = "VPCLattice-Database-High-Connections-${random_id.suffix.hex}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ActiveConnectionCount"
  namespace           = "AWS/VpcLattice"
  period              = "300"
  statistic           = "Average"
  threshold           = var.high_connection_threshold
  alarm_description   = "This metric monitors high database connection count"
  insufficient_data_actions = []

  dimensions = {
    TargetGroup = aws_vpclattice_target_group.rds_tcp_targets.id
  }

  tags = var.common_tags
}