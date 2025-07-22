# Output Values for Fine-Grained Access Control Infrastructure
# These outputs provide important information about created resources

# ========================================
# General Infrastructure Outputs
# ========================================

output "aws_region" {
  description = "AWS region where resources were created"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources were created"
  value       = data.aws_caller_identity.current.account_id
}

output "project_name" {
  description = "Project name used as prefix for all resources"
  value       = var.project_name
}

output "resource_prefix" {
  description = "Full resource prefix including random suffix"
  value       = local.resource_prefix
}

# ========================================
# S3 Bucket Outputs
# ========================================

output "test_bucket_name" {
  description = "Name of the S3 bucket created for testing access control policies"
  value       = aws_s3_bucket.test_bucket.id
}

output "test_bucket_arn" {
  description = "ARN of the S3 bucket created for testing"
  value       = aws_s3_bucket.test_bucket.arn
}

output "test_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.test_bucket.bucket_domain_name
}

output "test_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.test_bucket.bucket_regional_domain_name
}

# ========================================
# CloudWatch Log Group Outputs
# ========================================

output "log_group_name" {
  description = "Name of the CloudWatch log group created for testing"
  value       = aws_cloudwatch_log_group.test_log_group.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.test_log_group.arn
}

# ========================================
# IAM Policy Outputs
# ========================================

output "business_hours_policy_arn" {
  description = "ARN of the business hours access control policy"
  value       = aws_iam_policy.business_hours_policy.arn
}

output "ip_restriction_policy_arn" {
  description = "ARN of the IP-based access control policy"
  value       = aws_iam_policy.ip_restriction_policy.arn
}

output "tag_based_policy_arn" {
  description = "ARN of the tag-based access control policy"
  value       = aws_iam_policy.tag_based_policy.arn
}

output "mfa_required_policy_arn" {
  description = "ARN of the MFA-required access control policy"
  value       = aws_iam_policy.mfa_required_policy.arn
}

output "session_policy_arn" {
  description = "ARN of the session-based access control policy"
  value       = aws_iam_policy.session_policy.arn
}

# ========================================
# IAM Policy Names (for CLI Testing)
# ========================================

output "business_hours_policy_name" {
  description = "Name of the business hours policy for CLI testing"
  value       = aws_iam_policy.business_hours_policy.name
}

output "ip_restriction_policy_name" {
  description = "Name of the IP restriction policy for CLI testing"
  value       = aws_iam_policy.ip_restriction_policy.name
}

output "tag_based_policy_name" {
  description = "Name of the tag-based policy for CLI testing"
  value       = aws_iam_policy.tag_based_policy.name
}

output "mfa_required_policy_name" {
  description = "Name of the MFA required policy for CLI testing"
  value       = aws_iam_policy.mfa_required_policy.name
}

output "session_policy_name" {
  description = "Name of the session policy for CLI testing"
  value       = aws_iam_policy.session_policy.name
}

# ========================================
# Test Resources Outputs (Conditional)
# ========================================

output "test_user_name" {
  description = "Name of the test user (if created)"
  value       = var.create_test_resources ? aws_iam_user.test_user[0].name : null
}

output "test_user_arn" {
  description = "ARN of the test user (if created)"
  value       = var.create_test_resources ? aws_iam_user.test_user[0].arn : null
}

output "test_role_name" {
  description = "Name of the test role (if created)"
  value       = var.create_test_resources ? aws_iam_role.test_role[0].name : null
}

output "test_role_arn" {
  description = "ARN of the test role (if created)"
  value       = var.create_test_resources ? aws_iam_role.test_role[0].arn : null
}

# ========================================
# CloudTrail Outputs (Conditional)
# ========================================

output "cloudtrail_name" {
  description = "Name of the CloudTrail (if enabled)"
  value       = var.enable_cloudtrail_logging ? aws_cloudtrail.access_control_trail[0].name : null
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail (if enabled)"
  value       = var.enable_cloudtrail_logging ? aws_cloudtrail.access_control_trail[0].arn : null
}

output "cloudtrail_bucket_name" {
  description = "Name of the CloudTrail S3 bucket (if enabled)"
  value       = var.enable_cloudtrail_logging ? aws_s3_bucket.cloudtrail_bucket[0].id : null
}

# ========================================
# Configuration Details
# ========================================

output "business_hours_utc" {
  description = "Business hours configuration in UTC"
  value = {
    start = local.business_hours_start_utc
    end   = local.business_hours_end_utc
  }
}

