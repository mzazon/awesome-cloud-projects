#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Props for the ResourceCleanupStack
 */
export interface ResourceCleanupStackProps extends cdk.StackProps {
  /**
   * Email address to receive cleanup notifications
   */
  readonly notificationEmail?: string;
  
  /**
   * Schedule expression for automatic cleanup (default: daily at 2 AM UTC)
   * @default 'cron(0 2 * * ? *)'
   */
  readonly scheduleExpression?: string;
  
  /**
   * Tag key used to identify resources for cleanup
   * @default 'AutoCleanup'
   */
  readonly cleanupTagKey?: string;
  
  /**
   * Tag values that trigger cleanup (case-insensitive)
   * @default ['true', 'True', 'TRUE']
   */
  readonly cleanupTagValues?: string[];
}

/**
 * CDK Stack for automated resource cleanup using Lambda and tags
 * 
 * This stack creates:
 * - Lambda function to identify and terminate tagged EC2 instances
 * - SNS topic for cleanup notifications
 * - IAM role with least privilege permissions
 * - CloudWatch Events rule for scheduled execution (optional)
 * - CloudWatch Log Group for function logs
 */
export class ResourceCleanupStack extends cdk.Stack {
  /**
   * The Lambda function that performs resource cleanup
   */
  public readonly cleanupFunction: lambda.Function;
  
  /**
   * The SNS topic for cleanup notifications
   */
  public readonly notificationTopic: sns.Topic;

  constructor(scope: Construct, id: string, props?: ResourceCleanupStackProps) {
    super(scope, id, props);

    // Configuration with defaults
    const cleanupTagKey = props?.cleanupTagKey || 'AutoCleanup';
    const cleanupTagValues = props?.cleanupTagValues || ['true', 'True', 'TRUE'];
    const scheduleExpression = props?.scheduleExpression || 'cron(0 2 * * ? *)';

    // Create SNS topic for notifications
    this.notificationTopic = new sns.Topic(this, 'CleanupNotificationTopic', {
      displayName: 'Resource Cleanup Alerts',
      description: 'Notifications for automated resource cleanup actions',
    });

    // Subscribe email to SNS topic if provided
    if (props?.notificationEmail) {
      this.notificationTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(props.notificationEmail)
      );
    }

