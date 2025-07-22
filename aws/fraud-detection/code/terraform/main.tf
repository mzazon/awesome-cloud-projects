# Data sources for AWS account information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = var.random_suffix_length
  special = false
  upper   = false
}

# Local values for consistent naming
locals {
  suffix = random_string.suffix.result
  
  # Resource names with random suffix
  bucket_name        = "${var.project_name}-data-${local.suffix}"
  entity_type_name   = "customer_${local.suffix}"
  event_type_name    = "payment_fraud_${local.suffix}"
  model_name         = "fraud_detection_model_${local.suffix}"
  detector_name      = "payment_fraud_detector_${local.suffix}"
  
  # Common tags
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Recipe      = "fraud-detection-systems-amazon-fraud-detector"
    },
    var.additional_tags
  )
}

# S3 bucket for storing training data
resource "aws_s3_bucket" "training_data" {
  bucket        = local.bucket_name
  force_destroy = true

  tags = merge(
    local.common_tags,
    {
      Name        = "${var.project_name}-training-data-bucket"
      Description = "S3 bucket for storing fraud detection training data"
    }
  )
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "training_data" {
  count  = var.training_data_bucket_versioning ? 1 : 0
  bucket = aws_s3_bucket.training_data.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "training_data" {
  count  = var.training_data_bucket_encryption ? 1 : 0
  bucket = aws_s3_bucket.training_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "training_data" {
  bucket = aws_s3_bucket.training_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "training_data" {
  count      = var.training_data_lifecycle_enabled ? 1 : 0
  depends_on = [aws_s3_bucket_versioning.training_data]
  bucket     = aws_s3_bucket.training_data.id

  rule {
    id     = "training_data_lifecycle"
    status = "Enabled"

    expiration {
      days = var.training_data_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# Sample training data object (optional)
resource "aws_s3_object" "sample_training_data" {
  count   = var.create_sample_data ? 1 : 0
  bucket  = aws_s3_bucket.training_data.bucket
  key     = var.sample_data_file_name
  content = <<EOF
event_timestamp,customer_id,email_address,ip_address,customer_name,phone_number,billing_address,billing_city,billing_state,billing_zip,shipping_address,shipping_city,shipping_state,shipping_zip,payment_method,card_bin,order_price,product_category,EVENT_LABEL
2024-01-15T10:30:00Z,cust001,john.doe@email.com,192.168.1.1,John Doe,555-1234,123 Main St,Seattle,WA,98101,123 Main St,Seattle,WA,98101,credit_card,411111,99.99,electronics,legit
2024-01-15T11:45:00Z,cust002,jane.smith@email.com,10.0.0.1,Jane Smith,555-5678,456 Oak Ave,Portland,OR,97201,456 Oak Ave,Portland,OR,97201,credit_card,424242,1299.99,electronics,legit
2024-01-15T12:15:00Z,cust003,fraud@temp.com,1.2.3.4,Test User,555-0000,789 Pine St,New York,NY,10001,999 Different St,Los Angeles,CA,90210,credit_card,444444,2500.00,jewelry,fraud
2024-01-15T13:30:00Z,cust004,alice.johnson@email.com,172.16.0.1,Alice Johnson,555-9876,321 Elm St,Chicago,IL,60601,321 Elm St,Chicago,IL,60601,debit_card,555555,45.99,books,legit
2024-01-15T14:45:00Z,cust005,bob.wilson@email.com,192.168.2.1,Bob Wilson,555-4321,654 Maple Dr,Denver,CO,80201,654 Maple Dr,Denver,CO,80201,credit_card,666666,150.00,clothing,legit
2024-01-15T15:00:00Z,cust006,suspicious@tempmail.com,5.6.7.8,Fake Name,555-1111,123 Fake St,Nowhere,XX,00000,456 Other St,Somewhere,YY,11111,credit_card,777777,5000.00,electronics,fraud
EOF
  
  content_type = "text/csv"
  
  tags = merge(
    local.common_tags,
    {
      Name        = "sample-training-data"
      Description = "Sample fraud detection training data"
    }
  )
}

# IAM role for Amazon Fraud Detector
resource "aws_iam_role" "fraud_detector_service_role" {
  name = "FraudDetectorServiceRole-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "frauddetector.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name        = "fraud-detector-service-role"
      Description = "IAM role for Amazon Fraud Detector service"
    }
  )
}

# IAM policy attachment for Fraud Detector
resource "aws_iam_role_policy_attachment" "fraud_detector_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonFraudDetectorFullAccessPolicy"
  role       = aws_iam_role.fraud_detector_service_role.name
}

# Custom IAM policy for S3 access
resource "aws_iam_role_policy" "fraud_detector_s3_access" {
  name = "FraudDetectorS3Access-${local.suffix}"
  role = aws_iam_role.fraud_detector_service_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.training_data.arn,
          "${aws_s3_bucket.training_data.arn}/*"
        ]
      }
    ]
  })
}

# Entity type for customers
resource "aws_frauddetector_entity_type" "customer" {
  name        = local.entity_type_name
  description = var.entity_type_description

  tags = merge(
    local.common_tags,
    {
      Name        = "customer-entity-type"
      Description = "Customer entity type for fraud detection"
    }
  )
}

