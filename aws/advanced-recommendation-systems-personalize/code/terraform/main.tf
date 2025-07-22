# =============================================================================
# Amazon Personalize Comprehensive Recommendation System
# =============================================================================

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  resource_suffix = random_id.suffix.hex
  account_id      = data.aws_caller_identity.current.account_id
  region          = data.aws_region.current.name
  
  # Resource naming
  bucket_name        = "${var.s3_bucket_prefix}-${local.resource_suffix}"
  dataset_group_name = "${var.dataset_group_name}-${local.resource_suffix}"
  
  solution_names = {
    for k, v in var.solution_names : k => "${v}-${local.resource_suffix}"
  }
  
  campaign_names = {
    for k, v in local.solution_names : k => "${v}-campaign"
  }
  
  filter_names = {
    exclude_purchased = "exclude-purchased-${local.resource_suffix}"
    category_filter   = "category-filter-${local.resource_suffix}"
    price_filter      = "price-filter-${local.resource_suffix}"
  }
}

# =============================================================================
# S3 Storage for Training Data and Batch Output
# =============================================================================

# KMS key for S3 encryption
resource "aws_kms_key" "s3_key" {
  count = var.enable_kms_encryption ? 1 : 0
  
  description             = "KMS key for Personalize S3 bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  
  tags = merge(var.common_tags, {
    Name = "${var.project_name}-s3-kms-key"
  })
}

resource "aws_kms_alias" "s3_key_alias" {
  count = var.enable_kms_encryption ? 1 : 0
  
  name          = "alias/${var.project_name}-s3-${local.resource_suffix}"
  target_key_id = aws_kms_key.s3_key[0].key_id
}

# S3 bucket for storing training data and batch output
resource "aws_s3_bucket" "personalize_data" {
  bucket = local.bucket_name
  
  tags = merge(var.common_tags, {
    Name        = local.bucket_name
    Purpose     = "PersonalizeDataStorage"
    Environment = var.environment
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "personalize_data_versioning" {
  bucket = aws_s3_bucket.personalize_data.id
  
  versioning_configuration {
    status = var.enable_s3_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "personalize_data_encryption" {
  bucket = aws_s3_bucket.personalize_data.id
  
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.s3_key[0].arn : null
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
    }
    bucket_key_enabled = var.enable_kms_encryption
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "personalize_data_pab" {
  bucket = aws_s3_bucket.personalize_data.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "personalize_data_lifecycle" {
  count = var.enable_cost_optimization ? 1 : 0
  
  bucket = aws_s3_bucket.personalize_data.id
  
  rule {
    id     = "transition_to_ia"
    status = "Enabled"
    
    transition {
      days          = var.s3_lifecycle_days
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = var.s3_lifecycle_days * 3
      storage_class = "GLACIER"
    }
    
    expiration {
      days = var.s3_lifecycle_days * 12
    }
  }
}

# Create S3 object structure
resource "aws_s3_object" "training_data_folder" {
  bucket = aws_s3_bucket.personalize_data.id
  key    = "training-data/"
  source = "/dev/null"
  
  tags = var.common_tags
}

resource "aws_s3_object" "batch_output_folder" {
  bucket = aws_s3_bucket.personalize_data.id
  key    = "batch-output/"
  source = "/dev/null"
  
  tags = var.common_tags
}

resource "aws_s3_object" "metadata_folder" {
  bucket = aws_s3_bucket.personalize_data.id
  key    = "metadata/"
  source = "/dev/null"
  
  tags = var.common_tags
}

resource "aws_s3_object" "batch_input_folder" {
  bucket = aws_s3_bucket.personalize_data.id
  key    = "batch-input/"
  source = "/dev/null"
  
  tags = var.common_tags
}

# =============================================================================
# IAM Roles and Policies
# =============================================================================

# IAM role for Amazon Personalize service
resource "aws_iam_role" "personalize_service_role" {
  name = "PersonalizeServiceRole-${local.resource_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "personalize.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(var.common_tags, {
    Name = "PersonalizeServiceRole-${local.resource_suffix}"
  })
}

# IAM policy for Personalize S3 access
resource "aws_iam_policy" "personalize_s3_policy" {
  name        = "PersonalizeS3Access-${local.resource_suffix}"
  description = "Policy for Personalize to access S3 bucket"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.personalize_data.arn,
          "${aws_s3_bucket.personalize_data.arn}/*"
        ]
      }
    ]
  })
  
  tags = var.common_tags
}

# Attach S3 policy to Personalize role
resource "aws_iam_role_policy_attachment" "personalize_s3_attachment" {
  role       = aws_iam_role.personalize_service_role.name
  policy_arn = aws_iam_policy.personalize_s3_policy.arn
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_execution_role" {
  name = "LambdaRecommendationRole-${local.resource_suffix}"
  
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
  
  tags = merge(var.common_tags, {
    Name = "LambdaRecommendationRole-${local.resource_suffix}"
  })
}

# IAM policy for Lambda Personalize access
resource "aws_iam_policy" "lambda_personalize_policy" {
  name        = "LambdaPersonalizePolicy-${local.resource_suffix}"
  description = "Policy for Lambda to access Personalize and CloudWatch"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "personalize:GetRecommendations",
          "personalize:GetPersonalizedRanking",
          "personalize:DescribeCampaign",
          "personalize:DescribeFilter",
          "personalize:CreateSolutionVersion",
          "personalize:DescribeSolution",
          "personalize:DescribeSolutionVersion"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = var.common_tags
}

# Attach policies to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_personalize_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_personalize_policy.arn
}

