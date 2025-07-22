# Infrastructure Policy Validation with CloudFormation Guard
# This Terraform configuration creates the infrastructure needed for implementing
# policy-as-code validation using AWS CloudFormation Guard

# Data source to get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# S3 bucket for storing Guard rules, test cases, and validation reports
resource "aws_s3_bucket" "guard_policies" {
  bucket = "cfn-guard-policies-${random_id.suffix.hex}"

  tags = {
    Name        = "CloudFormation Guard Policies"
    Environment = var.environment
    Project     = "Policy Validation"
    Team        = var.team
    CostCenter  = var.cost_center
  }
}

# Enable versioning on the S3 bucket for rule history and compliance auditing
resource "aws_s3_bucket_versioning" "guard_policies_versioning" {
  bucket = aws_s3_bucket.guard_policies.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption for security compliance
resource "aws_s3_bucket_server_side_encryption_configuration" "guard_policies_encryption" {
  bucket = aws_s3_bucket.guard_policies.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block all public access to ensure security
resource "aws_s3_bucket_public_access_block" "guard_policies_pab" {
  bucket = aws_s3_bucket.guard_policies.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "guard_policies_lifecycle" {
  bucket = aws_s3_bucket.guard_policies.id

  rule {
    id     = "validation_reports_cleanup"
    status = "Enabled"

    # Move validation reports to IA after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Move to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Delete old reports after 1 year
    expiration {
      days = 365
    }

    filter {
      prefix = "reports/"
    }
  }

  rule {
    id     = "guard_rules_versioning"
    status = "Enabled"

    # Keep only the latest 10 versions of rule files
    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    filter {
      prefix = "guard-rules/"
    }
  }
}

# CloudWatch Log Group for storing validation logs
resource "aws_cloudwatch_log_group" "guard_validation_logs" {
  name              = "/aws/guard-validation/${random_id.suffix.hex}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "Guard Validation Logs"
    Environment = var.environment
    Project     = "Policy Validation"
  }
}

# IAM role for CloudFormation Guard validation automation
resource "aws_iam_role" "guard_validation_role" {
  name = "CloudFormationGuardValidationRole-${random_id.suffix.hex}"
  path = "/policy-validation/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "codebuild.amazonaws.com"
          ]
        }
      }
    ]
  })

  tags = {
    Name        = "Guard Validation Role"
    Environment = var.environment
    Project     = "Policy Validation"
  }
}

# IAM policy for Guard validation role
resource "aws_iam_role_policy" "guard_validation_policy" {
  name = "GuardValidationPolicy"
  role = aws_iam_role.guard_validation_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.guard_policies.arn,
          "${aws_s3_bucket.guard_policies.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.guard_validation_logs.arn}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudformation:ValidateTemplate",
          "cloudformation:DescribeStacks",
          "cloudformation:DescribeStackResources"
        ]
        Resource = "*"
      }
    ]
  })
}

# S3 objects for Guard rule files - Security Rules
resource "aws_s3_object" "s3_security_rules" {
  bucket = aws_s3_bucket.guard_policies.id
  key    = "guard-rules/security/s3-security.guard"
  
  content = <<EOF
# Rule: S3 buckets must have versioning enabled
rule s3_bucket_versioning_enabled {
    AWS::S3::Bucket {
        Properties {
            VersioningConfiguration exists
            VersioningConfiguration {
                Status == "Enabled"
            }
        }
    }
}

# Rule: S3 buckets must have encryption enabled
rule s3_bucket_encryption_enabled {
    AWS::S3::Bucket {
        Properties {
            BucketEncryption exists
            BucketEncryption {
                ServerSideEncryptionConfiguration exists
                ServerSideEncryptionConfiguration[*] {
                    ServerSideEncryptionByDefault exists
                    ServerSideEncryptionByDefault {
                        SSEAlgorithm exists
                    }
                }
            }
        }
    }
}

# Rule: S3 buckets must block public access
rule s3_bucket_public_access_blocked {
    AWS::S3::Bucket {
        Properties {
            PublicAccessBlockConfiguration exists
            PublicAccessBlockConfiguration {
                BlockPublicAcls == true
                BlockPublicPolicy == true
                IgnorePublicAcls == true
                RestrictPublicBuckets == true
            }
        }
    }
}

# Rule: S3 buckets must have MFA delete enabled for production
rule s3_bucket_mfa_delete_enabled when Tags exists {
    AWS::S3::Bucket {
        Properties {
            when Tags[*] { Key == "Environment" Value == "Production" } {
                VersioningConfiguration {
                    MfaDelete == "Enabled"
                }
            }
        }
    }
}
EOF

  tags = {
    RuleCategory = "Security"
    RuleType     = "S3"
  }
}

