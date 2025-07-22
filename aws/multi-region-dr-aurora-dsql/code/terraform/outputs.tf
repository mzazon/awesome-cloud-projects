# Output values for Aurora DSQL multi-region disaster recovery infrastructure

# ========================================
# Aurora DSQL Cluster Information
# ========================================

output "primary_cluster_id" {
  description = "Aurora DSQL primary cluster identifier"
  value       = aws_dsql_cluster.primary.cluster_identifier
}

output "primary_cluster_arn" {
  description = "Aurora DSQL primary cluster ARN"
  value       = aws_dsql_cluster.primary.arn
}

output "primary_cluster_status" {
  description = "Aurora DSQL primary cluster status"
  value       = aws_dsql_cluster.primary.status
}

output "secondary_cluster_id" {
  description = "Aurora DSQL secondary cluster identifier"
  value       = aws_dsql_cluster.secondary.cluster_identifier
}

output "secondary_cluster_arn" {
  description = "Aurora DSQL secondary cluster ARN"
  value       = aws_dsql_cluster.secondary.arn
}

output "secondary_cluster_status" {
  description = "Aurora DSQL secondary cluster status"
  value       = aws_dsql_cluster.secondary.status
}

output "cluster_configuration" {
  description = "Aurora DSQL cluster configuration summary"
  value = {
    primary = {
      id         = aws_dsql_cluster.primary.cluster_identifier
      arn        = aws_dsql_cluster.primary.arn
      region     = var.primary_region
      status     = aws_dsql_cluster.primary.status
    }
    secondary = {
      id         = aws_dsql_cluster.secondary.cluster_identifier
      arn        = aws_dsql_cluster.secondary.arn
      region     = var.secondary_region
      status     = aws_dsql_cluster.secondary.status
    }
    witness_region = var.witness_region
  }
}

# ========================================
# SNS Topic Information
# ========================================

output "primary_sns_topic_arn" {
  description = "SNS topic ARN for primary region alerts"
  value       = aws_sns_topic.primary.arn
}

output "secondary_sns_topic_arn" {
  description = "SNS topic ARN for secondary region alerts"
  value       = aws_sns_topic.secondary.arn
}

output "sns_topics" {
  description = "SNS topic configuration summary"
  value = {
    primary = {
      arn    = aws_sns_topic.primary.arn
      name   = aws_sns_topic.primary.name
      region = var.primary_region
    }
    secondary = {
      arn    = aws_sns_topic.secondary.arn
      name   = aws_sns_topic.secondary.name
      region = var.secondary_region
    }
  }
}

# ========================================
# Lambda Function Information
# ========================================

output "primary_lambda_function_arn" {
  description = "Lambda function ARN for primary region monitoring"
  value       = aws_lambda_function.primary.arn
}

output "primary_lambda_function_name" {
  description = "Lambda function name for primary region monitoring"
  value       = aws_lambda_function.primary.function_name
}

output "secondary_lambda_function_arn" {
  description = "Lambda function ARN for secondary region monitoring"
  value       = aws_lambda_function.secondary.arn
}

output "secondary_lambda_function_name" {
  description = "Lambda function name for secondary region monitoring"
  value       = aws_lambda_function.secondary.function_name
}

output "lambda_execution_role_arn" {
  description = "IAM role ARN for Lambda function execution"
  value       = aws_iam_role.lambda_execution.arn
}

output "lambda_functions" {
  description = "Lambda function configuration summary"
  value = {
    primary = {
      arn           = aws_lambda_function.primary.arn
      function_name = aws_lambda_function.primary.function_name
      region        = var.primary_region
      runtime       = aws_lambda_function.primary.runtime
      timeout       = aws_lambda_function.primary.timeout
      memory_size   = aws_lambda_function.primary.memory_size
    }
    secondary = {
      arn           = aws_lambda_function.secondary.arn
      function_name = aws_lambda_function.secondary.function_name
      region        = var.secondary_region
      runtime       = aws_lambda_function.secondary.runtime
      timeout       = aws_lambda_function.secondary.timeout
      memory_size   = aws_lambda_function.secondary.memory_size
    }
    execution_role_arn = aws_iam_role.lambda_execution.arn
  }
}

