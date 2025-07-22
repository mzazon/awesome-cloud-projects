#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Props for the Reserved Instance Management Automation Stack
 */
export interface RIManagementStackProps extends cdk.StackProps {
  /** Email address for SNS notifications */
  readonly notificationEmail?: string;
  /** S3 bucket name prefix (will be made unique) */
  readonly bucketNamePrefix?: string;
  /** Project name for resource tagging */
  readonly projectName?: string;
}

/**
 * AWS CDK Stack for Reserved Instance Management Automation
 * 
 * This stack deploys a complete solution for automating Reserved Instance (RI) management
 * including utilization monitoring, purchase recommendations, and expiration tracking.
 * 
 * Architecture Components:
 * - Lambda functions for RI analysis, recommendations, and monitoring
 * - DynamoDB table for tracking RI history and alerts
 * - S3 bucket for storing RI reports
 * - SNS topic for notifications
 * - EventBridge rules for scheduled automation
 * - IAM roles with least privilege permissions
 */
export class RIManagementStack extends cdk.Stack {
  /** S3 bucket for storing RI reports */
  public readonly reportsBucket: s3.Bucket;
  
  /** SNS topic for RI alerts and notifications */
  public readonly notificationsTopic: sns.Topic;
  
  /** DynamoDB table for RI tracking data */
  public readonly trackingTable: dynamodb.Table;
  
  /** Lambda function for RI utilization analysis */
  public readonly utilizationFunction: lambda.Function;
  
  /** Lambda function for RI recommendations */
  public readonly recommendationsFunction: lambda.Function;
  
  /** Lambda function for RI monitoring */
  public readonly monitoringFunction: lambda.Function;

