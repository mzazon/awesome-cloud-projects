# Get current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random project ID for unique resource naming
resource "random_id" "project" {
  byte_length = 4
}

locals {
  project_id = lower(random_id.project.hex)
  common_name = "${var.project_name}-${local.project_id}"
  
  # Merge default and additional tags
  common_tags = merge(
    {
      Project     = var.project_name
      ProjectId   = local.project_id
      Environment = var.environment
      Purpose     = "BusinessContinuityTesting"
    },
    var.additional_tags
  )
}

# ============================================================================
# KMS Key for Encryption (if enabled)
# ============================================================================

resource "aws_kms_key" "bc_testing" {
  count = var.enable_encryption ? 1 : 0

  description             = "KMS key for business continuity testing resources"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow BC Testing Services"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "s3.amazonaws.com",
            "ssm.amazonaws.com",
            "logs.amazonaws.com"
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.common_name}-kms-key"
  })
}

resource "aws_kms_alias" "bc_testing" {
  count = var.enable_encryption ? 1 : 0

  name          = "alias/${local.common_name}-bc-testing"
  target_key_id = aws_kms_key.bc_testing[0].key_id
}

# ============================================================================
# S3 Bucket for Test Results and Reports
# ============================================================================

resource "aws_s3_bucket" "test_results" {
  bucket        = "${local.common_name}-test-results"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name        = "${local.common_name}-test-results"
    Description = "Storage for business continuity test results and compliance reports"
  })
}

resource "aws_s3_bucket_versioning" "test_results" {
  bucket = aws_s3_bucket.test_results.id
  
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "test_results" {
  bucket = aws_s3_bucket.test_results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_encryption ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_encryption ? aws_kms_key.bc_testing[0].arn : null
    }
    bucket_key_enabled = var.enable_encryption
  }
}

resource "aws_s3_bucket_public_access_block" "test_results" {
  bucket = aws_s3_bucket.test_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "test_results" {
  bucket = aws_s3_bucket.test_results.id

  rule {
    id     = "bc-test-results-retention"
    status = "Enabled"

    filter {
      prefix = "test-results/"
    }

    transition {
      days          = var.s3_lifecycle_rules.transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_lifecycle_rules.transition_to_glacier_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.s3_lifecycle_rules.expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# ============================================================================
# IAM Role for Business Continuity Testing Automation
# ============================================================================

resource "aws_iam_role" "bc_automation" {
  name = "${local.common_name}-bc-automation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "ssm.amazonaws.com",
            "lambda.amazonaws.com",
            "states.amazonaws.com",
            "events.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "${local.common_name}-bc-automation-role"
    Description = "IAM role for business continuity testing automation"
  })
}

resource "aws_iam_role_policy" "bc_automation" {
  name = "${local.common_name}-bc-automation-policy"
  role = aws_iam_role.bc_automation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          # Systems Manager permissions
          "ssm:*",
          # EC2 permissions for testing
          "ec2:*",
          # RDS permissions for database testing
          "rds:*",
          # S3 permissions for results storage
          "s3:*",
          # Lambda permissions for orchestration
          "lambda:*",
          # Step Functions permissions
          "states:*",
          # EventBridge permissions
          "events:*",
          # CloudWatch permissions
          "cloudwatch:*",
          "logs:*",
          # SNS permissions for notifications
          "sns:*",
          # AWS Backup permissions
          "backup:*",
          # Route 53 permissions for DNS testing
          "route53:*",
          # KMS permissions
          "kms:Decrypt",
          "kms:GenerateDataKey",
          # IAM permissions for role passing
          "iam:PassRole"
        ]
        Resource = "*"
      }
    ]
  })
}

# ============================================================================
# SNS Topic for Notifications
# ============================================================================

