#===============================================================================
# DATA SOURCES
#===============================================================================

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  
  # Resource naming with random suffix for uniqueness
  name_prefix = "${var.project_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # S3 bucket names (globally unique)
  raw_data_bucket       = "${local.name_prefix}-raw-data-${local.name_suffix}"
  processed_data_bucket = "${local.name_prefix}-processed-data-${local.name_suffix}"
  reports_bucket        = "${local.name_prefix}-reports-${local.name_suffix}"
  analytics_bucket      = "${local.name_prefix}-analytics-${local.name_suffix}"
  
  # Common tags
  common_tags = merge(
    var.additional_tags,
    {
      Name        = local.name_prefix
      Environment = var.environment
      Project     = var.project_name
      Department  = var.cost_allocation_tags.department
      ManagedBy   = "Terraform"
    }
  )
}

#===============================================================================
# KMS KEY FOR ENCRYPTION
#===============================================================================

resource "aws_kms_key" "financial_analytics" {
  count = var.enable_bucket_encryption ? 1 : 0
  
  description             = "KMS key for financial analytics data encryption"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Lambda Access"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_analytics.arn
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:ReEncrypt*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kms-key"
  })
}

resource "aws_kms_alias" "financial_analytics" {
  count = var.enable_bucket_encryption ? 1 : 0
  
  name          = "alias/${local.name_prefix}-financial-analytics"
  target_key_id = aws_kms_key.financial_analytics[0].key_id
}

#===============================================================================
# S3 BUCKETS FOR DATA STORAGE
#===============================================================================

# Raw cost data storage bucket
resource "aws_s3_bucket" "raw_data" {
  bucket        = local.raw_data_bucket
  force_destroy = var.environment != "prod"

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-raw-data"
    DataType    = "RawCostData"
    Purpose     = "Store raw cost data from Cost Explorer API"
  })
}

# Processed data storage bucket
resource "aws_s3_bucket" "processed_data" {
  bucket        = local.processed_data_bucket
  force_destroy = var.environment != "prod"

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-processed-data"
    DataType    = "ProcessedCostData"
    Purpose     = "Store transformed and optimized cost data"
  })
}

# Reports storage bucket
resource "aws_s3_bucket" "reports" {
  bucket        = local.reports_bucket
  force_destroy = var.environment != "prod"

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-reports"
    DataType    = "FinancialReports"
    Purpose     = "Store generated financial reports and analytics"
  })
}

# Analytics bucket for Athena query results
resource "aws_s3_bucket" "analytics" {
  bucket        = local.analytics_bucket
  force_destroy = var.environment != "prod"

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-analytics"
    DataType    = "AthenaResults"
    Purpose     = "Store Athena query results and QuickSight data"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "buckets" {
  for_each = var.enable_s3_versioning ? toset([
    aws_s3_bucket.raw_data.id,
    aws_s3_bucket.processed_data.id,
    aws_s3_bucket.reports.id,
    aws_s3_bucket.analytics.id
  ]) : toset([])

  bucket = each.value
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "buckets" {
  for_each = var.enable_bucket_encryption ? toset([
    aws_s3_bucket.raw_data.id,
    aws_s3_bucket.processed_data.id,
    aws_s3_bucket.reports.id,
    aws_s3_bucket.analytics.id
  ]) : toset([])

  bucket = each.value

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.financial_analytics[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block (security best practice)
resource "aws_s3_bucket_public_access_block" "buckets" {
  for_each = toset([
    aws_s3_bucket.raw_data.id,
    aws_s3_bucket.processed_data.id,
    aws_s3_bucket.reports.id,
    aws_s3_bucket.analytics.id
  ])

  bucket = each.value

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 lifecycle policies for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "buckets" {
  count = var.enable_s3_lifecycle ? 4 : 0
  
  bucket = [
    aws_s3_bucket.raw_data.id,
    aws_s3_bucket.processed_data.id,
    aws_s3_bucket.reports.id,
    aws_s3_bucket.analytics.id
  ][count.index]

  rule {
    id     = "cost_optimization"
    status = "Enabled"

    transition {
      days          = var.s3_transition_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.s3_transition_glacier_days
      storage_class = "GLACIER"
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    # Delete old versions after 90 days
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

#===============================================================================
# IAM ROLES AND POLICIES
#===============================================================================

# Lambda execution role for financial analytics
resource "aws_iam_role" "lambda_analytics" {
  name = "${local.name_prefix}-lambda-analytics-role"

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

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-role"
  })
}

# Comprehensive IAM policy for financial analytics Lambda functions
resource "aws_iam_role_policy" "lambda_analytics" {
  name = "${local.name_prefix}-lambda-analytics-policy"
  role = aws_iam_role.lambda_analytics.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "ce:GetUsageReport",
          "ce:GetRightsizingRecommendation",
          "ce:GetReservationCoverage",
          "ce:GetReservationPurchaseRecommendation",
          "ce:GetReservationUtilization",
          "ce:GetSavingsPlansUtilization",
          "ce:GetDimensionValues",
          "ce:ListCostCategoryDefinitions"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "organizations:ListAccounts",
          "organizations:DescribeOrganization",
          "organizations:ListOrganizationalUnitsForParent",
          "organizations:ListParents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.raw_data.arn,
          "${aws_s3_bucket.raw_data.arn}/*",
          aws_s3_bucket.processed_data.arn,
          "${aws_s3_bucket.processed_data.arn}/*",
          aws_s3_bucket.reports.arn,
          "${aws_s3_bucket.reports.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:GetTable",
          "glue:GetDatabase",
          "glue:CreateDatabase",
          "glue:CreatePartition"
        ]
        Resource = [
          "arn:aws:glue:${local.region}:${local.account_id}:catalog",
          "arn:aws:glue:${local.region}:${local.account_id}:database/${var.glue_database_name}",
          "arn:aws:glue:${local.region}:${local.account_id}:table/${var.glue_database_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "quicksight:CreateDataSet",
          "quicksight:UpdateDataSet",
          "quicksight:DescribeDataSet",
          "quicksight:CreateAnalysis",
          "quicksight:UpdateAnalysis"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.enable_cost_alerts ? aws_sns_topic.cost_alerts[0].arn : "*"
      }
    ]
  })
}

# Attach AWS managed policy for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_analytics.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# KMS permissions for Lambda functions
resource "aws_iam_role_policy" "lambda_kms" {
  count = var.enable_bucket_encryption ? 1 : 0
  
  name = "${local.name_prefix}-lambda-kms-policy"
  role = aws_iam_role.lambda_analytics.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:ReEncrypt*"
        ]
        Resource = aws_kms_key.financial_analytics[0].arn
      }
    ]
  })
}

