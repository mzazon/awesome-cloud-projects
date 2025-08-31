# Main Terraform configuration for Simple Web Application Deployment with Elastic Beanstalk and CloudWatch

# Data sources for current AWS account and region information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Data source for default VPC if not specified
data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

# Data source for default subnets if not specified
data "aws_subnets" "default" {
  count = length(var.subnet_ids) == 0 ? 1 : 0
  
  filter {
    name   = "vpc-id"
    values = [var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id]
  }
  
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Generate random suffix for unique resource naming
resource "random_password" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  app_name     = var.application_name != "" ? var.application_name : "simple-web-app-${random_password.suffix.result}"
  env_name     = var.environment_name != "" ? var.environment_name : "simple-web-env-${random_password.suffix.result}"
  s3_bucket    = "eb-source-${random_password.suffix.result}"
  
  # Merge default and additional tags
  common_tags = merge(var.default_tags, var.additional_tags, {
    Application = local.app_name
    Environment = local.env_name
  })
  
  # VPC and subnet configuration
  vpc_id     = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_ids = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids
}

# S3 bucket for storing application source bundle
resource "aws_s3_bucket" "source_bucket" {
  bucket        = local.s3_bucket
  force_destroy = true
  
  tags = merge(local.common_tags, {
    Name        = "${local.app_name}-source-bucket"
    Description = "S3 bucket for Elastic Beanstalk application source bundles"
  })
}

# S3 bucket versioning configuration
resource "aws_s3_bucket_versioning" "source_bucket_versioning" {
  bucket = aws_s3_bucket.source_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "source_bucket_encryption" {
  bucket = aws_s3_bucket.source_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access to S3 bucket
resource "aws_s3_bucket_public_access_block" "source_bucket_pab" {
  bucket = aws_s3_bucket.source_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create sample application files locally
resource "local_file" "application_py" {
  content = <<-EOF
import flask
import logging
from datetime import datetime

# Create Flask application instance
application = flask.Flask(__name__)

# Configure logging for CloudWatch
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@application.route('/')
def hello():
    logger.info("Home page accessed")
    return flask.render_template('index.html')

@application.route('/health')
def health():
    logger.info("Health check accessed")
    return {'status': 'healthy', 'timestamp': datetime.now().isoformat()}

@application.route('/api/info')
def info():
    logger.info("Info API accessed")
    return {
        'application': 'Simple Web App',
        'version': '1.0',
        'environment': 'production'
    }

if __name__ == '__main__':
    application.run(debug=True)
EOF
  filename = "${path.module}/app/application.py"
}

resource "local_file" "requirements_txt" {
  content = <<-EOF
Flask==3.0.3
Werkzeug==3.0.3
EOF
  filename = "${path.module}/app/requirements.txt"
}

resource "local_file" "index_html" {
  content = <<-EOF
<!DOCTYPE html>
<html>
<head>
    <title>Simple Web App</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 600px; margin: 0 auto; }
        .status { background: #e8f5e8; padding: 20px; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome to Simple Web App</h1>
        <div class="status">
            <h3>Application Status: Running</h3>
            <p>This application is deployed on AWS Elastic Beanstalk with CloudWatch monitoring enabled.</p>
            <ul>
                <li><a href="/health">Health Check</a></li>
                <li><a href="/api/info">Application Info</a></li>
            </ul>
        </div>
    </div>
</body>
</html>
EOF
  filename = "${path.module}/app/templates/index.html"
}

# Create Elastic Beanstalk configuration file for CloudWatch integration
resource "local_file" "ebextensions_config" {
  content = <<-EOF
option_settings:
  aws:elasticbeanstalk:cloudwatch:logs:
    StreamLogs: ${var.stream_logs}
    DeleteOnTerminate: ${var.delete_logs_on_terminate}
    RetentionInDays: ${var.log_retention_days}
  aws:elasticbeanstalk:cloudwatch:logs:health:
    HealthStreamingEnabled: ${var.health_streaming_enabled}
    DeleteOnTerminate: ${var.delete_logs_on_terminate}
    RetentionInDays: ${var.log_retention_days}
  aws:elasticbeanstalk:healthreporting:system:
    SystemType: ${var.enhanced_health_reporting ? "enhanced" : "basic"}
    EnhancedHealthAuthEnabled: ${var.enhanced_health_reporting}
EOF
  filename = "${path.module}/app/.ebextensions/cloudwatch-logs.config"
}

# Create ZIP archive of application files
data "archive_file" "app_zip" {
  type        = "zip"
  output_path = "${path.module}/app.zip"
  source_dir  = "${path.module}/app"
  
  depends_on = [
    local_file.application_py,
    local_file.requirements_txt,
    local_file.index_html,
    local_file.ebextensions_config
  ]
}

# Upload application source bundle to S3
resource "aws_s3_object" "app_source" {
  bucket = aws_s3_bucket.source_bucket.bucket
  key    = "${local.app_name}-source.zip"
  source = data.archive_file.app_zip.output_path
  etag   = data.archive_file.app_zip.output_md5
  
  tags = merge(local.common_tags, {
    Name        = "${local.app_name}-source-bundle"
    Description = "Application source bundle for Elastic Beanstalk deployment"
  })
}

# IAM role for Elastic Beanstalk EC2 instances
resource "aws_iam_role" "eb_ec2_role" {
  name = "${local.app_name}-eb-ec2-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name        = "${local.app_name}-eb-ec2-role"
    Description = "IAM role for Elastic Beanstalk EC2 instances"
  })
}

# Attach required policies to EC2 role
resource "aws_iam_role_policy_attachment" "eb_web_tier" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_role_policy_attachment" "eb_worker_tier" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier"
}

