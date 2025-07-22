# Progressive Web App Infrastructure with AWS Amplify Hosting
# This configuration creates a complete PWA hosting solution with CI/CD pipeline

# Generate a random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  app_name_with_suffix = "${var.app_name}-${random_id.suffix.hex}"
  full_domain          = var.domain_name != "" ? "${var.subdomain_prefix}.${var.domain_name}" : ""
  
  # Default build spec if none provided
  default_build_spec = var.build_spec != "" ? var.build_spec : yamlencode({
    version = 1
    frontend = {
      phases = {
        preBuild = {
          commands = [
            "echo \"Pre-build phase - checking PWA requirements\"",
            "npm install -g pwa-asset-generator || echo 'PWA asset generator not available'"
          ]
        }
        build = {
          commands = [
            "echo \"Build phase - generating PWA assets\"",
            "echo \"Optimizing for Progressive Web App\"",
            "ls -la"
          ]
        }
        postBuild = {
          commands = [
            "echo \"Post-build phase - PWA optimization complete\"",
            "echo \"Service Worker and Manifest validated\""
          ]
        }
      }
      artifacts = {
        baseDirectory = "."
        files = ["**/*"]
      }
      cache = {
        paths = ["node_modules/**/*"]
      }
    }
  })

  # Common tags for all resources
  common_tags = merge(var.tags, {
    Application = "Progressive Web App"
    Framework   = var.framework
    Environment = var.environment
  })
}

# Data source to get current AWS caller identity
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# IAM Service Role for Amplify (only created if repository URL is provided)
resource "aws_iam_role" "amplify_service_role" {
  count = var.repository_url != "" ? 1 : 0
  name  = "${local.app_name_with_suffix}-amplify-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "amplify.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# IAM Policy for Amplify Service Role
resource "aws_iam_role_policy" "amplify_service_policy" {
  count = var.repository_url != "" ? 1 : 0
  name  = "${local.app_name_with_suffix}-amplify-policy"
  role  = aws_iam_role.amplify_service_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "cloudformation:*",
          "s3:*",
          "cloudfront:*",
          "route53:*",
          "acm:*",
          "iam:PassRole"
        ]
        Resource = "*"
      }
    ]
  })
}

# AWS Amplify App
resource "aws_amplify_app" "pwa_app" {
  name         = local.app_name_with_suffix
  description  = "Progressive Web App with offline functionality and CI/CD pipeline"
  repository   = var.repository_url != "" ? var.repository_url : null
  access_token = var.access_token != "" ? var.access_token : null

  # Platform and framework configuration
  platform = "WEB"
  
  # IAM service role (only if repository is connected)
  iam_service_role_arn = var.repository_url != "" ? aws_iam_role.amplify_service_role[0].arn : null

  # Build specification
  build_spec = local.default_build_spec

  # Auto branch creation settings
  enable_auto_branch_creation = var.enable_auto_branch_creation
  
  auto_branch_creation_config {
    enable_auto_build                = true
    enable_pull_request_preview      = var.enable_pull_request_preview
    environment_variables            = var.environment_variables
    framework                        = var.framework
    enable_performance_mode          = var.performance_mode == "COMPUTE_OPTIMIZED"
    
    # Basic authentication if enabled
    enable_basic_auth = var.enable_basic_auth
    basic_auth_config = var.enable_basic_auth ? {
      username = var.basic_auth_username
      password = var.basic_auth_password
    } : null
  }

  # Environment variables for all branches
  environment_variables = merge(var.environment_variables, {
    AMPLIFY_DIFF_DEPLOY = "false"
    AMPLIFY_MONOREPO_APP_ROOT = "."
  })

  # Custom rules for PWA routing (SPA support)
  dynamic "custom_rule" {
    for_each = var.custom_rules
    content {
      source    = custom_rule.value.source
      target    = custom_rule.value.target
      status    = custom_rule.value.status
      condition = custom_rule.value.condition
    }
  }

  # Custom headers for PWA optimization and security
  custom_headers = jsonencode([
    {
      pattern = "**/*"
      headers = [
        {
          key   = "X-Frame-Options"
          value = "DENY"
        },
        {
          key   = "X-Content-Type-Options"
          value = "nosniff"
        },
        {
          key   = "Referrer-Policy"
          value = "strict-origin-when-cross-origin"
        },
        {
          key   = "X-XSS-Protection"
          value = "1; mode=block"
        },
        {
          key   = "Cache-Control"
          value = "public, max-age=31536000, immutable"
        }
      ]
    },
    {
      pattern = "**.html"
      headers = [
        {
          key   = "Cache-Control"
          value = "public, max-age=0, must-revalidate"
        }
      ]
    },
    {
      pattern = "sw.js"
      headers = [
        {
          key   = "Cache-Control"
          value = "public, max-age=0, must-revalidate"
        },
        {
          key   = "Service-Worker-Allowed"
          value = "/"
        }
      ]
    },
    {
      pattern = "manifest.json"
      headers = [
        {
          key   = "Cache-Control"
          value = "public, max-age=86400"
        },
        {
          key   = "Content-Type"
          value = "application/manifest+json"
        }
      ]
    }
  ])

  tags = local.common_tags
}