# =============================================================================
# Sample Data Generation (Optional)
# =============================================================================

# Lambda function for sample data generation
resource "aws_lambda_function" "data_generator" {
  count = var.generate_sample_data ? 1 : 0
  
  filename         = data.archive_file.data_generator_zip[0].output_path
  function_name    = "personalize-data-generator-${local.resource_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "data_generator.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = 300
  memory_size     = 1024
  
  environment {
    variables = {
      BUCKET_NAME       = aws_s3_bucket.personalize_data.id
      NUM_USERS         = var.sample_data_config.num_users
      NUM_ITEMS         = var.sample_data_config.num_items
      NUM_INTERACTIONS  = var.sample_data_config.num_interactions
      CATEGORIES        = join(",", var.sample_data_config.categories)
    }
  }
  
  tags = merge(var.common_tags, {
    Name = "personalize-data-generator-${local.resource_suffix}"
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.data_generator_logs[0]
  ]
}

# IAM policy for data generator S3 access
resource "aws_iam_policy" "data_generator_s3_policy" {
  count = var.generate_sample_data ? 1 : 0
  
  name        = "DataGeneratorS3Policy-${local.resource_suffix}"
  description = "Policy for data generator Lambda to write to S3"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.personalize_data.arn}/*"
      }
    ]
  })
  
  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "data_generator_s3_attachment" {
  count = var.generate_sample_data ? 1 : 0
  
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.data_generator_s3_policy[0].arn
}

# Archive for data generator Lambda
data "archive_file" "data_generator_zip" {
  count = var.generate_sample_data ? 1 : 0
  
  type        = "zip"
  output_path = "${path.module}/data_generator.zip"
  
  source {
    content = templatefile("${path.module}/lambda_functions/data_generator.py", {
      bucket_name = aws_s3_bucket.personalize_data.id
    })
    filename = "data_generator.py"
  }
}

# CloudWatch log group for data generator
resource "aws_cloudwatch_log_group" "data_generator_logs" {
  count = var.generate_sample_data ? 1 : 0
  
  name              = "/aws/lambda/personalize-data-generator-${local.resource_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = merge(var.common_tags, {
    Name = "personalize-data-generator-logs"
  })
}

# Invoke data generator to create sample data
resource "aws_lambda_invocation" "generate_data" {
  count = var.generate_sample_data ? 1 : 0
  
  function_name = aws_lambda_function.data_generator[0].function_name
  
  input = jsonencode({
    action = "generate_all_datasets"
  })
  
  depends_on = [
    aws_lambda_function.data_generator[0],
    aws_s3_bucket.personalize_data
  ]
}

# =============================================================================
# Amazon Personalize Resources
# =============================================================================

# Dataset Group
resource "aws_personalize_dataset_group" "main" {
  name = local.dataset_group_name
  
  tags = merge(var.common_tags, {
    Name = local.dataset_group_name
  })
}

# Schemas for different dataset types
resource "aws_personalize_schema" "interactions" {
  name   = "interactions-schema-${local.resource_suffix}"
  domain = "ECOMMERCE"
  
  schema = jsonencode({
    type      = "record"
    name      = "Interactions"
    namespace = "com.amazonaws.personalize.schema"
    fields = [
      {
        name = "USER_ID"
        type = "string"
      },
      {
        name = "ITEM_ID"
        type = "string"
      },
      {
        name = "TIMESTAMP"
        type = "long"
      },
      {
        name = "EVENT_TYPE"
        type = "string"
      },
      {
        name = "EVENT_VALUE"
        type = "float"
      }
    ]
    version = "1.0"
  })
  
  tags = merge(var.common_tags, {
    Name = "interactions-schema-${local.resource_suffix}"
  })
}

resource "aws_personalize_schema" "items" {
  name   = "items-schema-${local.resource_suffix}"
  domain = "ECOMMERCE"
  
  schema = jsonencode({
    type      = "record"
    name      = "Items"
    namespace = "com.amazonaws.personalize.schema"
    fields = [
      {
        name = "ITEM_ID"
        type = "string"
      },
      {
        name        = "CATEGORY"
        type        = "string"
        categorical = true
      },
      {
        name = "PRICE"
        type = "float"
      },
      {
        name        = "BRAND"
        type        = "string"
        categorical = true
      },
      {
        name = "CREATION_TIMESTAMP"
        type = "long"
      }
    ]
    version = "1.0"
  })
  
  tags = merge(var.common_tags, {
    Name = "items-schema-${local.resource_suffix}"
  })
}

resource "aws_personalize_schema" "users" {
  name   = "users-schema-${local.resource_suffix}"
  domain = "ECOMMERCE"
  
  schema = jsonencode({
    type      = "record"
    name      = "Users"
    namespace = "com.amazonaws.personalize.schema"
    fields = [
      {
        name = "USER_ID"
        type = "string"
      },
      {
        name = "AGE"
        type = "int"
      },
      {
        name        = "GENDER"
        type        = "string"
        categorical = true
      },
      {
        name        = "MEMBERSHIP_TYPE"
        type        = "string"
        categorical = true
      }
    ]
    version = "1.0"
  })
  
  tags = merge(var.common_tags, {
    Name = "users-schema-${local.resource_suffix}"
  })
}

# Datasets
resource "aws_personalize_dataset" "interactions" {
  name           = "interactions-dataset-${local.resource_suffix}"
  dataset_group_arn = aws_personalize_dataset_group.main.arn
  dataset_type   = "Interactions"
  schema_arn     = aws_personalize_schema.interactions.arn
  
  tags = merge(var.common_tags, {
    Name = "interactions-dataset-${local.resource_suffix}"
  })
}

resource "aws_personalize_dataset" "items" {
  name           = "items-dataset-${local.resource_suffix}"
  dataset_group_arn = aws_personalize_dataset_group.main.arn
  dataset_type   = "Items"
  schema_arn     = aws_personalize_schema.items.arn
  
  tags = merge(var.common_tags, {
    Name = "items-dataset-${local.resource_suffix}"
  })
}

resource "aws_personalize_dataset" "users" {
  name           = "users-dataset-${local.resource_suffix}"
  dataset_group_arn = aws_personalize_dataset_group.main.arn
  dataset_type   = "Users"
  schema_arn     = aws_personalize_schema.users.arn
  
  tags = merge(var.common_tags, {
    Name = "users-dataset-${local.resource_suffix}"
  })
}

# Solutions (ML Models)
resource "aws_personalize_solution" "user_personalization" {
  name               = local.solution_names.user_personalization
  dataset_group_arn  = aws_personalize_dataset_group.main.arn
  recipe_arn         = "arn:aws:personalize:::recipe/aws-user-personalization"
  
  solution_config {
    algorithm_hyper_parameters = var.user_personalization_config
    
    feature_transformation_parameters = {
      max_hist_len = var.user_personalization_config.max_hist_len
    }
  }
  
  tags = merge(var.common_tags, {
    Name = local.solution_names.user_personalization
    Type = "UserPersonalization"
  })
  
  depends_on = [aws_personalize_dataset.interactions]
}

resource "aws_personalize_solution" "similar_items" {
  name               = local.solution_names.similar_items
  dataset_group_arn  = aws_personalize_dataset_group.main.arn
  recipe_arn         = "arn:aws:personalize:::recipe/aws-similar-items"
  
  tags = merge(var.common_tags, {
    Name = local.solution_names.similar_items
    Type = "SimilarItems"
  })
  
  depends_on = [aws_personalize_dataset.interactions]
}

resource "aws_personalize_solution" "trending_now" {
  name               = local.solution_names.trending_now
  dataset_group_arn  = aws_personalize_dataset_group.main.arn
  recipe_arn         = "arn:aws:personalize:::recipe/aws-trending-now"
  
  tags = merge(var.common_tags, {
    Name = local.solution_names.trending_now
    Type = "TrendingNow"
  })
  
  depends_on = [aws_personalize_dataset.interactions]
}

resource "aws_personalize_solution" "popularity" {
  name               = local.solution_names.popularity
  dataset_group_arn  = aws_personalize_dataset_group.main.arn
  recipe_arn         = "arn:aws:personalize:::recipe/aws-popularity-count"
  
  tags = merge(var.common_tags, {
    Name = local.solution_names.popularity
    Type = "PopularityCount"
  })
  
  depends_on = [aws_personalize_dataset.interactions]
}

# =============================================================================
# Recommendation Filters
# =============================================================================

resource "aws_personalize_filter" "exclude_purchased" {
  name               = local.filter_names.exclude_purchased
  dataset_group_arn  = aws_personalize_dataset_group.main.arn
  filter_expression  = "EXCLUDE ItemID WHERE Interactions.EVENT_TYPE IN (\"purchase\")"
  
  tags = merge(var.common_tags, {
    Name = local.filter_names.exclude_purchased
    Type = "ExcludePurchased"
  })
  
  depends_on = [aws_personalize_dataset.interactions]
}

resource "aws_personalize_filter" "category_filter" {
  name               = local.filter_names.category_filter
  dataset_group_arn  = aws_personalize_dataset_group.main.arn
  filter_expression  = "INCLUDE ItemID WHERE Items.CATEGORY IN ($CATEGORY)"
  
  tags = merge(var.common_tags, {
    Name = local.filter_names.category_filter
    Type = "CategoryFilter"
  })
  
  depends_on = [aws_personalize_dataset.items]
}

resource "aws_personalize_filter" "price_filter" {
  name               = local.filter_names.price_filter
  dataset_group_arn  = aws_personalize_dataset_group.main.arn
  filter_expression  = "INCLUDE ItemID WHERE Items.PRICE >= $MIN_PRICE AND Items.PRICE <= $MAX_PRICE"
  
  tags = merge(var.common_tags, {
    Name = local.filter_names.price_filter
    Type = "PriceRangeFilter"
  })
  
  depends_on = [aws_personalize_dataset.items]
}

# =============================================================================
# Lambda Functions for Recommendation API
# =============================================================================

# Main recommendation service Lambda
resource "aws_lambda_function" "recommendation_service" {
  filename         = data.archive_file.recommendation_service_zip.output_path
  function_name    = "comprehensive-recommendation-api-${local.resource_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "recommendation_service.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  
  environment {
    variables = {
      USER_PERSONALIZATION_CAMPAIGN_ARN = "" # Will be populated after campaigns are created
      SIMILAR_ITEMS_CAMPAIGN_ARN        = ""
      TRENDING_NOW_CAMPAIGN_ARN         = ""
      POPULARITY_CAMPAIGN_ARN           = ""
      EXCLUDE_PURCHASED_FILTER_ARN      = aws_personalize_filter.exclude_purchased.arn
      CATEGORY_FILTER_ARN               = aws_personalize_filter.category_filter.arn
      PRICE_FILTER_ARN                  = aws_personalize_filter.price_filter.arn
      REGION                            = local.region
    }
  }
  
  tags = merge(var.common_tags, {
    Name = "comprehensive-recommendation-api-${local.resource_suffix}"
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_personalize_attachment,
    aws_cloudwatch_log_group.recommendation_service_logs
  ]
}

# Archive for recommendation service Lambda
data "archive_file" "recommendation_service_zip" {
  type        = "zip"
  output_path = "${path.module}/recommendation_service.zip"
  
  source {
    content  = file("${path.module}/lambda_functions/recommendation_service.py")
    filename = "recommendation_service.py"
  }
}

# CloudWatch log group for recommendation service
resource "aws_cloudwatch_log_group" "recommendation_service_logs" {
  name              = "/aws/lambda/comprehensive-recommendation-api-${local.resource_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = merge(var.common_tags, {
    Name = "recommendation-service-logs"
  })
}

# Automated retraining Lambda function
resource "aws_lambda_function" "retraining_automation" {
  count = var.enable_auto_retraining ? 1 : 0
  
  filename         = data.archive_file.retraining_automation_zip[0].output_path
  function_name    = "personalize-retraining-${local.resource_suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "retraining_automation.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = 300
  memory_size     = var.lambda_memory_size
  
  environment {
    variables = {
      USER_PERSONALIZATION_ARN = aws_personalize_solution.user_personalization.arn
      SIMILAR_ITEMS_ARN        = aws_personalize_solution.similar_items.arn
      TRENDING_NOW_ARN         = aws_personalize_solution.trending_now.arn
      POPULARITY_ARN           = aws_personalize_solution.popularity.arn
      REGION                   = local.region
    }
  }
  
  tags = merge(var.common_tags, {
    Name = "personalize-retraining-${local.resource_suffix}"
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_personalize_attachment,
    aws_cloudwatch_log_group.retraining_automation_logs[0]
  ]
}

# Archive for retraining automation Lambda
data "archive_file" "retraining_automation_zip" {
  count = var.enable_auto_retraining ? 1 : 0
  
  type        = "zip"
  output_path = "${path.module}/retraining_automation.zip"
  
  source {
    content  = file("${path.module}/lambda_functions/retraining_automation.py")
    filename = "retraining_automation.py"
  }
}

# CloudWatch log group for retraining automation
resource "aws_cloudwatch_log_group" "retraining_automation_logs" {
  count = var.enable_auto_retraining ? 1 : 0
  
  name              = "/aws/lambda/personalize-retraining-${local.resource_suffix}"
  retention_in_days = var.cloudwatch_log_retention_days
  
  tags = merge(var.common_tags, {
    Name = "retraining-automation-logs"
  })
}

# =============================================================================
# EventBridge for Automated Retraining
# =============================================================================

# EventBridge rule for scheduled retraining
resource "aws_cloudwatch_event_rule" "retraining_schedule" {
  count = var.enable_auto_retraining ? 1 : 0
  
  name                = "personalize-retraining-${local.resource_suffix}"
  description         = "Trigger Personalize model retraining"
  schedule_expression = var.retraining_schedule
  
  tags = merge(var.common_tags, {
    Name = "personalize-retraining-${local.resource_suffix}"
  })
}

# EventBridge target for retraining Lambda
resource "aws_cloudwatch_event_target" "retraining_target" {
  count = var.enable_auto_retraining ? 1 : 0
  
  rule      = aws_cloudwatch_event_rule.retraining_schedule[0].name
  target_id = "RetrainingLambdaTarget"
  arn       = aws_lambda_function.retraining_automation[0].arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  count = var.enable_auto_retraining ? 1 : 0
  
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.retraining_automation[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.retraining_schedule[0].arn
}

# =============================================================================
# CloudWatch Dashboards and Alarms
# =============================================================================

# CloudWatch dashboard for monitoring
resource "aws_cloudwatch_dashboard" "personalize_dashboard" {
  dashboard_name = "PersonalizeRecommendationSystem-${local.resource_suffix}"
  
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
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.recommendation_service.function_name],
            [".", "Errors", ".", "."],
            [".", "Invocations", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = local.region
          title  = "Recommendation API Performance"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["PersonalizeABTest", "RecommendationRequests", "Strategy", "user_personalization"],
            [".", ".", ".", "similar_items"],
            [".", ".", ".", "trending_now"],
            [".", ".", ".", "popularity"]
          ]
          period = 300
          stat   = "Sum"
          region = local.region
          title  = "A/B Test Distribution"
        }
      }
    ]
  })
  
  tags = merge(var.common_tags, {
    Name = "PersonalizeRecommendationSystem-${local.resource_suffix}"
  })
}

# CloudWatch alarm for high error rate
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  alarm_name          = "personalize-api-high-error-rate-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors recommendation API error rate"
  alarm_actions       = []
  
  dimensions = {
    FunctionName = aws_lambda_function.recommendation_service.function_name
  }
  
  tags = merge(var.common_tags, {
    Name = "personalize-api-high-error-rate-${local.resource_suffix}"
  })
}

# =============================================================================
# Optional API Gateway Integration
# =============================================================================

# API Gateway Rest API
resource "aws_api_gateway_rest_api" "recommendation_api" {
  count = var.enable_api_gateway ? 1 : 0
  
  name        = "personalize-recommendation-api-${local.resource_suffix}"
  description = "API Gateway for Personalize Recommendation System"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  tags = merge(var.common_tags, {
    Name = "personalize-recommendation-api-${local.resource_suffix}"
  })
}

# API Gateway resource for recommendations
resource "aws_api_gateway_resource" "recommendations" {
  count = var.enable_api_gateway ? 1 : 0
  
  rest_api_id = aws_api_gateway_rest_api.recommendation_api[0].id
  parent_id   = aws_api_gateway_rest_api.recommendation_api[0].root_resource_id
  path_part   = "recommendations"
}

# API Gateway method
resource "aws_api_gateway_method" "get_recommendations" {
  count = var.enable_api_gateway ? 1 : 0
  
  rest_api_id   = aws_api_gateway_rest_api.recommendation_api[0].id
  resource_id   = aws_api_gateway_resource.recommendations[0].id
  http_method   = "GET"
  authorization = "NONE"
}

# API Gateway integration
resource "aws_api_gateway_integration" "lambda_integration" {
  count = var.enable_api_gateway ? 1 : 0
  
  rest_api_id = aws_api_gateway_rest_api.recommendation_api[0].id
  resource_id = aws_api_gateway_resource.recommendations[0].id
  http_method = aws_api_gateway_method.get_recommendations[0].http_method
  
  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.recommendation_service.invoke_arn
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  count = var.enable_api_gateway ? 1 : 0
  
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.recommendation_service.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.recommendation_api[0].execution_arn}/*/*"
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "recommendation_deployment" {
  count = var.enable_api_gateway ? 1 : 0
  
  depends_on = [
    aws_api_gateway_method.get_recommendations[0],
    aws_api_gateway_integration.lambda_integration[0]
  ]
  
  rest_api_id = aws_api_gateway_rest_api.recommendation_api[0].id
  stage_name  = var.api_gateway_stage_name
  
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.recommendations[0].id,
      aws_api_gateway_method.get_recommendations[0].id,
      aws_api_gateway_integration.lambda_integration[0].id,
    ]))
  }
  
  lifecycle {
    create_before_destroy = true
  }
}