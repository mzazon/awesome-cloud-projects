# Outputs for Blue-Green Deployment with VPC Lattice and Lambda

# ==============================================================================
# Service Information
# ==============================================================================

output "service_endpoint" {
  description = "DNS endpoint for the VPC Lattice service"
  value       = aws_vpclattice_service.blue_green_service.dns_entry
}

output "service_arn" {
  description = "ARN of the VPC Lattice service"
  value       = aws_vpclattice_service.blue_green_service.arn
}

output "service_id" {
  description = "ID of the VPC Lattice service"
  value       = aws_vpclattice_service.blue_green_service.id
}

output "service_status" {
  description = "Status of the VPC Lattice service"
  value       = aws_vpclattice_service.blue_green_service.status
}

# ==============================================================================
# Service Network Information
# ==============================================================================

output "service_network_arn" {
  description = "ARN of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.ecommerce_network.arn
}

output "service_network_id" {
  description = "ID of the VPC Lattice service network"
  value       = aws_vpclattice_service_network.ecommerce_network.id
}

# ==============================================================================
# Lambda Function Information
# ==============================================================================

output "blue_lambda_function_name" {
  description = "Name of the blue Lambda function"
  value       = aws_lambda_function.blue_function.function_name
}

output "blue_lambda_function_arn" {
  description = "ARN of the blue Lambda function"
  value       = aws_lambda_function.blue_function.arn
}

output "green_lambda_function_name" {
  description = "Name of the green Lambda function"
  value       = aws_lambda_function.green_function.function_name
}

output "green_lambda_function_arn" {
  description = "ARN of the green Lambda function"
  value       = aws_lambda_function.green_function.arn
}

# ==============================================================================
# Target Group Information
# ==============================================================================

output "blue_target_group_arn" {
  description = "ARN of the blue target group"
  value       = aws_vpclattice_target_group.blue_target_group.arn
}

output "blue_target_group_id" {
  description = "ID of the blue target group"
  value       = aws_vpclattice_target_group.blue_target_group.id
}

output "green_target_group_arn" {
  description = "ARN of the green target group"
  value       = aws_vpclattice_target_group.green_target_group.arn
}

output "green_target_group_id" {
  description = "ID of the green target group"
  value       = aws_vpclattice_target_group.green_target_group.id
}

# ==============================================================================
# Listener Information
# ==============================================================================

output "http_listener_arn" {
  description = "ARN of the HTTP listener"
  value       = aws_vpclattice_listener.http_listener.arn
}

output "http_listener_id" {
  description = "ID of the HTTP listener"
  value       = aws_vpclattice_listener.http_listener.id
}

# ==============================================================================
# Traffic Weights
# ==============================================================================

output "current_blue_weight" {
  description = "Current traffic weight for blue environment"
  value       = var.initial_blue_weight
}

output "current_green_weight" {
  description = "Current traffic weight for green environment"
  value       = var.initial_green_weight
}

# ==============================================================================
# CloudWatch Alarms
# ==============================================================================

output "green_error_alarm_arn" {
  description = "ARN of the green environment error rate alarm"
  value       = aws_cloudwatch_metric_alarm.green_error_rate.arn
}

output "green_duration_alarm_arn" {
  description = "ARN of the green environment duration alarm"
  value       = aws_cloudwatch_metric_alarm.green_duration.arn
}

output "blue_error_alarm_arn" {
  description = "ARN of the blue environment error rate alarm"
  value       = aws_cloudwatch_metric_alarm.blue_error_rate.arn
}

# ==============================================================================
# Log Groups
# ==============================================================================

output "blue_log_group_name" {
  description = "Name of the blue Lambda function CloudWatch log group"
  value       = aws_cloudwatch_log_group.blue_lambda_logs.name
}

output "green_log_group_name" {
  description = "Name of the green Lambda function CloudWatch log group"
  value       = aws_cloudwatch_log_group.green_lambda_logs.name
}

# ==============================================================================
# IAM Role
# ==============================================================================

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

# ==============================================================================
# Testing Information
# ==============================================================================

output "test_curl_command" {
  description = "Curl command to test the service endpoint"
  value       = "curl -X GET https://${aws_vpclattice_service.blue_green_service.dns_entry.domain_name}/"
}

output "aws_cli_test_commands" {
  description = "AWS CLI commands for testing and monitoring"
  value = {
    get_service_status = "aws vpc-lattice get-service --service-identifier ${aws_vpclattice_service.blue_green_service.id}"
    list_blue_targets = "aws vpc-lattice list-targets --target-group-identifier ${aws_vpclattice_target_group.blue_target_group.id}"
    list_green_targets = "aws vpc-lattice list-targets --target-group-identifier ${aws_vpclattice_target_group.green_target_group.id}"
    get_listener = "aws vpc-lattice get-listener --service-identifier ${aws_vpclattice_service.blue_green_service.id} --listener-identifier ${aws_vpclattice_listener.http_listener.id}"
  }
}

# ==============================================================================
# Deployment Information
# ==============================================================================

output "deployment_summary" {
  description = "Summary of the deployed blue-green infrastructure"
  value = {
    project_name = var.project_name
    environment = var.environment
    aws_region = var.aws_region
    blue_function = local.blue_function_name
    green_function = local.green_function_name
    service_name = local.lattice_service_name
    initial_traffic_distribution = "${var.initial_blue_weight}% blue, ${var.initial_green_weight}% green"
    service_endpoint = aws_vpclattice_service.blue_green_service.dns_entry.domain_name
  }
}

# ==============================================================================
# Traffic Update Helper
# ==============================================================================

output "traffic_update_example" {
  description = "Example commands to update traffic weights"
  value = {
    shift_to_50_50 = <<-EOT
      aws vpc-lattice update-listener \
        --service-identifier ${aws_vpclattice_service.blue_green_service.id} \
        --listener-identifier ${aws_vpclattice_listener.http_listener.id} \
        --default-action '{
          "forward": {
            "targetGroups": [
              {
                "targetGroupIdentifier": "${aws_vpclattice_target_group.blue_target_group.id}",
                "weight": 50
              },
              {
                "targetGroupIdentifier": "${aws_vpclattice_target_group.green_target_group.id}",
                "weight": 50
              }
            ]
          }
        }'
    EOT
    
    shift_to_all_green = <<-EOT
      aws vpc-lattice update-listener \
        --service-identifier ${aws_vpclattice_service.blue_green_service.id} \
        --listener-identifier ${aws_vpclattice_listener.http_listener.id} \
        --default-action '{
          "forward": {
            "targetGroups": [
              {
                "targetGroupIdentifier": "${aws_vpclattice_target_group.blue_target_group.id}",
                "weight": 0
              },
              {
                "targetGroupIdentifier": "${aws_vpclattice_target_group.green_target_group.id}",
                "weight": 100
              }
            ]
          }
        }'
    EOT
    
    rollback_to_blue = <<-EOT
      aws vpc-lattice update-listener \
        --service-identifier ${aws_vpclattice_service.blue_green_service.id} \
        --listener-identifier ${aws_vpclattice_listener.http_listener.id} \
        --default-action '{
          "forward": {
            "targetGroups": [
              {
                "targetGroupIdentifier": "${aws_vpclattice_target_group.blue_target_group.id}",
                "weight": 100
              },
              {
                "targetGroupIdentifier": "${aws_vpclattice_target_group.green_target_group.id}",
                "weight": 0
              }
            ]
          }
        }'
    EOT
  }
}