resource "aws_iam_role_policy_attachment" "eb_multicontainer_docker" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker"
}

# Instance profile for EC2 instances
resource "aws_iam_instance_profile" "eb_ec2_profile" {
  name = "${local.app_name}-eb-ec2-profile"
  role = aws_iam_role.eb_ec2_role.name
  
  tags = merge(local.common_tags, {
    Name        = "${local.app_name}-eb-ec2-profile"
    Description = "Instance profile for Elastic Beanstalk EC2 instances"
  })
}

# IAM role for Elastic Beanstalk service
resource "aws_iam_role" "eb_service_role" {
  name = "${local.app_name}-eb-service-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "elasticbeanstalk.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name        = "${local.app_name}-eb-service-role"
    Description = "IAM service role for Elastic Beanstalk"
  })
}

# Attach service role policy
resource "aws_iam_role_policy_attachment" "eb_service" {
  role       = aws_iam_role.eb_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkService"
}

resource "aws_iam_role_policy_attachment" "eb_enhanced_health" {
  role       = aws_iam_role.eb_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

# Elastic Beanstalk application
resource "aws_elastic_beanstalk_application" "app" {
  name        = local.app_name
  description = "Simple web application for learning deployment with CloudWatch monitoring"
  
  appversion_lifecycle {
    service_role          = aws_iam_role.eb_service_role.arn
    max_count             = 128
    delete_source_from_s3 = true
  }
  
  tags = merge(local.common_tags, {
    Name        = local.app_name
    Description = "Elastic Beanstalk application for simple web deployment"
  })
}

# Elastic Beanstalk application version
resource "aws_elastic_beanstalk_application_version" "app_version" {
  name         = "v1-${random_password.suffix.result}"
  application  = aws_elastic_beanstalk_application.app.name
  description  = "Initial deployment version"
  bucket       = aws_s3_bucket.source_bucket.bucket
  key          = aws_s3_object.app_source.key
  
  tags = merge(local.common_tags, {
    Name        = "v1-${random_password.suffix.result}"
    Description = "Application version for initial deployment"
  })
}

# Security group for Elastic Beanstalk environment
resource "aws_security_group" "eb_sg" {
  name        = "${local.app_name}-eb-sg"
  description = "Security group for Elastic Beanstalk environment"
  vpc_id      = local.vpc_id
  
  # HTTP traffic
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP traffic from internet"
  }
  
  # HTTPS traffic
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS traffic from internet"
  }
  
  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.app_name}-eb-sg"
    Description = "Security group for Elastic Beanstalk environment"
  })
}

