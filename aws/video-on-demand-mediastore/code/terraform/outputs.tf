# Output values for the VOD platform infrastructure

output "mediastore_container_name" {
  description = "Name of the MediaStore container"
  value       = aws_mediastore_container.vod_origin.name
}

output "mediastore_container_endpoint" {
  description = "Endpoint URL for the MediaStore container"
  value       = aws_mediastore_container.vod_origin.endpoint
}

output "mediastore_container_arn" {
  description = "ARN of the MediaStore container"
  value       = aws_mediastore_container.vod_origin.arn
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.vod_distribution.id
}

output "cloudfront_distribution_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.vod_distribution.domain_name
}

output "cloudfront_distribution_url" {
  description = "Full HTTPS URL of the CloudFront distribution"
  value       = "https://${aws_cloudfront_distribution.vod_distribution.domain_name}"
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.vod_distribution.arn
}

output "cloudfront_distribution_zone_id" {
  description = "CloudFront distribution hosted zone ID"
  value       = aws_cloudfront_distribution.vod_distribution.hosted_zone_id
}

output "s3_staging_bucket_name" {
  description = "Name of the S3 staging bucket"
  value       = aws_s3_bucket.staging.bucket
}

output "s3_staging_bucket_arn" {
  description = "ARN of the S3 staging bucket"
  value       = aws_s3_bucket.staging.arn
}

output "s3_staging_bucket_domain_name" {
  description = "Domain name of the S3 staging bucket"
  value       = aws_s3_bucket.staging.bucket_domain_name
}

output "iam_role_name" {
  description = "Name of the MediaStore access IAM role"
  value       = aws_iam_role.mediastore_access.name
}

output "iam_role_arn" {
  description = "ARN of the MediaStore access IAM role"
  value       = aws_iam_role.mediastore_access.arn
}

# Video content URLs for testing
output "sample_video_mediastore_url" {
  description = "Direct MediaStore URL for sample video content"
  value       = "${aws_mediastore_container.vod_origin.endpoint}/videos/sample-video.mp4"
}

output "sample_video_cloudfront_url" {
  description = "CloudFront URL for sample video content"
  value       = "https://${aws_cloudfront_distribution.vod_distribution.domain_name}/videos/sample-video.mp4"
}

# Monitoring and operational outputs
output "cloudwatch_alarm_name" {
  description = "Name of the CloudWatch alarm for request monitoring"
  value       = var.enable_mediastore_metrics ? aws_cloudwatch_metric_alarm.high_request_rate[0].alarm_name : null
}

# Resource deployment information
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = data.aws_region.current.name
}

output "aws_account_id" {
  description = "AWS account ID where resources are deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

# Deployment instructions
output "deployment_instructions" {
  description = "Instructions for testing the video-on-demand platform"
  value = <<-EOT
    Video-on-Demand Platform Deployment Complete!
    
    Next Steps:
    1. Upload video content to MediaStore:
       aws mediastore-data put-object \
         --endpoint-url ${aws_mediastore_container.vod_origin.endpoint} \
         --body /path/to/video.mp4 \
         --path /videos/your-video.mp4 \
         --content-type video/mp4
    
    2. Access video via CloudFront:
       https://${aws_cloudfront_distribution.vod_distribution.domain_name}/videos/your-video.mp4
    
    3. Test with staging bucket:
       aws s3 cp /path/to/video.mp4 s3://${aws_s3_bucket.staging.bucket}/
    
    4. Monitor with CloudWatch:
       - Container metrics: AWS/MediaStore namespace
       - Distribution metrics: AWS/CloudFront namespace
    
    Resources Created:
    - MediaStore Container: ${aws_mediastore_container.vod_origin.name}
    - CloudFront Distribution: ${aws_cloudfront_distribution.vod_distribution.id}
    - S3 Staging Bucket: ${aws_s3_bucket.staging.bucket}
    - IAM Role: ${aws_iam_role.mediastore_access.name}
  EOT
}