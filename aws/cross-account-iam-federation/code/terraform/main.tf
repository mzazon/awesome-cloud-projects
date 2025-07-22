# Advanced Cross-Account IAM Role Federation Infrastructure
# This Terraform configuration implements enterprise-grade cross-account access patterns

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Generate external IDs for enhanced security
resource "random_password" "production_external_id" {
  length  = 32
  special = true
}

resource "random_password" "development_external_id" {
  length  = 32
  special = true
}

# Get current caller identity for the security account
data "aws_caller_identity" "security" {}

# Get current AWS region
data "aws_region" "current" {}

# Create SAML Identity Provider (if ARN not provided)
resource "aws_iam_saml_provider" "corporate_idp" {
  count                  = var.saml_provider_arn == "" ? 1 : 0
  name                   = var.identity_provider_name
  saml_metadata_document = file("${path.module}/saml-metadata.xml")

  tags = {
    Name        = var.identity_provider_name
    Environment = var.environment
    Purpose     = "Cross-Account-Federation"
  }
}

# Local value for SAML provider ARN
locals {
  saml_provider_arn = var.saml_provider_arn != "" ? var.saml_provider_arn : aws_iam_saml_provider.corporate_idp[0].arn
}

#------------------------------------------------------------------------------
# SECURITY ACCOUNT RESOURCES (Master Cross-Account Role)
#------------------------------------------------------------------------------

# IAM role trust policy for master cross-account role
data "aws_iam_policy_document" "master_cross_account_trust_policy" {
  # Allow SAML federation
  statement {
    effect = "Allow"
    
    principals {
      type        = "Federated"
      identifiers = [local.saml_provider_arn]
    }
    
    actions = ["sts:AssumeRoleWithSAML"]
    
    condition {
      test     = "StringEquals"
      variable = "SAML:aud"
      values   = ["https://signin.aws.amazon.com/saml"]
    }
    
    condition {
      test     = "ForAllValues:StringLike"
      variable = "SAML:department"
      values   = var.allowed_departments
    }
  }
  
  # Allow direct role assumption with MFA
  dynamic "statement" {
    for_each = var.enable_mfa_requirement ? [1] : []
    
    content {
      effect = "Allow"
      
      principals {
        type        = "AWS"
        identifiers = ["arn:aws:iam::${var.security_account_id}:root"]
      }
      
      actions = ["sts:AssumeRole"]
      
      condition {
        test     = "Bool"
        variable = "aws:MultiFactorAuthPresent"
        values   = ["true"]
      }
      
      condition {
        test     = "NumericLessThan"
        variable = "aws:MultiFactorAuthAge"
        values   = [var.mfa_max_age_seconds]
      }
    }
  }
}

# IAM policy for master cross-account role permissions
data "aws_iam_policy_document" "master_cross_account_permissions" {
  # Allow cross-account role assumption
  statement {
    effect = "Allow"
    
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
    
    resources = [
      "arn:aws:iam::${var.production_account_id}:role/CrossAccount-*",
      "arn:aws:iam::${var.development_account_id}:role/CrossAccount-*"
    ]
    
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [random_password.production_external_id.result, random_password.development_external_id.result]
    }
    
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
    
    dynamic "condition" {
      for_each = var.enable_session_tagging ? [1] : []
      
      content {
        test     = "ForAllValues:StringEquals"
        variable = "sts:TransitiveTagKeys"
        values   = var.transitive_tag_keys
      }
    }
  }
  
  # Allow basic IAM read permissions
  statement {
    effect = "Allow"
    
    actions = [
      "iam:ListRoles",
      "iam:GetRole",
      "sts:GetCallerIdentity"
    ]
    
    resources = ["*"]
  }
}

# Master cross-account role in security account
resource "aws_iam_role" "master_cross_account" {
  name                 = "MasterCrossAccountRole-${random_id.suffix.hex}"
  description          = "Master role for federated cross-account access"
  assume_role_policy   = data.aws_iam_policy_document.master_cross_account_trust_policy.json
  max_session_duration = var.max_session_duration_master

  tags = {
    Name        = "MasterCrossAccountRole-${random_id.suffix.hex}"
    Environment = var.environment
    Purpose     = "Cross-Account-Master"
  }
}

