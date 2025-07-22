# DRM-Protected Video Streaming Infrastructure
# Complete Infrastructure as Code for AWS Elemental MediaPackage with DRM

# Generate unique resource identifiers
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ============================================================================
# KMS KEY AND ENCRYPTION INFRASTRUCTURE
# ============================================================================

# KMS key for DRM content encryption
resource "aws_kms_key" "drm_content_key" {
  description              = "DRM content encryption key for video streaming"
  key_usage               = "ENCRYPT_DECRYPT"
  key_spec                = "SYMMETRIC_DEFAULT"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow DRM Services"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "medialive.amazonaws.com",
            "secretsmanager.amazonaws.com"
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.additional_tags, {
    Name        = "${var.project_name}-drm-key-${random_string.suffix.result}"
    Component   = "Security"
    Purpose     = "DRM-Content-Encryption"
  })
}

# KMS key alias for easier reference
resource "aws_kms_alias" "drm_content_key_alias" {
  name          = "alias/${var.project_name}-drm-content-${random_string.suffix.result}"
  target_key_id = aws_kms_key.drm_content_key.key_id
}

# ============================================================================
# SECRETS MANAGER FOR DRM CONFIGURATION
# ============================================================================

# Secrets Manager secret for DRM configuration
resource "aws_secretsmanager_secret" "drm_config" {
  name                    = "${var.project_name}-drm-config-${random_string.suffix.result}"
  description             = "DRM configuration and provider settings"
  kms_key_id             = aws_kms_key.drm_content_key.arn
  recovery_window_in_days = 0 # Immediate deletion for development

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-drm-config-${random_string.suffix.result}"
    Component = "Security"
    Purpose   = "DRM-Configuration"
  })
}

# DRM configuration secret version
resource "aws_secretsmanager_secret_version" "drm_config" {
  secret_id = aws_secretsmanager_secret.drm_config.id
  secret_string = jsonencode({
    widevine_provider             = var.drm_config.widevine_provider
    playready_provider            = var.drm_config.playready_provider
    fairplay_provider             = var.drm_config.fairplay_provider
    content_id_template           = var.drm_config.content_id_template
    key_rotation_interval_seconds = var.drm_config.key_rotation_interval_seconds
    license_duration_seconds      = var.drm_config.license_duration_seconds
  })
}

# ============================================================================
# SPEKE KEY PROVIDER LAMBDA FUNCTION
# ============================================================================

# IAM role for SPEKE Lambda function
resource "aws_iam_role" "speke_lambda_role" {
  name = "${var.project_name}-speke-lambda-role-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-speke-lambda-role-${random_string.suffix.result}"
    Component = "SPEKE-Provider"
    Purpose   = "Lambda-Execution"
  })
}

# Lambda basic execution policy attachment
resource "aws_iam_role_policy_attachment" "speke_lambda_basic_execution" {
  role       = aws_iam_role.speke_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for Secrets Manager and KMS access
resource "aws_iam_role_policy" "speke_lambda_secrets_policy" {
  name = "SecretsManagerAccessPolicy"
  role = aws_iam_role.speke_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.drm_config.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.drm_content_key.arn
      }
    ]
  })
}

# SPEKE Lambda function source code
data "archive_file" "speke_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/speke_provider.zip"
  
  source {
    content = <<EOF
import json
import boto3
import base64
import uuid
import os
from datetime import datetime, timedelta

def lambda_handler(event, context):
    print(f"SPEKE request: {json.dumps(event, indent=2)}")
    
    # Parse SPEKE request
    if 'body' in event:
        body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
    else:
        body = event
    
    # Extract content ID and DRM systems
    content_id = body.get('content_id', str(uuid.uuid4()))
    drm_systems = body.get('drm_systems', [])
    
    # Initialize response
    response = {
        "content_id": content_id,
        "drm_systems": []
    }
    
    # Generate keys for each requested DRM system
    for drm_system in drm_systems:
        system_id = drm_system.get('system_id')
        
        if system_id == 'edef8ba9-79d6-4ace-a3c8-27dcd51d21ed':  # Widevine
            drm_response = generate_widevine_keys(content_id)
        elif system_id == '9a04f079-9840-4286-ab92-e65be0885f95':  # PlayReady  
            drm_response = generate_playready_keys(content_id)
        elif system_id == '94ce86fb-07ff-4f43-adb8-93d2fa968ca2':  # FairPlay
            drm_response = generate_fairplay_keys(content_id)
        else:
            continue
        
        response['drm_systems'].append(drm_response)
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(response)
    }

