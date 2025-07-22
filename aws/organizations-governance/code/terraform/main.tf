# Multi-Account Governance with AWS Organizations and Service Control Policies
# This Terraform configuration creates a comprehensive governance framework

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Get current AWS account ID and caller identity
data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# Create AWS Organization with all features enabled
resource "aws_organizations_organization" "main" {
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "sso.amazonaws.com",
    "account.amazonaws.com",
    "budgets.amazonaws.com"
  ]

  feature_set = var.enable_all_features ? "ALL" : "CONSOLIDATED_BILLING"

  enabled_policy_types = var.enable_all_features ? [
    "SERVICE_CONTROL_POLICY",
    "TAG_POLICY",
    "BACKUP_POLICY",
    "AISERVICES_OPT_OUT_POLICY"
  ] : []

  tags = {
    Name = "${var.organization_name_prefix}-${random_string.suffix.result}"
  }
}

# Create Organizational Units for different environments
resource "aws_organizations_organizational_unit" "production" {
  name      = "Production"
  parent_id = aws_organizations_organization.main.roots[0].id

  tags = {
    Environment = "Production"
    Purpose     = "Production workloads"
  }
}

resource "aws_organizations_organizational_unit" "development" {
  name      = "Development"
  parent_id = aws_organizations_organization.main.roots[0].id

  tags = {
    Environment = "Development"
    Purpose     = "Development and testing workloads"
  }
}

resource "aws_organizations_organizational_unit" "sandbox" {
  name      = "Sandbox"
  parent_id = aws_organizations_organization.main.roots[0].id

  tags = {
    Environment = "Sandbox"
    Purpose     = "Experimental and learning workloads"
  }
}

resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = aws_organizations_organization.main.roots[0].id

  tags = {
    Environment = "Security"
    Purpose     = "Security and compliance workloads"
  }
}

# Service Control Policy for Cost Control
resource "aws_organizations_policy" "cost_control" {
  name        = "CostControlPolicy"
  description = "Policy to control costs and enforce tagging"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyExpensiveInstances"
        Effect = "Deny"
        Action = [
          "ec2:RunInstances"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:ec2:*:*:instance/*"
        Condition = {
          ForAnyValue:StringLike = {
            "ec2:InstanceType" = var.max_instance_types
          }
        }
      },
      {
        Sid    = "DenyExpensiveRDSInstances"
        Effect = "Deny"
        Action = [
          "rds:CreateDBInstance",
          "rds:CreateDBCluster"
        ]
        Resource = "*"
        Condition = {
          ForAnyValue:StringLike = {
            "rds:db-instance-class" = [
              "*.8xlarge",
              "*.12xlarge",
              "*.16xlarge",
              "*.24xlarge"
            ]
          }
        }
      },
      {
        Sid    = "RequireCostAllocationTags"
        Effect = "Deny"
        Action = [
          "ec2:RunInstances",
          "rds:CreateDBInstance",
          "s3:CreateBucket"
        ]
        Resource = "*"
        Condition = {
          Null = {
            "aws:RequestedRegion" = "false"
          }
          ForAllValues:StringNotEquals = {
            "aws:TagKeys" = var.required_tags
          }
        }
      }
    ]
  })

  tags = {
    PolicyType = "CostControl"
  }
}

# Service Control Policy for Security Baseline
resource "aws_organizations_policy" "security_baseline" {
  name        = "SecurityBaselinePolicy"
  description = "Baseline security controls for all accounts"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyRootUserActions"
        Effect = "Deny"
        Action = "*"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:PrincipalType" = "Root"
          }
        }
      },
      {
        Sid    = "DenyCloudTrailDisable"
        Effect = "Deny"
        Action = [
          "cloudtrail:StopLogging",
          "cloudtrail:DeleteTrail",
          "cloudtrail:PutEventSelectors",
          "cloudtrail:UpdateTrail"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyConfigDisable"
        Effect = "Deny"
        Action = [
          "config:DeleteConfigRule",
          "config:DeleteConfigurationRecorder",
          "config:DeleteDeliveryChannel",
          "config:StopConfigurationRecorder"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyUnencryptedS3Objects"
        Effect = "Deny"
        Action = "s3:PutObject"
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "AES256"
          }
          Null = {
            "s3:x-amz-server-side-encryption" = "true"
          }
        }
      }
    ]
  })

  tags = {
    PolicyType = "SecurityBaseline"
  }
}

# Service Control Policy for Region Restriction
resource "aws_organizations_policy" "region_restriction" {
  name        = "RegionRestrictionPolicy"
  description = "Restrict sandbox accounts to approved regions"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonApprovedRegions"
        Effect    = "Deny"
        NotAction = [
          "iam:*",
          "organizations:*",
          "route53:*",
          "cloudfront:*",
          "waf:*",
          "wafv2:*",
          "waf-regional:*",
          "support:*",
          "trustedadvisor:*"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = var.allowed_regions
          }
        }
      }
    ]
  })

  tags = {
    PolicyType = "RegionRestriction"
  }
}

# Attach Cost Control SCP to Production OU
resource "aws_organizations_policy_attachment" "cost_control_production" {
  policy_id = aws_organizations_policy.cost_control.id
  target_id = aws_organizations_organizational_unit.production.id
}

# Attach Cost Control SCP to Development OU
resource "aws_organizations_policy_attachment" "cost_control_development" {
  policy_id = aws_organizations_policy.cost_control.id
  target_id = aws_organizations_organizational_unit.development.id
}

# Attach Security Baseline SCP to Production OU
resource "aws_organizations_policy_attachment" "security_baseline_production" {
  policy_id = aws_organizations_policy.security_baseline.id
  target_id = aws_organizations_organizational_unit.production.id
}

# Attach Region Restriction SCP to Sandbox OU
resource "aws_organizations_policy_attachment" "region_restriction_sandbox" {
  policy_id = aws_organizations_policy.region_restriction.id
  target_id = aws_organizations_organizational_unit.sandbox.id
}

# S3 bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = "org-cloudtrail-${random_string.suffix.result}"

  tags = {
    Purpose = "CloudTrail logging"
  }
}

# S3 bucket versioning for CloudTrail
resource "aws_s3_bucket_versioning" "cloudtrail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption for CloudTrail
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket lifecycle configuration for CloudTrail
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail[0].id

  rule {
    id     = "cloudtrail_retention"
    status = "Enabled"

    expiration {
      days = var.cloudtrail_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# S3 bucket policy for CloudTrail
resource "aws_s3_bucket_policy" "cloudtrail" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail[0].arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# Organization-wide CloudTrail
resource "aws_cloudtrail" "organization" {
  count                         = var.enable_cloudtrail ? 1 : 0
  name                          = "OrganizationTrail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail[0].bucket
  include_global_service_events = true
  is_multi_region_trail         = true
  is_organization_trail         = true
  enable_logging                = true

  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    exclude_management_event_sources = []

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:${data.aws_partition.current.partition}:s3:::*/*"]
    }
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail[0]]

  tags = {
    Purpose = "Organization audit trail"
  }
}