#===============================================================================
# LAMBDA FUNCTIONS
#===============================================================================

# Create Lambda function code archives
data "archive_file" "cost_collector" {
  type        = "zip"
  output_path = "${path.module}/cost_collector.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/cost_data_collector.py", {
      raw_data_bucket = aws_s3_bucket.raw_data.bucket
      lookback_days   = var.cost_data_lookback_days
      granularity     = var.cost_granularity
    })
    filename = "lambda_function.py"
  }
}

data "archive_file" "data_transformer" {
  type        = "zip"
  output_path = "${path.module}/data_transformer.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/data_transformer.py", {
      raw_data_bucket       = aws_s3_bucket.raw_data.bucket
      processed_data_bucket = aws_s3_bucket.processed_data.bucket
      glue_database_name    = var.glue_database_name
    })
    filename = "lambda_function.py"
  }
}

# Cost Data Collector Lambda Function
resource "aws_lambda_function" "cost_collector" {
  filename         = data.archive_file.cost_collector.output_path
  function_name    = "${local.name_prefix}-cost-collector"
  role            = aws_iam_role.lambda_analytics.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.cost_collector_timeout
  memory_size     = var.cost_collector_memory
  source_code_hash = data.archive_file.cost_collector.output_base64sha256

  environment {
    variables = {
      RAW_DATA_BUCKET = aws_s3_bucket.raw_data.bucket
      LOOKBACK_DAYS   = var.cost_data_lookback_days
      GRANULARITY     = var.cost_granularity
      LOG_LEVEL       = var.enable_enhanced_monitoring ? "INFO" : "WARNING"
    }
  }

  dynamic "dead_letter_config" {
    for_each = var.enable_cost_alerts ? [1] : []
    content {
      target_arn = aws_sns_topic.cost_alerts[0].arn
    }
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-cost-collector"
    Function    = "CostDataCollection"
    Schedule    = var.cost_collection_schedule
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.cost_collector,
  ]
}

# Data Transformer Lambda Function
resource "aws_lambda_function" "data_transformer" {
  filename         = data.archive_file.data_transformer.output_path
  function_name    = "${local.name_prefix}-data-transformer"
  role            = aws_iam_role.lambda_analytics.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.data_transformer_timeout
  memory_size     = var.data_transformer_memory
  source_code_hash = data.archive_file.data_transformer.output_base64sha256

  environment {
    variables = {
      RAW_DATA_BUCKET       = aws_s3_bucket.raw_data.bucket
      PROCESSED_DATA_BUCKET = aws_s3_bucket.processed_data.bucket
      GLUE_DATABASE_NAME    = var.glue_database_name
      LOG_LEVEL             = var.enable_enhanced_monitoring ? "INFO" : "WARNING"
    }
  }

  dynamic "dead_letter_config" {
    for_each = var.enable_cost_alerts ? [1] : []
    content {
      target_arn = aws_sns_topic.cost_alerts[0].arn
    }
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-data-transformer"
    Function    = "DataTransformation"
    Schedule    = var.data_transformation_schedule
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.data_transformer,
  ]
}