# Labels for fraud classification
resource "aws_frauddetector_label" "fraud" {
  name        = "fraud"
  description = "Fraudulent transaction label"

  tags = merge(
    local.common_tags,
    {
      Name        = "fraud-label"
      Description = "Label for fraudulent transactions"
    }
  )
}

resource "aws_frauddetector_label" "legit" {
  name        = "legit"
  description = "Legitimate transaction label"

  tags = merge(
    local.common_tags,
    {
      Name        = "legit-label"
      Description = "Label for legitimate transactions"
    }
  )
}

# Event variables definition
locals {
  event_variables = [
    {
      name         = "customer_id"
      data_type    = "STRING"
      data_source  = "EVENT"
      default_value = "unknown"
    },
    {
      name         = "email_address"
      data_type    = "STRING"
      data_source  = "EVENT"
      default_value = "unknown"
    },
    {
      name         = "ip_address"
      data_type    = "STRING"
      data_source  = "EVENT"
      default_value = "unknown"
    },
    {
      name         = "customer_name"
      data_type    = "STRING"
      data_source  = "EVENT"
      default_value = "unknown"
    },
    {
      name         = "phone_number"
      data_type    = "STRING"
      data_source  = "EVENT"
      default_value = "unknown"
    },
    {
      name         = "billing_address"
      data_type    = "STRING"
      data_source  = "EVENT"
      default_value = "unknown"
    },
    {
      name         = "billing_city"
      data_type    = "STRING"
      data_source  = "EVENT"
      default_value = "unknown"
    },
    {
      name         = "billing_state"
      data_type    = "STRING"
      data_source  = "EVENT"
      default_value = "unknown"
    },
    {
      name         = "billing_zip"
      data_type    = "STRING"
      data_source  = "EVENT"
      default_value = "unknown"
    },
    {
      name         = "payment_method"
      data_type    = "STRING"
      data_source  = "EVENT"
      default_value = "unknown"
    },
    {
      name         = "card_bin"
      data_type    = "STRING"
      data_source  = "EVENT"
      default_value = "unknown"
    },
    {
      name         = "order_price"
      data_type    = "FLOAT"
      data_source  = "EVENT"
      default_value = "0.0"
    },
    {
      name         = "product_category"
      data_type    = "STRING"
      data_source  = "EVENT"
      default_value = "unknown"
    }
  ]
}

# Event variables
resource "aws_frauddetector_variable" "event_variables" {
  count = length(local.event_variables)
  
  name          = local.event_variables[count.index].name
  data_type     = local.event_variables[count.index].data_type
  data_source   = local.event_variables[count.index].data_source
  default_value = local.event_variables[count.index].default_value
  description   = "Event variable: ${local.event_variables[count.index].name}"

  tags = merge(
    local.common_tags,
    {
      Name        = "event-variable-${local.event_variables[count.index].name}"
      Description = "Event variable for ${local.event_variables[count.index].name}"
    }
  )
}

# Event type for payment fraud detection
resource "aws_frauddetector_event_type" "payment_fraud" {
  name         = local.event_type_name
  description  = var.event_type_description
  entity_types = [aws_frauddetector_entity_type.customer.name]
  event_variables = [for v in aws_frauddetector_variable.event_variables : v.name]
  labels       = [
    aws_frauddetector_label.fraud.name,
    aws_frauddetector_label.legit.name
  ]
  
  event_ingestion = var.event_ingestion

  tags = merge(
    local.common_tags,
    {
      Name        = "payment-fraud-event-type"
      Description = "Event type for payment fraud detection"
    }
  )
  
  depends_on = [
    aws_frauddetector_entity_type.customer,
    aws_frauddetector_variable.event_variables,
    aws_frauddetector_label.fraud,
    aws_frauddetector_label.legit
  ]
}

# Model for fraud detection (Note: This will trigger training)
resource "aws_frauddetector_model" "fraud_detection_model" {
  model_id    = local.model_name
  model_type  = var.model_type
  description = "Machine learning model for fraud detection"
  event_type  = aws_frauddetector_event_type.payment_fraud.name

  training_data_source {
    data_location        = var.create_sample_data ? "s3://${aws_s3_bucket.training_data.bucket}/${var.sample_data_file_name}" : "s3://${aws_s3_bucket.training_data.bucket}/training-data.csv"
    data_access_role_arn = aws_iam_role.fraud_detector_service_role.arn
  }

  training_data_schema {
    model_variables = [for v in aws_frauddetector_variable.event_variables : v.name]
    
    label_schema {
      label_mapper = {
        "FRAUD" = [aws_frauddetector_label.fraud.name]
        "LEGIT" = [aws_frauddetector_label.legit.name]
      }
      unlabeled_events_treatment = "IGNORE"
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name        = "fraud-detection-model"
      Description = "ML model for fraud detection"
    }
  )

  depends_on = [
    aws_frauddetector_event_type.payment_fraud,
    aws_s3_object.sample_training_data,
    aws_iam_role_policy_attachment.fraud_detector_policy,
    aws_iam_role_policy.fraud_detector_s3_access
  ]
}

