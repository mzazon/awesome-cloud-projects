# Adaptive Bitrate Streaming Infrastructure with MediaConvert and CloudFront
# This configuration creates a complete ABR streaming solution including:
# - S3 buckets for source and output content
# - MediaConvert job template for ABR transcoding
# - Lambda function for automated processing
# - CloudFront distribution for global delivery
# - IAM roles and policies with least privilege access

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get MediaConvert endpoint for the current region
data "aws_mediaconvert_endpoints" "default" {}

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and configuration
locals {
  random_suffix          = random_string.suffix.result
  source_bucket_name     = var.source_bucket_name != "" ? var.source_bucket_name : "${var.project_name}-source-${local.random_suffix}"
  output_bucket_name     = var.output_bucket_name != "" ? var.output_bucket_name : "${var.project_name}-output-${local.random_suffix}"
  lambda_function_name   = "${var.project_name}-processor-${local.random_suffix}"
  mediaconvert_role_name = "${var.project_name}-mediaconvert-role-${local.random_suffix}"
  job_template_name      = "${var.project_name}-abr-template-${local.random_suffix}"
  
  # Common tags for all resources
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    Component   = "adaptive-bitrate-streaming"
  })
}

#------------------------------------------------------------------------------
# S3 BUCKETS FOR VIDEO STORAGE
#------------------------------------------------------------------------------

# S3 bucket for source video files
resource "aws_s3_bucket" "source" {
  bucket = local.source_bucket_name

  tags = merge(local.common_tags, {
    Name        = "Source Video Bucket"
    Description = "Stores original video files for ABR processing"
  })
}

# S3 bucket versioning for source bucket
resource "aws_s3_bucket_versioning" "source" {
  bucket = aws_s3_bucket.source.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption for source bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "source" {
  bucket = aws_s3_bucket.source.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access to source bucket
resource "aws_s3_bucket_public_access_block" "source" {
  bucket = aws_s3_bucket.source.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket for processed ABR output files
resource "aws_s3_bucket" "output" {
  bucket = local.output_bucket_name

  tags = merge(local.common_tags, {
    Name        = "ABR Output Bucket"
    Description = "Stores processed ABR streaming content"
  })
}

# S3 bucket versioning for output bucket
resource "aws_s3_bucket_versioning" "output" {
  bucket = aws_s3_bucket.output.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption for output bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "output" {
  bucket = aws_s3_bucket.output.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# CORS configuration for output bucket to enable web playback
resource "aws_s3_bucket_cors_configuration" "output" {
  count  = var.enable_cors ? 1 : 0
  bucket = aws_s3_bucket.output.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }
}

# Public read access policy for output bucket (required for CloudFront)
resource "aws_s3_bucket_policy" "output" {
  bucket = aws_s3_bucket.output.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.output.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.abr_streaming.arn
          }
        }
      }
    ]
  })
}

#------------------------------------------------------------------------------
# IAM ROLES AND POLICIES
#------------------------------------------------------------------------------

# IAM role for MediaConvert service
resource "aws_iam_role" "mediaconvert" {
  name = local.mediaconvert_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "mediaconvert.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name        = "MediaConvert Service Role"
    Description = "Allows MediaConvert to access S3 buckets for video processing"
  })
}

# IAM policy for MediaConvert S3 access
resource "aws_iam_role_policy" "mediaconvert_s3" {
  name = "S3AccessPolicy"
  role = aws_iam_role.mediaconvert.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.source.arn,
          "${aws_s3_bucket.source.arn}/*",
          aws_s3_bucket.output.arn,
          "${aws_s3_bucket.output.arn}/*"
        ]
      }
    ]
  })
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda" {
  name = "${local.lambda_function_name}-role"

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

  tags = merge(local.common_tags, {
    Name        = "Lambda Execution Role"
    Description = "Allows Lambda to create MediaConvert jobs and write logs"
  })
}

# Attach basic execution role to Lambda
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM policy for Lambda MediaConvert access
resource "aws_iam_role_policy" "lambda_mediaconvert" {
  name = "MediaConvertAccessPolicy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "mediaconvert:CreateJob",
          "mediaconvert:GetJob",
          "mediaconvert:ListJobs",
          "mediaconvert:GetJobTemplate",
          "mediaconvert:DescribeEndpoints"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.mediaconvert.arn
      }
    ]
  })
}

