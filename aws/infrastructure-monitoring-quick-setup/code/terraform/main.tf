# Infrastructure Monitoring Quick Setup with Systems Manager and CloudWatch
# This Terraform configuration deploys a comprehensive monitoring solution

# Data source for current AWS account information
data "aws_caller_identity" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent resource naming and configuration
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  resource_suffix = random_string.suffix.result
  
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Recipe      = "Systems Manager Quick Setup"
  }
}

# ============================================================================
# IAM ROLES AND POLICIES
# ============================================================================

# IAM assume role policy for Systems Manager service
data "aws_iam_policy_document" "ssm_assume_role" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# IAM role for Systems Manager service operations
resource "aws_iam_role" "ssm_service_role" {
  name               = "SSMServiceRole-${local.resource_suffix}"
  assume_role_policy = data.aws_iam_policy_document.ssm_assume_role.json
  description        = "Service role for Systems Manager operations including host management and monitoring"
  
  tags = merge(local.common_tags, {
    Name = "SSMServiceRole-${local.resource_suffix}"
  })
}

# Attach AWS managed policy for SSM managed instance core functionality
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ssm_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach AWS managed policy for CloudWatch Agent server operations
resource "aws_iam_role_policy_attachment" "cloudwatch_agent_server_policy" {
  role       = aws_iam_role.ssm_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# ============================================================================
# CLOUDWATCH AGENT CONFIGURATION
# ============================================================================

# CloudWatch Agent configuration stored in SSM Parameter Store
resource "aws_ssm_parameter" "cloudwatch_agent_config" {
  name        = "AmazonCloudWatch-Agent-Config-${local.resource_suffix}"
  type        = "String"
  description = "CloudWatch Agent configuration for comprehensive system monitoring"
  
  value = jsonencode({
    metrics = {
      namespace = var.cloudwatch_namespace
      metrics_collected = {
        cpu = {
          measurement = [
            "cpu_usage_idle",
            "cpu_usage_iowait",
            "cpu_usage_user",
            "cpu_usage_system"
          ]
          metrics_collection_interval = var.metrics_collection_interval
          totalcpu                   = false
        }
        disk = {
          measurement = [
            "used_percent",
            "free",
            "total",
            "used"
          ]
          metrics_collection_interval = var.metrics_collection_interval
          resources                  = ["*"]
          ignore_file_system_types = [
            "sysfs",
            "devtmpfs",
            "tmpfs"
          ]
        }
        mem = {
          measurement = [
            "mem_used_percent",
            "mem_available_percent",
            "mem_used",
            "mem_cached",
            "mem_total"
          ]
          metrics_collection_interval = var.metrics_collection_interval
        }
        netstat = {
          measurement = [
            "tcp_established",
            "tcp_time_wait"
          ]
          metrics_collection_interval = var.metrics_collection_interval
        }
        processes = {
          measurement = [
            "running",
            "sleeping",
            "dead"
          ]
          metrics_collection_interval = var.metrics_collection_interval
        }
      }
    }
    logs = var.enable_detailed_monitoring ? {
      logs_collected = {
        files = {
          collect_list = [
            {
              file_path      = "/var/log/messages"
              log_group_name = "/aws/systems-manager/infrastructure-${local.resource_suffix}"
              log_stream_name = "{instance_id}/messages"
              timezone       = "UTC"
            }
          ]
        }
      }
    } : {}
  })
  
  tags = merge(local.common_tags, {
    Name = "CloudWatch-Agent-Config-${local.resource_suffix}"
  })
}

# ============================================================================
# CLOUDWATCH LOG GROUPS
# ============================================================================

# Log group for Systems Manager infrastructure logs
resource "aws_cloudwatch_log_group" "infrastructure_logs" {
  name              = "/aws/systems-manager/infrastructure-${local.resource_suffix}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "Infrastructure-Logs-${local.resource_suffix}"
    Type = "SystemsManager"
  })
}

