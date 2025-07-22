# ==============================================================================
# DATA SOURCES
# ==============================================================================

# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Get current AWS region
data "aws_region" "current" {}

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# ==============================================================================
# RANDOM RESOURCES FOR UNIQUE NAMING
# ==============================================================================

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# ==============================================================================
# NETWORKING INFRASTRUCTURE
# ==============================================================================

# VPC for VMware Cloud on AWS connectivity
resource "aws_vpc" "vmware_migration" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "vmware-migration-vpc"
  }
}

# Internet Gateway for VPC
resource "aws_internet_gateway" "vmware_migration" {
  vpc_id = aws_vpc.vmware_migration.id

  tags = {
    Name = "vmware-migration-igw"
  }
}

# Subnet for VMware Cloud connectivity
resource "aws_subnet" "vmware_migration" {
  vpc_id                  = aws_vpc.vmware_migration.id
  cidr_block              = var.subnet_cidr
  availability_zone       = "${var.aws_region}${var.availability_zone}"
  map_public_ip_on_launch = true

  tags = {
    Name = "vmware-migration-subnet"
  }
}

# Route table for public subnet
resource "aws_route_table" "vmware_migration" {
  vpc_id = aws_vpc.vmware_migration.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.vmware_migration.id
  }

  tags = {
    Name = "vmware-migration-rt"
  }
}

# Associate route table with subnet
resource "aws_route_table_association" "vmware_migration" {
  subnet_id      = aws_subnet.vmware_migration.id
  route_table_id = aws_route_table.vmware_migration.id
}

# ==============================================================================
# SECURITY GROUPS
# ==============================================================================

# Security group for HCX traffic
resource "aws_security_group" "hcx" {
  name        = "vmware-hcx-sg"
  description = "Security group for VMware HCX traffic"
  vpc_id      = aws_vpc.vmware_migration.id

  # HTTPS traffic for HCX management
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "HTTPS for HCX management"
  }

  # HCX Cloud Manager
  ingress {
    from_port   = 9443
    to_port     = 9443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "HCX Cloud Manager"
  }

  # HCX Service Mesh
  ingress {
    from_port   = 8043
    to_port     = 8043
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "HCX Service Mesh"
  }

  # HCX Mobility traffic
  ingress {
    from_port   = 902
    to_port     = 902
    protocol    = "tcp"
    cidr_blocks = ["192.168.0.0/16"]
    description = "HCX Mobility traffic"
  }

  # vMotion traffic
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["192.168.0.0/16"]
    description = "vMotion traffic"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "vmware-hcx-sg"
  }
}

# Security group for MGN replication servers
resource "aws_security_group" "mgn_replication" {
  count       = var.enable_mgn ? 1 : 0
  name        = "mgn-replication-sg"
  description = "Security group for MGN replication servers"
  vpc_id      = aws_vpc.vmware_migration.id

  # MGN replication traffic
  ingress {
    from_port   = 1500
    to_port     = 1500
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "MGN replication traffic"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "mgn-replication-sg"
  }
}

# ==============================================================================
# DIRECT CONNECT (OPTIONAL)
# ==============================================================================

# Direct Connect Gateway for hybrid connectivity
resource "aws_dx_gateway" "vmware_migration" {
  count           = var.enable_direct_connect ? 1 : 0
  name            = "vmware-migration-dx-gateway"
  amazon_side_asn = "64512"

  tags = {
    Name = "vmware-migration-dx-gateway"
  }
}

# Direct Connect Virtual Interface (only if connection ID is provided)
resource "aws_dx_private_virtual_interface" "vmware_migration" {
  count             = var.enable_direct_connect && var.direct_connect_connection_id != "" ? 1 : 0
  connection_id     = var.direct_connect_connection_id
  name              = "vmware-migration-vif"
  vlan              = var.direct_connect_vlan
  address_family    = "ipv4"
  bgp_asn           = var.direct_connect_asn
  customer_address  = var.direct_connect_customer_address
  amazon_address    = var.direct_connect_amazon_address
  dx_gateway_id     = aws_dx_gateway.vmware_migration[0].id

  tags = {
    Name = "vmware-migration-vif"
  }
}

# ==============================================================================
# IAM ROLES AND POLICIES
# ==============================================================================

# IAM role for VMware Cloud on AWS
resource "aws_iam_role" "vmware_cloud_service_role" {
  name = "VMwareCloudOnAWS-ServiceRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::063048924651:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = {
    Name = "VMwareCloudOnAWS-ServiceRole"
  }
}