# ========================================
# EventBridge Configuration
# ========================================

output "primary_eventbridge_rule_arn" {
  description = "EventBridge rule ARN for primary region monitoring"
  value       = aws_cloudwatch_event_rule.primary.arn
}

output "secondary_eventbridge_rule_arn" {
  description = "EventBridge rule ARN for secondary region monitoring"
  value       = aws_cloudwatch_event_rule.secondary.arn
}

output "eventbridge_rules" {
  description = "EventBridge rule configuration summary"
  value = {
    primary = {
      arn                 = aws_cloudwatch_event_rule.primary.arn
      name                = aws_cloudwatch_event_rule.primary.name
      schedule_expression = aws_cloudwatch_event_rule.primary.schedule_expression
      region              = var.primary_region
      state               = aws_cloudwatch_event_rule.primary.state
    }
    secondary = {
      arn                 = aws_cloudwatch_event_rule.secondary.arn
      name                = aws_cloudwatch_event_rule.secondary.name
      schedule_expression = aws_cloudwatch_event_rule.secondary.schedule_expression
      region              = var.secondary_region
      state               = aws_cloudwatch_event_rule.secondary.state
    }
  }
}

# ========================================
# CloudWatch Monitoring
# ========================================

output "cloudwatch_dashboard_name" {
  description = "CloudWatch dashboard name for disaster recovery monitoring"
  value       = aws_cloudwatch_dashboard.dr_dashboard.dashboard_name
}

output "cloudwatch_dashboard_url" {
  description = "CloudWatch dashboard URL for disaster recovery monitoring"
  value       = "https://${var.primary_region}.console.aws.amazon.com/cloudwatch/home?region=${var.primary_region}#dashboards:name=${aws_cloudwatch_dashboard.dr_dashboard.dashboard_name}"
}

output "cloudwatch_log_groups" {
  description = "CloudWatch log groups for Lambda functions"
  value = {
    primary   = aws_cloudwatch_log_group.primary.name
    secondary = aws_cloudwatch_log_group.secondary.name
  }
}

output "cloudwatch_metric_namespace" {
  description = "CloudWatch namespace for custom Aurora DSQL metrics"
  value       = var.cloudwatch_metric_namespace
}

# ========================================
# CloudWatch Alarms
# ========================================

output "cloudwatch_alarms" {
  description = "CloudWatch alarm configuration summary"
  value = {
    lambda_errors_primary = {
      name   = aws_cloudwatch_metric_alarm.lambda_errors_primary.alarm_name
      arn    = aws_cloudwatch_metric_alarm.lambda_errors_primary.arn
      region = var.primary_region
    }
    lambda_errors_secondary = {
      name   = aws_cloudwatch_metric_alarm.lambda_errors_secondary.alarm_name
      arn    = aws_cloudwatch_metric_alarm.lambda_errors_secondary.arn
      region = var.secondary_region
    }
    cluster_health = {
      name   = aws_cloudwatch_metric_alarm.cluster_health.alarm_name
      arn    = aws_cloudwatch_metric_alarm.cluster_health.arn
      region = var.primary_region
    }
    eventbridge_failures = {
      name   = aws_cloudwatch_metric_alarm.eventbridge_failures.alarm_name
      arn    = aws_cloudwatch_metric_alarm.eventbridge_failures.arn
      region = var.primary_region
    }
  }
}

# ========================================
# Security and Encryption
# ========================================

output "kms_keys" {
  description = "KMS keys used for encryption"
  value = var.enable_sns_encryption ? {
    sns_primary = {
      arn   = aws_kms_key.sns_primary[0].arn
      alias = aws_kms_alias.sns_primary[0].name
    }
    sns_secondary = {
      arn   = aws_kms_key.sns_secondary[0].arn
      alias = aws_kms_alias.sns_secondary[0].name
    }
  } : {}
  sensitive = true
}

# ========================================
# Resource Naming and Tagging
# ========================================

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "resource_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# ========================================
# Deployment Information
# ========================================

output "deployment_regions" {
  description = "AWS regions used for deployment"
  value = {
    primary   = var.primary_region
    secondary = var.secondary_region
    witness   = var.witness_region
  }
}

