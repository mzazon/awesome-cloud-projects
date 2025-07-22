# Outputs for Redshift Spectrum operational analytics infrastructure

# Redshift cluster information
output "redshift_cluster_identifier" {
  description = "Identifier of the Redshift cluster"
  value       = aws_redshift_cluster.main.cluster_identifier
}

output "redshift_cluster_endpoint" {
  description = "The connection endpoint for the Redshift cluster"
  value       = aws_redshift_cluster.main.endpoint
}

output "redshift_cluster_port" {
  description = "The port the Redshift cluster is listening on"
  value       = aws_redshift_cluster.main.port
}

output "redshift_database_name" {
  description = "Name of the database in the Redshift cluster"
  value       = aws_redshift_cluster.main.database_name
}

output "redshift_master_username" {
  description = "Master username for the Redshift cluster"
  value       = aws_redshift_cluster.main.master_username
  sensitive   = true
}

output "redshift_cluster_arn" {
  description = "ARN of the Redshift cluster"
  value       = aws_redshift_cluster.main.arn
}

# S3 Data Lake information
output "data_lake_bucket_name" {
  description = "Name of the S3 bucket used for data lake storage"
  value       = aws_s3_bucket.data_lake.bucket
}

output "data_lake_bucket_arn" {
  description = "ARN of the S3 data lake bucket"
  value       = aws_s3_bucket.data_lake.arn
}

output "data_lake_bucket_domain_name" {
  description = "Bucket domain name for the S3 data lake bucket"
  value       = aws_s3_bucket.data_lake.bucket_domain_name
}

output "sample_data_prefix" {
  description = "Prefix used for sample data in the S3 bucket"
  value       = var.sample_data_prefix
}

# Glue Data Catalog information
output "glue_database_name" {
  description = "Name of the Glue database for data catalog"
  value       = aws_glue_catalog_database.main.name
}

output "glue_database_arn" {
  description = "ARN of the Glue database"
  value       = aws_glue_catalog_database.main.arn
}

# Glue crawlers information
output "sales_crawler_name" {
  description = "Name of the Glue crawler for sales data"
  value       = aws_glue_crawler.sales_crawler.name
}

output "customers_crawler_name" {
  description = "Name of the Glue crawler for customers data"
  value       = aws_glue_crawler.customers_crawler.name
}

output "products_crawler_name" {
  description = "Name of the Glue crawler for products data"
  value       = aws_glue_crawler.products_crawler.name
}

# IAM roles information
output "redshift_spectrum_role_arn" {
  description = "ARN of the IAM role for Redshift Spectrum"
  value       = aws_iam_role.redshift_spectrum_role.arn
}

output "glue_crawler_role_arn" {
  description = "ARN of the IAM role for Glue crawlers"
  value       = aws_iam_role.glue_crawler_role.arn
}

# Connection information
output "connection_instructions" {
  description = "Instructions for connecting to the Redshift cluster"
  value = {
    host     = aws_redshift_cluster.main.endpoint
    port     = aws_redshift_cluster.main.port
    database = aws_redshift_cluster.main.database_name
    username = aws_redshift_cluster.main.master_username
    ssl_mode = "require"
  }
}

# SQL commands for Spectrum setup
output "spectrum_setup_commands" {
  description = "SQL commands to set up Redshift Spectrum external schema"
  value = {
    create_external_schema = "CREATE EXTERNAL SCHEMA spectrum_schema FROM DATA CATALOG DATABASE '${aws_glue_catalog_database.main.name}' IAM_ROLE '${aws_iam_role.redshift_spectrum_role.arn}' CREATE EXTERNAL DATABASE IF NOT EXISTS;"
    
    list_external_tables = "SELECT schemaname, tablename FROM SVV_EXTERNAL_TABLES WHERE schemaname = 'spectrum_schema';"
    
    sample_query = "SELECT region, COUNT(*) as transaction_count, SUM(quantity * unit_price) as total_revenue FROM spectrum_schema.sales GROUP BY region ORDER BY total_revenue DESC;"
  }
}

# Crawler run commands
output "crawler_commands" {
  description = "AWS CLI commands to run the Glue crawlers"
  value = {
    run_sales_crawler     = "aws glue start-crawler --name ${aws_glue_crawler.sales_crawler.name}"
    run_customers_crawler = "aws glue start-crawler --name ${aws_glue_crawler.customers_crawler.name}"
    run_products_crawler  = "aws glue start-crawler --name ${aws_glue_crawler.products_crawler.name}"
    run_all_crawlers      = "aws glue start-crawler --name ${aws_glue_crawler.sales_crawler.name} && aws glue start-crawler --name ${aws_glue_crawler.customers_crawler.name} && aws glue start-crawler --name ${aws_glue_crawler.products_crawler.name}"
  }
}

# Cost optimization tips
output "cost_optimization_tips" {
  description = "Tips for optimizing costs with Redshift Spectrum"
  value = {
    data_format       = "Use columnar formats like Parquet or ORC to reduce data scanned"
    partitioning      = "Partition your data by commonly filtered columns (e.g., date, region)"
    compression       = "Compress your data files to reduce storage costs and improve query performance"
    query_optimization = "Use WHERE clauses to limit data scanned by Spectrum queries"
    cluster_sizing    = "Right-size your Redshift cluster based on your analytical workload"
  }
}

# Monitoring and troubleshooting
output "monitoring_queries" {
  description = "Useful SQL queries for monitoring Spectrum performance"
  value = {
    spectrum_queries = "SELECT query, starttime, endtime, DATEDIFF(seconds, starttime, endtime) as duration_seconds, rows, bytes FROM stl_query WHERE querytxt LIKE '%spectrum_schema%' ORDER BY starttime DESC LIMIT 10;"
    
    data_scanned = "SELECT query, segment, step, max_rows, rows, bytes, ROUND(bytes/1024/1024, 2) as mb_scanned FROM svl_s3query ORDER BY query DESC LIMIT 10;"
    
    external_tables = "SELECT schemaname, tablename, location FROM SVV_EXTERNAL_TABLES WHERE schemaname = 'spectrum_schema';"
  }
}

# Resource tags
output "resource_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}