def generate_widevine_keys(content_id):
    # Generate 16-byte content key
    content_key = os.urandom(16)
    key_id = os.urandom(16)
    
    return {
        "system_id": "edef8ba9-79d6-4ace-a3c8-27dcd51d21ed",
        "key_id": base64.b64encode(key_id).decode('utf-8'),
        "content_key": base64.b64encode(content_key).decode('utf-8'),
        "url": f"https://proxy.uat.widevine.com/proxy?provider=widevine_test",
        "pssh": generate_widevine_pssh(key_id)
    }

def generate_playready_keys(content_id):
    content_key = os.urandom(16)
    key_id = os.urandom(16)
    
    return {
        "system_id": "9a04f079-9840-4286-ab92-e65be0885f95", 
        "key_id": base64.b64encode(key_id).decode('utf-8'),
        "content_key": base64.b64encode(content_key).decode('utf-8'),
        "url": f"https://playready-license.test.com/rightsmanager.asmx",
        "pssh": generate_playready_pssh(key_id, content_key)
    }

def generate_fairplay_keys(content_id):
    content_key = os.urandom(16) 
    key_id = os.urandom(16)
    iv = os.urandom(16)
    
    return {
        "system_id": "94ce86fb-07ff-4f43-adb8-93d2fa968ca2",
        "key_id": base64.b64encode(key_id).decode('utf-8'),
        "content_key": base64.b64encode(content_key).decode('utf-8'),
        "url": f"skd://fairplay-license.test.com/license",
        "certificate_url": f"https://fairplay-license.test.com/cert",
        "iv": base64.b64encode(iv).decode('utf-8')
    }

def generate_widevine_pssh(key_id):
    # Simplified Widevine PSSH generation
    pssh_data = {
        "key_ids": [base64.b64encode(key_id).decode('utf-8')],
        "provider": "widevine_test",
        "content_id": base64.b64encode(key_id).decode('utf-8')
    }
    return base64.b64encode(json.dumps(pssh_data).encode()).decode('utf-8')

def generate_playready_pssh(key_id, content_key):
    # Simplified PlayReady PSSH generation
    pssh_data = f"""
    <WRMHEADER xmlns="http://schemas.microsoft.com/DRM/2007/03/PlayReadyHeader" version="4.0.0.0">
        <DATA>
            <PROTECTINFO>
                <KEYLEN>16</KEYLEN>
                <ALGID>AESCTR</ALGID>
            </PROTECTINFO>
            <KID>{base64.b64encode(key_id).decode('utf-8')}</KID>
            <CHECKSUM></CHECKSUM>
        </DATA>
    </WRMHEADER>
    """
    return base64.b64encode(pssh_data.encode()).decode('utf-8')
EOF
    filename = "speke_provider.py"
  }
}

# SPEKE Lambda function
resource "aws_lambda_function" "speke_provider" {
  filename         = data.archive_file.speke_lambda_zip.output_path
  function_name    = "${var.project_name}-speke-provider-${random_string.suffix.result}"
  role            = aws_iam_role.speke_lambda_role.arn
  handler         = "speke_provider.lambda_handler"
  source_code_hash = data.archive_file.speke_lambda_zip.output_base64sha256
  runtime         = var.lambda_config.runtime
  timeout         = var.lambda_config.timeout
  memory_size     = var.lambda_config.memory_size

  environment {
    variables = {
      DRM_SECRET_ARN = aws_secretsmanager_secret.drm_config.arn
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.speke_lambda_basic_execution,
    aws_iam_role_policy.speke_lambda_secrets_policy,
    aws_cloudwatch_log_group.speke_lambda_logs
  ]

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-speke-provider-${random_string.suffix.result}"
    Component = "SPEKE-Provider"
    Purpose   = "DRM-Key-Generation"
  })
}

# CloudWatch log group for SPEKE Lambda
resource "aws_cloudwatch_log_group" "speke_lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-speke-provider-${random_string.suffix.result}"
  retention_in_days = 14

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-speke-logs-${random_string.suffix.result}"
    Component = "SPEKE-Provider"
    Purpose   = "Lambda-Logging"
  })
}

# Lambda function URL for SPEKE endpoint
resource "aws_lambda_function_url" "speke_endpoint" {
  function_name      = aws_lambda_function.speke_provider.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["*"]
    max_age          = 86400
  }
}

# ============================================================================
# MEDIALIVE INFRASTRUCTURE
# ============================================================================

