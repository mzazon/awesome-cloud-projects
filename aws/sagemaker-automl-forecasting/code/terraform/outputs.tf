# S3 Bucket Outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for storing training data and model artifacts"
  value       = aws_s3_bucket.forecasting_bucket.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.forecasting_bucket.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.forecasting_bucket.bucket_domain_name
}

# IAM Role Outputs
output "sagemaker_execution_role_arn" {
  description = "ARN of the SageMaker execution role"
  value       = aws_iam_role.sagemaker_execution_role.arn
}

output "sagemaker_execution_role_name" {
  description = "Name of the SageMaker execution role"
  value       = aws_iam_role.sagemaker_execution_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

# Lambda Function Outputs
output "lambda_function_name" {
  description = "Name of the Lambda function for forecast API"
  value       = aws_lambda_function.forecast_api.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.forecast_api.arn
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = aws_lambda_function.forecast_api.invoke_arn
}

# API Gateway Outputs
output "api_gateway_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.forecast_api.id
}

output "api_gateway_url" {
  description = "URL of the API Gateway"
  value       = "https://${aws_api_gateway_rest_api.forecast_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}/forecast"
}

output "api_gateway_stage_name" {
  description = "Stage name of the API Gateway deployment"
  value       = aws_api_gateway_stage.forecast_stage.stage_name
}

# SageMaker Model Package Group Output
output "model_package_group_name" {
  description = "Name of the SageMaker Model Package Group"
  value       = aws_sagemaker_model_package_group.forecasting_model_group.model_package_group_name
}

output "model_package_group_arn" {
  description = "ARN of the SageMaker Model Package Group"
  value       = aws_sagemaker_model_package_group.forecasting_model_group.arn
}

# CloudWatch Outputs
output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = var.enable_monitoring ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.forecasting_dashboard[0].dashboard_name}" : null
}

output "lambda_log_group_name" {
  description = "Name of the Lambda CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda_log_group.name
}

# SNS Topic Output
output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = var.enable_monitoring ? aws_sns_topic.alerts[0].arn : null
}

# KMS Key Outputs
output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = var.enable_encryption ? aws_kms_key.forecasting_key[0].key_id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = var.enable_encryption ? aws_kms_key.forecasting_key[0].arn : null
}

output "kms_key_alias" {
  description = "Alias of the KMS key"
  value       = var.enable_encryption ? aws_kms_alias.forecasting_key_alias[0].name : null
}

# Random Suffix Output
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.name_suffix
}

# Configuration Outputs for Manual Steps
output "automl_job_configuration" {
  description = "Configuration template for creating AutoML job"
  value = {
    AutoMLJobName = "${local.name_prefix}-automl-job-${local.name_suffix}"
    InputDataConfig = [
      {
        ChannelName = "training"
        DataSource = {
          S3DataSource = {
            S3DataType             = "S3Prefix"
            S3Uri                  = "s3://${aws_s3_bucket.forecasting_bucket.bucket}/${var.training_data_s3_prefix}/"
            S3DataDistributionType = "FullyReplicated"
          }
        }
        ContentType         = "text/csv"
        CompressionType     = "None"
        TargetAttributeName = "target_value"
      }
    ]
    OutputDataConfig = {
      S3OutputPath = "s3://${aws_s3_bucket.forecasting_bucket.bucket}/${var.automl_output_s3_prefix}/"
    }
    RoleArn = aws_iam_role.sagemaker_execution_role.arn
    AutoMLProblemTypeConfig = {
      TimeSeriesForecastingJobConfig = {
        ForecastFrequency = "D"
        ForecastHorizon   = var.forecast_horizon
        TimeSeriesConfig = {
          TargetAttributeName      = "target_value"
          TimestampAttributeName   = "timestamp"
          ItemIdentifierAttributeName = "item_id"
        }
        ForecastQuantiles = var.forecast_quantiles
        Transformations = {
          Filling = {
            target_value = "mean"
          }
          Aggregation = {
            target_value = "sum"
          }
        }
        CandidateGenerationConfig = {
          AlgorithmsConfig = [
            {
              AutoMLAlgorithms = [
                "cnn-qr",
                "deepar",
                "prophet",
                "npts",
                "arima",
                "ets"
              ]
            }
          ]
        }
      }
    }
    AutoMLJobObjective = {
      MetricName = "MAPE"
    }
  }
}

