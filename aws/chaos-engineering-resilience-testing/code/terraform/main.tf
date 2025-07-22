# AWS FIS and EventBridge Chaos Engineering Infrastructure

# Random ID for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name_suffix = random_id.suffix.hex
  
  common_tags = {
    Environment   = var.environment
    Project       = "ChaosEngineering"
    Terraform     = "true"
    Purpose       = "AWS-FIS-EventBridge-Recipe"
    ResourceGroup = "${var.resource_prefix}-${local.name_suffix}"
  }
}

# Data source for current AWS caller identity
data "aws_caller_identity" "current" {}

# Data source for current AWS region
data "aws_region" "current" {}

# SNS Topic for notifications
resource "aws_sns_topic" "fis_alerts" {
  name = "${var.resource_prefix}-fis-alerts-${local.name_suffix}"
  
  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-fis-alerts-${local.name_suffix}"
  })
}

# SNS Topic Policy
resource "aws_sns_topic_policy" "fis_alerts" {
  arn = aws_sns_topic.fis_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.fis_alerts.arn
      }
    ]
  })
}

# SNS Topic Subscription
resource "aws_sns_topic_subscription" "email_notification" {
  topic_arn = aws_sns_topic.fis_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# IAM Role for AWS FIS experiments
resource "aws_iam_role" "fis_experiment_role" {
  name = "${var.resource_prefix}-fis-experiment-role-${local.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "fis.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-fis-experiment-role-${local.name_suffix}"
  })
}

# IAM policy for FIS experiment role with specific permissions
resource "aws_iam_role_policy" "fis_experiment_policy" {
  name = "${var.resource_prefix}-fis-experiment-policy"
  role = aws_iam_role.fis_experiment_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:TerminateInstances",
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:RebootInstances",
          "ssm:SendCommand",
          "ssm:ListCommandInvocations",
          "ssm:DescribeInstanceInformation",
          "cloudwatch:DescribeAlarms"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/ChaosReady" = "true"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# CloudWatch Alarm for high error rate (stop condition)
resource "aws_cloudwatch_metric_alarm" "high_error_rate" {
  alarm_name          = "${var.resource_prefix}-high-error-rate-${local.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4XXError"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Sum"
  threshold           = var.error_rate_threshold
  alarm_description   = "Stop FIS experiment on high error rate"
  treat_missing_data  = "notBreaching"

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-high-error-rate-${local.name_suffix}"
  })
}

# CloudWatch Alarm for high CPU utilization
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.resource_prefix}-high-cpu-${local.name_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = var.high_cpu_threshold
  alarm_description   = "Monitor CPU during FIS experiments"

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-high-cpu-${local.name_suffix}"
  })
}

# AWS FIS Experiment Template
resource "aws_fis_experiment_template" "chaos_experiment" {
  description = "Multi-action chaos experiment for resilience testing"
  role_arn    = aws_iam_role.fis_experiment_role.arn

  # Stop conditions
  stop_condition {
    source = "aws:cloudwatch:alarm"
    value  = aws_cloudwatch_metric_alarm.high_error_rate.arn
  }

  # Target EC2 instances with ChaosReady tag
  target {
    name           = "ec2-instances"
    resource_type  = "aws:ec2:instance"
    selection_mode = "COUNT(1)"
    
    resource_tags = var.target_instance_tags
  }

  # CPU stress action
  action {
    name        = "cpu-stress"
    action_id   = "aws:ssm:send-command"
    description = "Inject CPU stress on EC2 instances"

    parameter {
      key   = "documentArn"
      value = "arn:aws:ssm:${data.aws_region.current.name}::document/AWSFIS-Run-CPU-Stress"
    }

    parameter {
      key   = "documentParameters"
      value = jsonencode({
        DurationSeconds = tostring(var.cpu_stress_duration)
        CPU            = "0"
        LoadPercent    = tostring(var.cpu_load_percent)
      })
    }

    parameter {
      key   = "duration"
      value = "PT${ceil(var.cpu_stress_duration / 60) + 1}M"
    }

    target {
      key   = "Instances"
      value = "ec2-instances"
    }
  }

  # Instance termination action (runs after CPU stress)
  action {
    name        = "terminate-instance"
    action_id   = "aws:ec2:terminate-instances"
    description = "Terminate EC2 instance to test recovery"

    target {
      key   = "Instances"
      value = "ec2-instances"
    }

    start_after = ["cpu-stress"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-chaos-experiment-${local.name_suffix}"
  })
}

