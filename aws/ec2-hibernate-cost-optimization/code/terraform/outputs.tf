# EC2 Instance Outputs
output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.hibernation_demo.id
}

output "instance_arn" {
  description = "ARN of the EC2 instance"
  value       = aws_instance.hibernation_demo.arn
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.hibernation_demo.public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.hibernation_demo.private_ip
}

output "instance_public_dns" {
  description = "Public DNS name of the EC2 instance"
  value       = aws_instance.hibernation_demo.public_dns
}

output "instance_state" {
  description = "Current state of the EC2 instance"
  value       = aws_instance.hibernation_demo.instance_state
}

output "hibernation_enabled" {
  description = "Whether hibernation is enabled for the instance"
  value       = aws_instance.hibernation_demo.hibernation
}

# Key Pair Outputs
output "key_pair_name" {
  description = "Name of the EC2 key pair"
  value       = aws_key_pair.ec2_key_pair.key_name
}

output "key_pair_fingerprint" {
  description = "Fingerprint of the EC2 key pair"
  value       = aws_key_pair.ec2_key_pair.fingerprint
}

output "private_key_ssm_parameter" {
  description = "SSM parameter name containing the private key"
  value       = aws_ssm_parameter.ec2_private_key.name
  sensitive   = true
}

# Security Group Outputs
output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.ec2_sg.id
}

output "security_group_arn" {
  description = "ARN of the security group"
  value       = aws_security_group.ec2_sg.arn
}

# IAM Outputs
output "iam_role_name" {
  description = "Name of the IAM role for the EC2 instance"
  value       = aws_iam_role.ec2_hibernation_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role for the EC2 instance"
  value       = aws_iam_role.ec2_hibernation_role.arn
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = aws_iam_instance_profile.ec2_hibernation_profile.name
}

output "iam_instance_profile_arn" {
  description = "ARN of the IAM instance profile"
  value       = aws_iam_instance_profile.ec2_hibernation_profile.arn
}

# SNS Outputs
output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.hibernation_notifications.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic"
  value       = aws_sns_topic.hibernation_notifications.arn
}

# CloudWatch Outputs
output "cloudwatch_alarm_low_cpu_name" {
  description = "Name of the CloudWatch alarm for low CPU utilization"
  value       = aws_cloudwatch_metric_alarm.low_cpu_utilization.alarm_name
}

output "cloudwatch_alarm_low_cpu_arn" {
  description = "ARN of the CloudWatch alarm for low CPU utilization"
  value       = aws_cloudwatch_metric_alarm.low_cpu_utilization.arn
}

output "cloudwatch_alarm_state_change_name" {
  description = "Name of the CloudWatch alarm for instance state changes"
  value       = aws_cloudwatch_metric_alarm.instance_state_change.alarm_name
}

output "cloudwatch_alarm_state_change_arn" {
  description = "ARN of the CloudWatch alarm for instance state changes"
  value       = aws_cloudwatch_metric_alarm.instance_state_change.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.hibernation_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.hibernation_logs.arn
}

# Lambda Outputs (conditional)
output "lambda_function_name" {
  description = "Name of the Lambda function for hibernation scheduling"
  value       = var.environment == "dev" ? aws_lambda_function.hibernation_scheduler[0].function_name : null
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function for hibernation scheduling"
  value       = var.environment == "dev" ? aws_lambda_function.hibernation_scheduler[0].arn : null
}

# Network Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = local.vpc_id
}

output "subnet_id" {
  description = "ID of the subnet"
  value       = local.subnet_id
}

# AMI Outputs
output "ami_id" {
  description = "ID of the AMI used for the instance"
  value       = data.aws_ami.amazon_linux.id
}

output "ami_name" {
  description = "Name of the AMI used for the instance"
  value       = data.aws_ami.amazon_linux.name
}

# Resource Naming Outputs
output "name_prefix" {
  description = "Prefix used for resource naming"
  value       = var.name_prefix
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.name_suffix
}

# SSH Connection Information
output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ${local.key_pair_name}.pem ec2-user@${aws_instance.hibernation_demo.public_ip}"
}

output "ssh_command_with_ssm" {
  description = "Command to retrieve private key from SSM and connect via SSH"
  value       = "aws ssm get-parameter --name '${aws_ssm_parameter.ec2_private_key.name}' --with-decryption --query 'Parameter.Value' --output text > ${local.key_pair_name}.pem && chmod 400 ${local.key_pair_name}.pem && ssh -i ${local.key_pair_name}.pem ec2-user@${aws_instance.hibernation_demo.public_ip}"
}

# Cost Optimization Information
output "cost_optimization_info" {
  description = "Cost optimization information and hibernation commands"
  value = {
    hibernate_command = "aws ec2 stop-instances --instance-ids ${aws_instance.hibernation_demo.id} --hibernate"
    resume_command    = "aws ec2 start-instances --instance-ids ${aws_instance.hibernation_demo.id}"
    monitor_command   = "aws ec2 describe-instances --instance-ids ${aws_instance.hibernation_demo.id} --query 'Reservations[0].Instances[0].State.Name'"
    estimated_hourly_cost = "Instance type ${var.instance_type} - Check AWS pricing for current costs"
    hibernation_storage_cost = "EBS storage cost: ${var.ebs_volume_size}GB × $0.10/GB/month (gp3 pricing)"
  }
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the hibernation setup"
  value = {
    check_hibernation_support = "aws ec2 describe-instances --instance-ids ${aws_instance.hibernation_demo.id} --query 'Reservations[0].Instances[0].HibernationOptions.Configured'"
    check_instance_state     = "aws ec2 describe-instances --instance-ids ${aws_instance.hibernation_demo.id} --query 'Reservations[0].Instances[0].State.Name'"
    check_cloudwatch_metrics = "aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization --dimensions Name=InstanceId,Value=${aws_instance.hibernation_demo.id} --start-time $(date -u -d '1 hour ago' +%%Y-%%m-%%dT%%H:%%M:%%S) --end-time $(date -u +%%Y-%%m-%%dT%%H:%%M:%%S) --period 300 --statistics Average"
    check_alarm_state        = "aws cloudwatch describe-alarms --alarm-names '${aws_cloudwatch_metric_alarm.low_cpu_utilization.alarm_name}' --query 'MetricAlarms[0].StateValue'"
  }
}

# Cleanup Commands
output "cleanup_commands" {
  description = "Commands to clean up resources"
  value = {
    terraform_destroy = "terraform destroy -auto-approve"
    manual_cleanup = [
      "aws ec2 terminate-instances --instance-ids ${aws_instance.hibernation_demo.id}",
      "aws sns delete-topic --topic-arn ${aws_sns_topic.hibernation_notifications.arn}",
      "aws cloudwatch delete-alarms --alarm-names '${aws_cloudwatch_metric_alarm.low_cpu_utilization.alarm_name}' '${aws_cloudwatch_metric_alarm.instance_state_change.alarm_name}'",
      "aws ec2 delete-key-pair --key-name ${aws_key_pair.ec2_key_pair.key_name}",
      "aws ssm delete-parameter --name '${aws_ssm_parameter.ec2_private_key.name}'"
    ]
  }
}