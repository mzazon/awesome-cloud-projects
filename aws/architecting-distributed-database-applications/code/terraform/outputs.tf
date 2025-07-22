# outputs.tf - Output values for the multi-region Aurora DSQL deployment

# ----- Aurora DSQL Cluster Outputs -----

output "primary_cluster_id" {
  description = "Aurora DSQL primary cluster identifier"
  value       = aws_dsql_cluster.primary.identifier
}

output "primary_cluster_arn" {
  description = "Aurora DSQL primary cluster ARN"
  value       = aws_dsql_cluster.primary.arn
}

output "primary_cluster_endpoint" {
  description = "Aurora DSQL primary cluster endpoint"
  value       = aws_dsql_cluster.primary.endpoint
  sensitive   = true
}

output "secondary_cluster_id" {
  description = "Aurora DSQL secondary cluster identifier"
  value       = aws_dsql_cluster.secondary.identifier
}

output "secondary_cluster_arn" {
  description = "Aurora DSQL secondary cluster ARN"
  value       = aws_dsql_cluster.secondary.arn
}

output "secondary_cluster_endpoint" {
  description = "Aurora DSQL secondary cluster endpoint"
  value       = aws_dsql_cluster.secondary.endpoint
  sensitive   = true
}

output "witness_region" {
  description = "Witness region used for multi-region consensus"
  value       = var.witness_region
}

output "cluster_configuration" {
  description = "Complete Aurora DSQL cluster configuration summary"
  value = {
    primary = {
      id               = aws_dsql_cluster.primary.identifier
      region           = var.primary_region
      deletion_protection = var.deletion_protection_enabled
    }
    secondary = {
      id               = aws_dsql_cluster.secondary.identifier
      region           = var.secondary_region
      deletion_protection = var.deletion_protection_enabled
    }
    witness_region     = var.witness_region
    multi_region_enabled = true
  }
}

# ----- Lambda Function Outputs -----

output "lambda_function_name_primary" {
  description = "Name of the Lambda function in primary region"
  value       = aws_lambda_function.primary.function_name
}

output "lambda_function_arn_primary" {
  description = "ARN of the Lambda function in primary region"
  value       = aws_lambda_function.primary.arn
}

output "lambda_function_name_secondary" {
  description = "Name of the Lambda function in secondary region"
  value       = aws_lambda_function.secondary.function_name
}

