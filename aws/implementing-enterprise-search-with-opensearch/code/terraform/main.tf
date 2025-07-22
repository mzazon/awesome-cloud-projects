# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get available availability zones if not specified
data "aws_availability_zones" "available" {
  state = "available"
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Use provided AZs or default to first 3 available
  availability_zones = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 3)
  
  # Common naming convention
  name_prefix = "${var.project_name}-${var.environment}-${random_id.suffix.hex}"
  
  # OpenSearch domain name (must be lowercase and follow naming rules)
  domain_name = replace(lower("${local.name_prefix}-domain"), "_", "-")
  
  # S3 bucket name (must be globally unique)
  s3_bucket_name = replace(lower("${local.name_prefix}-data"), "_", "-")
  
  # Lambda function name
  lambda_function_name = "${local.name_prefix}-indexer"
  
  # Common tags
  common_tags = merge(var.additional_tags, {
    Name        = local.name_prefix
    Environment = var.environment
    Project     = var.project_name
  })
}

# S3 bucket for sample data and indexing
resource "aws_s3_bucket" "opensearch_data" {
  bucket        = local.s3_bucket_name
  force_destroy = var.s3_force_destroy

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-data-bucket"
    Description = "S3 bucket for OpenSearch sample data and indexing"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "opensearch_data" {
  bucket = aws_s3_bucket.opensearch_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "opensearch_data" {
  bucket = aws_s3_bucket.opensearch_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "opensearch_data" {
  bucket = aws_s3_bucket.opensearch_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudWatch log groups for OpenSearch logging (conditional)
resource "aws_cloudwatch_log_group" "opensearch_index_slow_logs" {
  count             = var.enable_logging ? 1 : 0
  name              = "/aws/opensearch/domains/${local.domain_name}/index-slow-logs"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-index-slow-logs"
    Description = "OpenSearch index slow logs"
  })
}

resource "aws_cloudwatch_log_group" "opensearch_search_slow_logs" {
  count             = var.enable_logging ? 1 : 0
  name              = "/aws/opensearch/domains/${local.domain_name}/search-slow-logs"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-search-slow-logs"
    Description = "OpenSearch search slow logs"
  })
}

resource "aws_cloudwatch_log_group" "opensearch_application_logs" {
  count             = var.enable_logging ? 1 : 0
  name              = "/aws/opensearch/domains/${local.domain_name}/application-logs"
  retention_in_days = var.log_retention_days

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-application-logs"
    Description = "OpenSearch application logs"
  })
}

# CloudWatch log resource policy for OpenSearch
resource "aws_cloudwatch_log_resource_policy" "opensearch_logs" {
  count           = var.enable_logging ? 1 : 0
  policy_name     = "${local.name_prefix}-opensearch-logs-policy"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "opensearch.amazonaws.com"
        }
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
          "logs:CreateLogStream"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

# IAM role for OpenSearch Service
resource "aws_iam_role" "opensearch_service_role" {
  name = "${local.name_prefix}-opensearch-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "opensearch.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-opensearch-service-role"
    Description = "IAM role for OpenSearch Service"
  })
}