# Elastic Beanstalk environment
resource "aws_elastic_beanstalk_environment" "env" {
  name                = local.env_name
  application         = aws_elastic_beanstalk_application.app.name
  solution_stack_name = var.solution_stack_name
  version_label       = aws_elastic_beanstalk_application_version.app_version.name
  tier                = "WebServer"
  
  # EC2 instance configuration
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = var.instance_type
  }
  
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.eb_ec2_profile.name
  }
  
  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = aws_security_group.eb_sg.id
  }
  
  setting {
    namespace = "aws:ec2:vpc"
    name      = "AssociatePublicIpAddress"
    value     = var.associate_public_ip_address
  }
  
  # Auto Scaling configuration
  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MinSize"
    value     = var.min_size
  }
  
  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MaxSize"
    value     = var.max_size
  }
  
  # VPC configuration
  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = local.vpc_id
  }
  
  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = join(",", local.subnet_ids)
  }
  
  # CloudWatch Logs configuration
  setting {
    namespace = "aws:elasticbeanstalk:cloudwatch:logs"
    name      = "StreamLogs"
    value     = var.stream_logs
  }
  
  setting {
    namespace = "aws:elasticbeanstalk:cloudwatch:logs"
    name      = "DeleteOnTerminate"
    value     = var.delete_logs_on_terminate
  }
  
  setting {
    namespace = "aws:elasticbeanstalk:cloudwatch:logs"
    name      = "RetentionInDays"
    value     = var.log_retention_days
  }
  
  # Health monitoring configuration
  setting {
    namespace = "aws:elasticbeanstalk:cloudwatch:logs:health"
    name      = "HealthStreamingEnabled"
    value     = var.health_streaming_enabled
  }
  
  setting {
    namespace = "aws:elasticbeanstalk:cloudwatch:logs:health"
    name      = "DeleteOnTerminate"
    value     = var.delete_logs_on_terminate
  }
  
  setting {
    namespace = "aws:elasticbeanstalk:cloudwatch:logs:health"
    name      = "RetentionInDays"
    value     = var.log_retention_days
  }
  
  # Enhanced health reporting
  setting {
    namespace = "aws:elasticbeanstalk:healthreporting:system"
    name      = "SystemType"
    value     = var.enhanced_health_reporting ? "enhanced" : "basic"
  }
  
  setting {
    namespace = "aws:elasticbeanstalk:healthreporting:system"
    name      = "EnhancedHealthAuthEnabled"
    value     = var.enhanced_health_reporting
  }
  
  # Service role for enhanced health reporting
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = aws_iam_role.eb_service_role.arn
  }
  
  # Load balancer configuration
  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
  }
  
  tags = merge(local.common_tags, {
    Name        = local.env_name
    Description = "Elastic Beanstalk environment for simple web application"
  })
  
  depends_on = [
    aws_iam_role_policy_attachment.eb_service,
    aws_iam_role_policy_attachment.eb_enhanced_health,
    aws_iam_role_policy_attachment.eb_web_tier,
    aws_iam_role_policy_attachment.eb_worker_tier,
    aws_iam_role_policy_attachment.eb_multicontainer_docker
  ]
}

