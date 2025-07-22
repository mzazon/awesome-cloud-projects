# ========================================
# Dedicated Hosts Information
# ========================================

output "dedicated_hosts" {
  description = "Information about allocated Dedicated Hosts"
  value = {
    for key, host in aws_ec2_host.dedicated_hosts : key => {
      host_id           = host.id
      instance_family   = host.instance_family
      availability_zone = host.availability_zone
      auto_placement    = host.auto_placement
      host_recovery     = host.host_recovery
      license_type      = host.tags["LicenseType"]
      purpose          = host.tags["Purpose"]
      state            = host.host_resource_group_arn
    }
  }
}

output "windows_host_id" {
  description = "ID of the Windows/SQL Server Dedicated Host"
  value       = aws_ec2_host.dedicated_hosts["windows_host"].id
}

output "oracle_host_id" {
  description = "ID of the Oracle Database Dedicated Host"
  value       = aws_ec2_host.dedicated_hosts["oracle_host"].id
}

# ========================================
# License Manager Information
# ========================================

output "license_configurations" {
  description = "License Manager configuration details"
  value = {
    windows_server = {
      arn                      = aws_licensemanager_license_configuration.windows_server.arn
      name                     = aws_licensemanager_license_configuration.windows_server.name
      license_counting_type    = aws_licensemanager_license_configuration.windows_server.license_counting_type
      license_count           = aws_licensemanager_license_configuration.windows_server.license_count
      license_count_hard_limit = aws_licensemanager_license_configuration.windows_server.license_count_hard_limit
    }
    oracle_enterprise = {
      arn                      = aws_licensemanager_license_configuration.oracle_enterprise.arn
      name                     = aws_licensemanager_license_configuration.oracle_enterprise.name
      license_counting_type    = aws_licensemanager_license_configuration.oracle_enterprise.license_counting_type
      license_count           = aws_licensemanager_license_configuration.oracle_enterprise.license_count
      license_count_hard_limit = aws_licensemanager_license_configuration.oracle_enterprise.license_count_hard_limit
    }
  }
}

output "windows_license_arn" {
  description = "ARN of the Windows Server license configuration"
  value       = aws_licensemanager_license_configuration.windows_server.arn
}

output "oracle_license_arn" {
  description = "ARN of the Oracle Enterprise Edition license configuration"
  value       = aws_licensemanager_license_configuration.oracle_enterprise.arn
}

# ========================================
# Instance Information
# ========================================

output "byol_instances" {
  description = "Information about BYOL instances running on Dedicated Hosts"
  value = {
    windows_sql = {
      instance_id       = aws_instance.windows_sql.id
      instance_type     = aws_instance.windows_sql.instance_type
      availability_zone = aws_instance.windows_sql.availability_zone
      private_ip        = aws_instance.windows_sql.private_ip
      public_ip         = aws_instance.windows_sql.public_ip
      host_id          = aws_instance.windows_sql.host_id
      license_type     = aws_instance.windows_sql.tags["LicenseType"]
      application      = aws_instance.windows_sql.tags["Application"]
      state            = aws_instance.windows_sql.instance_state
    }
    oracle_db = {
      instance_id       = aws_instance.oracle_db.id
      instance_type     = aws_instance.oracle_db.instance_type
      availability_zone = aws_instance.oracle_db.availability_zone
      private_ip        = aws_instance.oracle_db.private_ip
      public_ip         = aws_instance.oracle_db.public_ip
      host_id          = aws_instance.oracle_db.host_id
      license_type     = aws_instance.oracle_db.tags["LicenseType"]
      application      = aws_instance.oracle_db.tags["Application"]
      state            = aws_instance.oracle_db.instance_state
    }
  }
}

output "windows_instance_id" {
  description = "ID of the Windows/SQL Server BYOL instance"
  value       = aws_instance.windows_sql.id
}

output "oracle_instance_id" {
  description = "ID of the Oracle Database BYOL instance"
  value       = aws_instance.oracle_db.id
}

