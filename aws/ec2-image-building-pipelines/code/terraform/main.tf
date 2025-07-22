# EC2 Image Builder Pipeline Infrastructure

# Data sources for existing AWS resources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  name_suffix         = random_id.suffix.hex
  current_region      = data.aws_region.current.name
  account_id          = data.aws_caller_identity.current.account_id
  distribution_regions = length(var.distribution_regions) > 0 ? var.distribution_regions : [local.current_region]
  
  common_tags = merge(var.additional_tags, {
    Project     = var.project_name
    Environment = var.environment
  })
}

# Default VPC and Subnet for build instances
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Latest Amazon Linux 2 AMI for base image
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# S3 Bucket for Image Builder logs and component storage
resource "aws_s3_bucket" "image_builder_logs" {
  bucket = "${var.project_name}-image-builder-logs-${local.name_suffix}"
  
  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-image-builder-logs-${local.name_suffix}"
    Purpose = "ImageBuilder logs and component storage"
  })
}

# S3 Bucket versioning
resource "aws_s3_bucket_versioning" "image_builder_logs" {
  bucket = aws_s3_bucket.image_builder_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "image_builder_logs" {
  bucket = aws_s3_bucket.image_builder_logs.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# S3 Bucket public access block
resource "aws_s3_bucket_public_access_block" "image_builder_logs" {
  bucket = aws_s3_bucket.image_builder_logs.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM Role for EC2 Image Builder instances
resource "aws_iam_role" "image_builder_instance" {
  name = "${var.project_name}-image-builder-instance-role-${local.name_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-image-builder-instance-role-${local.name_suffix}"
    Purpose = "EC2 Image Builder instance execution role"
  })
}

# Attach AWS managed policies to instance role
resource "aws_iam_role_policy_attachment" "image_builder_instance_profile" {
  policy_arn = "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilder"
  role       = aws_iam_role.image_builder_instance.name
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.image_builder_instance.name
}

# Custom IAM policy for S3 access
resource "aws_iam_role_policy" "s3_access" {
  name = "${var.project_name}-s3-access-policy-${local.name_suffix}"
  role = aws_iam_role.image_builder_instance.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.image_builder_logs.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.image_builder_logs.arn
      }
    ]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "image_builder" {
  name = "${var.project_name}-image-builder-instance-profile-${local.name_suffix}"
  role = aws_iam_role.image_builder_instance.name
  
  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-image-builder-instance-profile-${local.name_suffix}"
    Purpose = "EC2 Image Builder instance profile"
  })
}

# Security Group for Image Builder instances
resource "aws_security_group" "image_builder" {
  name_prefix = "${var.project_name}-image-builder-${local.name_suffix}"
  description = "Security group for EC2 Image Builder instances"
  vpc_id      = data.aws_vpc.default.id
  
  # Outbound rules for package downloads and updates
  egress {
    description = "HTTPS outbound for package downloads"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    description = "HTTP outbound for package downloads"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # DNS resolution
  egress {
    description = "DNS resolution"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-image-builder-sg-${local.name_suffix}"
    Purpose = "EC2 Image Builder instance security group"
  })
}

# SNS Topic for build notifications
resource "aws_sns_topic" "image_builder_notifications" {
  name = "${var.project_name}-image-builder-notifications-${local.name_suffix}"
  
  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-image-builder-notifications-${local.name_suffix}"
    Purpose = "EC2 Image Builder build notifications"
  })
}

# SNS Topic subscription for email notifications (if email provided)
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.image_builder_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# CloudWatch Log Group for Image Builder logs
resource "aws_cloudwatch_log_group" "image_builder" {
  name              = "/aws/imagebuilder/${var.project_name}-${local.name_suffix}"
  retention_in_days = var.log_retention_days
  
  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-image-builder-logs-${local.name_suffix}"
    Purpose = "EC2 Image Builder CloudWatch logs"
  })
}