# Attach VMware Cloud on AWS service policy
resource "aws_iam_role_policy_attachment" "vmware_cloud_service_policy" {
  role       = aws_iam_role.vmware_cloud_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/VMwareCloudOnAWSServiceRolePolicy"
}

# IAM role for Lambda functions
resource "aws_iam_role" "lambda_execution_role" {
  name = "vmware-migration-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "vmware-migration-lambda-role"
  }
}

# Lambda execution policy
resource "aws_iam_role_policy" "lambda_execution_policy" {
  name = "vmware-migration-lambda-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "cloudwatch:PutMetricData",
          "sns:Publish",
          "s3:GetObject",
          "s3:PutObject",
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Resource = "*"
      }
    ]
  })
}

# ==============================================================================
# AWS APPLICATION MIGRATION SERVICE (MGN)
# ==============================================================================

# Initialize MGN service
resource "aws_mgn_service_configuration" "main" {
  count = var.enable_mgn ? 1 : 0

  depends_on = [time_sleep.mgn_initialization]
}

# Wait for MGN service initialization
resource "time_sleep" "mgn_initialization" {
  count           = var.enable_mgn ? 1 : 0
  create_duration = "30s"
}

# MGN replication configuration template
resource "aws_mgn_replication_configuration_template" "main" {
  count = var.enable_mgn ? 1 : 0

  associate_default_security_group = true
  bandwidth_throttling             = var.mgn_bandwidth_throttling
  create_public_ip                = true
  data_plane_routing              = "PRIVATE_IP"
  default_large_staging_disk_type = var.mgn_default_large_staging_disk_type
  ebs_encryption                  = "DEFAULT"
  replication_server_instance_type = var.mgn_replication_server_instance_type
  replication_servers_security_groups_ids = var.enable_mgn ? [aws_security_group.mgn_replication[0].id] : []
  staging_area_subnet_id          = aws_subnet.vmware_migration.id
  use_dedicated_replication_server = false

  staging_area_tags = {
    Environment = var.environment
    Project     = "VMware Migration"
  }

  depends_on = [aws_mgn_service_configuration.main]
}

# ==============================================================================
# S3 BACKUP INFRASTRUCTURE
# ==============================================================================

# S3 bucket for VMware backups
resource "aws_s3_bucket" "vmware_backup" {
  bucket = "vmware-backup-${random_string.suffix.result}-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "vmware-backup-bucket"
  }
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "vmware_backup" {
  bucket = aws_s3_bucket.vmware_backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "vmware_backup" {
  bucket = aws_s3_bucket.vmware_backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "vmware_backup" {
  bucket = aws_s3_bucket.vmware_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "vmware_backup" {
  bucket = aws_s3_bucket.vmware_backup.id

  rule {
    id     = "VMwareBackupLifecycle"
    status = "Enabled"

    transition {
      days          = var.backup_transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.backup_transition_to_glacier_days
      storage_class = "GLACIER"
    }

    expiration {
      days = var.backup_retention_days
    }
  }
}

# ==============================================================================
# DYNAMODB TABLE FOR MIGRATION TRACKING
# ==============================================================================

# DynamoDB table for migration tracking
resource "aws_dynamodb_table" "migration_tracking" {
  name           = "VMwareMigrationTracking"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "VMName"
  range_key      = "MigrationWave"

  attribute {
    name = "VMName"
    type = "S"
  }

  attribute {
    name = "MigrationWave"
    type = "S"
  }

  tags = {
    Name = "VMwareMigrationTracking"
  }
}

# Populate migration waves in DynamoDB
resource "aws_dynamodb_table_item" "migration_waves" {
  count      = length(var.migration_waves)
  table_name = aws_dynamodb_table.migration_tracking.name
  hash_key   = aws_dynamodb_table.migration_tracking.hash_key
  range_key  = aws_dynamodb_table.migration_tracking.range_key

  item = jsonencode({
    VMName = {
      S = "Wave-${var.migration_waves[count.index].wave}"
    }
    MigrationWave = {
      S = "Wave-${var.migration_waves[count.index].wave}"
    }
    Description = {
      S = var.migration_waves[count.index].description
    }
    Priority = {
      S = var.migration_waves[count.index].priority
    }
    VMs = {
      SS = var.migration_waves[count.index].vms
    }
    MigrationType = {
      S = var.migration_waves[count.index].migration_type
    }
    Status = {
      S = "Planned"
    }
    CreatedAt = {
      S = timestamp()
    }
  })
}

# ==============================================================================
# CLOUDWATCH LOGGING AND MONITORING
# ==============================================================================

# CloudWatch log group for VMware operations
resource "aws_cloudwatch_log_group" "vmware_migration" {
  name              = "/aws/vmware/migration"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = {
    Name = "vmware-migration-logs"
  }
}

# CloudWatch dashboard for VMware migration
resource "aws_cloudwatch_dashboard" "vmware_migration" {
  dashboard_name = "VMware-Migration-Dashboard"

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
            ["AWS/VMwareCloudOnAWS", "HostHealth"],
            ["VMware/Migration", "MigrationProgress"],
            ["AWS/ApplicationMigrationService", "ReplicationProgress"]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "VMware Migration Status"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 12
        height = 6

        properties = {
          query   = "SOURCE '/aws/vmware/migration' | fields @timestamp, @message | sort @timestamp desc | limit 50"
          region  = var.aws_region
          title   = "Recent Migration Events"
          view    = "table"
        }
      }
    ]
  })
}

