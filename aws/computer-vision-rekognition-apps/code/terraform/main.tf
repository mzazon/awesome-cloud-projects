# main.tf - Main Terraform configuration for computer vision application

# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

locals {
  # Common name prefix with environment and random suffix
  name_prefix = "${var.project_name}-${var.environment}-${random_string.suffix.result}"
  
  # Full resource names
  s3_bucket_name                = "${var.s3_bucket_name_prefix}-${random_string.suffix.result}"
  face_collection_name          = "${var.face_collection_name_prefix}-${random_string.suffix.result}"
  kinesis_video_stream_name     = "${var.kinesis_video_stream_name_prefix}-${random_string.suffix.result}"
  kinesis_data_stream_name      = "${var.kinesis_data_stream_name_prefix}-${random_string.suffix.result}"
  rekognition_role_name         = "RekognitionVideoAnalysisRole-${random_string.suffix.result}"
  stream_processor_name         = "face-search-processor-${random_string.suffix.result}"

  # Common tags
  common_tags = merge({
    Project     = "Computer Vision Application"
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "Terraform"
  }, var.additional_tags)
}

#####################################
# S3 Bucket for Image and Video Storage
#####################################

resource "aws_s3_bucket" "computer_vision" {
  bucket        = local.s3_bucket_name
  force_destroy = true # For demo purposes - remove in production

  tags = merge(local.common_tags, {
    Name        = local.s3_bucket_name
    Purpose     = "Computer vision media storage"
    ContentType = "Images and Videos"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "computer_vision" {
  count  = var.enable_s3_versioning ? 1 : 0
  bucket = aws_s3_bucket.computer_vision.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "computer_vision" {
  count  = var.enable_s3_encryption ? 1 : 0
  bucket = aws_s3_bucket.computer_vision.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "computer_vision" {
  bucket = aws_s3_bucket.computer_vision.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "computer_vision" {
  bucket = aws_s3_bucket.computer_vision.id

  rule {
    id     = "intelligent_tiering"
    status = "Enabled"

    filter {
      prefix = "images/"
    }

    transition {
      days          = var.s3_lifecycle_transition_days
      storage_class = "INTELLIGENT_TIERING"
    }
  }

  rule {
    id     = "video_lifecycle"
    status = "Enabled"

    filter {
      prefix = "videos/"
    }

    transition {
      days          = var.s3_lifecycle_transition_days
      storage_class = "INTELLIGENT_TIERING"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }

  rule {
    id     = "results_cleanup"
    status = "Enabled"

    filter {
      prefix = "results/"
    }

    expiration {
      days = 365 # Keep analysis results for 1 year
    }
  }
}

# S3 bucket folders (objects with trailing slash)
resource "aws_s3_object" "images_folder" {
  bucket  = aws_s3_bucket.computer_vision.id
  key     = "images/"
  content = ""

  tags = merge(local.common_tags, {
    Name    = "Images Folder"
    Purpose = "Image uploads storage"
  })
}

resource "aws_s3_object" "videos_folder" {
  bucket  = aws_s3_bucket.computer_vision.id
  key     = "videos/"
  content = ""

  tags = merge(local.common_tags, {
    Name    = "Videos Folder"
    Purpose = "Video uploads storage"
  })
}

resource "aws_s3_object" "results_folder" {
  bucket  = aws_s3_bucket.computer_vision.id
  key     = "results/"
  content = ""

  tags = merge(local.common_tags, {
    Name    = "Results Folder"
    Purpose = "Analysis results storage"
  })
}

#####################################
# IAM Role for Rekognition Services
#####################################

# Trust policy for Rekognition service
data "aws_iam_policy_document" "rekognition_trust_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["rekognition.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# IAM role for Rekognition video analysis
resource "aws_iam_role" "rekognition_video_analysis" {
  name               = local.rekognition_role_name
  assume_role_policy = data.aws_iam_policy_document.rekognition_trust_policy.json

  tags = merge(local.common_tags, {
    Name    = local.rekognition_role_name
    Purpose = "Rekognition video analysis service role"
  })
}

# Attach AWS managed policy for Rekognition service
resource "aws_iam_role_policy_attachment" "rekognition_service_role" {
  role       = aws_iam_role.rekognition_video_analysis.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRekognitionServiceRole"
}

# Custom policy for S3 bucket access
data "aws_iam_policy_document" "rekognition_s3_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectMetadata",
      "s3:PutObject"
    ]
    resources = [
      "${aws_s3_bucket.computer_vision.arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.computer_vision.arn
    ]
  }
}

resource "aws_iam_policy" "rekognition_s3_access" {
  name        = "${local.name_prefix}-rekognition-s3-policy"
  path        = "/"
  description = "Policy for Rekognition to access computer vision S3 bucket"
  policy      = data.aws_iam_policy_document.rekognition_s3_policy.json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-rekognition-s3-policy"
    Purpose = "S3 access for Rekognition services"
  })
}

resource "aws_iam_role_policy_attachment" "rekognition_s3_access" {
  role       = aws_iam_role.rekognition_video_analysis.name
  policy_arn = aws_iam_policy.rekognition_s3_access.arn
}

#####################################
# Amazon Rekognition Face Collection
#####################################

# Note: AWS provider doesn't have native support for Rekognition collections
# This would typically be created using AWS CLI or SDK in real deployment
# We'll create a null resource to document this requirement

resource "null_resource" "face_collection" {
  # This resource documents the need to create a face collection
  # In practice, this would be done via AWS CLI or Lambda function

  triggers = {
    collection_name = local.face_collection_name
    region         = data.aws_region.current.name
  }

  # Note: In production, you would use aws CLI or a Lambda function to create this
  # Example: aws rekognition create-collection --collection-id ${local.face_collection_name}

  tags = merge(local.common_tags, {
    Name    = local.face_collection_name
    Purpose = "Face recognition collection for retail security"
    Type    = "Rekognition Collection"
  })
}

#####################################
# Kinesis Data Stream for Results
#####################################

resource "aws_kinesis_stream" "rekognition_results" {
  name             = local.kinesis_data_stream_name
  shard_count      = var.kinesis_data_stream_shard_count
  retention_period = 24 # Hours

  shard_level_metrics = [
    "IncomingRecords",
    "OutgoingRecords",
  ]

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  encryption_type = "KMS"
  kms_key_id     = "alias/aws/kinesis"

  tags = merge(local.common_tags, {
    Name    = local.kinesis_data_stream_name
    Purpose = "Rekognition analysis results stream"
    Type    = "Kinesis Data Stream"
  })
}

#####################################
# Kinesis Video Stream for Real-time Analysis
#####################################

resource "aws_kinesisvideo_stream" "security_video" {
  name                    = local.kinesis_video_stream_name
  data_retention_in_hours = var.kinesis_video_data_retention_hours
  device_name             = "security-camera-${random_string.suffix.result}"
  media_type              = "video/h264"

  tags = merge(local.common_tags, {
    Name    = local.kinesis_video_stream_name
    Purpose = "Security camera video stream"
    Type    = "Kinesis Video Stream"
  })
}

#####################################
# Rekognition Stream Processor (Optional)
#####################################

# Note: AWS provider doesn't have native support for Rekognition stream processors
# This would typically be created using AWS CLI or SDK in real deployment

resource "null_resource" "stream_processor" {
  count = var.create_stream_processor ? 1 : 0

  depends_on = [
    aws_kinesisvideo_stream.security_video,
    aws_kinesis_stream.rekognition_results,
    aws_iam_role.rekognition_video_analysis,
    null_resource.face_collection
  ]

  triggers = {
    processor_name           = local.stream_processor_name
    kinesis_video_stream_arn = aws_kinesisvideo_stream.security_video.arn
    kinesis_data_stream_arn  = aws_kinesis_stream.rekognition_results.arn
    role_arn                = aws_iam_role.rekognition_video_analysis.arn
    face_collection_name     = local.face_collection_name
    face_match_threshold     = var.face_match_threshold
  }

  # Note: In production, you would use aws CLI or a Lambda function to create this
  # Example AWS CLI command would be:
  # aws rekognition create-stream-processor \
  #   --name ${local.stream_processor_name} \
  #   --input '{"KinesisVideoStream":{"Arn":"${aws_kinesisvideo_stream.security_video.arn}"}}' \
  #   --stream-processor-output '{"KinesisDataStream":{"Arn":"${aws_kinesis_stream.rekognition_results.arn}"}}' \
  #   --role-arn ${aws_iam_role.rekognition_video_analysis.arn} \
  #   --settings '{"FaceSearch":{"CollectionId":"${local.face_collection_name}","FaceMatchThreshold":${var.face_match_threshold}}}'

  tags = merge(local.common_tags, {
    Name    = local.stream_processor_name
    Purpose = "Real-time face search stream processor"
    Type    = "Rekognition Stream Processor"
  })
}

#####################################
# CloudWatch Log Groups for Monitoring
#####################################

resource "aws_cloudwatch_log_group" "computer_vision_logs" {
  name              = "/aws/computer-vision/${local.name_prefix}"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Name    = "/aws/computer-vision/${local.name_prefix}"
    Purpose = "Computer vision application logs"
  })
}

