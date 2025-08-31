# Output Values for Simple Resource Monitoring Infrastructure
# These outputs provide important information about the created resources

# General Information
output "aws_region" {
  description = "AWS region where resources were created"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources were created"
  value       = data.aws_caller_identity.current.account_id
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# EC2 Instance Information
output "instance_id" {
  description = "ID of the EC2 instance created for monitoring"
  value       = aws_instance.monitoring_demo.id
}

output "instance_arn" {
  description = "ARN of the EC2 instance"
  value       = aws_instance.monitoring_demo.arn
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance (if available)"
  value       = aws_instance.monitoring_demo.public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.monitoring_demo.private_ip
}

output "instance_public_dns" {
  description = "Public DNS name of the EC2 instance (if available)"
  value       = aws_instance.monitoring_demo.public_dns
}

output "instance_private_dns" {
  description = "Private DNS name of the EC2 instance"
  value       = aws_instance.monitoring_demo.private_dns
}

output "instance_type" {
  description = "Instance type of the EC2 instance"
  value       = aws_instance.monitoring_demo.instance_type
}

output "instance_ami_id" {
  description = "AMI ID used for the EC2 instance"
  value       = aws_instance.monitoring_demo.ami
}

output "instance_key_name" {
  description = "Key pair name associated with the instance (if any)"
  value       = aws_instance.monitoring_demo.key_name
}

output "instance_subnet_id" {
  description = "Subnet ID where the instance is launched"
  value       = aws_instance.monitoring_demo.subnet_id
}

output "instance_vpc_id" {
  description = "VPC ID where the instance is launched"
  value       = var.create_vpc ? aws_vpc.monitoring_vpc[0].id : data.aws_vpc.default[0].id
}

# Security Group Information
output "security_group_id" {
  description = "ID of the security group attached to the instance"
  value       = aws_security_group.monitoring_sg.id
}

output "security_group_arn" {
  description = "ARN of the security group"
  value       = aws_security_group.monitoring_sg.arn
}

# SNS Topic Information
output "sns_topic_arn" {
  description = "ARN of the SNS topic for alarm notifications"
  value       = aws_sns_topic.cpu_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.cpu_alerts.name
}

output "sns_subscription_arn" {
  description = "ARN of the email subscription (will be 'PendingConfirmation' until confirmed)"
  value       = aws_sns_topic_subscription.email_notification.arn
}

output "sns_subscription_status" {
  description = "Status of the email subscription"
  value       = aws_sns_topic_subscription.email_notification.pending_confirmation ? "PendingConfirmation" : "Confirmed"
}

output "notification_email" {
  description = "Email address configured for notifications"
  value       = var.email_address
  sensitive   = true
}

# CloudWatch Alarm Information
output "cpu_alarm_name" {
  description = "Name of the CPU utilization alarm"
  value       = aws_cloudwatch_metric_alarm.high_cpu.alarm_name
}

output "cpu_alarm_arn" {
  description = "ARN of the CPU utilization alarm"
  value       = aws_cloudwatch_metric_alarm.high_cpu.arn
}

output "cpu_alarm_threshold" {
  description = "CPU threshold that triggers the alarm"
  value       = "${aws_cloudwatch_metric_alarm.high_cpu.threshold}%"
}

output "instance_status_alarm_name" {
  description = "Name of the instance status check alarm"
  value       = aws_cloudwatch_metric_alarm.instance_status_check.alarm_name
}

output "instance_status_alarm_arn" {
  description = "ARN of the instance status check alarm"
  value       = aws_cloudwatch_metric_alarm.instance_status_check.arn
}

output "system_status_alarm_name" {
  description = "Name of the system status check alarm"
  value       = aws_cloudwatch_metric_alarm.system_status_check.alarm_name
}

output "system_status_alarm_arn" {
  description = "ARN of the system status check alarm"
  value       = aws_cloudwatch_metric_alarm.system_status_check.arn
}

# CloudWatch Logs Information
output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.monitoring_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.monitoring_logs.arn
}

# IAM Information
output "iam_role_name" {
  description = "Name of the IAM role attached to the instance"
  value       = aws_iam_role.ec2_monitoring_role.name
}