# Attach permissions policy to master role
resource "aws_iam_role_policy" "master_cross_account_permissions" {
  name   = "CrossAccountAssumePolicy"
  role   = aws_iam_role.master_cross_account.id
  policy = data.aws_iam_policy_document.master_cross_account_permissions.json
}

#------------------------------------------------------------------------------
# PRODUCTION ACCOUNT RESOURCES
#------------------------------------------------------------------------------

# S3 bucket for production account shared data
resource "aws_s3_bucket" "production_shared_data" {
  provider = aws.production
  bucket   = "${var.production_s3_bucket_name}-${random_id.suffix.hex}"

  tags = {
    Name        = "${var.production_s3_bucket_name}-${random_id.suffix.hex}"
    Environment = "production"
    Purpose     = "Cross-Account-Shared-Data"
  }
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "production_shared_data" {
  provider = aws.production
  bucket   = aws_s3_bucket.production_shared_data.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "production_shared_data" {
  provider = aws.production
  bucket   = aws_s3_bucket.production_shared_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "production_shared_data" {
  provider = aws.production
  bucket   = aws_s3_bucket.production_shared_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM trust policy for production cross-account role
data "aws_iam_policy_document" "production_cross_account_trust_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.master_cross_account.arn]
    }
    
    actions = ["sts:AssumeRole"]
    
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [random_password.production_external_id.result]
    }
    
    dynamic "condition" {
      for_each = var.enable_mfa_requirement ? [1] : []
      
      content {
        test     = "Bool"
        variable = "aws:MultiFactorAuthPresent"
        values   = ["true"]
      }
    }
    
    condition {
      test     = "StringLike"
      variable = "aws:userid"
      values   = ["*:${var.security_account_id}:*"]
    }
  }
}

# IAM permissions policy for production cross-account role
data "aws_iam_policy_document" "production_cross_account_permissions" {
  # S3 access permissions
  statement {
    effect = "Allow"
    
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket"
    ]
    
    resources = [
      aws_s3_bucket.production_shared_data.arn,
      "${aws_s3_bucket.production_shared_data.arn}/*"
    ]
  }
  
  # CloudWatch Logs permissions
  statement {
    effect = "Allow"
    
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
    
    resources = ["arn:aws:logs:${var.aws_region}:${var.production_account_id}:*"]
  }
  
  # CloudWatch metrics permissions
  statement {
    effect = "Allow"
    
    actions = [
      "cloudwatch:PutMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics"
    ]
    
    resources = ["*"]
  }
}

# Production cross-account role
resource "aws_iam_role" "production_cross_account" {
  provider             = aws.production
  name                 = "CrossAccount-ProductionAccess-${random_id.suffix.hex}"
  description          = "Cross-account role for production resource access"
  assume_role_policy   = data.aws_iam_policy_document.production_cross_account_trust_policy.json
  max_session_duration = var.max_session_duration_production

  tags = {
    Name        = "CrossAccount-ProductionAccess-${random_id.suffix.hex}"
    Environment = "production"
    Purpose     = "Cross-Account-Production"
  }
}

# Attach permissions policy to production role
resource "aws_iam_role_policy" "production_cross_account_permissions" {
  provider = aws.production
  name     = "ProductionResourceAccess"
  role     = aws_iam_role.production_cross_account.id
  policy   = data.aws_iam_policy_document.production_cross_account_permissions.json
}

#------------------------------------------------------------------------------
# DEVELOPMENT ACCOUNT RESOURCES
#------------------------------------------------------------------------------