# Upload component YAML files to S3
resource "aws_s3_object" "web_server_component" {
  bucket = aws_s3_bucket.image_builder_logs.bucket
  key    = "components/web-server-component.yaml"
  
  content = yamlencode({
    name           = "WebServerSetup"
    description    = "Install and configure Apache web server with security hardening"
    schemaVersion  = "1.0"
    
    phases = [
      {
        name = "build"
        steps = [
          {
            name   = "UpdateSystem"
            action = "UpdateOS"
          },
          {
            name   = "InstallApache"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "yum update -y",
                "yum install -y httpd",
                "systemctl enable httpd"
              ]
            }
          },
          {
            name   = "ConfigureApache"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "echo '<html><body><h1>Custom Web Server</h1><p>Built with EC2 Image Builder</p></body></html>' > /var/www/html/index.html",
                "chown apache:apache /var/www/html/index.html",
                "chmod 644 /var/www/html/index.html"
              ]
            }
          },
          {
            name   = "SecurityHardening"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "sed -i 's/^#ServerTokens OS/ServerTokens Prod/' /etc/httpd/conf/httpd.conf",
                "sed -i 's/^#ServerSignature On/ServerSignature Off/' /etc/httpd/conf/httpd.conf",
                "systemctl start httpd"
              ]
            }
          }
        ]
      },
      {
        name = "validate"
        steps = [
          {
            name   = "ValidateApache"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "systemctl is-active httpd",
                "curl -f http://localhost/ || exit 1"
              ]
            }
          }
        ]
      },
      {
        name = "test"
        steps = [
          {
            name   = "TestWebServer"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "systemctl status httpd",
                "curl -s http://localhost/ | grep -q \"Custom Web Server\" || exit 1",
                "netstat -tlnp | grep :80 || exit 1"
              ]
            }
          }
        ]
      }
    ]
  })
  
  content_type = "application/x-yaml"
  
  tags = merge(local.common_tags, {
    Name    = "web-server-component.yaml"
    Purpose = "EC2 Image Builder web server component"
  })
}

resource "aws_s3_object" "web_server_test_component" {
  bucket = aws_s3_bucket.image_builder_logs.bucket
  key    = "components/web-server-test.yaml"
  
  content = yamlencode({
    name           = "WebServerTest"
    description    = "Comprehensive testing of web server setup"
    schemaVersion  = "1.0"
    
    phases = [
      {
        name = "test"
        steps = [
          {
            name   = "ServiceTest"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "echo \"Testing Apache service status...\"",
                "systemctl is-enabled httpd",
                "systemctl is-active httpd"
              ]
            }
          },
          {
            name   = "ConfigurationTest"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "echo \"Testing Apache configuration...\"",
                "httpd -t",
                "grep -q \"ServerTokens Prod\" /etc/httpd/conf/httpd.conf || exit 1",
                "grep -q \"ServerSignature Off\" /etc/httpd/conf/httpd.conf || exit 1"
              ]
            }
          },
          {
            name   = "SecurityTest"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "echo \"Testing security configurations...\"",
                "curl -I http://localhost/ | grep -q \"Apache\" && exit 1 || echo \"Server signature hidden\"",
                "ss -tlnp | grep :80 | grep -q httpd || exit 1"
              ]
            }
          },
          {
            name   = "ContentTest"
            action = "ExecuteBash"
            inputs = {
              commands = [
                "echo \"Testing web content...\"",
                "curl -s http://localhost/ | grep -q \"Custom Web Server\" || exit 1",
                "test -f /var/www/html/index.html || exit 1"
              ]
            }
          }
        ]
      }
    ]
  })
  
  content_type = "application/x-yaml"
  
  tags = merge(local.common_tags, {
    Name    = "web-server-test.yaml"
    Purpose = "EC2 Image Builder web server test component"
  })
}

# EC2 Image Builder Components
resource "aws_imagebuilder_component" "web_server" {
  name         = "${var.project_name}-component-${local.name_suffix}"
  description  = "Web server setup with security hardening"
  platform     = "Linux"
  version      = var.component_version
  uri          = "s3://${aws_s3_bucket.image_builder_logs.bucket}/${aws_s3_object.web_server_component.key}"
  
  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-component-${local.name_suffix}"
    Purpose = "Web server build component"
  })
  
  depends_on = [aws_s3_object.web_server_component]
}