    // Create CloudWatch Log Group for Lambda function
    const logGroup = new logs.LogGroup(this, 'CleanupFunctionLogGroup', {
      logGroupName: '/aws/lambda/resource-cleanup-function',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create Lambda function for resource cleanup
    this.cleanupFunction = new lambda.Function(this, 'ResourceCleanupFunction', {
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime, timezone
from typing import List, Dict, Any

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function to cleanup EC2 instances based on tags
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Response dictionary with status and message
    """
    ec2 = boto3.client('ec2')
    sns = boto3.client('sns')
    
    # Get environment variables
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    cleanup_tag_key = os.environ.get('CLEANUP_TAG_KEY', 'AutoCleanup')
    cleanup_tag_values = os.environ.get('CLEANUP_TAG_VALUES', 'true,True,TRUE').split(',')
    
    try:
        print(f"Starting cleanup process for tag {cleanup_tag_key} with values: {cleanup_tag_values}")
        
        # Query instances with cleanup tag
        response = ec2.describe_instances(
            Filters=[
                {
                    'Name': f'tag:{cleanup_tag_key}',
                    'Values': cleanup_tag_values
                },
                {
                    'Name': 'instance-state-name',
                    'Values': ['running', 'stopped']
                }
            ]
        )
        
        instances_to_cleanup: List[Dict[str, str]] = []
        
        # Extract instance information
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_id = instance['InstanceId']
                instance_name = 'Unnamed'
                instance_type = instance.get('InstanceType', 'Unknown')
                instance_state = instance['State']['Name']
                launch_time = instance.get('LaunchTime', 'Unknown')
                
                # Get instance name from tags
                for tag in instance.get('Tags', []):
                    if tag['Key'] == 'Name':
                        instance_name = tag['Value']
                        break
                
                instances_to_cleanup.append({
                    'InstanceId': instance_id,
                    'Name': instance_name,
                    'State': instance_state,
                    'Type': instance_type,
                    'LaunchTime': str(launch_time)
                })
        
        if not instances_to_cleanup:
            print(f"No instances found with {cleanup_tag_key} tag")
            return {
                'statusCode': 200,
                'body': json.dumps('No instances to cleanup')
            }
        
        print(f"Found {len(instances_to_cleanup)} instances to cleanup")
        
        # Terminate instances
        instance_ids = [inst['InstanceId'] for inst in instances_to_cleanup]
        termination_response = ec2.terminate_instances(InstanceIds=instance_ids)
        
        print(f"Termination initiated for instances: {instance_ids}")
        
        # Prepare notification message
        message = f"""AWS Resource Cleanup Report
Time: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC
Region: {os.environ.get('AWS_REGION', 'Unknown')}
Tag Filter: {cleanup_tag_key} in {cleanup_tag_values}

The following EC2 instances were terminated:

"""
        
        for instance in instances_to_cleanup:
            message += f"- {instance['Name']} ({instance['InstanceId']})\\n"
            message += f"  Type: {instance['Type']}, State: {instance['State']}\\n"
            message += f"  Launch Time: {instance['LaunchTime']}\\n\\n"
        
        message += f"Total instances cleaned up: {len(instances_to_cleanup)}\\n"
        message += f"Estimated cost savings: Varies by instance type and usage pattern\\n"
        message += f"\\nFor cost analysis, review your AWS Cost Explorer after resources are fully terminated."
        
        # Publish success notification to SNS
        sns.publish(
            TopicArn=sns_topic_arn,
            Subject='✅ AWS Resource Cleanup Completed Successfully',
            Message=message
        )
        
        print(f"Successfully initiated termination for {len(instances_to_cleanup)} instances")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully cleaned up {len(instances_to_cleanup)} instances',
                'instances': instances_to_cleanup
            })
        }
        
    except Exception as e:
        error_message = f"Error during cleanup: {str(e)}"
        print(f"ERROR: {error_message}")
        
        # Send error notification
        try:
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject='❌ AWS Resource Cleanup Error',
                Message=f"""An error occurred during the automated resource cleanup process:

Error Details:
{error_message}

Time: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC
Region: {os.environ.get('AWS_REGION', 'Unknown')}
Function: {context.function_name if context else 'Unknown'}

Please check the CloudWatch logs for more details and investigate the issue.
"""
            )
        except Exception as sns_error:
            print(f"CRITICAL: Failed to send error notification: {sns_error}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_message
            })
        }
`),
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      description: 'Automated cleanup of tagged EC2 instances with SNS notifications',
      environment: {
        SNS_TOPIC_ARN: this.notificationTopic.topicArn,
        CLEANUP_TAG_KEY: cleanupTagKey,
        CLEANUP_TAG_VALUES: cleanupTagValues.join(','),
      },
      logGroup: logGroup,
      reservedConcurrentExecutions: 1, // Prevent multiple concurrent executions
    });

    // Create IAM policy for EC2 and SNS permissions
    const cleanupPolicy = new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'ec2:DescribeInstances',
        'ec2:TerminateInstances',
        'ec2:DescribeTags'
      ],
      resources: ['*'], // EC2 actions require wildcard resource
    });

    const snsPolicy = new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['sns:Publish'],
      resources: [this.notificationTopic.topicArn],
    });

    // Add policies to the Lambda function's execution role
    this.cleanupFunction.addToRolePolicy(cleanupPolicy);
    this.cleanupFunction.addToRolePolicy(snsPolicy);

    // Create EventBridge rule for scheduled execution (optional)
    const scheduleRule = new events.Rule(this, 'CleanupScheduleRule', {
      description: 'Scheduled execution of resource cleanup function',
      schedule: events.Schedule.expression(scheduleExpression),
      enabled: false, // Disabled by default for safety
    });

    // Add Lambda function as target for the schedule
    scheduleRule.addTarget(new targets.LambdaFunction(this.cleanupFunction, {
      retryAttempts: 2,
    }));

    // Add tags to all resources for better organization
    cdk.Tags.of(this).add('Project', 'ResourceCleanupAutomation');
    cdk.Tags.of(this).add('Purpose', 'CostOptimization');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');

    // Output important information
    new cdk.CfnOutput(this, 'CleanupFunctionName', {
      value: this.cleanupFunction.functionName,
      description: 'Name of the resource cleanup Lambda function',
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'ARN of the SNS topic for cleanup notifications',
    });

    new cdk.CfnOutput(this, 'ScheduleRuleName', {
      value: scheduleRule.ruleName,
      description: 'Name of the EventBridge rule for scheduled cleanup (disabled by default)',
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: logGroup.logGroupName,
      description: 'CloudWatch Log Group for Lambda function logs',
    });

    new cdk.CfnOutput(this, 'ManualTestCommand', {
      value: `aws lambda invoke --function-name ${this.cleanupFunction.functionName} --payload '{}' response.json && cat response.json`,
      description: 'CLI command to manually test the cleanup function',
    });
  }
}

// CDK App
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const notificationEmail = app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL;
const scheduleExpression = app.node.tryGetContext('scheduleExpression') || process.env.SCHEDULE_EXPRESSION;
const cleanupTagKey = app.node.tryGetContext('cleanupTagKey') || process.env.CLEANUP_TAG_KEY;

// Deploy the stack
new ResourceCleanupStack(app, 'ResourceCleanupStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Automated resource cleanup system using Lambda and SNS notifications',
  notificationEmail: notificationEmail,
  scheduleExpression: scheduleExpression,
  cleanupTagKey: cleanupTagKey,
  
  // Add stack-level tags
  tags: {
    Project: 'ResourceCleanupAutomation',
    Environment: 'Production',
    CostCenter: 'Infrastructure',
    Owner: 'DevOps',
  },
});