# Resource Identifiers
output "resource_suffix" {
  description = "Random suffix used for resource names"
  value       = local.resource_suffix
}

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region"
  value       = data.aws_region.current.name
}

# S3 Bucket Information
output "s3_bucket_name" {
  description = "S3 bucket name for storage"
  value       = aws_s3_bucket.streaming_storage.bucket
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.streaming_storage.arn
}

output "s3_bucket_website_endpoint" {
  description = "S3 bucket website endpoint (if enabled)"
  value       = var.create_test_resources ? aws_s3_bucket_website_configuration.streaming_storage[0].website_endpoint : null
}

# IAM Role Information
output "medialive_role_arn" {
  description = "MediaLive IAM role ARN"
  value       = aws_iam_role.medialive_role.arn
}

output "medialive_role_name" {
  description = "MediaLive IAM role name"
  value       = aws_iam_role.medialive_role.name
}

# MediaLive Input Information
output "medialive_input_id" {
  description = "MediaLive input ID"
  value       = aws_medialive_input.streaming_input.id
}

output "medialive_input_arn" {
  description = "MediaLive input ARN"
  value       = aws_medialive_input.streaming_input.arn
}

output "medialive_input_destinations" {
  description = "MediaLive input destinations (RTMP URLs)"
  value       = aws_medialive_input.streaming_input.destinations
}

output "medialive_input_security_group_id" {
  description = "MediaLive input security group ID"
  value       = var.enable_input_security_group ? aws_medialive_input_security_group.streaming_input_sg[0].id : null
}

# MediaLive Channel Information
output "medialive_channel_id" {
  description = "MediaLive channel ID"
  value       = aws_medialive_channel.streaming_channel.id
}

output "medialive_channel_arn" {
  description = "MediaLive channel ARN"
  value       = aws_medialive_channel.streaming_channel.arn
}

output "medialive_channel_name" {
  description = "MediaLive channel name"
  value       = aws_medialive_channel.streaming_channel.name
}

# MediaPackage Channel Information
output "mediapackage_channel_id" {
  description = "MediaPackage channel ID"
  value       = aws_media_package_channel.streaming_channel.id
}

output "mediapackage_channel_arn" {
  description = "MediaPackage channel ARN"
  value       = aws_media_package_channel.streaming_channel.arn
}

output "mediapackage_hls_ingest_endpoints" {
  description = "MediaPackage HLS ingest endpoints"
  value       = aws_media_package_channel.streaming_channel.hls_ingest
}

# MediaPackage Origin Endpoints
output "mediapackage_hls_endpoint_id" {
  description = "MediaPackage HLS origin endpoint ID"
  value       = aws_media_package_origin_endpoint.hls_endpoint.id
}

output "mediapackage_hls_endpoint_url" {
  description = "MediaPackage HLS origin endpoint URL"
  value       = aws_media_package_origin_endpoint.hls_endpoint.url
}

output "mediapackage_dash_endpoint_id" {
  description = "MediaPackage DASH origin endpoint ID"
  value       = aws_media_package_origin_endpoint.dash_endpoint.id
}

output "mediapackage_dash_endpoint_url" {
  description = "MediaPackage DASH origin endpoint URL"
  value       = aws_media_package_origin_endpoint.dash_endpoint.url
}

# CloudFront Distribution Information
output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.streaming_distribution.id
}

output "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN"
  value       = aws_cloudfront_distribution.streaming_distribution.arn
}

output "cloudfront_distribution_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.streaming_distribution.domain_name
}

output "cloudfront_distribution_hosted_zone_id" {
  description = "CloudFront distribution hosted zone ID"
  value       = aws_cloudfront_distribution.streaming_distribution.hosted_zone_id
}

# SNS Topic Information
output "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  value       = var.enable_cloudwatch_alarms && var.sns_notification_email != "" ? aws_sns_topic.medialive_alerts[0].arn : null
}

# CloudWatch Alarms
output "cloudwatch_alarm_channel_errors_name" {
  description = "CloudWatch alarm name for channel errors"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.medialive_channel_errors[0].alarm_name : null
}

output "cloudwatch_alarm_input_freeze_name" {
  description = "CloudWatch alarm name for input video freeze"
  value       = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.medialive_input_freeze[0].alarm_name : null
}