output "iam_role_arn" {
  description = "ARN of the IAM role"
  value       = aws_iam_role.ec2_monitoring_role.arn
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = aws_iam_instance_profile.ec2_monitoring_profile.name
}

output "iam_instance_profile_arn" {
  description = "ARN of the IAM instance profile"
  value       = aws_iam_instance_profile.ec2_monitoring_profile.arn
}

# KMS Information (if encryption is enabled)
output "kms_key_id" {
  description = "ID of the KMS key used for SNS encryption (if enabled)"
  value       = var.enable_sns_encryption ? aws_kms_key.sns_key[0].key_id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for SNS encryption (if enabled)"
  value       = var.enable_sns_encryption ? aws_kms_key.sns_key[0].arn : null
}

# Key Pair Information (if created)
output "key_pair_name" {
  description = "Name of the created key pair (if created)"
  value       = var.create_key_pair ? aws_key_pair.monitoring_key[0].key_name : null
}

output "key_pair_fingerprint" {
  description = "MD5 fingerprint of the key pair (if created)"
  value       = var.create_key_pair ? aws_key_pair.monitoring_key[0].fingerprint : null
}

# VPC Information (if created)
output "vpc_id" {
  description = "ID of the VPC (created or default)"
  value       = var.create_vpc ? aws_vpc.monitoring_vpc[0].id : data.aws_vpc.default[0].id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = var.create_vpc ? aws_vpc.monitoring_vpc[0].cidr_block : data.aws_vpc.default[0].cidr_block
}

output "subnet_id" {
  description = "ID of the subnet where the instance is deployed"
  value       = var.create_vpc ? aws_subnet.monitoring_subnet[0].id : data.aws_subnets.default[0].ids[0]
}

output "subnet_cidr" {
  description = "CIDR block of the subnet"
  value       = var.create_vpc ? aws_subnet.monitoring_subnet[0].cidr_block : null
}

# Helpful Commands and Next Steps
output "ssh_command" {
  description = "SSH command to connect to the instance (if key pair was created and instance has public IP)"
  value = var.create_key_pair && aws_instance.monitoring_demo.public_ip != "" ? "ssh -i ~/.ssh/${aws_key_pair.monitoring_key[0].key_name} ec2-user@${aws_instance.monitoring_demo.public_ip}" : "SSH not available - no key pair created or no public IP"
}

output "ssm_session_command" {
  description = "AWS CLI command to start an SSM session with the instance"
  value       = "aws ssm start-session --target ${aws_instance.monitoring_demo.id} --region ${data.aws_region.current.name}"
}

output "cloudwatch_metrics_url" {
  description = "URL to view CloudWatch metrics for the instance"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#metricsV2:graph=~();search=${aws_instance.monitoring_demo.id};namespace=AWS/EC2;dimensions=InstanceId"
}

output "cloudwatch_alarms_url" {
  description = "URL to view CloudWatch alarms"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#alarmsV2:"
}

output "sns_topic_url" {
  description = "URL to view the SNS topic in the AWS console"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/sns/v3/home?region=${data.aws_region.current.name}#/topic/${aws_sns_topic.cpu_alerts.arn}"
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost for the monitoring infrastructure (USD)"
  value = {
    ec2_instance    = "~$8.50 (t2.micro 24/7)"
    cloudwatch_alarms = "$0.30 (3 alarms × $0.10)"
    sns_notifications = "$0.00 (first 1,000 emails free)"
    cloudwatch_logs   = "~$0.50 (depends on log volume)"
    total_estimate    = "~$9.30/month"
    note             = "Costs may vary based on usage, region, and AWS pricing changes"
  }
}

# Instructions
output "next_steps" {
  description = "Next steps to complete the monitoring setup"
  value = {
    step_1 = "Check your email (${var.email_address}) and confirm the SNS subscription"
    step_2 = "Connect to the instance using SSM Session Manager or SSH (if configured)"
    step_3 = "Run './cpu-stress-test.sh' on the instance to generate CPU load and test alarms"
    step_4 = "Run './system-info.sh' to view current system metrics"
    step_5 = "Monitor CloudWatch metrics and alarms in the AWS console"
    step_6 = "Verify email notifications are received when alarms are triggered"
  }
}