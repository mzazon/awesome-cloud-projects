#===============================================================================
# INFRASTRUCTURE OUTPUTS
#===============================================================================

output "account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = local.account_id
}

output "region" {
  description = "AWS region where resources are deployed"
  value       = local.region
}

output "resource_name_prefix" {
  description = "Common prefix used for resource naming"
  value       = local.name_prefix
}

output "resource_name_suffix" {
  description = "Random suffix added to resource names for uniqueness"
  value       = local.name_suffix
}

#===============================================================================
# S3 BUCKET OUTPUTS
#===============================================================================

output "s3_buckets" {
  description = "S3 buckets created for the financial analytics pipeline"
  value = {
    raw_data_bucket = {
      name = aws_s3_bucket.raw_data.bucket
      arn  = aws_s3_bucket.raw_data.arn
      url  = "s3://${aws_s3_bucket.raw_data.bucket}"
    }
    processed_data_bucket = {
      name = aws_s3_bucket.processed_data.bucket
      arn  = aws_s3_bucket.processed_data.arn
      url  = "s3://${aws_s3_bucket.processed_data.bucket}"
    }
    reports_bucket = {
      name = aws_s3_bucket.reports.bucket
      arn  = aws_s3_bucket.reports.arn
      url  = "s3://${aws_s3_bucket.reports.bucket}"
    }
    analytics_bucket = {
      name = aws_s3_bucket.analytics.bucket
      arn  = aws_s3_bucket.analytics.arn
      url  = "s3://${aws_s3_bucket.analytics.bucket}"
    }
  }
}

output "s3_raw_data_bucket" {
  description = "Raw cost data S3 bucket name"
  value       = aws_s3_bucket.raw_data.bucket
}

output "s3_processed_data_bucket" {
  description = "Processed cost data S3 bucket name"
  value       = aws_s3_bucket.processed_data.bucket
}

output "s3_reports_bucket" {
  description = "Reports S3 bucket name"
  value       = aws_s3_bucket.reports.bucket
}

output "s3_analytics_bucket" {
  description = "Analytics S3 bucket name"
  value       = aws_s3_bucket.analytics.bucket
}

#===============================================================================
# LAMBDA FUNCTION OUTPUTS
#===============================================================================

output "lambda_functions" {
  description = "Lambda functions created for cost data processing"
  value = {
    cost_collector = {
      function_name = aws_lambda_function.cost_collector.function_name
      arn          = aws_lambda_function.cost_collector.arn
      invoke_arn   = aws_lambda_function.cost_collector.invoke_arn
      version      = aws_lambda_function.cost_collector.version
    }
    data_transformer = {
      function_name = aws_lambda_function.data_transformer.function_name
      arn          = aws_lambda_function.data_transformer.arn
      invoke_arn   = aws_lambda_function.data_transformer.invoke_arn
      version      = aws_lambda_function.data_transformer.version
    }
  }
}

output "cost_collector_function_name" {
  description = "Cost data collector Lambda function name"
  value       = aws_lambda_function.cost_collector.function_name
}

output "data_transformer_function_name" {
  description = "Data transformer Lambda function name"
  value       = aws_lambda_function.data_transformer.function_name
}

#===============================================================================
# IAM ROLE OUTPUTS
#===============================================================================

output "iam_roles" {
  description = "IAM roles created for the financial analytics pipeline"
  value = {
    lambda_analytics_role = {
      name = aws_iam_role.lambda_analytics.name
      arn  = aws_iam_role.lambda_analytics.arn
    }
  }
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role for financial analytics"
  value       = aws_iam_role.lambda_analytics.arn
}

#===============================================================================
# EVENTBRIDGE OUTPUTS
#===============================================================================