# CloudWatch dashboard for governance monitoring
resource "aws_cloudwatch_dashboard" "governance" {
  dashboard_name = "OrganizationGovernance"

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
            ["AWS/Organizations", "TotalAccounts"],
            ["AWS/Organizations", "ActiveAccounts"]
          ]
          view      = "timeSeries"
          stacked   = false
          region    = var.aws_region
          title     = "Organization Account Metrics"
          period    = 300
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          query  = "SOURCE '/aws/cloudtrail' | fields @timestamp, sourceIPAddress, userIdentity.type, eventName, errorMessage\n| filter eventName like /organizations/\n| sort @timestamp desc\n| limit 100"
          region = var.aws_region
          title  = "Organization API Activity"
          view   = "table"
        }
      }
    ]
  })
}

# AWS Budgets for cost monitoring
resource "aws_budgets_budget" "organization" {
  name         = "OrganizationMasterBudget"
  budget_type  = "COST"
  limit_amount = var.budget_amount
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  
  time_period_start = formatdate("YYYY-MM-01_00:00", timestamp())

  cost_filters {
    linked_account = [data.aws_caller_identity.current.account_id]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = var.budget_notification_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.budget_notification_emails
  }

  tags = {
    Purpose = "Organization cost monitoring"
  }
}

# Cost Anomaly Detection
resource "aws_ce_anomaly_detector" "organization" {
  count         = var.enable_cost_anomaly_detection ? 1 : 0
  name          = "organization-anomaly-detector"
  detector_type = "DIMENSIONAL"

  specification = jsonencode({
    DimensionKey = "SERVICE"
    MatchOptions = ["EQUALS"]
    Values       = ["EC2-Instance"]
  })

  tags = {
    Purpose = "Cost anomaly detection"
  }
}

# Cost Anomaly Subscription
resource "aws_ce_anomaly_subscription" "organization" {
  count     = var.enable_cost_anomaly_detection ? 1 : 0
  name      = "organization-anomaly-subscription"
  frequency = "DAILY"
  
  monitor_arn_list = [
    aws_ce_anomaly_detector.organization[0].arn
  ]
  
  subscriber {
    type    = "EMAIL"
    address = var.budget_notification_emails[0]
  }

  threshold_expression {
    and {
      dimension {
        key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
        values        = ["100"]
        match_options = ["GREATER_THAN_OR_EQUAL"]
      }
    }
  }

  tags = {
    Purpose = "Cost anomaly notifications"
  }
}

# Create member accounts (optional)
resource "aws_organizations_account" "member" {
  count = var.create_member_accounts ? length(var.member_accounts) : 0
  
  name  = var.member_accounts[count.index].name
  email = var.member_accounts[count.index].email

  # Assign to appropriate OU after creation
  parent_id = local.ou_map[var.member_accounts[count.index].ou]

  tags = {
    Environment = var.member_accounts[count.index].ou
    Purpose     = "Member account"
  }
}

# Local values for OU mapping
locals {
  ou_map = {
    "Production"  = aws_organizations_organizational_unit.production.id
    "Development" = aws_organizations_organizational_unit.development.id
    "Sandbox"     = aws_organizations_organizational_unit.sandbox.id
    "Security"    = aws_organizations_organizational_unit.security.id
  }
}