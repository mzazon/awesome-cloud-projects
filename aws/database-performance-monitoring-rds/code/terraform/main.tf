# Data sources for existing resources
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_vpc" "default" {
  count   = var.vpc_id == "" ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = length(var.subnet_ids) == 0 ? 1 : 0
  
  filter {
    name   = "vpc-id"
    values = [var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id]
  }
}

# Random suffix for resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  # Resource identifiers
  resource_suffix = random_string.suffix.result
  vpc_id          = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default[0].id
  subnet_ids      = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default[0].ids
  
  # Resource names
  db_instance_id       = "${var.project_name}-db-${local.resource_suffix}"
  db_subnet_group_name = "${var.project_name}-subnet-group-${local.resource_suffix}"
  sns_topic_name       = "${var.project_name}-alerts-${local.resource_suffix}"
  lambda_function_name = "${var.project_name}-analyzer-${local.resource_suffix}"
  s3_bucket_name       = "${var.project_name}-reports-${local.resource_suffix}"
  
  # Common tags
  common_tags = merge(
    {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
    },
    var.additional_tags
  )
}

# S3 bucket for performance reports
resource "aws_s3_bucket" "performance_reports" {
  bucket = local.s3_bucket_name
  
  tags = merge(local.common_tags, {
    Name = "Performance Reports Storage"
  })
}

resource "aws_s3_bucket_versioning" "performance_reports" {
  bucket = aws_s3_bucket.performance_reports.id
  versioning_configuration {
    status = var.s3_bucket_versioning ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "performance_reports" {
  count  = var.s3_bucket_encryption ? 1 : 0
  bucket = aws_s3_bucket.performance_reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "performance_reports" {
  bucket = aws_s3_bucket.performance_reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SNS topic for performance alerts
resource "aws_sns_topic" "performance_alerts" {
  name = local.sns_topic_name
  
  tags = merge(local.common_tags, {
    Name = "Performance Alerts Topic"
  })
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email_alerts" {
  count     = var.notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.performance_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# IAM role for RDS enhanced monitoring
resource "aws_iam_role" "rds_monitoring_role" {
  name = "${var.project_name}-rds-monitoring-role-${local.resource_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "RDS Enhanced Monitoring Role"
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring_policy" {
  role       = aws_iam_role.rds_monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Security group for RDS instance
resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg-${local.resource_suffix}"
  description = "Security group for RDS instance"
  vpc_id      = local.vpc_id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "RDS Security Group"
  })
}

# DB subnet group
resource "aws_db_subnet_group" "main" {
  name       = local.db_subnet_group_name
  subnet_ids = local.subnet_ids

  tags = merge(local.common_tags, {
    Name = "DB Subnet Group"
  })
}

# RDS instance with Performance Insights
resource "aws_db_instance" "main" {
  identifier = local.db_instance_id
  
  # Engine configuration
  engine         = var.db_engine
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class
  
  # Storage configuration
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp2"
  storage_encrypted = true
  
  # Database configuration
  db_name  = "testdb"
  username = var.db_username
  password = var.db_password
  
  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = var.db_publicly_accessible
  
  # Performance Insights configuration
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_retention_period
  
  # Enhanced monitoring configuration
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring_role.arn : null
  
  # CloudWatch logs configuration
  enabled_cloudwatch_logs_exports = ["error", "general", "slow-query"]
  
  # Backup configuration
  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  # Deletion protection
  deletion_protection = false
  skip_final_snapshot = true
  
  tags = merge(local.common_tags, {
    Name = "Performance Insights Database"
  })
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role-${local.resource_suffix}"

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
    Name = "Performance Analyzer Lambda Role"
  })
}

# IAM policy for Lambda function
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy-${local.resource_suffix}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "pi:DescribeDimensionKeys",
          "pi:GetResourceMetrics",
          "pi:ListAvailableResourceDimensions",
          "pi:ListAvailableResourceMetrics"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.performance_reports.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  source {
    content = templatefile("${path.module}/lambda_function.py", {
      # Template variables can be passed here if needed
    })
    filename = "lambda_function.py"
  }
}

# Lambda function for performance analysis
resource "aws_lambda_function" "performance_analyzer" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = local.lambda_function_name
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = var.lambda_runtime
  timeout         = var.lambda_timeout
  memory_size     = var.lambda_memory_size
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      PI_RESOURCE_ID = aws_db_instance.main.resource_id
      S3_BUCKET_NAME = aws_s3_bucket.performance_reports.bucket
    }
  }

  tags = merge(local.common_tags, {
    Name = "Performance Analyzer Function"
  })
}