output "eventbridge_rules" {
  description = "EventBridge rules for automated scheduling"
  value = var.enable_automated_scheduling ? {
    daily_cost_collection = {
      name                = aws_cloudwatch_event_rule.daily_cost_collection[0].name
      arn                 = aws_cloudwatch_event_rule.daily_cost_collection[0].arn
      schedule_expression = aws_cloudwatch_event_rule.daily_cost_collection[0].schedule_expression
    }
    weekly_data_transformation = {
      name                = aws_cloudwatch_event_rule.weekly_data_transformation[0].name
      arn                 = aws_cloudwatch_event_rule.weekly_data_transformation[0].arn
      schedule_expression = aws_cloudwatch_event_rule.weekly_data_transformation[0].schedule_expression
    }
  } : {}
}

output "cost_collection_schedule" {
  description = "Schedule expression for daily cost data collection"
  value       = var.cost_collection_schedule
}

output "data_transformation_schedule" {
  description = "Schedule expression for weekly data transformation"
  value       = var.data_transformation_schedule
}

#===============================================================================
# GLUE DATA CATALOG OUTPUTS
#===============================================================================

output "glue_database" {
  description = "Glue database for financial analytics"
  value = {
    name        = aws_glue_catalog_database.financial_analytics.name
    arn         = aws_glue_catalog_database.financial_analytics.arn
    description = aws_glue_catalog_database.financial_analytics.description
  }
}

output "glue_tables" {
  description = "Glue tables for financial analytics data"
  value = {
    daily_costs = {
      name          = aws_glue_catalog_table.daily_costs.name
      database_name = aws_glue_catalog_table.daily_costs.database_name
      location      = aws_glue_catalog_table.daily_costs.storage_descriptor[0].location
    }
    department_costs = {
      name          = aws_glue_catalog_table.department_costs.name
      database_name = aws_glue_catalog_table.department_costs.database_name
      location      = aws_glue_catalog_table.department_costs.storage_descriptor[0].location
    }
  }
}

output "glue_database_name" {
  description = "Name of the Glue database for financial analytics"
  value       = aws_glue_catalog_database.financial_analytics.name
}

#===============================================================================
# ATHENA OUTPUTS
#===============================================================================

output "athena_workgroup" {
  description = "Athena workgroup for financial analytics queries"
  value = {
    name        = aws_athena_workgroup.financial_analytics.name
    arn         = aws_athena_workgroup.financial_analytics.arn
    state       = aws_athena_workgroup.financial_analytics.state
    output_location = aws_athena_workgroup.financial_analytics.configuration[0].result_configuration[0].output_location
  }
}

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup for financial analytics"
  value       = aws_athena_workgroup.financial_analytics.name
}

output "athena_query_result_location" {
  description = "S3 location for Athena query results"
  value       = "s3://${aws_s3_bucket.analytics.bucket}/athena-results/"
}

#===============================================================================
# QUICKSIGHT OUTPUTS
#===============================================================================

output "quicksight_data_sources" {
  description = "QuickSight data sources for financial analytics"
  value = var.enable_quicksight_resources ? {
    s3_data_source = {
      id   = aws_quicksight_data_source.s3_financial_data[0].data_source_id
      name = aws_quicksight_data_source.s3_financial_data[0].name
      type = aws_quicksight_data_source.s3_financial_data[0].type
      arn  = aws_quicksight_data_source.s3_financial_data[0].arn
    }
    athena_data_source = {
      id   = aws_quicksight_data_source.athena_financial_data[0].data_source_id
      name = aws_quicksight_data_source.athena_financial_data[0].name
      type = aws_quicksight_data_source.athena_financial_data[0].type
      arn  = aws_quicksight_data_source.athena_financial_data[0].arn
    }
  } : {}
}

output "quicksight_console_url" {
  description = "URL to access QuickSight console"
  value       = "https://quicksight.aws.amazon.com/"
}

output "quicksight_manifest_location" {
  description = "S3 location of QuickSight manifest file"
  value       = var.enable_quicksight_resources ? "s3://${aws_s3_bucket.processed_data.bucket}/quicksight-manifest.json" : ""
}