# Log group for application logs
resource "aws_cloudwatch_log_group" "application_logs" {
  name              = "/aws/ec2/application-logs-${local.resource_suffix}"
  retention_in_days = var.application_log_retention_days
  
  tags = merge(local.common_tags, {
    Name = "Application-Logs-${local.resource_suffix}"
    Type = "Application"
  })
}

# Log stream for Run Command outputs
resource "aws_cloudwatch_log_stream" "run_command_outputs" {
  name           = "run-command-outputs"
  log_group_name = aws_cloudwatch_log_group.infrastructure_logs.name
}

# ============================================================================
# CLOUDWATCH DASHBOARD
# ============================================================================

# Comprehensive monitoring dashboard for infrastructure visibility
resource "aws_cloudwatch_dashboard" "infrastructure_monitoring" {
  dashboard_name = "Infrastructure-Monitoring-${local.resource_suffix}"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        width  = 12
        height = 6
        x      = 0
        y      = 0
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization"],
            ["AWS/EC2", "NetworkIn"],
            ["AWS/EC2", "NetworkOut"],
            ["AWS/EC2", "DiskReadOps"],
            ["AWS/EC2", "DiskWriteOps"]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "EC2 Instance Performance Metrics"
          view   = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        x      = 12
        y      = 0
        properties = {
          metrics = [
            [var.cloudwatch_namespace, "mem_used_percent"],
            [var.cloudwatch_namespace, "disk_used_percent", "device", "/dev/xvda1"],
            [var.cloudwatch_namespace, "cpu_usage_active"]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "CloudWatch Agent Custom Metrics"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        x      = 0
        y      = 6
        properties = {
          metrics = [
            ["AWS/SSM-RunCommand", "CommandsSucceeded"],
            ["AWS/SSM-RunCommand", "CommandsFailed"],
            ["AWS/SSM-RunCommand", "CommandsTimedOut"]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Systems Manager Run Command Operations"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        width  = 12
        height = 6
        x      = 12
        y      = 6
        properties = {
          query   = "SOURCE '${aws_cloudwatch_log_group.infrastructure_logs.name}' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          region  = var.aws_region
          title   = "Recent Infrastructure Log Events"
          view    = "table"
        }
      }
    ]
  })
}

# ============================================================================
# CLOUDWATCH ALARMS
# ============================================================================

# High CPU utilization alarm
resource "aws_cloudwatch_metric_alarm" "high_cpu_utilization" {
  alarm_name          = "High-CPU-Utilization-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "This metric monitors ec2 cpu utilization exceeding ${var.cpu_alarm_threshold}%"
  alarm_actions       = []
  treat_missing_data  = "notBreaching"
  
  tags = merge(local.common_tags, {
    Name     = "High-CPU-Utilization-${local.resource_suffix}"
    Severity = "Warning"
  })
}

# High disk usage alarm (requires CloudWatch Agent)
resource "aws_cloudwatch_metric_alarm" "high_disk_usage" {
  count = var.enable_detailed_monitoring ? 1 : 0
  
  alarm_name          = "High-Disk-Usage-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "disk_used_percent"
  namespace           = var.cloudwatch_namespace
  period              = "300"
  statistic           = "Average"
  threshold           = var.disk_alarm_threshold
  alarm_description   = "This metric monitors disk usage exceeding ${var.disk_alarm_threshold}%"
  alarm_actions       = []
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    device = "/dev/xvda1"
  }
  
  tags = merge(local.common_tags, {
    Name     = "High-Disk-Usage-${local.resource_suffix}"
    Severity = "Critical"
  })
}

# Memory usage alarm (requires CloudWatch Agent)
resource "aws_cloudwatch_metric_alarm" "high_memory_usage" {
  count = var.enable_detailed_monitoring ? 1 : 0
  
  alarm_name          = "High-Memory-Usage-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "mem_used_percent"
  namespace           = var.cloudwatch_namespace
  period              = "300"
  statistic           = "Average"
  threshold           = 90
  alarm_description   = "This metric monitors memory usage exceeding 90%"
  alarm_actions       = []
  treat_missing_data  = "notBreaching"
  
  tags = merge(local.common_tags, {
    Name     = "High-Memory-Usage-${local.resource_suffix}"
    Severity = "Warning"
  })
}