resource "aws_sns_topic" "bc_alerts" {
  name = "${local.common_name}-bc-alerts"

  kms_master_key_id = var.enable_encryption ? aws_kms_key.bc_testing[0].id : null

  tags = merge(local.common_tags, {
    Name        = "${local.common_name}-bc-alerts"
    Description = "SNS topic for business continuity testing alerts"
  })
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.bc_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ============================================================================
# Systems Manager Automation Documents
# ============================================================================

# Backup Validation Automation Document
resource "aws_ssm_document" "backup_validation" {
  name          = "BC-BackupValidation-${local.project_id}"
  document_type = "Automation"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "0.3"
    description   = "Validate backup integrity and restore capabilities"
    assumeRole    = "{{ AutomationAssumeRole }}"
    parameters = {
      InstanceId = {
        type        = "String"
        description = "EC2 instance ID to test backup restore"
      }
      BackupVaultName = {
        type        = "String"
        description = "AWS Backup vault name"
      }
      AutomationAssumeRole = {
        type        = "String"
        description = "IAM role for automation execution"
      }
    }
    mainSteps = [
      {
        name   = "CreateRestoreTestInstance"
        action = "aws:executeAwsApi"
        inputs = {
          Service = "backup"
          Api     = "StartRestoreJob"
          RecoveryPointArn = "{{ GetLatestRecoveryPoint.RecoveryPointArn }}"
          Metadata = {
            InstanceType = "t3.micro"
          }
          IamRoleArn = "{{ AutomationAssumeRole }}"
        }
        outputs = [
          {
            Name     = "RestoreJobId"
            Selector = "$.RestoreJobId"
            Type     = "String"
          }
        ]
      },
      {
        name   = "WaitForRestoreCompletion"
        action = "aws:waitForAwsResourceProperty"
        inputs = {
          Service          = "backup"
          Api              = "DescribeRestoreJob"
          RestoreJobId     = "{{ CreateRestoreTestInstance.RestoreJobId }}"
          PropertySelector = "$.Status"
          DesiredValues    = ["COMPLETED"]
        }
        timeoutSeconds = 3600
      },
      {
        name   = "ValidateRestoredInstance"
        action = "aws:runCommand"
        inputs = {
          DocumentName = "AWS-RunShellScript"
          InstanceIds  = ["{{ CreateRestoreTestInstance.CreatedResourceArn }}"]
          Parameters = {
            commands = [
              "#!/bin/bash",
              "echo 'Validating restored instance...'",
              "systemctl status",
              "df -h",
              "if command -v nginx &> /dev/null; then systemctl status nginx; fi",
              "echo 'Validation completed'"
            ]
          }
        }
        outputs = [
          {
            Name     = "ValidationResults"
            Selector = "$.CommandInvocations[0].CommandPlugins[0].Output"
            Type     = "String"
          }
        ]
      },
      {
        name   = "CleanupTestInstance"
        action = "aws:executeAwsApi"
        inputs = {
          Service     = "ec2"
          Api         = "TerminateInstances"
          InstanceIds = ["{{ CreateRestoreTestInstance.CreatedResourceArn }}"]
        }
      }
    ]
    outputs = [
      {
        ValidationResults = "{{ ValidateRestoredInstance.ValidationResults }}"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "BC-BackupValidation-${local.project_id}"
    Description = "Systems Manager document for backup validation testing"
    Purpose     = "BusinessContinuityTesting"
  })
}

# Database Recovery Automation Document
resource "aws_ssm_document" "database_recovery" {
  name          = "BC-DatabaseRecovery-${local.project_id}"
  document_type = "Automation"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "0.3"
    description   = "Test database backup and recovery procedures"
    assumeRole    = "{{ AutomationAssumeRole }}"
    parameters = {
      DBInstanceIdentifier = {
        type        = "String"
        description = "RDS instance identifier"
      }
      DBSnapshotIdentifier = {
        type        = "String"
        description = "Snapshot to restore from"
      }
      TestDBInstanceIdentifier = {
        type        = "String"
        description = "Test database instance identifier"
      }
      AutomationAssumeRole = {
        type        = "String"
        description = "IAM role for automation execution"
      }
    }
    mainSteps = [
      {
        name   = "CreateTestDatabase"
        action = "aws:executeAwsApi"
        inputs = {
          Service                = "rds"
          Api                    = "RestoreDBInstanceFromDBSnapshot"
          DBInstanceIdentifier   = "{{ TestDBInstanceIdentifier }}"
          DBSnapshotIdentifier   = "{{ DBSnapshotIdentifier }}"
          DBInstanceClass        = "db.t3.micro"
          PubliclyAccessible     = false
          StorageEncrypted       = true
        }
        outputs = [
          {
            Name     = "TestDBEndpoint"
            Selector = "$.DBInstance.Endpoint.Address"
            Type     = "String"
          }
        ]
      },
      {
        name   = "WaitForDBAvailable"
        action = "aws:waitForAwsResourceProperty"
        inputs = {
          Service             = "rds"
          Api                 = "DescribeDBInstances"
          DBInstanceIdentifier = "{{ TestDBInstanceIdentifier }}"
          PropertySelector     = "$.DBInstances[0].DBInstanceStatus"
          DesiredValues        = ["available"]
        }
        timeoutSeconds = 1800
      },
      {
        name   = "CleanupTestDatabase"
        action = "aws:executeAwsApi"
        inputs = {
          Service                = "rds"
          Api                    = "DeleteDBInstance"
          DBInstanceIdentifier   = "{{ TestDBInstanceIdentifier }}"
          SkipFinalSnapshot      = true
          DeleteAutomatedBackups = true
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "BC-DatabaseRecovery-${local.project_id}"
    Description = "Systems Manager document for database recovery testing"
    Purpose     = "BusinessContinuityTesting"
  })
}

# Application Failover Automation Document
resource "aws_ssm_document" "application_failover" {
  name          = "BC-ApplicationFailover-${local.project_id}"
  document_type = "Automation"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "0.3"
    description   = "Test application failover to secondary region"
    assumeRole    = "{{ AutomationAssumeRole }}"
    parameters = {
      PrimaryLoadBalancerArn = {
        type        = "String"
        description = "Primary Application Load Balancer ARN"
      }
      SecondaryLoadBalancerArn = {
        type        = "String"
        description = "Secondary Application Load Balancer ARN"
      }
      Route53HostedZoneId = {
        type        = "String"
        description = "Route 53 hosted zone ID"
      }
      DomainName = {
        type        = "String"
        description = "Domain name for failover testing"
      }
      AutomationAssumeRole = {
        type        = "String"
        description = "IAM role for automation execution"
      }
    }
    mainSteps = [
      {
        name   = "SimulateFailoverToSecondary"
        action = "aws:executeAwsApi"
        inputs = {
          Service      = "route53"
          Api          = "ChangeResourceRecordSets"
          HostedZoneId = "{{ Route53HostedZoneId }}"
          ChangeBatch = {
            Changes = [
              {
                Action = "UPSERT"
                ResourceRecordSet = {
                  Name        = "{{ DomainName }}"
                  Type        = "A"
                  SetIdentifier = "Primary"
                  Failover    = "SECONDARY"
                  TTL         = 60
                  ResourceRecords = [
                    {
                      Value = "1.2.3.4"
                    }
                  ]
                }
              }
            ]
          }
        }
      },
      {
        name   = "WaitForDNSPropagation"
        action = "aws:sleep"
        inputs = {
          Duration = "PT2M"
        }
      },
      {
        name   = "RestorePrimaryRouting"
        action = "aws:executeAwsApi"
        inputs = {
          Service      = "route53"
          Api          = "ChangeResourceRecordSets"
          HostedZoneId = "{{ Route53HostedZoneId }}"
          ChangeBatch = {
            Changes = [
              {
                Action = "UPSERT"
                ResourceRecordSet = {
                  Name        = "{{ DomainName }}"
                  Type        = "A"
                  SetIdentifier = "Primary"
                  Failover    = "PRIMARY"
                  TTL         = 300
                  ResourceRecords = [
                    {
                      Value = "5.6.7.8"
                    }
                  ]
                }
              }
            ]
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "BC-ApplicationFailover-${local.project_id}"
    Description = "Systems Manager document for application failover testing"
    Purpose     = "BusinessContinuityTesting"
  })
}

# ============================================================================
# Lambda Functions
# ============================================================================

# CloudWatch Log Groups for Lambda functions
resource "aws_cloudwatch_log_group" "orchestrator" {
  name              = "/aws/lambda/${local.common_name}-orchestrator"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.enable_encryption ? aws_kms_key.bc_testing[0].arn : null

  tags = merge(local.common_tags, {
    Name = "${local.common_name}-orchestrator-logs"
  })
}

resource "aws_cloudwatch_log_group" "compliance_reporter" {
  name              = "/aws/lambda/${local.common_name}-compliance-reporter"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.enable_encryption ? aws_kms_key.bc_testing[0].arn : null

  tags = merge(local.common_tags, {
    Name = "${local.common_name}-compliance-reporter-logs"
  })
}

resource "aws_cloudwatch_log_group" "manual_executor" {
  name              = "/aws/lambda/${local.common_name}-manual-executor"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.enable_encryption ? aws_kms_key.bc_testing[0].arn : null

  tags = merge(local.common_tags, {
    Name = "${local.common_name}-manual-executor-logs"
  })
}

# Package Lambda functions
data "archive_file" "orchestrator" {
  type        = "zip"
  output_path = "${path.module}/orchestrator.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/orchestrator.py", {
      project_id          = local.project_id
      results_bucket      = aws_s3_bucket.test_results.bucket
      sns_topic_arn       = aws_sns_topic.bc_alerts.arn
      automation_role_arn = aws_iam_role.bc_automation.arn
    })
    filename = "orchestrator.py"
  }
}

data "archive_file" "compliance_reporter" {
  type        = "zip"
  output_path = "${path.module}/compliance_reporter.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/compliance_reporter.py", {
      results_bucket = aws_s3_bucket.test_results.bucket
    })
    filename = "compliance_reporter.py"
  }
}

