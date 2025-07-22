# Output values for Adaptive Bitrate Streaming infrastructure

#------------------------------------------------------------------------------
# S3 BUCKET OUTPUTS
#------------------------------------------------------------------------------

output "source_bucket_name" {
  description = "Name of the S3 bucket for source video files"
  value       = aws_s3_bucket.source.bucket
}

output "source_bucket_arn" {
  description = "ARN of the S3 bucket for source video files"
  value       = aws_s3_bucket.source.arn
}

output "output_bucket_name" {
  description = "Name of the S3 bucket for processed ABR content"
  value       = aws_s3_bucket.output.bucket
}

output "output_bucket_arn" {
  description = "ARN of the S3 bucket for processed ABR content"
  value       = aws_s3_bucket.output.arn
}

output "upload_instructions" {
  description = "Instructions for uploading video files"
  value = {
    upload_command = "aws s3 cp your-video.mp4 s3://${aws_s3_bucket.source.bucket}/"
    supported_formats = var.video_file_extensions
    note = "Upload video files to the source bucket to trigger automatic ABR processing"
  }
}

#------------------------------------------------------------------------------
# MEDIACONVERT OUTPUTS
#------------------------------------------------------------------------------

output "mediaconvert_role_arn" {
  description = "ARN of the IAM role used by MediaConvert"
  value       = aws_iam_role.mediaconvert.arn
}

output "mediaconvert_job_template_name" {
  description = "Name of the MediaConvert job template for ABR processing"
  value       = aws_mediaconvert_job_template.abr_streaming.name
}

output "mediaconvert_job_template_arn" {
  description = "ARN of the MediaConvert job template"
  value       = aws_mediaconvert_job_template.abr_streaming.arn
}

output "mediaconvert_endpoint" {
  description = "MediaConvert endpoint URL for this region"
  value       = data.aws_mediaconvert_endpoints.default.endpoints[0].url
}

#------------------------------------------------------------------------------
# LAMBDA FUNCTION OUTPUTS
#------------------------------------------------------------------------------

output "lambda_function_name" {
  description = "Name of the Lambda function that processes video uploads"
  value       = aws_lambda_function.abr_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.abr_processor.arn
}

output "lambda_log_group_name" {
  description = "CloudWatch Log Group name for Lambda function"
  value       = aws_cloudwatch_log_group.lambda.name
}

#------------------------------------------------------------------------------
# CLOUDFRONT DISTRIBUTION OUTPUTS
#------------------------------------------------------------------------------

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.abr_streaming.id
}

output "cloudfront_distribution_domain" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.abr_streaming.domain_name
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.abr_streaming.arn
}

output "cloudfront_distribution_status" {
  description = "Status of the CloudFront distribution"
  value       = aws_cloudfront_distribution.abr_streaming.status
}

#------------------------------------------------------------------------------
# STREAMING URL PATTERNS
#------------------------------------------------------------------------------

output "streaming_urls" {
  description = "URL patterns for accessing streaming content"
  value = {
    hls_pattern  = "https://${aws_cloudfront_distribution.abr_streaming.domain_name}/hls/[video-name]/index.m3u8"
    dash_pattern = "https://${aws_cloudfront_distribution.abr_streaming.domain_name}/dash/[video-name]/index.mpd"
    thumbnail_pattern = "https://${aws_cloudfront_distribution.abr_streaming.domain_name}/thumbnails/[video-name]/[video-name]_thumb_0001.jpg"
    example_hls  = "https://${aws_cloudfront_distribution.abr_streaming.domain_name}/hls/sample-video/index.m3u8"
    example_dash = "https://${aws_cloudfront_distribution.abr_streaming.domain_name}/dash/sample-video/index.mpd"
  }
}

#------------------------------------------------------------------------------
# CONFIGURATION SUMMARY
#------------------------------------------------------------------------------

output "abr_configuration" {
  description = "Summary of ABR streaming configuration"
  value = {
    enabled_formats = {
      hls        = var.enable_hls_output
      dash       = var.enable_dash_output
      thumbnails = var.enable_thumbnails
    }
    bitrate_ladder = {
      "1080p" = var.abr_bitrate_ladder.enable_1080p ? "5000 kbps" : "disabled"
      "720p"  = var.abr_bitrate_ladder.enable_720p ? "3000 kbps" : "disabled"
      "480p"  = var.abr_bitrate_ladder.enable_480p ? "1500 kbps" : "disabled"
      "360p"  = var.abr_bitrate_ladder.enable_360p ? "800 kbps" : "disabled"
    }
    segment_lengths = {
      hls_segments  = "${var.hls_segment_length} seconds"
      dash_segments = "${var.dash_segment_length} seconds"
    }
    processing = {
      lambda_timeout = "${var.lambda_timeout} seconds"
      lambda_memory  = "${var.lambda_memory_size} MB"
    }
  }
}