# Outcomes for fraud detection decisions
resource "aws_frauddetector_outcome" "review" {
  name        = "review"
  description = "Send transaction for manual review"

  tags = merge(
    local.common_tags,
    {
      Name        = "review-outcome"
      Description = "Outcome for transactions requiring review"
    }
  )
}

resource "aws_frauddetector_outcome" "block" {
  name        = "block"
  description = "Block fraudulent transaction"

  tags = merge(
    local.common_tags,
    {
      Name        = "block-outcome"
      Description = "Outcome for blocking transactions"
    }
  )
}

resource "aws_frauddetector_outcome" "approve" {
  name        = "approve"
  description = "Approve legitimate transaction"

  tags = merge(
    local.common_tags,
    {
      Name        = "approve-outcome"
      Description = "Outcome for approving transactions"
    }
  )
}

# Detector for orchestrating fraud detection
resource "aws_frauddetector_detector" "payment_fraud_detector" {
  detector_id = local.detector_name
  description = "Payment fraud detection system"
  event_type  = aws_frauddetector_event_type.payment_fraud.name

  tags = merge(
    local.common_tags,
    {
      Name        = "payment-fraud-detector"
      Description = "Main fraud detection system"
    }
  )

  depends_on = [aws_frauddetector_event_type.payment_fraud]
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name = "FraudProcessorLambdaRole-${local.suffix}"

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

  tags = merge(
    local.common_tags,
    {
      Name        = "lambda-execution-role"
      Description = "IAM role for fraud processor Lambda function"
    }
  )
}

# IAM policy attachment for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

# Custom IAM policy for Lambda to access Fraud Detector
resource "aws_iam_role_policy" "lambda_fraud_detector_access" {
  name = "LambdaFraudDetectorAccess-${local.suffix}"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "frauddetector:GetEventPrediction",
          "frauddetector:DescribeDetector",
          "frauddetector:DescribeModelVersions"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda function code archive
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/fraud-processor.zip"
  
  source {
    content = <<EOF
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

frauddetector = boto3.client('frauddetector')

def lambda_handler(event, context):
    try:
        # Extract transaction data from event
        transaction_data = event.get('transaction', {})
        
        # Prepare variables for fraud detection
        variables = {
            'customer_id': transaction_data.get('customer_id', 'unknown'),
            'email_address': transaction_data.get('email_address', 'unknown'),
            'ip_address': transaction_data.get('ip_address', 'unknown'),
            'customer_name': transaction_data.get('customer_name', 'unknown'),
            'phone_number': transaction_data.get('phone_number', 'unknown'),
            'billing_address': transaction_data.get('billing_address', 'unknown'),
            'billing_city': transaction_data.get('billing_city', 'unknown'),
            'billing_state': transaction_data.get('billing_state', 'unknown'),
            'billing_zip': transaction_data.get('billing_zip', 'unknown'),
            'payment_method': transaction_data.get('payment_method', 'unknown'),
            'card_bin': transaction_data.get('card_bin', 'unknown'),
            'order_price': str(transaction_data.get('order_price', 0.0)),
            'product_category': transaction_data.get('product_category', 'unknown')
        }
        
        # Get fraud prediction
        response = frauddetector.get_event_prediction(
            detectorId=event['detector_id'],
            eventId=f"txn_{datetime.now().strftime('%Y%m%d_%H%M%S')}",
            eventTypeName=event['event_type_name'],
            entities=[{
                'entityType': event['entity_type_name'],
                'entityId': variables['customer_id']
            }],
            eventTimestamp=datetime.now().isoformat(),
            eventVariables=variables
        )
        
        # Process results
        prediction_result = {
            'transaction_id': event.get('transaction_id'),
            'customer_id': variables['customer_id'],
            'timestamp': datetime.now().isoformat(),
            'fraud_prediction': response
        }
        
        # Extract outcomes and scores
        outcomes = response.get('ruleResults', [])
        model_scores = response.get('modelScores', [])
        
        # Log prediction results
        logger.info(f"Fraud prediction completed for transaction: {event.get('transaction_id')}")
        logger.info(f"Outcomes: {outcomes}")
        logger.info(f"Model scores: {model_scores}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(prediction_result)
        }
        
    except Exception as e:
        logger.error(f"Error processing fraud prediction: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'transaction_id': event.get('transaction_id')
            })
        }
EOF
    filename = "fraud-processor.py"
  }
}

# Lambda function for processing fraud predictions
resource "aws_lambda_function" "fraud_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "fraud-prediction-processor-${local.suffix}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "fraud-processor.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DETECTOR_ID     = local.detector_name
      EVENT_TYPE_NAME = local.event_type_name
      ENTITY_TYPE_NAME = local.entity_type_name
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name        = "fraud-prediction-processor"
      Description = "Lambda function for processing fraud predictions"
    }
  )

  depends_on = [
    aws_frauddetector_detector.payment_fraud_detector,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_fraud_detector_access
  ]
}