# ============================================================================
# CORE INFRASTRUCTURE OUTPUTS
# ============================================================================

# AWS Account and Region Information
output "aws_account_id" {
  description = "AWS Account ID"
  value       = local.account_id
}

output "aws_region" {
  description = "AWS Region"
  value       = local.region
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# ============================================================================
# S3 BUCKET OUTPUTS
# ============================================================================

output "s3_buckets" {
  description = "S3 bucket information for data lake zones"
  value = {
    raw_data = {
      name = aws_s3_bucket.raw_data.id
      arn  = aws_s3_bucket.raw_data.arn
      url  = "s3://${aws_s3_bucket.raw_data.id}"
    }
    processed_data = {
      name = aws_s3_bucket.processed_data.id
      arn  = aws_s3_bucket.processed_data.arn
      url  = "s3://${aws_s3_bucket.processed_data.id}"
    }
    curated_data = {
      name = aws_s3_bucket.curated_data.id
      arn  = aws_s3_bucket.curated_data.arn
      url  = "s3://${aws_s3_bucket.curated_data.id}"
    }
  }
}

# Individual bucket outputs for convenience
output "raw_bucket_name" {
  description = "Name of the raw data S3 bucket"
  value       = aws_s3_bucket.raw_data.id
}

output "processed_bucket_name" {
  description = "Name of the processed data S3 bucket"
  value       = aws_s3_bucket.processed_data.id
}

output "curated_bucket_name" {
  description = "Name of the curated data S3 bucket"
  value       = aws_s3_bucket.curated_data.id
}

# ============================================================================
# LAKE FORMATION OUTPUTS
# ============================================================================

output "lake_formation_service_role" {
  description = "Lake Formation service role information"
  value = {
    name = aws_iam_role.lake_formation_service.name
    arn  = aws_iam_role.lake_formation_service.arn
  }
}

output "lake_formation_admins" {
  description = "List of Lake Formation administrators"
  value       = aws_lakeformation_data_lake_settings.main.admins
}

output "lf_tags" {
  description = "Lake Formation tags (LF-Tags) created for governance"
  value = {
    for key, tag in aws_lakeformation_lf_tag.governance_tags : key => {
      key    = tag.key
      values = tag.values
    }
  }
}

# ============================================================================
# GLUE CATALOG OUTPUTS
# ============================================================================

output "glue_database" {
  description = "Glue database information"
  value = {
    name        = aws_glue_catalog_database.data_lake.name
    arn         = aws_glue_catalog_database.data_lake.arn
    catalog_id  = aws_glue_catalog_database.data_lake.catalog_id
    description = aws_glue_catalog_database.data_lake.description
  }
}

output "glue_crawlers" {
  description = "Glue crawler information"
  value = var.enable_glue_crawlers ? {
    sales_crawler = {
      name = aws_glue_crawler.sales_crawler[0].name
      arn  = aws_glue_crawler.sales_crawler[0].arn
    }
    customer_crawler = {
      name = aws_glue_crawler.customer_crawler[0].name
      arn  = aws_glue_crawler.customer_crawler[0].arn
    }
  } : {}
}

output "glue_crawler_role" {
  description = "Glue crawler IAM role information"
  value = {
    name = aws_iam_role.glue_crawler.name
    arn  = aws_iam_role.glue_crawler.arn
  }
}

# ============================================================================
# IAM OUTPUTS
# ============================================================================

output "iam_users" {
  description = "IAM users created for data lake access"
  value = var.create_iam_users ? {
    for key, user in aws_iam_user.data_lake_users : key => {
      name = user.name
      arn  = user.arn
    }
  } : {}
}

output "iam_roles" {
  description = "IAM roles created for data lake access"
  value = var.create_iam_users ? {
    for key, role in aws_iam_role.data_lake_roles : key => {
      name = role.name
      arn  = role.arn
    }
  } : {}
}

output "data_analyst_role_arn" {
  description = "ARN of the data analyst role"
  value       = var.create_iam_users ? aws_iam_role.data_lake_roles["data_analyst"].arn : null
}

output "data_engineer_role_arn" {
  description = "ARN of the data engineer role"
  value       = var.create_iam_users ? aws_iam_role.data_lake_roles["data_engineer"].arn : null
}

output "lake_formation_admin_role_arn" {
  description = "ARN of the Lake Formation admin role"
  value       = var.create_iam_users ? aws_iam_role.data_lake_roles["lake_formation_admin"].arn : null
}

# ============================================================================
# DATA CELL FILTERS OUTPUTS
# ============================================================================

output "data_cell_filters" {
  description = "Data cell filters created for fine-grained access control"
  value = var.enable_data_cell_filters ? {
    for key, filter in aws_lakeformation_data_cells_filter.filters : key => {
      name           = filter.table_data[0].name
      table_name     = filter.table_data[0].table_name
      database_name  = filter.table_data[0].database_name
    }
  } : {}
}

# ============================================================================
# CLOUDTRAIL AND MONITORING OUTPUTS
# ============================================================================

output "cloudtrail_trail" {
  description = "CloudTrail trail information for audit logging"
  value = var.enable_cloudtrail ? {
    name            = aws_cloudtrail.lake_formation_audit[0].name
    arn             = aws_cloudtrail.lake_formation_audit[0].arn
    s3_bucket_name  = aws_cloudtrail.lake_formation_audit[0].s3_bucket_name
    s3_key_prefix   = aws_cloudtrail.lake_formation_audit[0].s3_key_prefix
  } : null
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for Lake Formation audit logs"
  value = var.enable_cloudtrail ? {
    name              = aws_cloudwatch_log_group.lake_formation_audit[0].name
    arn               = aws_cloudwatch_log_group.lake_formation_audit[0].arn
    retention_in_days = aws_cloudwatch_log_group.lake_formation_audit[0].retention_in_days
  } : null
}

# ============================================================================
# SAMPLE DATA OUTPUTS
# ============================================================================

output "sample_data_files" {
  description = "Sample data files uploaded to the raw bucket"
  value = var.upload_sample_data ? {
    for key, file in aws_s3_object.sample_data : key => {
      bucket = file.bucket
      key    = file.key
      url    = "s3://${file.bucket}/${file.key}"
    }
  } : {}
}

# ============================================================================
# VALIDATION AND TESTING OUTPUTS
# ============================================================================

output "athena_query_example" {
  description = "Example Athena query to test the data lake"
  value = var.upload_sample_data ? {
    query = "SELECT COUNT(*) FROM ${local.database_name}.sales_sales_data;"
    note  = "Run this query in Athena to test Lake Formation permissions"
  } : null
}

output "aws_cli_commands" {
  description = "Useful AWS CLI commands for testing and validation"
  value = {
    list_lf_tags = "aws lakeformation list-lf-tags --catalog-id ${local.account_id}"
    list_resources = "aws lakeformation list-resources"
    get_database = "aws glue get-database --name ${local.database_name}"
    list_tables = "aws glue get-tables --database-name ${local.database_name}"
    get_data_lake_settings = "aws lakeformation get-data-lake-settings --catalog-id ${local.account_id}"
  }
}

# ============================================================================
# NEXT STEPS AND RECOMMENDATIONS
# ============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    "1_run_crawlers" = "Run Glue crawlers to populate the data catalog: aws glue start-crawler --name ${var.enable_glue_crawlers ? aws_glue_crawler.sales_crawler[0].name : "crawler-name"}"
    "2_test_athena" = "Test data access with Athena queries on the cataloged tables"
    "3_configure_permissions" = "Configure additional Lake Formation permissions for specific users/roles"
    "4_setup_etl_jobs" = "Create Glue ETL jobs to process data from raw to processed/curated zones"
    "5_monitor_access" = "Monitor data access patterns using CloudTrail logs in CloudWatch"
  }
}

