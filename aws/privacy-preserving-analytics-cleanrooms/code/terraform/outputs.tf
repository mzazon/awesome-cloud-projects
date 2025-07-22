# ==========================================
# Core Infrastructure Outputs
# ==========================================

output "aws_account_id" {
  description = "AWS Account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region where resources are deployed"
  value       = data.aws_region.current.name
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.suffix
}

# ==========================================
# S3 Bucket Outputs
# ==========================================

output "org_a_data_bucket" {
  description = "S3 bucket for Organization A data"
  value = {
    id  = aws_s3_bucket.org_a_data.id
    arn = aws_s3_bucket.org_a_data.arn
    bucket_domain_name = aws_s3_bucket.org_a_data.bucket_domain_name
    region = aws_s3_bucket.org_a_data.region
  }
}

output "org_b_data_bucket" {
  description = "S3 bucket for Organization B data"
  value = {
    id  = aws_s3_bucket.org_b_data.id
    arn = aws_s3_bucket.org_b_data.arn
    bucket_domain_name = aws_s3_bucket.org_b_data.bucket_domain_name
    region = aws_s3_bucket.org_b_data.region
  }
}

output "results_bucket" {
  description = "S3 bucket for Clean Rooms query results"
  value = {
    id  = aws_s3_bucket.results.id
    arn = aws_s3_bucket.results.arn
    bucket_domain_name = aws_s3_bucket.results.bucket_domain_name
    region = aws_s3_bucket.results.region
  }
}

# ==========================================
# IAM Role Outputs
# ==========================================

output "clean_rooms_role" {
  description = "IAM role for Clean Rooms service"
  value = {
    name = aws_iam_role.clean_rooms_role.name
    arn  = aws_iam_role.clean_rooms_role.arn
    id   = aws_iam_role.clean_rooms_role.id
  }
}

output "glue_role" {
  description = "IAM role for AWS Glue service"
  value = {
    name = aws_iam_role.glue_role.name
    arn  = aws_iam_role.glue_role.arn
    id   = aws_iam_role.glue_role.id
  }
}

# ==========================================
# AWS Glue Outputs
# ==========================================

output "glue_database" {
  description = "AWS Glue database for Clean Rooms analytics"
  value = {
    name = aws_glue_catalog_database.clean_rooms_database.name
    id   = aws_glue_catalog_database.clean_rooms_database.id
    arn  = aws_glue_catalog_database.clean_rooms_database.arn
  }
}

output "glue_crawlers" {
  description = "AWS Glue crawlers for data discovery"
  value = {
    org_a = {
      name = aws_glue_crawler.org_a_crawler.name
      arn  = aws_glue_crawler.org_a_crawler.arn
      id   = aws_glue_crawler.org_a_crawler.id
    }
    org_b = {
      name = aws_glue_crawler.org_b_crawler.name
      arn  = aws_glue_crawler.org_b_crawler.arn
      id   = aws_glue_crawler.org_b_crawler.id
    }
  }
}

# ==========================================
# QuickSight Outputs
# ==========================================

output "quicksight_resources" {
  description = "QuickSight resources (if enabled)"
  value = var.enable_quicksight ? {
    account_subscription = {
      account_name          = aws_quicksight_account_subscription.subscription[0].account_name
      edition              = aws_quicksight_account_subscription.subscription[0].edition
      notification_email   = aws_quicksight_account_subscription.subscription[0].notification_email
    }
    data_source = {
      id   = aws_quicksight_data_source.clean_rooms_results[0].data_source_id
      name = aws_quicksight_data_source.clean_rooms_results[0].name
      arn  = aws_quicksight_data_source.clean_rooms_results[0].arn
    }
    admin_user = {
      user_name = aws_quicksight_user.admin_user[0].user_name
      arn       = aws_quicksight_user.admin_user[0].arn
    }
  } : null
}

# ==========================================
# CloudWatch Outputs
# ==========================================

output "cloudwatch_log_group" {
  description = "CloudWatch log group for Clean Rooms query logs"
  value = {
    name = aws_cloudwatch_log_group.clean_rooms_logs.name
    arn  = aws_cloudwatch_log_group.clean_rooms_logs.arn
  }
}

# ==========================================
# Configuration Outputs for Manual Steps
# ==========================================