resource "aws_imagebuilder_component" "web_server_test" {
  name         = "${var.project_name}-test-component-${local.name_suffix}"
  description  = "Comprehensive web server testing"
  platform     = "Linux"
  version      = var.component_version
  uri          = "s3://${aws_s3_bucket.image_builder_logs.bucket}/${aws_s3_object.web_server_test_component.key}"
  
  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-test-component-${local.name_suffix}"
    Purpose = "Web server test component"
  })
  
  depends_on = [aws_s3_object.web_server_test_component]
}

# EC2 Image Builder Image Recipe
resource "aws_imagebuilder_image_recipe" "web_server" {
  name         = "${var.project_name}-recipe-${local.name_suffix}"
  description  = "Web server recipe with security hardening"
  parent_image = data.aws_ami.amazon_linux_2.id
  version      = var.image_recipe_version
  
  component {
    component_arn = aws_imagebuilder_component.web_server.arn
  }
  
  component {
    component_arn = aws_imagebuilder_component.web_server_test.arn
  }
  
  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-recipe-${local.name_suffix}"
    Purpose = "Web server image recipe"
  })
}

# EC2 Image Builder Infrastructure Configuration
resource "aws_imagebuilder_infrastructure_configuration" "web_server" {
  name                          = "${var.project_name}-infrastructure-${local.name_suffix}"
  description                   = "Infrastructure for web server image builds"
  instance_profile_name         = aws_iam_instance_profile.image_builder.name
  instance_types                = var.instance_types
  subnet_id                     = data.aws_subnets.default.ids[0]
  security_group_ids           = [aws_security_group.image_builder.id]
  terminate_instance_on_failure = var.terminate_instance_on_failure
  sns_topic_arn                = aws_sns_topic.image_builder_notifications.arn
  
  logging {
    s3_logs {
      s3_bucket_name = aws_s3_bucket.image_builder_logs.bucket
      s3_key_prefix  = "build-logs/"
    }
  }
  
  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-infrastructure-${local.name_suffix}"
    Purpose = "Image Builder infrastructure configuration"
  })
}

# EC2 Image Builder Distribution Configuration
resource "aws_imagebuilder_distribution_configuration" "web_server" {
  name        = "${var.project_name}-distribution-${local.name_suffix}"
  description = "Multi-region distribution for web server AMIs"
  
  dynamic "distribution" {
    for_each = local.distribution_regions
    content {
      region = distribution.value
      
      ami_distribution_configuration {
        name               = "WebServer-{{imagebuilder:buildDate}}-{{imagebuilder:buildVersion}}"
        description        = "Custom web server AMI built with EC2 Image Builder"
        
        ami_tags = merge(local.common_tags, {
          Name         = "WebServer-AMI"
          BuildDate    = "{{imagebuilder:buildDate}}"
          BuildVersion = "{{imagebuilder:buildVersion}}"
          Recipe       = "${var.project_name}-recipe-${local.name_suffix}"
        })
      }
    }
  }
  
  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-distribution-${local.name_suffix}"
    Purpose = "Image Builder distribution configuration"
  })
}

# EC2 Image Builder Pipeline
resource "aws_imagebuilder_image_pipeline" "web_server" {
  name                             = "${var.project_name}-pipeline-${local.name_suffix}"
  description                      = "Automated web server image building pipeline"
  image_recipe_arn                 = aws_imagebuilder_image_recipe.web_server.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.web_server.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.web_server.arn
  status                           = var.pipeline_status
  
  image_tests_configuration {
    image_tests_enabled                = var.image_tests_enabled
    timeout_minutes                    = var.image_tests_timeout_minutes
  }
  
  schedule {
    schedule_expression                = var.pipeline_schedule
    pipeline_execution_start_condition = "EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE"
  }
  
  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-pipeline-${local.name_suffix}"
    Purpose = "Image Builder automated pipeline"
  })
}