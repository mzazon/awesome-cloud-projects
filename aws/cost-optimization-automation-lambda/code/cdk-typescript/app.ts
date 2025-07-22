#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as scheduler from 'aws-cdk-lib/aws-scheduler';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Duration } from 'aws-cdk-lib';

/**
 * Properties for the Cost Optimization Automation Stack
 */
export interface CostOptimizationStackProps extends cdk.StackProps {
  /** Email address for cost optimization notifications */
  readonly notificationEmail?: string;
  /** Slack webhook URL for notifications (optional) */
  readonly slackWebhookUrl?: string;
  /** Prefix for resource names to ensure uniqueness */
  readonly resourcePrefix?: string;
  /** Schedule expression for daily analysis (default: rate(1 day)) */
  readonly dailySchedule?: string;
  /** Schedule expression for weekly comprehensive analysis (default: rate(7 days)) */
  readonly weeklySchedule?: string;
}

/**
 * CDK Stack for Cost Optimization Automation with Lambda and Trusted Advisor APIs
 * 
 * This stack creates:
 * - Lambda functions for cost analysis and remediation
 * - DynamoDB table for tracking optimization opportunities
 * - S3 bucket for reports and function code
 * - SNS topic for notifications
 * - EventBridge schedules for automated execution
 * - CloudWatch dashboard for monitoring
 * - IAM roles and policies with least privilege access
 */
