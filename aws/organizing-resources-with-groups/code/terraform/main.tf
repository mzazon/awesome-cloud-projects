# Get current AWS account information
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming
  resource_suffix = random_id.suffix.hex
  resource_group_name = "${var.resource_name_prefix}-${var.environment}-${local.resource_suffix}"
  sns_topic_name = "${var.resource_name_prefix}-alerts-${local.resource_suffix}"
  automation_role_name = "${var.resource_name_prefix}-automation-role-${local.resource_suffix}"
  dashboard_name = "${var.resource_name_prefix}-dashboard-${local.resource_suffix}"
  
  # Common tags
  common_tags = merge(var.additional_tags, {
    Environment = var.environment
    Application = var.application
    Purpose     = "resource-management"
    ManagedBy   = "terraform"
    Recipe      = "resource-groups-automated-resource-management"
  })
}

# SNS Topic for notifications
resource "aws_sns_topic" "resource_alerts" {
  name = local.sns_topic_name
  
  tags = merge(local.common_tags, {
    Name = local.sns_topic_name
    Type = "notification"
  })
}

# SNS Topic Policy to allow CloudWatch and Budgets to publish
resource "aws_sns_topic_policy" "resource_alerts_policy" {
  arn = aws_sns_topic.resource_alerts.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarmsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.resource_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AllowBudgetsToPublish"
        Effect = "Allow"
        Principal = {
          Service = "budgets.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.resource_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# SNS Email Subscription (if email is provided)
resource "aws_sns_topic_subscription" "email_notification" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.resource_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# IAM Role for Systems Manager Automation
resource "aws_iam_role" "automation_role" {
  name = local.automation_role_name
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = local.automation_role_name
    Type = "iam-role"
  })
}

# Attach AWS managed policy for Systems Manager automation
resource "aws_iam_role_policy_attachment" "automation_policy" {
  role       = aws_iam_role.automation_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMAutomationRole"
}

# Custom IAM policy for resource group operations
resource "aws_iam_role_policy" "resource_group_operations" {
  name = "${local.automation_role_name}-resource-group-policy"
  role = aws_iam_role.automation_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "resource-groups:ListGroupResources",
          "resource-groups:GetGroup",
          "resource-groups:GetGroupQuery",
          "resourcegroupstaggingapi:TagResources",
          "resourcegroupstaggingapi:UntagResources",
          "resourcegroupstaggingapi:GetResources"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeImages",
          "ec2:DescribeSnapshots",
          "ec2:DescribeVolumes",
          "s3:ListBucket",
          "s3:GetBucketTagging",
          "rds:DescribeDBInstances",
          "rds:ListTagsForResource"
        ]
        Resource = "*"
      }
    ]
  })
}

# Resource Group for organizing resources
resource "aws_resourcegroups_group" "main" {
  name        = local.resource_group_name
  description = "Automated resource group for ${var.environment} ${var.application} resources"
  
  resource_query {
    query = jsonencode({
      ResourceTypeFilters = var.additional_resource_types
      TagFilters = [
        {
          Key    = "Environment"
          Values = [var.environment]
        },
        {
          Key    = "Application"
          Values = [var.application]
        }
      ]
    })
  }
  
  tags = merge(local.common_tags, {
    Name = local.resource_group_name
    Type = "resource-group"
  })
}

