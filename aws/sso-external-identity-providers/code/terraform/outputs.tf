# Outputs for AWS Single Sign-On with External Identity Providers
# This file defines the outputs that will be displayed after deployment

# ==============================================================================
# IAM Identity Center Instance Information
# ==============================================================================

output "sso_instance_arn" {
  description = "ARN of the AWS IAM Identity Center instance"
  value       = local.sso_instance_arn
}

output "identity_store_id" {
  description = "ID of the AWS Identity Store"
  value       = local.identity_store_id
}

output "aws_access_portal_url" {
  description = "URL of the AWS Access Portal for user sign-in"
  value       = length(data.aws_ssoadmin_instances.current.arns) > 0 ? "https://${split("/", data.aws_ssoadmin_instances.current.arns[0])[1]}.awsapps.com/start" : "N/A - IAM Identity Center not enabled"
}

# ==============================================================================
# Permission Sets
# ==============================================================================

output "permission_sets" {
  description = "Information about created permission sets"
  value = {
    for ps_key, ps in aws_ssoadmin_permission_set.this : ps_key => {
      name         = ps.name
      arn          = ps.arn
      description  = ps.description
      session_duration = ps.session_duration
    }
  }
}

output "permission_set_arns" {
  description = "ARNs of all created permission sets"
  value = {
    for ps_key, ps in aws_ssoadmin_permission_set.this : ps_key => ps.arn
  }
}

# ==============================================================================
# External Identity Provider Information
# ==============================================================================

output "external_identity_provider" {
  description = "Information about the external identity provider (if configured)"
  value = var.enable_external_idp && length(aws_ssoadmin_external_identity_provider.this) > 0 ? {
    provider_id = aws_ssoadmin_external_identity_provider.this[0].id
    provider_arn = aws_ssoadmin_external_identity_provider.this[0].external_identity_provider_arn
    issuer_url = aws_ssoadmin_external_identity_provider.this[0].saml[0].issuer_url
  } : null
}

output "scim_endpoint" {
  description = "SCIM endpoint URL for user and group provisioning"
  value = local.sso_instance_arn != null ? replace(
    replace(local.sso_instance_arn, "arn:aws:sso::", "https://scim."),
    ":sso-instance/", ".amazonaws.com/"
  ) : "N/A - IAM Identity Center not enabled"
}

# ==============================================================================
# Test Users and Groups (Local Identity Store)
# ==============================================================================

output "test_users" {
  description = "Information about created test users"
  value = {
    for user_key, user in aws_identitystore_user.test_users : user_key => {
      user_id      = user.user_id
      user_name    = user.user_name
      display_name = user.display_name
      email        = user.emails[0].value
    }
  }
  sensitive = false
}

output "test_groups" {
  description = "Information about created test groups"
  value = {
    for group_key, group in aws_identitystore_group.test_groups : group_key => {
      group_id     = group.group_id
      display_name = group.display_name
      description  = group.description
    }
  }
}

output "group_memberships" {
  description = "Information about group memberships"
  value = {
    for membership_key, membership in aws_identitystore_group_membership.test_group_memberships : membership_key => {
      membership_id = membership.membership_id
      group_id     = membership.group_id
      member_id    = membership.member_id
    }
  }
}

# ==============================================================================
# Account Assignments
# ==============================================================================

output "account_assignments" {
  description = "Information about account assignments"
  value = {
    for assignment_key, assignment in aws_ssoadmin_account_assignment.this : assignment_key => {
      permission_set_name = assignment.permission_set_arn
      target_account_id   = assignment.target_id
      principal_type      = assignment.principal_type
      principal_id        = assignment.principal_id
    }
  }
}

# ==============================================================================
# CloudTrail Information
# ==============================================================================

output "cloudtrail_info" {
  description = "Information about CloudTrail configuration for SSO audit logging"
  value = var.enable_cloudtrail_logging && length(aws_cloudtrail.sso_audit) > 0 ? {
    trail_name    = aws_cloudtrail.sso_audit[0].name
    trail_arn     = aws_cloudtrail.sso_audit[0].arn
    s3_bucket     = aws_s3_bucket.cloudtrail[0].bucket
    s3_bucket_arn = aws_s3_bucket.cloudtrail[0].arn
  } : null
}

# ==============================================================================
# Deployment Information
# ==============================================================================

output "deployment_info" {
  description = "General deployment information"
  value = {
    aws_region         = data.aws_region.current.name
    aws_account_id     = data.aws_caller_identity.current.account_id
    random_suffix      = local.suffix
    environment        = var.environment
    organization_name  = var.organization_name
  }
}

# ==============================================================================
# Next Steps and Configuration URLs
# ==============================================================================

output "next_steps" {
  description = "Next steps for completing the SSO configuration"
  value = <<-EOT
    
    AWS Single Sign-On Configuration Complete!
    
    Next Steps:
    1. Access the AWS Access Portal: ${length(data.aws_ssoadmin_instances.current.arns) > 0 ? "https://${split("/", data.aws_ssoadmin_instances.current.arns[0])[1]}.awsapps.com/start" : "Enable IAM Identity Center first"}
    
    2. Configure External Identity Provider (if using):
       - Go to AWS IAM Identity Center Console
       - Navigate to Settings > Identity source
       - Choose "External identity provider"
       - Upload your SAML metadata document
    
    3. Set up SCIM provisioning (if using external IdP):
       - SCIM Endpoint: ${local.sso_instance_arn != null ? replace(replace(local.sso_instance_arn, "arn:aws:sso::", "https://scim."), ":sso-instance/", ".amazonaws.com/") : "N/A"}
       - Generate SCIM access token in the AWS Console
       - Configure your identity provider with the endpoint and token
    
    4. Test user access:
       - Users can access the portal using the URL above
       - Test with the created test users (if using local identity store)
    
    5. Monitor access:
       ${var.enable_cloudtrail_logging ? "- CloudTrail is enabled for audit logging" : "- Consider enabling CloudTrail for audit logging"}
       - Review CloudWatch logs for authentication events
    
    For production use:
    - Replace test users/groups with real identity provider integration
    - Configure appropriate permission sets for your organization
    - Set up proper account assignments based on your organizational structure
    - Enable MFA requirements in your external identity provider
    
  EOT
}

# ==============================================================================
# Security Recommendations
# ==============================================================================

output "security_recommendations" {
  description = "Security recommendations for production deployment"
  value = {
    recommendations = [
      "Enable MFA in your external identity provider",
      "Use short session durations for privileged permission sets",
      "Implement attribute-based access control (ABAC) with user attributes",
      "Regularly review and audit permission set assignments",
      "Enable CloudTrail logging for all SSO events",
      "Use least privilege principle when creating custom permission sets",
      "Implement break-glass access procedures for emergency situations",
      "Regularly rotate SCIM access tokens",
      "Monitor failed authentication attempts and unusual access patterns",
      "Document your permission set usage and assignment policies"
    ]
    
    compliance_notes = [
      "This configuration supports SOC 2, ISO 27001, and other compliance frameworks",
      "CloudTrail logs provide audit trails required for compliance",
      "Permission sets enable role-based access control (RBAC)",
      "SAML integration provides secure authentication without password sharing"
    ]
  }
}