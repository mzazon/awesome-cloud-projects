# ================================
# Core Infrastructure Outputs
# ================================

output "s3_bucket_name" {
  description = "Name of the S3 bucket for MLOps artifacts"
  value       = aws_s3_bucket.mlops_bucket.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for MLOps artifacts"
  value       = aws_s3_bucket.mlops_bucket.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.mlops_bucket.bucket_domain_name
}

output "codecommit_repository_name" {
  description = "Name of the CodeCommit repository"
  value       = aws_codecommit_repository.mlops_repo.repository_name
}

output "codecommit_repository_arn" {
  description = "ARN of the CodeCommit repository"
  value       = aws_codecommit_repository.mlops_repo.arn
}

output "codecommit_repository_clone_url_http" {
  description = "HTTP clone URL of the CodeCommit repository"
  value       = aws_codecommit_repository.mlops_repo.clone_url_http
}

output "codecommit_repository_clone_url_ssh" {
  description = "SSH clone URL of the CodeCommit repository"
  value       = aws_codecommit_repository.mlops_repo.clone_url_ssh
}

# ================================
# IAM and Security Outputs
# ================================

output "sagemaker_execution_role_name" {
  description = "Name of the SageMaker execution role"
  value       = aws_iam_role.sagemaker_execution_role.name
}

output "sagemaker_execution_role_arn" {
  description = "ARN of the SageMaker execution role"
  value       = aws_iam_role.sagemaker_execution_role.arn
}

output "sagemaker_custom_policy_arn" {
  description = "ARN of the custom SageMaker policy"
  value       = aws_iam_policy.sagemaker_custom_policy.arn
}

# ================================
# SageMaker Resources Outputs
# ================================

output "model_package_group_name" {
  description = "Name of the SageMaker Model Package Group"
  value       = aws_sagemaker_model_package_group.mlops_model_group.model_package_group_name
}

output "model_package_group_arn" {
  description = "ARN of the SageMaker Model Package Group"
  value       = aws_sagemaker_model_package_group.mlops_model_group.arn
}

output "pipeline_name" {
  description = "Name of the SageMaker pipeline (configured for creation)"
  value       = local.pipeline_name
}

# ================================
# CloudWatch and Monitoring Outputs
# ================================

output "pipeline_log_group_name" {
  description = "Name of the CloudWatch log group for SageMaker pipeline logs"
  value       = aws_cloudwatch_log_group.sagemaker_pipeline_logs.name
}

output "pipeline_log_group_arn" {
  description = "ARN of the CloudWatch log group for SageMaker pipeline logs"
  value       = aws_cloudwatch_log_group.sagemaker_pipeline_logs.arn
}

output "training_log_group_name" {
  description = "Name of the CloudWatch log group for SageMaker training job logs"
  value       = aws_cloudwatch_log_group.sagemaker_training_logs.name
}

output "training_log_group_arn" {
  description = "ARN of the CloudWatch log group for SageMaker training job logs"
  value       = aws_cloudwatch_log_group.sagemaker_training_logs.arn
}

# ================================
# Data and Configuration Outputs
# ================================

output "training_data_s3_path" {
  description = "S3 path to the training data"
  value       = "s3://${aws_s3_bucket.mlops_bucket.bucket}/${var.pipeline_parameters.training_data_path}"
}

output "validation_data_s3_path" {
  description = "S3 path to the validation data"
  value       = "s3://${aws_s3_bucket.mlops_bucket.bucket}/${var.pipeline_parameters.validation_data_path}"
}

output "model_output_s3_path" {
  description = "S3 path for model artifacts output"
  value       = "s3://${aws_s3_bucket.mlops_bucket.bucket}/${var.pipeline_parameters.output_model_path}"
}

output "training_script_s3_path" {
  description = "S3 path to the training script"
  value       = "s3://${aws_s3_bucket.mlops_bucket.bucket}/code/train.py"
}

output "pipeline_config_s3_path" {
  description = "S3 path to the pipeline configuration file"
  value       = "s3://${aws_s3_bucket.mlops_bucket.bucket}/config/pipeline_config.json"
}

# ================================
# AWS Account and Region Information
# ================================

output "aws_account_id" {
  description = "AWS Account ID where resources are created"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region where resources are created"
  value       = data.aws_region.current.name
}

# ================================
# Resource Tags Output
# ================================

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

# ================================
# Next Steps Information
# ================================

output "next_steps" {
  description = "Instructions for next steps after infrastructure deployment"
  value = {
    step_1 = "Clone the CodeCommit repository: git clone ${aws_codecommit_repository.mlops_repo.clone_url_http}"
    step_2 = "Create your SageMaker pipeline using the AWS SDK or SageMaker Studio"
    step_3 = "Use the provided training script at: s3://${aws_s3_bucket.mlops_bucket.bucket}/code/train.py"
    step_4 = "Monitor pipeline execution in the AWS Console under SageMaker > Pipelines"
    step_5 = "View logs in CloudWatch: ${aws_cloudwatch_log_group.sagemaker_pipeline_logs.name}"
  }
}

# ================================
# SageMaker Pipeline Creation Command
# ================================

output "pipeline_creation_example" {
  description = "Example AWS CLI command to create the SageMaker pipeline"
  value = <<-EOT
    # Use the following Python code to create your SageMaker pipeline:
    
    import boto3
    import sagemaker
    from sagemaker.workflow.pipeline import Pipeline
    from sagemaker.workflow.steps import TrainingStep
    from sagemaker.sklearn.estimator import SKLearn
    
    # Initialize SageMaker session
    sagemaker_session = sagemaker.Session()
    role = "${aws_iam_role.sagemaker_execution_role.arn}"
    
    # Create SKLearn estimator
    sklearn_estimator = SKLearn(
        entry_point="train.py",
        source_dir="s3://${aws_s3_bucket.mlops_bucket.bucket}/code/",
        framework_version="${var.sklearn_framework_version}",
        instance_type="${var.training_instance_type}",
        role=role,
        sagemaker_session=sagemaker_session
    )
    
    # Create training step
    training_step = TrainingStep(
        name="ModelTraining",
        estimator=sklearn_estimator,
        inputs={
            "training": "s3://${aws_s3_bucket.mlops_bucket.bucket}/data/"
        }
    )
    
    # Create and execute pipeline
    pipeline = Pipeline(
        name="${local.pipeline_name}",
        steps=[training_step],
        sagemaker_session=sagemaker_session
    )
    
    pipeline.upsert(role_arn=role)
    execution = pipeline.start()
    print(f"Pipeline execution started: {execution.arn}")
  EOT
}

# ================================
# Cost Estimation Information
# ================================

output "estimated_monthly_costs" {
  description = "Estimated monthly costs for running this MLOps infrastructure"
  value = {
    s3_storage        = "~$0.023 per GB stored (Standard tier)"
    codecommit        = "Free for first 5 users, then $1 per additional user per month"
    cloudwatch_logs   = "~$0.50 per GB ingested, $0.03 per GB stored"
    sagemaker_training = "Depends on instance type and usage time (${var.training_instance_type} ~$0.269/hour when running)"
    iam_roles         = "Free"
    note             = "Actual costs depend on usage patterns. Monitor AWS Cost Explorer for precise tracking."
  }
}