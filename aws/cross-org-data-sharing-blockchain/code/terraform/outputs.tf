# Network Information
output "network_id" {
  description = "ID of the managed blockchain network"
  value       = aws_managedblockchain_network.cross_org_network.id
}

output "network_name" {
  description = "Name of the managed blockchain network"
  value       = aws_managedblockchain_network.cross_org_network.name
}

output "network_arn" {
  description = "ARN of the managed blockchain network"
  value       = aws_managedblockchain_network.cross_org_network.arn
}

# Organization A Information
output "organization_a_member_id" {
  description = "Member ID for Organization A"
  value       = data.aws_managedblockchain_member.org_a.id
}

output "organization_a_node_id" {
  description = "Node ID for Organization A"
  value       = aws_managedblockchain_node.org_a_node.id
}

output "organization_a_node_endpoint" {
  description = "Endpoint for Organization A's peer node"
  value       = aws_managedblockchain_node.org_a_node.node_configuration[0].availability_zone
}

# Storage Information
output "s3_bucket_name" {
  description = "Name of the S3 bucket for shared data storage"
  value       = aws_s3_bucket.cross_org_data.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for shared data storage"
  value       = aws_s3_bucket.cross_org_data.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB audit trail table"
  value       = aws_dynamodb_table.audit_trail.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB audit trail table"
  value       = aws_dynamodb_table.audit_trail.arn
}

# Lambda Function Information
output "lambda_function_name" {
  description = "Name of the data validation Lambda function"
  value       = aws_lambda_function.data_validator.function_name
}

output "lambda_function_arn" {
  description = "ARN of the data validation Lambda function"
  value       = aws_lambda_function.data_validator.arn
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

# EventBridge Information
output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for data sharing events"
  value       = aws_cloudwatch_event_rule.data_sharing_events.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule for data sharing events"
  value       = aws_cloudwatch_event_rule.data_sharing_events.arn
}

# SNS Information
output "sns_topic_name" {
  description = "Name of the SNS topic for notifications"
  value       = aws_sns_topic.notifications.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for notifications"
  value       = aws_sns_topic.notifications.arn
}

# IAM Information
output "cross_org_access_policy_arn" {
  description = "ARN of the cross-organization access policy"
  value       = aws_iam_policy.cross_org_access.arn
}

# Monitoring Information
output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard (if enabled)"
  value = var.enable_cloudwatch_dashboard ? "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.cross_org_monitoring[0].dashboard_name}" : "Dashboard not enabled"
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

# Region and Account Information
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# Resource Naming
output "unique_suffix" {
  description = "Unique suffix used for resource naming"
  value       = local.unique_suffix
}

# Instructions for Organization B Setup
output "organization_b_setup_instructions" {
  description = "Instructions for setting up Organization B"
  value = <<-EOT
    To invite Organization B to join the network:
    
    1. Create a proposal to invite Organization B:
       aws managedblockchain create-proposal \
           --network-id ${aws_managedblockchain_network.cross_org_network.id} \
           --member-id ${data.aws_managedblockchain_member.org_a.id} \
           --actions '{"Invitations":[{"Principal":"ACCOUNT_ID_OF_ORG_B"}]}' \
           --description "Invite Organization B to cross-org network"
    
    2. Vote on the proposal (as Organization A):
       aws managedblockchain vote-on-proposal \
           --network-id ${aws_managedblockchain_network.cross_org_network.id} \
           --proposal-id PROPOSAL_ID \
           --voter-member-id ${data.aws_managedblockchain_member.org_a.id} \
           --vote YES
    
    3. Organization B accepts the invitation:
       aws managedblockchain create-member \
           --invitation-id INVITATION_ID \
           --network-id ${aws_managedblockchain_network.cross_org_network.id} \
           --member-configuration '{"Name":"${local.org_b_name}","Description":"${var.organization_b_description}","MemberFabricConfiguration":{"AdminUsername":"${var.admin_username}","AdminPassword":"${var.admin_password}"}}'
  EOT
}

# Sample CLI Commands
output "sample_cli_commands" {
  description = "Sample CLI commands for interacting with the blockchain network"
  value = <<-EOT
    # List network members
    aws managedblockchain list-members --network-id ${aws_managedblockchain_network.cross_org_network.id}
    
    # Get network details
    aws managedblockchain get-network --network-id ${aws_managedblockchain_network.cross_org_network.id}
    
    # Check Lambda function logs
    aws logs filter-log-events --log-group-name ${aws_cloudwatch_log_group.lambda_logs.name}
    
    # Query audit trail
    aws dynamodb scan --table-name ${aws_dynamodb_table.audit_trail.name} --limit 10
  EOT
}