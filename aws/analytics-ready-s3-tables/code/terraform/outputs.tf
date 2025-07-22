# ==============================================================================
# Outputs for Analytics-Ready Data Storage with S3 Tables
# ==============================================================================

# ==============================================================================
# S3 Tables Infrastructure Outputs
# ==============================================================================

output "table_bucket_name" {
  description = "Name of the S3 table bucket"
  value       = aws_s3tables_table_bucket.analytics.name
}

output "table_bucket_arn" {
  description = "ARN of the S3 table bucket"
  value       = aws_s3tables_table_bucket.analytics.arn
}

output "table_bucket_creation_date" {
  description = "Creation date of the S3 table bucket"
  value       = aws_s3tables_table_bucket.analytics.created_at
}

output "table_bucket_owner_account_id" {
  description = "AWS account ID that owns the table bucket"
  value       = aws_s3tables_table_bucket.analytics.owner_account_id
}

# ==============================================================================
# Namespace Outputs
# ==============================================================================

output "namespace_name" {
  description = "Name of the S3 Tables namespace"
  value       = aws_s3tables_namespace.analytics_data.namespace
}

output "namespace_creation_date" {
  description = "Creation date of the namespace"
  value       = aws_s3tables_namespace.analytics_data.created_at
}

output "namespace_created_by" {
  description = "Account ID that created the namespace"
  value       = aws_s3tables_namespace.analytics_data.created_by
}

# ==============================================================================
# Table Outputs
# ==============================================================================

output "customer_events_table_name" {
  description = "Name of the customer events table"
  value       = aws_s3tables_table.customer_events.name
}

output "customer_events_table_arn" {
  description = "ARN of the customer events table"
  value       = aws_s3tables_table.customer_events.arn
}

output "customer_events_table_metadata_location" {
  description = "Location of the table metadata"
  value       = aws_s3tables_table.customer_events.metadata_location
}

output "customer_events_table_warehouse_location" {
  description = "S3 URI for the table data warehouse location"
  value       = aws_s3tables_table.customer_events.warehouse_location
}

output "customer_events_table_version_token" {
  description = "Version token for the current table data"
  value       = aws_s3tables_table.customer_events.version_token
}

output "customer_events_table_creation_date" {
  description = "Creation date of the customer events table"
  value       = aws_s3tables_table.customer_events.created_at
}

output "customer_events_table_modified_date" {
  description = "Last modification date of the customer events table"
  value       = aws_s3tables_table.customer_events.modified_at
}

# ==============================================================================
# Athena Configuration Outputs
# ==============================================================================

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup for S3 Tables queries"
  value       = aws_athena_workgroup.s3_tables.name
}

output "athena_workgroup_arn" {
  description = "ARN of the Athena workgroup"
  value       = aws_athena_workgroup.s3_tables.arn
}

output "athena_results_bucket_name" {
  description = "Name of the S3 bucket for Athena query results"
  value       = aws_s3_bucket.athena_results.bucket
}

output "athena_results_bucket_arn" {
  description = "ARN of the S3 bucket for Athena query results"
  value       = aws_s3_bucket.athena_results.arn
}

# ==============================================================================
# AWS Glue Integration Outputs
# ==============================================================================

output "glue_database_name" {
  description = "Name of the AWS Glue database for S3 Tables integration"
  value       = aws_glue_catalog_database.s3_tables.name
}

output "glue_database_arn" {
  description = "ARN of the AWS Glue database"
  value       = aws_glue_catalog_database.s3_tables.arn
}

# ==============================================================================
# Query and Connection Information
# ==============================================================================

output "athena_query_examples" {
  description = "Example Athena queries for the customer events table"
  value = {
    create_table_ddl = "CREATE TABLE IF NOT EXISTS s3tablescatalog.${var.namespace_name}.${var.sample_table_name} (event_id STRING, customer_id STRING, event_type STRING, event_timestamp TIMESTAMP, product_category STRING, amount DECIMAL(10,2), session_id STRING, user_agent STRING, event_date DATE) USING ICEBERG PARTITIONED BY (event_date) TBLPROPERTIES ('table_type'='ICEBERG', 'format'='PARQUET', 'write_compression'='SNAPPY');"

    sample_insert = "INSERT INTO s3tablescatalog.${var.namespace_name}.${var.sample_table_name} VALUES ('evt_001', 'cust_12345', 'page_view', TIMESTAMP '2025-01-15 10:30:00', 'electronics', 0.00, 'sess_abc123', 'Mozilla/5.0', DATE '2025-01-15');"

    sample_analytics_query = "SELECT event_type, COUNT(*) as event_count, AVG(amount) as avg_amount FROM s3tablescatalog.${var.namespace_name}.${var.sample_table_name} WHERE event_date = DATE '2025-01-15' GROUP BY event_type;"

    time_travel_query = "SELECT * FROM s3tablescatalog.${var.namespace_name}.${var.sample_table_name} FOR SYSTEM_TIME AS OF '2025-01-15 12:00:00';"
  }
}

