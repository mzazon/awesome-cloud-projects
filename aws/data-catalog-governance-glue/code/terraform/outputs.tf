# ============================================================================
# GENERAL OUTPUTS
# ============================================================================

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region"
  value       = data.aws_region.current.name
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# ============================================================================
# S3 BUCKET OUTPUTS
# ============================================================================

output "governance_bucket_name" {
  description = "Name of the S3 bucket for data storage"
  value       = aws_s3_bucket.governance_bucket.bucket
}

output "governance_bucket_arn" {
  description = "ARN of the S3 bucket for data storage"
  value       = aws_s3_bucket.governance_bucket.arn
}

output "governance_bucket_domain_name" {
  description = "Domain name of the S3 bucket for data storage"
  value       = aws_s3_bucket.governance_bucket.bucket_domain_name
}

output "audit_bucket_name" {
  description = "Name of the S3 bucket for audit logs"
  value       = var.enable_cloudtrail ? aws_s3_bucket.audit_bucket[0].bucket : null
}

output "audit_bucket_arn" {
  description = "ARN of the S3 bucket for audit logs"
  value       = var.enable_cloudtrail ? aws_s3_bucket.audit_bucket[0].arn : null
}

output "sample_data_location" {
  description = "S3 location of sample data"
  value       = var.create_sample_data ? "s3://${aws_s3_bucket.governance_bucket.bucket}/data/sample_customer_data.csv" : null
}

# ============================================================================
# IAM OUTPUTS
# ============================================================================

output "glue_crawler_role_arn" {
  description = "ARN of the Glue crawler IAM role"
  value       = aws_iam_role.glue_crawler_role.arn
}

output "glue_crawler_role_name" {
  description = "Name of the Glue crawler IAM role"
  value       = aws_iam_role.glue_crawler_role.name
}

output "data_analyst_role_arn" {
  description = "ARN of the data analyst IAM role"
  value       = var.create_data_analyst_role ? aws_iam_role.data_analyst_role[0].arn : null
}

output "data_analyst_role_name" {
  description = "Name of the data analyst IAM role"
  value       = var.create_data_analyst_role ? aws_iam_role.data_analyst_role[0].name : null
}

output "data_analyst_policy_arn" {
  description = "ARN of the data analyst IAM policy"
  value       = var.create_data_analyst_role ? aws_iam_policy.data_analyst_policy[0].arn : null
}

# ============================================================================
# AWS GLUE DATA CATALOG OUTPUTS
# ============================================================================

output "database_name" {
  description = "Name of the Glue Data Catalog database"
  value       = aws_glue_catalog_database.governance_database.name
}

output "database_arn" {
  description = "ARN of the Glue Data Catalog database"
  value       = aws_glue_catalog_database.governance_database.arn
}

output "crawler_name" {
  description = "Name of the Glue crawler"
  value       = aws_glue_crawler.governance_crawler.name
}

output "crawler_arn" {
  description = "ARN of the Glue crawler"
  value       = aws_glue_crawler.governance_crawler.arn
}

output "classifier_name" {
  description = "Name of the PII classifier"
  value       = aws_glue_classifier.pii_classifier.name
}

output "pii_detection_script_location" {
  description = "S3 location of the PII detection script"
  value       = "s3://${aws_s3_bucket.governance_bucket.bucket}/scripts/pii-detection-script.py"
}

# ============================================================================
# LAKE FORMATION OUTPUTS
# ============================================================================

output "lake_formation_enabled" {
  description = "Whether Lake Formation is enabled"
  value       = var.enable_lake_formation
}

output "lake_formation_resource_arn" {
  description = "ARN of the Lake Formation registered resource"
  value       = var.enable_lake_formation ? aws_lakeformation_resource.governance_resource[0].arn : null
}

output "lake_formation_admins" {
  description = "List of Lake Formation administrators"
  value       = var.enable_lake_formation ? var.lake_formation_admins : null
}

# ============================================================================
# CLOUDTRAIL OUTPUTS
# ============================================================================

output "cloudtrail_enabled" {
  description = "Whether CloudTrail is enabled"
  value       = var.enable_cloudtrail
}

output "cloudtrail_name" {
  description = "Name of the CloudTrail"
  value       = var.enable_cloudtrail ? aws_cloudtrail.governance_trail[0].name : null
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail"
  value       = var.enable_cloudtrail ? aws_cloudtrail.governance_trail[0].arn : null
}

output "cloudtrail_home_region" {
  description = "Home region of the CloudTrail"
  value       = var.enable_cloudtrail ? aws_cloudtrail.governance_trail[0].home_region : null
}

# ============================================================================
# CLOUDWATCH MONITORING OUTPUTS
# ============================================================================

output "cloudwatch_dashboard_enabled" {
  description = "Whether CloudWatch dashboard is enabled"
  value       = var.enable_cloudwatch_dashboard
}

output "cloudwatch_dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = var.enable_cloudwatch_dashboard ? aws_cloudwatch_dashboard.governance_dashboard[0].dashboard_name : null
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = var.enable_cloudwatch_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.governance_dashboard[0].dashboard_name}" : null
}

output "glue_crawler_log_group_name" {
  description = "Name of the Glue crawler CloudWatch log group"
  value       = aws_cloudwatch_log_group.glue_crawler_logs.name
}