# S3 bucket for development account shared data
resource "aws_s3_bucket" "development_shared_data" {
  provider = aws.development
  bucket   = "${var.development_s3_bucket_name}-${random_id.suffix.hex}"

  tags = {
    Name        = "${var.development_s3_bucket_name}-${random_id.suffix.hex}"
    Environment = "development"
    Purpose     = "Cross-Account-Shared-Data"
  }
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "development_shared_data" {
  provider = aws.development
  bucket   = aws_s3_bucket.development_shared_data.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "development_shared_data" {
  provider = aws.development
  bucket   = aws_s3_bucket.development_shared_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "development_shared_data" {
  provider = aws.development
  bucket   = aws_s3_bucket.development_shared_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM trust policy for development cross-account role
data "aws_iam_policy_document" "development_cross_account_trust_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.master_cross_account.arn]
    }
    
    actions = ["sts:AssumeRole"]
    
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [random_password.development_external_id.result]
    }
    
    condition {
      test     = "StringLike"
      variable = "aws:userid"
      values   = ["*:${var.security_account_id}:*"]
    }
    
    dynamic "condition" {
      for_each = var.enable_ip_restrictions ? [1] : []
      
      content {
        test     = "IpAddress"
        variable = "aws:SourceIp"
        values   = var.allowed_source_ips
      }
    }
  }
}

# IAM permissions policy for development cross-account role
data "aws_iam_policy_document" "development_cross_account_permissions" {
  # S3 full access to development bucket
  statement {
    effect = "Allow"
    
    actions = ["s3:*"]
    
    resources = [
      aws_s3_bucket.development_shared_data.arn,
      "${aws_s3_bucket.development_shared_data.arn}/*"
    ]
  }
  
  # EC2 read-only permissions
  statement {
    effect = "Allow"
    
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets"
    ]
    
    resources = ["*"]
  }
  
  # Lambda permissions for development functions
  statement {
    effect = "Allow"
    
    actions = [
      "lambda:InvokeFunction",
      "lambda:GetFunction",
      "lambda:ListFunctions"
    ]
    
    resources = ["arn:aws:lambda:${var.aws_region}:${var.development_account_id}:function:dev-*"]
  }
  
  # CloudWatch Logs full access
  statement {
    effect = "Allow"
    
    actions = ["logs:*"]
    
    resources = ["arn:aws:logs:${var.aws_region}:${var.development_account_id}:*"]
  }
}

# Development cross-account role
resource "aws_iam_role" "development_cross_account" {
  provider             = aws.development
  name                 = "CrossAccount-DevelopmentAccess-${random_id.suffix.hex}"
  description          = "Cross-account role for development resource access"
  assume_role_policy   = data.aws_iam_policy_document.development_cross_account_trust_policy.json
  max_session_duration = var.max_session_duration_development

  tags = {
    Name        = "CrossAccount-DevelopmentAccess-${random_id.suffix.hex}"
    Environment = "development"
    Purpose     = "Cross-Account-Development"
  }
}

# Attach permissions policy to development role
resource "aws_iam_role_policy" "development_cross_account_permissions" {
  provider = aws.development
  name     = "DevelopmentResourceAccess"
  role     = aws_iam_role.development_cross_account.id
  policy   = data.aws_iam_policy_document.development_cross_account_permissions.json
}

#------------------------------------------------------------------------------
# CLOUDTRAIL AUDIT LOGGING (Security Account)
#------------------------------------------------------------------------------

# S3 bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail_logs" {
  count  = var.enable_cloudtrail_logging ? 1 : 0
  bucket = "cross-account-audit-trail-${random_id.suffix.hex}"

  tags = {
    Name        = "cross-account-audit-trail-${random_id.suffix.hex}"
    Environment = var.environment
    Purpose     = "CloudTrail-Audit-Logs"
  }
}

# S3 bucket versioning for CloudTrail
resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  count  = var.enable_cloudtrail_logging ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption for CloudTrail
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  count  = var.enable_cloudtrail_logging ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block for CloudTrail
resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  count  = var.enable_cloudtrail_logging ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration for CloudTrail logs
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs" {
  count  = var.enable_cloudtrail_logging ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  rule {
    id     = "cloudtrail_log_retention"
    status = "Enabled"

    expiration {
      days = var.cloudtrail_log_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# S3 bucket policy for CloudTrail
data "aws_iam_policy_document" "cloudtrail_bucket_policy" {
  count = var.enable_cloudtrail_logging ? 1 : 0
  
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    
    actions = [
      "s3:PutObject",
      "s3:GetBucketAcl"
    ]
    
    resources = [
      aws_s3_bucket.cloudtrail_logs[0].arn,
      "${aws_s3_bucket.cloudtrail_logs[0].arn}/*"
    ]
    
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
  
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    
    actions = ["s3:GetBucketAcl"]
    
    resources = [aws_s3_bucket.cloudtrail_logs[0].arn]
  }
}

# Apply bucket policy
resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  count  = var.enable_cloudtrail_logging ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id
  policy = data.aws_iam_policy_document.cloudtrail_bucket_policy[0].json
}

