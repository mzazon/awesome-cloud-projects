# Outputs for Amazon Polly Text-to-Speech Solutions
# This file defines all output values that will be displayed after deployment

# Core Infrastructure Outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for audio file storage"
  value       = aws_s3_bucket.audio_storage.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for audio file storage"
  value       = aws_s3_bucket.audio_storage.arn
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.audio_storage.bucket_regional_domain_name
}

output "lambda_function_name" {
  description = "Name of the Lambda function for batch processing"
  value       = aws_lambda_function.polly_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for batch processing"
  value       = aws_lambda_function.polly_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.polly_processor.invoke_arn
}

output "iam_role_name" {
  description = "Name of the IAM role used by Lambda function"
  value       = aws_iam_role.lambda_execution_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role used by Lambda function"
  value       = aws_iam_role.lambda_execution_role.arn
}

# CloudWatch Outputs
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

# CloudFront Outputs (conditional)
output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution (if enabled)"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.audio_cdn[0].id : null
}

output "cloudfront_distribution_domain_name" {
  description = "Domain name of the CloudFront distribution (if enabled)"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.audio_cdn[0].domain_name : null
}

output "cloudfront_distribution_hosted_zone_id" {
  description = "Hosted zone ID of the CloudFront distribution (if enabled)"
  value       = var.enable_cloudfront ? aws_cloudfront_distribution.audio_cdn[0].hosted_zone_id : null
}

# API Gateway Outputs (conditional)
output "api_gateway_rest_api_id" {
  description = "ID of the API Gateway REST API (if enabled)"
  value       = var.enable_api_gateway ? aws_api_gateway_rest_api.polly_api[0].id : null
}

output "api_gateway_deployment_invoke_url" {
  description = "Invoke URL of the API Gateway deployment (if enabled)"
  value       = var.enable_api_gateway ? aws_api_gateway_deployment.polly_api_deployment[0].invoke_url : null
}

output "api_gateway_synthesize_endpoint" {
  description = "Full URL for the synthesize endpoint (if API Gateway enabled)"
  value       = var.enable_api_gateway ? "${aws_api_gateway_deployment.polly_api_deployment[0].invoke_url}/synthesize" : null
}

# Custom Lexicon Outputs
output "custom_lexicons" {
  description = "Map of custom lexicon names and their ARNs"
  value = {
    for name, lexicon in aws_polly_lexicon.custom_lexicons : name => {
      name = lexicon.name
      arn  = lexicon.arn
    }
  }
}

# Configuration and Usage Information
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "default_voice_id" {
  description = "Default Amazon Polly voice ID configured"
  value       = var.default_voice_id
}

output "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  value       = aws_lambda_function.polly_processor.timeout
}

output "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  value       = aws_lambda_function.polly_processor.memory_size
}

# Useful CLI Commands
output "cli_commands" {
  description = "Useful AWS CLI commands for interacting with the deployed resources"
  value = {
    # S3 commands
    upload_text_file = "aws s3 cp your-text-file.txt s3://${aws_s3_bucket.audio_storage.bucket}/text/ --metadata voice-id=${var.default_voice_id},engine=neural"
    list_audio_files = "aws s3 ls s3://${aws_s3_bucket.audio_storage.bucket}/audio/ --recursive"
    download_audio   = "aws s3 cp s3://${aws_s3_bucket.audio_storage.bucket}/audio/your-file.mp3 ./downloaded-audio.mp3"
    
    # Lambda commands
    invoke_lambda_direct = "aws lambda invoke --function-name ${aws_lambda_function.polly_processor.function_name} --payload '{\"text\":\"Hello from Polly!\",\"voice_id\":\"${var.default_voice_id}\"}' response.json"
    view_lambda_logs     = "aws logs tail /aws/lambda/${aws_lambda_function.polly_processor.function_name} --follow"
    
    # Polly commands
    list_voices          = "aws polly describe-voices --engine neural --query 'Voices[?LanguageCode==`en-US`]'"
    synthesize_direct    = "aws polly synthesize-speech --text 'Hello World' --voice-id ${var.default_voice_id} --output-format mp3 --engine neural hello.mp3"
  }
}

# Testing and Validation Information
output "testing_information" {
  description = "Information for testing the deployed Polly TTS solution"
  value = {
    s3_upload_path_for_auto_processing = "s3://${aws_s3_bucket.audio_storage.bucket}/text/"
    s3_audio_output_path              = "s3://${aws_s3_bucket.audio_storage.bucket}/audio/"
    
    sample_lambda_payload = jsonencode({
      text     = "This is a sample text for testing Amazon Polly text-to-speech conversion."
      voice_id = var.default_voice_id
      engine   = "neural"
    })
    
    sample_ssml_payload = jsonencode({
      text      = "<speak>Welcome to <emphasis level=\"strong\">Amazon Polly</emphasis>. <break time=\"500ms\"/> This is a test of SSML markup.</speak>"
      voice_id  = var.default_voice_id
      engine    = "neural"
      text_type = "ssml"
    })
  }
}

# Cost Optimization Information
output "cost_optimization_tips" {
  description = "Tips for optimizing costs with the deployed solution"
  value = {
    s3_lifecycle_policy = "Configured to transition files to IA after 30 days and Glacier after 90 days"
    polly_pricing_info  = "Neural voices: $16 per 1M characters. Standard voices: $4 per 1M characters. Long-form/Generative: $100 per 1M characters"
    lambda_optimization = "Function memory: ${aws_lambda_function.polly_processor.memory_size}MB, timeout: ${aws_lambda_function.polly_processor.timeout}s"
    
    recommendations = [
      "Use caching to avoid re-synthesizing the same content",
      "Consider using standard voices for non-customer-facing content",
      "Implement batch processing for multiple files to reduce Lambda invocations",
      "Use S3 Intelligent Tiering for unknown access patterns",
      "Monitor CloudWatch metrics to optimize Lambda memory allocation"
    ]
  }
}

# Security and Compliance Information
output "security_configuration" {
  description = "Security features configured in the deployment"
  value = {
    s3_encryption          = var.enable_s3_encryption ? "AES256 server-side encryption enabled" : "Encryption disabled"
    s3_public_access_block = "All public access blocked"
    iam_principle          = "Least privilege access configured"
    cloudfront_https       = var.enable_cloudfront ? "HTTPS redirect enforced" : "CloudFront not enabled"
    
    security_recommendations = [
      "Enable AWS CloudTrail for API logging",
      "Consider using AWS KMS for S3 encryption if handling sensitive content",
      "Implement VPC endpoints for private API access",
      "Enable AWS Config for compliance monitoring",
      "Use AWS WAF with API Gateway for DDoS protection"
    ]
  }
}