#####################################
# CloudWatch Alarms for Monitoring
#####################################

# Alarm for Kinesis Data Stream incoming records
resource "aws_cloudwatch_metric_alarm" "kinesis_incoming_records" {
  alarm_name          = "${local.name_prefix}-kinesis-incoming-records"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "IncomingRecords"
  namespace           = "AWS/Kinesis"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors kinesis incoming records"
  alarm_actions       = []

  dimensions = {
    StreamName = aws_kinesis_stream.rekognition_results.name
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-kinesis-incoming-records"
    Purpose = "Monitor Kinesis stream activity"
  })
}

# Alarm for S3 bucket size
resource "aws_cloudwatch_metric_alarm" "s3_bucket_size" {
  alarm_name          = "${local.name_prefix}-s3-bucket-size"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "BucketSizeBytes"
  namespace           = "AWS/S3"
  period              = "86400" # Daily
  statistic           = "Average"
  threshold           = "10737418240" # 10 GB in bytes
  alarm_description   = "This metric monitors S3 bucket size"
  alarm_actions       = []

  dimensions = {
    BucketName  = aws_s3_bucket.computer_vision.bucket
    StorageType = "StandardStorage"
  }

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-s3-bucket-size"
    Purpose = "Monitor S3 storage usage"
  })
}