# Outputs for Multi-Region Aurora DSQL Application Infrastructure
# This file provides essential information about deployed resources for verification and integration

# =============================================================================
# AURORA DSQL CLUSTER OUTPUTS
# =============================================================================

output "aurora_dsql_clusters" {
  description = "Aurora DSQL cluster information for both regions"
  value = {
    primary = {
      arn              = aws_dsql_cluster.primary.arn
      cluster_id       = aws_dsql_cluster.primary.cluster_identifier
      endpoint         = aws_dsql_cluster.primary.endpoint
      status           = aws_dsql_cluster.primary.status
      region           = var.primary_region
      creation_time    = aws_dsql_cluster.primary.creation_time
      witness_region   = var.witness_region
    }
    secondary = {
      arn              = aws_dsql_cluster.secondary.arn
      cluster_id       = aws_dsql_cluster.secondary.cluster_identifier
      endpoint         = aws_dsql_cluster.secondary.endpoint
      status           = aws_dsql_cluster.secondary.status
      region           = var.secondary_region
      creation_time    = aws_dsql_cluster.secondary.creation_time
      witness_region   = var.witness_region
    }
  }
}

output "primary_cluster_arn" {
  description = "ARN of the primary Aurora DSQL cluster"
  value       = aws_dsql_cluster.primary.arn
}

output "secondary_cluster_arn" {
  description = "ARN of the secondary Aurora DSQL cluster"
  value       = aws_dsql_cluster.secondary.arn
}

output "primary_cluster_endpoint" {
  description = "Endpoint of the primary Aurora DSQL cluster"
  value       = aws_dsql_cluster.primary.endpoint
}

output "secondary_cluster_endpoint" {
  description = "Endpoint of the secondary Aurora DSQL cluster"
  value       = aws_dsql_cluster.secondary.endpoint
}

output "witness_region" {
  description = "Witness region for Aurora DSQL multi-region configuration"
  value       = var.witness_region
}

# =============================================================================
# LAMBDA FUNCTION OUTPUTS
# =============================================================================

output "lambda_functions" {
  description = "Lambda function information for both regions"
  value = {
    primary = {
      function_name = aws_lambda_function.primary.function_name
      function_arn  = aws_lambda_function.primary.arn
      invoke_arn    = aws_lambda_function.primary.invoke_arn
      region        = var.primary_region
      runtime       = aws_lambda_function.primary.runtime
      timeout       = aws_lambda_function.primary.timeout
      memory_size   = aws_lambda_function.primary.memory_size
      version       = aws_lambda_function.primary.version
    }
    secondary = {
      function_name = aws_lambda_function.secondary.function_name
      function_arn  = aws_lambda_function.secondary.arn
      invoke_arn    = aws_lambda_function.secondary.invoke_arn
      region        = var.secondary_region
      runtime       = aws_lambda_function.secondary.runtime
      timeout       = aws_lambda_function.secondary.timeout
      memory_size   = aws_lambda_function.secondary.memory_size
      version       = aws_lambda_function.secondary.version
    }
  }
}

output "primary_lambda_function_name" {
  description = "Name of the primary region Lambda function"
  value       = aws_lambda_function.primary.function_name
}

output "secondary_lambda_function_name" {
  description = "Name of the secondary region Lambda function"
  value       = aws_lambda_function.secondary.function_name
}

output "lambda_execution_role_arn" {
  description = "ARN of the IAM role used by Lambda functions"
  value       = aws_iam_role.lambda_execution_role.arn
}

# =============================================================================
# API GATEWAY OUTPUTS
# =============================================================================

output "api_gateway_endpoints" {
  description = "API Gateway endpoint information for both regions"
  value = {
    primary = {
      api_id           = aws_api_gateway_rest_api.primary.id
      api_arn          = aws_api_gateway_rest_api.primary.arn
      execution_arn    = aws_api_gateway_rest_api.primary.execution_arn
      endpoint_url     = "https://${aws_api_gateway_rest_api.primary.id}.execute-api.${var.primary_region}.amazonaws.com/${var.api_gateway_stage_name}"
      health_url       = "https://${aws_api_gateway_rest_api.primary.id}.execute-api.${var.primary_region}.amazonaws.com/${var.api_gateway_stage_name}/health"
      users_url        = "https://${aws_api_gateway_rest_api.primary.id}.execute-api.${var.primary_region}.amazonaws.com/${var.api_gateway_stage_name}/users"
      region           = var.primary_region
      stage_name       = var.api_gateway_stage_name
    }
    secondary = {
      api_id           = aws_api_gateway_rest_api.secondary.id
      api_arn          = aws_api_gateway_rest_api.secondary.arn
      execution_arn    = aws_api_gateway_rest_api.secondary.execution_arn
      endpoint_url     = "https://${aws_api_gateway_rest_api.secondary.id}.execute-api.${var.secondary_region}.amazonaws.com/${var.api_gateway_stage_name}"
      health_url       = "https://${aws_api_gateway_rest_api.secondary.id}.execute-api.${var.secondary_region}.amazonaws.com/${var.api_gateway_stage_name}/health"
      users_url        = "https://${aws_api_gateway_rest_api.secondary.id}.execute-api.${var.secondary_region}.amazonaws.com/${var.api_gateway_stage_name}/users"
      region           = var.secondary_region
      stage_name       = var.api_gateway_stage_name
    }
  }
}