output "important_notes" {
  description = "Important notes about the deployed infrastructure"
  value = {
    lake_formation_permissions = "Lake Formation permissions override IAM S3 permissions for registered resources"
    data_cell_filters = "Data cell filters provide column-level and row-level security at query time"
    cost_optimization = "Consider lifecycle policies on S3 buckets to optimize storage costs"
    security_best_practices = "Regularly review and audit Lake Formation permissions and access patterns"
    backup_strategy = "Implement backup and disaster recovery strategies for critical data"
  }
}

# ============================================================================
# RESOURCE ARNS FOR INTEGRATION
# ============================================================================

output "resource_arns" {
  description = "ARNs of all major resources for integration with other systems"
  value = {
    raw_bucket               = aws_s3_bucket.raw_data.arn
    processed_bucket         = aws_s3_bucket.processed_data.arn
    curated_bucket          = aws_s3_bucket.curated_data.arn
    glue_database           = aws_glue_catalog_database.data_lake.arn
    glue_crawler_role       = aws_iam_role.glue_crawler.arn
    lake_formation_service_role = aws_iam_role.lake_formation_service.arn
    cloudtrail_trail        = var.enable_cloudtrail ? aws_cloudtrail.lake_formation_audit[0].arn : null
    cloudwatch_log_group    = var.enable_cloudtrail ? aws_cloudwatch_log_group.lake_formation_audit[0].arn : null
  }
}