# Outputs for Lake Formation cross-account data access infrastructure

#######################
# Data Lake Infrastructure
#######################

output "data_lake_bucket_name" {
  description = "Name of the S3 data lake bucket"
  value       = aws_s3_bucket.data_lake.bucket
}

output "data_lake_bucket_arn" {
  description = "ARN of the S3 data lake bucket"
  value       = aws_s3_bucket.data_lake.arn
}

output "data_lake_bucket_region" {
  description = "Region where the data lake bucket is located"
  value       = aws_s3_bucket.data_lake.region
}

#######################
# Account Information
#######################

output "producer_account_id" {
  description = "AWS Account ID of the producer account"
  value       = local.account_id
}

output "consumer_account_id" {
  description = "AWS Account ID of the consumer account"
  value       = var.consumer_account_id
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = local.region
}

#######################
# Lake Formation Resources
#######################

output "lf_tags" {
  description = "Lake Formation tags created for access control"
  value = {
    department = {
      key    = aws_lakeformation_lf_tag.department.key
      values = aws_lakeformation_lf_tag.department.values
    }
    classification = {
      key    = aws_lakeformation_lf_tag.classification.key
      values = aws_lakeformation_lf_tag.classification.values
    }
    data_category = {
      key    = aws_lakeformation_lf_tag.data_category.key
      values = aws_lakeformation_lf_tag.data_category.values
    }
  }
}

output "lake_formation_data_lake_settings" {
  description = "Lake Formation data lake settings configuration"
  value = {
    admins = aws_lakeformation_data_lake_settings.main.admins
  }
  sensitive = true
}

#######################
# Glue Data Catalog
#######################

output "glue_databases" {
  description = "Glue catalog databases created"
  value = {
    for db_name, db in aws_glue_catalog_database.databases : db_name => {
      name        = db.name
      arn         = db.arn
      catalog_id  = db.catalog_id
      description = db.description
    }
  }
}

output "glue_crawlers" {
  description = "Glue crawlers created for data discovery"
  value = {
    for crawler_name, crawler in aws_glue_crawler.crawlers : crawler_name => {
      name          = crawler.name
      arn           = crawler.arn
      database_name = crawler.database_name
      role          = crawler.role
      schedule      = crawler.schedule
    }
  }
}

output "glue_service_role_arn" {
  description = "ARN of the Glue service role"
  value       = aws_iam_role.glue_service_role.arn
}

#######################
# AWS RAM Resource Sharing
#######################

output "resource_share_arn" {
  description = "ARN of the AWS RAM resource share"
  value       = aws_ram_resource_share.lake_formation_share.arn
}

output "resource_share_id" {
  description = "ID of the AWS RAM resource share"
  value       = aws_ram_resource_share.lake_formation_share.id
}

output "resource_share_status" {
  description = "Status of the AWS RAM resource share"
  value       = aws_ram_resource_share.lake_formation_share.status
}

output "shared_database_arns" {
  description = "ARNs of the databases shared via AWS RAM"
  value = {
    for db_name in var.shared_databases : db_name => "arn:aws:glue:${local.region}:${local.account_id}:database/${db_name}"
  }
}

#######################
# CloudTrail Auditing
#######################

output "cloudtrail_trail_arn" {
  description = "ARN of the CloudTrail trail for Lake Formation auditing"
  value       = var.enable_cloudtrail_logging ? aws_cloudtrail.lake_formation_audit[0].arn : null
}

output "cloudtrail_s3_bucket" {
  description = "S3 bucket for CloudTrail logs"
  value       = var.enable_cloudtrail_logging ? aws_s3_bucket.cloudtrail_logs[0].bucket : null
}

#######################
# Consumer Account Resources
#######################

output "data_analyst_role_arn" {
  description = "ARN of the data analyst role in the consumer account"
  value       = var.enable_consumer_account_setup && var.consumer_account_assume_role_arn != null ? aws_iam_role.data_analyst_consumer[0].arn : null
}

output "shared_database_links" {
  description = "Resource links created in the consumer account"
  value = var.enable_consumer_account_setup && var.consumer_account_assume_role_arn != null ? {
    for db_name, db in aws_glue_catalog_database.shared_database_links : db_name => {
      name           = db.name
      catalog_id     = db.catalog_id
      target_database = db.target_database
    }
  } : {}
}

