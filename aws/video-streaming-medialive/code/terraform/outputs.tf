# Outputs for Video Streaming Platform Infrastructure
# This file defines all outputs that provide important information after deployment

# Platform Identification
output "platform_name" {
  description = "Complete platform name with unique suffix"
  value       = local.platform_name
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

# MediaLive Outputs
output "medialive_channel" {
  description = "MediaLive channel information"
  value = {
    id    = aws_medialive_channel.main.id
    name  = aws_medialive_channel.main.name
    arn   = aws_medialive_channel.main.arn
    state = aws_medialive_channel.main.state
  }
}

output "medialive_inputs" {
  description = "MediaLive input information and endpoints"
  value = {
    rtmp_input = {
      id           = aws_medialive_input.rtmp.id
      name         = aws_medialive_input.rtmp.name
      type         = aws_medialive_input.rtmp.type
      destinations = aws_medialive_input.rtmp.destinations
    }
    hls_input = {
      id   = aws_medialive_input.hls.id
      name = aws_medialive_input.hls.name
      type = aws_medialive_input.hls.type
    }
    rtp_input = {
      id           = aws_medialive_input.rtp.id
      name         = aws_medialive_input.rtp.name
      type         = aws_medialive_input.rtp.type
      destinations = aws_medialive_input.rtp.destinations
    }
  }
}

output "streaming_endpoints" {
  description = "Primary RTMP streaming endpoints for content ingestion"
  value = {
    primary_rtmp_url = length(aws_medialive_input.rtmp.destinations) > 0 ? aws_medialive_input.rtmp.destinations[0].url : ""
    backup_rtmp_url  = length(aws_medialive_input.rtmp.destinations) > 1 ? aws_medialive_input.rtmp.destinations[1].url : ""
    stream_key       = "live"
    rtmp_instructions = "Use OBS Studio or similar software to stream to these RTMP endpoints with stream key 'live'"
  }
}

output "input_security_groups" {
  description = "MediaLive input security group information"
  value = {
    public_security_group = {
      id           = aws_medialive_input_security_group.public.id
      whitelist_rules = aws_medialive_input_security_group.public.whitelist_rules
    }
    internal_security_group = {
      id           = aws_medialive_input_security_group.internal.id
      whitelist_rules = aws_medialive_input_security_group.internal.whitelist_rules
    }
  }
}

# MediaPackage Outputs
output "mediapackage_channel" {
  description = "MediaPackage channel information"
  value = {
    id          = aws_mediapackage_channel.main.id
    description = aws_mediapackage_channel.main.description
    arn         = aws_mediapackage_channel.main.arn
    hls_ingest  = aws_mediapackage_channel.main.hls_ingest
  }
}

output "mediapackage_endpoints" {
  description = "MediaPackage origin endpoint URLs for different streaming formats"
  value = {
    hls_endpoint = {
      id  = aws_mediapackage_origin_endpoint.hls.id
      url = aws_mediapackage_origin_endpoint.hls.url
      description = "HLS endpoint with adaptive bitrate streaming and advanced features"
    }
    dash_endpoint = {
      id  = aws_mediapackage_origin_endpoint.dash.id
      url = aws_mediapackage_origin_endpoint.dash.url
      description = "DASH endpoint with DRM protection support"
    }
    cmaf_endpoint = var.enable_low_latency ? {
      id  = aws_mediapackage_origin_endpoint.cmaf[0].id
      url = aws_mediapackage_origin_endpoint.cmaf[0].url
      description = "CMAF endpoint for low-latency streaming"
    } : null
  }
}

# CloudFront Outputs
output "cloudfront_distribution" {
  description = "CloudFront distribution information and playback URLs"
  value = {
    id                     = aws_cloudfront_distribution.main.id
    domain_name           = aws_cloudfront_distribution.main.domain_name
    hosted_zone_id        = aws_cloudfront_distribution.main.hosted_zone_id
    status                = aws_cloudfront_distribution.main.status
    hls_playback_url      = "https://${aws_cloudfront_distribution.main.domain_name}/out/v1/master.m3u8"
    dash_playback_url     = "https://${aws_cloudfront_distribution.main.domain_name}/out/v1/manifest.mpd"
    cmaf_playback_url     = var.enable_low_latency ? "https://${aws_cloudfront_distribution.main.domain_name}/out/v1/ll.m3u8" : null
  }
}

# S3 Storage Outputs
output "s3_storage" {
  description = "S3 bucket information for content storage and archives"
  value = {
    bucket_name           = aws_s3_bucket.storage.id
    bucket_arn           = aws_s3_bucket.storage.arn
    bucket_domain_name   = aws_s3_bucket.storage.bucket_domain_name
    website_endpoint     = var.create_web_player ? aws_s3_bucket_website_configuration.main[0].website_endpoint : null
    archive_prefix       = "archives/"
  }
}

# Web Player Outputs
output "web_player" {
  description = "Web player interface information"
  value = var.create_web_player ? {
    url         = "http://${aws_s3_bucket.storage.id}.s3-website.${var.aws_region}.amazonaws.com/"
    description = "Advanced HTML5 video player with adaptive bitrate support and real-time analytics"
  } : null
}

# IAM Role Outputs
output "iam_roles" {
  description = "IAM roles created for the streaming platform"
  value = {
    medialive_role = {
      name = aws_iam_role.medialive.name
      arn  = aws_iam_role.medialive.arn
    }
  }
}

# DRM and Security Outputs
output "drm_configuration" {
  description = "DRM and security configuration details"
  value = var.enable_drm ? {
    secret_arn     = aws_secretsmanager_secret.drm_key[0].arn
    secret_name    = aws_secretsmanager_secret.drm_key[0].name
    description    = "DRM encryption key for content protection"
  } : null
  sensitive = true
}

# Monitoring Outputs
output "monitoring" {
  description = "CloudWatch monitoring and alarm configuration"
  value = var.enable_monitoring ? {
    sns_topic_arn = var.alarm_email_endpoint != "" ? aws_sns_topic.alerts[0].arn : null
    alarms = {
      input_loss_alarm = aws_cloudwatch_metric_alarm.input_loss[0].alarm_name
      mediapackage_egress_alarm = aws_cloudwatch_metric_alarm.mediapackage_egress[0].alarm_name
      cloudfront_error_alarm = aws_cloudwatch_metric_alarm.cloudfront_errors[0].alarm_name
    }
  } : null
}

# Platform Features Summary
output "platform_features" {
  description = "Summary of enabled platform features and capabilities"
  value = {
    adaptive_bitrate_streaming = true
    supported_protocols = concat(
      ["HLS", "DASH"],
      var.enable_low_latency ? ["CMAF"] : []
    )
    video_qualities = concat(
      var.enable_4k_output ? ["4K (2160p)"] : [],
      var.enable_hd_outputs ? ["1080p", "720p"] : [],
      var.enable_sd_outputs ? ["480p", "240p"] : []
    )
    audio_formats = ["Stereo AAC", "5.1 Surround AAC"]
    drm_protection = var.enable_drm
    low_latency_streaming = var.enable_low_latency
    content_archiving = var.archive_enabled
    global_cdn = true
    real_time_monitoring = var.enable_monitoring
    web_player_interface = var.create_web_player
  }
}

# Cost Estimation
output "cost_estimation" {
  description = "Estimated monthly costs for the streaming platform (approximate)"
  value = {
    medialive_channel = "~$100-300/hour when running (varies by quality and features)"
    mediapackage = "~$0.08/GB egress + $0.065/hour per endpoint"
    cloudfront = "~$0.085/GB for first 10TB + edge location costs"
    s3_storage = "~$0.023/GB/month for Standard, plus data transfer costs"
    monitoring = "~$0.50/month for CloudWatch alarms"
    total_estimate = "Highly variable based on usage - can range from $50/month (minimal usage) to $10,000+/month (high traffic)"
    optimization_tips = [
      "Stop MediaLive channel when not streaming to avoid hourly charges",
      "Use S3 lifecycle policies to transition archived content to cheaper storage classes",
      "Consider CloudFront price class optimization for regional content delivery",
      "Monitor egress data transfer costs as they scale with viewer count"
    ]
  }
}

# Deployment Instructions
output "deployment_instructions" {
  description = "Next steps and usage instructions for the streaming platform"
  value = {
    channel_startup = var.auto_start_channel ? "MediaLive channel will start automatically" : "Run 'aws medialive start-channel --channel-id ${aws_medialive_channel.main.id}' to start streaming"
    rtmp_streaming = "Configure your streaming software (OBS Studio, etc.) with the RTMP URLs and stream key provided above"
    testing_playback = "Use the web player URL or playback URLs in your preferred video player to test streaming"
    production_considerations = [
      "Configure custom domain and SSL certificate for CloudFront",
      "Set up proper monitoring and alerting for production use",
      "Implement authentication and authorization for content access",
      "Configure backup streaming inputs for redundancy",
      "Test DRM implementation with your content protection requirements"
    ]
  }
}

# Network Configuration
output "network_configuration" {
  description = "Network configuration and firewall requirements"
  value = {
    required_outbound_ports = {
      "443"  = "HTTPS for AWS API calls and MediaPackage egress"
      "1935" = "RTMP for video ingestion"
      "80"   = "HTTP for web player and redirects"
    }
    allowed_inbound_cidrs = var.input_whitelist_cidrs
    internal_access_cidrs = var.internal_cidrs
    cdn_edge_locations = "Global (based on CloudFront price class: ${var.cloudfront_price_class})"
  }
}

# Resource Tags
output "resource_tags" {
  description = "Tags applied to all resources for management and billing"
  value = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "video-streaming-platforms-aws-elemental-medialive"
  }
}