# Systems Manager Automation Document for Resource Group Maintenance
resource "aws_ssm_document" "resource_group_maintenance" {
  count           = var.enable_automation_documents ? 1 : 0
  name            = "ResourceGroupMaintenance-${local.resource_suffix}"
  document_type   = "Automation"
  document_format = "YAML"
  
  content = yamlencode({
    schemaVersion = "0.3"
    description   = "Automated maintenance for resource group"
    assumeRole    = aws_iam_role.automation_role.arn
    parameters = {
      ResourceGroupName = {
        type        = "String"
        description = "Name of the resource group to process"
      }
    }
    mainSteps = [
      {
        name   = "GetResourceGroupResources"
        action = "aws:executeAwsApi"
        inputs = {
          Service   = "resource-groups"
          Api       = "ListGroupResources"
          GroupName = "{{ ResourceGroupName }}"
        }
        outputs = [
          {
            Name     = "ResourceList"
            Selector = "$.ResourceIdentifiers"
            Type     = "MapList"
          }
        ]
      },
      {
        name   = "LogResourceCount"
        action = "aws:executeAwsApi"
        inputs = {
          Service = "logs"
          Api     = "PutLogEvents"
          logGroupName = "/aws/ssm/automation"
          logStreamName = "resource-group-maintenance"
          logEvents = [
            {
              timestamp = "{{ global:DATE_TIME }}"
              message   = "Found {{ GetResourceGroupResources.ResourceList | length }} resources in group {{ ResourceGroupName }}"
            }
          ]
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "ResourceGroupMaintenance-${local.resource_suffix}"
    Type = "ssm-document"
  })
}

# Systems Manager Automation Document for Automated Resource Tagging
resource "aws_ssm_document" "automated_resource_tagging" {
  count           = var.enable_automation_documents ? 1 : 0
  name            = "AutomatedResourceTagging-${local.resource_suffix}"
  document_type   = "Automation"
  document_format = "YAML"
  
  content = yamlencode({
    schemaVersion = "0.3"
    description   = "Automated resource tagging for resource groups"
    assumeRole    = aws_iam_role.automation_role.arn
    parameters = {
      ResourceType = {
        type        = "String"
        description = "Type of AWS resource to tag"
      }
      TagKey = {
        type        = "String"
        description = "Tag key to apply"
      }
      TagValue = {
        type        = "String"
        description = "Tag value to apply"
      }
    }
    mainSteps = [
      {
        name   = "TagResources"
        action = "aws:executeAwsApi"
        inputs = {
          Service = "resourcegroupstaggingapi"
          Api     = "TagResources"
          ResourceARNList = []
          Tags = {
            "{{ TagKey }}" = "{{ TagValue }}"
          }
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "AutomatedResourceTagging-${local.resource_suffix}"
    Type = "ssm-document"
  })
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "resource_monitoring" {
  dashboard_name = local.dashboard_name
  
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
            ["AWS/EC2", "CPUUtilization", { "stat" = "Average" }],
            ["AWS/RDS", "CPUUtilization", { "stat" = "Average" }]
          ]
          period = var.dashboard_period
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Resource Group CPU Utilization"
          view   = "timeSeries"
          stacked = false
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Billing", "EstimatedCharges", "Currency", "USD"]
          ]
          period = 86400
          stat   = "Maximum"
          region = "us-east-1"
          title  = "Estimated Monthly Charges"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 12
        width  = 24
        height = 6
        properties = {
          query = "SOURCE '/aws/ssm/automation' | fields @timestamp, @message\n| filter @message like /resource-group/\n| sort @timestamp desc\n| limit 100"
          region = data.aws_region.current.name
          title = "Resource Group Automation Logs"
        }
      }
    ]
  })
}

# CloudWatch Alarm for High CPU Utilization
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "ResourceGroup-HighCPU-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "High CPU usage across resource group"
  alarm_actions       = [aws_sns_topic.resource_alerts.arn]
  treat_missing_data  = "notBreaching"
  
  tags = merge(local.common_tags, {
    Name = "ResourceGroup-HighCPU-${local.resource_suffix}"
    Type = "cloudwatch-alarm"
  })
}

# CloudWatch Alarm for EC2 Status Check Failures
resource "aws_cloudwatch_metric_alarm" "health_check" {
  alarm_name          = "ResourceGroup-HealthCheck-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "0"
  alarm_description   = "Overall health monitoring for resource group"
  alarm_actions       = [aws_sns_topic.resource_alerts.arn]
  treat_missing_data  = "notBreaching"
  
  tags = merge(local.common_tags, {
    Name = "ResourceGroup-HealthCheck-${local.resource_suffix}"
    Type = "cloudwatch-alarm"
  })
}