output "endpoint_configuration" {
  description = "Configuration template for creating SageMaker endpoint"
  value = {
    endpoint_name        = "${local.name_prefix}-endpoint-${local.name_suffix}"
    endpoint_config_name = "${local.name_prefix}-endpoint-config-${local.name_suffix}"
    model_name           = "${local.name_prefix}-model-${local.name_suffix}"
    instance_type        = var.sagemaker_instance_type
    initial_instance_count = var.endpoint_initial_instance_count
  }
}

# Environment Variables for CLI Operations
output "environment_variables" {
  description = "Environment variables for CLI operations"
  value = {
    AWS_REGION                = data.aws_region.current.name
    AWS_ACCOUNT_ID           = data.aws_caller_identity.current.account_id
    FORECAST_BUCKET          = aws_s3_bucket.forecasting_bucket.bucket
    SAGEMAKER_ROLE_NAME      = aws_iam_role.sagemaker_execution_role.name
    SAGEMAKER_ROLE_ARN       = aws_iam_role.sagemaker_execution_role.arn
    MODEL_PACKAGE_GROUP_NAME = aws_sagemaker_model_package_group.forecasting_model_group.model_package_group_name
    LAMBDA_FUNCTION_NAME     = aws_lambda_function.forecast_api.function_name
    API_GATEWAY_URL          = "https://${aws_api_gateway_rest_api.forecast_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.api_gateway_stage_name}/forecast"
    RESOURCE_SUFFIX          = local.name_suffix
  }
}

# Data Paths
output "s3_data_paths" {
  description = "S3 paths for different types of data"
  value = {
    training_data_path    = "s3://${aws_s3_bucket.forecasting_bucket.bucket}/${var.training_data_s3_prefix}/"
    automl_output_path    = "s3://${aws_s3_bucket.forecasting_bucket.bucket}/${var.automl_output_s3_prefix}/"
    batch_input_path      = "s3://${aws_s3_bucket.forecasting_bucket.bucket}/batch-input/"
    batch_output_path     = "s3://${aws_s3_bucket.forecasting_bucket.bucket}/batch-output/"
    bi_reports_path       = "s3://${aws_s3_bucket.forecasting_bucket.bucket}/bi-reports/"
    results_path          = "s3://${aws_s3_bucket.forecasting_bucket.bucket}/results/"
  }
}

# Sample CLI Commands
output "sample_cli_commands" {
  description = "Sample CLI commands to interact with the infrastructure"
  value = {
    create_automl_job = "aws sagemaker create-auto-ml-job-v2 --cli-input-json file://automl_job_config.json"
    list_automl_jobs  = "aws sagemaker list-auto-ml-jobs --name-contains ${local.name_prefix}"
    invoke_lambda     = "aws lambda invoke --function-name ${aws_lambda_function.forecast_api.function_name} --payload '{\"body\": \"{\\\"item_id\\\": \\\"test_item\\\", \\\"forecast_horizon\\\": 7}\"}' response.json"
    test_api          = "curl -X POST ${self.api_gateway_url} -H 'Content-Type: application/json' -d '{\"item_id\": \"test_item\", \"forecast_horizon\": 14}'"
    upload_data       = "aws s3 cp your_data.csv s3://${aws_s3_bucket.forecasting_bucket.bucket}/${var.training_data_s3_prefix}/"
    download_results  = "aws s3 sync s3://${aws_s3_bucket.forecasting_bucket.bucket}/results/ ./results/"
  }
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    s3_bucket                = aws_s3_bucket.forecasting_bucket.bucket
    sagemaker_role           = aws_iam_role.sagemaker_execution_role.name
    lambda_function          = aws_lambda_function.forecast_api.function_name
    api_gateway              = aws_api_gateway_rest_api.forecast_api.name
    model_package_group      = aws_sagemaker_model_package_group.forecasting_model_group.model_package_group_name
    cloudwatch_dashboard     = var.enable_monitoring ? aws_cloudwatch_dashboard.forecasting_dashboard[0].dashboard_name : "disabled"
    kms_key                  = var.enable_encryption ? aws_kms_key.forecasting_key[0].key_id : "disabled"
    monitoring_enabled       = var.enable_monitoring
    encryption_enabled       = var.enable_encryption
    sample_data_generation   = var.generate_sample_data
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after infrastructure deployment"
  value = [
    "1. Upload training data to S3 bucket: ${aws_s3_bucket.forecasting_bucket.bucket}",
    "2. Create AutoML job using the provided configuration",
    "3. Monitor job progress in SageMaker console",
    "4. Create endpoint from best candidate after job completion",
    "5. Update Lambda environment variable with endpoint name",
    "6. Test forecast API using the provided URL",
    "7. Set up CloudWatch alarms and SNS subscriptions for monitoring",
    "8. Review and customize forecast parameters as needed"
  ]
}