# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source for current AWS account ID
data "aws_caller_identity" "current" {}

# Data source for current AWS region
data "aws_region" "current" {}

# Data source for current AWS partition
data "aws_partition" "current" {}

# DynamoDB table for document storage
resource "aws_dynamodb_table" "documents" {
  name           = "${var.documents_table_name}-${random_id.suffix.hex}"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "documentId"

  attribute {
    name = "documentId"
    type = "S"
  }

  tags = {
    Name = "${var.documents_table_name}-${random_id.suffix.hex}"
  }
}

# Cognito User Pool for identity management
resource "aws_cognito_user_pool" "main" {
  name = "${var.user_pool_name}-${random_id.suffix.hex}"

  # Password policy configuration
  password_policy {
    minimum_length    = var.cognito_password_policy.minimum_length
    require_lowercase = var.cognito_password_policy.require_lowercase
    require_numbers   = var.cognito_password_policy.require_numbers
    require_symbols   = var.cognito_password_policy.require_symbols
    require_uppercase = var.cognito_password_policy.require_uppercase
  }

  # Custom attributes for ABAC
  schema {
    attribute_data_type = "String"
    name               = "email"
    required           = true
    mutable            = true
  }

  schema {
    attribute_data_type      = "String"
    name                    = "department"
    developer_only_attribute = false
    mutable                 = true
  }

  schema {
    attribute_data_type      = "String"
    name                    = "role"
    developer_only_attribute = false
    mutable                 = true
  }

  # Auto-verified attributes
  auto_verified_attributes = ["email"]

  tags = {
    Name = "${var.user_pool_name}-${random_id.suffix.hex}"
  }
}

# Cognito User Pool Client
resource "aws_cognito_user_pool_client" "main" {
  name         = "DocManagement-Client"
  user_pool_id = aws_cognito_user_pool.main.id

  # Auth flows
  explicit_auth_flows = [
    "ADMIN_NO_SRP_AUTH",
    "USER_PASSWORD_AUTH"
  ]

  generate_secret = true
}

# Verified Permissions Policy Store
resource "aws_verifiedpermissions_policy_store" "main" {
  description = "Document Management Authorization Policies"
  
  validation_settings {
    mode = "STRICT"
  }
}

# Identity source linking Cognito to Verified Permissions
resource "aws_verifiedpermissions_identity_source" "cognito" {
  policy_store_id = aws_verifiedpermissions_policy_store.main.policy_store_id
  
  configuration {
    cognito_user_pool_configuration {
      user_pool_arn = aws_cognito_user_pool.main.arn
      client_ids    = [aws_cognito_user_pool_client.main.id]
    }
  }
  
  principal_entity_type = "User"
}

# Cedar Policy for document viewing
resource "aws_verifiedpermissions_policy" "view_policy" {
  policy_store_id = aws_verifiedpermissions_policy_store.main.policy_store_id
  
  definition {
    static {
      description = var.cedar_policies.view_policy.description
      statement   = var.cedar_policies.view_policy.statement
    }
  }
}

# Cedar Policy for document editing
resource "aws_verifiedpermissions_policy" "edit_policy" {
  policy_store_id = aws_verifiedpermissions_policy_store.main.policy_store_id
  
  definition {
    static {
      description = var.cedar_policies.edit_policy.description
      statement   = var.cedar_policies.edit_policy.statement
    }
  }
}

# Cedar Policy for document deletion
resource "aws_verifiedpermissions_policy" "delete_policy" {
  policy_store_id = aws_verifiedpermissions_policy_store.main.policy_store_id
  
  definition {
    static {
      description = var.cedar_policies.delete_policy.description
      statement   = var.cedar_policies.delete_policy.statement
    }
  }
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "VerifiedPermissions-Lambda-Role-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM policy for Verified Permissions access
resource "aws_iam_role_policy" "verified_permissions_policy" {
  name = "VerifiedPermissionsAccess"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "verifiedpermissions:IsAuthorizedWithToken"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:verifiedpermissions::${data.aws_caller_identity.current.account_id}:policy-store/${aws_verifiedpermissions_policy_store.main.policy_store_id}"
      }
    ]
  })
}

# IAM policy for DynamoDB access
resource "aws_iam_role_policy" "dynamodb_policy" {
  name = "DynamoDBAccess"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.documents.arn
      }
    ]
  })
}

# Lambda authorizer function code
data "archive_file" "authorizer_lambda" {
  type        = "zip"
  output_path = "authorizer-function.zip"
  
  source {
    content = templatefile("${path.module}/lambda/authorizer.py", {
      policy_store_id = aws_verifiedpermissions_policy_store.main.policy_store_id
      user_pool_id    = aws_cognito_user_pool.main.id
      aws_region      = data.aws_region.current.name
    })
    filename = "index.py"
  }
  
  source {
    content  = "PyJWT==2.8.0\ncryptography==41.0.7"
    filename = "requirements.txt"
  }
}

# Lambda authorizer function
resource "aws_lambda_function" "authorizer" {
  filename         = data.archive_file.authorizer_lambda.output_path
  function_name    = "${var.lambda_authorizer_name}-${random_id.suffix.hex}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      POLICY_STORE_ID      = aws_verifiedpermissions_policy_store.main.policy_store_id
      USER_POOL_ID         = aws_cognito_user_pool.main.id
      USER_POOL_CLIENT_ID  = aws_cognito_user_pool_client.main.id
      AWS_REGION           = data.aws_region.current.name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.verified_permissions_policy,
    aws_cloudwatch_log_group.authorizer_logs
  ]
}