output "windows_instance_private_ip" {
  description = "Private IP address of the Windows/SQL Server instance"
  value       = aws_instance.windows_sql.private_ip
}

output "oracle_instance_private_ip" {
  description = "Private IP address of the Oracle Database instance"
  value       = aws_instance.oracle_db.private_ip
}

# ========================================
# Security and Access Information
# ========================================

output "security_group_id" {
  description = "ID of the security group for BYOL instances"
  value       = aws_security_group.byol_instances.id
}

output "iam_instance_profile" {
  description = "IAM instance profile for EC2 instances"
  value = {
    name = aws_iam_instance_profile.ec2_profile.name
    arn  = aws_iam_instance_profile.ec2_profile.arn
    role = aws_iam_instance_profile.ec2_profile.role
  }
}

output "ec2_ssm_role_arn" {
  description = "ARN of the IAM role for EC2 Systems Manager access"
  value       = aws_iam_role.ec2_ssm_role.arn
}

# ========================================
# Monitoring and Compliance Information
# ========================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for compliance notifications"
  value       = aws_sns_topic.compliance_alerts.arn
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarms for license utilization monitoring"
  value = {
    windows_license = {
      name      = aws_cloudwatch_metric_alarm.windows_license_utilization.alarm_name
      arn       = aws_cloudwatch_metric_alarm.windows_license_utilization.arn
      threshold = aws_cloudwatch_metric_alarm.windows_license_utilization.threshold
    }
    oracle_license = {
      name      = aws_cloudwatch_metric_alarm.oracle_license_utilization.alarm_name
      arn       = aws_cloudwatch_metric_alarm.oracle_license_utilization.arn
      threshold = aws_cloudwatch_metric_alarm.oracle_license_utilization.threshold
    }
  }
}

output "compliance_dashboard_url" {
  description = "URL to the CloudWatch compliance dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.compliance_dashboard.dashboard_name}"
}

output "lambda_function_name" {
  description = "Name of the Lambda function for compliance reporting"
  value       = aws_lambda_function.compliance_report.function_name
}

# ========================================
# AWS Config Information (if enabled)
# ========================================

output "config_configuration" {
  description = "AWS Config configuration details (if enabled)"
  value = var.enable_config ? {
    recorder_name    = aws_config_configuration_recorder.recorder[0].name
    delivery_channel = aws_config_delivery_channel.channel[0].name
    config_rule_name = aws_config_config_rule.host_compliance[0].name
    s3_bucket       = aws_s3_bucket.config_bucket[0].id
  } : null
}

# ========================================
# S3 Bucket Information
# ========================================

output "s3_buckets" {
  description = "S3 buckets created for license management and compliance"
  value = {
    license_reports = {
      name   = aws_s3_bucket.license_reports.id
      arn    = aws_s3_bucket.license_reports.arn
      region = aws_s3_bucket.license_reports.region
    }
    config_bucket = var.enable_config ? {
      name   = aws_s3_bucket.config_bucket[0].id
      arn    = aws_s3_bucket.config_bucket[0].arn
      region = aws_s3_bucket.config_bucket[0].region
    } : null
  }
}

# ========================================
# Launch Template Information
# ========================================

output "launch_templates" {
  description = "Launch templates for BYOL instances"
  value = {
    windows_sql = {
      id           = aws_launch_template.windows_sql.id
      name         = aws_launch_template.windows_sql.name
      latest_version = aws_launch_template.windows_sql.latest_version
    }
    oracle_db = {
      id           = aws_launch_template.oracle_db.id
      name         = aws_launch_template.oracle_db.name
      latest_version = aws_launch_template.oracle_db.latest_version
    }
  }
}

# ========================================
# Systems Manager Information (if enabled)
# ========================================