#===============================================================================
# KMS OUTPUTS
#===============================================================================

output "kms_key" {
  description = "KMS key for financial analytics data encryption"
  value = var.enable_bucket_encryption ? {
    key_id    = aws_kms_key.financial_analytics[0].key_id
    arn       = aws_kms_key.financial_analytics[0].arn
    alias_arn = aws_kms_alias.financial_analytics[0].arn
    alias     = aws_kms_alias.financial_analytics[0].name
  } : {}
}

output "kms_key_arn" {
  description = "ARN of the KMS key for encryption"
  value       = var.enable_bucket_encryption ? aws_kms_key.financial_analytics[0].arn : null
}

#===============================================================================
# SNS OUTPUTS
#===============================================================================

output "sns_topic" {
  description = "SNS topic for cost alerts and notifications"
  value = var.enable_cost_alerts ? {
    name = aws_sns_topic.cost_alerts[0].name
    arn  = aws_sns_topic.cost_alerts[0].arn
  } : {}
}

output "cost_alerts_topic_arn" {
  description = "ARN of the SNS topic for cost alerts"
  value       = var.enable_cost_alerts ? aws_sns_topic.cost_alerts[0].arn : null
}

#===============================================================================
# CLOUDWATCH OUTPUTS
#===============================================================================

output "cloudwatch_log_groups" {
  description = "CloudWatch log groups for Lambda functions"
  value = {
    cost_collector = {
      name              = aws_cloudwatch_log_group.cost_collector.name
      arn               = aws_cloudwatch_log_group.cost_collector.arn
      retention_in_days = aws_cloudwatch_log_group.cost_collector.retention_in_days
    }
    data_transformer = {
      name              = aws_cloudwatch_log_group.data_transformer.name
      arn               = aws_cloudwatch_log_group.data_transformer.arn
      retention_in_days = aws_cloudwatch_log_group.data_transformer.retention_in_days
    }
  }
}

output "cloudwatch_alarms" {
  description = "CloudWatch alarms for monitoring"
  value = var.enable_enhanced_monitoring ? {
    cost_collector_errors = {
      name = aws_cloudwatch_metric_alarm.cost_collector_errors[0].alarm_name
      arn  = aws_cloudwatch_metric_alarm.cost_collector_errors[0].arn
    }
    data_transformer_errors = {
      name = aws_cloudwatch_metric_alarm.data_transformer_errors[0].alarm_name
      arn  = aws_cloudwatch_metric_alarm.data_transformer_errors[0].arn
    }
  } : {}
}

#===============================================================================
# DEPLOYMENT INSTRUCTIONS
#===============================================================================

output "deployment_instructions" {
  description = "Next steps to complete the financial analytics setup"
  value = {
    step_1 = "Ensure Cost Explorer is enabled in your AWS account"
    step_2 = "Set up QuickSight if not already configured: https://quicksight.aws.amazon.com/"
    step_3 = "Run initial data collection: aws lambda invoke --function-name ${aws_lambda_function.cost_collector.function_name} response.json"
    step_4 = "Run initial data transformation: aws lambda invoke --function-name ${aws_lambda_function.data_transformer.function_name} response.json"
    step_5 = "Create QuickSight datasets and dashboards using the configured data sources"
    step_6 = "Configure cost allocation tags in your AWS account for better reporting"
  }
}