#------------------------------------------------------------------------------
# MONITORING OUTPUTS
#------------------------------------------------------------------------------

output "monitoring_resources" {
  description = "Monitoring and alerting resources"
  value = var.enable_monitoring ? {
    lambda_error_alarm    = aws_cloudwatch_metric_alarm.lambda_errors[0].arn
    lambda_duration_alarm = aws_cloudwatch_metric_alarm.lambda_duration[0].arn
    sns_topic            = var.notification_email != "" ? aws_sns_topic.notifications[0].arn : null
    log_group            = aws_cloudwatch_log_group.lambda.arn
  } : {
    monitoring_enabled = false
    log_group         = aws_cloudwatch_log_group.lambda.arn
  }
}

#------------------------------------------------------------------------------
# GETTING STARTED GUIDE
#------------------------------------------------------------------------------

output "getting_started" {
  description = "Quick start guide for using the ABR streaming infrastructure"
  value = {
    step_1 = "Upload a video file: aws s3 cp your-video.mp4 s3://${aws_s3_bucket.source.bucket}/"
    step_2 = "Monitor processing: aws logs tail /aws/lambda/${aws_lambda_function.abr_processor.function_name} --follow"
    step_3 = "Check job status: aws mediaconvert list-jobs --endpoint-url ${data.aws_mediaconvert_endpoints.default.endpoints[0].url} --max-results 5"
    step_4 = "Access HLS stream: https://${aws_cloudfront_distribution.abr_streaming.domain_name}/hls/[video-name]/index.m3u8"
    step_5 = "Access DASH stream: https://${aws_cloudfront_distribution.abr_streaming.domain_name}/dash/[video-name]/index.mpd"
    note   = "Replace [video-name] with the filename (without extension) of your uploaded video"
  }
}

#------------------------------------------------------------------------------
# COST ESTIMATION
#------------------------------------------------------------------------------

output "estimated_costs" {
  description = "Estimated monthly costs for the ABR streaming infrastructure"
  value = {
    note = "Costs vary based on usage. Estimates are for moderate usage scenarios."
    components = {
      s3_storage       = "~$0.023 per GB/month for Standard storage"
      cloudfront       = "~$0.085 per GB for data transfer out (first 10TB)"
      mediaconvert     = "~$0.0075 per minute of HD video transcoding"
      lambda           = "~$0.20 per 1M requests + compute time"
      data_transfer    = "Variable based on viewer traffic"
    }
    optimization_tips = [
      "Use S3 Intelligent Tiering for long-term storage cost optimization",
      "Configure CloudFront caching policies to reduce origin requests",
      "Monitor MediaConvert job completion metrics to optimize encoding settings",
      "Use S3 lifecycle policies to archive or delete old content"
    ]
  }
}

#------------------------------------------------------------------------------
# SECURITY INFORMATION
#------------------------------------------------------------------------------

output "security_configuration" {
  description = "Security features and recommendations"
  value = {
    implemented_features = [
      "S3 bucket encryption at rest using AES-256",
      "S3 bucket versioning enabled for data protection",
      "S3 public access blocked on source bucket",
      "CloudFront Origin Access Control (OAC) for secure S3 access",
      "IAM roles with least privilege access",
      "HTTPS enforcement on CloudFront distribution",
      "Lambda function with minimal required permissions"
    ]
    recommendations = [
      "Enable AWS CloudTrail for API call logging",
      "Consider using AWS Config for compliance monitoring",
      "Implement S3 bucket access logging if needed",
      "Review and rotate IAM access keys regularly",
      "Enable AWS GuardDuty for threat detection",
      "Consider using AWS KMS for enhanced encryption control"
    ]
  }
}

#------------------------------------------------------------------------------
# TROUBLESHOOTING INFORMATION
#------------------------------------------------------------------------------

output "troubleshooting" {
  description = "Common troubleshooting commands and information"
  value = {
    check_lambda_logs = "aws logs tail /aws/lambda/${aws_lambda_function.abr_processor.function_name} --follow"
    list_mediaconvert_jobs = "aws mediaconvert list-jobs --endpoint-url ${data.aws_mediaconvert_endpoints.default.endpoints[0].url}"
    check_s3_uploads = "aws s3 ls s3://${aws_s3_bucket.source.bucket}/ --recursive"
    check_outputs = "aws s3 ls s3://${aws_s3_bucket.output.bucket}/ --recursive"
    cloudfront_invalidation = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.abr_streaming.id} --paths '/*'"
    common_issues = {
      "Lambda not triggering" = "Check S3 event notifications and Lambda permissions"
      "MediaConvert job fails" = "Verify IAM role permissions and input file format"
      "CloudFront 403 errors" = "Check Origin Access Control configuration"
      "Slow processing" = "Monitor MediaConvert queue and consider reserved capacity"
    }
  }
}