# OpenSearch Service Domain
resource "aws_opensearch_domain" "main" {
  domain_name    = local.domain_name
  engine_version = var.opensearch_version

  # Cluster configuration with dedicated masters and multi-AZ
  cluster_config {
    instance_type            = var.opensearch_instance_type
    instance_count           = var.opensearch_instance_count
    dedicated_master_enabled = true
    dedicated_master_type    = var.opensearch_master_instance_type
    dedicated_master_count   = var.opensearch_master_instance_count
    zone_awareness_enabled   = true

    zone_awareness_config {
      availability_zone_count = length(local.availability_zones)
    }

    # UltraWarm configuration (conditional)
    dynamic "warm_config" {
      for_each = var.enable_ultrawarm ? [1] : []
      content {
        warm_enabled                = true
        warm_type                  = var.ultrawarm_instance_type
        warm_count                 = var.ultrawarm_instance_count
      }
    }
  }

  # EBS storage configuration
  ebs_options {
    ebs_enabled = true
    volume_type = var.opensearch_ebs_volume_type
    volume_size = var.opensearch_ebs_volume_size
    iops        = var.opensearch_ebs_volume_type == "gp3" || var.opensearch_ebs_volume_type == "io1" || var.opensearch_ebs_volume_type == "io2" ? var.opensearch_ebs_iops : null
    throughput  = var.opensearch_ebs_volume_type == "gp3" ? var.opensearch_ebs_throughput : null
  }

  # Security configuration
  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  # Fine-grained access control
  advanced_security_options {
    enabled                        = true
    anonymous_auth_enabled         = false
    internal_user_database_enabled = true

    master_user_options {
      master_user_name     = var.opensearch_admin_username
      master_user_password = var.opensearch_admin_password
    }
  }

  # Access policy
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action   = "es:*"
        Resource = "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${local.domain_name}/*"
      }
    ]
  })

  # Log publishing options (conditional)
  dynamic "log_publishing_options" {
    for_each = var.enable_logging ? [
      {
        log_type                 = "INDEX_SLOW_LOGS"
        cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_index_slow_logs[0].arn
      },
      {
        log_type                 = "SEARCH_SLOW_LOGS"
        cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_search_slow_logs[0].arn
      },
      {
        log_type                 = "ES_APPLICATION_LOGS"
        cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch_application_logs[0].arn
      }
    ] : []

    content {
      log_type                 = log_publishing_options.value.log_type
      cloudwatch_log_group_arn = log_publishing_options.value.cloudwatch_log_group_arn
      enabled                  = true
    }
  }

  # Advanced options for performance optimization
  advanced_options = {
    "rest.action.multi.allow_explicit_index" = "true"
    "indices.fielddata.cache.size"           = "20%"
    "indices.query.bool.max_clause_count"    = "1024"
  }

  depends_on = [
    aws_cloudwatch_log_resource_policy.opensearch_logs
  ]

  tags = merge(local.common_tags, {
    Name        = local.domain_name
    Description = "OpenSearch domain for search solutions"
  })
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_opensearch_role" {
  name = "${local.name_prefix}-lambda-opensearch-role"

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

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-lambda-opensearch-role"
    Description = "IAM role for Lambda OpenSearch indexer"
  })
}

# IAM policy for Lambda to access S3 and OpenSearch
resource "aws_iam_role_policy" "lambda_opensearch_policy" {
  name = "${local.name_prefix}-lambda-opensearch-policy"
  role = aws_iam_role.lambda_opensearch_role.id

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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.opensearch_data.arn,
          "${aws_s3_bucket.opensearch_data.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "es:ESHttpPost",
          "es:ESHttpPut",
          "es:ESHttpGet"
        ]
        Resource = "${aws_opensearch_domain.main.arn}/*"
      }
    ]
  })
}