output "ssm_association" {
  description = "Systems Manager association for inventory collection (if enabled)"
  value = var.enable_ssm_inventory ? {
    association_id = aws_ssm_association.inventory_collection[0].association_id
    name          = aws_ssm_association.inventory_collection[0].name
    schedule      = aws_ssm_association.inventory_collection[0].schedule_expression
  } : null
}

# ========================================
# Cost and Resource Summary
# ========================================

output "resource_summary" {
  description = "Summary of deployed resources for cost tracking"
  value = {
    dedicated_hosts_count     = length(aws_ec2_host.dedicated_hosts)
    instances_count          = 2
    license_configurations   = 2
    cloudwatch_alarms       = 2
    s3_buckets             = var.enable_config ? 2 : 1
    lambda_functions       = 1
    sns_topics            = 1
    security_groups       = 1
    launch_templates      = 2
    iam_roles            = var.enable_config ? 3 : 2
    aws_config_enabled   = var.enable_config
    ssm_inventory_enabled = var.enable_ssm_inventory
  }
}

# ========================================
# Connection and Access Information
# ========================================

output "connection_instructions" {
  description = "Instructions for connecting to the deployed instances"
  value = {
    windows_instance = {
      connection_method = "RDP"
      port             = 3389
      private_ip       = aws_instance.windows_sql.private_ip
      public_ip        = aws_instance.windows_sql.public_ip
      note            = "Use EC2 Instance Connect or Session Manager for secure access"
    }
    oracle_instance = {
      connection_method = "SSH"
      port             = 22
      private_ip       = aws_instance.oracle_db.private_ip
      public_ip        = aws_instance.oracle_db.public_ip
      note            = "Use EC2 Instance Connect or Session Manager for secure access"
    }
    session_manager = {
      url  = "https://console.aws.amazon.com/systems-manager/session-manager"
      note = "Use AWS Systems Manager Session Manager for secure shell access without SSH keys"
    }
  }
}

# ========================================
# Next Steps and Recommendations
# ========================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Verify Dedicated Hosts allocation: aws ec2 describe-hosts",
    "2. Check license utilization: aws license-manager list-usage-for-license-configuration",
    "3. Monitor CloudWatch dashboard for compliance metrics",
    "4. Configure SNS email subscription for compliance alerts",
    "5. Install and configure your licensed software (SQL Server, Oracle DB)",
    "6. Review AWS Config compliance rules (if enabled)",
    "7. Test Systems Manager inventory collection (if enabled)",
    "8. Set up automated compliance reporting schedule",
    "9. Review and optimize security group rules for your environment",
    "10. Configure backup and monitoring for your licensed applications"
  ]
}

# ========================================
# Compliance and Audit Information
# ========================================

output "compliance_information" {
  description = "Key information for compliance audits and license management"
  value = {
    license_tracking = {
      windows_server = {
        counting_method     = "Socket-based"
        total_licenses     = var.windows_license_count
        hard_limit_enforced = true
        dedicated_host_id   = aws_ec2_host.dedicated_hosts["windows_host"].id
      }
      oracle_enterprise = {
        counting_method     = "Core-based"
        total_licenses     = var.oracle_license_count
        hard_limit_enforced = true
        dedicated_host_id   = aws_ec2_host.dedicated_hosts["oracle_host"].id
      }
    }
    monitoring = {
      cloudwatch_dashboard = aws_cloudwatch_dashboard.compliance_dashboard.dashboard_name
      sns_notifications   = aws_sns_topic.compliance_alerts.arn
      automated_reporting = aws_lambda_function.compliance_report.function_name
      config_monitoring   = var.enable_config
    }
    audit_trail = {
      cloudtrail_enabled = "Configure CloudTrail for complete audit trail"
      config_changes     = var.enable_config ? "Tracked by AWS Config" : "Enable AWS Config for change tracking"
      license_usage      = "Tracked by AWS License Manager"
      inventory_data     = var.enable_ssm_inventory ? "Collected by Systems Manager" : "Enable SSM inventory for detailed software inventory"
    }
  }
}