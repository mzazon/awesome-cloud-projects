# VPC and Networking Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "db_subnet_group_name" {
  description = "Name of the DB subnet group"
  value       = aws_db_subnet_group.main.name
}

# Security Group Outputs
output "rds_security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}

output "rds_proxy_security_group_id" {
  description = "ID of the RDS Proxy security group"
  value       = aws_security_group.rds_proxy.id
}

# RDS Instance Outputs
output "rds_instance_id" {
  description = "RDS instance ID"
  value       = aws_db_instance.main.id
}

output "rds_instance_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.main.endpoint
}

output "rds_instance_port" {
  description = "RDS instance port"
  value       = aws_db_instance.main.port
}

output "rds_instance_arn" {
  description = "RDS instance ARN"
  value       = aws_db_instance.main.arn
}

output "rds_instance_status" {
  description = "RDS instance status"
  value       = aws_db_instance.main.status
}

# RDS Proxy Outputs
output "rds_proxy_id" {
  description = "RDS Proxy ID"
  value       = aws_db_proxy.main.id
}

output "rds_proxy_arn" {
  description = "RDS Proxy ARN"
  value       = aws_db_proxy.main.arn
}

output "rds_proxy_endpoint" {
  description = "RDS Proxy endpoint"
  value       = aws_db_proxy.main.endpoint
}

output "rds_proxy_target_endpoint" {
  description = "RDS Proxy target endpoint (use this for applications)"
  value       = aws_db_proxy.main.endpoint
}

# Secrets Manager Outputs
output "db_credentials_secret_arn" {
  description = "ARN of the database credentials secret"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "db_credentials_secret_name" {
  description = "Name of the database credentials secret"
  value       = aws_secretsmanager_secret.db_credentials.name
}

# IAM Role Outputs
output "rds_proxy_role_arn" {
  description = "ARN of the RDS Proxy IAM role"
  value       = aws_iam_role.rds_proxy.arn
}

output "rds_proxy_role_name" {
  description = "Name of the RDS Proxy IAM role"
  value       = aws_iam_role.rds_proxy.name
}

# Lambda Function Outputs (conditional)
output "lambda_function_name" {
  description = "Name of the Lambda test function"
  value       = var.create_lambda_test_function ? aws_lambda_function.test[0].function_name : null
}

output "lambda_function_arn" {
  description = "ARN of the Lambda test function"
  value       = var.create_lambda_test_function ? aws_lambda_function.test[0].arn : null
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = var.create_lambda_test_function ? aws_iam_role.lambda[0].arn : null
}

# Database Connection Information
output "database_connection_info" {
  description = "Database connection information"
  value = {
    proxy_endpoint = aws_db_proxy.main.endpoint
    port          = 3306
    database_name = var.db_name
    username      = var.db_username
  }
  sensitive = false
}

# Connection String Examples
output "connection_examples" {
  description = "Example connection strings for different programming languages"
  value = {
    python_pymysql = "pymysql.connect(host='${aws_db_proxy.main.endpoint}', user='${var.db_username}', password='YOUR_PASSWORD', database='${var.db_name}', port=3306)"
    nodejs_mysql2  = "mysql.createConnection({host: '${aws_db_proxy.main.endpoint}', user: '${var.db_username}', password: 'YOUR_PASSWORD', database: '${var.db_name}', port: 3306})"
    java_jdbc      = "jdbc:mysql://${aws_db_proxy.main.endpoint}:3306/${var.db_name}"
    cli_mysql      = "mysql -h ${aws_db_proxy.main.endpoint} -P 3306 -u ${var.db_username} -p ${var.db_name}"
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    vpc_id                = aws_vpc.main.id
    rds_instance_id       = aws_db_instance.main.id
    rds_proxy_name        = aws_db_proxy.main.name
    proxy_endpoint        = aws_db_proxy.main.endpoint
    secret_name           = aws_secretsmanager_secret.db_credentials.name
    lambda_function_name  = var.create_lambda_test_function ? aws_lambda_function.test[0].function_name : "Not created"
    region               = data.aws_region.current.name
    account_id           = data.aws_caller_identity.current.account_id
  }
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for major resources (USD)"
  value = {
    rds_instance     = "~$15-25 (db.t3.micro with 20GB storage)"
    rds_proxy        = "~$11 ($0.015/hour)"
    secrets_manager  = "~$0.40 ($0.40/secret/month)"
    lambda          = "~$0 (within free tier for testing)"
    data_transfer   = "Variable based on usage"
    total_estimated = "~$27-37/month"
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Test connectivity using the Lambda function: aws lambda invoke --function-name ${var.create_lambda_test_function ? aws_lambda_function.test[0].function_name : "LAMBDA_FUNCTION_NAME"} output.json",
    "2. Monitor RDS Proxy metrics in CloudWatch under AWS/RDS namespace",
    "3. Update your application connection strings to use the proxy endpoint: ${aws_db_proxy.main.endpoint}",
    "4. Configure connection pooling parameters based on your application's needs",
    "5. Set up CloudWatch alarms for connection pool utilization and errors",
    "6. Consider enabling automatic credential rotation in Secrets Manager"
  ]
}