output "lambda_function_arn_secondary" {
  description = "ARN of the Lambda function in secondary region"
  value       = aws_lambda_function.secondary.arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

# ----- EventBridge Outputs -----

output "eventbridge_bus_name" {
  description = "Name of the custom EventBridge bus"
  value       = local.eventbridge_bus_name
}

output "eventbridge_bus_arn_primary" {
  description = "ARN of EventBridge bus in primary region"
  value       = aws_cloudwatch_event_bus.primary.arn
}

output "eventbridge_bus_arn_secondary" {
  description = "ARN of EventBridge bus in secondary region"
  value       = aws_cloudwatch_event_bus.secondary.arn
}

output "eventbridge_rule_name_primary" {
  description = "Name of EventBridge rule in primary region"
  value       = aws_cloudwatch_event_rule.transaction_events_primary.name
}

output "eventbridge_rule_name_secondary" {
  description = "Name of EventBridge rule in secondary region"
  value       = aws_cloudwatch_event_rule.transaction_events_secondary.name
}

# ----- Deployment Information -----

output "deployment_regions" {
  description = "AWS regions where resources are deployed"
  value = {
    primary   = var.primary_region
    secondary = var.secondary_region
    witness   = var.witness_region
  }
}

output "deployment_summary" {
  description = "Complete deployment summary"
  value = {
    project_name    = var.project_name
    environment     = var.environment
    deployment_id   = local.name_suffix
    deployed_at     = timestamp()
    aurora_dsql = {
      primary_cluster   = aws_dsql_cluster.primary.identifier
      secondary_cluster = aws_dsql_cluster.secondary.identifier
      witness_region    = var.witness_region
    }
    lambda_functions = {
      primary   = aws_lambda_function.primary.function_name
      secondary = aws_lambda_function.secondary.function_name
    }
    eventbridge = {
      bus_name = local.eventbridge_bus_name
      primary_region_bus = aws_cloudwatch_event_bus.primary.name
      secondary_region_bus = aws_cloudwatch_event_bus.secondary.name
    }
  }
}

# ----- Database Configuration -----

output "database_name" {
  description = "Name of the database created in Aurora DSQL clusters"
  value       = var.database_name
}

output "schema_initialization" {
  description = "Database schema initialization status"
  value = {
    enabled          = var.create_sample_schema
    primary_status   = var.create_sample_schema ? "Initialized" : "Skipped"
    secondary_status = var.create_sample_schema ? "Initialized" : "Skipped"
  }
}

# ----- Testing and Validation Outputs -----

output "test_commands" {
  description = "CLI commands for testing the deployment"
  value = {
    test_primary_read = "aws lambda invoke --region ${var.primary_region} --function-name ${aws_lambda_function.primary.function_name} --payload '{\"operation\":\"read\"}' --cli-binary-format raw-in-base64-out response.json"
    
    test_secondary_read = "aws lambda invoke --region ${var.secondary_region} --function-name ${aws_lambda_function.secondary.function_name} --payload '{\"operation\":\"read\"}' --cli-binary-format raw-in-base64-out response.json"
    
    test_primary_write = "aws lambda invoke --region ${var.primary_region} --function-name ${aws_lambda_function.primary.function_name} --payload '{\"operation\":\"write\",\"transaction_id\":\"test-001\",\"amount\":100.50,\"description\":\"Test transaction\"}' --cli-binary-format raw-in-base64-out write_response.json"
    
    test_secondary_write = "aws lambda invoke --region ${var.secondary_region} --function-name ${aws_lambda_function.secondary.function_name} --payload '{\"operation\":\"write\",\"transaction_id\":\"test-002\",\"amount\":250.75,\"description\":\"Test transaction from secondary\"}' --cli-binary-format raw-in-base64-out write_response.json"
    
    check_eventbridge_primary = "aws events list-rules --region ${var.primary_region} --event-bus-name ${local.eventbridge_bus_name}"
    
    check_eventbridge_secondary = "aws events list-rules --region ${var.secondary_region} --event-bus-name ${local.eventbridge_bus_name}"
  }
}

output "validation_endpoints" {
  description = "Endpoints and resources for validation"
  value = {
    aurora_dsql = {
      primary_endpoint   = aws_dsql_cluster.primary.endpoint
      secondary_endpoint = aws_dsql_cluster.secondary.endpoint
    }
    lambda_functions = {
      primary_function   = aws_lambda_function.primary.function_name
      secondary_function = aws_lambda_function.secondary.function_name
    }
    eventbridge = {
      primary_bus   = aws_cloudwatch_event_bus.primary.name
      secondary_bus = aws_cloudwatch_event_bus.secondary.name
    }
    logs = {
      primary_log_group   = var.enable_cloudwatch_logs ? "/aws/lambda/${aws_lambda_function.primary.function_name}" : null
      secondary_log_group = var.enable_cloudwatch_logs ? "/aws/lambda/${aws_lambda_function.secondary.function_name}" : null
    }
  }
}

# ----- Cost and Resource Information -----

output "resource_summary" {
  description = "Summary of deployed AWS resources"
  value = {
    aurora_dsql_clusters = 2
    lambda_functions    = 2
    eventbridge_buses   = 2
    eventbridge_rules   = 2
    iam_roles          = 1
    iam_policies       = 1
    cloudwatch_log_groups = var.enable_cloudwatch_logs ? 2 : 0
  }
}

output "cost_optimization_notes" {
  description = "Cost optimization recommendations"
  value = {
    aurora_dsql = "Aurora DSQL charges based on Database Processing Units (DPUs) and storage. Monitor usage through CloudWatch metrics."
    lambda = "Lambda functions are billed per request and execution time. Consider reserved concurrency for predictable workloads."
    eventbridge = "EventBridge charges per event published and cross-region data transfer. Monitor event volume."
    logs = "CloudWatch logs incur charges for ingestion and storage. Set appropriate retention periods."
    free_tier = "Aurora DSQL includes 100,000 DPUs and 1 GB storage per month in the free tier."
  }
}

# ----- Connection Information -----

output "connection_details" {
  description = "Connection details for applications (sensitive values hidden)"
  value = {
    primary_region = {
      cluster_id = aws_dsql_cluster.primary.identifier
      region     = var.primary_region
      database   = var.database_name
    }
    secondary_region = {
      cluster_id = aws_dsql_cluster.secondary.identifier
      region     = var.secondary_region
      database   = var.database_name
    }
    note = "Cluster endpoints are marked as sensitive. Use 'terraform output -raw primary_cluster_endpoint' to view."
  }
}

# ----- Monitoring and Observability -----

output "monitoring_resources" {
  description = "Monitoring and observability resources"
  value = {
    cloudwatch_logs = {
      enabled    = var.enable_cloudwatch_logs
      retention  = var.log_retention_days
      primary_log_group = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.lambda_logs_primary[0].name : null
      secondary_log_group = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.lambda_logs_secondary[0].name : null
    }
    x_ray_tracing = {
      enabled = var.enable_x_ray_tracing
    }
    recommended_dashboards = [
      "Aurora DSQL Performance Metrics",
      "Lambda Function Duration and Error Rates",
      "EventBridge Rule Invocations and Failures",
      "Cross-Region Replication Latency"
    ]
  }
}