output "allowed_ip_ranges" {
  description = "IP ranges allowed for access"
  value       = var.allowed_ip_ranges
}

output "test_department" {
  description = "Department tag used for testing"
  value       = var.test_department
}

output "mfa_max_age_seconds" {
  description = "Maximum MFA age in seconds"
  value       = var.mfa_max_age_seconds
}

output "session_duration_seconds" {
  description = "Maximum session duration in seconds"
  value       = var.session_duration_seconds
}

# ========================================
# Testing Commands
# ========================================

output "policy_simulator_commands" {
  description = "AWS CLI commands for testing policies with Policy Simulator"
  value = {
    test_business_hours = "aws iam simulate-principal-policy --policy-source-arn '${var.create_test_resources ? aws_iam_role.test_role[0].arn : "ROLE_ARN"}' --action-names 's3:GetObject' --resource-arns '${aws_s3_bucket.test_bucket.arn}/test-file.txt' --context-entries ContextKeyName=aws:CurrentTime,ContextKeyValues=\"14:00:00Z\",ContextKeyType=date"
    
    test_ip_access = "aws iam simulate-principal-policy --policy-source-arn '${aws_iam_policy.ip_restriction_policy.arn}' --action-names 'logs:PutLogEvents' --resource-arns '${aws_cloudwatch_log_group.test_log_group.arn}' --context-entries ContextKeyName=aws:SourceIp,ContextKeyValues=\"203.0.113.100\",ContextKeyType=ip"
    
    test_tag_based = "aws iam simulate-principal-policy --policy-source-arn '${aws_iam_policy.tag_based_policy.arn}' --action-names 's3:GetObject' --resource-arns '${aws_s3_bucket.test_bucket.arn}/${var.test_department}/test-file.txt' --context-entries ContextKeyName=aws:PrincipalTag/Department,ContextKeyValues=\"${var.test_department}\",ContextKeyType=string ContextKeyName=s3:ExistingObjectTag/Department,ContextKeyValues=\"${var.test_department}\",ContextKeyType=string"
    
    test_mfa_required = "aws iam simulate-principal-policy --policy-source-arn '${aws_iam_policy.mfa_required_policy.arn}' --action-names 's3:PutObject' --resource-arns '${aws_s3_bucket.test_bucket.arn}/test-file.txt' --context-entries ContextKeyName=aws:MultiFactorAuthPresent,ContextKeyValues=\"false\",ContextKeyType=boolean"
  }
}

output "s3_test_commands" {
  description = "S3 CLI commands for testing access control"
  value = {
    list_bucket = "aws s3 ls s3://${aws_s3_bucket.test_bucket.id}/"
    get_object  = "aws s3 cp s3://${aws_s3_bucket.test_bucket.id}/${var.test_department}/test-file.txt ./downloaded-file.txt"
    put_object  = "echo 'Test content' | aws s3 cp - s3://${aws_s3_bucket.test_bucket.id}/test-upload.txt --sse ${var.s3_encryption_type}"
  }
}

# ========================================
# Summary Information
# ========================================

output "deployment_summary" {
  description = "Summary of deployed resources and their purposes"
  value = {
    resources_created = {
      s3_bucket           = aws_s3_bucket.test_bucket.id
      cloudwatch_log_group = aws_cloudwatch_log_group.test_log_group.name
      iam_policies        = [
        aws_iam_policy.business_hours_policy.name,
        aws_iam_policy.ip_restriction_policy.name,
        aws_iam_policy.tag_based_policy.name,
        aws_iam_policy.mfa_required_policy.name,
        aws_iam_policy.session_policy.name
      ]
      test_user = var.create_test_resources ? aws_iam_user.test_user[0].name : "Not created"
      test_role = var.create_test_resources ? aws_iam_role.test_role[0].name : "Not created"
      cloudtrail = var.enable_cloudtrail_logging ? aws_cloudtrail.access_control_trail[0].name : "Not enabled"
    }
    
    access_control_patterns = [
      "Time-based access (business hours)",
      "IP-based network restrictions",
      "Tag-based attribute control (ABAC)",
      "MFA requirements for sensitive operations",
      "Session duration limits",
      "Resource-based encryption requirements"
    ]
    
    next_steps = [
      "Test policies using AWS IAM Policy Simulator",
      "Validate access controls with test user/role",
      "Review CloudTrail logs for audit trail",
      "Customize IP ranges and business hours as needed",
      "Implement additional condition keys for your use case"
    ]
  }
}