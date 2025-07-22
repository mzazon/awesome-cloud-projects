# Data sources for current AWS account information
data "aws_caller_identity" "current" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  random_suffix = random_string.suffix.result
  
  # Resource names with random suffix
  flow_name_primary = "${local.name_prefix}-primary-${local.random_suffix}"
  flow_name_backup  = "${local.name_prefix}-backup-${local.random_suffix}"
  medialive_channel_name = "${local.name_prefix}-channel-${local.random_suffix}"
  mediapackage_channel_id = "${local.name_prefix}-package-${local.random_suffix}"
  iam_role_name = "MediaLiveAccessRole-${local.random_suffix}"
  
  # Availability zones
  primary_az = "${var.aws_region}${var.mediaconnect_availability_zones[0]}"
  backup_az  = "${var.aws_region}${var.mediaconnect_availability_zones[1]}"
  
  # Common tags
  common_tags = merge({
    Project     = var.project_name
    Environment = var.environment
    CreatedBy   = "terraform"
    Recipe      = "live-event-broadcasting-aws-elemental-mediaconnect"
  }, var.additional_tags)
}

# ==========================================
# IAM Role for MediaLive
# ==========================================

# Trust policy for MediaLive service
data "aws_iam_policy_document" "medialive_trust_policy" {
  statement {
    effect = "Allow"
    
    principals {
      type        = "Service"
      identifiers = ["medialive.amazonaws.com"]
    }
    
    actions = ["sts:AssumeRole"]
  }
}

# IAM role for MediaLive
resource "aws_iam_role" "medialive_role" {
  name               = local.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.medialive_trust_policy.json
  description        = "IAM role for MediaLive channel to access MediaConnect and MediaPackage"
  
  tags = local.common_tags
}

# Attach necessary policies to MediaLive role
resource "aws_iam_role_policy_attachment" "medialive_full_access" {
  role       = aws_iam_role.medialive_role.name
  policy_arn = "arn:aws:iam::aws:policy/MediaLiveFullAccess"
}

resource "aws_iam_role_policy_attachment" "mediaconnect_full_access" {
  role       = aws_iam_role.medialive_role.name
  policy_arn = "arn:aws:iam::aws:policy/MediaConnectFullAccess"
}

resource "aws_iam_role_policy_attachment" "mediapackage_full_access" {
  role       = aws_iam_role.medialive_role.name
  policy_arn = "arn:aws:iam::aws:policy/MediaPackageFullAccess"
}

# ==========================================
# MediaConnect Flows
# ==========================================

# Primary MediaConnect Flow
resource "aws_media_connect_flow" "primary_flow" {
  name             = local.flow_name_primary
  availability_zone = local.primary_az
  
  # Source configuration
  source {
    name              = "PrimarySource"
    protocol          = "rtp"
    ingest_port       = var.mediaconnect_primary_ingest_port
    description       = "Primary encoder input"
    whitelist_cidr    = join(",", var.mediaconnect_ingest_whitelist_cidrs)
    
    # Enable encryption if specified
    dynamic "encryption" {
      for_each = var.enable_flow_source_encryption ? [1] : []
      content {
        algorithm = "aes128"
        role_arn  = aws_iam_role.medialive_role.arn
      }
    }
  }
  
  tags = merge(local.common_tags, {
    Name = local.flow_name_primary
    Type = "primary"
  })
}

# Backup MediaConnect Flow
resource "aws_media_connect_flow" "backup_flow" {
  name             = local.flow_name_backup
  availability_zone = local.backup_az
  
  # Source configuration
  source {
    name              = "BackupSource"
    protocol          = "rtp"
    ingest_port       = var.mediaconnect_backup_ingest_port
    description       = "Backup encoder input"
    whitelist_cidr    = join(",", var.mediaconnect_ingest_whitelist_cidrs)
    
    # Enable encryption if specified
    dynamic "encryption" {
      for_each = var.enable_flow_source_encryption ? [1] : []
      content {
        algorithm = "aes128"
        role_arn  = aws_iam_role.medialive_role.arn
      }
    }
  }
  
  tags = merge(local.common_tags, {
    Name = local.flow_name_backup
    Type = "backup"
  })
}

