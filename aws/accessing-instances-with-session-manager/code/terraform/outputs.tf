# Output values for Session Manager secure access infrastructure

output "instance_id" {
  description = "ID of the EC2 instance available for Session Manager access"
  value       = aws_instance.session_manager_demo.id
}

output "instance_arn" {
  description = "ARN of the EC2 instance"
  value       = "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/${aws_instance.session_manager_demo.id}"
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.session_manager_demo.private_ip
}

output "instance_role_arn" {
  description = "ARN of the IAM role attached to the instance"
  value       = aws_iam_role.session_manager_instance_role.arn
}

output "instance_profile_name" {
  description = "Name of the instance profile attached to the EC2 instance"
  value       = aws_iam_instance_profile.session_manager_instance_profile.name
}

output "user_policy_arn" {
  description = "ARN of the IAM policy for Session Manager user access"
  value       = aws_iam_policy.session_manager_user_policy.arn
}

output "security_group_id" {
  description = "ID of the security group attached to the instance"
  value       = aws_security_group.session_manager_instance.id
}

output "session_start_command" {
  description = "AWS CLI command to start a Session Manager session"
  value       = "aws ssm start-session --target ${aws_instance.session_manager_demo.id}"
}

output "port_forward_example" {
  description = "Example AWS CLI command for port forwarding through Session Manager"
  value       = "aws ssm start-session --target ${aws_instance.session_manager_demo.id} --document-name AWS-StartPortForwardingSession --parameters 'portNumber=80,localPortNumber=8080'"
}

# Conditional outputs for logging resources
output "s3_logs_bucket_name" {
  description = "Name of the S3 bucket for session logs (if logging enabled)"
  value       = var.enable_logging ? aws_s3_bucket.session_logs[0].id : null
}

output "s3_logs_bucket_arn" {
  description = "ARN of the S3 bucket for session logs (if logging enabled)"
  value       = var.enable_logging ? aws_s3_bucket.session_logs[0].arn : null
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for session logs (if logging enabled)"
  value       = var.enable_logging ? aws_cloudwatch_log_group.session_logs[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for session logs (if logging enabled)"
  value       = var.enable_logging ? aws_cloudwatch_log_group.session_logs[0].arn : null
}

output "kms_key_id" {
  description = "ID of the KMS key used for encryption (if logging enabled)"
  value       = var.enable_logging ? aws_kms_key.session_manager[0].key_id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption (if logging enabled)"
  value       = var.enable_logging ? aws_kms_key.session_manager[0].arn : null
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail for Session Manager API logging (if enabled)"
  value       = var.enable_cloudtrail_logging ? aws_cloudtrail.session_manager[0].arn : null
}

# Verification commands
output "verification_commands" {
  description = "Commands to verify the Session Manager setup"
  value = {
    check_instance_status = "aws ssm describe-instance-information --filters 'Key=InstanceIds,Values=${aws_instance.session_manager_demo.id}' --query 'InstanceInformationList[0].[InstanceId,PingStatus,LastPingDateTime]' --output table"
    list_managed_instances = "aws ssm describe-instance-information --query 'InstanceInformationList[*].[InstanceId,PingStatus,AgentVersion]' --output table"
    check_session_logs = var.enable_logging ? "aws logs describe-log-streams --log-group-name ${aws_cloudwatch_log_group.session_logs[0].name} --order-by LastEventTime --descending --max-items 5" : "Logging not enabled"
    test_session_access = "aws ssm start-session --target ${aws_instance.session_manager_demo.id} --document-name AWS-StartNonInteractiveCommand --parameters command='echo Session Manager is working'"
  }
}

# Resource summary for documentation
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    ec2_instance = {
      id           = aws_instance.session_manager_demo.id
      type         = var.instance_type
      ami_id       = data.aws_ami.amazon_linux.id
      private_ip   = aws_instance.session_manager_demo.private_ip
    }
    iam_resources = {
      instance_role = aws_iam_role.session_manager_instance_role.name
      instance_profile = aws_iam_instance_profile.session_manager_instance_profile.name
      user_policy = aws_iam_policy.session_manager_user_policy.name
    }
    security = {
      security_group = aws_security_group.session_manager_instance.id
      kms_key = var.enable_logging ? aws_kms_key.session_manager[0].key_id : "Logging disabled"
    }
    logging = var.enable_logging ? {
      s3_bucket = aws_s3_bucket.session_logs[0].id
      cloudwatch_log_group = aws_cloudwatch_log_group.session_logs[0].name
      cloudtrail = var.enable_cloudtrail_logging ? aws_cloudtrail.session_manager[0].name : "CloudTrail disabled"
    } : "Logging disabled"
  }
}

# Usage instructions
output "usage_instructions" {
  description = "Instructions for using Session Manager with the created resources"
  value = {
    attach_user_policy = "Attach the IAM policy '${aws_iam_policy.session_manager_user_policy.name}' to users who need Session Manager access"
    start_session = "Use: aws ssm start-session --target ${aws_instance.session_manager_demo.id}"
    port_forwarding = "For port forwarding: aws ssm start-session --target ${aws_instance.session_manager_demo.id} --document-name AWS-StartPortForwardingSession --parameters 'portNumber=<remote_port>,localPortNumber=<local_port>'"
    view_logs = var.enable_logging ? "View session logs in CloudWatch log group: ${aws_cloudwatch_log_group.session_logs[0].name}" : "Logging not enabled - set enable_logging=true to enable session logging"
  }
}