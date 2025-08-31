# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming
  resource_prefix = "${var.project_name}-${random_id.suffix.hex}"
  
  # Common tags
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    CreatedBy   = "terraform"
    Purpose     = "website-monitoring"
  }
}

# S3 bucket for storing canary artifacts
resource "aws_s3_bucket" "synthetics_artifacts" {
  bucket = "synthetics-artifacts-${local.resource_prefix}"

  tags = merge(local.common_tags, {
    Name = "Synthetics Artifacts Bucket"
    Type = "Storage"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "synthetics_artifacts" {
  bucket = aws_s3_bucket.synthetics_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "synthetics_artifacts" {
  bucket = aws_s3_bucket.synthetics_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "synthetics_artifacts" {
  bucket = aws_s3_bucket.synthetics_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "synthetics_artifacts" {
  bucket = aws_s3_bucket.synthetics_artifacts.id

  rule {
    id     = "synthetics-artifact-retention"
    status = "Enabled"

    transition {
      days          = var.s3_lifecycle_transition_days
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = var.s3_lifecycle_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# IAM role for CloudWatch Synthetics canary
resource "aws_iam_role" "synthetics_canary_role" {
  name = "SyntheticsCanaryRole-${local.resource_prefix}"

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
    Name = "Synthetics Canary IAM Role"
    Type = "IAM"
  })
}

# Attach AWS managed policy for Synthetics execution
resource "aws_iam_role_policy_attachment" "synthetics_execution_policy" {
  role       = aws_iam_role.synthetics_canary_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchSyntheticsExecutionRolePolicy"
}

# Additional IAM policy for S3 access to artifacts bucket
resource "aws_iam_role_policy" "synthetics_s3_policy" {
  name = "SyntheticsS3Access-${local.resource_prefix}"
  role = aws_iam_role.synthetics_canary_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.synthetics_artifacts.arn,
          "${aws_s3_bucket.synthetics_artifacts.arn}/*"
        ]
      }
    ]
  })
}

# Create canary script as a local file
resource "local_file" "canary_script" {
  filename = "${path.module}/canary-script.js"
  content  = <<-EOF
const synthetics = require('Synthetics');
const log = require('SyntheticsLogger');

const checkWebsite = async function () {
    let page = await synthetics.getPage();
    
    // Navigate to website with performance monitoring
    const response = await synthetics.executeStepFunction('loadHomepage', async function () {
        return await page.goto(synthetics.getConfiguration().getUrl(), {
            waitUntil: 'networkidle0',
            timeout: 30000
        });
    });
    
    // Verify successful response
    if (response.status() < 200 || response.status() > 299) {
        throw new Error(`Failed to load page: $${response.status()}`);
    }
    
    // Check for critical page elements
    await synthetics.executeStepFunction('verifyPageElements', async function () {
        await page.waitForSelector('body', { timeout: 10000 });
        
        // Verify page title exists
        const title = await page.title();
        if (!title || title.length === 0) {
            throw new Error('Page title is missing');
        }
        
        log.info(`Page title: $${title}`);
        
        // Check for JavaScript errors
        const errors = await page.evaluate(() => {
            return window.console.errors || [];
        });
        
        if (errors.length > 0) {
            log.warn(`JavaScript errors detected: $${errors.length}`);
        }
    });
    
    // Capture performance metrics
    await synthetics.executeStepFunction('captureMetrics', async function () {
        const metrics = await page.evaluate(() => {
            const navigation = performance.getEntriesByType('navigation')[0];
            return {
                loadTime: navigation.loadEventEnd - navigation.loadEventStart,
                domContentLoaded: navigation.domContentLoadedEventEnd - navigation.domContentLoadedEventStart,
                responseTime: navigation.responseEnd - navigation.requestStart
            };
        });
        
        // Log custom metrics
        log.info(`Load time: $${metrics.loadTime}ms`);
        log.info(`DOM content loaded: $${metrics.domContentLoaded}ms`);
        log.info(`Response time: $${metrics.responseTime}ms`);
        
        // Set custom CloudWatch metrics
        await synthetics.addUserAgentMetric('LoadTime', metrics.loadTime, 'Milliseconds');
        await synthetics.addUserAgentMetric('ResponseTime', metrics.responseTime, 'Milliseconds');
    });
};

exports.handler = async () => {
    return await synthetics.executeStep('checkWebsite', checkWebsite);
};
EOF
}

# Create ZIP archive of the canary script
data "archive_file" "canary_package" {
  type        = "zip"
  source_file = local_file.canary_script.filename
  output_path = "${path.module}/canary-package.zip"
  depends_on  = [local_file.canary_script]
}

# CloudWatch Synthetics Canary
resource "aws_synthetics_canary" "website_monitor" {
  name                 = "website-monitor-${local.resource_prefix}"
  artifact_s3_location = "s3://${aws_s3_bucket.synthetics_artifacts.bucket}/canary-artifacts"
  execution_role_arn   = aws_iam_role.synthetics_canary_role.arn
  handler              = "canary-script.handler"
  zip_file             = data.archive_file.canary_package.output_path
  runtime_version      = var.runtime_version

  schedule {
    expression = var.canary_schedule
  }

  run_config {
    timeout_in_seconds    = var.canary_timeout
    memory_in_mb         = var.canary_memory
    active_tracing       = var.enable_x_ray_tracing
    environment_variables = {
      URL = var.website_url
    }
  }

  success_retention_period = var.success_retention_days
  failure_retention_period = var.failure_retention_days

  start_canary = true

  tags = merge(local.common_tags, {
    Name = "Website Monitor Canary"
    Type = "Synthetics"
    URL  = var.website_url
  })

  depends_on = [
    aws_iam_role_policy_attachment.synthetics_execution_policy,
    aws_iam_role_policy.synthetics_s3_policy,
    aws_s3_bucket.synthetics_artifacts
  ]
}

# SNS topic for alerts
resource "aws_sns_topic" "synthetics_alerts" {
  name = "synthetics-alerts-${local.resource_prefix}"

  tags = merge(local.common_tags, {
    Name = "Synthetics Alerts Topic"
    Type = "Notifications"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.synthetics_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch alarm for canary failures
resource "aws_cloudwatch_metric_alarm" "canary_failure_alarm" {
  alarm_name          = "${aws_synthetics_canary.website_monitor.name}-failure-alarm"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "SuccessPercent"
  namespace           = "CloudWatchSynthetics"
  period              = 300
  statistic           = "Average"
  threshold           = var.success_threshold
  alarm_description   = "Alert when website monitoring canary success rate falls below ${var.success_threshold}%"
  alarm_actions       = [aws_sns_topic.synthetics_alerts.arn]

  dimensions = {
    CanaryName = aws_synthetics_canary.website_monitor.name
  }

  tags = merge(local.common_tags, {
    Name = "Canary Failure Alarm"
    Type = "Monitoring"
  })
}

# CloudWatch alarm for high response times
resource "aws_cloudwatch_metric_alarm" "canary_response_time_alarm" {
  alarm_name          = "${aws_synthetics_canary.website_monitor.name}-response-time-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "Duration"
  namespace           = "CloudWatchSynthetics"
  period              = 300
  statistic           = "Average"
  threshold           = var.response_time_threshold
  alarm_description   = "Alert when website response time exceeds ${var.response_time_threshold}ms"
  alarm_actions       = [aws_sns_topic.synthetics_alerts.arn]

  dimensions = {
    CanaryName = aws_synthetics_canary.website_monitor.name
  }

  tags = merge(local.common_tags, {
    Name = "Canary Response Time Alarm"
    Type = "Monitoring"
  })
}

# CloudWatch Dashboard (conditional creation)
resource "aws_cloudwatch_dashboard" "website_monitoring" {
  count          = var.create_dashboard ? 1 : 0
  dashboard_name = "Website-Monitoring-${local.resource_prefix}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["CloudWatchSynthetics", "SuccessPercent", "CanaryName", aws_synthetics_canary.website_monitor.name],
            [".", "Duration", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Website Monitoring Overview"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["CloudWatchSynthetics", "Failed", "CanaryName", aws_synthetics_canary.website_monitor.name],
            [".", "Passed", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Test Results"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6
        properties = {
          metrics = [
            ["CloudWatchSynthetics", "Duration", "CanaryName", aws_synthetics_canary.website_monitor.name, { stat = "Average" }],
            ["...", { stat = "Maximum" }],
            ["...", { stat = "Minimum" }]
          ]
          period = 300
          region = data.aws_region.current.name
          title  = "Response Time Trends"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "Website Monitoring Dashboard"
    Type = "Dashboard"
  })
}