# Data sources for current AWS account and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  resource_suffix = lower(random_id.suffix.hex)
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
      Recipe      = "live-streaming-solutions-aws-elemental-medialive"
    },
    var.additional_tags
  )
}

# S3 bucket for archive storage and web hosting
resource "aws_s3_bucket" "streaming_storage" {
  bucket = "${var.resource_name_prefix}-${local.resource_suffix}"
  
  tags = merge(local.common_tags, {
    Name = "${var.resource_name_prefix}-storage-${local.resource_suffix}"
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "streaming_storage" {
  bucket = aws_s3_bucket.streaming_storage.id
  versioning_configuration {
    status = var.s3_enable_versioning ? "Enabled" : "Disabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "streaming_storage" {
  count  = var.s3_enable_server_side_encryption ? 1 : 0
  bucket = aws_s3_bucket.streaming_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "streaming_storage" {
  bucket = aws_s3_bucket.streaming_storage.id

  rule {
    id     = "archive_cleanup"
    status = "Enabled"

    expiration {
      days = var.s3_lifecycle_expiration_days
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "streaming_storage" {
  bucket = aws_s3_bucket.streaming_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket website configuration (for test player)
resource "aws_s3_bucket_website_configuration" "streaming_storage" {
  count  = var.create_test_resources ? 1 : 0
  bucket = aws_s3_bucket.streaming_storage.id

  index_document {
    suffix = "test-player.html"
  }
}

# IAM role for MediaLive
resource "aws_iam_role" "medialive_role" {
  name = "MediaLiveAccessRole-${local.resource_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "medialive.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "MediaLiveAccessRole-${local.resource_suffix}"
  })
}

# IAM policy attachment for MediaLive
resource "aws_iam_role_policy_attachment" "medialive_policy" {
  role       = aws_iam_role.medialive_role.name
  policy_arn = "arn:aws:iam::aws:policy/MediaLiveFullAccess"
}

# Additional IAM policy for S3 access
resource "aws_iam_role_policy" "medialive_s3_policy" {
  name = "MediaLiveS3Access-${local.resource_suffix}"
  role = aws_iam_role.medialive_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.streaming_storage.arn,
          "${aws_s3_bucket.streaming_storage.arn}/*"
        ]
      }
    ]
  })
}

# MediaLive input security group
resource "aws_medialive_input_security_group" "streaming_input_sg" {
  count = var.enable_input_security_group ? 1 : 0

  dynamic "whitelist_rules" {
    for_each = var.medialive_input_cidr_allow_list
    content {
      cidr = whitelist_rules.value
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.resource_name_prefix}-input-sg-${local.resource_suffix}"
  })
}

# MediaLive RTMP input
resource "aws_medialive_input" "streaming_input" {
  name                    = "${var.resource_name_prefix}-input-${local.resource_suffix}"
  type                    = var.medialive_input_type
  input_security_groups   = var.enable_input_security_group ? [aws_medialive_input_security_group.streaming_input_sg[0].id] : []

  tags = merge(local.common_tags, {
    Name = "${var.resource_name_prefix}-input-${local.resource_suffix}"
  })
}

# MediaPackage channel
resource "aws_media_package_channel" "streaming_channel" {
  channel_id  = "${var.resource_name_prefix}-package-${local.resource_suffix}"
  description = "Live streaming package channel"

  tags = merge(local.common_tags, {
    Name = "${var.resource_name_prefix}-package-${local.resource_suffix}"
  })
}

# MediaPackage HLS origin endpoint
resource "aws_media_package_origin_endpoint" "hls_endpoint" {
  channel_id    = aws_media_package_channel.streaming_channel.id
  endpoint_id   = "${var.resource_name_prefix}-hls-${local.resource_suffix}"
  manifest_name = "index.m3u8"
  description   = "HLS origin endpoint for live streaming"

  hls_package {
    segment_duration_seconds = var.segment_duration_seconds
    playlist_window_seconds  = var.playlist_window_seconds
    playlist_type           = "EVENT"
    
    stream_selection {
      stream_order = "ORIGINAL"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.resource_name_prefix}-hls-${local.resource_suffix}"
  })
}

# MediaPackage DASH origin endpoint
resource "aws_media_package_origin_endpoint" "dash_endpoint" {
  channel_id    = aws_media_package_channel.streaming_channel.id
  endpoint_id   = "${var.resource_name_prefix}-dash-${local.resource_suffix}"
  manifest_name = "index.mpd"
  description   = "DASH origin endpoint for live streaming"

  dash_package {
    segment_duration_seconds = var.segment_duration_seconds
    
    stream_selection {
      stream_order = "ORIGINAL"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.resource_name_prefix}-dash-${local.resource_suffix}"
  })
}