# ============================================================================
# SYSTEMS MANAGER ASSOCIATIONS
# ============================================================================

# Daily inventory collection association
resource "aws_ssm_association" "inventory_collection" {
  count = var.enable_compliance_monitoring ? 1 : 0
  
  name             = "AWS-GatherSoftwareInventory"
  association_name = "Daily-Inventory-Collection-${local.resource_suffix}"
  schedule_expression = var.inventory_collection_schedule
  
  targets {
    key    = "tag:${var.target_tag_key}"
    values = var.target_tag_values
  }
  
  parameters = {
    applications                = "Enabled"
    awsComponents              = "Enabled"
    customInventory            = "Enabled"
    instanceDetailedInformation = "Enabled"
    networkConfig              = "Enabled"
    services                   = "Enabled"
    windowsUpdates             = "Enabled"
    windowsRoles               = "Enabled"
    windowsRegistry            = "Disabled"
  }
  
  compliance_severity = "MEDIUM"
  
  output_location {
    s3_bucket_name = null  # Will use default S3 bucket for Systems Manager
  }
}

# Weekly patch baseline scanning association
resource "aws_ssm_association" "patch_scanning" {
  count = var.enable_compliance_monitoring ? 1 : 0
  
  name             = "AWS-RunPatchBaseline"
  association_name = "Weekly-Patch-Scanning-${local.resource_suffix}"
  schedule_expression = var.patch_scan_schedule
  
  targets {
    key    = "tag:${var.target_tag_key}"
    values = var.target_tag_values
  }
  
  parameters = {
    Operation = "Scan"
  }
  
  compliance_severity = "HIGH"
  
  output_location {
    s3_bucket_name = null  # Will use default S3 bucket for Systems Manager
  }
}

# CloudWatch Agent installation and configuration association
resource "aws_ssm_association" "cloudwatch_agent_install" {
  count = var.enable_detailed_monitoring ? 1 : 0
  
  name             = "AmazonCloudWatch-ManageAgent"
  association_name = "CloudWatch-Agent-Install-${local.resource_suffix}"
  
  targets {
    key    = "tag:${var.target_tag_key}"
    values = var.target_tag_values
  }
  
  parameters = {
    action                    = "configure"
    mode                     = "ec2"
    optionalConfigurationSource = "ssm"
    optionalConfigurationLocation = aws_ssm_parameter.cloudwatch_agent_config.name
    optionalRestart          = "yes"
  }
  
  compliance_severity = "MEDIUM"
}

# ============================================================================
# PATCH BASELINES (DEFAULT CONFIGURATION)
# ============================================================================

# Default patch baseline for Amazon Linux instances
resource "aws_ssm_patch_baseline" "amazon_linux" {
  count = var.enable_compliance_monitoring ? 1 : 0
  
  name             = "Amazon-Linux-Baseline-${local.resource_suffix}"
  description      = "Default patch baseline for Amazon Linux instances"
  operating_system = "AMAZON_LINUX_2"
  
  approval_rule {
    approve_after_days  = 7
    compliance_level    = "HIGH"
    enable_non_security = true
    
    patch_filter {
      key    = "PRODUCT"
      values = ["AmazonLinux2"]
    }
    
    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security", "Bugfix", "Critical", "Important"]
    }
    
    patch_filter {
      key    = "SEVERITY"
      values = ["Critical", "Important", "Medium", "Low"]
    }
  }
  
  rejected_patches_action = "BLOCK"
  
  tags = merge(local.common_tags, {
    Name = "Amazon-Linux-Baseline-${local.resource_suffix}"
    OS   = "AmazonLinux2"
  })
}