#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Stack, StackProps, Duration, RemovalPolicy } from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as scheduler from 'aws-cdk-lib/aws-scheduler';
import * as ses from 'aws-cdk-lib/aws-ses';
import { Construct } from 'constructs';

/**
 * Stack for automated report generation using EventBridge Scheduler, Lambda, S3, and SES
 * This stack creates a serverless solution for generating and distributing business reports
 */
export class AutomatedReportGenerationStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    // Parameters for email configuration
    const verifiedEmail = new cdk.CfnParameter(this, 'VerifiedEmail', {
      type: 'String',
      description: 'Verified email address for SES to send reports',
      constraintDescription: 'Must be a valid email address verified in SES',
    });

    // Generate random suffix for unique resource names
    const randomSuffix = Math.random().toString(36).substring(2, 8);

    // S3 Bucket for storing source data
    const dataBucket = new s3.Bucket(this, 'DataBucket', {
      bucketName: `report-data-${randomSuffix}`,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // S3 Bucket for storing generated reports
    const reportsBucket = new s3.Bucket(this, 'ReportsBucket', {
      bucketName: `report-output-${randomSuffix}`,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'DeleteOldReports',
          enabled: true,
          expiration: Duration.days(90), // Auto-delete reports after 90 days
        },
      ],
    });

    // IAM Role for Lambda function execution
    const lambdaRole = new iam.Role(this, 'ReportGeneratorRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for report generator Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        S3Access: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:ListBucket',
              ],
              resources: [
                dataBucket.bucketArn,
                `${dataBucket.bucketArn}/*`,
                reportsBucket.bucketArn,
                `${reportsBucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
        SESAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ses:SendEmail',
                'ses:SendRawEmail',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Lambda function for report generation
    const reportGeneratorFunction = new lambda.Function(this, 'ReportGeneratorFunction', {
      functionName: `report-generator-${randomSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: Duration.minutes(5),
      memorySize: 512,
      description: 'Function to generate business reports from S3 data and send via email',
      environment: {
        DATA_BUCKET: dataBucket.bucketName,
        REPORTS_BUCKET: reportsBucket.bucketName,
        EMAIL_ADDRESS: verifiedEmail.valueAsString,
      },
      code: lambda.Code.fromInline(`
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
    """
    Main Lambda handler for automated report generation
    Processes S3 data, generates reports, and sends via email
    """
    s3 = boto3.client('s3')
    ses = boto3.client('ses')
    
    data_bucket = os.environ['DATA_BUCKET']
    reports_bucket = os.environ['REPORTS_BUCKET']
    email_address = os.environ['EMAIL_ADDRESS']
    
    try:
        print(f"Starting report generation for bucket: {data_bucket}")
        
        # Read sales data from S3
        try:
            response = s3.get_object(Bucket=data_bucket, Key='sales/sample_sales.csv')
            sales_data = response['Body'].read().decode('utf-8')
            print("Successfully retrieved sales data")
        except Exception as e:
            print(f"Warning: Could not retrieve sales data: {str(e)}")
            sales_data = "Date,Product,Sales,Region\\n2025-01-01,Sample Product,1000,North"
        
        # Read inventory data from S3
        try:
            response = s3.get_object(Bucket=data_bucket, Key='inventory/sample_inventory.csv')
            inventory_data = response['Body'].read().decode('utf-8')
            print("Successfully retrieved inventory data")
        except Exception as e:
            print(f"Warning: Could not retrieve inventory data: {str(e)}")
            inventory_data = "Product,Stock,Warehouse,Last_Updated\\nSample Product,250,Warehouse 1,2025-01-01"
        
        # Generate comprehensive report
        report_content = generate_report(sales_data, inventory_data)
        
        # Save report to S3 with timestamp
        report_key = f"reports/daily_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
        s3.put_object(
            Bucket=reports_bucket,
            Key=report_key,
            Body=report_content,
            ContentType='text/csv',
            ServerSideEncryption='AES256'
        )
        print(f"Report saved to S3: {report_key}")
        
        # Send email notification with report attachment
        send_email_report(ses, email_address, report_content, report_key)
        print("Email sent successfully")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Report generated successfully: {report_key}',
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        error_msg = f"Error generating report: {str(e)}"
        print(error_msg)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_msg,
                'timestamp': datetime.now().isoformat()
            })
        }

def generate_report(sales_data, inventory_data):
    """
    Generate comprehensive business report from sales and inventory data
    """
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
    writer.writerow(['Product', 'Total Sales', 'Total Inventory', 'Sales Ratio', 'Stock Status'])
    
    for product in sales_summary:
        total_sales = sales_summary[product]
        total_inventory = inventory_summary.get(product, 0)
        sales_ratio = total_sales / total_inventory if total_inventory > 0 else 0
        
        # Determine stock status
        if sales_ratio > 0.8:
            stock_status = "Low Stock - Reorder Needed"
        elif sales_ratio > 0.5:
            stock_status = "Medium Stock"
        else:
            stock_status = "High Stock"
        
        writer.writerow([product, total_sales, total_inventory, f"{sales_ratio:.2f}", stock_status])
    
    return output.getvalue()

def send_email_report(ses, email_address, report_content, report_key):
    """
    Send email with report attachment using Amazon SES
    """
    subject = f"Daily Business Report - {datetime.now().strftime('%Y-%m-%d')}"
    
    msg = MIMEMultipart()
    msg['From'] = email_address
    msg['To'] = email_address
    msg['Subject'] = subject
    
    # Generate email body with report summary
    lines = report_content.strip().split('\\n')
    report_summary = f"Generated {len(lines) - 1} product reports" if len(lines) > 1 else "No data available"
    
    body = f"""
Dear Team,

Please find attached the daily business report generated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} UTC.

Report Summary:
- {report_summary}
- Report includes sales summary, inventory levels, and stock status analysis
- Automated recommendations for restocking based on sales ratios

This report has been automatically generated and stored in S3 at: {report_key}

For questions about this report, please contact your system administrator.

Best regards,
Automated Reporting System
AWS EventBridge Scheduler + Lambda
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
      `),
    });

    // IAM Role for EventBridge Scheduler
    const schedulerRole = new iam.Role(this, 'EventBridgeSchedulerRole', {
      assumedBy: new iam.ServicePrincipal('scheduler.amazonaws.com'),
      description: 'Execution role for EventBridge Scheduler to invoke Lambda',
      inlinePolicies: {
        LambdaInvoke: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['lambda:InvokeFunction'],
              resources: [reportGeneratorFunction.functionArn],
            }),
          ],
        }),
      },
    });

    // EventBridge Schedule for daily report generation
    const reportSchedule = new scheduler.CfnSchedule(this, 'DailyReportSchedule', {
      name: `daily-reports-${randomSuffix}`,
      description: 'Daily business report generation at 9 AM UTC',
      scheduleExpression: 'cron(0 9 * * ? *)', // Daily at 9 AM UTC
      flexibleTimeWindow: {
        mode: 'OFF',
      },
      target: {
        arn: reportGeneratorFunction.functionArn,
        roleArn: schedulerRole.roleArn,
        input: JSON.stringify({
          source: 'EventBridge-Scheduler',
          'detail-type': 'Scheduled Report Generation',
          detail: {
            scheduleType: 'daily',
            timestamp: new Date().toISOString(),
          },
        }),
        retryPolicy: {
          maximumRetryAttempts: 3,
        },
      },
      state: 'ENABLED',
    });

    // Create sample data in S3 buckets using custom resource
    const sampleDataLambda = new lambda.Function(this, 'SampleDataFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.handler',
      timeout: Duration.minutes(2),
      code: lambda.Code.fromInline(`
import boto3
import json
import cfnresponse

def handler(event, context):
    if event['RequestType'] == 'Delete':
        cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
        return
    
    s3 = boto3.client('s3')
    bucket_name = event['ResourceProperties']['BucketName']
    
    try:
        # Sample sales data
        sales_csv = """Date,Product,Sales,Region
2025-01-01,Product A,1000,North
2025-01-01,Product B,1500,South
2025-01-02,Product A,1200,North
2025-01-02,Product B,800,South
2025-01-03,Product A,1100,North
2025-01-03,Product B,1300,South"""
        
        # Sample inventory data
        inventory_csv = """Product,Stock,Warehouse,Last_Updated
Product A,250,Warehouse 1,2025-01-03
Product B,180,Warehouse 1,2025-01-03
Product A,300,Warehouse 2,2025-01-03
Product B,220,Warehouse 2,2025-01-03"""
        
        # Upload sample data
        s3.put_object(
            Bucket=bucket_name,
            Key='sales/sample_sales.csv',
            Body=sales_csv,
            ContentType='text/csv'
        )
        
        s3.put_object(
            Bucket=bucket_name,
            Key='inventory/sample_inventory.csv',
            Body=inventory_csv,
            ContentType='text/csv'
        )
        
        cfnresponse.send(event, context, cfnresponse.SUCCESS, {'Message': 'Sample data uploaded'})
    except Exception as e:
        print(f"Error: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {'Error': str(e)})
      `),
      role: new iam.Role(this, 'SampleDataRole', {
        assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
        managedPolicies: [
          iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        ],
        inlinePolicies: {
          S3Access: new iam.PolicyDocument({
            statements: [
              new iam.PolicyStatement({
                effect: iam.Effect.ALLOW,
                actions: ['s3:PutObject'],
                resources: [`${dataBucket.bucketArn}/*`],
              }),
            ],
          }),
        },
      }),
    });

    // Custom resource to populate sample data
    new cdk.CustomResource(this, 'SampleDataResource', {
      serviceToken: sampleDataLambda.functionArn,
      properties: {
        BucketName: dataBucket.bucketName,
      },
    });

    // Email identity verification (creates the resource but verification must be done manually)
    const emailIdentity = new ses.EmailIdentity(this, 'ReportEmailIdentity', {
      identity: ses.Identity.email(verifiedEmail.valueAsString),
    });

    // Outputs for verification and testing
    new cdk.CfnOutput(this, 'DataBucketName', {
      value: dataBucket.bucketName,
      description: 'S3 bucket for storing source data',
    });

    new cdk.CfnOutput(this, 'ReportsBucketName', {
      value: reportsBucket.bucketName,
      description: 'S3 bucket for storing generated reports',
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: reportGeneratorFunction.functionName,
      description: 'Lambda function for report generation',
    });

    new cdk.CfnOutput(this, 'ScheduleName', {
      value: reportSchedule.name!,
      description: 'EventBridge schedule for daily report generation',
    });

    new cdk.CfnOutput(this, 'VerifiedEmailAddress', {
      value: verifiedEmail.valueAsString,
      description: 'Email address for report distribution (must be verified in SES)',
    });

    new cdk.CfnOutput(this, 'EmailVerificationInstructions', {
      value: `Check your email (${verifiedEmail.valueAsString}) for a verification link from AWS SES`,
      description: 'Manual step required to complete email verification',
    });
  }
}

// CDK Application
const app = new cdk.App();

new AutomatedReportGenerationStack(app, 'AutomatedReportGenerationStack', {
  description: 'Automated report generation with EventBridge Scheduler, Lambda, S3, and SES',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Application: 'AutomatedReportGeneration',
    Environment: 'Production',
    CostCenter: 'IT-Automation',
    Owner: 'DevOps-Team',
  },
});

app.synth();