export class CostOptimizationStack extends cdk.Stack {
  public readonly analysisFunction: lambda.Function;
  public readonly remediationFunction: lambda.Function;
  public readonly trackingTable: dynamodb.Table;
  public readonly reportsBucket: s3.Bucket;
  public readonly notificationTopic: sns.Topic;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: CostOptimizationStackProps = {}) {
    super(scope, id, props);

    // Generate unique resource names
    const resourcePrefix = props.resourcePrefix || `cost-opt-${this.node.addr.substring(0, 8)}`;

    // Create S3 bucket for reports and Lambda deployment packages
    this.reportsBucket = new s3.Bucket(this, 'ReportsBucket', {
      bucketName: `${resourcePrefix}-reports`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'DeleteOldReports',
          enabled: true,
          expiration: Duration.days(90), // Keep reports for 90 days
          abortIncompleteMultipartUploadAfter: Duration.days(1),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create DynamoDB table for tracking optimization opportunities
    this.trackingTable = new dynamodb.Table(this, 'TrackingTable', {
      tableName: `${resourcePrefix}-tracking`,
      partitionKey: {
        name: 'ResourceId',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'CheckId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create SNS topic for notifications
    this.notificationTopic = new sns.Topic(this, 'NotificationTopic', {
      topicName: `${resourcePrefix}-alerts`,
      displayName: 'Cost Optimization Alerts',
      enforceSSL: true,
    });

    // Add email subscription if provided
    if (props.notificationEmail) {
      this.notificationTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(props.notificationEmail)
      );
    }

    // Add Slack webhook subscription if provided
    if (props.slackWebhookUrl) {
      this.notificationTopic.addSubscription(
        new snsSubscriptions.UrlSubscription(props.slackWebhookUrl)
      );
    }

    // Create IAM role for Lambda functions
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `${resourcePrefix}-lambda-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        CostOptimizationPolicy: new iam.PolicyDocument({
          statements: [
            // Trusted Advisor and Support API permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'support:DescribeTrustedAdvisorChecks',
                'support:DescribeTrustedAdvisorCheckResult',
                'support:RefreshTrustedAdvisorCheck',
              ],
              resources: ['*'],
            }),
            // Cost Explorer permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ce:GetCostAndUsage',
                'ce:GetDimensionValues',
                'ce:GetUsageReport',
                'ce:GetReservationCoverage',
                'ce:GetReservationPurchaseRecommendation',
                'ce:GetReservationUtilization',
              ],
              resources: ['*'],
            }),
            // DynamoDB permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:PutItem',
                'dynamodb:GetItem',
                'dynamodb:UpdateItem',
                'dynamodb:Query',
                'dynamodb:Scan',
              ],
              resources: [this.trackingTable.tableArn],
            }),
            // SNS permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [this.notificationTopic.topicArn],
            }),
            // S3 permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
              ],
              resources: [`${this.reportsBucket.bucketArn}/*`],
            }),
            // EC2 permissions for cost optimization
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ec2:DescribeInstances',
                'ec2:StopInstances',
                'ec2:TerminateInstances',
                'ec2:ModifyInstanceAttribute',
                'ec2:DescribeVolumes',
                'ec2:ModifyVolume',
                'ec2:CreateSnapshot',
                'ec2:DeleteVolume',
              ],
              resources: ['*'],
            }),
            // RDS permissions for cost optimization
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'rds:DescribeDBInstances',
                'rds:ModifyDBInstance',
                'rds:StopDBInstance',
              ],
              resources: ['*'],
            }),
            // Lambda invoke permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['lambda:InvokeFunction'],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create Cost Analysis Lambda Function
    this.analysisFunction = new lambda.Function(this, 'CostAnalysisFunction', {
      functionName: `${resourcePrefix}-analysis`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'lambda_function.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime, timedelta
from decimal import Decimal

def lambda_handler(event, context):
    """
    Main handler for cost analysis using Trusted Advisor APIs
    """
    print("Starting cost optimization analysis...")
    
    # Initialize AWS clients
    support_client = boto3.client('support', region_name='us-east-1')
    ce_client = boto3.client('ce')
    dynamodb = boto3.resource('dynamodb')
    lambda_client = boto3.client('lambda')
    
    # Get environment variables
    table_name = os.environ['COST_OPT_TABLE']
    remediation_function = os.environ['REMEDIATION_FUNCTION_NAME']
    
    table = dynamodb.Table(table_name)
    
    try:
        # Get list of cost optimization checks
        cost_checks = get_cost_optimization_checks(support_client)
        
        # Process each check
        optimization_opportunities = []
        for check in cost_checks:
            print(f"Processing check: {check['name']}")
            
            # Get check results
            check_result = support_client.describe_trusted_advisor_check_result(
                checkId=check['id'],
                language='en'
            )
            
            # Process flagged resources
            flagged_resources = check_result['result']['flaggedResources']
            
            for resource in flagged_resources:
                opportunity = {
                    'check_id': check['id'],
                    'check_name': check['name'],
                    'resource_id': resource['resourceId'],
                    'status': resource['status'],
                    'metadata': resource['metadata'],
                    'estimated_savings': extract_estimated_savings(resource),
                    'timestamp': datetime.now().isoformat()
                }
                
                # Store in DynamoDB
                store_optimization_opportunity(table, opportunity)
                
                # Add to opportunities list
                optimization_opportunities.append(opportunity)
        
        # Generate summary report
        report = generate_cost_optimization_report(optimization_opportunities)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost optimization analysis completed successfully',
                'opportunities_found': len(optimization_opportunities),
                'total_potential_savings': calculate_total_savings(optimization_opportunities),
                'report': report
            }, default=str)
        }
        
    except Exception as e:
        print(f"Error in cost analysis: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }

def get_cost_optimization_checks(support_client):
    """Get all cost optimization related Trusted Advisor checks"""
    response = support_client.describe_trusted_advisor_checks(language='en')
    
    cost_checks = []
    for check in response['checks']:
        if 'cost' in check['category'].lower():
            cost_checks.append({
                'id': check['id'],
                'name': check['name'],
                'category': check['category'],
                'description': check['description']
            })
    
    return cost_checks

def extract_estimated_savings(resource):
    """Extract estimated savings from resource metadata"""
    try:
        metadata = resource.get('metadata', [])
        for item in metadata:
            if '$' in str(item) and any(keyword in str(item).lower() 
                                     for keyword in ['save', 'saving', 'cost']):
                import re
                savings_match = re.search(r'\\$[\\d,]+\\.?\\d*', str(item))
                if savings_match:
                    return float(savings_match.group().replace('$', '').replace(',', ''))
        return 0.0
    except:
        return 0.0

def store_optimization_opportunity(table, opportunity):
    """Store optimization opportunity in DynamoDB"""
    table.put_item(
        Item={
            'ResourceId': opportunity['resource_id'],
            'CheckId': opportunity['check_id'],
            'CheckName': opportunity['check_name'],
            'Status': opportunity['status'],
            'EstimatedSavings': Decimal(str(opportunity['estimated_savings'])),
            'Timestamp': opportunity['timestamp'],
            'Metadata': json.dumps(opportunity['metadata'])
        }
    )

def generate_cost_optimization_report(opportunities):
    """Generate comprehensive cost optimization report"""
    report = {
        'summary': {
            'total_opportunities': len(opportunities),
            'total_potential_savings': calculate_total_savings(opportunities),
            'analysis_date': datetime.now().isoformat()
        },
        'top_opportunities': sorted(opportunities, 
                                  key=lambda x: x['estimated_savings'], 
                                  reverse=True)[:10],
        'savings_by_category': categorize_savings(opportunities)
    }
    
    return report

def calculate_total_savings(opportunities):
    """Calculate total potential savings"""
    return sum(op['estimated_savings'] for op in opportunities)

def categorize_savings(opportunities):
    """Categorize savings by service type"""
    categories = {}
    for op in opportunities:
        service = extract_service_from_check(op['check_name'])
        if service not in categories:
            categories[service] = {'count': 0, 'total_savings': 0}
        categories[service]['count'] += 1
        categories[service]['total_savings'] += op['estimated_savings']
    
    return categories

def extract_service_from_check(check_name):
    """Extract AWS service from check name"""
    if 'EC2' in check_name:
        return 'EC2'
    elif 'RDS' in check_name:
        return 'RDS'
    elif 'EBS' in check_name:
        return 'EBS'
    elif 'S3' in check_name:
        return 'S3'
    elif 'ElastiCache' in check_name:
        return 'ElastiCache'
    else:
        return 'Other'
`),
      timeout: Duration.minutes(5),
      memorySize: 512,
      role: lambdaRole,
      environment: {
        COST_OPT_TABLE: this.trackingTable.tableName,
        REMEDIATION_FUNCTION_NAME: `${resourcePrefix}-remediation`,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      description: 'Analyzes cost optimization opportunities using Trusted Advisor APIs',
    });

    // Create Remediation Lambda Function
    this.remediationFunction = new lambda.Function(this, 'RemediationFunction', {
      functionName: `${resourcePrefix}-remediation`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'lambda_function.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Handle cost optimization remediation actions
    """
    print("Starting cost optimization remediation...")
    
    # Initialize AWS clients
    ec2_client = boto3.client('ec2')
    rds_client = boto3.client('rds')
    s3_client = boto3.client('s3')
    sns_client = boto3.client('sns')
    dynamodb = boto3.resource('dynamodb')
    
    # Get environment variables
    table_name = os.environ['COST_OPT_TABLE']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    
    table = dynamodb.Table(table_name)
    
    try:
        # Parse the incoming opportunity
        opportunity = event['opportunity']
        action = event.get('action', 'manual')
        
        print(f"Processing remediation for: {opportunity['resource_id']}")
        print(f"Check: {opportunity['check_name']}")
        
        # Route to appropriate remediation handler
        remediation_result = None
        
        if 'EC2' in opportunity['check_name']:
            remediation_result = handle_ec2_remediation(
                ec2_client, opportunity, action
            )
        elif 'RDS' in opportunity['check_name']:
            remediation_result = handle_rds_remediation(
                rds_client, opportunity, action
            )
        elif 'EBS' in opportunity['check_name']:
            remediation_result = handle_ebs_remediation(
                ec2_client, opportunity, action
            )
        else:
            remediation_result = {
                'status': 'skipped',
                'message': f"No automated remediation available for: {opportunity['check_name']}"
            }
        
        # Update tracking record
        update_remediation_tracking(table, opportunity, remediation_result)
        
        # Send notification
        send_remediation_notification(
            sns_client, sns_topic_arn, opportunity, remediation_result
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Remediation completed',
                'resource_id': opportunity['resource_id'],
                'remediation_result': remediation_result
            }, default=str)
        }
        
    except Exception as e:
        print(f"Error in remediation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }

def handle_ec2_remediation(ec2_client, opportunity, action):
    """Handle EC2-related cost optimization remediation"""
    resource_id = opportunity['resource_id']
    check_name = opportunity['check_name']
    
    try:
        if 'stopped' in check_name.lower():
            return {
                'status': 'recommendation',
                'action': 'terminate',
                'message': f'Recommend terminating stopped instance {resource_id}',
                'estimated_savings': opportunity['estimated_savings']
            }
        elif 'underutilized' in check_name.lower():
            return {
                'status': 'recommendation',
                'action': 'downsize',
                'message': f'Recommend downsizing underutilized instance {resource_id}',
                'estimated_savings': opportunity['estimated_savings']
            }
        
        return {
            'status': 'analyzed',
            'message': f'No automatic remediation for {check_name}'
        }
        
    except Exception as e:
        return {
            'status': 'error',
            'message': f'Error handling EC2 remediation: {str(e)}'
        }

def handle_rds_remediation(rds_client, opportunity, action):
    """Handle RDS-related cost optimization remediation"""
    resource_id = opportunity['resource_id']
    check_name = opportunity['check_name']
    
    try:
        if 'idle' in check_name.lower():
            return {
                'status': 'recommendation',
                'action': 'stop',
                'message': f'Recommend stopping idle RDS instance {resource_id}',
                'estimated_savings': opportunity['estimated_savings']
            }
        
        return {
            'status': 'analyzed',
            'message': f'No automatic remediation for {check_name}'
        }
        
    except Exception as e:
        return {
            'status': 'error',
            'message': f'Error handling RDS remediation: {str(e)}'
        }

def handle_ebs_remediation(ec2_client, opportunity, action):
    """Handle EBS-related cost optimization remediation"""
    resource_id = opportunity['resource_id']
    check_name = opportunity['check_name']
    
    try:
        if 'unattached' in check_name.lower():
            return {
                'status': 'recommendation',
                'action': 'delete',
                'message': f'Recommend deleting unattached EBS volume {resource_id}',
                'estimated_savings': opportunity['estimated_savings']
            }
        
        return {
            'status': 'analyzed',
            'message': f'No automatic remediation for {check_name}'
        }
        
    except Exception as e:
        return {
            'status': 'error',
            'message': f'Error handling EBS remediation: {str(e)}'
        }

def update_remediation_tracking(table, opportunity, remediation_result):
    """Update DynamoDB tracking record with remediation results"""
    table.update_item(
        Key={
            'ResourceId': opportunity['resource_id'],
            'CheckId': opportunity['check_id']
        },
        UpdateExpression='SET RemediationStatus = :status, RemediationResult = :result, RemediationTimestamp = :timestamp',
        ExpressionAttributeValues={
            ':status': remediation_result['status'],
            ':result': json.dumps(remediation_result),
            ':timestamp': datetime.now().isoformat()
        }
    )

def send_remediation_notification(sns_client, topic_arn, opportunity, remediation_result):
    """Send notification about remediation action"""
    notification = {
        'resource_id': opportunity['resource_id'],
        'check_name': opportunity['check_name'],
        'remediation_status': remediation_result['status'],
        'remediation_action': remediation_result.get('action', 'none'),
        'estimated_savings': opportunity['estimated_savings'],
        'message': remediation_result.get('message', ''),
        'timestamp': datetime.now().isoformat()
    }
    
    subject = f"Cost Optimization: {remediation_result['status'].title()} - {opportunity['check_name']}"
    
    sns_client.publish(
        TopicArn=topic_arn,
        Message=json.dumps(notification, indent=2),
        Subject=subject
    )
`),
      timeout: Duration.minutes(5),
      memorySize: 512,
      role: lambdaRole,
      environment: {
        COST_OPT_TABLE: this.trackingTable.tableName,
        SNS_TOPIC_ARN: this.notificationTopic.topicArn,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      description: 'Handles cost optimization remediation actions',
    });

    // Create EventBridge schedule group
    const scheduleGroup = new scheduler.CfnScheduleGroup(this, 'ScheduleGroup', {
      name: `${resourcePrefix}-schedules`,
    });

    // Create IAM role for EventBridge Scheduler
    const schedulerRole = new iam.Role(this, 'SchedulerRole', {
      assumedBy: new iam.ServicePrincipal('scheduler.amazonaws.com'),
      inlinePolicies: {
        LambdaInvokePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['lambda:InvokeFunction'],
              resources: [this.analysisFunction.functionArn],
            }),
          ],
        }),
      },
    });

    // Create daily schedule for cost analysis
    new scheduler.CfnSchedule(this, 'DailySchedule', {
      name: `${resourcePrefix}-daily-analysis`,
      groupName: scheduleGroup.name,
      scheduleExpression: props.dailySchedule || 'rate(1 day)',
      target: {
        arn: this.analysisFunction.functionArn,
        roleArn: schedulerRole.roleArn,
      },
      flexibleTimeWindow: {
        mode: 'OFF',
      },
      description: 'Daily cost optimization analysis',
    });

    // Create weekly comprehensive schedule
    new scheduler.CfnSchedule(this, 'WeeklySchedule', {
      name: `${resourcePrefix}-weekly-analysis`,
      groupName: scheduleGroup.name,
      scheduleExpression: props.weeklySchedule || 'rate(7 days)',
      target: {
        arn: this.analysisFunction.functionArn,
        roleArn: schedulerRole.roleArn,
        input: JSON.stringify({ comprehensive_analysis: true }),
      },
      flexibleTimeWindow: {
        mode: 'OFF',
      },
      description: 'Weekly comprehensive cost optimization analysis',
    });

    // Create CloudWatch Dashboard
    this.dashboard = new cloudwatch.Dashboard(this, 'CostOptimizationDashboard', {
      dashboardName: `${resourcePrefix}-dashboard`,
      widgets: [
        [
          // Lambda function metrics
          new cloudwatch.GraphWidget({
            title: 'Lambda Function Metrics',
            left: [
              this.analysisFunction.metricDuration(),
              this.remediationFunction.metricDuration(),
            ],
            right: [
              this.analysisFunction.metricInvocations(),
              this.remediationFunction.metricInvocations(),
            ],
            width: 12,
          }),
          new cloudwatch.GraphWidget({
            title: 'Lambda Function Errors',
            left: [
              this.analysisFunction.metricErrors(),
              this.remediationFunction.metricErrors(),
            ],
            width: 12,
          }),
        ],
        [
          // DynamoDB metrics
          new cloudwatch.GraphWidget({
            title: 'DynamoDB Operations',
            left: [
              this.trackingTable.metricConsumedReadCapacityUnits(),
              this.trackingTable.metricConsumedWriteCapacityUnits(),
            ],
            width: 12,
          }),
          // SNS metrics
          new cloudwatch.GraphWidget({
            title: 'SNS Notifications',
            left: [
              this.notificationTopic.metricNumberOfMessagesPublished(),
              this.notificationTopic.metricNumberOfNotificationsDelivered(),
            ],
            width: 12,
          }),
        ],
      ],
    });

    // Grant necessary permissions
    this.trackingTable.grantReadWriteData(this.analysisFunction);
    this.trackingTable.grantReadWriteData(this.remediationFunction);
    this.notificationTopic.grantPublish(this.analysisFunction);
    this.notificationTopic.grantPublish(this.remediationFunction);
    this.reportsBucket.grantReadWrite(this.analysisFunction);
    this.reportsBucket.grantReadWrite(this.remediationFunction);

    // Allow analysis function to invoke remediation function
    this.remediationFunction.grantInvoke(this.analysisFunction);

    // Stack outputs
    new cdk.CfnOutput(this, 'AnalysisFunctionArn', {
      value: this.analysisFunction.functionArn,
      description: 'ARN of the cost analysis Lambda function',
    });

    new cdk.CfnOutput(this, 'RemediationFunctionArn', {
      value: this.remediationFunction.functionArn,
      description: 'ARN of the remediation Lambda function',
    });

    new cdk.CfnOutput(this, 'TrackingTableName', {
      value: this.trackingTable.tableName,
      description: 'Name of the DynamoDB tracking table',
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'ARN of the SNS notification topic',
    });

    new cdk.CfnOutput(this, 'ReportsBucketName', {
      value: this.reportsBucket.bucketName,
      description: 'Name of the S3 bucket for reports',
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard',
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'CostOptimization');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }
}

// Main CDK App
const app = new cdk.App();

// Get context values or use defaults
const notificationEmail = app.node.tryGetContext('notificationEmail');
const slackWebhookUrl = app.node.tryGetContext('slackWebhookUrl');
const resourcePrefix = app.node.tryGetContext('resourcePrefix');

// Create the stack
new CostOptimizationStack(app, 'CostOptimizationStack', {
  notificationEmail,
  slackWebhookUrl,
  resourcePrefix,
  description: 'Cost optimization automation with Lambda and Trusted Advisor APIs',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

app.synth();