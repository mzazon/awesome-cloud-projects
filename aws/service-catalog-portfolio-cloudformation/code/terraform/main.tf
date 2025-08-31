# Service Catalog Portfolio with CloudFormation Templates
# This Terraform configuration creates a complete Service Catalog portfolio with 
# S3 bucket and Lambda function products, including governance controls and access management.

# Data sources for AWS account information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 6
  keepers = {
    portfolio_name = var.portfolio_name
  }
}

locals {
  # Generate unique names using random suffix
  unique_suffix         = lower(random_id.suffix.hex)
  portfolio_display_name = "${var.portfolio_name}-${local.unique_suffix}"
  s3_product_display_name = "${var.s3_product_name}-${local.unique_suffix}"
  lambda_product_display_name = "${var.lambda_product_name}-${local.unique_suffix}"
  launch_role_name      = "${var.launch_role_name}-${local.unique_suffix}"
  templates_bucket_name = "${var.templates_bucket_prefix}-${local.unique_suffix}"
  
  # Combine default and additional tags
  common_tags = merge(
    {
      Environment = var.environment
      Project     = "ServiceCatalogPortfolio"
      ManagedBy   = "Terraform"
    },
    var.tags
  )
}

# S3 bucket for storing CloudFormation templates
resource "aws_s3_bucket" "templates" {
  bucket        = local.templates_bucket_name
  force_destroy = true

  tags = merge(local.common_tags, {
    Name        = "Service Catalog Templates Bucket"
    Description = "Storage for CloudFormation templates used in Service Catalog products"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "templates" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.templates.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "templates" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.templates.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block (security best practice)
resource "aws_s3_bucket_public_access_block" "templates" {
  bucket = aws_s3_bucket.templates.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFormation template for S3 bucket product
resource "aws_s3_object" "s3_template" {
  bucket       = aws_s3_bucket.templates.id
  key          = "s3-bucket-template.yaml"
  content_type = "application/x-yaml"
  
  content = yamlencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description = "Managed S3 bucket with security best practices"
    
    Parameters = {
      BucketName = {
        Type = "String"
        Description = "Name for the S3 bucket"
        AllowedPattern = "^[a-z0-9][a-z0-9-]*[a-z0-9]$"
        ConstraintDescription = "Bucket name must be lowercase alphanumeric with hyphens"
      }
      Environment = {
        Type = "String"
        Default = "development"
        AllowedValues = ["development", "staging", "production"]
        Description = "Environment for resource tagging"
      }
    }
    
    Resources = {
      S3Bucket = {
        Type = "AWS::S3::Bucket"
        Properties = {
          BucketName = { Ref = "BucketName" }
          BucketEncryption = {
            ServerSideEncryptionConfiguration = [{
              ServerSideEncryptionByDefault = {
                SSEAlgorithm = "AES256"
              }
            }]
          }
          VersioningConfiguration = {
            Status = "Enabled"
          }
          PublicAccessBlockConfiguration = {
            BlockPublicAcls = true
            BlockPublicPolicy = true
            IgnorePublicAcls = true
            RestrictPublicBuckets = true
          }
          Tags = [
            {
              Key = "Environment"
              Value = { Ref = "Environment" }
            },
            {
              Key = "ManagedBy"
              Value = "ServiceCatalog"
            }
          ]
        }
      }
    }
    
    Outputs = {
      BucketName = {
        Description = "Name of the created S3 bucket"
        Value = { Ref = "S3Bucket" }
      }
      BucketArn = {
        Description = "ARN of the created S3 bucket"
        Value = { "Fn::GetAtt" = ["S3Bucket", "Arn"] }
      }
    }
  })

  tags = merge(local.common_tags, {
    Name        = "S3 Bucket CloudFormation Template"
    Description = "Template for creating managed S3 buckets through Service Catalog"
  })
}

# CloudFormation template for Lambda function product
resource "aws_s3_object" "lambda_template" {
  bucket       = aws_s3_bucket.templates.id
  key          = "lambda-function-template.yaml"
  content_type = "application/x-yaml"
  
  content = yamlencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description = "Managed Lambda function with IAM role and CloudWatch logging"
    
    Parameters = {
      FunctionName = {
        Type = "String"
        Description = "Name for the Lambda function"
        AllowedPattern = "^[a-zA-Z0-9-_]+$"
      }
      Runtime = {
        Type = "String"
        Default = "python3.12"
        AllowedValues = ["python3.12", "python3.11", "nodejs20.x", "nodejs22.x"]
        Description = "Runtime environment for the function"
      }
      Environment = {
        Type = "String"
        Default = "development"
        AllowedValues = ["development", "staging", "production"]
        Description = "Environment for resource tagging"
      }
    }
    
    Resources = {
      LambdaExecutionRole = {
        Type = "AWS::IAM::Role"
        Properties = {
          AssumeRolePolicyDocument = {
            Version = "2012-10-17"
            Statement = [{
              Effect = "Allow"
              Principal = {
                Service = "lambda.amazonaws.com"
              }
              Action = "sts:AssumeRole"
            }]
          }
          ManagedPolicyArns = [
            "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
          ]
          Tags = [
            {
              Key = "Environment"
              Value = { Ref = "Environment" }
            },
            {
              Key = "ManagedBy"
              Value = "ServiceCatalog"
            }
          ]
        }
      }
      LambdaFunction = {
        Type = "AWS::Lambda::Function"
        Properties = {
          FunctionName = { Ref = "FunctionName" }
          Runtime = { Ref = "Runtime" }
          Handler = "index.handler"
          Role = { "Fn::GetAtt" = ["LambdaExecutionRole", "Arn"] }
          Code = {
            ZipFile = "def handler(event, context):\n    return {\n        'statusCode': 200,\n        'body': 'Hello from Service Catalog managed Lambda!'\n    }\n"
          }
          Tags = [
            {
              Key = "Environment"
              Value = { Ref = "Environment" }
            },
            {
              Key = "ManagedBy"
              Value = "ServiceCatalog"
            }
          ]
        }
      }
    }
    
    Outputs = {
      FunctionName = {
        Description = "Name of the created Lambda function"
        Value = { Ref = "LambdaFunction" }
      }
      FunctionArn = {
        Description = "ARN of the created Lambda function"
        Value = { "Fn::GetAtt" = ["LambdaFunction", "Arn"] }
      }
    }
  })

  tags = merge(local.common_tags, {
    Name        = "Lambda Function CloudFormation Template"
    Description = "Template for creating managed Lambda functions through Service Catalog"
  })
}

