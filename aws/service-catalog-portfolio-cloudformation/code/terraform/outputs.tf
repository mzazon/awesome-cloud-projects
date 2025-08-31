# Output values for Service Catalog Portfolio with CloudFormation Templates

# Portfolio Information
output "portfolio_id" {
  description = "ID of the Service Catalog portfolio"
  value       = aws_servicecatalog_portfolio.main.id
}

output "portfolio_name" {
  description = "Display name of the Service Catalog portfolio"
  value       = aws_servicecatalog_portfolio.main.name
}

output "portfolio_arn" {
  description = "ARN of the Service Catalog portfolio"
  value       = aws_servicecatalog_portfolio.main.arn
}

# Product Information
output "s3_product_id" {
  description = "ID of the S3 bucket Service Catalog product"
  value       = aws_servicecatalog_product.s3_bucket.id
}

output "s3_product_name" {
  description = "Name of the S3 bucket Service Catalog product"
  value       = aws_servicecatalog_product.s3_bucket.name
}

output "s3_product_arn" {
  description = "ARN of the S3 bucket Service Catalog product"
  value       = aws_servicecatalog_product.s3_bucket.arn
}

output "lambda_product_id" {
  description = "ID of the Lambda function Service Catalog product"
  value       = aws_servicecatalog_product.lambda_function.id
}

output "lambda_product_name" {
  description = "Name of the Lambda function Service Catalog product"
  value       = aws_servicecatalog_product.lambda_function.name
}

output "lambda_product_arn" {
  description = "ARN of the Lambda function Service Catalog product"
  value       = aws_servicecatalog_product.lambda_function.arn
}

# Launch Role Information
output "launch_role_arn" {
  description = "ARN of the Service Catalog launch role"
  value       = aws_iam_role.launch_role.arn
}

output "launch_role_name" {
  description = "Name of the Service Catalog launch role"
  value       = aws_iam_role.launch_role.name
}

# S3 Bucket Information
output "templates_bucket_name" {
  description = "Name of the S3 bucket storing CloudFormation templates"
  value       = aws_s3_bucket.templates.id
}

output "templates_bucket_arn" {
  description = "ARN of the S3 bucket storing CloudFormation templates"
  value       = aws_s3_bucket.templates.arn
}

output "templates_bucket_domain_name" {
  description = "Domain name of the S3 bucket storing CloudFormation templates"
  value       = aws_s3_bucket.templates.bucket_domain_name
}

# Template URLs
output "s3_template_url" {
  description = "URL of the S3 bucket CloudFormation template"
  value       = "https://${aws_s3_bucket.templates.bucket_domain_name}/${aws_s3_object.s3_template.key}"
}

output "lambda_template_url" {
  description = "URL of the Lambda function CloudFormation template"
  value       = "https://${aws_s3_bucket.templates.bucket_domain_name}/${aws_s3_object.lambda_template.key}"
}

# Constraint Information
output "s3_launch_constraint_id" {
  description = "ID of the S3 product launch constraint"
  value       = aws_servicecatalog_constraint.s3_launch_constraint.id
}

output "lambda_launch_constraint_id" {
  description = "ID of the Lambda product launch constraint"
  value       = aws_servicecatalog_constraint.lambda_launch_constraint.id
}

# Access Information
output "principal_associations" {
  description = "List of principal ARNs associated with the portfolio"
  value = concat(
    var.principal_arns,
    length(var.principal_arns) == 0 ? [data.aws_caller_identity.current_user.arn] : []
  )
}

# Console URLs for easy access
output "portfolio_console_url" {
  description = "AWS Console URL for the Service Catalog portfolio"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/servicecatalog/home?region=${data.aws_region.current.name}#admin-portfolios/${aws_servicecatalog_portfolio.main.id}"
}

output "end_user_console_url" {
  description = "AWS Console URL for end users to browse Service Catalog products"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/servicecatalog/home?region=${data.aws_region.current.name}#products"
}

# Deployment Information
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.unique_suffix
}

output "deployment_region" {
  description = "AWS region where resources were deployed"
  value       = data.aws_region.current.name
}

output "deployment_account" {
  description = "AWS account ID where resources were deployed"
  value       = data.aws_caller_identity.current.account_id
}