output "clean_rooms_collaboration_config" {
  description = "Configuration details for creating Clean Rooms collaboration"
  value = {
    collaboration_name    = local.collaboration_name
    collaboration_description = var.collaboration_description
    member_abilities     = var.member_abilities
    query_log_status     = var.enable_query_logging ? "ENABLED" : "DISABLED"
    service_role_arn     = aws_iam_role.clean_rooms_role.arn
  }
}

output "differential_privacy_config" {
  description = "Differential privacy configuration parameters"
  value = {
    epsilon             = var.differential_privacy_epsilon
    min_query_threshold = var.min_query_threshold
    privacy_budget_info = "Configure privacy budgets based on organizational requirements"
  }
}

# ==========================================
# Sample Data Information
# ==========================================

output "sample_data_info" {
  description = "Information about uploaded sample data"
  value = var.create_sample_data ? {
    org_a_data_location = "s3://${aws_s3_bucket.org_a_data.id}/data/customer_data_org_a.csv"
    org_b_data_location = "s3://${aws_s3_bucket.org_b_data.id}/data/customer_data_org_b.csv"
    org_a_record_count  = length(var.sample_data_org_a)
    org_b_record_count  = length(var.sample_data_org_b)
    data_format        = "CSV with headers"
  } : {
    message = "Sample data creation disabled - upload your own datasets to the S3 buckets"
  }
}

# ==========================================
# Next Steps Instructions
# ==========================================

output "next_steps" {
  description = "Instructions for completing the Clean Rooms setup"
  value = [
    "1. Run Glue crawlers to discover data schemas:",
    "   aws glue start-crawler --name ${aws_glue_crawler.org_a_crawler.name}",
    "   aws glue start-crawler --name ${aws_glue_crawler.org_b_crawler.name}",
    "",
    "2. Wait for crawlers to complete (check status):",
    "   aws glue get-crawler --name ${aws_glue_crawler.org_a_crawler.name}",
    "   aws glue get-crawler --name ${aws_glue_crawler.org_b_crawler.name}",
    "",
    "3. Create Clean Rooms collaboration using AWS CLI or Console:",
    "   aws cleanrooms create-collaboration \\",
    "     --name '${local.collaboration_name}' \\",
    "     --description '${var.collaboration_description}' \\",
    "     --member-abilities ${join(",", var.member_abilities)} \\",
    "     --query-log-status ${var.enable_query_logging ? "ENABLED" : "DISABLED"}",
    "",
    "4. Configure tables in Clean Rooms after crawlers complete",
    "5. Associate tables with the collaboration",
    "6. Execute privacy-preserving queries",
    var.enable_quicksight ? "7. Create QuickSight dashboards for visualization" : "7. Set up visualization tools as needed"
  ]
}

# ==========================================
# Security and Compliance Information
# ==========================================

output "security_features" {
  description = "Security features enabled in this deployment"
  value = {
    s3_encryption_enabled        = var.enable_bucket_encryption
    s3_versioning_enabled       = var.enable_bucket_versioning
    s3_public_access_blocked    = var.enable_bucket_public_access_block
    iam_roles_least_privilege   = true
    cloudwatch_logging_enabled  = true
    differential_privacy_ready  = true
  }
}

# ==========================================
# Cost Management Information
# ==========================================

output "cost_considerations" {
  description = "Cost-related information for the deployed resources"
  value = {
    s3_storage_cost = "Charged based on data stored and requests"
    glue_crawler_cost = "Charged per DPU-hour when crawlers run"
    clean_rooms_cost = "Charged based on query compute units and data scanned"
    quicksight_cost = var.enable_quicksight ? "Monthly subscription fee based on edition" : "Not applicable - QuickSight disabled"
    cloudwatch_logs_cost = "Charged based on log ingestion and storage"
    monitoring_recommendation = "Monitor costs through AWS Cost Explorer and set up billing alerts"
  }
}

# ==========================================
# Troubleshooting Information
# ==========================================

output "troubleshooting_resources" {
  description = "Resources for troubleshooting common issues"
  value = {
    cloudwatch_logs = aws_cloudwatch_log_group.clean_rooms_logs.name
    glue_database_name = aws_glue_catalog_database.clean_rooms_database.name
    iam_roles = {
      clean_rooms = aws_iam_role.clean_rooms_role.name
      glue = aws_iam_role.glue_role.name
    }
    s3_buckets = {
      org_a_data = aws_s3_bucket.org_a_data.id
      org_b_data = aws_s3_bucket.org_b_data.id
      results = aws_s3_bucket.results.id
    }
  }
}