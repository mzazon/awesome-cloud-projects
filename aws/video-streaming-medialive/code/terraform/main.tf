# Main Terraform Configuration for Video Streaming Platform
# This file creates a comprehensive enterprise-grade video streaming platform using AWS services

# Local values for resource naming and configuration
locals {
  # Generate unique platform name with suffix
  platform_name = "${var.project_name}-${random_string.suffix.result}"
  
  # Common tags for all resources
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Recipe      = "video-streaming-platforms-aws-elemental-medialive"
  }

  # MediaLive channel name
  channel_name = var.channel_name != "" ? var.channel_name : "${local.platform_name}-live-channel"
  
  # MediaPackage channel name
  package_channel_name = var.package_channel_name != "" ? var.package_channel_name : "${local.platform_name}-package-channel"
}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 8
  upper   = false
  special = false
}

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

#------------------------------------------------------------------------------
# IAM ROLES AND POLICIES
#------------------------------------------------------------------------------

# IAM role for MediaLive service
resource "aws_iam_role" "medialive" {
  name = "MediaLivePlatformRole-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "medialive.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

# IAM policy for MediaLive with comprehensive permissions
resource "aws_iam_role_policy" "medialive" {
  name = "MediaLivePlatformPolicy"
  role = aws_iam_role.medialive.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "mediapackage:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.storage.arn,
          "${aws_s3_bucket.storage.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:CreateSecret"
        ]
        Resource = var.enable_drm ? [aws_secretsmanager_secret.drm_key[0].arn] : []
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
}

#------------------------------------------------------------------------------
# S3 STORAGE CONFIGURATION
#------------------------------------------------------------------------------