# AWS Budget for Resource Group Cost Tracking
resource "aws_budgets_budget" "resource_group_budget" {
  name         = "ResourceGroup-Budget-${local.resource_suffix}"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_limit)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  
  cost_filters {
    tag {
      key    = "Environment"
      values = [var.environment]
    }
    tag {
      key    = "Application"
      values = [var.application]
    }
  }
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = var.budget_threshold_percentage
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = var.notification_email != "" ? [var.notification_email] : []
    subscriber_sns_topic_arns  = [aws_sns_topic.resource_alerts.arn]
  }
  
  depends_on = [aws_sns_topic_policy.resource_alerts_policy]
}

# Cost Anomaly Detector
resource "aws_ce_anomaly_detector" "resource_group_anomaly" {
  count       = var.enable_cost_anomaly_detection ? 1 : 0
  name        = "ResourceGroupAnomalyDetector-${local.resource_suffix}"
  monitor_type = "DIMENSIONAL"
  
  specification = jsonencode({
    DimensionKey = "SERVICE"
    MatchOptions = ["EQUALS"]
    Values       = ["Amazon Elastic Compute Cloud - Compute"]
  })
  
  tags = merge(local.common_tags, {
    Name = "ResourceGroupAnomalyDetector-${local.resource_suffix}"
    Type = "cost-anomaly-detector"
  })
}

# EventBridge Rule for Automated Resource Tagging
resource "aws_cloudwatch_event_rule" "auto_tag_resources" {
  count       = var.enable_eventbridge_tagging_rules ? 1 : 0
  name        = "AutoTagNewResources-${local.resource_suffix}"
  description = "Automatically tag new AWS resources"
  state       = "ENABLED"
  
  event_pattern = jsonencode({
    source        = ["aws.ec2", "aws.s3", "aws.rds"]
    detail-type   = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = var.eventbridge_monitored_services
      eventName   = ["RunInstances", "CreateBucket", "CreateDBInstance"]
    }
  })
  
  tags = merge(local.common_tags, {
    Name = "AutoTagNewResources-${local.resource_suffix}"
    Type = "eventbridge-rule"
  })
}

# IAM Role for EventBridge to invoke Systems Manager
resource "aws_iam_role" "eventbridge_role" {
  count = var.enable_eventbridge_tagging_rules ? 1 : 0
  name  = "EventBridge-SSM-Role-${local.resource_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
  
  tags = merge(local.common_tags, {
    Name = "EventBridge-SSM-Role-${local.resource_suffix}"
    Type = "iam-role"
  })
}

# IAM Policy for EventBridge to invoke Systems Manager
resource "aws_iam_role_policy" "eventbridge_ssm_policy" {
  count = var.enable_eventbridge_tagging_rules ? 1 : 0
  name  = "EventBridge-SSM-Policy-${local.resource_suffix}"
  role  = aws_iam_role.eventbridge_role[0].id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:StartAutomationExecution"
        ]
        Resource = var.enable_automation_documents ? [
          aws_ssm_document.automated_resource_tagging[0].arn
        ] : []
      }
    ]
  })
}

# EventBridge Target for Systems Manager Automation
resource "aws_cloudwatch_event_target" "ssm_automation_target" {
  count     = var.enable_eventbridge_tagging_rules && var.enable_automation_documents ? 1 : 0
  rule      = aws_cloudwatch_event_rule.auto_tag_resources[0].name
  target_id = "SSMAutomationTarget"
  arn       = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:automation-definition/${aws_ssm_document.automated_resource_tagging[0].name}"
  role_arn  = aws_iam_role.eventbridge_role[0].arn
  
  input_transformer {
    input_paths = {
      "resource-type" = "$.detail.eventName"
    }
    input_template = jsonencode({
      ResourceType = "<resource-type>"
      TagKey       = "AutoTagged"
      TagValue     = "true"
    })
  }
}

# CloudWatch Log Group for Systems Manager Automation
resource "aws_cloudwatch_log_group" "ssm_automation_logs" {
  name              = "/aws/ssm/automation"
  retention_in_days = 30
  
  tags = merge(local.common_tags, {
    Name = "ssm-automation-logs"
    Type = "log-group"
  })
}