#######################
# Sample Data Locations
#######################

output "sample_data_locations" {
  description = "S3 locations of uploaded sample data"
  value = {
    financial_reports = "s3://${aws_s3_bucket.data_lake.bucket}/${aws_s3_object.financial_sample_data.key}"
    customer_data     = "s3://${aws_s3_bucket.data_lake.bucket}/${aws_s3_object.customer_sample_data.key}"
  }
}

#######################
# Access Instructions
#######################

output "cross_account_setup_commands" {
  description = "Commands to run in the consumer account for manual setup"
  value = [
    "# Accept RAM resource share invitation",
    "aws ram get-resource-share-invitations --resource-share-arns ${aws_ram_resource_share.lake_formation_share.arn}",
    "# Accept the invitation using the invitation ARN from the above command",
    "aws ram accept-resource-share-invitation --resource-share-invitation-arn <INVITATION_ARN>",
    "",
    "# Configure Lake Formation in consumer account",
    "aws lakeformation register-data-lake-settings --data-lake-settings 'DataLakeAdministrators=[{DataLakePrincipalIdentifier=arn:aws:iam::${var.consumer_account_id}:root}]'",
    "",
    "# Create resource links for shared databases",
    join("\n", [
      for db_name in var.shared_databases :
      "aws glue create-database --database-input '{\"Name\": \"shared_${db_name}\", \"Description\": \"Resource link to shared ${db_name} database\", \"TargetDatabase\": {\"CatalogId\": \"${local.account_id}\", \"DatabaseName\": \"${db_name}\"}}'"
    ])
  ]
}

output "athena_query_examples" {
  description = "Example Athena queries for testing cross-account access"
  value = [
    "-- Query shared financial data",
    "SELECT department, revenue, expenses, profit",
    "FROM shared_financial_db.financial_reports_2024_q1",
    "WHERE department IN ('finance', 'marketing')",
    "LIMIT 10;",
    "",
    "-- Test unauthorized access (should fail or return no results)",
    "SELECT *",
    "FROM shared_financial_db.financial_reports_2024_q1",
    "WHERE department = 'hr';"
  ]
}

#######################
# Validation Commands
#######################

output "validation_commands" {
  description = "Commands to validate the Lake Formation setup"
  value = [
    "# Verify LF-Tags are created",
    "aws lakeformation get-lf-tag --tag-key department",
    "aws lakeformation get-lf-tag --tag-key classification",
    "aws lakeformation get-lf-tag --tag-key data-category",
    "",
    "# Check resource tagging",
    "aws lakeformation get-resource-lf-tags --resource Database='{Name=financial_db}'",
    "",
    "# Verify cross-account permissions",
    "aws lakeformation list-permissions --principal ${var.consumer_account_id}",
    "",
    "# Check resource share status",
    "aws ram get-resource-shares --resource-owner SELF --name ${aws_ram_resource_share.lake_formation_share.name}",
    "",
    "# Verify crawler execution",
    join("\n", [
      for crawler_name in keys(var.glue_crawler_configurations) :
      "aws glue get-crawler --name ${crawler_name}"
    ])
  ]
}

#######################
# Resource Summary
#######################

output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    s3_buckets = {
      data_lake = aws_s3_bucket.data_lake.bucket
      cloudtrail_logs = var.enable_cloudtrail_logging ? aws_s3_bucket.cloudtrail_logs[0].bucket : "Not created"
    }
    glue_resources = {
      databases = length(aws_glue_catalog_database.databases)
      crawlers  = length(aws_glue_crawler.crawlers)
    }
    lake_formation = {
      lf_tags         = 3
      registered_locations = 1
      cross_account_permissions = length(var.cross_account_permissions)
    }
    aws_ram = {
      resource_shares = 1
      shared_databases = length(var.shared_databases)
      principal_associations = 1
    }
    iam_roles = {
      glue_service_role = aws_iam_role.glue_service_role.name
      data_analyst_role = var.enable_consumer_account_setup && var.consumer_account_assume_role_arn != null ? aws_iam_role.data_analyst_consumer[0].name : "Not created"
    }
  }
}