output "s3_tables_catalog_connection" {
  description = "Connection information for S3 Tables catalog"
  value = {
    catalog_name      = "s3tablescatalog"
    database_name     = var.namespace_name
    table_name        = var.sample_table_name
    full_table_name   = "s3tablescatalog.${var.namespace_name}.${var.sample_table_name}"
    athena_workgroup  = aws_athena_workgroup.s3_tables.name
  }
}

# ==============================================================================
# CLI Commands for Validation
# ==============================================================================

output "validation_commands" {
  description = "AWS CLI commands to validate the deployment"
  value = {
    check_table_bucket = "aws s3tables get-table-bucket --name ${aws_s3tables_table_bucket.analytics.name}"
    
    list_namespaces = "aws s3tables list-namespaces --table-bucket-arn ${aws_s3tables_table_bucket.analytics.arn}"
    
    list_tables = "aws s3tables list-tables --table-bucket-arn ${aws_s3tables_table_bucket.analytics.arn} --namespace ${var.namespace_name}"
    
    get_table_details = "aws s3tables get-table --table-bucket-arn ${aws_s3tables_table_bucket.analytics.arn} --namespace ${var.namespace_name} --name ${var.sample_table_name}"
    
    check_athena_workgroup = "aws athena get-work-group --work-group ${aws_athena_workgroup.s3_tables.name}"
    
    check_glue_database = "aws glue get-database --name ${aws_glue_catalog_database.s3_tables.name}"
    
    verify_glue_integration = "aws glue get-table --database-name ${var.namespace_name} --name ${var.sample_table_name} --catalog-id ${data.aws_caller_identity.current.account_id}"
  }
}

# ==============================================================================
# Resource Management Information
# ==============================================================================

output "resource_summary" {
  description = "Summary of created resources and their purposes"
  value = {
    s3_table_bucket = {
      name        = aws_s3tables_table_bucket.analytics.name
      arn         = aws_s3tables_table_bucket.analytics.arn
      purpose     = "Purpose-built storage for Apache Iceberg tables with automatic optimization"
      features    = ["Automatic compaction", "Snapshot management", "Unreferenced file cleanup"]
    }
    
    namespace = {
      name    = aws_s3tables_namespace.analytics_data.namespace
      purpose = "Logical organization of related tables for better governance"
    }
    
    table = {
      name    = aws_s3tables_table.customer_events.name
      format  = "ICEBERG"
      purpose = "Customer events analytics table with optimized schema"
      features = ["ACID transactions", "Schema evolution", "Time travel queries"]
    }
    
    athena_workgroup = {
      name    = aws_athena_workgroup.s3_tables.name
      purpose = "Dedicated workgroup for S3 Tables analytics with cost controls"
      features = ["Query result encryption", "CloudWatch metrics", "Cost controls"]
    }
    
    glue_database = {
      name    = aws_glue_catalog_database.s3_tables.name
      purpose = "Data catalog integration for unified metadata management"
    }
  }
}

# ==============================================================================
# Cost and Performance Information
# ==============================================================================

output "performance_optimizations" {
  description = "Performance optimizations enabled in this configuration"
  value = {
    automatic_compaction = {
      enabled = "true"
      target_file_size_mb = var.target_file_size_mb
      benefit = "Improves query performance by optimizing file sizes"
    }
    
    snapshot_management = {
      enabled = "true"
      max_age_hours = var.max_snapshot_age_hours
      min_snapshots = var.min_snapshots_to_keep
      benefit = "Manages storage costs while maintaining data versioning"
    }
    
    unreferenced_file_cleanup = {
      enabled = "true"
      cleanup_days = var.unreferenced_file_cleanup_days
      benefit = "Reduces storage costs by cleaning up unused files"
    }
    
    athena_engine = {
      version = "Athena engine version 3"
      benefit = "Latest engine optimized for S3 Tables performance"
    }
  }
}

# ==============================================================================
# Security Configuration Information
# ==============================================================================

output "security_configuration" {
  description = "Security features enabled in this configuration"
  value = {
    encryption = {
      s3_tables = "AES256 server-side encryption"
      athena_results = "AES256 server-side encryption"
      benefit = "Data protection at rest"
    }
    
    access_control = {
      s3_bucket_public_access = "Blocked"
      iam_policies = "Least privilege for analytics services"
      benefit = "Prevents unauthorized access"
    }
    
    integration_policy = {
      glue_service_access = "Read-only access to table metadata"
      additional_services = length(var.additional_analytics_services) > 0 ? "Configured" : "None"
      benefit = "Secure integration with AWS analytics services"
    }
  }
}