output "useful_commands" {
  description = "Useful AWS CLI commands for managing the financial analytics pipeline"
  value = {
    list_s3_raw_data = "aws s3 ls s3://${aws_s3_bucket.raw_data.bucket}/raw-cost-data/ --recursive"
    list_s3_processed_data = "aws s3 ls s3://${aws_s3_bucket.processed_data.bucket}/processed-data/ --recursive"
    query_athena = "aws athena start-query-execution --query-string 'SELECT COUNT(*) FROM ${aws_glue_catalog_database.financial_analytics.name}.daily_costs;' --work-group ${aws_athena_workgroup.financial_analytics.name}"
    invoke_cost_collector = "aws lambda invoke --function-name ${aws_lambda_function.cost_collector.function_name} --payload '{\"source\": \"manual\"}' response.json"
    invoke_data_transformer = "aws lambda invoke --function-name ${aws_lambda_function.data_transformer.function_name} --payload '{\"source\": \"manual\"}' response.json"
    view_logs_cost_collector = "aws logs tail /aws/lambda/${aws_lambda_function.cost_collector.function_name} --follow"
    view_logs_data_transformer = "aws logs tail /aws/lambda/${aws_lambda_function.data_transformer.function_name} --follow"
  }
}

#===============================================================================
# COST ESTIMATION
#===============================================================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for the financial analytics infrastructure"
  value = {
    s3_storage = "~$20-50 (depends on data volume and lifecycle policies)"
    lambda_executions = "~$5-15 (daily collection + weekly transformation)"
    athena_queries = "~$10-30 (depends on query frequency and data scanned)"
    quicksight = "~$18-35 per user (Standard: $18, Enterprise: $35)"
    cloudwatch_logs = "~$1-5 (depends on log retention and volume)"
    kms = "~$1 (key usage charges)"
    total_estimated = "~$55-136 per month (excluding QuickSight user costs)"
    note = "Costs vary based on data volume, query frequency, and usage patterns"
  }
}

#===============================================================================
# SECURITY CONSIDERATIONS
#===============================================================================

output "security_features" {
  description = "Security features implemented in the financial analytics pipeline"
  value = {
    encryption_at_rest = var.enable_bucket_encryption ? "Enabled with KMS" : "Disabled"
    encryption_in_transit = "Enabled for all AWS service communications"
    iam_least_privilege = "Lambda functions have minimal required permissions"
    s3_public_access_blocked = "All S3 buckets block public access"
    cloudwatch_monitoring = var.enable_enhanced_monitoring ? "Enhanced monitoring enabled" : "Basic monitoring"
    vpc_endpoints = "Consider adding VPC endpoints for enhanced security (not included)"
    cost_alerts = var.enable_cost_alerts ? "SNS alerts configured" : "No alerts configured"
  }
}

#===============================================================================
# TROUBLESHOOTING
#===============================================================================

output "troubleshooting_resources" {
  description = "Resources for troubleshooting the financial analytics pipeline"
  value = {
    cloudwatch_logs_urls = {
      cost_collector = "https://console.aws.amazon.com/cloudwatch/home?region=${local.region}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.cost_collector.name, "/", "$252F")}"
      data_transformer = "https://console.aws.amazon.com/cloudwatch/home?region=${local.region}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.data_transformer.name, "/", "$252F")}"
    }
    lambda_console_urls = {
      cost_collector = "https://console.aws.amazon.com/lambda/home?region=${local.region}#/functions/${aws_lambda_function.cost_collector.function_name}"
      data_transformer = "https://console.aws.amazon.com/lambda/home?region=${local.region}#/functions/${aws_lambda_function.data_transformer.function_name}"
    }
    athena_console_url = "https://console.aws.amazon.com/athena/home?region=${local.region}#/workgroup/${aws_athena_workgroup.financial_analytics.name}"
    s3_console_urls = {
      raw_data = "https://console.aws.amazon.com/s3/buckets/${aws_s3_bucket.raw_data.bucket}"
      processed_data = "https://console.aws.amazon.com/s3/buckets/${aws_s3_bucket.processed_data.bucket}"
    }
    common_issues = {
      no_cost_data = "Ensure Cost Explorer is enabled and Lambda has proper IAM permissions"
      quicksight_setup = "QuickSight must be set up separately through the console"
      athena_permissions = "Verify Athena has access to S3 buckets and Glue catalog"
      lambda_timeouts = "Increase timeout values if processing large amounts of data"
    }
  }
}