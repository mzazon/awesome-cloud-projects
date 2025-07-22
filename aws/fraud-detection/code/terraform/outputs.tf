# Resource identifiers and names
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# S3 bucket outputs
output "training_data_bucket_name" {
  description = "Name of the S3 bucket for training data"
  value       = aws_s3_bucket.training_data.bucket
}

output "training_data_bucket_arn" {
  description = "ARN of the S3 bucket for training data"
  value       = aws_s3_bucket.training_data.arn
}

output "training_data_bucket_domain_name" {
  description = "Bucket domain name of the S3 bucket"
  value       = aws_s3_bucket.training_data.bucket_domain_name
}

output "sample_training_data_key" {
  description = "S3 object key for the sample training data"
  value       = var.create_sample_data ? aws_s3_object.sample_training_data[0].key : null
}

# IAM role outputs
output "fraud_detector_service_role_arn" {
  description = "ARN of the IAM role for Amazon Fraud Detector"
  value       = aws_iam_role.fraud_detector_service_role.arn
}

output "fraud_detector_service_role_name" {
  description = "Name of the IAM role for Amazon Fraud Detector"
  value       = aws_iam_role.fraud_detector_service_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

# Amazon Fraud Detector resource outputs
output "entity_type_name" {
  description = "Name of the customer entity type"
  value       = aws_frauddetector_entity_type.customer.name
}

output "event_type_name" {
  description = "Name of the payment fraud event type"
  value       = aws_frauddetector_event_type.payment_fraud.name
}

output "model_name" {
  description = "Name of the fraud detection model"
  value       = aws_frauddetector_model.fraud_detection_model.model_id
}

output "model_type" {
  description = "Type of the fraud detection model"
  value       = aws_frauddetector_model.fraud_detection_model.model_type
}

output "detector_name" {
  description = "Name of the fraud detector"
  value       = aws_frauddetector_detector.payment_fraud_detector.detector_id
}

# Labels and outcomes
output "fraud_label_name" {
  description = "Name of the fraud label"
  value       = aws_frauddetector_label.fraud.name
}

output "legit_label_name" {
  description = "Name of the legitimate label"
  value       = aws_frauddetector_label.legit.name
}

output "review_outcome_name" {
  description = "Name of the review outcome"
  value       = aws_frauddetector_outcome.review.name
}

output "block_outcome_name" {
  description = "Name of the block outcome"
  value       = aws_frauddetector_outcome.block.name
}

output "approve_outcome_name" {
  description = "Name of the approve outcome"
  value       = aws_frauddetector_outcome.approve.name
}

# Event variables
output "event_variables" {
  description = "List of event variable names"
  value       = [for v in aws_frauddetector_variable.event_variables : v.name]
}

# Lambda function outputs
output "lambda_function_name" {
  description = "Name of the fraud processing Lambda function"
  value       = aws_lambda_function.fraud_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the fraud processing Lambda function"
  value       = aws_lambda_function.fraud_processor.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the fraud processing Lambda function"
  value       = aws_lambda_function.fraud_processor.invoke_arn
}

# Configuration values
output "configuration_summary" {
  description = "Summary of fraud detection system configuration"
  value = {
    environment                     = var.environment
    project_name                   = var.project_name
    high_risk_score_threshold      = var.high_risk_score_threshold
    fraud_score_threshold          = var.fraud_score_threshold
    high_value_transaction_threshold = var.high_value_transaction_threshold
    rule_execution_mode            = var.rule_execution_mode
    model_type                     = var.model_type
    event_ingestion                = var.event_ingestion
  }
}

# AWS account and region information
output "aws_account_id" {
  description = "AWS account ID where resources are created"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region where resources are created"
  value       = data.aws_region.current.name
}

# Resource URLs and endpoints
output "s3_console_url" {
  description = "AWS Console URL for the S3 bucket"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.training_data.bucket}"
}

output "fraud_detector_console_url" {
  description = "AWS Console URL for the Fraud Detector"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/frauddetector/home?region=${data.aws_region.current.name}#/detectors/${aws_frauddetector_detector.payment_fraud_detector.detector_id}"
}

output "lambda_console_url" {
  description = "AWS Console URL for the Lambda function"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/lambda/home?region=${data.aws_region.current.name}#/functions/${aws_lambda_function.fraud_processor.function_name}"
}

# Next steps and usage information
output "next_steps" {
  description = "Next steps for using the fraud detection system"
  value = <<-EOT
    Fraud Detection System Deployment Complete!
    
    1. Monitor model training status:
       aws frauddetector describe-model-versions \
         --model-id ${aws_frauddetector_model.fraud_detection_model.model_id} \
         --model-type ${aws_frauddetector_model.fraud_detection_model.model_type}
    
    2. Once training is complete, create and activate detector version:
       aws frauddetector create-detector-version \
         --detector-id ${aws_frauddetector_detector.payment_fraud_detector.detector_id} \
         --description "Initial detector version" \
         --model-versions '[{"modelId":"${aws_frauddetector_model.fraud_detection_model.model_id}","modelType":"${aws_frauddetector_model.fraud_detection_model.model_type}","modelVersionNumber":"1.0"}]' \
         --rule-execution-mode ${var.rule_execution_mode}
    
    3. Test fraud predictions:
       aws lambda invoke \
         --function-name ${aws_lambda_function.fraud_processor.function_name} \
         --payload '{"transaction":{"customer_id":"test123","order_price":100.00},"detector_id":"${aws_frauddetector_detector.payment_fraud_detector.detector_id}","event_type_name":"${aws_frauddetector_event_type.payment_fraud.name}","entity_type_name":"${aws_frauddetector_entity_type.customer.name}","transaction_id":"test_txn_001"}' \
         response.json
    
    4. Monitor resources in AWS Console:
       - S3 Bucket: ${aws_s3_bucket.training_data.bucket}
       - Fraud Detector: ${aws_frauddetector_detector.payment_fraud_detector.detector_id}
       - Lambda Function: ${aws_lambda_function.fraud_processor.function_name}
    
    Note: Model training typically takes 45-60 minutes to complete.
  EOT
}

# Warning about costs
output "cost_warning" {
  description = "Important cost information"
  value = <<-EOT
    COST WARNING:
    - Model training costs approximately $1-5 per hour
    - Each fraud prediction costs $7.50 per 1,000 requests
    - S3 storage costs apply for training data
    - Lambda execution costs apply per invocation
    
    Remember to destroy resources when no longer needed:
    terraform destroy
  EOT
}