# CloudTrail for cross-account activity monitoring
resource "aws_cloudtrail" "cross_account_audit" {
  count                         = var.enable_cloudtrail_logging ? 1 : 0
  name                          = "CrossAccountAuditTrail-${random_id.suffix.hex}"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs[0].bucket
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type                 = "All"
    include_management_events       = true

    data_resource {
      type   = "AWS::IAM::Role"
      values = ["arn:aws:iam::*:role/CrossAccount-*"]
    }

    data_resource {
      type   = "AWS::STS::AssumeRole"
      values = ["*"]
    }
  }

  tags = {
    Name        = "CrossAccountAuditTrail-${random_id.suffix.hex}"
    Environment = var.environment
    Purpose     = "Cross-Account-Audit"
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
}

#------------------------------------------------------------------------------
# LAMBDA ROLE VALIDATION (Security Account)
#------------------------------------------------------------------------------

# Lambda execution role for role validator
resource "aws_iam_role" "role_validator_lambda" {
  count = var.enable_role_validation ? 1 : 0
  name  = "RoleValidatorLambdaRole-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "RoleValidatorLambdaRole-${random_id.suffix.hex}"
    Environment = var.environment
    Purpose     = "Role-Validation"
  }
}

# Attach basic execution policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  count      = var.enable_role_validation ? 1 : 0
  role       = aws_iam_role.role_validator_lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach IAM read-only policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_iam_readonly" {
  count      = var.enable_role_validation ? 1 : 0
  role       = aws_iam_role.role_validator_lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/IAMReadOnlyAccess"
}

# Lambda function for role validation
resource "aws_lambda_function" "role_validator" {
  count            = var.enable_role_validation ? 1 : 0
  filename         = data.archive_file.role_validator_zip[0].output_path
  function_name    = "CrossAccountRoleValidator-${random_id.suffix.hex}"
  role            = aws_iam_role.role_validator_lambda[0].arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.role_validator_zip[0].output_base64sha256
  runtime         = var.lambda_runtime
  timeout         = 300
  memory_size     = 256

  environment {
    variables = {
      LOG_LEVEL = "INFO"
    }
  }

  tags = {
    Name        = "CrossAccountRoleValidator-${random_id.suffix.hex}"
    Environment = var.environment
    Purpose     = "Role-Validation"
  }
}

# Lambda function code archive
data "archive_file" "role_validator_zip" {
  count       = var.enable_role_validation ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/role_validator.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      security_account_id = var.security_account_id
    })
    filename = "lambda_function.py"
  }
}

# CloudWatch EventBridge rule for scheduled validation
resource "aws_cloudwatch_event_rule" "role_validation_schedule" {
  count               = var.enable_role_validation ? 1 : 0
  name                = "role-validation-schedule-${random_id.suffix.hex}"
  description         = "Trigger role validation Lambda function"
  schedule_expression = "rate(24 hours)"

  tags = {
    Name        = "role-validation-schedule-${random_id.suffix.hex}"
    Environment = var.environment
    Purpose     = "Role-Validation"
  }
}

# CloudWatch EventBridge target
resource "aws_cloudwatch_event_target" "role_validation_target" {
  count = var.enable_role_validation ? 1 : 0
  rule  = aws_cloudwatch_event_rule.role_validation_schedule[0].name
  arn   = aws_lambda_function.role_validator[0].arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  count         = var.enable_role_validation ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.role_validator[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.role_validation_schedule[0].arn
}