output "glue_crawler_log_group_arn" {
  description = "ARN of the Glue crawler CloudWatch log group"
  value       = aws_cloudwatch_log_group.glue_crawler_logs.arn
}

# ============================================================================
# VALIDATION AND TESTING OUTPUTS
# ============================================================================

output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    check_database = "aws glue get-database --name ${aws_glue_catalog_database.governance_database.name}"
    check_tables   = "aws glue get-tables --database-name ${aws_glue_catalog_database.governance_database.name}"
    check_crawler  = "aws glue get-crawler --name ${aws_glue_crawler.governance_crawler.name}"
    start_crawler  = "aws glue start-crawler --name ${aws_glue_crawler.governance_crawler.name}"
    crawler_status = "aws glue get-crawler --name ${aws_glue_crawler.governance_crawler.name} --query 'Crawler.State' --output text"
    list_s3_objects = "aws s3 ls s3://${aws_s3_bucket.governance_bucket.bucket}/ --recursive"
  }
}

output "testing_commands" {
  description = "Commands to test the governance features"
  value = {
    test_pii_detection     = "aws glue get-table --database-name ${aws_glue_catalog_database.governance_database.name} --name [TABLE_NAME] --query 'Table.StorageDescriptor.Columns[?contains(Name, `ssn`) || contains(Name, `email`) || contains(Name, `phone`)].[Name,Type,Parameters]' --output table"
    check_lf_permissions   = var.enable_lake_formation ? "aws lakeformation list-permissions --resource Table='{DatabaseName=${aws_glue_catalog_database.governance_database.name},Name=[TABLE_NAME]}' --query 'PrincipalResourcePermissions[*].[Principal,Permissions]' --output table" : null
    check_audit_trail      = var.enable_cloudtrail ? "aws cloudtrail describe-trails --trail-name-list ${aws_cloudtrail.governance_trail[0].name} --query 'trailList[*].[Name,S3BucketName,IsLogging]' --output table" : null
    list_audit_logs        = var.enable_cloudtrail ? "aws s3 ls s3://${aws_s3_bucket.audit_bucket[0].bucket}/ --recursive | head -5" : null
  }
}

# ============================================================================
# DEPLOYMENT GUIDANCE
# ============================================================================

output "deployment_guidance" {
  description = "Guidance for deploying and using the data governance solution"
  value = {
    next_steps = [
      "1. Run the crawler to populate the Data Catalog: aws glue start-crawler --name ${aws_glue_crawler.governance_crawler.name}",
      "2. Wait for crawler completion: aws glue get-crawler --name ${aws_glue_crawler.governance_crawler.name} --query 'Crawler.State'",
      "3. Check discovered tables: aws glue get-tables --database-name ${aws_glue_catalog_database.governance_database.name}",
      "4. Review PII classification results in table metadata",
      var.enable_lake_formation ? "5. Configure Lake Formation permissions for specific tables and users" : null,
      var.enable_cloudtrail ? "6. Monitor audit logs in S3 bucket: ${var.enable_cloudtrail ? aws_s3_bucket.audit_bucket[0].bucket : "N/A"}" : null,
      var.enable_cloudwatch_dashboard ? "7. Review governance metrics in CloudWatch dashboard" : null
    ]
    
    important_notes = [
      "Sample data contains PII fields (SSN, email, phone) for testing classification",
      "Lake Formation provides fine-grained access control beyond IAM policies",
      "CloudTrail logs all Data Catalog access for compliance and audit purposes",
      "Custom classifier identifies PII patterns in CSV files",
      "Data analyst role provides read-only access to governed data"
    ]
    
    cost_considerations = [
      "Glue crawler charges per DPU-hour and data store scanned",
      "Lake Formation has no additional charges beyond underlying AWS services",
      "CloudTrail charges for data events beyond the free tier",
      "S3 storage costs for data and audit logs",
      "CloudWatch charges for dashboard and log storage"
    ]
  }
}

# ============================================================================
# SECURITY CONSIDERATIONS
# ============================================================================

output "security_considerations" {
  description = "Security considerations for the data governance solution"
  value = {
    encryption = {
      s3_data_bucket  = "AES256 server-side encryption enabled"
      s3_audit_bucket = var.enable_cloudtrail ? "AES256 server-side encryption enabled" : null
      cloudtrail_logs = var.enable_cloudtrail ? "S3 server-side encryption for log files" : null
    }
    
    access_control = {
      iam_roles           = "Principle of least privilege applied to all IAM roles"
      s3_public_access    = "All S3 buckets have public access blocked"
      lake_formation      = var.enable_lake_formation ? "Fine-grained access control enabled" : null
      data_analyst_access = var.create_data_analyst_role ? "Read-only access to governed data" : null
    }
    
    audit_logging = {
      cloudtrail      = var.enable_cloudtrail ? "Comprehensive audit logging enabled" : null
      log_validation  = var.enable_cloudtrail && var.enable_log_file_validation ? "CloudTrail log file validation enabled" : null
      cloudwatch_logs = "Glue crawler logs centralized in CloudWatch"
    }
    
    compliance = {
      pii_detection   = "Automated PII classification for compliance"
      data_lineage    = "Metadata tracking for data governance"
      access_tracking = var.enable_cloudtrail ? "Complete audit trail for regulatory compliance" : null
    }
  }
}