#===============================================================================
# CLOUDWATCH LOG GROUPS
#===============================================================================

resource "aws_cloudwatch_log_group" "cost_collector" {
  name              = "/aws/lambda/${local.name_prefix}-cost-collector"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cost-collector-logs"
  })
}

resource "aws_cloudwatch_log_group" "data_transformer" {
  name              = "/aws/lambda/${local.name_prefix}-data-transformer"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-data-transformer-logs"
  })
}

#===============================================================================
# EVENTBRIDGE SCHEDULES
#===============================================================================

# Daily cost data collection schedule
resource "aws_cloudwatch_event_rule" "daily_cost_collection" {
  count = var.enable_automated_scheduling ? 1 : 0
  
  name                = "${local.name_prefix}-daily-cost-collection"
  description         = "Daily collection of cost data for analytics"
  schedule_expression = var.cost_collection_schedule

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-daily-collection-rule"
  })
}

# Weekly data transformation schedule
resource "aws_cloudwatch_event_rule" "weekly_data_transformation" {
  count = var.enable_automated_scheduling ? 1 : 0
  
  name                = "${local.name_prefix}-weekly-data-transformation"
  description         = "Weekly transformation of cost data"
  schedule_expression = var.data_transformation_schedule

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-weekly-transformation-rule"
  })
}

# EventBridge targets for Lambda functions
resource "aws_cloudwatch_event_target" "cost_collection_target" {
  count = var.enable_automated_scheduling ? 1 : 0
  
  rule      = aws_cloudwatch_event_rule.daily_cost_collection[0].name
  target_id = "CostCollectorTarget"
  arn       = aws_lambda_function.cost_collector.arn

  input = jsonencode({
    source = "scheduled-daily"
  })
}

resource "aws_cloudwatch_event_target" "data_transformation_target" {
  count = var.enable_automated_scheduling ? 1 : 0
  
  rule      = aws_cloudwatch_event_rule.weekly_data_transformation[0].name
  target_id = "DataTransformerTarget"
  arn       = aws_lambda_function.data_transformer.arn

  input = jsonencode({
    source = "scheduled-weekly"
  })
}

# Lambda permissions for EventBridge
resource "aws_lambda_permission" "allow_eventbridge_cost_collector" {
  count = var.enable_automated_scheduling ? 1 : 0
  
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_collector.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_cost_collection[0].arn
}

resource "aws_lambda_permission" "allow_eventbridge_data_transformer" {
  count = var.enable_automated_scheduling ? 1 : 0
  
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_transformer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weekly_data_transformation[0].arn
}

#===============================================================================
# GLUE DATA CATALOG
#===============================================================================

# Glue database for financial analytics
resource "aws_glue_catalog_database" "financial_analytics" {
  name        = var.glue_database_name
  description = var.glue_database_description

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-glue-database"
  })
}

# Glue table for daily costs
resource "aws_glue_catalog_table" "daily_costs" {
  name          = "daily_costs"
  database_name = aws_glue_catalog_database.financial_analytics.name
  table_type    = "EXTERNAL_TABLE"
  description   = "Daily cost data from Cost Explorer API"

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.processed_data.bucket}/processed-data-parquet/daily_costs/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"
    }

    columns {
      name = "date"
      type = "string"
    }
    columns {
      name = "service"
      type = "string"
    }
    columns {
      name = "account_id"
      type = "string"
    }
    columns {
      name = "blended_cost"
      type = "double"
    }
    columns {
      name = "unblended_cost"
      type = "double"
    }
    columns {
      name = "usage_quantity"
      type = "double"
    }
    columns {
      name = "currency"
      type = "string"
    }
  }

  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
}

# Glue table for department costs
resource "aws_glue_catalog_table" "department_costs" {
  name          = "department_costs"
  database_name = aws_glue_catalog_database.financial_analytics.name
  table_type    = "EXTERNAL_TABLE"
  description   = "Department-level cost allocation data"

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.processed_data.bucket}/processed-data-parquet/department_costs/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"
    }

    columns {
      name = "month"
      type = "string"
    }
    columns {
      name = "department"
      type = "string"
    }
    columns {
      name = "project"
      type = "string"
    }
    columns {
      name = "environment"
      type = "string"
    }
    columns {
      name = "cost"
      type = "double"
    }
    columns {
      name = "currency"
      type = "string"
    }
  }
}

#===============================================================================
# ATHENA WORKGROUP
#===============================================================================

