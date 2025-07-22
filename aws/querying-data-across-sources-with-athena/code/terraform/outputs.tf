# S3 Bucket Outputs
output "athena_spill_bucket" {
  description = "Name of the S3 bucket for Athena spill data"
  value       = aws_s3_bucket.athena_spill.bucket
}

output "athena_results_bucket" {
  description = "Name of the S3 bucket for Athena query results"
  value       = aws_s3_bucket.athena_results.bucket
}

output "athena_results_bucket_url" {
  description = "S3 URL for Athena query results"
  value       = "s3://${aws_s3_bucket.athena_results.bucket}/"
}

# Network Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "rds_security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}

# Database Outputs
output "rds_endpoint" {
  description = "RDS MySQL endpoint"
  value       = aws_db_instance.mysql.endpoint
}

output "rds_port" {
  description = "RDS MySQL port"
  value       = aws_db_instance.mysql.port
}

output "rds_database_name" {
  description = "RDS MySQL database name"
  value       = aws_db_instance.mysql.db_name
}

output "rds_identifier" {
  description = "RDS instance identifier"
  value       = aws_db_instance.mysql.id
}

output "rds_connection_string" {
  description = "MySQL connection string for Athena connector"
  value       = "mysql://jdbc:mysql://${aws_db_instance.mysql.endpoint}:${aws_db_instance.mysql.port}/${aws_db_instance.mysql.db_name}?user=${aws_db_instance.mysql.username}&password=${aws_db_instance.mysql.password}"
  sensitive   = true
}

# DynamoDB Outputs
output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.orders.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.orders.arn
}

# Lambda Connector Outputs
output "mysql_connector_function_name" {
  description = "Name of the MySQL connector Lambda function"
  value       = "${var.project_name}-mysql-connector"
}

output "dynamodb_connector_function_name" {
  description = "Name of the DynamoDB connector Lambda function"
  value       = "${var.project_name}-dynamodb-connector"
}

output "mysql_connector_arn" {
  description = "ARN of the MySQL connector Lambda function"
  value       = "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-mysql-connector"
}

output "dynamodb_connector_arn" {
  description = "ARN of the DynamoDB connector Lambda function"
  value       = "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-dynamodb-connector"
}

# Athena Data Catalog Outputs
output "mysql_catalog_name" {
  description = "Name of the MySQL data catalog"
  value       = aws_athena_data_catalog.mysql.name
}

output "dynamodb_catalog_name" {
  description = "Name of the DynamoDB data catalog"
  value       = aws_athena_data_catalog.dynamodb.name
}

# Athena Workgroup Outputs
output "athena_workgroup_name" {
  description = "Name of the Athena workgroup"
  value       = aws_athena_workgroup.federated_analytics.name
}

output "athena_workgroup_arn" {
  description = "ARN of the Athena workgroup"
  value       = aws_athena_workgroup.federated_analytics.arn
}

# Sample Query Examples
output "sample_federated_query" {
  description = "Example federated query to join MySQL and DynamoDB data"
  value = <<EOF
SELECT 
    mysql_orders.order_id,
    mysql_orders.customer_id,
    mysql_orders.product_name,
    mysql_orders.quantity,
    mysql_orders.price,
    mysql_orders.order_date,
    ddb_tracking.status as shipment_status,
    ddb_tracking.tracking_number,
    ddb_tracking.carrier
FROM mysql_catalog.${aws_db_instance.mysql.db_name}.${var.sample_orders_table} mysql_orders
LEFT JOIN dynamodb_catalog.default.${aws_dynamodb_table.orders.name} ddb_tracking
ON CAST(mysql_orders.order_id AS VARCHAR) = ddb_tracking.order_id
ORDER BY mysql_orders.order_date DESC
LIMIT 10;
EOF
}

output "sample_view_creation" {
  description = "Example SQL to create a federated view"
  value = <<EOF
CREATE VIEW default.order_analytics AS
SELECT 
    mysql_orders.order_id,
    mysql_orders.customer_id,
    mysql_orders.product_name,
    mysql_orders.quantity,
    mysql_orders.price,
    mysql_orders.order_date,
    COALESCE(ddb_tracking.status, 'pending') as shipment_status,
    ddb_tracking.tracking_number,
    ddb_tracking.carrier,
    (mysql_orders.quantity * mysql_orders.price) as total_amount
FROM mysql_catalog.${aws_db_instance.mysql.db_name}.${var.sample_orders_table} mysql_orders
LEFT JOIN dynamodb_catalog.default.${aws_dynamodb_table.orders.name} ddb_tracking
ON CAST(mysql_orders.order_id AS VARCHAR) = ddb_tracking.order_id;
EOF
}

# Cost Estimation
output "estimated_monthly_cost" {
  description = "Estimated monthly cost for the infrastructure (USD)"
  value = <<EOF
Estimated Monthly Costs:
- RDS MySQL (${var.rds_instance_class}): ~$15-25
- DynamoDB (${var.dynamodb_read_capacity}/${var.dynamodb_write_capacity} RCU/WCU): ~$3-5
- Lambda executions (moderate usage): ~$5-10
- S3 storage and requests: ~$2-5
- Athena queries (data scanned): Variable based on usage
- VPC resources: ~$1-2
Total estimated: ~$26-47/month

Note: Actual costs depend on query frequency, data volume, and usage patterns.
EOF
}

# Access Information
output "athena_console_url" {
  description = "URL to access Athena console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/athena/home?region=${data.aws_region.current.name}#/query-editor"
}

output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

# Resource Summary
output "resource_summary" {
  description = "Summary of deployed resources"
  value = {
    s3_buckets = {
      spill_bucket   = aws_s3_bucket.athena_spill.bucket
      results_bucket = aws_s3_bucket.athena_results.bucket
    }
    networking = {
      vpc_id             = aws_vpc.main.id
      private_subnets    = aws_subnet.private[*].id
      security_group_id  = aws_security_group.rds.id
    }
    databases = {
      rds_endpoint         = aws_db_instance.mysql.endpoint
      rds_database        = aws_db_instance.mysql.db_name
      dynamodb_table      = aws_dynamodb_table.orders.name
    }
    athena = {
      workgroup_name      = aws_athena_workgroup.federated_analytics.name
      mysql_catalog       = aws_athena_data_catalog.mysql.name
      dynamodb_catalog    = aws_athena_data_catalog.dynamodb.name
    }
    lambda_functions = {
      mysql_connector     = "${var.project_name}-mysql-connector"
      dynamodb_connector  = "${var.project_name}-dynamodb-connector"
    }
  }
}