# MediaLive channel
resource "aws_medialive_channel" "streaming_channel" {
  name          = "${var.resource_name_prefix}-channel-${local.resource_suffix}"
  channel_class = var.medialive_channel_class
  role_arn      = aws_iam_role.medialive_role.arn

  input_specification {
    codec             = "AVC"
    input_resolution  = var.medialive_input_resolution
    maximum_bitrate   = var.medialive_input_max_bitrate
  }

  input_attachments {
    input_attachment_name = "primary-input"
    input_id             = aws_medialive_input.streaming_input.id
    
    input_settings {
      source_end_behavior = "CONTINUE"
    }
  }

  destinations {
    id = "destination1"
    
    media_package_settings {
      channel_id = aws_media_package_channel.streaming_channel.id
    }
  }

  encoder_settings {
    # Audio description
    audio_descriptions {
      audio_selector_name = "default"
      name               = "audio_1"
      
      codec_settings {
        aac_settings {
          bitrate      = var.audio_bitrate
          coding_mode  = "CODING_MODE_2_0"
          sample_rate  = var.audio_sample_rate
        }
      }
    }

    # Video descriptions for different resolutions
    video_descriptions {
      name = "video_1080p"
      
      codec_settings {
        h264_settings {
          bitrate                = var.video_bitrates.video_1080p
          framerate_control      = "SPECIFIED"
          framerate_numerator    = var.video_frame_rate
          framerate_denominator  = 1
          gop_b_reference        = "DISABLED"
          gop_closed_cadence     = 1
          gop_num_b_frames       = 2
          gop_size               = 90
          gop_size_units         = "FRAMES"
          profile                = "MAIN"
          rate_control_mode      = "CBR"
          syntax                 = "DEFAULT"
        }
      }
      
      width            = 1920
      height           = 1080
      respond_to_afd   = "NONE"
      sharpness        = 50
      scaling_behavior = "DEFAULT"
    }

    video_descriptions {
      name = "video_720p"
      
      codec_settings {
        h264_settings {
          bitrate                = var.video_bitrates.video_720p
          framerate_control      = "SPECIFIED"
          framerate_numerator    = var.video_frame_rate
          framerate_denominator  = 1
          gop_b_reference        = "DISABLED"
          gop_closed_cadence     = 1
          gop_num_b_frames       = 2
          gop_size               = 90
          gop_size_units         = "FRAMES"
          profile                = "MAIN"
          rate_control_mode      = "CBR"
          syntax                 = "DEFAULT"
        }
      }
      
      width            = 1280
      height           = 720
      respond_to_afd   = "NONE"
      sharpness        = 50
      scaling_behavior = "DEFAULT"
    }

    video_descriptions {
      name = "video_480p"
      
      codec_settings {
        h264_settings {
          bitrate                = var.video_bitrates.video_480p
          framerate_control      = "SPECIFIED"
          framerate_numerator    = var.video_frame_rate
          framerate_denominator  = 1
          gop_b_reference        = "DISABLED"
          gop_closed_cadence     = 1
          gop_num_b_frames       = 2
          gop_size               = 90
          gop_size_units         = "FRAMES"
          profile                = "MAIN"
          rate_control_mode      = "CBR"
          syntax                 = "DEFAULT"
        }
      }
      
      width            = 854
      height           = 480
      respond_to_afd   = "NONE"
      sharpness        = 50
      scaling_behavior = "DEFAULT"
    }

    # Output groups
    output_groups {
      name = "MediaPackage"
      
      output_group_settings {
        media_package_group_settings {
          destination {
            destination_ref_id = "destination1"
          }
        }
      }

      outputs {
        output_name                = "1080p"
        video_description_name     = "video_1080p"
        audio_description_names    = ["audio_1"]
        
        output_settings {
          media_package_output_settings {}
        }
      }

      outputs {
        output_name                = "720p"
        video_description_name     = "video_720p"
        audio_description_names    = ["audio_1"]
        
        output_settings {
          media_package_output_settings {}
        }
      }

      outputs {
        output_name                = "480p"
        video_description_name     = "video_480p"
        audio_description_names    = ["audio_1"]
        
        output_settings {
          media_package_output_settings {}
        }
      }
    }

    # Timecode configuration
    timecode_config {
      source = "EMBEDDED"
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.resource_name_prefix}-channel-${local.resource_suffix}"
  })
}