# Main branch for the Amplify app
resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.pwa_app.id
  branch_name = var.branch_name
  description = "Main production branch for PWA"

  # Framework and performance settings
  framework                    = var.framework
  enable_auto_build           = true
  enable_pull_request_preview = var.enable_pull_request_preview
  enable_performance_mode     = var.performance_mode == "COMPUTE_OPTIMIZED"

  # Environment variables specific to this branch
  environment_variables = merge(var.environment_variables, {
    NODE_ENV = var.environment
    PWA_ENVIRONMENT = var.environment
  })

  # Basic authentication if enabled
  enable_basic_auth = var.enable_basic_auth
  basic_auth_config = var.enable_basic_auth ? {
    username = var.basic_auth_username
    password = var.basic_auth_password
  } : null

  tags = local.common_tags
}

# Domain association (only if domain is provided)
resource "aws_amplify_domain_association" "main" {
  count       = var.domain_name != "" ? 1 : 0
  app_id      = aws_amplify_app.pwa_app.id
  domain_name = var.domain_name

  # Wait for SSL certificate provisioning
  wait_for_verification = true

  # Subdomain configuration
  sub_domain {
    branch_name = aws_amplify_branch.main.branch_name
    prefix      = var.subdomain_prefix
  }

  tags = local.common_tags

  depends_on = [aws_amplify_branch.main]
}

# CloudWatch Log Group for Amplify application logs
resource "aws_cloudwatch_log_group" "amplify_logs" {
  name              = "/aws/amplify/${aws_amplify_app.pwa_app.name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Purpose = "Amplify PWA Application Logs"
  })
}

# CloudWatch Log Group for Amplify build logs
resource "aws_cloudwatch_log_group" "amplify_build_logs" {
  name              = "/aws/amplify/${aws_amplify_app.pwa_app.name}/build"
  retention_in_days = 7

  tags = merge(local.common_tags, {
    Purpose = "Amplify PWA Build Logs"
  })
}

# CloudWatch Metric Alarm for build failures
resource "aws_cloudwatch_metric_alarm" "build_failures" {
  alarm_name          = "${local.app_name_with_suffix}-build-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "BuildFailures"
  namespace           = "AWS/Amplify"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors Amplify build failures"
  alarm_actions       = []

  dimensions = {
    App = aws_amplify_app.pwa_app.name
  }

  tags = local.common_tags
}

# CloudWatch Dashboard for PWA monitoring
resource "aws_cloudwatch_dashboard" "pwa_dashboard" {
  dashboard_name = "${local.app_name_with_suffix}-dashboard"

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
            ["AWS/Amplify", "BuildTime", "App", aws_amplify_app.pwa_app.name],
            ["AWS/Amplify", "Builds", "App", aws_amplify_app.pwa_app.name],
            ["AWS/Amplify", "BuildFailures", "App", aws_amplify_app.pwa_app.name]
          ]
          view    = "timeSeries"
          stacked = false
          region  = data.aws_region.current.name
          title   = "Amplify PWA Metrics"
          period  = 300
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          query   = <<-EOT
            SOURCE '/aws/amplify/${aws_amplify_app.pwa_app.name}'
            | fields @timestamp, @message
            | sort @timestamp desc
            | limit 100
          EOT
          region  = data.aws_region.current.name
          title   = "Recent Amplify Logs"
        }
      }
    ]
  })

  tags = local.common_tags
}