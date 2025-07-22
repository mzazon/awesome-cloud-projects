output "project_name" {
  description = "Name of the project with unique suffix"
  value       = local.project_name_with_suffix
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

# S3 Bucket outputs
output "s3_bucket_name" {
  description = "Name of the S3 bucket for checkpoints and workflows"
  value       = aws_s3_bucket.checkpoints.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for checkpoints and workflows"
  value       = aws_s3_bucket.checkpoints.arn
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.checkpoints.bucket_regional_domain_name
}

# DynamoDB outputs
output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for workflow state"
  value       = aws_dynamodb_table.workflow_state.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table for workflow state"
  value       = aws_dynamodb_table.workflow_state.arn
}

# Step Functions outputs
output "state_machine_name" {
  description = "Name of the Step Functions state machine"
  value       = aws_sfn_state_machine.hpc_workflow.name
}

output "state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  value       = aws_sfn_state_machine.hpc_workflow.arn
}

output "state_machine_definition" {
  description = "Definition of the Step Functions state machine"
  value       = aws_sfn_state_machine.hpc_workflow.definition
  sensitive   = true
}

# Lambda function outputs
output "lambda_functions" {
  description = "Information about Lambda functions"
  value = {
    spot_fleet_manager = {
      function_name = aws_lambda_function.spot_fleet_manager.function_name
      arn          = aws_lambda_function.spot_fleet_manager.arn
      invoke_arn   = aws_lambda_function.spot_fleet_manager.invoke_arn
    }
    checkpoint_manager = {
      function_name = aws_lambda_function.checkpoint_manager.function_name
      arn          = aws_lambda_function.checkpoint_manager.arn
      invoke_arn   = aws_lambda_function.checkpoint_manager.invoke_arn
    }
    workflow_parser = {
      function_name = aws_lambda_function.workflow_parser.function_name
      arn          = aws_lambda_function.workflow_parser.arn
      invoke_arn   = aws_lambda_function.workflow_parser.invoke_arn
    }
    spot_interruption_handler = {
      function_name = aws_lambda_function.spot_interruption_handler.function_name
      arn          = aws_lambda_function.spot_interruption_handler.arn
      invoke_arn   = aws_lambda_function.spot_interruption_handler.invoke_arn
    }
  }
}

# AWS Batch outputs
output "batch_compute_environment_name" {
  description = "Name of the Batch compute environment"
  value       = aws_batch_compute_environment.hpc_compute.compute_environment_name
}

output "batch_compute_environment_arn" {
  description = "ARN of the Batch compute environment"
  value       = aws_batch_compute_environment.hpc_compute.arn
}

output "batch_job_queue_name" {
  description = "Name of the Batch job queue"
  value       = aws_batch_job_queue.hpc_queue.name
}

output "batch_job_queue_arn" {
  description = "ARN of the Batch job queue"
  value       = aws_batch_job_queue.hpc_queue.arn
}

output "batch_job_definition_name" {
  description = "Name of the Batch job definition"
  value       = aws_batch_job_definition.hpc_job.name
}

output "batch_job_definition_arn" {
  description = "ARN of the Batch job definition"
  value       = aws_batch_job_definition.hpc_job.arn
}

# IAM role outputs
output "iam_roles" {
  description = "Information about IAM roles"
  value = {
    stepfunctions_role = {
      name = aws_iam_role.stepfunctions_role.name
      arn  = aws_iam_role.stepfunctions_role.arn
    }
    lambda_role = {
      name = aws_iam_role.lambda_role.name
      arn  = aws_iam_role.lambda_role.arn
    }
    spot_fleet_role = {
      name = aws_iam_role.spot_fleet_role.name
      arn  = aws_iam_role.spot_fleet_role.arn
    }
    ec2_instance_role = {
      name = aws_iam_role.ec2_instance_role.name
      arn  = aws_iam_role.ec2_instance_role.arn
    }
    batch_service_role = {
      name = aws_iam_role.batch_service_role.name
      arn  = aws_iam_role.batch_service_role.arn
    }
  }
}

# Security Group outputs
output "security_group_id" {
  description = "ID of the security group for HPC instances"
  value       = aws_security_group.hpc_instances.id
}

output "security_group_arn" {
  description = "ARN of the security group for HPC instances"
  value       = aws_security_group.hpc_instances.arn
}

# VPC and networking outputs
output "vpc_id" {
  description = "ID of the VPC used for resources"
  value       = local.vpc_id
}

output "subnet_ids" {
  description = "List of subnet IDs used for resources"
  value       = local.subnet_ids
}

output "availability_zones" {
  description = "List of availability zones used"
  value       = data.aws_availability_zones.available.names
}

# SNS outputs
output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = var.enable_alerts ? aws_sns_topic.alerts[0].arn : null
}