# CloudFront distribution for global content delivery
resource "aws_cloudfront_distribution" "streaming_distribution" {
  comment             = "Live streaming distribution"
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.m3u8"
  price_class         = var.cloudfront_price_class

  # HLS origin
  origin {
    domain_name = element(split("/", aws_media_package_origin_endpoint.hls_endpoint.url), 2)
    origin_id   = "MediaPackage-HLS"
    origin_path = "/${join("/", slice(split("/", aws_media_package_origin_endpoint.hls_endpoint.url), 3, length(split("/", aws_media_package_origin_endpoint.hls_endpoint.url))))}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # DASH origin
  origin {
    domain_name = element(split("/", aws_media_package_origin_endpoint.dash_endpoint.url), 2)
    origin_id   = "MediaPackage-DASH"
    origin_path = "/${join("/", slice(split("/", aws_media_package_origin_endpoint.dash_endpoint.url), 3, length(split("/", aws_media_package_origin_endpoint.dash_endpoint.url))))}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Default cache behavior for HLS
  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "MediaPackage-HLS"
    viewer_protocol_policy = "redirect-to-https"
    compress               = false

    forwarded_values {
      query_string = false
      headers      = ["*"]
      
      cookies {
        forward = "none"
      }
    }

    min_ttl     = var.cloudfront_cache_policy.min_ttl
    default_ttl = var.cloudfront_cache_policy.default_ttl
    max_ttl     = var.cloudfront_cache_policy.max_ttl
  }

  # Cache behavior for DASH manifests
  ordered_cache_behavior {
    path_pattern           = "*.mpd"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "MediaPackage-DASH"
    viewer_protocol_policy = "redirect-to-https"
    compress               = false

    forwarded_values {
      query_string = false
      headers      = ["*"]
      
      cookies {
        forward = "none"
      }
    }

    min_ttl     = var.cloudfront_cache_policy.min_ttl
    default_ttl = var.cloudfront_cache_policy.default_ttl
    max_ttl     = var.cloudfront_cache_policy.max_ttl
  }

  # Geographic restrictions
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # SSL certificate
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.resource_name_prefix}-distribution-${local.resource_suffix}"
  })
}

# SNS topic for notifications (if email is provided)
resource "aws_sns_topic" "medialive_alerts" {
  count = var.enable_cloudwatch_alarms && var.sns_notification_email != "" ? 1 : 0
  name  = "${var.resource_name_prefix}-alerts-${local.resource_suffix}"

  tags = merge(local.common_tags, {
    Name = "${var.resource_name_prefix}-alerts-${local.resource_suffix}"
  })
}

# SNS topic subscription
resource "aws_sns_topic_subscription" "medialive_email_alerts" {
  count     = var.enable_cloudwatch_alarms && var.sns_notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.medialive_alerts[0].arn
  protocol  = "email"
  endpoint  = var.sns_notification_email
}

# CloudWatch alarm for MediaLive channel errors
resource "aws_cloudwatch_metric_alarm" "medialive_channel_errors" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "MediaLive-${var.resource_name_prefix}-${local.resource_suffix}-Errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "4xxErrors"
  namespace           = "AWS/MediaLive"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "This metric monitors MediaLive channel errors"
  alarm_actions       = var.sns_notification_email != "" ? [aws_sns_topic.medialive_alerts[0].arn] : []

  dimensions = {
    ChannelId = aws_medialive_channel.streaming_channel.id
  }

  tags = merge(local.common_tags, {
    Name = "MediaLive-${var.resource_name_prefix}-${local.resource_suffix}-Errors"
  })
}

# CloudWatch alarm for input video freeze
resource "aws_cloudwatch_metric_alarm" "medialive_input_freeze" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "MediaLive-${var.resource_name_prefix}-${local.resource_suffix}-InputVideoFreeze"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "InputVideoFreeze"
  namespace           = "AWS/MediaLive"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0.5
  alarm_description   = "This metric monitors MediaLive input video freeze"
  alarm_actions       = var.sns_notification_email != "" ? [aws_sns_topic.medialive_alerts[0].arn] : []

  dimensions = {
    ChannelId = aws_medialive_channel.streaming_channel.id
  }

  tags = merge(local.common_tags, {
    Name = "MediaLive-${var.resource_name_prefix}-${local.resource_suffix}-InputVideoFreeze"
  })
}

# Test player HTML file (optional)
resource "aws_s3_object" "test_player" {
  count = var.create_test_resources ? 1 : 0
  
  bucket       = aws_s3_bucket.streaming_storage.bucket
  key          = "test-player.html"
  content_type = "text/html"
  
  content = templatefile("${path.module}/templates/test-player.html", {
    cloudfront_domain = aws_cloudfront_distribution.streaming_distribution.domain_name
  })

  tags = merge(local.common_tags, {
    Name = "test-player-${local.resource_suffix}"
  })
}

# Test player template file creation
resource "local_file" "test_player_template" {
  count    = var.create_test_resources ? 1 : 0
  filename = "${path.module}/templates/test-player.html"
  
  content = <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Live Stream Test Player</title>
    <script src="https://vjs.zencdn.net/8.0.4/video.js"></script>
    <link href="https://vjs.zencdn.net/8.0.4/video-js.css" rel="stylesheet">
</head>
<body>
    <h1>Live Stream Test Player</h1>
    <video
        id="live-player"
        class="video-js"
        controls
        preload="auto"
        width="1280"
        height="720"
        data-setup="{}">
        <source src="https://${cloudfront_domain}/out/v1/index.m3u8" type="application/x-mpegURL">
        <p class="vjs-no-js">
            To view this video please enable JavaScript, and consider upgrading to a web browser that
            <a href="https://videojs.com/html5-video-support/" target="_blank">supports HTML5 video</a>.
        </p>
    </video>
    <script>
        var player = videojs('live-player');
    </script>
</body>
</html>
EOF

  depends_on = [aws_cloudfront_distribution.streaming_distribution]
}