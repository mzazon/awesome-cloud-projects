# outputs.tf - Output values for computer vision infrastructure

#####################################
# S3 Bucket Outputs
#####################################

output "s3_bucket_name" {
  description = "Name of the S3 bucket for storing images and videos"
  value       = aws_s3_bucket.computer_vision.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for storing images and videos"
  value       = aws_s3_bucket.computer_vision.arn
}

output "s3_bucket_domain_name" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.computer_vision.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.computer_vision.bucket_regional_domain_name
}

#####################################
# IAM Role Outputs
#####################################

output "rekognition_role_arn" {
  description = "ARN of the IAM role for Rekognition video analysis"
  value       = aws_iam_role.rekognition_video_analysis.arn
}

output "rekognition_role_name" {
  description = "Name of the IAM role for Rekognition video analysis"
  value       = aws_iam_role.rekognition_video_analysis.name
}

#####################################
# Kinesis Outputs
#####################################

output "kinesis_data_stream_name" {
  description = "Name of the Kinesis Data Stream for analysis results"
  value       = aws_kinesis_stream.rekognition_results.name
}

output "kinesis_data_stream_arn" {
  description = "ARN of the Kinesis Data Stream for analysis results"
  value       = aws_kinesis_stream.rekognition_results.arn
}

output "kinesis_video_stream_name" {
  description = "Name of the Kinesis Video Stream for real-time analysis"
  value       = aws_kinesisvideo_stream.security_video.name
}

output "kinesis_video_stream_arn" {
  description = "ARN of the Kinesis Video Stream for real-time analysis"
  value       = aws_kinesisvideo_stream.security_video.arn
}

#####################################
# Rekognition Outputs
#####################################

output "face_collection_name" {
  description = "Name of the Rekognition face collection (created manually)"
  value       = local.face_collection_name
}

output "stream_processor_name" {
  description = "Name of the Rekognition stream processor (created manually)"
  value       = local.stream_processor_name
}

#####################################
# CloudWatch Outputs
#####################################

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for computer vision logs"
  value       = aws_cloudwatch_log_group.computer_vision_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for computer vision logs"
  value       = aws_cloudwatch_log_group.computer_vision_logs.arn
}

#####################################
# Configuration Outputs
#####################################

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "resource_name_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_string.suffix.result
}

output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
}

#####################################
# Resource Summary
#####################################

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    s3_bucket = {
      name   = aws_s3_bucket.computer_vision.id
      arn    = aws_s3_bucket.computer_vision.arn
      region = data.aws_region.current.name
    }
    kinesis_data_stream = {
      name        = aws_kinesis_stream.rekognition_results.name
      arn         = aws_kinesis_stream.rekognition_results.arn
      shard_count = aws_kinesis_stream.rekognition_results.shard_count
    }
    kinesis_video_stream = {
      name = aws_kinesisvideo_stream.security_video.name
      arn  = aws_kinesisvideo_stream.security_video.arn
    }
    iam_role = {
      name = aws_iam_role.rekognition_video_analysis.name
      arn  = aws_iam_role.rekognition_video_analysis.arn
    }
    face_collection_name  = local.face_collection_name
    stream_processor_name = local.stream_processor_name
  }
}

#####################################
# CLI Commands for Manual Setup
#####################################

output "manual_setup_commands" {
  description = "AWS CLI commands to complete the setup"
  value = {
    create_face_collection = "aws rekognition create-collection --collection-id ${local.face_collection_name} --region ${data.aws_region.current.name}"
    create_stream_processor = "aws rekognition create-stream-processor --name ${local.stream_processor_name} --input '{\"KinesisVideoStream\":{\"Arn\":\"${aws_kinesisvideo_stream.security_video.arn}\"}}' --stream-processor-output '{\"KinesisDataStream\":{\"Arn\":\"${aws_kinesis_stream.rekognition_results.arn}\"}}' --role-arn ${aws_iam_role.rekognition_video_analysis.arn} --settings '{\"FaceSearch\":{\"CollectionId\":\"${local.face_collection_name}\",\"FaceMatchThreshold\":${var.face_match_threshold}}}' --region ${data.aws_region.current.name}"
    list_collections = "aws rekognition list-collections --region ${data.aws_region.current.name}"
    list_stream_processors = "aws rekognition list-stream-processors --region ${data.aws_region.current.name}"
  }
}

#####################################
# Environment Variables for Scripts
#####################################

output "environment_variables" {
  description = "Environment variables for use with deployment scripts"
  value = {
    AWS_REGION               = data.aws_region.current.name
    AWS_ACCOUNT_ID           = data.aws_caller_identity.current.account_id
    S3_BUCKET_NAME           = aws_s3_bucket.computer_vision.id
    FACE_COLLECTION_NAME     = local.face_collection_name
    KVS_STREAM_NAME          = aws_kinesisvideo_stream.security_video.name
    KDS_STREAM_NAME          = aws_kinesis_stream.rekognition_results.name
    REKOGNITION_ROLE_ARN     = aws_iam_role.rekognition_video_analysis.arn
    STREAM_PROCESSOR_NAME    = local.stream_processor_name
    FACE_MATCH_THRESHOLD     = var.face_match_threshold
    CLOUDWATCH_LOG_GROUP     = aws_cloudwatch_log_group.computer_vision_logs.name
  }
}

#####################################
# Sample Analysis Commands
#####################################

output "sample_analysis_commands" {
  description = "Sample AWS CLI commands for testing the computer vision pipeline"
  value = {
    detect_labels = "aws rekognition detect-labels --image 'S3Object={Bucket=${aws_s3_bucket.computer_vision.id},Name=images/sample.jpg}' --region ${data.aws_region.current.name}"
    detect_faces = "aws rekognition detect-faces --image 'S3Object={Bucket=${aws_s3_bucket.computer_vision.id},Name=images/sample.jpg}' --attributes ALL --region ${data.aws_region.current.name}"
    search_faces = "aws rekognition search-faces-by-image --image 'S3Object={Bucket=${aws_s3_bucket.computer_vision.id},Name=images/sample.jpg}' --collection-id ${local.face_collection_name} --face-match-threshold ${var.face_match_threshold} --region ${data.aws_region.current.name}"
    detect_text = "aws rekognition detect-text --image 'S3Object={Bucket=${aws_s3_bucket.computer_vision.id},Name=images/sample.jpg}' --region ${data.aws_region.current.name}"
    detect_moderation = "aws rekognition detect-moderation-labels --image 'S3Object={Bucket=${aws_s3_bucket.computer_vision.id},Name=images/sample.jpg}' --region ${data.aws_region.current.name}"
  }
}