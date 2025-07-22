# Output values for Amazon Connect contact center infrastructure
# These outputs provide essential information for accessing and managing the deployed contact center

output "connect_instance_id" {
  description = "The unique identifier of the Amazon Connect instance"
  value       = aws_connect_instance.contact_center.id
}

output "connect_instance_arn" {
  description = "The ARN of the Amazon Connect instance"
  value       = aws_connect_instance.contact_center.arn
}

output "connect_instance_alias" {
  description = "The alias of the Amazon Connect instance"
  value       = aws_connect_instance.contact_center.instance_alias
}

output "connect_instance_url" {
  description = "The URL to access the Amazon Connect instance console"
  value       = "https://${aws_connect_instance.contact_center.instance_alias}.my.connect.aws/connect/home"
}

output "admin_user_id" {
  description = "The unique identifier of the administrative user"
  value       = aws_connect_user.admin.user_id
}

output "admin_username" {
  description = "The username for the administrative user"
  value       = aws_connect_user.admin.name
  sensitive   = false
}

output "agent_user_id" {
  description = "The unique identifier of the agent user"
  value       = aws_connect_user.agent.user_id
}

output "agent_username" {
  description = "The username for the agent user"
  value       = aws_connect_user.agent.name
  sensitive   = false
}

output "customer_service_queue_id" {
  description = "The unique identifier of the customer service queue"
  value       = aws_connect_queue.customer_service.queue_id
}

output "customer_service_queue_arn" {
  description = "The ARN of the customer service queue"
  value       = aws_connect_queue.customer_service.arn
}

output "routing_profile_id" {
  description = "The unique identifier of the customer service routing profile"
  value       = aws_connect_routing_profile.customer_service_agents.routing_profile_id
}

output "contact_flow_id" {
  description = "The unique identifier of the customer service contact flow"
  value       = aws_connect_contact_flow.customer_service_flow.contact_flow_id
}

output "contact_flow_arn" {
  description = "The ARN of the customer service contact flow"
  value       = aws_connect_contact_flow.customer_service_flow.arn
}

output "s3_bucket_name" {
  description = "The name of the S3 bucket used for call recordings and chat transcripts"
  value       = aws_s3_bucket.connect_recordings.bucket
}

output "s3_bucket_arn" {
  description = "The ARN of the S3 bucket used for call recordings and chat transcripts"
  value       = aws_s3_bucket.connect_recordings.arn
}

output "s3_bucket_region" {
  description = "The AWS region where the S3 bucket is located"
  value       = aws_s3_bucket.connect_recordings.region
}

output "cloudwatch_dashboard_url" {
  description = "The URL to access the CloudWatch dashboard for contact center metrics"
  value       = var.cloudwatch_dashboard_config.enabled ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.connect_dashboard[0].dashboard_name}" : "CloudWatch dashboard not enabled"
}

output "cloudwatch_log_group_name" {
  description = "The name of the CloudWatch log group for Connect instance logs"
  value       = aws_cloudwatch_log_group.connect_logs.name
}

output "connect_service_role_arn" {
  description = "The ARN of the IAM role used by Amazon Connect service"
  value       = aws_iam_role.connect_service_role.arn
}

# Security and compliance outputs
output "call_recordings_s3_path" {
  description = "The S3 path where call recordings are stored"
  value       = "s3://${aws_s3_bucket.connect_recordings.bucket}/call-recordings/"
}

output "chat_transcripts_s3_path" {
  description = "The S3 path where chat transcripts are stored"
  value       = "s3://${aws_s3_bucket.connect_recordings.bucket}/chat-transcripts/"
}

# Operational information
output "instance_identity_management_type" {
  description = "The identity management type configured for the Connect instance"
  value       = aws_connect_instance.contact_center.identity_management_type
}

output "inbound_calls_enabled" {
  description = "Whether inbound calls are enabled for the Connect instance"
  value       = aws_connect_instance.contact_center.inbound_calls_enabled
}

output "outbound_calls_enabled" {
  description = "Whether outbound calls are enabled for the Connect instance"
  value       = aws_connect_instance.contact_center.outbound_calls_enabled
}

output "contact_lens_enabled" {
  description = "Whether Contact Lens (AI analytics) is enabled"
  value       = var.enable_contact_lens
}

output "contact_flow_logs_enabled" {
  description = "Whether contact flow logging is enabled"
  value       = var.enable_contact_flow_logs
}

# Access and management information
output "management_console_instructions" {
  description = "Instructions for accessing the Amazon Connect management console"
  value = <<EOT
To access your Amazon Connect contact center:

1. Navigate to: https://${aws_connect_instance.contact_center.instance_alias}.my.connect.aws/connect/home
2. Use the admin credentials:
   - Username: ${aws_connect_user.admin.name}
   - Password: [Use the password specified in variables]

3. To access the agent workspace:
   - Navigate to: https://${aws_connect_instance.contact_center.instance_alias}.my.connect.aws/connect/ccp-v2/
   - Use the agent credentials:
     - Username: ${aws_connect_user.agent.name}
     - Password: [Use the password specified in variables]

4. View metrics and analytics:
   - CloudWatch Dashboard: ${var.cloudwatch_dashboard_config.enabled ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${try(aws_cloudwatch_dashboard.connect_dashboard[0].dashboard_name, "")}" : "Not enabled"}
   - Call recordings: s3://${aws_s3_bucket.connect_recordings.bucket}/call-recordings/
EOT
}

# Cost optimization information
output "estimated_monthly_costs" {
  description = "Estimated monthly costs breakdown (approximate)"
  value = <<EOT
Estimated monthly costs (approximate, actual costs may vary):

- Amazon Connect Instance: $0 (base cost)
- Agent usage: ~$150/month per full-time agent (based on ~170 hours/month)
- Phone calls: Variable based on usage (typically $0.0022 per minute)
- S3 storage: ~$0.023 per GB/month for call recordings
- CloudWatch logs: ~$0.50 per GB ingested
- Data transfer: Variable based on usage

Total estimated cost for 1 agent with moderate usage: ~$175-200/month

Note: Actual costs depend on usage patterns, call volume, and storage requirements.
Use AWS Cost Calculator for more precise estimates.
EOT
}

# Next steps and recommendations
output "deployment_next_steps" {
  description = "Recommended next steps after deployment"
  value = <<EOT
Next steps to complete your contact center setup:

1. Claim a phone number:
   - Go to Amazon Connect console → Telephony → Phone numbers
   - Claim a toll-free or DID number for customer calls
   - Associate the number with your contact flow

2. Configure additional contact flows:
   - Create IVR menus for call routing
   - Set up after-hours messaging
   - Configure voicemail and callback options

3. Set up additional users and permissions:
   - Create more agent accounts as needed
   - Configure supervisor accounts for monitoring
   - Set up appropriate security profiles

4. Enable advanced features:
   - Configure real-time and historical reporting
   - Set up Contact Lens rules for quality monitoring
   - Integrate with external CRM systems

5. Test the complete customer journey:
   - Test inbound call flow from customer perspective
   - Verify call recording and storage
   - Validate agent experience and tools

6. Implement monitoring and alerting:
   - Set up CloudWatch alarms for key metrics
   - Configure notifications for queue thresholds
   - Monitor cost and usage patterns
EOT
}