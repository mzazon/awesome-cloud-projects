output "api_gateway_url" {
  description = "URL of the API Gateway endpoint"
  value       = "${aws_api_gateway_deployment.main.invoke_url}"
}

output "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_client_id" {
  description = "ID of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.main.id
}

output "cognito_user_pool_client_secret" {
  description = "Secret of the Cognito User Pool Client"
  value       = aws_cognito_user_pool_client.main.client_secret
  sensitive   = true
}

output "cognito_user_pool_arn" {
  description = "ARN of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.arn
}

output "verified_permissions_policy_store_id" {
  description = "ID of the Verified Permissions Policy Store"
  value       = aws_verifiedpermissions_policy_store.main.policy_store_id
}

output "verified_permissions_identity_source_id" {
  description = "ID of the Verified Permissions Identity Source"
  value       = aws_verifiedpermissions_identity_source.cognito.identity_source_id
}

output "lambda_authorizer_function_name" {
  description = "Name of the Lambda authorizer function"
  value       = aws_lambda_function.authorizer.function_name
}

output "lambda_authorizer_function_arn" {
  description = "ARN of the Lambda authorizer function"
  value       = aws_lambda_function.authorizer.arn
}

output "lambda_business_function_name" {
  description = "Name of the Lambda business logic function"
  value       = aws_lambda_function.business.function_name
}

output "lambda_business_function_arn" {
  description = "ARN of the Lambda business logic function"
  value       = aws_lambda_function.business.arn
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB documents table"
  value       = aws_dynamodb_table.documents.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB documents table"
  value       = aws_dynamodb_table.documents.arn
}

output "api_gateway_rest_api_id" {
  description = "ID of the API Gateway REST API"
  value       = aws_api_gateway_rest_api.main.id
}

output "api_gateway_authorizer_id" {
  description = "ID of the API Gateway custom authorizer"
  value       = aws_api_gateway_authorizer.verified_permissions.id
}

output "cedar_policy_ids" {
  description = "IDs of the Cedar policies"
  value = {
    view_policy   = aws_verifiedpermissions_policy.view_policy.policy_id
    edit_policy   = aws_verifiedpermissions_policy.edit_policy.policy_id
    delete_policy = aws_verifiedpermissions_policy.delete_policy.policy_id
  }
}

output "test_users" {
  description = "Test user information"
  value = var.create_test_users ? {
    admin = {
      username = "admin@company.com"
      role     = "Admin"
      department = "IT"
    }
    manager = {
      username = "manager@company.com"
      role     = "Manager"
      department = "Sales"
    }
    employee = {
      username = "employee@company.com"
      role     = "Employee"
      department = "Sales"
    }
  } : null
}

output "iam_role_arn" {
  description = "ARN of the IAM role for Lambda functions"
  value       = aws_iam_role.lambda_role.arn
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

output "deployment_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# Testing and validation outputs
output "authentication_example" {
  description = "Example commands for testing authentication"
  value = var.create_test_users ? {
    admin_auth_command = "aws cognito-idp admin-initiate-auth --user-pool-id ${aws_cognito_user_pool.main.id} --client-id ${aws_cognito_user_pool_client.main.id} --auth-flow ADMIN_NO_SRP_AUTH --auth-parameters USERNAME=admin@company.com,PASSWORD=AdminPass123!"
    api_test_command   = "curl -X GET '${aws_api_gateway_deployment.main.invoke_url}/documents/test-doc' -H 'Authorization: Bearer \$ACCESS_TOKEN'"
  } : null
}

output "cedar_policy_statements" {
  description = "Cedar policy statements for reference"
  value = {
    view_policy   = var.cedar_policies.view_policy.statement
    edit_policy   = var.cedar_policies.edit_policy.statement
    delete_policy = var.cedar_policies.delete_policy.statement
  }
}