#------------------------------------------------------------------------------
# MEDIACONVERT JOB TEMPLATE
#------------------------------------------------------------------------------

# MediaConvert job template for adaptive bitrate streaming
resource "aws_mediaconvert_job_template" "abr_streaming" {
  name        = local.job_template_name
  description = "Adaptive bitrate streaming template with HLS and DASH outputs"

  settings_json = jsonencode({
    OutputGroups = concat(
      # HLS Output Group
      var.enable_hls_output ? [{
        Name = "HLS_ABR_Package"
        OutputGroupSettings = {
          Type = "HLS_GROUP_SETTINGS"
          HlsGroupSettings = {
            Destination              = "s3://${aws_s3_bucket.output.bucket}/hls/"
            HlsCdnSettings = {
              HlsBasicPutSettings = {
                ConnectionRetryInterval = 1
                FilecacheDuration      = 300
                NumRetries             = 10
              }
            }
            ManifestDurationFormat = "FLOATING_POINT"
            OutputSelection        = "MANIFESTS_AND_SEGMENTS"
            SegmentControl         = "SEGMENTED_FILES"
            SegmentLength          = var.hls_segment_length
            TimedMetadataId3Frame  = "PRIV"
            TimedMetadataId3Period = 10
            MinSegmentLength       = 0
            DirectoryStructure     = "SINGLE_DIRECTORY"
          }
        }
        Outputs = compact([
          # 1080p output
          var.abr_bitrate_ladder.enable_1080p ? {
            NameModifier = "_1080p"
            ContainerSettings = {
              Container = "M3U8"
              M3u8Settings = {
                PcrControl         = "PCR_EVERY_PES_PACKET"
                PmtPid            = 480
                PrivateMetadataPid = 503
                ProgramNumber     = 1
                PatInterval       = 0
                PmtInterval       = 0
                VideoPid          = 481
                AudioPids         = [482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492]
              }
            }
            VideoDescription = {
              Width  = 1920
              Height = 1080
              CodecSettings = {
                Codec = "H_264"
                H264Settings = {
                  RateControlMode      = "QVBR"
                  QvbrSettings = {
                    QvbrQualityLevel = 8
                  }
                  MaxBitrate           = 5000000
                  FramerateControl     = "INITIALIZE_FROM_SOURCE"
                  GopClosedCadence     = 1
                  GopSize              = 90
                  GopSizeUnits         = "FRAMES"
                  ParControl           = "INITIALIZE_FROM_SOURCE"
                  QualityTuningLevel   = "SINGLE_PASS"
                  SceneChangeDetect    = "ENABLED"
                }
              }
            }
            AudioDescriptions = [{
              AudioTypeControl = "FOLLOW_INPUT"
              CodecSettings = {
                Codec = "AAC"
                AacSettings = {
                  Bitrate     = 128000
                  CodingMode  = "CODING_MODE_2_0"
                  SampleRate  = 48000
                }
              }
            }]
          } : null,
          # 720p output
          var.abr_bitrate_ladder.enable_720p ? {
            NameModifier = "_720p"
            ContainerSettings = {
              Container = "M3U8"
              M3u8Settings = {
                PcrControl         = "PCR_EVERY_PES_PACKET"
                PmtPid            = 480
                PrivateMetadataPid = 503
                ProgramNumber     = 1
                PatInterval       = 0
                PmtInterval       = 0
                VideoPid          = 481
                AudioPids         = [482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492]
              }
            }
            VideoDescription = {
              Width  = 1280
              Height = 720
              CodecSettings = {
                Codec = "H_264"
                H264Settings = {
                  RateControlMode      = "QVBR"
                  QvbrSettings = {
                    QvbrQualityLevel = 7
                  }
                  MaxBitrate           = 3000000
                  FramerateControl     = "INITIALIZE_FROM_SOURCE"
                  GopClosedCadence     = 1
                  GopSize              = 90
                  GopSizeUnits         = "FRAMES"
                  ParControl           = "INITIALIZE_FROM_SOURCE"
                  QualityTuningLevel   = "SINGLE_PASS"
                  SceneChangeDetect    = "ENABLED"
                }
              }
            }
            AudioDescriptions = [{
              AudioTypeControl = "FOLLOW_INPUT"
              CodecSettings = {
                Codec = "AAC"
                AacSettings = {
                  Bitrate     = 128000
                  CodingMode  = "CODING_MODE_2_0"
                  SampleRate  = 48000
                }
              }
            }]
          } : null,
          # 480p output
          var.abr_bitrate_ladder.enable_480p ? {
            NameModifier = "_480p"
            ContainerSettings = {
              Container = "M3U8"
              M3u8Settings = {
                PcrControl         = "PCR_EVERY_PES_PACKET"
                PmtPid            = 480
                PrivateMetadataPid = 503
                ProgramNumber     = 1
                PatInterval       = 0
                PmtInterval       = 0
                VideoPid          = 481
                AudioPids         = [482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492]
              }
            }
            VideoDescription = {
              Width  = 854
              Height = 480
              CodecSettings = {
                Codec = "H_264"
                H264Settings = {
                  RateControlMode      = "QVBR"
                  QvbrSettings = {
                    QvbrQualityLevel = 6
                  }
                  MaxBitrate           = 1500000
                  FramerateControl     = "INITIALIZE_FROM_SOURCE"
                  GopClosedCadence     = 1
                  GopSize              = 90
                  GopSizeUnits         = "FRAMES"
                  ParControl           = "INITIALIZE_FROM_SOURCE"
                  QualityTuningLevel   = "SINGLE_PASS"
                  SceneChangeDetect    = "ENABLED"
                }
              }
            }
            AudioDescriptions = [{
              AudioTypeControl = "FOLLOW_INPUT"
              CodecSettings = {
                Codec = "AAC"
                AacSettings = {
                  Bitrate     = 96000
                  CodingMode  = "CODING_MODE_2_0"
                  SampleRate  = 48000
                }
              }
            }]
          } : null,
          # 360p output
          var.abr_bitrate_ladder.enable_360p ? {
            NameModifier = "_360p"
            ContainerSettings = {
              Container = "M3U8"
              M3u8Settings = {
                PcrControl         = "PCR_EVERY_PES_PACKET"
                PmtPid            = 480
                PrivateMetadataPid = 503
                ProgramNumber     = 1
                PatInterval       = 0
                PmtInterval       = 0
                VideoPid          = 481
                AudioPids         = [482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492]
              }
            }
            VideoDescription = {
              Width  = 640
              Height = 360
              CodecSettings = {
                Codec = "H_264"
                H264Settings = {
                  RateControlMode      = "QVBR"
                  QvbrSettings = {
                    QvbrQualityLevel = 5
                  }
                  MaxBitrate           = 800000
                  FramerateControl     = "INITIALIZE_FROM_SOURCE"
                  GopClosedCadence     = 1
                  GopSize              = 90
                  GopSizeUnits         = "FRAMES"
                  ParControl           = "INITIALIZE_FROM_SOURCE"
                  QualityTuningLevel   = "SINGLE_PASS"
                  SceneChangeDetect    = "ENABLED"
                }
              }
            }
            AudioDescriptions = [{
              AudioTypeControl = "FOLLOW_INPUT"
              CodecSettings = {
                Codec = "AAC"
                AacSettings = {
                  Bitrate     = 64000
                  CodingMode  = "CODING_MODE_2_0"
                  SampleRate  = 48000
                }
              }
            }]
          } : null
        ])
      }] : [],
      # DASH Output Group
      var.enable_dash_output ? [{
        Name = "DASH_ABR_Package"
        OutputGroupSettings = {
          Type = "DASH_ISO_GROUP_SETTINGS"
          DashIsoGroupSettings = {
            Destination     = "s3://${aws_s3_bucket.output.bucket}/dash/"
            FragmentLength  = 2
            SegmentControl  = "SEGMENTED_FILES"
            SegmentLength   = var.dash_segment_length
            MpdProfile      = "ON_DEMAND_PROFILE"
            HbbtvCompliance = "NONE"
          }
        }
        Outputs = compact([
          # DASH 1080p output
          var.abr_bitrate_ladder.enable_1080p ? {
            NameModifier = "_dash_1080p"
            ContainerSettings = {
              Container = "MP4"
              Mp4Settings = {
                CslgAtom       = "INCLUDE"
                FreeSpaceBox   = "EXCLUDE"
                MoovPlacement  = "PROGRESSIVE_DOWNLOAD"
              }
            }
            VideoDescription = {
              Width  = 1920
              Height = 1080
              CodecSettings = {
                Codec = "H_264"
                H264Settings = {
                  RateControlMode      = "QVBR"
                  QvbrSettings = {
                    QvbrQualityLevel = 8
                  }
                  MaxBitrate           = 5000000
                  FramerateControl     = "INITIALIZE_FROM_SOURCE"
                  GopClosedCadence     = 1
                  GopSize              = 90
                  GopSizeUnits         = "FRAMES"
                  ParControl           = "INITIALIZE_FROM_SOURCE"
                  QualityTuningLevel   = "SINGLE_PASS"
                  SceneChangeDetect    = "ENABLED"
                }
              }
            }
            AudioDescriptions = [{
              AudioTypeControl = "FOLLOW_INPUT"
              CodecSettings = {
                Codec = "AAC"
                AacSettings = {
                  Bitrate     = 128000
                  CodingMode  = "CODING_MODE_2_0"
                  SampleRate  = 48000
                }
              }
            }]
          } : null,
          # DASH 720p output
          var.abr_bitrate_ladder.enable_720p ? {
            NameModifier = "_dash_720p"
            ContainerSettings = {
              Container = "MP4"
              Mp4Settings = {
                CslgAtom       = "INCLUDE"
                FreeSpaceBox   = "EXCLUDE"
                MoovPlacement  = "PROGRESSIVE_DOWNLOAD"
              }
            }
            VideoDescription = {
              Width  = 1280
              Height = 720
              CodecSettings = {
                Codec = "H_264"
                H264Settings = {
                  RateControlMode      = "QVBR"
                  QvbrSettings = {
                    QvbrQualityLevel = 7
                  }
                  MaxBitrate           = 3000000
                  FramerateControl     = "INITIALIZE_FROM_SOURCE"
                  GopClosedCadence     = 1
                  GopSize              = 90
                  GopSizeUnits         = "FRAMES"
                  ParControl           = "INITIALIZE_FROM_SOURCE"
                  QualityTuningLevel   = "SINGLE_PASS"
                  SceneChangeDetect    = "ENABLED"
                }
              }
            }
            AudioDescriptions = [{
              AudioTypeControl = "FOLLOW_INPUT"
              CodecSettings = {
                Codec = "AAC"
                AacSettings = {
                  Bitrate     = 128000
                  CodingMode  = "CODING_MODE_2_0"
                  SampleRate  = 48000
                }
              }
            }]
          } : null
        ])
      }] : [],
      # Thumbnail Output Group
      var.enable_thumbnails ? [{
        Name = "Thumbnail_Output"
        OutputGroupSettings = {
          Type = "FILE_GROUP_SETTINGS"
          FileGroupSettings = {
            Destination = "s3://${aws_s3_bucket.output.bucket}/thumbnails/"
          }
        }
        Outputs = [{
          NameModifier = "_thumb_%04d"
          ContainerSettings = {
            Container = "RAW"
          }
          VideoDescription = {
            Width  = 1280
            Height = 720
            CodecSettings = {
              Codec = "FRAME_CAPTURE"
              FrameCaptureSettings = {
                FramerateNumerator   = 1
                FramerateDenominator = 10
                MaxCaptures          = 10
                Quality              = 80
              }
            }
          }
        }]
      }] : []
    )
    Inputs = [{
      FileInput = "s3://${aws_s3_bucket.source.bucket}/"
      AudioSelectors = {
        "Audio Selector 1" = {
          Tracks          = [1]
          DefaultSelection = "DEFAULT"
        }
      }
      VideoSelector = {
        ColorSpace = "FOLLOW"
      }
      TimecodeSource = "EMBEDDED"
    }]
  })

  tags = merge(local.common_tags, {
    Name        = "ABR Job Template"
    Description = "Template for creating adaptive bitrate streaming content"
  })
}

