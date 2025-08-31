# S3 bucket information
output "s3_bucket_name" {
  description = "Name of the created S3 bucket for file organization"
  value       = aws_s3_bucket.file_organizer.id
}

output "s3_bucket_arn" {
  description = "ARN of the created S3 bucket"
  value       = aws_s3_bucket.file_organizer.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.file_organizer.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.file_organizer.bucket_regional_domain_name
}

# Lambda function information
output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.file_organizer.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.file_organizer.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.file_organizer.invoke_arn
}

output "lambda_function_version" {
  description = "Latest version of the Lambda function"
  value       = aws_lambda_function.file_organizer.version
}

# IAM role information
output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

# CloudWatch log group information
output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

# Organization folders created
output "organization_folders" {
  description = "List of organization folders created in the S3 bucket"
  value       = var.organization_folders
}

# Upload instructions
output "upload_instructions" {
  description = "Instructions for uploading files to trigger organization"
  value = <<-EOT
    Upload files to the S3 bucket using AWS CLI:
    
    aws s3 cp your-file.jpg s3://${aws_s3_bucket.file_organizer.id}/
    aws s3 cp your-document.pdf s3://${aws_s3_bucket.file_organizer.id}/
    
    Files will be automatically organized into folders:
    - Images: ${join(", ", [for folder in var.organization_folders : folder if folder == "images"])}
    - Documents: ${join(", ", [for folder in var.organization_folders : folder if folder == "documents"])}
    - Videos: ${join(", ", [for folder in var.organization_folders : folder if folder == "videos"])}
    - Other: ${join(", ", [for folder in var.organization_folders : folder if folder == "other"])}
  EOT
}

# Monitoring and troubleshooting
output "cloudwatch_logs_url" {
  description = "URL to view CloudWatch logs for the Lambda function"
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.lambda_logs.name, "/", "$252F")}"
}

output "s3_console_url" {
  description = "URL to view the S3 bucket in AWS Console"
  value = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.file_organizer.id}?region=${var.aws_region}"
}

output "lambda_console_url" {
  description = "URL to view the Lambda function in AWS Console"
  value = "https://${var.aws_region}.console.aws.amazon.com/lambda/home?region=${var.aws_region}#/functions/${aws_lambda_function.file_organizer.function_name}"
}