output "primary_api_endpoint" {
  description = "Primary region API Gateway endpoint URL"
  value       = "https://${aws_api_gateway_rest_api.primary.id}.execute-api.${var.primary_region}.amazonaws.com/${var.api_gateway_stage_name}"
}

output "secondary_api_endpoint" {
  description = "Secondary region API Gateway endpoint URL"
  value       = "https://${aws_api_gateway_rest_api.secondary.id}.execute-api.${var.secondary_region}.amazonaws.com/${var.api_gateway_stage_name}"
}

output "api_gateway_stage_name" {
  description = "API Gateway deployment stage name"
  value       = var.api_gateway_stage_name
}

# =============================================================================
# CLOUDWATCH MONITORING OUTPUTS
# =============================================================================

output "cloudwatch_log_groups" {
  description = "CloudWatch log group information for Lambda functions"
  value = {
    primary = {
      name              = aws_cloudwatch_log_group.primary_lambda_logs.name
      arn               = aws_cloudwatch_log_group.primary_lambda_logs.arn
      retention_in_days = aws_cloudwatch_log_group.primary_lambda_logs.retention_in_days
      region            = var.primary_region
    }
    secondary = {
      name              = aws_cloudwatch_log_group.secondary_lambda_logs.name
      arn               = aws_cloudwatch_log_group.secondary_lambda_logs.arn
      retention_in_days = aws_cloudwatch_log_group.secondary_lambda_logs.retention_in_days
      region            = var.secondary_region
    }
  }
}

output "primary_lambda_log_group" {
  description = "Primary region Lambda function CloudWatch log group name"
  value       = aws_cloudwatch_log_group.primary_lambda_logs.name
}

output "secondary_lambda_log_group" {
  description = "Secondary region Lambda function CloudWatch log group name"
  value       = aws_cloudwatch_log_group.secondary_lambda_logs.name
}

# =============================================================================
# ROUTE 53 HEALTH CHECK OUTPUTS
# =============================================================================

output "route53_health_checks" {
  description = "Route 53 health check information (if enabled)"
  value = var.create_route53_health_checks ? {
    primary = {
      id                = try(aws_route53_health_check.primary[0].id, null)
      fqdn              = try(aws_route53_health_check.primary[0].fqdn, null)
      cloudwatch_alarm  = try(aws_route53_health_check.primary[0].cloudwatch_alarm_name, null)
      region            = var.primary_region
    }
    secondary = {
      id                = try(aws_route53_health_check.secondary[0].id, null)
      fqdn              = try(aws_route53_health_check.secondary[0].fqdn, null)
      cloudwatch_alarm  = try(aws_route53_health_check.secondary[0].cloudwatch_alarm_name, null)
      region            = var.secondary_region
    }
  } : {}
}

# =============================================================================
# SECURITY AND IAM OUTPUTS
# =============================================================================

output "iam_resources" {
  description = "IAM resource information for the multi-region application"
  value = {
    lambda_execution_role = {
      name = aws_iam_role.lambda_execution_role.name
      arn  = aws_iam_role.lambda_execution_role.arn
    }
    aurora_dsql_policy = {
      name = aws_iam_policy.aurora_dsql_policy.name
      arn  = aws_iam_policy.aurora_dsql_policy.arn
    }
  }
}

# =============================================================================
# DATABASE CONFIGURATION OUTPUTS
# =============================================================================

output "database_configuration" {
  description = "Database configuration information"
  value = {
    database_name        = var.database_name
    deletion_protection  = var.enable_deletion_protection
    sample_data_created  = var.create_sample_data
    backup_retention     = var.backup_retention_period
    maintenance_window   = var.maintenance_window
  }
}

# =============================================================================
# NETWORK AND CONNECTIVITY OUTPUTS
# =============================================================================

output "regions_configuration" {
  description = "Multi-region deployment configuration"
  value = {
    primary_region   = var.primary_region
    secondary_region = var.secondary_region
    witness_region   = var.witness_region
    deployment_mode  = "active-active"
    architecture     = "multi-region-aurora-dsql"
  }
}

# =============================================================================
# TESTING AND VALIDATION OUTPUTS
# =============================================================================