# IAM trust policy for Service Catalog launch role
data "aws_iam_policy_document" "servicecatalog_trust_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["servicecatalog.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# IAM policy document for launch constraints permissions
data "aws_iam_policy_document" "launch_policy" {
  statement {
    effect = "Allow"
    actions = [
      # S3 permissions
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:PutBucketEncryption",
      "s3:PutBucketVersioning",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketTagging",
      # Lambda permissions
      "lambda:CreateFunction",
      "lambda:DeleteFunction",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:TagResource",
      "lambda:UntagResource",
      # IAM permissions for Lambda execution roles
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PassRole",
      "iam:TagRole",
      "iam:UntagRole"
    ]
    resources = ["*"]
  }
}

# IAM role for Service Catalog launch constraints
resource "aws_iam_role" "launch_role" {
  name               = local.launch_role_name
  assume_role_policy = data.aws_iam_policy_document.servicecatalog_trust_policy.json
  description        = "IAM role for Service Catalog product launch constraints"

  tags = merge(local.common_tags, {
    Name        = "Service Catalog Launch Role"
    Description = "Role used by Service Catalog to provision resources"
  })
}

# IAM policy for launch role
resource "aws_iam_role_policy" "launch_policy" {
  name   = "ServiceCatalogLaunchPolicy"
  role   = aws_iam_role.launch_role.id
  policy = data.aws_iam_policy_document.launch_policy.json
}

# Service Catalog Portfolio
resource "aws_servicecatalog_portfolio" "main" {
  name          = local.portfolio_display_name
  description   = var.portfolio_description
  provider_name = var.portfolio_provider_name

  tags = merge(local.common_tags, {
    Name        = "Enterprise Infrastructure Portfolio"
    Description = "Portfolio containing standardized infrastructure templates"
  })
}