# ==============================================================================
# SNS TOPIC FOR NOTIFICATIONS
# ==============================================================================

# SNS topic for VMware migration alerts
resource "aws_sns_topic" "vmware_migration_alerts" {
  name = "VMware-Migration-Alerts"

  tags = {
    Name = "VMware-Migration-Alerts"
  }
}

# SNS topic subscription for email notifications
resource "aws_sns_topic_subscription" "email_notifications" {
  topic_arn = aws_sns_topic.vmware_migration_alerts.arn
  protocol  = "email"
  endpoint  = var.admin_email
}

# ==============================================================================
# CLOUDWATCH ALARMS
# ==============================================================================

# CloudWatch alarm for SDDC health
resource "aws_cloudwatch_metric_alarm" "sddc_host_health" {
  alarm_name          = "VMware-SDDC-HostHealth"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HostHealth"
  namespace           = "AWS/VMwareCloudOnAWS"
  period              = "300"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "Monitor VMware SDDC host health"
  alarm_actions       = [aws_sns_topic.vmware_migration_alerts.arn]

  tags = {
    Name = "VMware-SDDC-HostHealth"
  }
}

# ==============================================================================
# EVENTBRIDGE RULES
# ==============================================================================

# EventBridge rule for SDDC state changes
resource "aws_cloudwatch_event_rule" "sddc_state_change" {
  name        = "VMware-SDDC-StateChange"
  description = "Capture VMware SDDC state changes"

  event_pattern = jsonencode({
    source      = ["aws.vmware"]
    detail-type = ["VMware Cloud on AWS SDDC State Change"]
  })

  tags = {
    Name = "VMware-SDDC-StateChange"
  }
}

# EventBridge target for SNS notifications
resource "aws_cloudwatch_event_target" "sns_target" {
  rule      = aws_cloudwatch_event_rule.sddc_state_change.name
  target_id = "VMwareMigrationSNSTarget"
  arn       = aws_sns_topic.vmware_migration_alerts.arn
}

# EventBridge permission for SNS
resource "aws_sns_topic_policy" "vmware_migration_alerts" {
  arn = aws_sns_topic.vmware_migration_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sns:Publish"
        Resource = aws_sns_topic.vmware_migration_alerts.arn
      }
    ]
  })
}

# ==============================================================================
# LAMBDA FUNCTIONS
# ==============================================================================

# Lambda function for migration orchestration
resource "aws_lambda_function" "migration_orchestrator" {
  filename      = "migration-orchestrator.zip"
  function_name = "VMware-Migration-Orchestrator"
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = "index.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  environment {
    variables = {
      BACKUP_BUCKET   = aws_s3_bucket.vmware_backup.bucket
      SNS_TOPIC_ARN   = aws_sns_topic.vmware_migration_alerts.arn
      DYNAMODB_TABLE  = aws_dynamodb_table.migration_tracking.name
      AWS_REGION      = var.aws_region
    }
  }

  tags = {
    Name = "VMware-Migration-Orchestrator"
  }

  depends_on = [
    aws_iam_role_policy.lambda_execution_policy,
    aws_cloudwatch_log_group.lambda_migration_orchestrator
  ]
}

# CloudWatch log group for Lambda
resource "aws_cloudwatch_log_group" "lambda_migration_orchestrator" {
  name              = "/aws/lambda/VMware-Migration-Orchestrator"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = {
    Name = "lambda-migration-orchestrator-logs"
  }
}

