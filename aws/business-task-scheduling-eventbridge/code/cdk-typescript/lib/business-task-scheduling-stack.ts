import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as scheduler from 'aws-cdk-lib/aws-scheduler';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as path from 'path';

export class BusinessTaskSchedulingStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate a unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // Create S3 bucket for storing reports and processed data
    const businessDataBucket = new s3.Bucket(this, 'BusinessDataBucket', {
      bucketName: `business-automation-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo purposes
      lifecycleRules: [
        {
          id: 'delete-old-versions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
        {
          id: 'transition-to-ia',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
          ],
        },
      ],
    });

    // Create SNS topic for business notifications
    const businessNotificationTopic = new sns.Topic(this, 'BusinessNotificationTopic', {
      topicName: `business-notifications-${uniqueSuffix}`,
      displayName: 'Business Automation Notifications',
    });

    // Create CloudWatch Log Group for Lambda function
    const lambdaLogGroup = new logs.LogGroup(this, 'BusinessTaskProcessorLogGroup', {
      logGroupName: `/aws/lambda/business-task-processor-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create Lambda function for business task processing
    const businessTaskProcessor = new lambda.Function(this, 'BusinessTaskProcessor', {
      functionName: `business-task-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'business_task_processor.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import datetime
from io import StringIO
import csv
import os

s3 = boto3.client('s3')
sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        # Get task type from event
        task_type = event.get('task_type', 'report')
        bucket_name = os.environ['BUCKET_NAME']
        topic_arn = os.environ['TOPIC_ARN']
        
        if task_type == 'report':
            result = generate_daily_report(bucket_name)
        elif task_type == 'data_processing':
            result = process_business_data(bucket_name)
        elif task_type == 'notification':
            result = send_business_notification(topic_arn)
        else:
            result = f"Unknown task type: {task_type}"
        
        # Send success notification
        sns.publish(
            TopicArn=topic_arn,
            Message=f"Business task completed successfully: {result}",
            Subject=f"Task Completion - {task_type}"
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Task completed successfully',
                'result': result,
                'timestamp': datetime.datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        # Send failure notification
        sns.publish(
            TopicArn=topic_arn,
            Message=f"Business task failed: {str(e)}",
            Subject=f"Task Failure - {task_type}"
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.datetime.now().isoformat()
            })
        }

def generate_daily_report(bucket_name):
    # Generate sample business report
    report_data = [
        ['Date', 'Revenue', 'Orders', 'Customers'],
        [datetime.datetime.now().strftime('%Y-%m-%d'), '12500', '45', '38'],
        [datetime.datetime.now().strftime('%Y-%m-%d'), '15800', '52', '41']
    ]
    
    # Convert to CSV
    csv_buffer = StringIO()
    writer = csv.writer(csv_buffer)
    writer.writerows(report_data)
    
    # Upload to S3
    report_key = f"reports/daily-report-{datetime.datetime.now().strftime('%Y%m%d')}.csv"
    s3.put_object(
        Bucket=bucket_name,
        Key=report_key,
        Body=csv_buffer.getvalue(),
        ContentType='text/csv'
    )
    
    return f"Daily report generated: {report_key}"

def process_business_data(bucket_name):
    # Simulate data processing
    processed_data = {
        'processed_at': datetime.datetime.now().isoformat(),
        'records_processed': 150,
        'success_rate': 98.5,
        'errors': 2
    }
    
    # Save processed data to S3
    data_key = f"processed-data/batch-{datetime.datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
    s3.put_object(
        Bucket=bucket_name,
        Key=data_key,
        Body=json.dumps(processed_data),
        ContentType='application/json'
    )
    
    return f"Data processing completed: {data_key}"

def send_business_notification(topic_arn):
    # Send business update notification
    message = f"Business automation system status check completed at {datetime.datetime.now().isoformat()}"
    
    sns.publish(
        TopicArn=topic_arn,
        Message=message,
        Subject="Business Automation Status Update"
    )
    
    return "Business notification sent successfully"
      `),
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      environment: {
        BUCKET_NAME: businessDataBucket.bucketName,
        TOPIC_ARN: businessNotificationTopic.topicArn,
      },
      logGroup: lambdaLogGroup,
      description: 'Processes automated business tasks including reports, data processing, and notifications',
    });

    // Grant Lambda permissions to access S3 bucket
    businessDataBucket.grantReadWrite(businessTaskProcessor);

    // Grant Lambda permissions to publish to SNS topic
    businessNotificationTopic.grantPublish(businessTaskProcessor);

    // Create IAM role for EventBridge Scheduler
    const schedulerExecutionRole = new iam.Role(this, 'SchedulerExecutionRole', {
      roleName: `eventbridge-scheduler-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('scheduler.amazonaws.com'),
      description: 'IAM role for EventBridge Scheduler to invoke Lambda functions',
    });

    // Grant scheduler role permission to invoke Lambda function
    businessTaskProcessor.grantInvoke(schedulerExecutionRole);

    // Create schedule group for organizing business automation schedules
    const scheduleGroup = new scheduler.CfnScheduleGroup(this, 'BusinessAutomationScheduleGroup', {
      name: 'business-automation-group',
      tags: [
        { key: 'Environment', value: 'Production' },
        { key: 'Department', value: 'Operations' },
        { key: 'Application', value: 'BusinessAutomation' },
      ],
    });

    // Create daily report schedule (9 AM EST/EDT)
    new scheduler.CfnSchedule(this, 'DailyReportSchedule', {
      name: 'daily-report-schedule',
      groupName: scheduleGroup.name,
      description: 'Daily business report generation at 9 AM Eastern Time',
      scheduleExpression: 'cron(0 9 * * ? *)',
      scheduleExpressionTimezone: 'America/New_York',
      flexibleTimeWindow: {
        mode: 'OFF',
      },
      target: {
        arn: businessTaskProcessor.functionArn,
        roleArn: schedulerExecutionRole.roleArn,
        input: JSON.stringify({ task_type: 'report' }),
      },
      state: 'ENABLED',
    });

    // Create hourly data processing schedule
    new scheduler.CfnSchedule(this, 'HourlyDataProcessingSchedule', {
      name: 'hourly-data-processing',
      groupName: scheduleGroup.name,
      description: 'Hourly business data processing',
      scheduleExpression: 'rate(1 hour)',
      flexibleTimeWindow: {
        mode: 'OFF',
      },
      target: {
        arn: businessTaskProcessor.functionArn,
        roleArn: schedulerExecutionRole.roleArn,
        input: JSON.stringify({ task_type: 'data_processing' }),
      },
      state: 'ENABLED',
    });

    // Create weekly notification schedule (Monday 10 AM EST/EDT)
    new scheduler.CfnSchedule(this, 'WeeklyNotificationSchedule', {
      name: 'weekly-notification-schedule',
      groupName: scheduleGroup.name,
      description: 'Weekly business status notifications on Monday at 10 AM Eastern Time',
      scheduleExpression: 'cron(0 10 ? * MON *)',
      scheduleExpressionTimezone: 'America/New_York',
      flexibleTimeWindow: {
        mode: 'OFF',
      },
      target: {
        arn: businessTaskProcessor.functionArn,
        roleArn: schedulerExecutionRole.roleArn,
        input: JSON.stringify({ task_type: 'notification' }),
      },
      state: 'ENABLED',
    });

    // Output important resource information
    new cdk.CfnOutput(this, 'S3BucketName', {
      value: businessDataBucket.bucketName,
      description: 'Name of the S3 bucket for business automation data',
      exportName: `${this.stackName}-S3BucketName`,
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: businessNotificationTopic.topicArn,
      description: 'ARN of the SNS topic for business notifications',
      exportName: `${this.stackName}-SNSTopicArn`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: businessTaskProcessor.functionName,
      description: 'Name of the Lambda function for business task processing',
      exportName: `${this.stackName}-LambdaFunctionName`,
    });

    new cdk.CfnOutput(this, 'ScheduleGroupName', {
      value: scheduleGroup.name!,
      description: 'Name of the EventBridge Scheduler group',
      exportName: `${this.stackName}-ScheduleGroupName`,
    });

    new cdk.CfnOutput(this, 'ManualTestCommand', {
      value: `aws lambda invoke --function-name ${businessTaskProcessor.functionName} --payload '{"task_type":"report"}' --cli-binary-format raw-in-base64-out response.json`,
      description: 'Command to manually test the Lambda function',
    });
  }
}