# ==========================================
# CORE INFRASTRUCTURE OUTPUTS
# ==========================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for ML artifacts"
  value       = aws_s3_bucket.ml_artifacts.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for ML artifacts"
  value       = aws_s3_bucket.ml_artifacts.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.ml_artifacts.bucket_domain_name
}

# ==========================================
# IAM ROLE OUTPUTS
# ==========================================

output "sagemaker_role_arn" {
  description = "ARN of the SageMaker execution role"
  value       = aws_iam_role.sagemaker_role.arn
}

output "sagemaker_role_name" {
  description = "Name of the SageMaker execution role"
  value       = aws_iam_role.sagemaker_role.name
}

output "stepfunctions_role_arn" {
  description = "ARN of the Step Functions execution role"
  value       = aws_iam_role.stepfunctions_role.arn
}

output "stepfunctions_role_name" {
  description = "Name of the Step Functions execution role"
  value       = aws_iam_role.stepfunctions_role.name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_role.name
}

# ==========================================
# STEP FUNCTIONS OUTPUTS
# ==========================================

output "step_functions_state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.ml_pipeline.arn
}

output "step_functions_state_machine_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.ml_pipeline.name
}

output "step_functions_console_url" {
  description = "URL to view the Step Functions state machine in AWS Console"
  value       = "https://console.aws.amazon.com/states/home?region=${data.aws_region.current.name}#/statemachines/view/${aws_sfn_state_machine.ml_pipeline.arn}"
}

# ==========================================
# LAMBDA FUNCTION OUTPUTS
# ==========================================

output "lambda_function_name" {
  description = "Name of the Lambda function for model evaluation"
  value       = aws_lambda_function.evaluate_model.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for model evaluation"
  value       = aws_lambda_function.evaluate_model.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.evaluate_model.invoke_arn
}

# ==========================================
# SAMPLE DATA LAMBDA OUTPUTS
# ==========================================

output "sample_data_lambda_function_name" {
  description = "Name of the Lambda function for creating sample data"
  value       = var.create_sample_data ? aws_lambda_function.create_sample_data[0].function_name : null
}

output "sample_data_lambda_function_arn" {
  description = "ARN of the Lambda function for creating sample data"
  value       = var.create_sample_data ? aws_lambda_function.create_sample_data[0].arn : null
}

# ==========================================
# CLOUDWATCH OUTPUTS
# ==========================================

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "stepfunctions_log_group_name" {
  description = "Name of the CloudWatch log group for Step Functions"
  value       = aws_cloudwatch_log_group.stepfunctions_logs.name
}

output "stepfunctions_log_group_arn" {
  description = "ARN of the CloudWatch log group for Step Functions"
  value       = aws_cloudwatch_log_group.stepfunctions_logs.arn
}

# ==========================================
# SNS OUTPUTS
# ==========================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for pipeline notifications"
  value       = var.enable_sns_notifications ? aws_sns_topic.pipeline_notifications[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for pipeline notifications"
  value       = var.enable_sns_notifications ? aws_sns_topic.pipeline_notifications[0].name : null
}

# ==========================================
# SAGEMAKER CONFIGURATION OUTPUTS
# ==========================================

output "sagemaker_processing_instance_type" {
  description = "Instance type used for SageMaker processing jobs"
  value       = var.sagemaker_processing_instance_type
}

output "sagemaker_training_instance_type" {
  description = "Instance type used for SageMaker training jobs"
  value       = var.sagemaker_training_instance_type
}

output "sagemaker_endpoint_instance_type" {
  description = "Instance type used for SageMaker endpoints"
  value       = var.sagemaker_endpoint_instance_type
}

# ==========================================
# PIPELINE CONFIGURATION OUTPUTS
# ==========================================

output "model_performance_threshold" {
  description = "R2 score threshold for model deployment"
  value       = var.model_performance_threshold
}