# IAM Role for EventBridge to publish to SNS
resource "aws_iam_role" "eventbridge_sns_role" {
  name = "${var.resource_prefix}-eventbridge-sns-role-${local.name_suffix}"

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
    Name = "${var.resource_prefix}-eventbridge-sns-role-${local.name_suffix}"
  })
}

# IAM policy for EventBridge to publish to SNS
resource "aws_iam_role_policy" "eventbridge_sns_policy" {
  name = "${var.resource_prefix}-eventbridge-sns-policy"
  role = aws_iam_role.eventbridge_sns_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sns:Publish"
        Resource = aws_sns_topic.fis_alerts.arn
      }
    ]
  })
}

# EventBridge Rule for FIS state changes
resource "aws_cloudwatch_event_rule" "fis_state_changes" {
  name        = "${var.resource_prefix}-fis-state-changes-${local.name_suffix}"
  description = "Capture all FIS experiment state changes"

  event_pattern = jsonencode({
    source      = ["aws.fis"]
    detail-type = ["FIS Experiment State Change"]
  })

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-fis-state-changes-${local.name_suffix}"
  })
}

# EventBridge Target for SNS notifications
resource "aws_cloudwatch_event_target" "sns_target" {
  rule      = aws_cloudwatch_event_rule.fis_state_changes.name
  target_id = "SNSTarget"
  arn       = aws_sns_topic.fis_alerts.arn

  input_transformer {
    input_paths = {
      state      = "$.detail.state"
      experiment = "$.detail.experimentId"
      template   = "$.detail.experimentTemplateId"
    }
    input_template = jsonencode({
      message = "FIS Experiment <experiment> (Template: <template>) state changed to: <state>"
      subject = "AWS FIS Experiment State Change"
    })
  }
}

# IAM Role for EventBridge Scheduler
resource "aws_iam_role" "scheduler_role" {
  count = var.enable_automated_schedule ? 1 : 0
  name  = "${var.resource_prefix}-scheduler-role-${local.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.resource_prefix}-scheduler-role-${local.name_suffix}"
  })
}

# IAM policy for EventBridge Scheduler to start FIS experiments
resource "aws_iam_role_policy" "scheduler_fis_policy" {
  count = var.enable_automated_schedule ? 1 : 0
  name  = "${var.resource_prefix}-scheduler-fis-policy"
  role  = aws_iam_role.scheduler_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "fis:StartExperiment"
        Resource = [
          aws_fis_experiment_template.chaos_experiment.arn,
          "arn:aws:fis:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:experiment/*"
        ]
      }
    ]
  })
}

# EventBridge Schedule for automated experiments
resource "aws_scheduler_schedule" "chaos_experiment_schedule" {
  count = var.enable_automated_schedule ? 1 : 0
  name  = "${var.resource_prefix}-chaos-schedule-${local.name_suffix}"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = var.experiment_schedule

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:fis:startExperiment"
    role_arn = aws_iam_role.scheduler_role[0].arn

    input = jsonencode({
      experimentTemplateId = aws_fis_experiment_template.chaos_experiment.id
    })
  }
}

# CloudWatch Dashboard for experiment monitoring
resource "aws_cloudwatch_dashboard" "chaos_monitoring" {
  dashboard_name = "${var.resource_prefix}-chaos-monitoring-${local.name_suffix}"

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
            ["AWS/FIS", "ExperimentsStarted", { "stat" = "Sum" }],
            [".", "ExperimentsStopped", { "stat" = "Sum" }],
            [".", "ExperimentsFailed", { "stat" = "Sum" }]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "FIS Experiment Status"
          view   = "timeSeries"
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
            ["AWS/EC2", "CPUUtilization", { "stat" = "Average" }],
            ["AWS/ApplicationELB", "TargetResponseTime", { "stat" = "Average" }],
            [".", "HTTPCode_Target_4XX_Count", { "stat" = "Sum" }]
          ]
          period = 60
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Application Health During Experiments"
          view   = "timeSeries"
        }
      }
    ]
  })
}