# Primary flow output to MediaLive
resource "aws_media_connect_flow_output" "primary_output" {
  flow_arn    = aws_media_connect_flow.primary_flow.arn
  name        = "MediaLiveOutput"
  protocol    = "rtp-fec"
  destination = "0.0.0.0"
  port        = var.mediaconnect_output_port_primary
  description = "Output to MediaLive primary input"
}

# Backup flow output to MediaLive
resource "aws_media_connect_flow_output" "backup_output" {
  flow_arn    = aws_media_connect_flow.backup_flow.arn
  name        = "MediaLiveOutput"
  protocol    = "rtp-fec"
  destination = "0.0.0.0"
  port        = var.mediaconnect_output_port_backup
  description = "Output to MediaLive backup input"
}

# ==========================================
# MediaPackage Channel
# ==========================================

# MediaPackage channel for content distribution
resource "aws_media_package_channel" "live_channel" {
  channel_id  = local.mediapackage_channel_id
  description = "Live event broadcasting channel"
  
  tags = merge(local.common_tags, {
    Name = local.mediapackage_channel_id
  })
}

# MediaPackage HLS origin endpoint
resource "aws_media_package_origin_endpoint" "hls_endpoint" {
  channel_id = aws_media_package_channel.live_channel.channel_id
  endpoint_id = "${local.mediapackage_channel_id}-hls"
  description = "HLS endpoint for live event broadcasting"
  
  hls_package {
    ad_markers                = "NONE"
    include_iframe_only_stream = false
    playlist_type             = "EVENT"
    playlist_window_seconds   = var.mediapackage_playlist_window
    program_date_time_interval_seconds = 0
    segment_duration_seconds  = var.mediapackage_segment_duration
    
    stream_selection {
      max_video_bits_per_second = 2147483647
      min_video_bits_per_second = 0
      stream_order              = "ORIGINAL"
    }
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.mediapackage_channel_id}-hls"
  })
}

# ==========================================
# MediaLive Resources
# ==========================================

# Primary MediaLive input
resource "aws_medialive_input" "primary_input" {
  name = "${local.flow_name_primary}-input"
  type = "MEDIACONNECT"
  
  mediaconnect_flows {
    flow_arn = aws_media_connect_flow.primary_flow.arn
  }
  
  role_arn = aws_iam_role.medialive_role.arn
  
  tags = merge(local.common_tags, {
    Name = "${local.flow_name_primary}-input"
    Type = "primary"
  })
}

# Backup MediaLive input
resource "aws_medialive_input" "backup_input" {
  name = "${local.flow_name_backup}-input"
  type = "MEDIACONNECT"
  
  mediaconnect_flows {
    flow_arn = aws_media_connect_flow.backup_flow.arn
  }
  
  role_arn = aws_iam_role.medialive_role.arn
  
  tags = merge(local.common_tags, {
    Name = "${local.flow_name_backup}-input"
    Type = "backup"
  })
}

# MediaLive channel
resource "aws_medialive_channel" "live_channel" {
  name     = local.medialive_channel_name
  role_arn = aws_iam_role.medialive_role.arn
  
  # Input attachments
  input_attachments {
    input_attachment_name = "primary-input"
    input_id              = aws_medialive_input.primary_input.id
    
    input_settings {
      audio_selectors {
        name = "default"
        selector_settings {
          audio_pid_selection {
            pid = 256
          }
        }
      }
      
      video_selector {
        program_id = 1
      }
    }
  }
  
  input_attachments {
    input_attachment_name = "backup-input"
    input_id              = aws_medialive_input.backup_input.id
    
    input_settings {
      audio_selectors {
        name = "default"
        selector_settings {
          audio_pid_selection {
            pid = 256
          }
        }
      }
      
      video_selector {
        program_id = 1
      }
    }
  }
  
  # Destinations
  destinations {
    id = "mediapackage-destination"
    
    media_package_settings {
      channel_id = aws_media_package_channel.live_channel.channel_id
    }
  }
  
  # Encoder settings
  encoder_settings {
    # Audio descriptions
    audio_descriptions {
      audio_selector_name = "default"
      name                = "audio_1"
      
      codec_settings {
        aac_settings {
          bitrate        = var.medialive_audio_bitrate
          coding_mode    = "CODING_MODE_2_0"
          input_type     = "BROADCASTER_MIXED_AD"
          profile        = "LC"
          sample_rate    = 48000
        }
      }
    }
    
    # Video descriptions
    video_descriptions {
      name   = "video_720p30"
      width  = var.medialive_video_width
      height = var.medialive_video_height
      
      codec_settings {
        h264_settings {
          bitrate                 = var.medialive_video_bitrate
          framerate_control       = "SPECIFIED"
          framerate_denominator   = 1
          framerate_numerator     = var.medialive_framerate
          gop_b_reference         = "DISABLED"
          gop_closed_cadence      = 1
          gop_num_b_frames        = 2
          gop_size                = var.medialive_gop_size
          gop_size_units          = "FRAMES"
          level                   = "H264_LEVEL_4_1"
          look_ahead_rate_control = "MEDIUM"
          max_bitrate             = var.medialive_video_bitrate
          num_ref_frames          = 3
          par_control             = "INITIALIZE_FROM_SOURCE"
          profile                 = "MAIN"
          rate_control_mode       = "CBR"
          syntax                  = "DEFAULT"
        }
      }
    }
    
    # Output groups
    output_groups {
      name = "mediapackage-output-group"
      
      output_group_settings {
        media_package_group_settings {
          destination {
            destination_ref_id = "mediapackage-destination"
          }
        }
      }
      
      outputs {
        audio_description_names = ["audio_1"]
        output_name            = "720p30"
        video_description_name = "video_720p30"
        
        output_settings {
          media_package_output_settings {}
        }
      }
    }
  }
  
  # Input specification
  input_specification {
    codec           = "AVC"
    resolution      = "HD"
    maximum_bitrate = "MAX_10_MBPS"
  }
  
  tags = merge(local.common_tags, {
    Name = local.medialive_channel_name
  })
}