#------------------------------------------------------------------------------
# LAMBDA FUNCTION FOR VIDEO PROCESSING
#------------------------------------------------------------------------------

# Lambda function source code
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content = templatefile("${path.module}/lambda_function.py.tpl", {
      mediaconvert_endpoint = data.aws_mediaconvert_endpoints.default.endpoints[0].url
      job_template         = aws_mediaconvert_job_template.abr_streaming.name
      mediaconvert_role_arn = aws_iam_role.mediaconvert.arn
      output_bucket        = aws_s3_bucket.output.bucket
    })
    filename = "lambda_function.py"
  }
}

# Create the Lambda function source file template
resource "local_file" "lambda_function_template" {
  filename = "${path.module}/lambda_function.py.tpl"
  content = <<-EOF
import json
import boto3
import os
from urllib.parse import unquote_plus

def lambda_handler(event, context):
    """
    Lambda function to process video files uploaded to S3 and create ABR streaming jobs.
    
    This function is triggered by S3 events when video files are uploaded.
    It creates MediaConvert jobs using the pre-configured ABR job template.
    """
    # Initialize MediaConvert client with customer-specific endpoint
    mediaconvert = boto3.client('mediaconvert', 
        endpoint_url='${mediaconvert_endpoint}')
    
    # Process each S3 event record
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = unquote_plus(record['s3']['object']['key'])
        
        # Filter for video files only
        video_extensions = ('.mp4', '.mov', '.avi', '.mkv', '.mxf', '.mts', '.m2ts')
        if not key.lower().endswith(video_extensions):
            print(f"Skipping non-video file: {key}")
            continue
        
        # Extract filename without extension for output naming
        file_name = key.split('/')[-1].split('.')[0]
        
        # Create MediaConvert job configuration
        job_settings = {
            "JobTemplate": "${job_template}",
            "Role": "${mediaconvert_role_arn}",
            "Settings": {
                "Inputs": [
                    {
                        "FileInput": f"s3://{bucket}/{key}",
                        "AudioSelectors": {
                            "Audio Selector 1": {
                                "Tracks": [1],
                                "DefaultSelection": "DEFAULT"
                            }
                        },
                        "VideoSelector": {
                            "ColorSpace": "FOLLOW"
                        },
                        "TimecodeSource": "EMBEDDED"
                    }
                ],
                # Override output destinations with file-specific paths
                "OutputGroups": [
                    {
                        "OutputGroupSettings": {
                            "Type": "HLS_GROUP_SETTINGS",
                            "HlsGroupSettings": {
                                "Destination": f"s3://${output_bucket}/hls/{file_name}/"
                            }
                        }
                    },
                    {
                        "OutputGroupSettings": {
                            "Type": "DASH_ISO_GROUP_SETTINGS", 
                            "DashIsoGroupSettings": {
                                "Destination": f"s3://${output_bucket}/dash/{file_name}/"
                            }
                        }
                    },
                    {
                        "OutputGroupSettings": {
                            "Type": "FILE_GROUP_SETTINGS",
                            "FileGroupSettings": {
                                "Destination": f"s3://${output_bucket}/thumbnails/{file_name}/"
                            }
                        }
                    }
                ]
            },
            "StatusUpdateInterval": "SECONDS_60",
            "UserMetadata": {
                "SourceFile": key,
                "ProcessingType": "ABR_Streaming",
                "OutputBucket": "${output_bucket}"
            }
        }
        
        try:
            # Create MediaConvert job
            response = mediaconvert.create_job(**job_settings)
            job_id = response['Job']['Id']
            
            print(f"Successfully created ABR processing job {job_id} for {key}")
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Successfully started ABR processing job {job_id}',
                    'jobId': job_id,
                    'sourceFile': key,
                    'hlsOutput': f"s3://${output_bucket}/hls/{file_name}/",
                    'dashOutput': f"s3://${output_bucket}/dash/{file_name}/",
                    'thumbnailOutput': f"s3://${output_bucket}/thumbnails/{file_name}/"
                })
            }
            
        except Exception as e:
            print(f"Error creating MediaConvert job for {key}: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'error': str(e),
                    'sourceFile': key
                })
            }
