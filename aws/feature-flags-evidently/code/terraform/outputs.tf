# Outputs for CloudWatch Evidently feature flags infrastructure

output "evidently_project_name" {
  description = "Name of the CloudWatch Evidently project"
  value       = aws_evidently_project.main.name
}

output "evidently_project_arn" {
  description = "ARN of the CloudWatch Evidently project"
  value       = aws_evidently_project.main.arn
}

output "evidently_project_status" {
  description = "Status of the CloudWatch Evidently project"
  value       = aws_evidently_project.main.status
}

output "feature_flag_name" {
  description = "Name of the created feature flag"
  value       = aws_evidently_feature.checkout_flow.name
}

output "feature_flag_arn" {
  description = "ARN of the created feature flag"
  value       = aws_evidently_feature.checkout_flow.arn
}

output "feature_flag_status" {
  description = "Status of the feature flag"
  value       = aws_evidently_feature.checkout_flow.status
}

output "launch_name" {
  description = "Name of the Evidently launch configuration"
  value       = aws_evidently_launch.gradual_rollout.name
}

output "launch_arn" {
  description = "ARN of the Evidently launch configuration"
  value       = aws_evidently_launch.gradual_rollout.arn
}

output "launch_status" {
  description = "Status of the launch configuration"
  value       = aws_evidently_launch.gradual_rollout.status
}

output "lambda_function_name" {
  description = "Name of the Lambda function for feature evaluation"
  value       = aws_lambda_function.evidently_demo.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.evidently_demo.arn
}

output "lambda_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.evidently_demo.invoke_arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Evidently evaluations"
  value       = var.enable_data_delivery ? aws_cloudwatch_log_group.evidently_evaluations[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Evidently evaluations"
  value       = var.enable_data_delivery ? aws_cloudwatch_log_group.evidently_evaluations[0].arn : null
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.arn
}

output "treatment_traffic_percentage" {
  description = "Percentage of traffic routed to the treatment group"
  value       = var.treatment_traffic_percentage
}

output "control_traffic_percentage" {
  description = "Percentage of traffic routed to the control group"
  value       = 100 - var.treatment_traffic_percentage
}

# Sample Lambda invocation command
output "sample_lambda_invoke_command" {
  description = "Sample AWS CLI command to invoke the Lambda function"
  value = format("aws lambda invoke --function-name %s --payload '{\"userId\": \"test-user-123\"}' response.json", aws_lambda_function.evidently_demo.function_name)
}

# Sample feature evaluation commands
output "feature_evaluation_commands" {
  description = "Sample commands to interact with the feature flag"
  value = {
    get_feature = format("aws evidently get-feature --project %s --feature %s", 
                        aws_evidently_project.main.name, 
                        aws_evidently_feature.checkout_flow.name)
    get_launch = format("aws evidently get-launch --project %s --launch %s", 
                       aws_evidently_project.main.name, 
                       aws_evidently_launch.gradual_rollout.name)
    start_launch = format("aws evidently start-launch --project %s --launch %s", 
                         aws_evidently_project.main.name, 
                         aws_evidently_launch.gradual_rollout.name)
    stop_launch = format("aws evidently stop-launch --project %s --launch %s", 
                        aws_evidently_project.main.name, 
                        aws_evidently_launch.gradual_rollout.name)
  }
}