# Attach basic execution role policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_opensearch_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda function code archive
data "archive_file" "lambda_indexer" {
  type        = "zip"
  output_path = "${path.module}/lambda-indexer.zip"

  source {
    content = <<EOF
import json
import boto3
import urllib3
import base64
import os
from urllib.parse import urlparse, quote

def lambda_handler(event, context):
    """
    Lambda function to index data from S3 into OpenSearch
    """
    
    # OpenSearch endpoint from environment variable
    os_endpoint = os.environ['OPENSEARCH_ENDPOINT']
    
    # Initialize HTTP client
    http = urllib3.PoolManager()
    
    try:
        # Process S3 event (if triggered by S3)
        if 'Records' in event:
            s3_client = boto3.client('s3')
            
            for record in event['Records']:
                bucket = record['s3']['bucket']['name']
                key = record['s3']['object']['key']
                
                print(f"Processing file: s3://{bucket}/{key}")
                
                # Download file from S3
                try:
                    response = s3_client.get_object(Bucket=bucket, Key=key)
                    content = response['Body'].read().decode('utf-8')
                    
                    # Parse JSON data
                    data = json.loads(content)
                    
                    # Handle both single objects and arrays
                    if isinstance(data, dict):
                        products = [data]
                    elif isinstance(data, list):
                        products = data
                    else:
                        print(f"Unsupported data format in {key}")
                        continue
                    
                    # Index each product
                    for product in products:
                        if 'id' not in product:
                            print(f"Skipping product without id: {product}")
                            continue
                            
                        doc_id = product['id']
                        index_url = f"https://{os_endpoint}/products/_doc/{doc_id}"
                        
                        # Prepare request
                        headers = {
                            'Content-Type': 'application/json'
                        }
                        
                        response = http.request(
                            'PUT',
                            index_url,
                            headers=headers,
                            body=json.dumps(product)
                        )
                        
                        print(f"Indexed product {doc_id}: {response.status}")
                        
                        if response.status not in [200, 201]:
                            print(f"Error indexing {doc_id}: {response.data.decode('utf-8')}")
                
                except Exception as e:
                    print(f"Error processing {key}: {str(e)}")
                    continue
        
        # Manual invocation with direct data
        elif 'data' in event:
            data = event['data']
            
            # Handle both single objects and arrays
            if isinstance(data, dict):
                products = [data]
            elif isinstance(data, list):
                products = data
            else:
                return {
                    'statusCode': 400,
                    'body': json.dumps('Invalid data format')
                }
            
            # Index each product
            for product in products:
                if 'id' not in product:
                    print(f"Skipping product without id: {product}")
                    continue
                    
                doc_id = product['id']
                index_url = f"https://{os_endpoint}/products/_doc/{doc_id}"
                
                # Prepare request
                headers = {
                    'Content-Type': 'application/json'
                }
                
                response = http.request(
                    'PUT',
                    index_url,
                    headers=headers,
                    body=json.dumps(product)
                )
                
                print(f"Indexed product {doc_id}: {response.status}")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Data indexing completed successfully')
        }
        
    except Exception as e:
        print(f"Error in lambda_handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
EOF
    filename = "lambda_function.py"
  }
}

# Lambda function for OpenSearch indexing
resource "aws_lambda_function" "opensearch_indexer" {
  filename         = data.archive_file.lambda_indexer.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_opensearch_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_indexer.output_base64sha256

  environment {
    variables = {
      OPENSEARCH_ENDPOINT = aws_opensearch_domain.main.endpoint
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_opensearch_policy,
  ]

  tags = merge(local.common_tags, {
    Name        = local.lambda_function_name
    Description = "Lambda function for automated OpenSearch indexing"
  })
}

# S3 bucket notification to trigger Lambda
resource "aws_s3_bucket_notification" "opensearch_data_notification" {
  bucket = aws_s3_bucket.opensearch_data.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.opensearch_indexer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".json"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# Lambda permission for S3 to invoke the function
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.opensearch_indexer.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.opensearch_data.arn
}

# CloudWatch Dashboard for OpenSearch monitoring (conditional)
resource "aws_cloudwatch_dashboard" "opensearch_dashboard" {
  count          = var.enable_monitoring ? 1 : 0
  dashboard_name = "${local.name_prefix}-opensearch-dashboard"

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
            ["AWS/ES", "SearchLatency", "DomainName", local.domain_name, "ClientId", data.aws_caller_identity.current.account_id],
            [".", "IndexingLatency", ".", ".", ".", "."],
            [".", "SearchRate", ".", ".", ".", "."],
            [".", "IndexingRate", ".", ".", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "OpenSearch Performance Metrics"
          view   = "timeSeries"
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
            ["AWS/ES", "ClusterStatus.yellow", "DomainName", local.domain_name, "ClientId", data.aws_caller_identity.current.account_id],
            [".", "ClusterStatus.red", ".", ".", ".", "."],
            [".", "StorageUtilization", ".", ".", ".", "."],
            [".", "CPUUtilization", ".", ".", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "OpenSearch Cluster Health"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["AWS/ES", "JVMMemoryPressure", "DomainName", local.domain_name, "ClientId", data.aws_caller_identity.current.account_id],
            [".", "MasterJVMMemoryPressure", ".", ".", ".", "."],
            [".", "AutomatedSnapshotFailure", ".", ".", ".", "."],
            [".", "KibanaHealthyNodes", ".", ".", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "OpenSearch Advanced Metrics"
          view   = "timeSeries"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-opensearch-dashboard"
    Description = "CloudWatch dashboard for OpenSearch monitoring"
  })
}

# CloudWatch Alarms for OpenSearch monitoring (conditional)
resource "aws_cloudwatch_metric_alarm" "opensearch_high_search_latency" {
  count               = var.enable_monitoring ? 1 : 0
  alarm_name          = "${local.name_prefix}-opensearch-high-search-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "SearchLatency"
  namespace           = "AWS/ES"
  period              = "300"
  statistic           = "Average"
  threshold           = "1000"
  alarm_description   = "This metric monitors OpenSearch search latency"
  alarm_actions       = []

  dimensions = {
    DomainName = local.domain_name
    ClientId   = data.aws_caller_identity.current.account_id
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-high-search-latency-alarm"
    Description = "CloudWatch alarm for high OpenSearch search latency"
  })
}

resource "aws_cloudwatch_metric_alarm" "opensearch_cluster_red" {
  count               = var.enable_monitoring ? 1 : 0
  alarm_name          = "${local.name_prefix}-opensearch-cluster-red"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "ClusterStatus.red"
  namespace           = "AWS/ES"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "1"
  alarm_description   = "This metric monitors OpenSearch cluster red status"
  alarm_actions       = []

  dimensions = {
    DomainName = local.domain_name
    ClientId   = data.aws_caller_identity.current.account_id
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-cluster-red-alarm"
    Description = "CloudWatch alarm for OpenSearch cluster red status"
  })
}