resource "aws_athena_workgroup" "financial_analytics" {
  name        = var.athena_workgroup_name
  description = "Workgroup for financial analytics queries"
  state       = "ENABLED"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics         = var.enable_athena_cloudwatch_metrics
    bytes_scanned_cutoff_per_query     = var.athena_bytes_scanned_cutoff

    result_configuration {
      output_location = "s3://${aws_s3_bucket.analytics.bucket}/athena-results/"

      dynamic "encryption_configuration" {
        for_each = var.enable_bucket_encryption ? [1] : []
        content {
          encryption_option = "SSE_KMS"
          kms_key           = aws_kms_key.financial_analytics[0].arn
        }
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-athena-workgroup"
  })
}

#===============================================================================
# QUICKSIGHT RESOURCES
#===============================================================================

# Get current QuickSight user
data "aws_quicksight_user" "current" {
  count = var.enable_quicksight_resources ? 1 : 0
  
  user_name     = "admin/${local.account_id}"
  aws_account_id = local.account_id
  namespace     = var.quicksight_namespace
}

# QuickSight data source for S3
resource "aws_quicksight_data_source" "s3_financial_data" {
  count = var.enable_quicksight_resources ? 1 : 0
  
  aws_account_id = local.account_id
  data_source_id = "financial-analytics-s3"
  name           = "Financial Analytics S3 Data"
  type           = "S3"

  parameters {
    s3 {
      manifest_file_location {
        bucket = aws_s3_bucket.processed_data.bucket
        key    = "quicksight-manifest.json"
      }
    }
  }

  permission {
    principal = data.aws_quicksight_user.current[0].arn
    actions = [
      "quicksight:DescribeDataSource",
      "quicksight:DescribeDataSourcePermissions",
      "quicksight:PassDataSource",
      "quicksight:UpdateDataSource",
      "quicksight:DeleteDataSource",
      "quicksight:UpdateDataSourcePermissions"
    ]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-quicksight-s3-datasource"
  })
}

# QuickSight data source for Athena
resource "aws_quicksight_data_source" "athena_financial_data" {
  count = var.enable_quicksight_resources ? 1 : 0
  
  aws_account_id = local.account_id
  data_source_id = "financial-analytics-athena"
  name           = "Financial Analytics Athena"
  type           = "ATHENA"

  parameters {
    athena {
      work_group = aws_athena_workgroup.financial_analytics.name
    }
  }

  permission {
    principal = data.aws_quicksight_user.current[0].arn
    actions = [
      "quicksight:DescribeDataSource",
      "quicksight:DescribeDataSourcePermissions",
      "quicksight:PassDataSource",
      "quicksight:UpdateDataSource",
      "quicksight:DeleteDataSource",
      "quicksight:UpdateDataSourcePermissions"
    ]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-quicksight-athena-datasource"
  })
}

# Create manifest file for QuickSight S3 data source
resource "aws_s3_object" "quicksight_manifest" {
  count = var.enable_quicksight_resources ? 1 : 0
  
  bucket  = aws_s3_bucket.processed_data.bucket
  key     = "quicksight-manifest.json"
  content_type = "application/json"

  content = jsonencode({
    fileLocations = [
      {
        URIs = [
          "s3://${aws_s3_bucket.processed_data.bucket}/processed-data/daily_costs/",
          "s3://${aws_s3_bucket.processed_data.bucket}/processed-data/department_costs/",
          "s3://${aws_s3_bucket.processed_data.bucket}/processed-data/ri_utilization/"
        ]
      }
    ]
    globalUploadSettings = {
      format = "JSON"
    }
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-quicksight-manifest"
  })
}

#===============================================================================
# SNS TOPIC FOR ALERTS (OPTIONAL)
#===============================================================================

resource "aws_sns_topic" "cost_alerts" {
  count = var.enable_cost_alerts ? 1 : 0
  
  name              = "${local.name_prefix}-cost-alerts"
  kms_master_key_id = var.enable_bucket_encryption ? aws_kms_key.financial_analytics[0].arn : null

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cost-alerts"
  })
}

resource "aws_sns_topic_subscription" "email_alerts" {
  count = var.enable_cost_alerts && var.notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.cost_alerts[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

#===============================================================================
# CLOUDWATCH ALARMS FOR MONITORING
#===============================================================================

# Lambda function error rate alarms
resource "aws_cloudwatch_metric_alarm" "cost_collector_errors" {
  count = var.enable_enhanced_monitoring ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-cost-collector-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors cost collector lambda errors"
  alarm_actions       = var.enable_cost_alerts ? [aws_sns_topic.cost_alerts[0].arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.cost_collector.function_name
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "data_transformer_errors" {
  count = var.enable_enhanced_monitoring ? 1 : 0
  
  alarm_name          = "${local.name_prefix}-data-transformer-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors data transformer lambda errors"
  alarm_actions       = var.enable_cost_alerts ? [aws_sns_topic.cost_alerts[0].arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.data_transformer.function_name
  }

  tags = local.common_tags
}