  constructor(scope: Construct, id: string, props: RIManagementStackProps = {}) {
    super(scope, id, props);

    const projectName = props.projectName || 'ri-management';
    const bucketNamePrefix = props.bucketNamePrefix || 'ri-reports';

    // Create S3 bucket for storing RI reports
    this.reportsBucket = new s3.Bucket(this, 'RIReportsBucket', {
      bucketName: `${bucketNamePrefix}-${this.account}-${cdk.Names.uniqueId(this).toLowerCase().substring(0, 8)}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteOldReports',
          enabled: true,
          expiration: cdk.Duration.days(90), // Keep reports for 90 days
          prefix: 'ri-utilization-reports/',
        },
        {
          id: 'DeleteOldRecommendations',
          enabled: true,
          expiration: cdk.Duration.days(30), // Keep recommendations for 30 days
          prefix: 'ri-recommendations/',
        }
      ],
      tags: {
        Project: projectName,
        Purpose: 'RI Reports Storage'
      }
    });

    // Create SNS topic for notifications
    this.notificationsTopic = new sns.Topic(this, 'RINotificationsTopic', {
      topicName: `${projectName}-alerts`,
      displayName: 'Reserved Instance Management Alerts',
      tags: {
        Project: projectName,
        Purpose: 'RI Notifications'
      }
    });

    // Add email subscription if provided
    if (props.notificationEmail) {
      this.notificationsTopic.addSubscription(
        new cdk.aws_sns_subscriptions.EmailSubscription(props.notificationEmail)
      );
    }

    // Create DynamoDB table for RI tracking
    this.trackingTable = new dynamodb.Table(this, 'RITrackingTable', {
      tableName: `${projectName}-tracking`,
      partitionKey: {
        name: 'ReservationId',
        type: dynamodb.AttributeType.STRING
      },
      sortKey: {
        name: 'Timestamp',
        type: dynamodb.AttributeType.NUMBER
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      pointInTimeRecovery: true,
      tags: {
        Project: projectName,
        Purpose: 'RI Tracking Data'
      }
    });

    // Create IAM role for Lambda functions
    const lambdaRole = new iam.Role(this, 'RILambdaRole', {
      roleName: `${projectName}-lambda-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        RIManagementPolicy: new iam.PolicyDocument({
          statements: [
            // Cost Explorer permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ce:GetDimensionValues',
                'ce:GetUsageAndCosts',
                'ce:GetReservationCoverage',
                'ce:GetReservationPurchaseRecommendation',
                'ce:GetReservationUtilization',
                'ce:GetRightsizingRecommendation'
              ],
              resources: ['*']
            }),
            // EC2 permissions for RI monitoring
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ec2:DescribeReservedInstances'
              ],
              resources: ['*']
            }),
            // S3 permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject'
              ],
              resources: [`${this.reportsBucket.bucketArn}/*`]
            }),
            // DynamoDB permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:PutItem',
                'dynamodb:GetItem',
                'dynamodb:UpdateItem',
                'dynamodb:Query',
                'dynamodb:Scan'
              ],
              resources: [this.trackingTable.tableArn]
            }),
            // SNS permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [this.notificationsTopic.topicArn]
            })
          ]
        })
      },
      tags: {
        Project: projectName,
        Purpose: 'Lambda Execution Role'
      }
    });

    // Create Lambda function for RI utilization analysis
    this.utilizationFunction = new lambda.Function(this, 'RIUtilizationFunction', {
      functionName: `${projectName}-ri-utilization`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(this.getUtilizationFunctionCode()),
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      role: lambdaRole,
      environment: {
        S3_BUCKET_NAME: this.reportsBucket.bucketName,
        SNS_TOPIC_ARN: this.notificationsTopic.topicArn
      },
      logRetention: logs.RetentionDays.ONE_MONTH,
      tags: {
        Project: projectName,
        Purpose: 'RI Utilization Analysis'
      }
    });

    // Create Lambda function for RI recommendations
    this.recommendationsFunction = new lambda.Function(this, 'RIRecommendationsFunction', {
      functionName: `${projectName}-ri-recommendations`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(this.getRecommendationsFunctionCode()),
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      role: lambdaRole,
      environment: {
        S3_BUCKET_NAME: this.reportsBucket.bucketName,
        SNS_TOPIC_ARN: this.notificationsTopic.topicArn
      },
      logRetention: logs.RetentionDays.ONE_MONTH,
      tags: {
        Project: projectName,
        Purpose: 'RI Purchase Recommendations'
      }
    });

    // Create Lambda function for RI monitoring
    this.monitoringFunction = new lambda.Function(this, 'RIMonitoringFunction', {
      functionName: `${projectName}-ri-monitoring`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(this.getMonitoringFunctionCode()),
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      role: lambdaRole,
      environment: {
        DYNAMODB_TABLE_NAME: this.trackingTable.tableName,
        SNS_TOPIC_ARN: this.notificationsTopic.topicArn
      },
      logRetention: logs.RetentionDays.ONE_MONTH,
      tags: {
        Project: projectName,
        Purpose: 'RI Expiration Monitoring'
      }
    });

    // Create EventBridge rules for scheduled automation
    
    // Daily RI utilization analysis at 8 AM UTC
    const dailyUtilizationRule = new events.Rule(this, 'DailyUtilizationRule', {
      ruleName: `${projectName}-daily-utilization`,
      description: 'Daily RI utilization analysis at 8 AM UTC',
      schedule: events.Schedule.cron({
        minute: '0',
        hour: '8',
        day: '*',
        month: '*',
        year: '*'
      }),
      enabled: true,
      targets: [new targets.LambdaFunction(this.utilizationFunction)]
    });

    // Weekly RI recommendations on Monday at 9 AM UTC
    const weeklyRecommendationsRule = new events.Rule(this, 'WeeklyRecommendationsRule', {
      ruleName: `${projectName}-weekly-recommendations`,
      description: 'Weekly RI recommendations on Monday at 9 AM UTC',
      schedule: events.Schedule.cron({
        minute: '0',
        hour: '9',
        day: '*',
        month: '*',
        year: '*',
        weekDay: 'MON'
      }),
      enabled: true,
      targets: [new targets.LambdaFunction(this.recommendationsFunction)]
    });

    // Weekly RI monitoring on Monday at 10 AM UTC
    const weeklyMonitoringRule = new events.Rule(this, 'WeeklyMonitoringRule', {
      ruleName: `${projectName}-weekly-monitoring`,
      description: 'Weekly RI monitoring on Monday at 10 AM UTC',
      schedule: events.Schedule.cron({
        minute: '0',
        hour: '10',
        day: '*',
        month: '*',
        year: '*',
        weekDay: 'MON'
      }),
      enabled: true,
      targets: [new targets.LambdaFunction(this.monitoringFunction)]
    });

    // Grant EventBridge permission to invoke Lambda functions
    this.utilizationFunction.addPermission('AllowEventBridgeInvoke', {
      principal: new iam.ServicePrincipal('events.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceArn: dailyUtilizationRule.ruleArn
    });

    this.recommendationsFunction.addPermission('AllowEventBridgeInvoke', {
      principal: new iam.ServicePrincipal('events.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceArn: weeklyRecommendationsRule.ruleArn
    });

    this.monitoringFunction.addPermission('AllowEventBridgeInvoke', {
      principal: new iam.ServicePrincipal('events.amazonaws.com'),
      action: 'lambda:InvokeFunction',
      sourceArn: weeklyMonitoringRule.ruleArn
    });

    // Output important resource identifiers
    new cdk.CfnOutput(this, 'ReportsBucketName', {
      value: this.reportsBucket.bucketName,
      description: 'S3 bucket name for RI reports',
      exportName: `${projectName}-reports-bucket`
    });

    new cdk.CfnOutput(this, 'NotificationsTopicArn', {
      value: this.notificationsTopic.topicArn,
      description: 'SNS topic ARN for RI notifications',
      exportName: `${projectName}-notifications-topic`
    });

    new cdk.CfnOutput(this, 'TrackingTableName', {
      value: this.trackingTable.tableName,
      description: 'DynamoDB table name for RI tracking',
      exportName: `${projectName}-tracking-table`
    });

    new cdk.CfnOutput(this, 'UtilizationFunctionArn', {
      value: this.utilizationFunction.functionArn,
      description: 'ARN of the RI utilization analysis function',
      exportName: `${projectName}-utilization-function`
    });

    new cdk.CfnOutput(this, 'RecommendationsFunctionArn', {
      value: this.recommendationsFunction.functionArn,
      description: 'ARN of the RI recommendations function',
      exportName: `${projectName}-recommendations-function`
    });

    new cdk.CfnOutput(this, 'MonitoringFunctionArn', {
      value: this.monitoringFunction.functionArn,
      description: 'ARN of the RI monitoring function',
      exportName: `${projectName}-monitoring-function`
    });
  }

  /**
   * Get the Python code for the RI utilization analysis Lambda function
   */
  private getUtilizationFunctionCode(): string {
    return `
import json
import boto3
import datetime
from decimal import Decimal
import os

def lambda_handler(event, context):
    ce = boto3.client('ce')
    s3 = boto3.client('s3')
    sns = boto3.client('sns')
    
    # Get environment variables
    bucket_name = os.environ['S3_BUCKET_NAME']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    
    # Calculate date range (last 30 days)
    end_date = datetime.date.today()
    start_date = end_date - datetime.timedelta(days=30)
    
    try:
        # Get RI utilization data
        response = ce.get_reservation_utilization(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY',
            GroupBy=[
                {
                    'Type': 'DIMENSION',
                    'Key': 'SERVICE'
                }
            ]
        )
        
        # Process utilization data
        utilization_data = []
        alerts = []
        
        for result in response['UtilizationsByTime']:
            for group in result['Groups']:
                service = group['Keys'][0]
                utilization = group['Attributes']['UtilizationPercentage']
                
                utilization_data.append({
                    'service': service,
                    'utilization_percentage': float(utilization),
                    'period': result['TimePeriod']['Start'],
                    'total_actual_hours': group['Attributes']['TotalActualHours'],
                    'unused_hours': group['Attributes']['UnusedHours']
                })
                
                # Check for low utilization (below 80%)
                if float(utilization) < 80:
                    alerts.append({
                        'service': service,
                        'utilization': utilization,
                        'type': 'LOW_UTILIZATION',
                        'message': f'Low RI utilization for {service}: {utilization}%'
                    })
        
        # Save report to S3
        report_key = f"ri-utilization-reports/{start_date.strftime('%Y-%m-%d')}.json"
        s3.put_object(
            Bucket=bucket_name,
            Key=report_key,
            Body=json.dumps({
                'report_date': end_date.strftime('%Y-%m-%d'),
                'period': f"{start_date.strftime('%Y-%m-%d')} to {end_date.strftime('%Y-%m-%d')}",
                'utilization_data': utilization_data,
                'alerts': alerts
            }, indent=2)
        )
        
        # Send alerts if any
        if alerts:
            message = f"RI Utilization Alert Report\\n\\n"
            for alert in alerts:
                message += f"- {alert['message']}\\n"
            
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject="Reserved Instance Utilization Alert",
                Message=message
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'RI utilization analysis completed',
                'report_location': f"s3://{bucket_name}/{report_key}",
                'alerts_generated': len(alerts)
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
`;
  }

  /**
   * Get the Python code for the RI recommendations Lambda function
   */
  private getRecommendationsFunctionCode(): string {
    return `
import json
import boto3
import datetime
import os

def lambda_handler(event, context):
    ce = boto3.client('ce')
    s3 = boto3.client('s3')
    sns = boto3.client('sns')
    
    # Get environment variables
    bucket_name = os.environ['S3_BUCKET_NAME']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    
    try:
        # Get RI recommendations for EC2
        ec2_response = ce.get_reservation_purchase_recommendation(
            Service='Amazon Elastic Compute Cloud - Compute',
            LookbackPeriodInDays='SIXTY_DAYS',
            TermInYears='ONE_YEAR',
            PaymentOption='PARTIAL_UPFRONT'
        )
        
        # Get RI recommendations for RDS
        rds_response = ce.get_reservation_purchase_recommendation(
            Service='Amazon Relational Database Service',
            LookbackPeriodInDays='SIXTY_DAYS',
            TermInYears='ONE_YEAR',
            PaymentOption='PARTIAL_UPFRONT'
        )
        
        # Process recommendations
        recommendations = []
        total_estimated_savings = 0
        
        # Process EC2 recommendations
        for recommendation in ec2_response['Recommendations']:
            rec_data = {
                'service': 'EC2',
                'instance_type': recommendation['InstanceDetails']['EC2InstanceDetails']['InstanceType'],
                'region': recommendation['InstanceDetails']['EC2InstanceDetails']['Region'],
                'recommended_instances': recommendation['RecommendationDetails']['RecommendedNumberOfInstancesToPurchase'],
                'estimated_monthly_savings': float(recommendation['RecommendationDetails']['EstimatedMonthlySavingsAmount']),
                'estimated_monthly_on_demand_cost': float(recommendation['RecommendationDetails']['EstimatedMonthlyOnDemandCost']),
                'upfront_cost': float(recommendation['RecommendationDetails']['UpfrontCost']),
                'recurring_cost': float(recommendation['RecommendationDetails']['RecurringStandardMonthlyCost'])
            }
            recommendations.append(rec_data)
            total_estimated_savings += rec_data['estimated_monthly_savings']
        
        # Process RDS recommendations
        for recommendation in rds_response['Recommendations']:
            rec_data = {
                'service': 'RDS',
                'instance_type': recommendation['InstanceDetails']['RDSInstanceDetails']['InstanceType'],
                'database_engine': recommendation['InstanceDetails']['RDSInstanceDetails']['DatabaseEngine'],
                'region': recommendation['InstanceDetails']['RDSInstanceDetails']['Region'],
                'recommended_instances': recommendation['RecommendationDetails']['RecommendedNumberOfInstancesToPurchase'],
                'estimated_monthly_savings': float(recommendation['RecommendationDetails']['EstimatedMonthlySavingsAmount']),
                'estimated_monthly_on_demand_cost': float(recommendation['RecommendationDetails']['EstimatedMonthlyOnDemandCost']),
                'upfront_cost': float(recommendation['RecommendationDetails']['UpfrontCost']),
                'recurring_cost': float(recommendation['RecommendationDetails']['RecurringStandardMonthlyCost'])
            }
            recommendations.append(rec_data)
            total_estimated_savings += rec_data['estimated_monthly_savings']
        
        # Save recommendations to S3
        today = datetime.date.today()
        report_key = f"ri-recommendations/{today.strftime('%Y-%m-%d')}.json"
        
        report_data = {
            'report_date': today.strftime('%Y-%m-%d'),
            'total_recommendations': len(recommendations),
            'total_estimated_monthly_savings': total_estimated_savings,
            'recommendations': recommendations
        }
        
        s3.put_object(
            Bucket=bucket_name,
            Key=report_key,
            Body=json.dumps(report_data, indent=2)
        )
        
        # Send notification if there are recommendations
        if recommendations:
            message = f"RI Purchase Recommendations Report\\n\\n"
            message += f"Total Recommendations: {len(recommendations)}\\n"
            message += f"Estimated Monthly Savings: ${total_estimated_savings:.2f}\\n\\n"
            
            for rec in recommendations[:5]:  # Show top 5
                message += f"- {rec['service']}: {rec['instance_type']} "
                message += f"(${rec['estimated_monthly_savings']:.2f}/month savings)\\n"
            
            if len(recommendations) > 5:
                message += f"... and {len(recommendations) - 5} more recommendations\\n"
            
            message += f"\\nFull report: s3://{bucket_name}/{report_key}"
            
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject="Reserved Instance Purchase Recommendations",
                Message=message
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'RI recommendations analysis completed',
                'report_location': f"s3://{bucket_name}/{report_key}",
                'recommendations_count': len(recommendations),
                'estimated_savings': total_estimated_savings
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
`;
  }

  /**
   * Get the Python code for the RI monitoring Lambda function
   */
  private getMonitoringFunctionCode(): string {
    return `
import json
import boto3
import datetime
import os

def lambda_handler(event, context):
    ce = boto3.client('ce')
    ec2 = boto3.client('ec2')
    dynamodb = boto3.resource('dynamodb')
    sns = boto3.client('sns')
    
    # Get environment variables
    table_name = os.environ['DYNAMODB_TABLE_NAME']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    
    table = dynamodb.Table(table_name)
    
    try:
        # Get EC2 Reserved Instances
        response = ec2.describe_reserved_instances(
            Filters=[
                {
                    'Name': 'state',
                    'Values': ['active']
                }
            ]
        )
        
        alerts = []
        current_time = datetime.datetime.utcnow()
        
        for ri in response['ReservedInstances']:
            ri_id = ri['ReservedInstancesId']
            end_date = ri['End']
            
            # Calculate days until expiration
            days_until_expiration = (end_date.replace(tzinfo=None) - current_time).days
            
            # Store RI data in DynamoDB
            table.put_item(
                Item={
                    'ReservationId': ri_id,
                    'Timestamp': int(current_time.timestamp()),
                    'InstanceType': ri['InstanceType'],
                    'InstanceCount': ri['InstanceCount'],
                    'State': ri['State'],
                    'Start': ri['Start'].isoformat(),
                    'End': ri['End'].isoformat(),
                    'Duration': ri['Duration'],
                    'OfferingClass': ri['OfferingClass'],
                    'OfferingType': ri['OfferingType'],
                    'DaysUntilExpiration': days_until_expiration,
                    'AvailabilityZone': ri.get('AvailabilityZone', 'N/A'),
                    'Region': ri['AvailabilityZone'][:-1] if ri.get('AvailabilityZone') else 'N/A'
                }
            )
            
            # Check for expiration alerts
            if days_until_expiration <= 90:  # 90 days warning
                alert_type = 'EXPIRING_SOON' if days_until_expiration > 30 else 'EXPIRING_VERY_SOON'
                alerts.append({
                    'reservation_id': ri_id,
                    'instance_type': ri['InstanceType'],
                    'instance_count': ri['InstanceCount'],
                    'days_until_expiration': days_until_expiration,
                    'end_date': ri['End'].strftime('%Y-%m-%d'),
                    'alert_type': alert_type
                })
        
        # Send alerts if any
        if alerts:
            message = f"Reserved Instance Expiration Alert\\n\\n"
            
            for alert in alerts:
                urgency = "URGENT" if alert['days_until_expiration'] <= 30 else "WARNING"
                message += f"[{urgency}] RI {alert['reservation_id']}\\n"
                message += f"  Instance Type: {alert['instance_type']}\\n"
                message += f"  Count: {alert['instance_count']}\\n"
                message += f"  Expires: {alert['end_date']} ({alert['days_until_expiration']} days)\\n\\n"
            
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject="Reserved Instance Expiration Alert",
                Message=message
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'RI monitoring completed',
                'total_reservations': len(response['ReservedInstances']),
                'expiration_alerts': len(alerts)
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
`;
  }
}

/**
 * CDK App for Reserved Instance Management Automation
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const projectName = app.node.tryGetContext('projectName') || process.env.PROJECT_NAME || 'ri-management';
const notificationEmail = app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL;
const bucketNamePrefix = app.node.tryGetContext('bucketNamePrefix') || process.env.BUCKET_NAME_PREFIX || 'ri-reports';

// Create the stack
new RIManagementStack(app, 'RIManagementStack', {
  projectName: projectName,
  notificationEmail: notificationEmail,
  bucketNamePrefix: bucketNamePrefix,
  description: 'Reserved Instance Management Automation with Cost Explorer and Lambda',
  tags: {
    Project: projectName,
    Application: 'RI Management Automation',
    Environment: app.node.tryGetContext('environment') || 'development'
  }
});

// Add metadata to the app
app.node.setContext('@aws-cdk/core:enableStackNameDuplicates', true);