# S3 objects for Guard rule files - IAM Security Rules
resource "aws_s3_object" "iam_security_rules" {
  bucket = aws_s3_bucket.guard_policies.id
  key    = "guard-rules/security/iam-security.guard"
  
  content = <<EOF
# Rule: IAM roles must have assume role policy
rule iam_role_assume_role_policy {
    AWS::IAM::Role {
        Properties {
            AssumeRolePolicyDocument exists
        }
    }
}

# Rule: IAM policies must not allow full admin access
rule iam_no_admin_policy {
    AWS::IAM::Policy {
        Properties {
            PolicyDocument {
                Statement[*] {
                    Effect == "Allow"
                    Action != "*"
                    Resource != "*"
                }
            }
        }
    }
}

# Rule: IAM roles must have path prefix for organization
rule iam_role_path_prefix {
    AWS::IAM::Role {
        Properties {
            Path exists
            Path == /^\/[a-zA-Z0-9_-]+\/$/
        }
    }
}

# Rule: IAM users should not have direct policies
rule iam_user_no_direct_policies {
    AWS::IAM::User {
        Properties {
            Policies empty
        }
    }
}
EOF

  tags = {
    RuleCategory = "Security"
    RuleType     = "IAM"
  }
}

# S3 objects for Guard rule files - Compliance Rules
resource "aws_s3_object" "compliance_rules" {
  bucket = aws_s3_bucket.guard_policies.id
  key    = "guard-rules/compliance/resource-compliance.guard"
  
  content = <<EOF
# Rule: Resources must have required tags
rule resources_must_have_required_tags {
    Resources.*[ Type in ["AWS::S3::Bucket", "AWS::EC2::Instance", "AWS::Lambda::Function"] ] {
        Properties {
            Tags exists
            Tags[*] {
                Key in ["Environment", "Team", "Project", "CostCenter"]
            }
        }
    }
}

# Rule: Resource names must follow naming convention
rule resource_naming_convention {
    AWS::S3::Bucket {
        Properties {
            BucketName exists
            BucketName == /^[a-z0-9][a-z0-9\-]*[a-z0-9]$/
        }
    }
}

# Rule: Lambda functions must have timeout limits
rule lambda_timeout_limit {
    AWS::Lambda::Function {
        Properties {
            Timeout exists
            Timeout <= 300
        }
    }
}

# Rule: Lambda functions must have memory limits
rule lambda_memory_limit {
    AWS::Lambda::Function {
        Properties {
            MemorySize exists
            MemorySize <= 3008
            MemorySize >= 128
        }
    }
}
EOF

  tags = {
    RuleCategory = "Compliance"
    RuleType     = "General"
  }
}

# S3 objects for Guard rule files - Cost Optimization Rules
resource "aws_s3_object" "cost_optimization_rules" {
  bucket = aws_s3_bucket.guard_policies.id
  key    = "guard-rules/cost-optimization/cost-controls.guard"
  
  content = <<EOF
# Rule: EC2 instances must use approved instance types
rule ec2_approved_instance_types {
    AWS::EC2::Instance {
        Properties {
            InstanceType in ["t3.micro", "t3.small", "t3.medium", "m5.large", "m5.xlarge", "c5.large", "c5.xlarge"]
        }
    }
}

# Rule: RDS instances must have backup retention
rule rds_backup_retention {
    AWS::RDS::DBInstance {
        Properties {
            BackupRetentionPeriod exists
            BackupRetentionPeriod >= 7
            BackupRetentionPeriod <= 35
        }
    }
}

# Rule: RDS instances must use approved instance classes
rule rds_approved_instance_classes {
    AWS::RDS::DBInstance {
        Properties {
            DBInstanceClass in ["db.t3.micro", "db.t3.small", "db.t3.medium", "db.m5.large", "db.m5.xlarge"]
        }
    }
}
EOF

  tags = {
    RuleCategory = "CostOptimization"
    RuleType     = "General"
  }
}

# S3 object for rules manifest
resource "aws_s3_object" "rules_manifest" {
  bucket = aws_s3_bucket.guard_policies.id
  key    = "rules-manifest.json"
  
  content = jsonencode({
    version = "1.0"
    created = timestamp()
    rules = [
      {
        category    = "security"
        file        = "s3-security.guard"
        description = "S3 security compliance rules"
      },
      {
        category    = "security"
        file        = "iam-security.guard"
        description = "IAM security compliance rules"
      },
      {
        category    = "compliance"
        file        = "resource-compliance.guard"
        description = "Resource tagging and naming compliance"
      },
      {
        category    = "cost-optimization"
        file        = "cost-controls.guard"
        description = "Cost optimization and resource limits"
      }
    ]
  })

  tags = {
    Type = "Manifest"
  }
}