# CloudWatch log group for authorizer function
resource "aws_cloudwatch_log_group" "authorizer_logs" {
  name              = "/aws/lambda/${var.lambda_authorizer_name}-${random_id.suffix.hex}"
  retention_in_days = 14
}

# Lambda business logic function code
data "archive_file" "business_lambda" {
  type        = "zip"
  output_path = "business-function.zip"
  
  source {
    content = templatefile("${path.module}/lambda/business.py", {
      documents_table = aws_dynamodb_table.documents.name
    })
    filename = "index.py"
  }
}

# Lambda business logic function
resource "aws_lambda_function" "business" {
  filename         = data.archive_file.business_lambda.output_path
  function_name    = "${var.lambda_business_name}-${random_id.suffix.hex}"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size

  environment {
    variables = {
      DOCUMENTS_TABLE = aws_dynamodb_table.documents.name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.dynamodb_policy,
    aws_cloudwatch_log_group.business_logs
  ]
}

# CloudWatch log group for business function
resource "aws_cloudwatch_log_group" "business_logs" {
  name              = "/aws/lambda/${var.lambda_business_name}-${random_id.suffix.hex}"
  retention_in_days = 14
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.api_name}-${random_id.suffix.hex}"
  description = "Document Management API with Verified Permissions"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# API Gateway custom authorizer
resource "aws_api_gateway_authorizer" "verified_permissions" {
  name                   = "VerifiedPermissionsAuthorizer"
  rest_api_id           = aws_api_gateway_rest_api.main.id
  authorizer_uri        = aws_lambda_function.authorizer.invoke_arn
  authorizer_credentials = aws_iam_role.lambda_role.arn
  type                  = "TOKEN"
  identity_source       = "method.request.header.Authorization"
  authorizer_result_ttl_in_seconds = var.authorizer_result_ttl
}

# API Gateway Lambda permission for authorizer
resource "aws_lambda_permission" "authorizer_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/authorizers/${aws_api_gateway_authorizer.verified_permissions.id}"
}

# API Gateway Lambda permission for business logic
resource "aws_lambda_permission" "business_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.business.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# API Gateway resources
resource "aws_api_gateway_resource" "documents" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "documents"
}

resource "aws_api_gateway_resource" "document_id" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.documents.id
  path_part   = "{documentId}"
}

# API Gateway methods and integrations
resource "aws_api_gateway_method" "documents_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.documents.id
  http_method   = "POST"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.verified_permissions.id
}

resource "aws_api_gateway_integration" "documents_post" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.documents.id
  http_method = aws_api_gateway_method.documents_post.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.business.invoke_arn
}

resource "aws_api_gateway_method" "document_get" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.document_id.id
  http_method   = "GET"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.verified_permissions.id
}

resource "aws_api_gateway_integration" "document_get" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.document_id.id
  http_method = aws_api_gateway_method.document_get.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.business.invoke_arn
}

resource "aws_api_gateway_method" "document_put" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.document_id.id
  http_method   = "PUT"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.verified_permissions.id
}

resource "aws_api_gateway_integration" "document_put" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.document_id.id
  http_method = aws_api_gateway_method.document_put.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.business.invoke_arn
}

resource "aws_api_gateway_method" "document_delete" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.document_id.id
  http_method   = "DELETE"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.verified_permissions.id
}

resource "aws_api_gateway_integration" "document_delete" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.document_id.id
  http_method = aws_api_gateway_method.document_delete.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.business.invoke_arn
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "main" {
  depends_on = [
    aws_api_gateway_integration.documents_post,
    aws_api_gateway_integration.document_get,
    aws_api_gateway_integration.document_put,
    aws_api_gateway_integration.document_delete
  ]

  rest_api_id = aws_api_gateway_rest_api.main.id
  stage_name  = var.api_stage_name

  stage_description = "Production deployment with Verified Permissions"
}

# CloudWatch log group for API Gateway (conditional)
resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  count             = var.enable_api_gateway_logging ? 1 : 0
  name              = "/aws/apigateway/${aws_api_gateway_rest_api.main.name}"
  retention_in_days = 14
}

# Test users (conditional)
resource "aws_cognito_user" "admin" {
  count          = var.create_test_users ? 1 : 0
  user_pool_id   = aws_cognito_user_pool.main.id
  username       = "admin@company.com"
  message_action = "SUPPRESS"
  password       = var.test_user_passwords.admin_password

  attributes = {
    email               = "admin@company.com"
    "custom:department" = "IT"
    "custom:role"       = "Admin"
  }
}

resource "aws_cognito_user" "manager" {
  count          = var.create_test_users ? 1 : 0
  user_pool_id   = aws_cognito_user_pool.main.id
  username       = "manager@company.com"
  message_action = "SUPPRESS"
  password       = var.test_user_passwords.manager_password

  attributes = {
    email               = "manager@company.com"
    "custom:department" = "Sales"
    "custom:role"       = "Manager"
  }
}

resource "aws_cognito_user" "employee" {
  count          = var.create_test_users ? 1 : 0
  user_pool_id   = aws_cognito_user_pool.main.id
  username       = "employee@company.com"
  message_action = "SUPPRESS"
  password       = var.test_user_passwords.employee_password

  attributes = {
    email               = "employee@company.com"
    "custom:department" = "Sales"
    "custom:role"       = "Employee"
  }
}