# Create Lambda deployment package
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "migration-orchestrator.zip"
  source {
    content = <<EOF
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Lambda function to orchestrate VMware migration activities
    """
    # Initialize AWS clients
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    dynamodb = boto3.resource('dynamodb')
    
    # Get environment variables
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    dynamodb_table_name = os.environ['DYNAMODB_TABLE']
    
    try:
        # Parse event data
        wave_number = event.get('wave_number', 1)
        action = event.get('action', 'start')
        
        # Log migration activity
        print(f"Migration orchestrator: {action} for wave {wave_number}")
        
        # Update CloudWatch metrics
        cloudwatch.put_metric_data(
            Namespace='VMware/Migration',
            MetricData=[
                {
                    'MetricName': 'CurrentWave',
                    'Value': wave_number,
                    'Unit': 'Count'
                }
            ]
        )
        
        # Send SNS notification
        sns.publish(
            TopicArn=sns_topic_arn,
            Message=f"VMware Migration Wave {wave_number} has {action}ed",
            Subject=f"VMware Migration Update - Wave {wave_number}"
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Migration orchestration completed for wave {wave_number}')
        }
        
    except Exception as e:
        print(f"Error in migration orchestrator: {str(e)}")
        
        # Send error notification
        sns.publish(
            TopicArn=sns_topic_arn,
            Message=f"Error in migration orchestrator: {str(e)}",
            Subject="VMware Migration Error"
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
EOF
    filename = "index.py"
  }
}

# ==============================================================================
# COST MONITORING
# ==============================================================================

# AWS Budget for VMware Cloud on AWS
resource "aws_budgets_budget" "vmware_cloud_budget" {
  count = var.enable_cost_budget ? 1 : 0

  name         = "VMware-Cloud-Budget"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filters {
    service = ["VMware Cloud on AWS"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = var.budget_alert_threshold
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = [var.admin_email]
  }

  depends_on = [aws_sns_topic.vmware_migration_alerts]
}

# Cost Anomaly Detection
resource "aws_ce_anomaly_detector" "vmware_cost" {
  count = var.enable_cost_anomaly_detection ? 1 : 0

  name         = "VMware-Cost-Anomaly-Detector"
  monitor_type = "DIMENSIONAL"

  specification {
    dimension_key = "SERVICE"
    values        = ["VMware Cloud on AWS"]
    match_options = ["EQUALS"]
  }

  tags = {
    Name = "VMware-Cost-Anomaly-Detector"
  }
}

# ==============================================================================
# VPC FLOW LOGS (OPTIONAL)
# ==============================================================================

# VPC Flow Logs for network monitoring
resource "aws_flow_log" "vmware_vpc" {
  count           = var.enable_vpc_flow_logs ? 1 : 0
  iam_role_arn    = aws_iam_role.flow_log[0].arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.vmware_migration.id

  tags = {
    Name = "vmware-vpc-flow-logs"
  }
}

# CloudWatch log group for VPC Flow Logs
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count             = var.enable_vpc_flow_logs ? 1 : 0
  name              = "/aws/vpc/flowlogs"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = {
    Name = "vpc-flow-logs"
  }
}

# IAM role for VPC Flow Logs
resource "aws_iam_role" "flow_log" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  name  = "vmware-vpc-flow-log-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "vmware-vpc-flow-log-role"
  }
}

# IAM policy for VPC Flow Logs
resource "aws_iam_role_policy" "flow_log" {
  count = var.enable_vpc_flow_logs ? 1 : 0
  name  = "vmware-vpc-flow-log-policy"
  role  = aws_iam_role.flow_log[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# ==============================================================================
# CLOUDTRAIL (OPTIONAL)
# ==============================================================================

# CloudTrail for API logging
resource "aws_cloudtrail" "vmware_migration" {
  count                         = var.enable_cloudtrail ? 1 : 0
  name                          = "vmware-migration-cloudtrail"
  s3_bucket_name               = aws_s3_bucket.cloudtrail_logs[0].bucket
  s3_key_prefix               = "cloudtrail-logs/"
  include_global_service_events = true
  is_multi_region_trail        = true
  enable_logging               = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.vmware_backup.arn}/*"]
    }
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]

  tags = {
    Name = "vmware-migration-cloudtrail"
  }
}

# S3 bucket for CloudTrail logs
resource "aws_s3_bucket" "cloudtrail_logs" {
  count         = var.enable_cloudtrail ? 1 : 0
  bucket        = "vmware-migration-cloudtrail-${random_string.suffix.result}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name = "vmware-migration-cloudtrail-logs"
  }
}

# S3 bucket policy for CloudTrail
resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

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
        Resource = aws_s3_bucket.cloudtrail_logs[0].arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# S3 bucket public access block for CloudTrail
resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  count  = var.enable_cloudtrail ? 1 : 0
  bucket = aws_s3_bucket.cloudtrail_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}