# CloudWatch log group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name = "Lambda Log Group"
  })
}

# EventBridge rule for scheduled analysis
resource "aws_cloudwatch_event_rule" "performance_analysis_trigger" {
  name        = "${var.project_name}-analysis-trigger-${local.resource_suffix}"
  description = "Trigger performance analysis Lambda function"
  
  schedule_expression = var.analysis_schedule
  
  tags = merge(local.common_tags, {
    Name = "Performance Analysis Trigger"
  })
}

# EventBridge target for Lambda function
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.performance_analysis_trigger.name
  target_id = "PerformanceAnalysisLambdaTarget"
  arn       = aws_lambda_function.performance_analyzer.arn
}

# Permission for EventBridge to invoke Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.performance_analyzer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.performance_analysis_trigger.arn
}

# CloudWatch alarms for database performance monitoring
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.project_name}-high-cpu-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_threshold
  alarm_description   = "This metric monitors RDS CPU utilization"
  alarm_actions       = [aws_sns_topic.performance_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = merge(local.common_tags, {
    Name = "High CPU Utilization Alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "high_connections" {
  alarm_name          = "${var.project_name}-high-connections-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.connection_threshold
  alarm_description   = "This metric monitors RDS database connections"
  alarm_actions       = [aws_sns_topic.performance_alerts.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.main.id
  }

  tags = merge(local.common_tags, {
    Name = "High Database Connections Alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "high_load_events" {
  alarm_name          = "${var.project_name}-high-load-events-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HighLoadEvents"
  namespace           = "RDS/PerformanceInsights"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.high_load_events_threshold
  alarm_description   = "This metric monitors high load events from Performance Insights"
  alarm_actions       = [aws_sns_topic.performance_alerts.arn]

  tags = merge(local.common_tags, {
    Name = "High Load Events Alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "problematic_queries" {
  alarm_name          = "${var.project_name}-problematic-queries-${local.resource_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ProblematicQueries"
  namespace           = "RDS/PerformanceInsights"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.problematic_queries_threshold
  alarm_description   = "This metric monitors problematic SQL queries from Performance Insights"
  alarm_actions       = [aws_sns_topic.performance_alerts.arn]

  tags = merge(local.common_tags, {
    Name = "Problematic Queries Alarm"
  })
}

# CloudWatch anomaly detection for database connections
resource "aws_cloudwatch_anomaly_detector" "database_connections" {
  metric_math_anomaly_detector {
    metric_data_queries {
      id = "m1"
      metric_stat {
        metric {
          metric_name = "DatabaseConnections"
          namespace   = "AWS/RDS"
          dimensions = {
            DBInstanceIdentifier = aws_db_instance.main.id
          }
        }
        period = 300
        stat   = "Average"
      }
    }
  }
}

# CloudWatch dashboard for performance monitoring
resource "aws_cloudwatch_dashboard" "performance_dashboard" {
  dashboard_name = "${var.project_name}-dashboard-${local.resource_suffix}"

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
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.main.id],
            [".", "CPUUtilization", ".", "."],
            [".", "ReadLatency", ".", "."],
            [".", "WriteLatency", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "RDS Core Performance Metrics"
          yAxis = {
            left = {
              min = 0
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
            ["RDS/PerformanceInsights", "HighLoadEvents"],
            [".", "ProblematicQueries"]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Performance Insights Analysis Results"
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
            ["AWS/RDS", "ReadIOPS", "DBInstanceIdentifier", aws_db_instance.main.id],
            [".", "WriteIOPS", ".", "."],
            [".", "ReadThroughput", ".", "."],
            [".", "WriteThroughput", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "I/O Performance Metrics"
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          query  = "SOURCE '/aws/rds/instance/${aws_db_instance.main.id}/slowquery'\n| fields @timestamp, @message\n| sort @timestamp desc\n| limit 20"
          region = var.aws_region
          title  = "Recent Slow Query Log Entries"
        }
      }
    ]
  })
}

# Lambda function source code
resource "local_file" "lambda_function" {
  content = templatefile("${path.module}/lambda_function.py.tpl", {
    # Add any template variables here if needed
  })
  filename = "${path.module}/lambda_function.py"
}

# Create the Lambda function Python code
resource "local_file" "lambda_function_code" {
  content = <<-EOF
import json
import boto3
import datetime
import os
from decimal import Decimal

def lambda_handler(event, context):
    pi_client = boto3.client('pi')
    s3_client = boto3.client('s3')
    cloudwatch = boto3.client('cloudwatch')
    
    # Get Performance Insights resource ID from environment
    resource_id = os.environ.get('PI_RESOURCE_ID')
    bucket_name = os.environ.get('S3_BUCKET_NAME')
    
    # Define time range for analysis (last hour)
    end_time = datetime.datetime.utcnow()
    start_time = end_time - datetime.timedelta(hours=1)
    
    try:
        # Get database load metrics
        response = pi_client.get_resource_metrics(
            ServiceType='RDS',
            Identifier=resource_id,
            StartTime=start_time,
            EndTime=end_time,
            PeriodInSeconds=300,
            MetricQueries=[
                {
                    'Metric': 'db.load.avg',
                    'GroupBy': {'Group': 'db.wait_event', 'Limit': 10}
                },
                {
                    'Metric': 'db.load.avg',
                    'GroupBy': {'Group': 'db.sql_tokenized', 'Limit': 10}
                }
            ]
        )
        
        # Analyze performance patterns
        analysis_results = analyze_performance_data(response)
        
        # Store results in S3
        report_key = f"performance-reports/{datetime.datetime.utcnow().strftime('%Y/%m/%d/%H')}/analysis.json"
        s3_client.put_object(
            Bucket=bucket_name,
            Key=report_key,
            Body=json.dumps(analysis_results, default=str),
            ContentType='application/json'
        )
        
        # Send custom metrics to CloudWatch
        publish_custom_metrics(cloudwatch, analysis_results)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Performance analysis completed',
                'report_location': f's3://{bucket_name}/{report_key}'
            })
        }
        
    except Exception as e:
        print(f"Error in performance analysis: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def analyze_performance_data(response):
    """Analyze Performance Insights data for anomalies and patterns"""
    analysis = {
        'timestamp': datetime.datetime.utcnow().isoformat(),
        'metrics_analyzed': len(response['MetricList']),
        'high_load_events': [],
        'problematic_queries': [],
        'recommendations': []
    }
    
    for metric in response['MetricList']:
        if 'Dimensions' in metric['Key']:
            # Analyze wait events
            if 'db.wait_event.name' in metric['Key']['Dimensions']:
                wait_event = metric['Key']['Dimensions']['db.wait_event.name']
                avg_load = sum(dp['Value'] for dp in metric['DataPoints']) / len(metric['DataPoints'])
                
                if avg_load > 1.0:  # High load threshold
                    analysis['high_load_events'].append({
                        'wait_event': wait_event,
                        'average_load': avg_load
                    })
            
            # Analyze SQL queries
            if 'db.sql_tokenized.statement' in metric['Key']['Dimensions']:
                sql_statement = metric['Key']['Dimensions']['db.sql_tokenized.statement']
                avg_load = sum(dp['Value'] for dp in metric['DataPoints']) / len(metric['DataPoints'])
                
                if avg_load > 0.5:  # Problematic query threshold
                    analysis['problematic_queries'].append({
                        'sql_statement': sql_statement[:200] + '...' if len(sql_statement) > 200 else sql_statement,
                        'average_load': avg_load
                    })
    
    # Generate recommendations
    if analysis['high_load_events']:
        analysis['recommendations'].append("Consider investigating high wait events and optimizing queries")
    
    if analysis['problematic_queries']:
        analysis['recommendations'].append("Review and optimize high-load SQL queries")
    
    return analysis

def publish_custom_metrics(cloudwatch, analysis):
    """Publish custom metrics to CloudWatch"""
    try:
        cloudwatch.put_metric_data(
            Namespace='RDS/PerformanceInsights',
            MetricData=[
                {
                    'MetricName': 'HighLoadEvents',
                    'Value': len(analysis['high_load_events']),
                    'Unit': 'Count',
                    'Timestamp': datetime.datetime.utcnow()
                },
                {
                    'MetricName': 'ProblematicQueries',
                    'Value': len(analysis['problematic_queries']),
                    'Unit': 'Count',
                    'Timestamp': datetime.datetime.utcnow()
                }
            ]
        )
    except Exception as e:
        print(f"Error publishing custom metrics: {str(e)}")
EOF
  filename = "${path.module}/lambda_function.py"
}