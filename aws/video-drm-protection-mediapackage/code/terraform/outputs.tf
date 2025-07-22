# Output Values for DRM-Protected Video Streaming Infrastructure

# ============================================================================
# CORE INFRASTRUCTURE IDENTIFIERS
# ============================================================================

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

# ============================================================================
# SECURITY AND ENCRYPTION OUTPUTS
# ============================================================================

output "kms_key_id" {
  description = "KMS key ID for DRM content encryption"
  value       = aws_kms_key.drm_content_key.key_id
}

output "kms_key_arn" {
  description = "KMS key ARN for DRM content encryption"
  value       = aws_kms_key.drm_content_key.arn
}

output "kms_key_alias" {
  description = "KMS key alias for DRM content encryption"
  value       = aws_kms_alias.drm_content_key_alias.name
}

output "secrets_manager_secret_arn" {
  description = "Secrets Manager secret ARN containing DRM configuration"
  value       = aws_secretsmanager_secret.drm_config.arn
  sensitive   = true
}

output "secrets_manager_secret_name" {
  description = "Secrets Manager secret name containing DRM configuration"
  value       = aws_secretsmanager_secret.drm_config.name
}

# ============================================================================
# SPEKE KEY PROVIDER OUTPUTS
# ============================================================================

output "speke_lambda_function_name" {
  description = "Name of the SPEKE Lambda function"
  value       = aws_lambda_function.speke_provider.function_name
}

output "speke_lambda_function_arn" {
  description = "ARN of the SPEKE Lambda function"
  value       = aws_lambda_function.speke_provider.arn
}

output "speke_endpoint_url" {
  description = "SPEKE endpoint URL for MediaPackage integration"
  value       = aws_lambda_function_url.speke_endpoint.function_url
}

output "speke_lambda_role_arn" {
  description = "IAM role ARN for the SPEKE Lambda function"
  value       = aws_iam_role.speke_lambda_role.arn
}

# ============================================================================
# MEDIALIVE INFRASTRUCTURE OUTPUTS
# ============================================================================

output "medialive_input_id" {
  description = "MediaLive input ID for RTMP ingestion"
  value       = aws_medialive_input.drm_input.id
}

output "medialive_input_destinations" {
  description = "MediaLive input RTMP destinations"
  value       = aws_medialive_input.drm_input.destinations
}

output "medialive_security_group_id" {
  description = "MediaLive input security group ID"
  value       = aws_medialive_input_security_group.drm_security_group.id
}

output "medialive_channel_id" {
  description = "MediaLive channel ID for DRM-protected streaming"
  value       = aws_medialive_channel.drm_channel.id
}

output "medialive_channel_arn" {
  description = "MediaLive channel ARN for DRM-protected streaming"
  value       = aws_medialive_channel.drm_channel.arn
}

output "medialive_role_arn" {
  description = "MediaLive IAM role ARN with DRM permissions"
  value       = aws_iam_role.medialive_drm_role.arn
}

# ============================================================================
# MEDIAPACKAGE INFRASTRUCTURE OUTPUTS
# ============================================================================

output "mediapackage_channel_id" {
  description = "MediaPackage channel ID for content packaging"
  value       = aws_media_package_channel.drm_channel.id
}

output "mediapackage_channel_arn" {
  description = "MediaPackage channel ARN for content packaging"
  value       = aws_media_package_channel.drm_channel.arn
}

output "mediapackage_hls_ingest_urls" {
  description = "MediaPackage HLS ingest endpoints"
  value       = aws_media_package_channel.drm_channel.hls_ingest
  sensitive   = true
}

output "hls_drm_endpoint_id" {
  description = "MediaPackage HLS DRM endpoint ID"
  value       = aws_media_package_origin_endpoint.hls_drm_endpoint.id
}

output "hls_drm_endpoint_url" {
  description = "MediaPackage HLS DRM endpoint URL"
  value       = aws_media_package_origin_endpoint.hls_drm_endpoint.url
}

output "dash_drm_endpoint_id" {
  description = "MediaPackage DASH DRM endpoint ID"
  value       = aws_media_package_origin_endpoint.dash_drm_endpoint.id
}

output "dash_drm_endpoint_url" {
  description = "MediaPackage DASH DRM endpoint URL"
  value       = aws_media_package_origin_endpoint.dash_drm_endpoint.url
}

# ============================================================================
# CLOUDFRONT CDN OUTPUTS
# ============================================================================

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID for DRM content delivery"
  value       = aws_cloudfront_distribution.drm_distribution.id
}

output "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN for DRM content delivery"
  value       = aws_cloudfront_distribution.drm_distribution.arn
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.drm_distribution.domain_name
}

output "cloudfront_hosted_zone_id" {
  description = "CloudFront distribution hosted zone ID"
  value       = aws_cloudfront_distribution.drm_distribution.hosted_zone_id
}