# MediaLive input security group
resource "aws_medialive_input_security_group" "drm_security_group" {
  whitelist_rules {
    cidr = var.network_config.allowed_cidr_blocks
  }

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-security-group-${random_string.suffix.result}"
    Component = "MediaLive"
    Purpose   = "Input-Security"
  })
}

# MediaLive RTMP input
resource "aws_medialive_input" "drm_input" {
  name                  = "${var.project_name}-input-${random_string.suffix.result}"
  input_security_groups = [aws_medialive_input_security_group.drm_security_group.id]
  type                  = "RTMP_PUSH"

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-input-${random_string.suffix.result}"
    Component = "MediaLive"
    Purpose   = "Video-Ingestion"
  })
}

# IAM role for MediaLive channel
resource "aws_iam_role" "medialive_drm_role" {
  name = "${var.project_name}-medialive-role-${random_string.suffix.result}"

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

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-medialive-role-${random_string.suffix.result}"
    Component = "MediaLive"
    Purpose   = "Channel-Execution"
  })
}

# MediaLive DRM policy
resource "aws_iam_role_policy" "medialive_drm_policy" {
  name = "MediaLiveDRMPolicy"
  role = aws_iam_role.medialive_drm_role.id

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
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.drm_config.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.drm_content_key.arn
      }
    ]
  })
}

# ============================================================================
# MEDIAPACKAGE INFRASTRUCTURE  
# ============================================================================

# MediaPackage channel
resource "aws_media_package_channel" "drm_channel" {
  channel_id  = "${var.project_name}-channel-${random_string.suffix.result}"
  description = "DRM-protected streaming channel"

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-channel-${random_string.suffix.result}"
    Component = "MediaPackage"
    Purpose   = "Content-Packaging"
  })
}

# HLS endpoint with DRM protection
resource "aws_media_package_origin_endpoint" "hls_drm_endpoint" {
  channel_id  = aws_media_package_channel.drm_channel.id
  endpoint_id = "${var.project_name}-hls-drm-${random_string.suffix.result}"
  description = "HLS endpoint with multi-DRM protection"

  hls_package {
    segment_duration_seconds = var.mediapackage_config.segment_duration_seconds
    playlist_type           = var.mediapackage_config.playlist_type
    playlist_window_seconds = var.mediapackage_config.playlist_window_seconds
    program_date_time_interval_seconds = 60
    ad_markers = "SCTE35_ENHANCED"
    include_iframe_only_stream = false
    use_audio_rendition_group = true

    encryption {
      key_rotation_interval_seconds = var.mediapackage_config.key_rotation_interval

      speke_key_provider {
        url         = aws_lambda_function_url.speke_endpoint.function_url
        resource_id = "${aws_media_package_channel.drm_channel.id}-hls"
        system_ids = [
          var.mediapackage_config.drm_systems.widevine_system_id,
          var.mediapackage_config.drm_systems.playready_system_id,
          var.mediapackage_config.drm_systems.fairplay_system_id
        ]
      }
    }
  }

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-hls-drm-${random_string.suffix.result}"
    Component = "MediaPackage"
    Purpose   = "HLS-DRM-Delivery"
    Type      = "HLS"
    DRM       = "MultiDRM"
  })
}

# DASH endpoint with DRM protection
resource "aws_media_package_origin_endpoint" "dash_drm_endpoint" {
  channel_id  = aws_media_package_channel.drm_channel.id
  endpoint_id = "${var.project_name}-dash-drm-${random_string.suffix.result}"
  description = "DASH endpoint with multi-DRM protection"

  dash_package {
    segment_duration_seconds = var.mediapackage_config.segment_duration_seconds
    min_buffer_time_seconds = 30
    min_update_period_seconds = 15
    suggested_presentation_delay_seconds = 30
    profile = "NONE"
    period_triggers = ["ADS"]

    encryption {
      key_rotation_interval_seconds = var.mediapackage_config.key_rotation_interval

      speke_key_provider {
        url         = aws_lambda_function_url.speke_endpoint.function_url
        resource_id = "${aws_media_package_channel.drm_channel.id}-dash"
        system_ids = [
          var.mediapackage_config.drm_systems.widevine_system_id,
          var.mediapackage_config.drm_systems.playready_system_id
        ]
      }
    }
  }

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-dash-drm-${random_string.suffix.result}"
    Component = "MediaPackage"
    Purpose   = "DASH-DRM-Delivery"
    Type      = "DASH"
    DRM       = "MultiDRM"
  })
}

# ============================================================================
# MEDIALIVE CHANNEL
# ============================================================================