output "sns_topic_name" {
  description = "Name of the SNS topic for alerts"
  value       = var.enable_alerts ? aws_sns_topic.alerts[0].name : null
}

# CloudWatch outputs
output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value = var.enable_monitoring ? "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.hpc_monitoring[0].dashboard_name}" : null
}

output "cloudwatch_log_groups" {
  description = "CloudWatch log groups for Lambda functions"
  value = {
    for name, log_group in aws_cloudwatch_log_group.lambda_logs :
    name => {
      name = log_group.name
      arn  = log_group.arn
    }
  }
}

# EventBridge outputs
output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for Spot interruptions"
  value       = aws_cloudwatch_event_rule.spot_interruption.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for Spot interruptions"
  value       = aws_cloudwatch_event_rule.spot_interruption.arn
}

# Sample workflow outputs
output "sample_workflow_s3_key" {
  description = "S3 key of the sample workflow definition"
  value       = aws_s3_object.sample_workflow.key
}

output "sample_workflow_s3_url" {
  description = "S3 URL of the sample workflow definition"
  value       = "s3://${aws_s3_bucket.checkpoints.id}/${aws_s3_object.sample_workflow.key}"
}

# Monitoring URLs
output "step_functions_console_url" {
  description = "URL to the Step Functions console for this state machine"
  value       = "https://console.aws.amazon.com/states/home?region=${data.aws_region.current.name}#/statemachines/view/${aws_sfn_state_machine.hpc_workflow.arn}"
}

output "batch_console_url" {
  description = "URL to the Batch console for this job queue"
  value       = "https://console.aws.amazon.com/batch/home?region=${data.aws_region.current.name}#/queues/detail/${aws_batch_job_queue.hpc_queue.name}"
}

output "s3_console_url" {
  description = "URL to the S3 console for the checkpoints bucket"
  value       = "https://console.aws.amazon.com/s3/buckets/${aws_s3_bucket.checkpoints.id}?region=${data.aws_region.current.name}"
}

output "dynamodb_console_url" {
  description = "URL to the DynamoDB console for the workflow state table"
  value       = "https://console.aws.amazon.com/dynamodb/home?region=${data.aws_region.current.name}#tables:selected=${aws_dynamodb_table.workflow_state.name}"
}

# Cost estimation outputs
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (for reference only)"
  value = {
    description = "Estimated costs are based on minimal usage and may vary significantly based on actual workload"
    step_functions = "~$25/month for 1000 state transitions/day"
    lambda = "~$20/month for 10,000 invocations/day"
    s3 = "~$23/month for 1TB storage"
    dynamodb = "~$25/month for 1GB storage with on-demand billing"
    batch = "Variable based on EC2 instance usage"
    cloudwatch = "~$10/month for logs and metrics"
    total_fixed = "~$103/month + variable compute costs"
  }
}

# Usage instructions
output "usage_instructions" {
  description = "Instructions for using the deployed infrastructure"
  value = {
    step_1 = "Review the sample workflow at s3://${aws_s3_bucket.checkpoints.id}/${aws_s3_object.sample_workflow.key}"
    step_2 = "Modify the workflow definition for your specific HPC requirements"
    step_3 = "Update the Batch job definition with your container images"
    step_4 = "Configure EC2 key pair if SSH access is needed"
    step_5 = "Start workflow execution using the AWS CLI or console"
    step_6 = "Monitor progress in the Step Functions console"
    step_7 = "Check CloudWatch logs for detailed execution information"
    step_8 = "Review checkpoints and results in the S3 bucket"
  }
}

# Security considerations
output "security_considerations" {
  description = "Important security considerations for this deployment"
  value = {
    encryption = var.enable_encryption ? "Encryption enabled for S3 and DynamoDB" : "Encryption disabled - consider enabling for production"
    vpc_security = "Security group restricts access to VPC subnets only"
    iam_roles = "IAM roles follow least privilege principle"
    spot_instances = "Spot instances may be terminated with 2-minute notice"
    monitoring = var.enable_monitoring ? "CloudWatch monitoring enabled" : "CloudWatch monitoring disabled"
    alerts = var.enable_alerts ? "CloudWatch alerts enabled" : "CloudWatch alerts disabled"
  }
}

# Next steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = {
    step_1 = "Test the infrastructure with a simple workflow"
    step_2 = "Configure appropriate instance types for your workload"
    step_3 = "Set up VPC endpoints for better security and performance"
    step_4 = "Configure auto-scaling policies for the Batch compute environment"
    step_5 = "Implement custom metrics for workflow-specific monitoring"
    step_6 = "Set up backup strategies for critical workflow data"
    step_7 = "Configure cost budgets and billing alerts"
    step_8 = "Review and optimize IAM permissions for your specific use case"
  }
}