output "deployment_summary" {
  description = "Comprehensive deployment summary"
  value = {
    account_id = data.aws_caller_identity.current.account_id
    regions = {
      primary   = var.primary_region
      secondary = var.secondary_region
      witness   = var.witness_region
    }
    clusters = {
      primary   = aws_dsql_cluster.primary.cluster_identifier
      secondary = aws_dsql_cluster.secondary.cluster_identifier
    }
    monitoring = {
      dashboard_name     = aws_cloudwatch_dashboard.dr_dashboard.dashboard_name
      dashboard_url      = "https://${var.primary_region}.console.aws.amazon.com/cloudwatch/home?region=${var.primary_region}#dashboards:name=${aws_cloudwatch_dashboard.dr_dashboard.dashboard_name}"
      metric_namespace   = var.cloudwatch_metric_namespace
      monitoring_schedule = var.monitoring_schedule
    }
    alerting = {
      primary_sns_topic   = aws_sns_topic.primary.arn
      secondary_sns_topic = aws_sns_topic.secondary.arn
      email_configured    = var.sns_email_endpoint != ""
    }
    lambda_functions = {
      primary   = aws_lambda_function.primary.function_name
      secondary = aws_lambda_function.secondary.function_name
    }
    eventbridge_rules = {
      primary   = aws_cloudwatch_event_rule.primary.name
      secondary = aws_cloudwatch_event_rule.secondary.name
    }
  }
}

# ========================================
# Validation Commands
# ========================================

output "validation_commands" {
  description = "CLI commands for validating the deployment"
  value = {
    check_primary_cluster = "aws dsql get-cluster --region ${var.primary_region} --identifier ${aws_dsql_cluster.primary.cluster_identifier}"
    check_secondary_cluster = "aws dsql get-cluster --region ${var.secondary_region} --identifier ${aws_dsql_cluster.secondary.cluster_identifier}"
    invoke_primary_lambda = "aws lambda invoke --region ${var.primary_region} --function-name ${aws_lambda_function.primary.function_name} --payload '{}' /tmp/primary_response.json"
    invoke_secondary_lambda = "aws lambda invoke --region ${var.secondary_region} --function-name ${aws_lambda_function.secondary.function_name} --payload '{}' /tmp/secondary_response.json"
    test_primary_sns = "aws sns publish --region ${var.primary_region} --topic-arn ${aws_sns_topic.primary.arn} --subject 'Test Alert' --message 'Test message from primary region'"
    test_secondary_sns = "aws sns publish --region ${var.secondary_region} --topic-arn ${aws_sns_topic.secondary.arn} --subject 'Test Alert' --message 'Test message from secondary region'"
    view_dashboard = "https://${var.primary_region}.console.aws.amazon.com/cloudwatch/home?region=${var.primary_region}#dashboards:name=${aws_cloudwatch_dashboard.dr_dashboard.dashboard_name}"
  }
}

# ========================================
# Next Steps and Documentation
# ========================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Verify Aurora DSQL cluster status in both regions using the validation commands",
    "2. Test Lambda function execution manually using the provided invoke commands",
    "3. Configure Aurora DSQL cluster peering using AWS CLI or console (when available in Terraform)",
    "4. Set up email subscriptions for SNS topics if not configured during deployment",
    "5. Review CloudWatch dashboard and customize metrics as needed",
    "6. Test disaster recovery procedures in a non-production environment",
    "7. Document runbooks for disaster recovery scenarios",
    "8. Schedule regular disaster recovery testing",
    "9. Monitor CloudWatch alarms and adjust thresholds as needed",
    "10. Review and optimize costs using AWS Cost Explorer"
  ]
}

output "documentation_links" {
  description = "Useful documentation links for Aurora DSQL and disaster recovery"
  value = {
    aurora_dsql_docs = "https://docs.aws.amazon.com/aurora-dsql/latest/userguide/what-is-aurora-dsql.html"
    disaster_recovery_guide = "https://docs.aws.amazon.com/aurora-dsql/latest/userguide/disaster-recovery-resiliency.html"
    eventbridge_docs = "https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-what-is.html"
    lambda_best_practices = "https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html"
    cloudwatch_custom_metrics = "https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/publishingMetrics.html"
    well_architected_security = "https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html"
  }
}