# Streaming URLs
output "streaming_urls" {
  description = "Streaming URLs for playback"
  value = {
    hls_via_cloudfront  = "https://${aws_cloudfront_distribution.streaming_distribution.domain_name}/out/v1/index.m3u8"
    dash_via_cloudfront = "https://${aws_cloudfront_distribution.streaming_distribution.domain_name}/out/v1/index.mpd"
    hls_direct         = aws_media_package_origin_endpoint.hls_endpoint.url
    dash_direct        = aws_media_package_origin_endpoint.dash_endpoint.url
  }
}

# RTMP Streaming Configuration
output "rtmp_streaming_config" {
  description = "RTMP streaming configuration"
  value = {
    primary_url = length(aws_medialive_input.streaming_input.destinations) > 0 ? aws_medialive_input.streaming_input.destinations[0].url : null
    backup_url  = length(aws_medialive_input.streaming_input.destinations) > 1 ? aws_medialive_input.streaming_input.destinations[1].url : null
    stream_key  = "live"
  }
}

# Test Player Information
output "test_player_url" {
  description = "Test player URL (if created)"
  value       = var.create_test_resources ? "http://${aws_s3_bucket.streaming_storage.bucket}.s3-website.${data.aws_region.current.name}.amazonaws.com/" : null
}

# Complete Setup Summary
output "setup_summary" {
  description = "Complete setup summary with all important information"
  value = {
    # Infrastructure
    resource_suffix        = local.resource_suffix
    aws_region            = data.aws_region.current.name
    aws_account_id        = data.aws_caller_identity.current.account_id
    
    # Storage
    s3_bucket_name        = aws_s3_bucket.streaming_storage.bucket
    
    # MediaLive
    medialive_channel_id  = aws_medialive_channel.streaming_channel.id
    medialive_input_id    = aws_medialive_input.streaming_input.id
    
    # MediaPackage
    mediapackage_channel_id = aws_media_package_channel.streaming_channel.id
    
    # CloudFront
    cloudfront_domain     = aws_cloudfront_distribution.streaming_distribution.domain_name
    
    # Streaming URLs
    hls_playback_url      = "https://${aws_cloudfront_distribution.streaming_distribution.domain_name}/out/v1/index.m3u8"
    dash_playback_url     = "https://${aws_cloudfront_distribution.streaming_distribution.domain_name}/out/v1/index.mpd"
    
    # RTMP Configuration
    rtmp_primary_url      = length(aws_medialive_input.streaming_input.destinations) > 0 ? aws_medialive_input.streaming_input.destinations[0].url : null
    rtmp_backup_url       = length(aws_medialive_input.streaming_input.destinations) > 1 ? aws_medialive_input.streaming_input.destinations[1].url : null
    rtmp_stream_key       = "live"
    
    # Test Resources
    test_player_url       = var.create_test_resources ? "http://${aws_s3_bucket.streaming_storage.bucket}.s3-website.${data.aws_region.current.name}.amazonaws.com/" : null
    
    # Monitoring
    sns_topic_arn         = var.enable_cloudwatch_alarms && var.sns_notification_email != "" ? aws_sns_topic.medialive_alerts[0].arn : null
    
    # Next Steps
    next_steps = [
      "1. Start the MediaLive channel using AWS CLI or console",
      "2. Configure your streaming software with the RTMP URLs",
      "3. Begin streaming and test playback using the provided URLs",
      "4. Monitor the channel status and CloudWatch metrics",
      "5. Stop the channel when finished to avoid charges"
    ]
  }
}

# Cost Optimization Reminders
output "cost_optimization_reminders" {
  description = "Important reminders for cost optimization"
  value = {
    important_notes = [
      "MediaLive channels incur costs while running - stop when not in use",
      "CloudFront charges for data transfer - monitor usage",
      "S3 storage costs accumulate - clean up old files regularly",
      "Enable lifecycle policies to automatically delete old content"
    ]
    monitoring_recommendations = [
      "Set up billing alerts for unexpected charges",
      "Monitor MediaLive channel runtime through CloudWatch",
      "Review CloudFront usage reports regularly",
      "Implement automated channel stop/start schedules if needed"
    ]
  }
}

# FFmpeg Test Command
output "ffmpeg_test_command" {
  description = "FFmpeg command for testing stream ingestion"
  value = length(aws_medialive_input.streaming_input.destinations) > 0 ? "ffmpeg -re -i your-video-file.mp4 -c copy -f flv ${aws_medialive_input.streaming_input.destinations[0].url}/live" : null
}