# S3 bucket for content storage and archives
resource "aws_s3_bucket" "storage" {
  bucket = "${local.platform_name}-storage"

  tags = merge(local.common_tags, {
    Purpose = "StreamingStorage"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "storage" {
  bucket = aws_s3_bucket.storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "storage" {
  count  = var.archive_enabled ? 1 : 0
  bucket = aws_s3_bucket.storage.id

  rule {
    id     = "streaming-content-lifecycle"
    status = "Enabled"

    filter {
      prefix = "archives/"
    }

    transition {
      days          = var.lifecycle_transitions.standard_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.lifecycle_transitions.glacier_days
      storage_class = "GLACIER"
    }

    transition {
      days          = var.lifecycle_transitions.deep_archive_days
      storage_class = "DEEP_ARCHIVE"
    }
  }

  depends_on = [aws_s3_bucket_versioning.storage]
}

# S3 bucket public access block (security)
resource "aws_s3_bucket_public_access_block" "storage" {
  bucket = aws_s3_bucket.storage.id

  block_public_acls       = false  # Allow for website hosting
  block_public_policy     = false  # Allow for website hosting
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# S3 bucket policy for website hosting (if web player is enabled)
resource "aws_s3_bucket_policy" "storage_policy" {
  count  = var.create_web_player ? 1 : 0
  bucket = aws_s3_bucket.storage.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.storage.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.storage]
}

# S3 bucket website configuration (if web player is enabled)
resource "aws_s3_bucket_website_configuration" "main" {
  count  = var.create_web_player ? 1 : 0
  bucket = aws_s3_bucket.storage.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }

  depends_on = [aws_s3_bucket_policy.storage_policy]
}

#------------------------------------------------------------------------------
# DRM AND SECURITY CONFIGURATION
#------------------------------------------------------------------------------

# DRM encryption key (if DRM is enabled)
resource "aws_secretsmanager_secret" "drm_key" {
  count       = var.enable_drm ? 1 : 0
  name        = "medialive-drm-key-${random_string.suffix.result}"
  description = "DRM encryption key for streaming platform"

  tags = merge(local.common_tags, {
    Purpose = "DRMProtection"
  })
}

# Generate random DRM key value
resource "random_password" "drm_key" {
  count   = var.enable_drm ? 1 : 0
  length  = 32
  special = true
}

# Store DRM key in Secrets Manager
resource "aws_secretsmanager_secret_version" "drm_key" {
  count     = var.enable_drm ? 1 : 0
  secret_id = aws_secretsmanager_secret.drm_key[0].id
  secret_string = jsonencode({
    key = base64encode(random_password.drm_key[0].result)
  })
}

#------------------------------------------------------------------------------
# MEDIALIVE INPUT SECURITY GROUPS
#------------------------------------------------------------------------------

# Public input security group for general access
resource "aws_medialive_input_security_group" "public" {
  whitelist_rules = [
    for cidr in var.input_whitelist_cidrs : {
      cidr = cidr
    }
  ]

  tags = merge(local.common_tags, {
    Name    = "StreamingPlatformSG-${random_string.suffix.result}"
    Purpose = "PublicAccess"
  })
}

# Internal input security group for professional equipment
resource "aws_medialive_input_security_group" "internal" {
  whitelist_rules = [
    for cidr in var.internal_cidrs : {
      cidr = cidr
    }
  ]

  tags = merge(local.common_tags, {
    Name    = "InternalStreamingSG-${random_string.suffix.result}"
    Purpose = "InternalAccess"
  })
}

#------------------------------------------------------------------------------
# MEDIALIVE INPUTS
#------------------------------------------------------------------------------

# RTMP Push input for live streaming
resource "aws_medialive_input" "rtmp" {
  name                  = "${local.platform_name}-rtmp-input"
  type                  = "RTMP_PUSH"
  input_security_groups = [aws_medialive_input_security_group.public.id]

  tags = merge(local.common_tags, {
    Name = "RTMPInput-${random_string.suffix.result}"
    Type = "Live"
  })
}

# HLS Pull input for remote sources
resource "aws_medialive_input" "hls" {
  name = "${local.platform_name}-hls-input"
  type = "URL_PULL"

  sources {
    url = "https://example.com/stream.m3u8"
  }

  tags = merge(local.common_tags, {
    Name = "HLSInput-${random_string.suffix.result}"
    Type = "Remote"
  })
}

# RTP Push input for professional equipment
resource "aws_medialive_input" "rtp" {
  name                  = "${local.platform_name}-rtp-input"
  type                  = "RTP_PUSH"
  input_security_groups = [aws_medialive_input_security_group.internal.id]

  tags = merge(local.common_tags, {
    Name = "RTPInput-${random_string.suffix.result}"
    Type = "Professional"
  })
}

#------------------------------------------------------------------------------
# MEDIAPACKAGE CHANNEL AND ENDPOINTS
#------------------------------------------------------------------------------

# MediaPackage channel for content origin
resource "aws_mediapackage_channel" "main" {
  channel_id  = local.package_channel_name
  description = "Enterprise streaming platform channel"

  tags = merge(local.common_tags, {
    Name = "StreamingChannel-${random_string.suffix.result}"
  })
}

# HLS endpoint with advanced features
resource "aws_mediapackage_origin_endpoint" "hls" {
  channel_id            = aws_mediapackage_channel.main.id
  endpoint_id           = "${local.package_channel_name}-hls-advanced"
  manifest_name         = "master.m3u8"
  startover_window_seconds = var.startover_window_seconds
  time_delay_seconds    = 10

  hls_package {
    segment_duration_seconds           = var.segment_duration_seconds
    playlist_type                     = "EVENT"
    playlist_window_seconds           = 300
    program_date_time_interval_seconds = 60
    ad_markers                        = "SCTE35_ENHANCED"
    include_iframe_only_stream        = true
    use_audio_rendition_group         = true
  }

  tags = merge(local.common_tags, {
    Type        = "HLS"
    Quality     = "Advanced"
  })
}

# DASH endpoint with DRM support
resource "aws_mediapackage_origin_endpoint" "dash" {
  channel_id            = aws_mediapackage_channel.main.id
  endpoint_id           = "${local.package_channel_name}-dash-drm"
  manifest_name         = "manifest.mpd"
  startover_window_seconds = var.startover_window_seconds
  time_delay_seconds    = 10

  dash_package {
    segment_duration_seconds               = var.segment_duration_seconds
    min_buffer_time_seconds               = 20
    min_update_period_seconds             = 10
    suggested_presentation_delay_seconds  = 30
    profile                               = "NONE"
    period_triggers                       = ["ADS"]
  }

  tags = merge(local.common_tags, {
    Type = "DASH"
    DRM  = "Enabled"
  })
}

# CMAF endpoint for low-latency streaming (if enabled)
resource "aws_mediapackage_origin_endpoint" "cmaf" {
  count       = var.enable_low_latency ? 1 : 0
  channel_id  = aws_mediapackage_channel.main.id
  endpoint_id = "${local.package_channel_name}-cmaf-ll"
  manifest_name = "index.m3u8"
  startover_window_seconds = 1800
  time_delay_seconds = 2

  cmaf_package {
    segment_duration_seconds = var.low_latency_segment_duration
    segment_prefix          = "segment"

    hls_manifests {
      id                               = "low-latency"
      manifest_name                   = "ll.m3u8"
      playlist_type                   = "EVENT"
      playlist_window_seconds         = 60
      program_date_time_interval_seconds = 60
      ad_markers                      = "SCTE35_ENHANCED"
    }
  }

  tags = merge(local.common_tags, {
    Type    = "CMAF"
    Latency = "Low"
  })
}

#------------------------------------------------------------------------------
# MEDIALIVE CHANNEL CONFIGURATION
#------------------------------------------------------------------------------

# MediaLive channel with comprehensive encoding settings
resource "aws_medialive_channel" "main" {
  name     = local.channel_name
  role_arn = aws_iam_role.medialive.arn

  input_specification {
    codec             = var.input_codec
    input_resolution  = var.input_resolution
    maximum_bitrate   = var.maximum_bitrate
  }

  # Primary RTMP input attachment
  input_attachments {
    input_attachment_name = "primary-rtmp"
    input_id             = aws_medialive_input.rtmp.id

    input_settings {
      source_end_behavior = "CONTINUE"
      input_filter        = "AUTO"
      filter_strength     = 1
      deblock_filter      = "ENABLED"
      denoise_filter      = "ENABLED"
    }
  }

  # Backup HLS input attachment
  input_attachments {
    input_attachment_name = "backup-hls"
    input_id             = aws_medialive_input.hls.id

    input_settings {
      source_end_behavior = "CONTINUE"
      input_filter        = "AUTO"
      filter_strength     = 1
    }
  }

  # MediaPackage destination
  destinations {
    id = "mediapackage-destination"

    media_package_settings {
      channel_id = aws_mediapackage_channel.main.id
    }
  }

  # S3 archive destination (if enabled)
  dynamic "destinations" {
    for_each = var.archive_enabled ? [1] : []
    content {
      id = "s3-archive-destination"

      s3_settings {
        bucket_name        = aws_s3_bucket.storage.id
        file_name_prefix   = "archives/"
        role_arn          = aws_iam_role.medialive.arn
      }
    }
  }

  encoder_settings {
    # Timecode configuration
    timecode_config {
      source = "EMBEDDED"
    }

    # Audio descriptions
    audio_descriptions {
      name                = "audio_stereo"
      audio_selector_name = "default"
      audio_type_control  = "FOLLOW_INPUT"
      language_code_control = "FOLLOW_INPUT"

      codec_settings {
        aac_settings {
          bitrate      = var.audio_bitrates.stereo
          coding_mode  = "CODING_MODE_2_0"
          sample_rate  = 48000
          spec         = "MPEG4"
        }
      }
    }

    audio_descriptions {
      name                = "audio_surround"
      audio_selector_name = "default"
      audio_type_control  = "FOLLOW_INPUT"
      language_code_control = "FOLLOW_INPUT"

      codec_settings {
        aac_settings {
          bitrate      = var.audio_bitrates.surround
          coding_mode  = "CODING_MODE_5_1"
          sample_rate  = 48000
          spec         = "MPEG4"
        }
      }
    }

    # Video descriptions for different quality levels
    dynamic "video_descriptions" {
      for_each = var.enable_4k_output ? [1] : []
      content {
        name   = "video_2160p"
        width  = 3840
        height = 2160

        codec_settings {
          h264_settings {
            bitrate                = var.video_bitrates.video_2160p
            framerate_control      = "SPECIFIED"
            framerate_numerator    = 30
            framerate_denominator  = 1
            gop_b_reference       = "ENABLED"
            gop_closed_cadence    = 1
            gop_num_b_frames      = 3
            gop_size              = 90
            gop_size_units        = "FRAMES"
            profile               = "HIGH"
            level                 = "H264_LEVEL_5_1"
            rate_control_mode     = "CBR"
            syntax                = "DEFAULT"
            adaptive_quantization = "HIGH"
            afd_signaling         = "NONE"
            color_metadata        = "INSERT"
            entropy_encoding      = "CABAC"
            flicker_aq           = "ENABLED"
            force_field_pictures  = "DISABLED"
            temporal_aq          = "ENABLED"
            spatial_aq           = "ENABLED"
          }
        }

        respond_to_afd    = "RESPOND"
        scaling_behavior  = "DEFAULT"
        sharpness        = 50
      }
    }

    dynamic "video_descriptions" {
      for_each = var.enable_hd_outputs ? [1] : []
      content {
        name   = "video_1080p"
        width  = 1920
        height = 1080

        codec_settings {
          h264_settings {
            bitrate                = var.video_bitrates.video_1080p
            framerate_control      = "SPECIFIED"
            framerate_numerator    = 30
            framerate_denominator  = 1
            gop_b_reference       = "ENABLED"
            gop_closed_cadence    = 1
            gop_num_b_frames      = 3
            gop_size              = 90
            gop_size_units        = "FRAMES"
            profile               = "HIGH"
            level                 = "H264_LEVEL_4_1"
            rate_control_mode     = "CBR"
            syntax                = "DEFAULT"
            adaptive_quantization = "HIGH"
            temporal_aq          = "ENABLED"
            spatial_aq           = "ENABLED"
          }
        }

        respond_to_afd    = "RESPOND"
        scaling_behavior  = "DEFAULT"
        sharpness        = 50
      }
    }

    dynamic "video_descriptions" {
      for_each = var.enable_hd_outputs ? [1] : []
      content {
        name   = "video_720p"
        width  = 1280
        height = 720

        codec_settings {
          h264_settings {
            bitrate                = var.video_bitrates.video_720p
            framerate_control      = "SPECIFIED"
            framerate_numerator    = 30
            framerate_denominator  = 1
            gop_b_reference       = "ENABLED"
            gop_closed_cadence    = 1
            gop_num_b_frames      = 2
            gop_size              = 90
            gop_size_units        = "FRAMES"
            profile               = "HIGH"
            level                 = "H264_LEVEL_3_1"
            rate_control_mode     = "CBR"
            syntax                = "DEFAULT"
            adaptive_quantization = "MEDIUM"
            temporal_aq          = "ENABLED"
            spatial_aq           = "ENABLED"
          }
        }

        respond_to_afd    = "RESPOND"
        scaling_behavior  = "DEFAULT"
        sharpness        = 50
      }
    }

    dynamic "video_descriptions" {
      for_each = var.enable_sd_outputs ? [1] : []
      content {
        name   = "video_480p"
        width  = 854
        height = 480

        codec_settings {
          h264_settings {
            bitrate                = var.video_bitrates.video_480p
            framerate_control      = "SPECIFIED"
            framerate_numerator    = 30
            framerate_denominator  = 1
            gop_b_reference       = "DISABLED"
            gop_closed_cadence    = 1
            gop_num_b_frames      = 2
            gop_size              = 90
            gop_size_units        = "FRAMES"
            profile               = "MAIN"
            level                 = "H264_LEVEL_3_0"
            rate_control_mode     = "CBR"
            syntax                = "DEFAULT"
            adaptive_quantization = "MEDIUM"
          }
        }

        respond_to_afd    = "RESPOND"
        scaling_behavior  = "DEFAULT"
        sharpness        = 50
      }
    }

    dynamic "video_descriptions" {
      for_each = var.enable_sd_outputs ? [1] : []
      content {
        name   = "video_240p"
        width  = 426
        height = 240

        codec_settings {
          h264_settings {
            bitrate                = var.video_bitrates.video_240p
            framerate_control      = "SPECIFIED"
            framerate_numerator    = 30
            framerate_denominator  = 1
            gop_b_reference       = "DISABLED"
            gop_closed_cadence    = 1
            gop_num_b_frames      = 1
            gop_size              = 90
            gop_size_units        = "FRAMES"
            profile               = "BASELINE"
            level                 = "H264_LEVEL_2_0"
            rate_control_mode     = "CBR"
            syntax                = "DEFAULT"
          }
        }

        respond_to_afd    = "RESPOND"
        scaling_behavior  = "DEFAULT"
        sharpness        = 50
      }
    }

    # MediaPackage output group
    output_groups {
      name = "MediaPackage-ABR"

      output_group_settings {
        media_package_group_settings {
          destination {
            destination_ref_id = "mediapackage-destination"
          }
        }
      }

      # 4K output
      dynamic "outputs" {
        for_each = var.enable_4k_output ? [1] : []
        content {
          output_name                = "4K-UHD"
          video_description_name     = "video_2160p"
          audio_description_names    = ["audio_surround"]

          output_settings {
            media_package_output_settings {}
          }
        }
      }

      # HD outputs
      dynamic "outputs" {
        for_each = var.enable_hd_outputs ? [1] : []
        content {
          output_name                = "1080p-HD"
          video_description_name     = "video_1080p"
          audio_description_names    = ["audio_stereo"]

          output_settings {
            media_package_output_settings {}
          }
        }
      }

      dynamic "outputs" {
        for_each = var.enable_hd_outputs ? [1] : []
        content {
          output_name                = "720p-HD"
          video_description_name     = "video_720p"
          audio_description_names    = ["audio_stereo"]

          output_settings {
            media_package_output_settings {}
          }
        }
      }

      # SD outputs
      dynamic "outputs" {
        for_each = var.enable_sd_outputs ? [1] : []
        content {
          output_name                = "480p-SD"
          video_description_name     = "video_480p"
          audio_description_names    = ["audio_stereo"]

          output_settings {
            media_package_output_settings {}
          }
        }
      }

      dynamic "outputs" {
        for_each = var.enable_sd_outputs ? [1] : []
        content {
          output_name                = "240p-Mobile"
          video_description_name     = "video_240p"
          audio_description_names    = ["audio_stereo"]

          output_settings {
            media_package_output_settings {}
          }
        }
      }
    }

    # S3 archive output group (if enabled)
    dynamic "output_groups" {
      for_each = var.archive_enabled ? [1] : []
      content {
        name = "S3-Archive"

        output_group_settings {
          archive_group_settings {
            destination {
              destination_ref_id = "s3-archive-destination"
            }
            rollover_interval = var.archive_rollover_interval
          }
        }

        outputs {
          output_name                = "archive-source"
          video_description_name     = var.enable_hd_outputs ? "video_1080p" : (var.enable_sd_outputs ? "video_480p" : "video_240p")
          audio_description_names    = ["audio_stereo"]

          output_settings {
            archive_output_settings {
              name_modifier = "-archive"
              extension     = "m2ts"
            }
          }
        }
      }
    }

    # Caption descriptions
    caption_descriptions {
      caption_selector_name = "default"
      name                 = "captions"
      language_code        = "en"
      language_description = "English"
    }
  }

  tags = merge(local.common_tags, {
    Service   = "StreamingPlatform"
    Component = "MediaLive"
  })
}

#------------------------------------------------------------------------------
# CLOUDFRONT DISTRIBUTION
#------------------------------------------------------------------------------

# CloudFront distribution for global content delivery
resource "aws_cloudfront_distribution" "main" {
  comment         = "Enterprise Video Streaming Platform Distribution"
  enabled         = true
  is_ipv6_enabled = var.enable_ipv6
  price_class     = var.cloudfront_price_class

  # Primary HLS origin
  origin {
    domain_name = replace(aws_mediapackage_origin_endpoint.hls.url, "https://", "")
    domain_name = split("/", local.hls_domain)[0]
    origin_id   = "MediaPackage-HLS-Primary"
    origin_path = "/${join("/", slice(split("/", replace(aws_mediapackage_origin_endpoint.hls.url, "https://", "")), 1, length(split("/", replace(aws_mediapackage_origin_endpoint.hls.url, "https://", ""))) - 1))}"

    custom_origin_config {
      http_port              = 443
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-MediaPackage-CDNIdentifier"
      value = "streaming-platform-${random_string.suffix.result}"
    }
  }

  # DASH origin
  origin {
    domain_name = split("/", replace(aws_mediapackage_origin_endpoint.dash.url, "https://", ""))[0]
    origin_id   = "MediaPackage-DASH-DRM"
    origin_path = "/${join("/", slice(split("/", replace(aws_mediapackage_origin_endpoint.dash.url, "https://", "")), 1, length(split("/", replace(aws_mediapackage_origin_endpoint.dash.url, "https://", ""))) - 1))}"

    custom_origin_config {
      http_port              = 443
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-MediaPackage-CDNIdentifier"
      value = "streaming-platform-${random_string.suffix.result}"
    }
  }

  # CMAF origin (if low latency is enabled)
  dynamic "origin" {
    for_each = var.enable_low_latency ? [1] : []
    content {
      domain_name = split("/", replace(aws_mediapackage_origin_endpoint.cmaf[0].url, "https://", ""))[0]
      origin_id   = "MediaPackage-CMAF-LowLatency"
      origin_path = "/${join("/", slice(split("/", replace(aws_mediapackage_origin_endpoint.cmaf[0].url, "https://", "")), 1, length(split("/", replace(aws_mediapackage_origin_endpoint.cmaf[0].url, "https://", ""))) - 1))}"

      custom_origin_config {
        http_port              = 443
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }

      custom_header {
        name  = "X-MediaPackage-CDNIdentifier"
        value = "streaming-platform-${random_string.suffix.result}"
      }
    }
  }

  # Default cache behavior for HLS content
  default_cache_behavior {
    target_origin_id       = "MediaPackage-HLS-Primary"
    viewer_protocol_policy = "redirect-to-https"
    compress              = true

    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"  # Managed-CachingOptimized
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"  # Managed-CORS-S3Origin

    min_ttl     = 0
    default_ttl = var.cloudfront_default_ttl
    max_ttl     = var.cloudfront_max_ttl
  }

  # Cache behavior for DASH manifests
  ordered_cache_behavior {
    path_pattern           = "*.mpd"
    target_origin_id       = "MediaPackage-DASH-DRM"
    viewer_protocol_policy = "redirect-to-https"
    compress              = true

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"

    min_ttl     = 0
    default_ttl = 5
    max_ttl     = 60
  }

  # Cache behavior for low latency manifests (if enabled)
  dynamic "ordered_cache_behavior" {
    for_each = var.enable_low_latency ? [1] : []
    content {
      path_pattern           = "*/ll.m3u8"
      target_origin_id       = "MediaPackage-CMAF-LowLatency"
      viewer_protocol_policy = "redirect-to-https"
      compress              = true

      allowed_methods = ["GET", "HEAD"]
      cached_methods  = ["GET", "HEAD"]

      cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
      origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"

      min_ttl     = 0
      default_ttl = 2
      max_ttl     = 10
    }
  }

  # Cache behavior for video segments
  ordered_cache_behavior {
    path_pattern           = "*.ts"
    target_origin_id       = "MediaPackage-HLS-Primary"
    viewer_protocol_policy = "redirect-to-https"
    compress              = false

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = merge(local.common_tags, {
    Service = "ContentDelivery"
  })
}

# Local variable to extract domain name from MediaPackage URL
locals {
  hls_domain = replace(aws_mediapackage_origin_endpoint.hls.url, "https://", "")
}

#------------------------------------------------------------------------------
# WEB PLAYER INTERFACE (Optional)
#------------------------------------------------------------------------------

# Web player HTML file (if enabled)
resource "aws_s3_object" "web_player" {
  count        = var.create_web_player ? 1 : 0
  bucket       = aws_s3_bucket.storage.id
  key          = "index.html"
  content_type = "text/html"
  cache_control = "max-age=300"

  content = templatefile("${path.module}/templates/player.html", {
    platform_name       = local.platform_name
    channel_id         = aws_medialive_channel.main.id
    distribution_id    = aws_cloudfront_distribution.main.id
    cloudfront_domain  = aws_cloudfront_distribution.main.domain_name
    player_title       = var.web_player_title
    random_suffix      = random_string.suffix.result
  })

  tags = merge(local.common_tags, {
    Purpose = "WebPlayer"
  })
}

#------------------------------------------------------------------------------
# MONITORING AND ALERTING (Optional)
#------------------------------------------------------------------------------

# SNS topic for alerts (if email endpoint is provided)
resource "aws_sns_topic" "alerts" {
  count = var.enable_monitoring && var.alarm_email_endpoint != "" ? 1 : 0
  name  = "streaming-platform-alerts-${random_string.suffix.result}"

  tags = local.common_tags
}

# SNS topic subscription for email alerts
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.enable_monitoring && var.alarm_email_endpoint != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email_endpoint
}

# CloudWatch alarm for MediaLive input loss
resource "aws_cloudwatch_metric_alarm" "input_loss" {
  count               = var.enable_monitoring ? 1 : 0
  alarm_name          = "MediaLive-${local.channel_name}-InputLoss"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "InputVideoFreeze"
  namespace           = "AWS/MediaLive"
  period              = "60"
  statistic           = "Maximum"
  threshold           = var.input_loss_threshold
  alarm_description   = "MediaLive channel input loss detection"
  treat_missing_data  = "breaching"

  dimensions = {
    ChannelId = aws_medialive_channel.main.id
  }

  alarm_actions = var.alarm_email_endpoint != "" ? [aws_sns_topic.alerts[0].arn] : []

  tags = local.common_tags
}

# CloudWatch alarm for MediaPackage egress errors
resource "aws_cloudwatch_metric_alarm" "mediapackage_egress" {
  count               = var.enable_monitoring ? 1 : 0
  alarm_name          = "MediaPackage-${local.package_channel_name}-EgressErrors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "EgressRequestCount"
  namespace           = "AWS/MediaPackage"
  period              = "300"
  statistic           = "Sum"
  threshold           = "100"
  alarm_description   = "MediaPackage egress error detection"

  dimensions = {
    Channel = aws_mediapackage_channel.main.id
  }

  alarm_actions = var.alarm_email_endpoint != "" ? [aws_sns_topic.alerts[0].arn] : []

  tags = local.common_tags
}

# CloudWatch alarm for CloudFront error rate
resource "aws_cloudwatch_metric_alarm" "cloudfront_errors" {
  count               = var.enable_monitoring ? 1 : 0
  alarm_name          = "CloudFront-${aws_cloudfront_distribution.main.id}-ErrorRate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = "300"
  statistic           = "Average"
  threshold           = var.error_rate_threshold
  alarm_description   = "CloudFront 4xx/5xx error rate monitoring"

  dimensions = {
    DistributionId = aws_cloudfront_distribution.main.id
  }

  alarm_actions = var.alarm_email_endpoint != "" ? [aws_sns_topic.alerts[0].arn] : []

  tags = local.common_tags
}