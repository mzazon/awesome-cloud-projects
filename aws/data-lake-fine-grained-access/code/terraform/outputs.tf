# Outputs for the Lake Formation Fine-Grained Access Control infrastructure

output "s3_bucket_name" {
  description = "Name of the S3 bucket created for the data lake"
  value       = aws_s3_bucket.data_lake.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket created for the data lake"
  value       = aws_s3_bucket.data_lake.arn
}

output "glue_database_name" {
  description = "Name of the Glue database created"
  value       = aws_glue_catalog_database.sample_database.name
}

output "glue_table_name" {
  description = "Name of the Glue table created"
  value       = aws_glue_catalog_table.customer_data.name
}

output "data_analyst_role_arn" {
  description = "ARN of the data analyst IAM role"
  value       = aws_iam_role.data_analyst.arn
}

output "finance_team_role_arn" {
  description = "ARN of the finance team IAM role"
  value       = aws_iam_role.finance_team.arn
}

output "hr_role_arn" {
  description = "ARN of the HR IAM role"
  value       = aws_iam_role.hr.arn
}

output "lake_formation_data_lake_admin" {
  description = "ARN of the Lake Formation data lake administrator"
  value       = local.data_lake_admin_arn
}

output "lake_formation_registered_location" {
  description = "S3 location registered with Lake Formation"
  value       = aws_lakeformation_resource.data_lake_bucket.arn
}

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup for query testing"
  value       = aws_athena_workgroup.query_workgroup.name
}

output "sample_data_location" {
  description = "S3 location where sample data is stored"
  value       = var.create_sample_data ? "s3://${aws_s3_bucket.data_lake.bucket}/customer_data/" : "No sample data created"
}

output "data_cells_filter_name" {
  description = "Name of the data cells filter for row-level security"
  value       = aws_lakeformation_data_cells_filter.engineering_only.name
}

# Useful information for testing and validation
output "testing_instructions" {
  description = "Instructions for testing the fine-grained access controls"
  value = <<-EOT
    To test the fine-grained access controls:
    
    1. Assume the data analyst role to test full table access:
       aws sts assume-role --role-arn ${aws_iam_role.data_analyst.arn} --role-session-name test-session
    
    2. Assume the finance team role to test column-level access:
       aws sts assume-role --role-arn ${aws_iam_role.finance_team.arn} --role-session-name finance-session
    
    3. Assume the HR role to test limited column access:
       aws sts assume-role --role-arn ${aws_iam_role.hr.arn} --role-session-name hr-session
    
    4. Use Athena to query the table with different role credentials:
       aws athena start-query-execution --query-string "SELECT * FROM ${aws_glue_catalog_database.sample_database.name}.${aws_glue_catalog_table.customer_data.name} LIMIT 5" --work-group ${aws_athena_workgroup.query_workgroup.name}
  EOT
}

# Resource counts for cost estimation
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    s3_buckets       = 1
    glue_databases   = 1
    glue_tables      = 1
    iam_roles        = 3
    lf_permissions   = 3
    data_filters     = 1
    athena_workgroup = 1
  }
}