resource "aws_cloudwatch_metric_alarm" "opensearch_high_cpu" {
  count               = var.enable_monitoring ? 1 : 0
  alarm_name          = "${local.name_prefix}-opensearch-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ES"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors OpenSearch CPU utilization"
  alarm_actions       = []

  dimensions = {
    DomainName = local.domain_name
    ClientId   = data.aws_caller_identity.current.account_id
  }

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-high-cpu-alarm"
    Description = "CloudWatch alarm for high OpenSearch CPU utilization"
  })
}

# Sample data file for testing
resource "aws_s3_object" "sample_products" {
  bucket = aws_s3_bucket.opensearch_data.id
  key    = "sample-products.json"
  content = jsonencode([
    {
      id          = "prod-001"
      title       = "Wireless Bluetooth Headphones"
      description = "High-quality wireless headphones with noise cancellation and 30-hour battery life"
      category    = "Electronics"
      brand       = "TechSound"
      price       = 199.99
      rating      = 4.5
      tags        = ["wireless", "bluetooth", "noise-cancelling", "headphones"]
      stock       = 150
      created_date = "2024-01-15"
    },
    {
      id          = "prod-002"
      title       = "Organic Cotton T-Shirt"
      description = "Comfortable organic cotton t-shirt available in multiple colors and sizes"
      category    = "Clothing"
      brand       = "EcoWear"
      price       = 29.99
      rating      = 4.2
      tags        = ["organic", "cotton", "t-shirt", "eco-friendly"]
      stock       = 75
      created_date = "2024-01-10"
    },
    {
      id          = "prod-003"
      title       = "Smart Fitness Watch"
      description = "Advanced fitness tracking watch with heart rate monitor and GPS"
      category    = "Electronics"
      brand       = "FitTech"
      price       = 299.99
      rating      = 4.7
      tags        = ["smartwatch", "fitness", "GPS", "heart-rate"]
      stock       = 89
      created_date = "2024-01-12"
    },
    {
      id          = "prod-004"
      title       = "Ergonomic Office Chair"
      description = "Comfortable ergonomic office chair with lumbar support and adjustable height"
      category    = "Furniture"
      brand       = "OfficeComfort"
      price       = 449.99
      rating      = 4.3
      tags        = ["chair", "office", "ergonomic", "lumbar-support"]
      stock       = 32
      created_date = "2024-01-08"
    },
    {
      id          = "prod-005"
      title       = "Stainless Steel Water Bottle"
      description = "Insulated stainless steel water bottle keeps drinks cold for 24 hours"
      category    = "Home & Kitchen"
      brand       = "HydroSteel"
      price       = 34.99
      rating      = 4.6
      tags        = ["water-bottle", "stainless-steel", "insulated", "eco-friendly"]
      stock       = 200
      created_date = "2024-01-05"
    }
  ])

  tags = merge(local.common_tags, {
    Name        = "${local.name_prefix}-sample-products"
    Description = "Sample product data for OpenSearch indexing"
  })
}