EOF
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name        = "Lambda Log Group"
    Description = "CloudWatch logs for ABR processing Lambda function"
  })
}

# Lambda function
resource "aws_lambda_function" "abr_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      MEDIACONVERT_ENDPOINT  = data.aws_mediaconvert_endpoints.default.endpoints[0].url
      JOB_TEMPLATE          = aws_mediaconvert_job_template.abr_streaming.name
      MEDIACONVERT_ROLE_ARN = aws_iam_role.mediaconvert.arn
      OUTPUT_BUCKET         = aws_s3_bucket.output.bucket
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.lambda,
  ]

  tags = merge(local.common_tags, {
    Name        = "ABR Processing Function"
    Description = "Processes video uploads and creates MediaConvert jobs"
  })
}

# S3 bucket notification to trigger Lambda
resource "aws_s3_bucket_notification" "source_bucket_notification" {
  bucket = aws_s3_bucket.source.id

  dynamic "lambda_function" {
    for_each = var.video_file_extensions
    content {
      lambda_function_arn = aws_lambda_function.abr_processor.arn
      events              = ["s3:ObjectCreated:*"]
      filter_suffix       = lambda_function.value
    }
  }

  depends_on = [aws_lambda_permission.s3_invoke]
}

# Lambda permission for S3 to invoke the function
resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.abr_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.source.arn
}