output "project_name" {
  description = "Name of the ML pipeline project"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "unique_suffix" {
  description = "Unique suffix used for resource naming"
  value       = local.unique_suffix
}

# ==========================================
# DEPLOYMENT GUIDANCE OUTPUTS
# ==========================================

output "pipeline_execution_command" {
  description = "AWS CLI command to execute the ML pipeline"
  value = <<-EOT
# Generate unique job names
TIMESTAMP=$(date +%Y%m%d%H%M%S)
PREPROCESSING_JOB_NAME="preprocessing-$TIMESTAMP"
TRAINING_JOB_NAME="training-$TIMESTAMP"
MODEL_NAME="model-$TIMESTAMP"
ENDPOINT_CONFIG_NAME="endpoint-config-$TIMESTAMP"
ENDPOINT_NAME="endpoint-$TIMESTAMP"

# Execute the pipeline
aws stepfunctions start-execution \
    --state-machine-arn ${aws_sfn_state_machine.ml_pipeline.arn} \
    --name "execution-$TIMESTAMP" \
    --input '{
      "PreprocessingJobName": "'$PREPROCESSING_JOB_NAME'",
      "TrainingJobName": "'$TRAINING_JOB_NAME'",
      "ModelName": "'$MODEL_NAME'",
      "EndpointConfigName": "'$ENDPOINT_CONFIG_NAME'",
      "EndpointName": "'$ENDPOINT_NAME'",
      "ModelDataUrl": "s3://${aws_s3_bucket.ml_artifacts.id}/model-artifacts/'$TRAINING_JOB_NAME'/output/model.tar.gz"
    }'
EOT
}

output "monitoring_commands" {
  description = "Commands for monitoring pipeline execution"
  value = <<-EOT
# List recent executions
aws stepfunctions list-executions \
    --state-machine-arn ${aws_sfn_state_machine.ml_pipeline.arn} \
    --max-items 10

# Describe specific execution (replace EXECUTION_ARN)
aws stepfunctions describe-execution \
    --execution-arn EXECUTION_ARN

# View logs
aws logs tail /aws/stepfunctions/${aws_sfn_state_machine.ml_pipeline.name} --follow
aws logs tail /aws/lambda/${aws_lambda_function.evaluate_model.function_name} --follow
EOT
}

output "testing_commands" {
  description = "Commands for testing the deployed model endpoint"
  value = <<-EOT
# Test prediction (replace ENDPOINT_NAME with actual endpoint name)
echo '{
  "instances": [
    [0.02729, 0.0, 7.07, 0, 0.469, 7.185, 61.1, 4.9671, 2, 242, 17.8, 392.83, 4.03]
  ]
}' > test-prediction.json

aws sagemaker-runtime invoke-endpoint \
    --endpoint-name ENDPOINT_NAME \
    --content-type application/json \
    --body file://test-prediction.json \
    prediction-output.json

cat prediction-output.json
EOT
}

output "cleanup_commands" {
  description = "Commands for cleaning up resources not managed by Terraform"
  value = <<-EOT
# List and delete SageMaker endpoints
aws sagemaker list-endpoints --name-contains ${var.project_name} --query 'Endpoints[*].EndpointName' --output text | xargs -I {} aws sagemaker delete-endpoint --endpoint-name {}

# List and delete endpoint configurations
aws sagemaker list-endpoint-configs --name-contains ${var.project_name} --query 'EndpointConfigs[*].EndpointConfigName' --output text | xargs -I {} aws sagemaker delete-endpoint-config --endpoint-config-name {}

# List and delete models
aws sagemaker list-models --name-contains ${var.project_name} --query 'Models[*].ModelName' --output text | xargs -I {} aws sagemaker delete-model --model-name {}

# Note: Run 'terraform destroy' to remove all other resources
EOT
}

# ==========================================
# RESOURCE SUMMARY OUTPUT
# ==========================================

output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    s3_bucket                = aws_s3_bucket.ml_artifacts.id
    step_functions_state_machine = aws_sfn_state_machine.ml_pipeline.name
    lambda_function          = aws_lambda_function.evaluate_model.function_name
    sagemaker_role          = aws_iam_role.sagemaker_role.name
    stepfunctions_role      = aws_iam_role.stepfunctions_role.name
    lambda_role             = aws_iam_role.lambda_role.name
    sns_topic               = var.enable_sns_notifications ? aws_sns_topic.pipeline_notifications[0].name : "disabled"
    sample_data_created     = var.create_sample_data
    cloudwatch_retention_days = var.cloudwatch_log_retention_days
  }
}