# ============================================================================
# PROTECTED STREAMING URLS
# ============================================================================

output "protected_hls_streaming_url" {
  description = "DRM-protected HLS streaming URL via CloudFront"
  value       = "https://${aws_cloudfront_distribution.drm_distribution.domain_name}/out/v1/index.m3u8"
}

output "protected_dash_streaming_url" {
  description = "DRM-protected DASH streaming URL via CloudFront"
  value       = "https://${aws_cloudfront_distribution.drm_distribution.domain_name}/out/v1/index.mpd"
}

# ============================================================================
# RTMP STREAMING INPUTS
# ============================================================================

output "rtmp_primary_endpoint" {
  description = "Primary RTMP endpoint for content ingestion"
  value       = length(aws_medialive_input.drm_input.destinations) > 0 ? aws_medialive_input.drm_input.destinations[0].url : null
}

output "rtmp_backup_endpoint" {
  description = "Backup RTMP endpoint for content ingestion"
  value       = length(aws_medialive_input.drm_input.destinations) > 1 ? aws_medialive_input.drm_input.destinations[1].url : null
}

output "rtmp_stream_key" {
  description = "RTMP stream key for content ingestion"
  value       = "live"
}

# ============================================================================
# S3 TEST INFRASTRUCTURE OUTPUTS
# ============================================================================

output "test_content_bucket_name" {
  description = "S3 bucket name for test content storage"
  value       = aws_s3_bucket.test_content.id
}

output "test_content_bucket_arn" {
  description = "S3 bucket ARN for test content storage"
  value       = aws_s3_bucket.test_content.arn
}

output "test_content_website_url" {
  description = "S3 bucket website URL for test content (if website hosting enabled)"
  value       = var.s3_config.enable_website_hosting ? "http://${aws_s3_bucket.test_content.id}.s3-website.${data.aws_region.current.name}.amazonaws.com" : null
}

# ============================================================================
# DRM CONFIGURATION OUTPUTS
# ============================================================================

output "drm_system_ids" {
  description = "DRM system IDs configured for content protection"
  value = {
    widevine  = var.mediapackage_config.drm_systems.widevine_system_id
    playready = var.mediapackage_config.drm_systems.playready_system_id
    fairplay  = var.mediapackage_config.drm_systems.fairplay_system_id
  }
}

output "key_rotation_interval_seconds" {
  description = "Key rotation interval in seconds for DRM content"
  value       = var.mediapackage_config.key_rotation_interval
}

# ============================================================================
# SECURITY AND ACCESS INFORMATION
# ============================================================================

output "geographic_restrictions" {
  description = "Geographic restrictions applied to content delivery"
  value = {
    restriction_type = var.cloudfront_config.geographic_restrictions.restriction_type
    blocked_countries = var.cloudfront_config.geographic_restrictions.locations
  }
}

output "allowed_cidr_blocks" {
  description = "CIDR blocks allowed for MediaLive input access"
  value       = var.network_config.allowed_cidr_blocks
}

# ============================================================================
# MONITORING AND LOGGING OUTPUTS
# ============================================================================

output "speke_lambda_log_group" {
  description = "CloudWatch log group for SPEKE Lambda function"
  value       = aws_cloudwatch_log_group.speke_lambda_logs.name
}

# ============================================================================
# DEPLOYMENT SUMMARY
# ============================================================================

output "deployment_summary" {
  description = "Summary of the deployed DRM-protected streaming infrastructure"
  value = {
    project_name         = var.project_name
    environment         = var.environment
    aws_region          = data.aws_region.current.name
    random_suffix       = random_string.suffix.result
    deployment_date     = timestamp()
    
    security_features = [
      "Multi-DRM Support (Widevine, PlayReady, FairPlay)",
      "SPEKE API Integration for Key Management", 
      "Content Encryption with Key Rotation",
      "Geographic Content Restrictions",
      "HTTPS-Only Content Delivery",
      "KMS-Encrypted Configuration Storage"
    ]
    
    streaming_capabilities = [
      "HLS Adaptive Bitrate Streaming",
      "DASH Adaptive Bitrate Streaming", 
      "Multiple Quality Tiers (1080p, 720p, 480p)",
      "Global CDN Distribution",
      "Real-time RTMP Ingestion"
    ]
    
    endpoints = {
      speke_provider = aws_lambda_function_url.speke_endpoint.function_url
      hls_streaming  = "https://${aws_cloudfront_distribution.drm_distribution.domain_name}/out/v1/index.m3u8"
      dash_streaming = "https://${aws_cloudfront_distribution.drm_distribution.domain_name}/out/v1/index.mpd"
      rtmp_primary   = length(aws_medialive_input.drm_input.destinations) > 0 ? aws_medialive_input.drm_input.destinations[0].url : null
    }
  }
}