#------------------------------------------------------------------------------
# CLOUDFRONT DISTRIBUTION FOR GLOBAL CONTENT DELIVERY
#------------------------------------------------------------------------------

# CloudFront Origin Access Control for S3
resource "aws_cloudfront_origin_access_control" "default" {
  name                              = "${var.project_name}-oac-${local.random_suffix}"
  description                       = "OAC for ABR streaming content"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront distribution for ABR streaming
resource "aws_cloudfront_distribution" "abr_streaming" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Adaptive Bitrate Streaming Distribution - ${var.environment}"
  default_root_object = "index.html"
  price_class         = var.cloudfront_price_class

  # S3 origin for processed video content
  origin {
    domain_name              = aws_s3_bucket.output.bucket_regional_domain_name
    origin_id                = "S3-ABR-Output"
    origin_access_control_id = aws_cloudfront_origin_access_control.default.id
  }

  # Default cache behavior
  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "S3-ABR-Output"
    compress                   = false
    viewer_protocol_policy     = "redirect-to-https"
    
    # Use AWS managed caching policy optimized for caching
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"  # Managed-CachingOptimized
    
    # Use AWS managed origin request policy
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"  # Managed-CORS-S3Origin
  }

  # Cache behavior for HLS manifest files (.m3u8) - short cache
  ordered_cache_behavior {
    path_pattern               = "*.m3u8"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "S3-ABR-Output"
    compress                   = false
    viewer_protocol_policy     = "redirect-to-https"
    
    # Custom cache behavior for manifests
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    
    min_ttl     = 0
    default_ttl = 5
    max_ttl     = 60
  }

  # Cache behavior for DASH manifest files (.mpd) - short cache
  ordered_cache_behavior {
    path_pattern               = "*.mpd"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "S3-ABR-Output"
    compress                   = false
    viewer_protocol_policy     = "redirect-to-https"
    
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    
    min_ttl     = 0
    default_ttl = 5
    max_ttl     = 60
  }

  # Cache behavior for video segments (.ts) - long cache
  ordered_cache_behavior {
    path_pattern               = "*.ts"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "S3-ABR-Output"
    compress                   = false
    viewer_protocol_policy     = "redirect-to-https"
    
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    
    min_ttl     = 0
    default_ttl = 86400  # 1 day
    max_ttl     = 86400  # 1 day
  }

  # Cache behavior for MP4 files - long cache
  ordered_cache_behavior {
    path_pattern               = "*.mp4"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "S3-ABR-Output"
    compress                   = false
    viewer_protocol_policy     = "redirect-to-https"
    
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    
    min_ttl     = 0
    default_ttl = 86400  # 1 day
    max_ttl     = 86400  # 1 day
  }

  # Geographic restrictions (none by default)
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # SSL/TLS configuration
  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  # HTTP version
  http_version = "http2and3"

  tags = merge(local.common_tags, {
    Name        = "ABR Streaming Distribution"
    Description = "Global CDN for adaptive bitrate streaming content"
  })
}

#------------------------------------------------------------------------------
# CLOUDWATCH MONITORING AND ALARMS
#------------------------------------------------------------------------------

# CloudWatch alarm for Lambda errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "${local.lambda_function_name}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors lambda errors"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.notifications[0].arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.abr_processor.function_name
  }

  tags = local.common_tags
}

# CloudWatch alarm for Lambda duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "${local.lambda_function_name}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = "240000"  # 4 minutes (close to 5-minute timeout)
  alarm_description   = "This metric monitors lambda duration"
  alarm_actions       = var.notification_email != "" ? [aws_sns_topic.notifications[0].arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.abr_processor.function_name
  }

  tags = local.common_tags
}

# SNS topic for notifications (if email provided)
resource "aws_sns_topic" "notifications" {
  count = var.notification_email != "" ? 1 : 0
  name  = "${var.project_name}-notifications-${local.random_suffix}"

  tags = merge(local.common_tags, {
    Name        = "ABR Processing Notifications"
    Description = "SNS topic for ABR processing alerts"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.notifications[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}