# Service Catalog Product for S3 Bucket
resource "aws_servicecatalog_product" "s3_bucket" {
  name  = local.s3_product_display_name
  owner = var.portfolio_provider_name
  type  = "CLOUD_FORMATION_TEMPLATE"
  description = "Managed S3 bucket with security best practices"

  provisioning_artifact_parameters {
    name         = "v1.0"
    description  = "Initial version with encryption and versioning"
    type         = "CLOUD_FORMATION_TEMPLATE"
    template_url = "https://${aws_s3_bucket.templates.bucket_domain_name}/${aws_s3_object.s3_template.key}"
  }

  tags = merge(local.common_tags, {
    Name        = "S3 Bucket Product"
    Description = "Service Catalog product for standardized S3 buckets"
  })

  depends_on = [aws_s3_object.s3_template]
}

# Service Catalog Product for Lambda Function
resource "aws_servicecatalog_product" "lambda_function" {
  name  = local.lambda_product_display_name
  owner = var.portfolio_provider_name
  type  = "CLOUD_FORMATION_TEMPLATE"
  description = "Managed Lambda function with IAM role and logging"

  provisioning_artifact_parameters {
    name         = "v1.0"
    description  = "Initial version with execution role"
    type         = "CLOUD_FORMATION_TEMPLATE"
    template_url = "https://${aws_s3_bucket.templates.bucket_domain_name}/${aws_s3_object.lambda_template.key}"
  }

  tags = merge(local.common_tags, {
    Name        = "Lambda Function Product"
    Description = "Service Catalog product for standardized Lambda functions"
  })

  depends_on = [aws_s3_object.lambda_template]
}

# Associate S3 product with portfolio
resource "aws_servicecatalog_product_portfolio_association" "s3_association" {
  portfolio_id = aws_servicecatalog_portfolio.main.id
  product_id   = aws_servicecatalog_product.s3_bucket.id
}

# Associate Lambda product with portfolio
resource "aws_servicecatalog_product_portfolio_association" "lambda_association" {
  portfolio_id = aws_servicecatalog_portfolio.main.id
  product_id   = aws_servicecatalog_product.lambda_function.id
}

# Launch constraint for S3 product
resource "aws_servicecatalog_constraint" "s3_launch_constraint" {
  description  = "Launch constraint for S3 bucket product"
  portfolio_id = aws_servicecatalog_portfolio.main.id
  product_id   = aws_servicecatalog_product.s3_bucket.id
  type         = "LAUNCH"
  parameters   = jsonencode({
    RoleArn = aws_iam_role.launch_role.arn
  })

  depends_on = [
    aws_servicecatalog_product_portfolio_association.s3_association,
    aws_iam_role_policy.launch_policy
  ]
}

# Launch constraint for Lambda product
resource "aws_servicecatalog_constraint" "lambda_launch_constraint" {
  description  = "Launch constraint for Lambda function product"
  portfolio_id = aws_servicecatalog_portfolio.main.id
  product_id   = aws_servicecatalog_product.lambda_function.id
  type         = "LAUNCH"
  parameters   = jsonencode({
    RoleArn = aws_iam_role.launch_role.arn
  })

  depends_on = [
    aws_servicecatalog_product_portfolio_association.lambda_association,
    aws_iam_role_policy.launch_policy
  ]
}

# Principal associations for portfolio access
resource "aws_servicecatalog_principal_portfolio_association" "main" {
  count        = length(var.principal_arns)
  portfolio_id = aws_servicecatalog_portfolio.main.id
  principal_arn = var.principal_arns[count.index]
  principal_type = "IAM"
}

# If no principal ARNs provided, associate with current user/role
data "aws_caller_identity" "current_user" {}

resource "aws_servicecatalog_principal_portfolio_association" "current_user" {
  count          = length(var.principal_arns) == 0 ? 1 : 0
  portfolio_id   = aws_servicecatalog_portfolio.main.id
  principal_arn  = data.aws_caller_identity.current_user.arn
  principal_type = "IAM"
}