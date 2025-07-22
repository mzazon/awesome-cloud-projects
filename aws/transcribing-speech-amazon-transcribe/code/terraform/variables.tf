# Variables for Amazon Transcribe Speech Recognition Infrastructure

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "transcribe-demo"
  
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "custom_vocabulary_terms" {
  description = "List of custom vocabulary terms for improved transcription accuracy"
  type        = list(string)
  default = [
    "AWS",
    "Amazon",
    "Transcribe",
    "API",
    "WebSocket",
    "real-time",
    "speech-to-text",
    "transcription",
    "diarization",
    "vocabulary"
  ]
}

variable "vocabulary_filter_terms" {
  description = "List of terms to filter/mask in transcriptions"
  type        = list(string)
  default = [
    "inappropriate",
    "confidential",
    "sensitive",
    "private"
  ]
}

variable "training_data_content" {
  description = "Training data content for custom language model"
  type        = string
  default     = <<-EOT
    AWS Transcribe provides automatic speech recognition capabilities.
    The service supports real-time streaming transcription.
    Custom vocabularies improve transcription accuracy for domain-specific terms.
    Speaker diarization identifies different speakers in audio files.
    Content redaction removes personally identifiable information.
    Amazon Transcribe integrates with other AWS services seamlessly.
  EOT
}

variable "lambda_timeout" {
  description = "Timeout for Lambda functions in seconds"
  type        = number
  default     = 300
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Memory size for Lambda functions in MB"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory size must be between 128 and 10240 MB."
  }
}

variable "enable_s3_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "enable_s3_encryption" {
  description = "Enable S3 bucket encryption"
  type        = bool
  default     = true
}

variable "s3_lifecycle_enabled" {
  description = "Enable S3 lifecycle management"
  type        = bool
  default     = true
}

variable "s3_transition_to_ia_days" {
  description = "Number of days before transitioning to IA storage class"
  type        = number
  default     = 30
}

variable "s3_transition_to_glacier_days" {
  description = "Number of days before transitioning to Glacier storage class"
  type        = number
  default     = 90
}

variable "s3_expiration_days" {
  description = "Number of days before object expiration"
  type        = number
  default     = 2555  # 7 years
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "speech-recognition-applications"
    ManagedBy   = "terraform"
    Service     = "amazon-transcribe"
    Environment = "dev"
  }
}

variable "max_speaker_labels" {
  description = "Maximum number of speaker labels for diarization"
  type        = number
  default     = 4
  
  validation {
    condition     = var.max_speaker_labels >= 2 && var.max_speaker_labels <= 10
    error_message = "Maximum speaker labels must be between 2 and 10."
  }
}

variable "language_code" {
  description = "Language code for transcription"
  type        = string
  default     = "en-US"
  
  validation {
    condition = contains([
      "en-US", "en-GB", "es-US", "es-ES", "fr-CA", "fr-FR", 
      "de-DE", "it-IT", "pt-BR", "ja-JP", "ko-KR", "zh-CN"
    ], var.language_code)
    error_message = "Language code must be a supported Amazon Transcribe language."
  }
}

variable "media_format" {
  description = "Default media format for transcription jobs"
  type        = string
  default     = "mp3"
  
  validation {
    condition     = contains(["mp3", "mp4", "wav", "flac"], var.media_format)
    error_message = "Media format must be one of: mp3, mp4, wav, flac."
  }
}

variable "vocabulary_filter_method" {
  description = "Method for vocabulary filtering"
  type        = string
  default     = "mask"
  
  validation {
    condition     = contains(["remove", "mask", "tag"], var.vocabulary_filter_method)
    error_message = "Vocabulary filter method must be one of: remove, mask, tag."
  }
}

variable "enable_content_redaction" {
  description = "Enable PII content redaction"
  type        = bool
  default     = true
}

variable "redaction_output_type" {
  description = "Content redaction output type"
  type        = string
  default     = "redacted_and_unredacted"
  
  validation {
    condition     = contains(["redacted", "redacted_and_unredacted"], var.redaction_output_type)
    error_message = "Redaction output type must be either 'redacted' or 'redacted_and_unredacted'."
  }
}

variable "enable_job_execution_settings" {
  description = "Enable job execution settings for transcription jobs"
  type        = bool
  default     = true
}

variable "allow_deferred_execution" {
  description = "Allow deferred execution of transcription jobs"
  type        = bool
  default     = false
}

variable "data_access_role_arn" {
  description = "ARN of the data access role for custom language models (optional)"
  type        = string
  default     = ""
}

variable "enable_automatic_language_detection" {
  description = "Enable automatic language detection"
  type        = bool
  default     = false
}

variable "identify_language_options" {
  description = "Language options for automatic detection"
  type        = list(string)
  default     = ["en-US", "es-US", "fr-FR"]
}

variable "enable_partial_results_stabilization" {
  description = "Enable partial results stabilization for streaming"
  type        = bool
  default     = true
}

variable "partial_results_stability" {
  description = "Partial results stability level"
  type        = string
  default     = "high"
  
  validation {
    condition     = contains(["low", "medium", "high"], var.partial_results_stability)
    error_message = "Partial results stability must be one of: low, medium, high."
  }
}

variable "media_sample_rate_hertz" {
  description = "Media sample rate in Hz for streaming transcription"
  type        = number
  default     = 44100
  
  validation {
    condition     = contains([8000, 16000, 22050, 44100, 48000], var.media_sample_rate_hertz)
    error_message = "Media sample rate must be one of: 8000, 16000, 22050, 44100, 48000."
  }
}

variable "enable_channel_identification" {
  description = "Enable channel identification for multi-channel audio"
  type        = bool
  default     = true
}

variable "enable_speaker_labels" {
  description = "Enable speaker labels (diarization)"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 14
  
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention days must be a valid value."
  }
}

variable "enable_xray_tracing" {
  description = "Enable X-Ray tracing for Lambda functions"
  type        = bool
  default     = false
}