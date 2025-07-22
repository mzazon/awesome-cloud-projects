# variables.tf - Input variables for computer vision infrastructure

variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"

  validation {
    condition = contains([
      "us-east-1", "us-east-2", "us-west-1", "us-west-2",
      "eu-west-1", "eu-west-2", "eu-central-1",
      "ap-southeast-1", "ap-southeast-2", "ap-northeast-1"
    ], var.aws_region)
    error_message = "AWS region must be a valid region that supports Amazon Rekognition."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,10}$", var.environment))
    error_message = "Environment must be 2-10 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "owner" {
  description = "Owner or team responsible for the infrastructure"
  type        = string
  default     = "data-team"

  validation {
    condition     = length(var.owner) > 0
    error_message = "Owner cannot be empty."
  }
}

variable "project_name" {
  description = "Name of the project for resource naming"
  type        = string
  default     = "computer-vision"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "s3_bucket_name_prefix" {
  description = "Prefix for S3 bucket name (will be combined with random suffix)"
  type        = string
  default     = "computer-vision-app"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.s3_bucket_name_prefix))
    error_message = "S3 bucket prefix must be 3-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "face_collection_name_prefix" {
  description = "Prefix for Rekognition face collection name"
  type        = string
  default     = "retail-faces"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{3,20}$", var.face_collection_name_prefix))
    error_message = "Face collection prefix must be 3-20 characters, letters, numbers, dots, hyphens, and underscores only."
  }
}

variable "kinesis_video_stream_name_prefix" {
  description = "Prefix for Kinesis Video Stream name"
  type        = string
  default     = "security-video"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{3,20}$", var.kinesis_video_stream_name_prefix))
    error_message = "Kinesis Video Stream prefix must be 3-20 characters, letters, numbers, dots, hyphens, and underscores only."
  }
}

variable "kinesis_data_stream_name_prefix" {
  description = "Prefix for Kinesis Data Stream name"
  type        = string
  default     = "rekognition-results"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{3,20}$", var.kinesis_data_stream_name_prefix))
    error_message = "Kinesis Data Stream prefix must be 3-20 characters, letters, numbers, dots, hyphens, and underscores only."
  }
}

variable "kinesis_data_stream_shard_count" {
  description = "Number of shards for Kinesis Data Stream"
  type        = number
  default     = 1

  validation {
    condition     = var.kinesis_data_stream_shard_count >= 1 && var.kinesis_data_stream_shard_count <= 10
    error_message = "Kinesis Data Stream shard count must be between 1 and 10."
  }
}

variable "kinesis_video_data_retention_hours" {
  description = "Data retention period in hours for Kinesis Video Stream"
  type        = number
  default     = 24

  validation {
    condition     = var.kinesis_video_data_retention_hours >= 1 && var.kinesis_video_data_retention_hours <= 8760
    error_message = "Kinesis Video Stream retention must be between 1 hour and 8760 hours (1 year)."
  }
}

variable "face_match_threshold" {
  description = "Minimum confidence threshold for face matching (0-100)"
  type        = number
  default     = 80.0

  validation {
    condition     = var.face_match_threshold >= 0 && var.face_match_threshold <= 100
    error_message = "Face match threshold must be between 0 and 100."
  }
}

variable "enable_s3_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "enable_s3_encryption" {
  description = "Enable S3 bucket server-side encryption"
  type        = bool
  default     = true
}

variable "s3_lifecycle_transition_days" {
  description = "Number of days before transitioning objects to Intelligent Tiering"
  type        = number
  default     = 30

  validation {
    condition     = var.s3_lifecycle_transition_days >= 1
    error_message = "S3 lifecycle transition days must be at least 1."
  }
}

variable "create_stream_processor" {
  description = "Whether to create Rekognition stream processor for real-time analysis"
  type        = bool
  default     = true
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}