# SNS topic for alarm notifications (optional)
resource "aws_sns_topic" "alarms" {
  count = var.enable_alarms && var.alarm_notification_email != "" ? 1 : 0
  
  name         = "${local.app_name}-alarms"
  display_name = "${local.app_name} CloudWatch Alarms"
  
  tags = merge(local.common_tags, {
    Name        = "${local.app_name}-alarms"
    Description = "SNS topic for CloudWatch alarm notifications"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email_alerts" {
  count = var.enable_alarms && var.alarm_notification_email != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_notification_email
}

# CloudWatch alarm for environment health
resource "aws_cloudwatch_metric_alarm" "environment_health" {
  count = var.enable_alarms ? 1 : 0
  
  alarm_name          = "${local.env_name}-health-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "EnvironmentHealth"
  namespace           = "AWS/ElasticBeanstalk"
  period              = "300"
  statistic           = "Average"
  threshold           = var.health_alarm_threshold
  alarm_description   = "This metric monitors Elastic Beanstalk environment health"
  alarm_actions       = var.alarm_notification_email != "" ? [aws_sns_topic.alarms[0].arn] : []
  ok_actions          = var.alarm_notification_email != "" ? [aws_sns_topic.alarms[0].arn] : []
  treat_missing_data  = "breaching"
  
  dimensions = {
    EnvironmentName = aws_elastic_beanstalk_environment.env.name
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.env_name}-health-alarm"
    Description = "CloudWatch alarm for environment health monitoring"
  })
}

# CloudWatch alarm for 4xx errors
resource "aws_cloudwatch_metric_alarm" "application_4xx_errors" {
  count = var.enable_alarms ? 1 : 0
  
  alarm_name          = "${local.env_name}-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApplicationRequests4xx"
  namespace           = "AWS/ElasticBeanstalk"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.error_4xx_threshold
  alarm_description   = "This metric monitors 4xx application errors"
  alarm_actions       = var.alarm_notification_email != "" ? [aws_sns_topic.alarms[0].arn] : []
  ok_actions          = var.alarm_notification_email != "" ? [aws_sns_topic.alarms[0].arn] : []
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    EnvironmentName = aws_elastic_beanstalk_environment.env.name
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.env_name}-4xx-errors"
    Description = "CloudWatch alarm for 4xx error monitoring"
  })
}

# CloudWatch alarm for 5xx errors
resource "aws_cloudwatch_metric_alarm" "application_5xx_errors" {
  count = var.enable_alarms ? 1 : 0
  
  alarm_name          = "${local.env_name}-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApplicationRequests5xx"
  namespace           = "AWS/ElasticBeanstalk"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors 5xx application errors"
  alarm_actions       = var.enable_alarms && var.alarm_notification_email != "" ? [aws_sns_topic.alarms[0].arn] : []
  ok_actions          = var.enable_alarms && var.alarm_notification_email != "" ? [aws_sns_topic.alarms[0].arn] : []
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    EnvironmentName = aws_elastic_beanstalk_environment.env.name
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.env_name}-5xx-errors"
    Description = "CloudWatch alarm for 5xx error monitoring"
  })
}

# CloudWatch alarm for high response time
resource "aws_cloudwatch_metric_alarm" "response_time" {
  count = var.enable_alarms ? 1 : 0
  
  alarm_name          = "${local.env_name}-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ApplicationLatencyP99"
  namespace           = "AWS/ElasticBeanstalk"
  period              = "300"
  statistic           = "Average"
  threshold           = "5000"  # 5 seconds in milliseconds
  alarm_description   = "This metric monitors application response time"
  alarm_actions       = var.alarm_notification_email != "" ? [aws_sns_topic.alarms[0].arn] : []
  ok_actions          = var.alarm_notification_email != "" ? [aws_sns_topic.alarms[0].arn] : []
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    EnvironmentName = aws_elastic_beanstalk_environment.env.name
  }
  
  tags = merge(local.common_tags, {
    Name        = "${local.env_name}-response-time"
    Description = "CloudWatch alarm for response time monitoring"
  })
}