output "validation_commands" {
  description = "Commands for testing and validating the deployment"
  value = {
    primary_health_check = "curl -X GET \"${aws_api_gateway_rest_api.primary.id}.execute-api.${var.primary_region}.amazonaws.com/${var.api_gateway_stage_name}/health\""
    secondary_health_check = "curl -X GET \"${aws_api_gateway_rest_api.secondary.id}.execute-api.${var.secondary_region}.amazonaws.com/${var.api_gateway_stage_name}/health\""
    primary_users_list = "curl -X GET \"${aws_api_gateway_rest_api.primary.id}.execute-api.${var.primary_region}.amazonaws.com/${var.api_gateway_stage_name}/users\""
    secondary_users_list = "curl -X GET \"${aws_api_gateway_rest_api.secondary.id}.execute-api.${var.secondary_region}.amazonaws.com/${var.api_gateway_stage_name}/users\""
    create_user_primary = "curl -X POST \"${aws_api_gateway_rest_api.primary.id}.execute-api.${var.primary_region}.amazonaws.com/${var.api_gateway_stage_name}/users\" -H \"Content-Type: application/json\" -d '{\"name\":\"Test User\",\"email\":\"test@example.com\"}'"
    create_user_secondary = "curl -X POST \"${aws_api_gateway_rest_api.secondary.id}.execute-api.${var.secondary_region}.amazonaws.com/${var.api_gateway_stage_name}/users\" -H \"Content-Type: application/json\" -d '{\"name\":\"Test User\",\"email\":\"test@example.com\"}'"
  }
}

# =============================================================================
# COST ESTIMATION OUTPUTS
# =============================================================================

output "cost_estimation" {
  description = "Estimated monthly costs for the deployed resources"
  value = {
    aurora_dsql_clusters = "Variable based on usage (pay-per-request)"
    lambda_functions = "Free tier: 1M requests + 400,000 GB-seconds per month"
    api_gateway = "Free tier: 1M API calls per month, then $3.50 per million"
    cloudwatch_logs = "First 5GB per month free, then $0.50 per GB"
    route53_health_checks = var.create_route53_health_checks ? "$0.50 per health check per month" : "Not enabled"
    estimated_monthly_range = "$10-50 for moderate usage"
    note = "Actual costs depend on usage patterns and data transfer"
  }
}

# =============================================================================
# DEPLOYMENT METADATA OUTPUTS
# =============================================================================

output "deployment_metadata" {
  description = "Metadata about the Terraform deployment"
  value = {
    deployment_id = random_id.suffix.hex
    environment   = var.environment
    project_name  = var.project_name
    cost_center   = var.cost_center
    owner         = var.owner
    deployed_by   = "terraform"
    recipe_name   = "building-multi-region-applications-aurora-dsql"
    terraform_version = "1.0+"
    aws_provider_version = "~> 5.0"
    deployment_timestamp = timestamp()
  }
}

# =============================================================================
# TROUBLESHOOTING OUTPUTS
# =============================================================================

output "troubleshooting_information" {
  description = "Information for troubleshooting common issues"
  value = {
    lambda_log_groups = {
      primary   = "aws logs tail ${aws_cloudwatch_log_group.primary_lambda_logs.name} --region ${var.primary_region}"
      secondary = "aws logs tail ${aws_cloudwatch_log_group.secondary_lambda_logs.name} --region ${var.secondary_region}"
    }
    cluster_status_commands = {
      primary   = "aws dsql get-cluster --region ${var.primary_region} --cluster-identifier ${aws_dsql_cluster.primary.cluster_identifier}"
      secondary = "aws dsql get-cluster --region ${var.secondary_region} --cluster-identifier ${aws_dsql_cluster.secondary.cluster_identifier}"
    }
    common_issues = {
      cluster_pending = "Aurora DSQL clusters may take 5-10 minutes to become active"
      lambda_timeout = "Increase lambda_timeout variable if functions are timing out"
      api_gateway_errors = "Check Lambda function logs and Aurora DSQL cluster status"
      cross_region_consistency = "Data should appear consistently across regions within seconds"
    }
  }
}

# =============================================================================
# NEXT STEPS OUTPUTS
# =============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    testing = [
      "Test health endpoints to verify deployment",
      "Create test users in both regions",
      "Verify data consistency across regions",
      "Test API Gateway rate limiting and error handling"
    ]
    monitoring = [
      "Set up CloudWatch dashboards for Lambda and Aurora DSQL metrics",
      "Configure additional CloudWatch alarms for critical metrics",
      "Enable AWS X-Ray for distributed tracing",
      "Review cost and usage reports"
    ]
    security = [
      "Implement API Gateway authentication if needed",
      "Review IAM policies and apply least privilege",
      "Enable VPC deployment for Lambda functions if required",
      "Configure WAF rules for API Gateway if needed"
    ]
    scaling = [
      "Monitor Lambda concurrency and adjust if needed",
      "Implement caching with ElastiCache if required",
      "Consider CloudFront for global content delivery",
      "Add additional regions as needed"
    ]
  }
}