# Example compliant CloudFormation template
resource "aws_s3_object" "compliant_template" {
  bucket = aws_s3_bucket.guard_policies.id
  key    = "templates/compliant-template.yaml"
  
  content = <<EOF
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Compliant S3 bucket template for Guard validation'

Resources:
  SecureDataBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub 'secure-data-bucket-$${AWS::AccountId}-$${AWS::Region}'
      VersioningConfiguration:
        Status: Enabled
      BucketEncryption:
        ServerSideEncryptionConfiguration:
          - ServerSideEncryptionByDefault:
              SSEAlgorithm: AES256
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      Tags:
        - Key: Environment
          Value: Production
        - Key: Team
          Value: DataEngineering
        - Key: Project
          Value: DataLake
        - Key: CostCenter
          Value: CC-1001

  DataProcessingLambda:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: !Sub 'data-processing-$${AWS::Region}'
      Runtime: python3.9
      Handler: index.handler
      Role: !GetAtt LambdaExecutionRole.Arn
      Code:
        ZipFile: |
          def handler(event, context):
              return {'statusCode': 200}
      Timeout: 60
      MemorySize: 256
      Tags:
        - Key: Environment
          Value: Production
        - Key: Team
          Value: DataEngineering
        - Key: Project
          Value: DataLake
        - Key: CostCenter
          Value: CC-1001

  LambdaExecutionRole:
    Type: AWS::IAM::Role
    Properties:
      Path: /data-engineering/
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: lambda.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

Outputs:
  BucketName:
    Description: 'Name of the created S3 bucket'
    Value: !Ref SecureDataBucket
    Export:
      Name: !Sub '$${AWS::StackName}-BucketName'
  
  LambdaFunctionName:
    Description: 'Name of the Lambda function'
    Value: !Ref DataProcessingLambda
    Export:
      Name: !Sub '$${AWS::StackName}-LambdaFunctionName'
EOF

  tags = {
    Type         = "Template"
    Compliance   = "Compliant"
    TestPurpose  = "ValidationTesting"
  }
}

# Example non-compliant CloudFormation template for testing
resource "aws_s3_object" "non_compliant_template" {
  bucket = aws_s3_bucket.guard_policies.id
  key    = "templates/non-compliant-template.yaml"
  
  content = <<EOF
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Non-compliant S3 bucket template for Guard validation'

Resources:
  InsecureDataBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: 'UPPERCASE-BUCKET-NAME'
      # Missing: VersioningConfiguration
      # Missing: BucketEncryption
      # Missing: PublicAccessBlockConfiguration
      # Missing: Required tags

  UnsafeLambda:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: 'unsafe-lambda'
      Runtime: python3.9
      Handler: index.handler
      Role: !GetAtt UnsafeRole.Arn
      Code:
        ZipFile: |
          def handler(event, context):
              return {'statusCode': 200}
      Timeout: 900  # Exceeds limit
      MemorySize: 5000  # Exceeds limit
      # Missing: Required tags

  UnsafeRole:
    Type: AWS::IAM::Role
    Properties:
      # Missing: Path
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: lambda.amazonaws.com
            Action: sts:AssumeRole
      Policies:
        - PolicyName: AdminPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action: "*"
                Resource: "*"
EOF

  tags = {
    Type         = "Template"
    Compliance   = "NonCompliant"
    TestPurpose  = "ValidationTesting"
  }
}

# SNS topic for validation notifications (optional)
resource "aws_sns_topic" "guard_validation_notifications" {
  name = "guard-validation-notifications-${random_id.suffix.hex}"

  tags = {
    Name        = "Guard Validation Notifications"
    Environment = var.environment
    Project     = "Policy Validation"
  }
}

# CloudWatch dashboard for monitoring policy validation metrics
resource "aws_cloudwatch_dashboard" "guard_validation_dashboard" {
  dashboard_name = "CloudFormation-Guard-Validation-${random_id.suffix.hex}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/S3", "BucketSizeBytes", "BucketName", aws_s3_bucket.guard_policies.bucket, "StorageType", "StandardStorage"],
            [".", "NumberOfObjects", ".", ".", ".", "AllStorageTypes"]
          ]
          period = 86400
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Guard Policies S3 Bucket Metrics"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          query   = "SOURCE '${aws_cloudwatch_log_group.guard_validation_logs.name}' | fields @timestamp, @message | sort @timestamp desc | limit 100"
          region  = data.aws_region.current.name
          title   = "Recent Guard Validation Logs"
        }
      }
    ]
  })
}