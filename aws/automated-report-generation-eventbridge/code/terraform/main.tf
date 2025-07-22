# Terraform configuration for automated report generation with EventBridge Scheduler and S3
# This configuration creates a serverless reporting system that processes data from S3 and generates 
# reports on a schedule using EventBridge Scheduler, Lambda, and SES

# Data source to get current AWS caller information
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# Random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# S3 bucket for storing source data files
resource "aws_s3_bucket" "data_bucket" {
  bucket = "${var.data_bucket_prefix}-${random_id.suffix.hex}"

  tags = {
    Name        = "Data Bucket for Automated Reports"
    Environment = var.environment
    Project     = var.project_name
  }
}

# S3 bucket versioning configuration for data bucket
resource "aws_s3_bucket_versioning" "data_bucket_versioning" {
  bucket = aws_s3_bucket.data_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket public access block for data bucket security
resource "aws_s3_bucket_public_access_block" "data_bucket_pab" {
  bucket = aws_s3_bucket.data_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket server-side encryption for data bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "data_bucket_encryption" {
  bucket = aws_s3_bucket.data_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket for storing generated reports
resource "aws_s3_bucket" "reports_bucket" {
  bucket = "${var.reports_bucket_prefix}-${random_id.suffix.hex}"

  tags = {
    Name        = "Reports Bucket for Automated Reports"
    Environment = var.environment
    Project     = var.project_name
  }
}

# S3 bucket versioning configuration for reports bucket
resource "aws_s3_bucket_versioning" "reports_bucket_versioning" {
  bucket = aws_s3_bucket.reports_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket public access block for reports bucket security
resource "aws_s3_bucket_public_access_block" "reports_bucket_pab" {
  bucket = aws_s3_bucket.reports_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket server-side encryption for reports bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "reports_bucket_encryption" {
  bucket = aws_s3_bucket.reports_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 lifecycle configuration for reports bucket to manage costs
resource "aws_s3_bucket_lifecycle_configuration" "reports_lifecycle" {
  bucket = aws_s3_bucket.reports_bucket.id

  rule {
    id     = "reports_lifecycle"
    status = "Enabled"

    # Transition to Infrequent Access after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Delete reports after 365 days
    expiration {
      days = 365
    }
  }
}

# Sample sales data for testing (uploaded to S3)
resource "aws_s3_object" "sample_sales_data" {
  bucket      = aws_s3_bucket.data_bucket.id
  key         = "sales/sample_sales.csv"
  content     = <<-EOT
Date,Product,Sales,Region
2025-01-01,Product A,1000,North
2025-01-01,Product B,1500,South
2025-01-02,Product A,1200,North
2025-01-02,Product B,800,South
2025-01-03,Product A,1100,North
2025-01-03,Product B,1300,South
EOT
  content_type = "text/csv"

  tags = {
    Name        = "Sample Sales Data"
    Environment = var.environment
  }
}

# Sample inventory data for testing (uploaded to S3)
resource "aws_s3_object" "sample_inventory_data" {
  bucket      = aws_s3_bucket.data_bucket.id
  key         = "inventory/sample_inventory.csv"
  content     = <<-EOT
Product,Stock,Warehouse,Last_Updated
Product A,250,Warehouse 1,2025-01-03
Product B,180,Warehouse 1,2025-01-03
Product A,300,Warehouse 2,2025-01-03
Product B,220,Warehouse 2,2025-01-03
EOT
  content_type = "text/csv"

  tags = {
    Name        = "Sample Inventory Data"
    Environment = var.environment
  }
}

# IAM trust policy document for Lambda service
data "aws_iam_policy_document" "lambda_trust_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_execution_role" {
  name               = "${var.project_name}-lambda-role-${random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust_policy.json

  tags = {
    Name        = "Lambda Execution Role for Report Generator"
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM policy document for Lambda function permissions
data "aws_iam_policy_document" "lambda_permissions" {
  # S3 permissions for data and reports buckets
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.data_bucket.arn,
      "${aws_s3_bucket.data_bucket.arn}/*",
      aws_s3_bucket.reports_bucket.arn,
      "${aws_s3_bucket.reports_bucket.arn}/*"
    ]
  }

  # SES permissions for sending emails
  statement {
    effect = "Allow"
    actions = [
      "ses:SendEmail",
      "ses:SendRawEmail"
    ]
    resources = ["*"]
  }
}

# IAM policy for Lambda function
resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.project_name}-lambda-policy-${random_id.suffix.hex}"
  description = "IAM policy for Lambda report generator function"
  policy      = data.aws_iam_policy_document.lambda_permissions.json

  tags = {
    Name        = "Lambda Policy for Report Generator"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Attach AWS managed policy for basic Lambda execution
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach custom policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_custom_policy" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Lambda function code as a zip file
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  source {
    content = <<-EOT
import boto3
import csv
import json
import os
from datetime import datetime
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders
import io

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    ses = boto3.client('ses')
    
    data_bucket = os.environ['DATA_BUCKET']
    reports_bucket = os.environ['REPORTS_BUCKET']
    email_address = os.environ['EMAIL_ADDRESS']
    
    try:
        # Read sales data from S3
        response = s3.get_object(Bucket=data_bucket, Key='sales/sample_sales.csv')
        sales_data = response['Body'].read().decode('utf-8')
        
        # Read inventory data from S3
        response = s3.get_object(Bucket=data_bucket, Key='inventory/sample_inventory.csv')
        inventory_data = response['Body'].read().decode('utf-8')
        
        # Generate comprehensive report
        report_content = generate_report(sales_data, inventory_data)
        
        # Save report to S3 with timestamp
        report_key = f"reports/daily_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
        s3.put_object(
            Bucket=reports_bucket,
            Key=report_key,
            Body=report_content,
            ContentType='text/csv'
        )
        
        # Send email notification with report attachment
        send_email_report(ses, email_address, report_content, report_key)
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Report generated successfully: {report_key}')
        }
        
    except Exception as e:
        print(f"Error generating report: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error generating report: {str(e)}')
        }

def generate_report(sales_data, inventory_data):
    # Process sales data and calculate totals
    sales_reader = csv.DictReader(io.StringIO(sales_data))
    sales_summary = {}
    
    for row in sales_reader:
        product = row['Product']
        sales = int(row['Sales'])
        if product not in sales_summary:
            sales_summary[product] = 0
        sales_summary[product] += sales
    
    # Process inventory data and calculate totals
    inventory_reader = csv.DictReader(io.StringIO(inventory_data))
    inventory_summary = {}
    
    for row in inventory_reader:
        product = row['Product']
        stock = int(row['Stock'])
        if product not in inventory_summary:
            inventory_summary[product] = 0
        inventory_summary[product] += stock
    
    # Generate combined business report
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(['Product', 'Total Sales', 'Total Inventory', 'Sales Ratio'])
    
    for product in sales_summary:
        total_sales = sales_summary[product]
        total_inventory = inventory_summary.get(product, 0)
        sales_ratio = total_sales / total_inventory if total_inventory > 0 else 0
        writer.writerow([product, total_sales, total_inventory, f"{sales_ratio:.2f}"])
    
    return output.getvalue()

def send_email_report(ses, email_address, report_content, report_key):
    subject = f"Daily Business Report - {datetime.now().strftime('%Y-%m-%d')}"
    
    msg = MIMEMultipart()
    msg['From'] = email_address
    msg['To'] = email_address
    msg['Subject'] = subject
    
    body = f"""
Dear Team,

Please find attached the daily business report generated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}.

Report includes:
- Sales summary by product
- Inventory levels by product
- Sales ratio analysis

This report has been automatically generated and stored in S3 at: {report_key}

Best regards,
Automated Reporting System
"""
    
    msg.attach(MIMEText(body, 'plain'))
    
    # Attach CSV report
    attachment = MIMEBase('application', 'octet-stream')
    attachment.set_payload(report_content.encode())
    encoders.encode_base64(attachment)
    attachment.add_header(
        'Content-Disposition',
        f'attachment; filename=daily_report_{datetime.now().strftime("%Y%m%d")}.csv'
    )
    msg.attach(attachment)
    
    # Send email using SES
    ses.send_raw_email(
        Source=email_address,
        Destinations=[email_address],
        RawMessage={'Data': msg.as_string()}
    )
EOT
    filename = "lambda_function.py"
  }
}

# Lambda function for report generation
resource "aws_lambda_function" "report_generator" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.lambda_function_name}-${random_id.suffix.hex}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime         = "python3.9"
  timeout         = 300
  memory_size     = 512

  environment {
    variables = {
      DATA_BUCKET    = aws_s3_bucket.data_bucket.id
      REPORTS_BUCKET = aws_s3_bucket.reports_bucket.id
      EMAIL_ADDRESS  = var.verified_email
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_custom_policy,
  ]

  tags = {
    Name        = "Report Generator Lambda Function"
    Environment = var.environment
    Project     = var.project_name
  }
}

# CloudWatch Log Group for Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.report_generator.function_name}"
  retention_in_days = 14

  tags = {
    Name        = "Lambda Log Group for Report Generator"
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM trust policy document for EventBridge Scheduler
data "aws_iam_policy_document" "scheduler_trust_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# IAM role for EventBridge Scheduler
resource "aws_iam_role" "scheduler_execution_role" {
  name               = "${var.project_name}-scheduler-role-${random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.scheduler_trust_policy.json

  tags = {
    Name        = "EventBridge Scheduler Execution Role"
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM policy document for EventBridge Scheduler
data "aws_iam_policy_document" "scheduler_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = [aws_lambda_function.report_generator.arn]
  }
}

# IAM policy for EventBridge Scheduler
resource "aws_iam_policy" "scheduler_policy" {
  name        = "${var.project_name}-scheduler-policy-${random_id.suffix.hex}"
  description = "IAM policy for EventBridge Scheduler to invoke Lambda"
  policy      = data.aws_iam_policy_document.scheduler_permissions.json

  tags = {
    Name        = "EventBridge Scheduler Policy"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Attach policy to EventBridge Scheduler role
resource "aws_iam_role_policy_attachment" "scheduler_policy_attachment" {
  role       = aws_iam_role.scheduler_execution_role.name
  policy_arn = aws_iam_policy.scheduler_policy.arn
}

# EventBridge Schedule for daily report generation
resource "aws_scheduler_schedule" "daily_report_schedule" {
  name                         = "${var.schedule_name}-${random_id.suffix.hex}"
  description                  = "Daily business report generation schedule"
  state                        = "ENABLED"
  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = var.schedule_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.report_generator.arn
    role_arn = aws_iam_role.scheduler_execution_role.arn

    retry_policy {
      maximum_retry_attempts       = 3
      maximum_event_age_in_seconds = 86400
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.scheduler_policy_attachment,
  ]

  tags = {
    Name        = "Daily Report Schedule"
    Environment = var.environment
    Project     = var.project_name
  }
}

# SES email identity verification (manual step required)
resource "aws_ses_email_identity" "verified_email" {
  count = var.create_ses_identity ? 1 : 0
  email = var.verified_email

  tags = {
    Name        = "Verified Email for Reports"
    Environment = var.environment
    Project     = var.project_name
  }
}