# ==========================================
# CloudWatch Monitoring
# ==========================================

# CloudWatch alarm for MediaConnect primary flow source errors
resource "aws_cloudwatch_metric_alarm" "primary_flow_source_errors" {
  alarm_name          = "${local.flow_name_primary}-source-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "SourceConnectionErrors"
  namespace           = "AWS/MediaConnect"
  period              = var.cloudwatch_alarm_period
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alert on MediaConnect primary flow source errors"
  alarm_actions       = []
  
  dimensions = {
    FlowName = aws_media_connect_flow.primary_flow.name
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.flow_name_primary}-source-errors"
  })
}

# CloudWatch alarm for MediaConnect backup flow source errors
resource "aws_cloudwatch_metric_alarm" "backup_flow_source_errors" {
  alarm_name          = "${local.flow_name_backup}-source-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "SourceConnectionErrors"
  namespace           = "AWS/MediaConnect"
  period              = var.cloudwatch_alarm_period
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alert on MediaConnect backup flow source errors"
  alarm_actions       = []
  
  dimensions = {
    FlowName = aws_media_connect_flow.backup_flow.name
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.flow_name_backup}-source-errors"
  })
}

# CloudWatch alarm for MediaLive channel input errors
resource "aws_cloudwatch_metric_alarm" "medialive_input_errors" {
  alarm_name          = "${local.medialive_channel_name}-input-errors"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "InputVideoFrameRate"
  namespace           = "AWS/MediaLive"
  period              = var.cloudwatch_alarm_period
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "Alert on MediaLive channel input errors"
  alarm_actions       = []
  
  dimensions = {
    ChannelId = aws_medialive_channel.live_channel.channel_id
  }
  
  tags = merge(local.common_tags, {
    Name = "${local.medialive_channel_name}-input-errors"
  })
}

# CloudWatch log groups for MediaConnect flows
resource "aws_cloudwatch_log_group" "primary_flow_logs" {
  name              = "/aws/mediaconnect/${local.flow_name_primary}"
  retention_in_days = 30
  
  tags = merge(local.common_tags, {
    Name = "/aws/mediaconnect/${local.flow_name_primary}"
  })
}

resource "aws_cloudwatch_log_group" "backup_flow_logs" {
  name              = "/aws/mediaconnect/${local.flow_name_backup}"
  retention_in_days = 30
  
  tags = merge(local.common_tags, {
    Name = "/aws/mediaconnect/${local.flow_name_backup}"
  })
}

# ==========================================
# Optional: Auto-start resources
# ==========================================

# Note: MediaConnect flows and MediaLive channels are created in IDLE state by default
# Starting them requires separate API calls which are not directly supported in Terraform
# Consider using aws_medialive_channel and aws_media_connect_flow resources with lifecycle rules
# or use AWS CLI commands in provisioners or separate deployment scripts