# MediaLive channel with DRM configuration
resource "aws_medialive_channel" "drm_channel" {
  name     = "${var.project_name}-channel-${random_string.suffix.result}"
  role_arn = aws_iam_role.medialive_drm_role.arn

  input_specification {
    codec           = var.medialive_config.input_specification.codec
    resolution      = var.medialive_config.input_specification.resolution
    maximum_bitrate = var.medialive_config.input_specification.maximum_bitrate
  }

  input_attachments {
    input_attachment_name = "primary-input"
    input_id             = aws_medialive_input.drm_input.id

    input_settings {
      source_end_behavior = "CONTINUE"
      input_filter        = "AUTO"
      filter_strength     = 1
      deblock_filter      = "ENABLED"
      denoise_filter      = "ENABLED"
    }
  }

  destinations {
    id = "mediapackage-drm-destination"

    media_package_settings {
      channel_id = aws_media_package_channel.drm_channel.id
    }
  }

  encoder_settings {
    # Audio description
    audio_descriptions {
      name                = "audio_aac"
      audio_selector_name = "default"
      audio_type_control  = "FOLLOW_INPUT"
      language_code_control = "FOLLOW_INPUT"

      codec_settings {
        aac_settings {
          bitrate      = var.medialive_config.audio_config.bitrate
          coding_mode  = var.medialive_config.audio_config.coding_mode
          sample_rate  = var.medialive_config.audio_config.sample_rate
          spec         = "MPEG4"
        }
      }
    }

    # Video descriptions for each quality tier
    dynamic "video_descriptions" {
      for_each = var.medialive_config.video_quality_tiers
      content {
        name   = "video_${video_descriptions.value.name}_drm"
        width  = video_descriptions.value.width
        height = video_descriptions.value.height

        codec_settings {
          h264_settings {
            bitrate                 = video_descriptions.value.bitrate
            framerate_control       = "SPECIFIED"
            framerate_numerator     = 30
            framerate_denominator   = 1
            gop_b_reference         = video_descriptions.value.name == "480p" ? "DISABLED" : "ENABLED"
            gop_closed_cadence      = 1
            gop_num_b_frames        = video_descriptions.value.name == "480p" ? 2 : 3
            gop_size                = 90
            gop_size_units          = "FRAMES"
            profile                 = video_descriptions.value.profile
            level                   = video_descriptions.value.level
            rate_control_mode       = "CBR"
            syntax                  = "DEFAULT"
            adaptive_quantization   = video_descriptions.value.name == "1080p" ? "HIGH" : "MEDIUM"
            color_metadata          = video_descriptions.value.name == "1080p" ? "INSERT" : "IGNORE"
            entropy_encoding        = video_descriptions.value.name != "480p" ? "CABAC" : "CAVLC"
            flicker_aq             = video_descriptions.value.name != "480p" ? "ENABLED" : "DISABLED"
            force_field_pictures    = "DISABLED"
            temporal_aq            = video_descriptions.value.name != "480p" ? "ENABLED" : "DISABLED"
            spatial_aq             = video_descriptions.value.name != "480p" ? "ENABLED" : "DISABLED"
          }
        }

        respond_to_afd    = "RESPOND"
        scaling_behavior  = "DEFAULT"
        sharpness        = 50
      }
    }

    # Output group for MediaPackage
    output_groups {
      name = "MediaPackage-DRM-ABR"

      output_group_settings {
        media_package_group_settings {
          destination {
            destination_ref_id = "mediapackage-drm-destination"
          }
        }
      }

      # Dynamic outputs for each quality tier
      dynamic "outputs" {
        for_each = var.medialive_config.video_quality_tiers
        content {
          output_name                = "${outputs.value.name}-protected"
          video_description_name     = "video_${outputs.value.name}_drm"
          audio_description_names    = ["audio_aac"]

          output_settings {
            media_package_output_settings {}
          }
        }
      }
    }

    timecode_config {
      source = "EMBEDDED"
    }
  }

  depends_on = [
    aws_media_package_channel.drm_channel,
    aws_iam_role_policy.medialive_drm_policy
  ]

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-channel-${random_string.suffix.result}"
    Component = "MediaLive"
    Purpose   = "DRM-Protected-Encoding"
    Service   = "DRM-Protected-Streaming"
  })
}

# ============================================================================
# CLOUDFRONT DISTRIBUTION
# ============================================================================