data "archive_file" "manual_executor" {
  type        = "zip"
  output_path = "${path.module}/manual_executor.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/manual_executor.py", {
      project_id          = local.project_id
      automation_role_arn = aws_iam_role.bc_automation.arn
    })
    filename = "manual_executor.py"
  }
}

# BC Test Orchestrator Lambda
resource "aws_lambda_function" "orchestrator" {
  filename         = data.archive_file.orchestrator.output_path
  function_name    = "${local.common_name}-orchestrator"
  role            = aws_iam_role.bc_automation.arn
  handler         = "orchestrator.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  source_code_hash = data.archive_file.orchestrator.output_base64sha256

  environment {
    variables = {
      PROJECT_ID          = local.project_id
      RESULTS_BUCKET      = aws_s3_bucket.test_results.bucket
      SNS_TOPIC_ARN       = aws_sns_topic.bc_alerts.arn
      AUTOMATION_ROLE_ARN = aws_iam_role.bc_automation.arn
      TEST_INSTANCE_ID    = var.test_instance_id
      BACKUP_VAULT_NAME   = var.backup_vault_name
      DB_INSTANCE_ID      = var.db_instance_identifier
      PRIMARY_ALB_ARN     = var.primary_alb_arn
      SECONDARY_ALB_ARN   = var.secondary_alb_arn
      HOSTED_ZONE_ID      = var.route53_hosted_zone_id
      DOMAIN_NAME         = var.domain_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.orchestrator]

  tags = merge(local.common_tags, {
    Name        = "${local.common_name}-orchestrator"
    Description = "Lambda function for BC test orchestration"
  })
}

# Compliance Reporter Lambda
resource "aws_lambda_function" "compliance_reporter" {
  filename         = data.archive_file.compliance_reporter.output_path
  function_name    = "${local.common_name}-compliance-reporter"
  role            = aws_iam_role.bc_automation.arn
  handler         = "compliance_reporter.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = 300
  source_code_hash = data.archive_file.compliance_reporter.output_base64sha256

  environment {
    variables = {
      RESULTS_BUCKET = aws_s3_bucket.test_results.bucket
    }
  }

  depends_on = [aws_cloudwatch_log_group.compliance_reporter]

  tags = merge(local.common_tags, {
    Name        = "${local.common_name}-compliance-reporter"
    Description = "Lambda function for BC compliance reporting"
  })
}

# Manual Test Executor Lambda
resource "aws_lambda_function" "manual_executor" {
  filename         = data.archive_file.manual_executor.output_path
  function_name    = "${local.common_name}-manual-executor"
  role            = aws_iam_role.bc_automation.arn
  handler         = "manual_executor.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = 300
  source_code_hash = data.archive_file.manual_executor.output_base64sha256

  environment {
    variables = {
      PROJECT_ID          = local.project_id
      AUTOMATION_ROLE_ARN = aws_iam_role.bc_automation.arn
      TEST_INSTANCE_ID    = var.test_instance_id
      BACKUP_VAULT_NAME   = var.backup_vault_name
      DB_INSTANCE_ID      = var.db_instance_identifier
      PRIMARY_ALB_ARN     = var.primary_alb_arn
      SECONDARY_ALB_ARN   = var.secondary_alb_arn
      HOSTED_ZONE_ID      = var.route53_hosted_zone_id
      DOMAIN_NAME         = var.domain_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.manual_executor]

  tags = merge(local.common_tags, {
    Name        = "${local.common_name}-manual-executor"
    Description = "Lambda function for manual BC test execution"
  })
}

# ============================================================================
# EventBridge Rules for Scheduled Testing
# ============================================================================

# Daily BC Tests
resource "aws_cloudwatch_event_rule" "daily_tests" {
  name                = "${local.common_name}-daily-tests"
  description         = "Daily business continuity basic tests"
  schedule_expression = var.test_schedules.daily_tests

  tags = merge(local.common_tags, {
    Name = "${local.common_name}-daily-tests"
  })
}

resource "aws_cloudwatch_event_target" "daily_tests" {
  rule      = aws_cloudwatch_event_rule.daily_tests.name
  target_id = "DailyBCTests"
  arn       = aws_lambda_function.orchestrator.arn

  input = jsonencode({
    testType = "daily"
  })
}

resource "aws_lambda_permission" "allow_eventbridge_daily" {
  statement_id  = "AllowExecutionFromEventBridgeDaily"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orchestrator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_tests.arn
}

# Weekly BC Tests
resource "aws_cloudwatch_event_rule" "weekly_tests" {
  name                = "${local.common_name}-weekly-tests"
  description         = "Weekly comprehensive business continuity tests"
  schedule_expression = var.test_schedules.weekly_tests

  tags = merge(local.common_tags, {
    Name = "${local.common_name}-weekly-tests"
  })
}

resource "aws_cloudwatch_event_target" "weekly_tests" {
  rule      = aws_cloudwatch_event_rule.weekly_tests.name
  target_id = "WeeklyBCTests"
  arn       = aws_lambda_function.orchestrator.arn

  input = jsonencode({
    testType = "weekly"
  })
}

resource "aws_lambda_permission" "allow_eventbridge_weekly" {
  statement_id  = "AllowExecutionFromEventBridgeWeekly"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orchestrator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weekly_tests.arn
}

# Monthly BC Tests
resource "aws_cloudwatch_event_rule" "monthly_tests" {
  name                = "${local.common_name}-monthly-tests"
  description         = "Monthly full disaster recovery tests"
  schedule_expression = var.test_schedules.monthly_tests

  tags = merge(local.common_tags, {
    Name = "${local.common_name}-monthly-tests"
  })
}

resource "aws_cloudwatch_event_target" "monthly_tests" {
  rule      = aws_cloudwatch_event_rule.monthly_tests.name
  target_id = "MonthlyBCTests"
  arn       = aws_lambda_function.orchestrator.arn

  input = jsonencode({
    testType = "monthly"
  })
}

resource "aws_lambda_permission" "allow_eventbridge_monthly" {
  statement_id  = "AllowExecutionFromEventBridgeMonthly"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orchestrator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.monthly_tests.arn
}

# Monthly Compliance Reporting
resource "aws_cloudwatch_event_rule" "compliance_reporting" {
  name                = "${local.common_name}-compliance-reporting"
  description         = "Monthly BC compliance reporting"
  schedule_expression = var.test_schedules.compliance_report

  tags = merge(local.common_tags, {
    Name = "${local.common_name}-compliance-reporting"
  })
}

resource "aws_cloudwatch_event_target" "compliance_reporting" {
  rule      = aws_cloudwatch_event_rule.compliance_reporting.name
  target_id = "MonthlyComplianceReport"
  arn       = aws_lambda_function.compliance_reporter.arn
}

resource "aws_lambda_permission" "allow_eventbridge_compliance" {
  statement_id  = "AllowExecutionFromEventBridgeCompliance"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.compliance_reporter.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.compliance_reporting.arn
}

# ============================================================================
# CloudWatch Dashboard
# ============================================================================

resource "aws_cloudwatch_dashboard" "bc_testing" {
  dashboard_name = "BC-Testing-${local.project_id}"

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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.orchestrator.function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "BC Testing Lambda Metrics"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/SSM", "ExecutionSuccess", "DocumentName", aws_ssm_document.backup_validation.name],
            [".", "ExecutionFailed", ".", "."],
            [".", "ExecutionSuccess", "DocumentName", aws_ssm_document.database_recovery.name],
            [".", "ExecutionFailed", ".", "."],
            [".", "ExecutionSuccess", "DocumentName", aws_ssm_document.application_failover.name],
            [".", "ExecutionFailed", ".", "."]
          ]
          period = 86400
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "BC Testing Success/Failure Rates"
          view   = "number"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          query  = "SOURCE '/aws/lambda/${aws_lambda_function.orchestrator.function_name}' | fields @timestamp, @message | filter @message like /Test/ | sort @timestamp desc | limit 20"
          region = data.aws_region.current.name
          title  = "Recent BC Test Executions"
          view   = "table"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "BC-Testing-${local.project_id}"
    Description = "CloudWatch dashboard for business continuity testing monitoring"
  })
}