# CloudFront distribution for DRM content delivery
resource "aws_cloudfront_distribution" "drm_distribution" {
  comment             = "DRM-protected content distribution with geo-restrictions"
  enabled             = true
  http_version        = "http2"
  is_ipv6_enabled     = true
  price_class         = var.cloudfront_config.price_class
  wait_for_deployment = false

  # Primary origin for HLS DRM content
  origin {
    domain_name = replace(aws_media_package_origin_endpoint.hls_drm_endpoint.url, "https://", "")
    origin_id   = "MediaPackage-HLS-DRM"
    origin_path = replace(
      replace(aws_media_package_origin_endpoint.hls_drm_endpoint.url, "https://", ""),
      "/[^/]*$", ""
    )

    custom_origin_config {
      http_port              = 443
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-MediaPackage-CDNIdentifier"
      value = "drm-protected-${random_string.suffix.result}"
    }
  }

  # Secondary origin for DASH DRM content
  origin {
    domain_name = replace(aws_media_package_origin_endpoint.dash_drm_endpoint.url, "https://", "")
    origin_id   = "MediaPackage-DASH-DRM"
    origin_path = replace(
      replace(aws_media_package_origin_endpoint.dash_drm_endpoint.url, "https://", ""),
      "/[^/]*$", ""
    )

    custom_origin_config {
      http_port              = 443
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-MediaPackage-CDNIdentifier"
      value = "drm-protected-${random_string.suffix.result}"
    }
  }

  # Default cache behavior (HLS)
  default_cache_behavior {
    target_origin_id       = "MediaPackage-HLS-DRM"
    viewer_protocol_policy = var.cloudfront_config.viewer_protocol_policy
    compress               = false
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingOptimized
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf" # Managed-CORS-S3Origin

    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]

    min_ttl     = 0
    default_ttl = var.cloudfront_config.cache_policies.manifest_default_ttl
    max_ttl     = var.cloudfront_config.cache_policies.manifest_max_ttl
  }

  # Cache behavior for DASH manifests
  ordered_cache_behavior {
    path_pattern           = "*.mpd"
    target_origin_id       = "MediaPackage-DASH-DRM"
    viewer_protocol_policy = var.cloudfront_config.viewer_protocol_policy
    compress               = false
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    min_ttl     = 0
    default_ttl = var.cloudfront_config.cache_policies.manifest_default_ttl
    max_ttl     = var.cloudfront_config.cache_policies.manifest_max_ttl
  }

  # Cache behavior for license requests (no caching)
  ordered_cache_behavior {
    path_pattern           = "*/license/*"
    target_origin_id       = "MediaPackage-HLS-DRM"
    viewer_protocol_policy = var.cloudfront_config.viewer_protocol_policy
    compress               = false
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"

    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]

    min_ttl     = var.cloudfront_config.cache_policies.license_default_ttl
    default_ttl = var.cloudfront_config.cache_policies.license_default_ttl
    max_ttl     = var.cloudfront_config.cache_policies.license_max_ttl
  }

  # Geographic restrictions
  restrictions {
    geo_restriction {
      restriction_type = var.cloudfront_config.geographic_restrictions.restriction_type
      locations        = var.cloudfront_config.geographic_restrictions.locations
    }
  }

  # SSL certificate configuration
  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = var.cloudfront_config.minimum_protocol_version
  }

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-distribution-${random_string.suffix.result}"
    Component = "CloudFront"
    Purpose   = "DRM-Content-Delivery"
  })
}

# ============================================================================
# S3 BUCKET FOR TEST CONTENT
# ============================================================================

# S3 bucket for test content and DRM player
resource "aws_s3_bucket" "test_content" {
  bucket        = "${var.project_name}-test-content-${random_string.suffix.result}"
  force_destroy = var.s3_config.force_destroy

  tags = merge(var.additional_tags, {
    Name      = "${var.project_name}-test-content-${random_string.suffix.result}"
    Component = "Testing"
    Purpose   = "Test-Content-Storage"
  })
}

# S3 bucket website configuration
resource "aws_s3_bucket_website_configuration" "test_content" {
  count  = var.s3_config.enable_website_hosting ? 1 : 0
  bucket = aws_s3_bucket.test_content.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "test_content" {
  bucket = aws_s3_bucket.test_content.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# S3 bucket policy for website hosting
resource "aws_s3_bucket_policy" "test_content" {
  count      = var.s3_config.enable_website_hosting ? 1 : 0
  bucket     = aws_s3_bucket.test_content.id
  depends_on = [aws_s3_bucket_public_access_block.test_content]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.test_content.arn}/*"
      }
    ]
  })
}