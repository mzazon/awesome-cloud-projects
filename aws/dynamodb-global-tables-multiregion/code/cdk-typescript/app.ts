#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Duration } from 'aws-cdk-lib';

/**
 * Interface defining the configuration for the DynamoDB Global Tables Stack
 */
interface GlobalTableStackProps extends cdk.StackProps {
  readonly tableName: string;
  readonly isPrimaryRegion: boolean;
  readonly replicaRegions: string[];
  readonly primaryRegion: string;
}

/**
 * Stack for deploying DynamoDB Global Tables with Lambda functions and CloudWatch monitoring
 * This stack implements a multi-region DynamoDB Global Table architecture with:
 * - DynamoDB table with streams enabled for global replication
 * - Lambda functions for testing global table operations
 * - CloudWatch alarms for monitoring replication latency and errors
 * - CloudWatch dashboard for operational visibility
 */
class DynamoDBGlobalTableStack extends cdk.Stack {
  public readonly table: dynamodb.Table;
  public readonly lambdaFunction: lambda.Function;
  public readonly lambdaRole: iam.Role;

  constructor(scope: Construct, id: string, props: GlobalTableStackProps) {
    super(scope, id, props);

    // Create IAM role for Lambda functions with DynamoDB permissions
    this.lambdaRole = new iam.Role(this, 'GlobalTableLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for Lambda functions accessing DynamoDB Global Tables',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        DynamoDBGlobalTablePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:PutItem',
                'dynamodb:GetItem',
                'dynamodb:UpdateItem',
                'dynamodb:DeleteItem',
                'dynamodb:Query',
                'dynamodb:Scan',
                'dynamodb:BatchGetItem',
                'dynamodb:BatchWriteItem',
                'dynamodb:DescribeTable',
                'dynamodb:DescribeStream',
                'dynamodb:GetRecords',
                'dynamodb:GetShardIterator',
                'dynamodb:ListStreams'
              ],
              resources: [
                `arn:aws:dynamodb:*:${this.account}:table/${props.tableName}`,
                `arn:aws:dynamodb:*:${this.account}:table/${props.tableName}/index/*`,
                `arn:aws:dynamodb:*:${this.account}:table/${props.tableName}/stream/*`
              ]
            })
          ]
        })
      }
    });

    // Create DynamoDB table with Global Tables configuration
    this.table = new dynamodb.Table(this, 'GlobalUserProfilesTable', {
      tableName: props.tableName,
      // Define composite primary key for user profiles
      partitionKey: {
        name: 'UserId',
        type: dynamodb.AttributeType.STRING
      },
      sortKey: {
        name: 'ProfileType',
        type: dynamodb.AttributeType.STRING
      },
      // Use on-demand billing for automatic scaling
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      // Enable streams for global replication (required for Global Tables)
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      // Enable point-in-time recovery for data protection
      pointInTimeRecovery: true,
      // Configure removal policy for cleanup
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      // Add Global Secondary Index for email-based queries
      globalSecondaryIndexes: [
        {
          indexName: 'EmailIndex',
          partitionKey: {
            name: 'Email',
            type: dynamodb.AttributeType.STRING
          },
          projectionType: dynamodb.ProjectionType.ALL
        }
      ],
      // Configure replica regions for Global Tables
      replicationRegions: props.isPrimaryRegion ? props.replicaRegions : undefined
    });

    // Create Lambda function for testing global table operations
    this.lambdaFunction = new lambda.Function(this, 'GlobalTableProcessor', {
      functionName: `GlobalTableProcessor-${props.tableName}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import time
from datetime import datetime

def lambda_handler(event, context):
    """
    Lambda function to process global table operations (put, get, scan)
    Supports testing cross-region replication and conflict resolution
    """
    try:
        # Get region from environment or context
        region = os.environ.get('AWS_REGION', context.invoked_function_arn.split(':')[3])
        
        # Initialize DynamoDB client
        dynamodb = boto3.resource('dynamodb', region_name=region)
        table = dynamodb.Table(os.environ['TABLE_NAME'])
        
        # Process the operation
        operation = event.get('operation', 'put')
        
        if operation == 'put':
            # Create or update an item
            user_id = event.get('userId', f'user-{int(time.time())}')
            profile_type = event.get('profileType', 'standard')
            
            item = {
                'UserId': user_id,
                'ProfileType': profile_type,
                'Name': event.get('name', 'Test User'),
                'Email': event.get('email', 'test@example.com'),
                'Region': region,
                'CreatedAt': datetime.utcnow().isoformat(),
                'LastModified': datetime.utcnow().isoformat()
            }
            
            response = table.put_item(Item=item)
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Item created in {region}',
                    'userId': user_id,
                    'profileType': profile_type,
                    'region': region
                })
            }
        
        elif operation == 'get':
            # Retrieve an item
            user_id = event.get('userId')
            profile_type = event.get('profileType', 'standard')
            
            if not user_id:
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'userId is required for get operation'})
                }
            
            response = table.get_item(
                Key={
                    'UserId': user_id,
                    'ProfileType': profile_type
                }
            )
            
            item = response.get('Item')
            if item:
                # Convert Decimal types to native types for JSON serialization
                item = json.loads(json.dumps(item, default=str))
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Item retrieved from {region}',
                    'item': item or 'Not found',
                    'region': region
                })
            }
        
        elif operation == 'scan':
            # Scan for items in this region
            response = table.scan(
                ProjectionExpression='UserId, ProfileType, #r, #n, Email',
                ExpressionAttributeNames={
                    '#r': 'Region',
                    '#n': 'Name'
                },
                Limit=10
            )
            
            items = response.get('Items', [])
            # Convert Decimal types to native types for JSON serialization
            items = json.loads(json.dumps(items, default=str))
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Items scanned from {region}',
                    'count': response['Count'],
                    'items': items,
                    'region': region
                })
            }
        
        elif operation == 'query-email':
            # Query using Global Secondary Index
            email = event.get('email')
            
            if not email:
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'email is required for query-email operation'})
                }
            
            response = table.query(
                IndexName='EmailIndex',
                KeyConditionExpression='Email = :email',
                ExpressionAttributeValues={
                    ':email': email
                }
            )
            
            items = response.get('Items', [])
            # Convert Decimal types to native types for JSON serialization
            items = json.loads(json.dumps(items, default=str))
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Items queried by email from {region}',
                    'count': response['Count'],
                    'items': items,
                    'region': region
                })
            }
        
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': f'Unknown operation: {operation}',
                    'supported_operations': ['put', 'get', 'scan', 'query-email']
                })
            }
    
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'region': region
            })
        }
      `),
      environment: {
        TABLE_NAME: this.table.tableName
      },
      role: this.lambdaRole,
      timeout: Duration.seconds(30),
      logRetention: logs.RetentionDays.ONE_WEEK,
      description: 'Lambda function for testing DynamoDB Global Table operations'
    });

    // Grant the Lambda function read/write permissions to the DynamoDB table
    this.table.grantReadWriteData(this.lambdaFunction);

    // Create CloudWatch alarms for monitoring (only in primary region)
    if (props.isPrimaryRegion) {
      this.createCloudWatchAlarms(props);
      this.createCloudWatchDashboard(props);
    }

    // Output important resource information
    new cdk.CfnOutput(this, 'TableName', {
      value: this.table.tableName,
      description: 'Name of the DynamoDB Global Table'
    });

    new cdk.CfnOutput(this, 'TableArn', {
      value: this.table.tableArn,
      description: 'ARN of the DynamoDB Global Table'
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: this.lambdaFunction.functionArn,
      description: 'ARN of the Lambda function for testing'
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: this.lambdaFunction.functionName,
      description: 'Name of the Lambda function for testing'
    });

    if (this.table.tableStreamArn) {
      new cdk.CfnOutput(this, 'TableStreamArn', {
        value: this.table.tableStreamArn,
        description: 'ARN of the DynamoDB table stream'
      });
    }
  }

  /**
   * Create CloudWatch alarms for monitoring Global Table metrics
   */
  private createCloudWatchAlarms(props: GlobalTableStackProps): void {
    // Create alarm for replication latency monitoring
    props.replicaRegions.forEach(region => {
      const replicationLatencyAlarm = new cloudwatch.Alarm(this, `ReplicationLatencyAlarm-${region}`, {
        alarmName: `GlobalTable-ReplicationLatency-${props.tableName}-${region}`,
        alarmDescription: `Monitor replication latency for global table ${props.tableName} to ${region}`,
        metric: new cloudwatch.Metric({
          namespace: 'AWS/DynamoDB',
          metricName: 'ReplicationLatency',
          dimensionsMap: {
            TableName: props.tableName,
            ReceivingRegion: region
          },
          statistic: 'Average',
          period: Duration.minutes(5)
        }),
        threshold: 10000, // 10 seconds in milliseconds
        evaluationPeriods: 2,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
      });

      // Add alarm description
      replicationLatencyAlarm.addAlarmDescription(
        `This alarm monitors replication latency from ${props.primaryRegion} to ${region}. ` +
        'High latency may indicate network issues or capacity constraints.'
      );
    });

    // Create alarm for user errors
    const userErrorsAlarm = new cloudwatch.Alarm(this, 'UserErrorsAlarm', {
      alarmName: `GlobalTable-UserErrors-${props.tableName}`,
      alarmDescription: `Monitor user errors for global table ${props.tableName}`,
      metric: new cloudwatch.Metric({
        namespace: 'AWS/DynamoDB',
        metricName: 'UserErrors',
        dimensionsMap: {
          TableName: props.tableName
        },
        statistic: 'Sum',
        period: Duration.minutes(5)
      }),
      threshold: 5,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    userErrorsAlarm.addAlarmDescription(
      'This alarm monitors user errors for the global table. ' +
      'High error rates may indicate application issues or throttling.'
    );

    // Create alarm for system errors
    const systemErrorsAlarm = new cloudwatch.Alarm(this, 'SystemErrorsAlarm', {
      alarmName: `GlobalTable-SystemErrors-${props.tableName}`,
      alarmDescription: `Monitor system errors for global table ${props.tableName}`,
      metric: new cloudwatch.Metric({
        namespace: 'AWS/DynamoDB',
        metricName: 'SystemErrors',
        dimensionsMap: {
          TableName: props.tableName
        },
        statistic: 'Sum',
        period: Duration.minutes(5)
      }),
      threshold: 1,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    systemErrorsAlarm.addAlarmDescription(
      'This alarm monitors system errors for the global table. ' +
      'System errors indicate issues with the DynamoDB service.'
    );
  }

  /**
   * Create CloudWatch dashboard for Global Table monitoring
   */
  private createCloudWatchDashboard(props: GlobalTableStackProps): void {
    const dashboard = new cloudwatch.Dashboard(this, 'GlobalTableDashboard', {
      dashboardName: `GlobalTable-${props.tableName}-Dashboard`,
      defaultInterval: Duration.minutes(5)
    });

    // Add capacity utilization widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Read/Write Capacity Utilization',
        width: 12,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/DynamoDB',
            metricName: 'ConsumedReadCapacityUnits',
            dimensionsMap: { TableName: props.tableName },
            statistic: 'Sum',
            period: Duration.minutes(5)
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/DynamoDB',
            metricName: 'ConsumedWriteCapacityUnits',
            dimensionsMap: { TableName: props.tableName },
            statistic: 'Sum',
            period: Duration.minutes(5)
          })
        ],
        stacked: false
      })
    );

    // Add replication latency widget
    const replicationLatencyMetrics = props.replicaRegions.map(region => 
      new cloudwatch.Metric({
        namespace: 'AWS/DynamoDB',
        metricName: 'ReplicationLatency',
        dimensionsMap: {
          TableName: props.tableName,
          ReceivingRegion: region
        },
        statistic: 'Average',
        period: Duration.minutes(5),
        label: `Replication to ${region}`
      })
    );

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Replication Latency by Region',
        width: 12,
        height: 6,
        left: replicationLatencyMetrics,
        stacked: false
      })
    );

    // Add error rates widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Error Rates',
        width: 12,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/DynamoDB',
            metricName: 'UserErrors',
            dimensionsMap: { TableName: props.tableName },
            statistic: 'Sum',
            period: Duration.minutes(5)
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/DynamoDB',
            metricName: 'SystemErrors',
            dimensionsMap: { TableName: props.tableName },
            statistic: 'Sum',
            period: Duration.minutes(5)
          })
        ],
        stacked: false
      })
    );

    // Add throttling widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Throttling Events',
        width: 12,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/DynamoDB',
            metricName: 'ReadThrottledRequests',
            dimensionsMap: { TableName: props.tableName },
            statistic: 'Sum',
            period: Duration.minutes(5)
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/DynamoDB',
            metricName: 'WriteThrottledRequests',
            dimensionsMap: { TableName: props.tableName },
            statistic: 'Sum',
            period: Duration.minutes(5)
          })
        ],
        stacked: false
      })
    );
  }
}

/**
 * CDK Application for DynamoDB Global Tables
 * This application creates a multi-region DynamoDB Global Table setup with:
 * - Primary region stack with monitoring and dashboard
 * - Replica region stacks for testing Lambda functions
 */
class DynamoDBGlobalTableApp extends cdk.App {
  constructor() {
    super();

    // Configuration for regions and table name
    const tableBaseName = 'GlobalUserProfiles';
    const primaryRegion = 'us-east-1';
    const replicaRegions = ['eu-west-1', 'ap-northeast-1'];
    const allRegions = [primaryRegion, ...replicaRegions];

    // Generate a unique suffix for resource names
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);
    const tableName = `${tableBaseName}-${uniqueSuffix}`;

    // Create stack in primary region with Global Table configuration
    const primaryStack = new DynamoDBGlobalTableStack(this, 'DynamoDBGlobalTableStack-Primary', {
      env: { region: primaryRegion },
      tableName: tableName,
      isPrimaryRegion: true,
      replicaRegions: replicaRegions,
      primaryRegion: primaryRegion,
      description: `Primary stack for DynamoDB Global Table ${tableName} in ${primaryRegion}`,
      tags: {
        Project: 'DynamoDB-Global-Tables',
        Environment: 'Demo',
        Region: primaryRegion,
        PrimaryRegion: 'true'
      }
    });

    // Create stacks in replica regions for Lambda testing functions
    replicaRegions.forEach(region => {
      const replicaStack = new DynamoDBGlobalTableStack(this, `DynamoDBGlobalTableStack-${region}`, {
        env: { region: region },
        tableName: tableName,
        isPrimaryRegion: false,
        replicaRegions: [],
        primaryRegion: primaryRegion,
        description: `Replica stack for DynamoDB Global Table ${tableName} in ${region}`,
        tags: {
          Project: 'DynamoDB-Global-Tables',
          Environment: 'Demo',
          Region: region,
          PrimaryRegion: 'false'
        }
      });

      // Add dependency to ensure primary stack is deployed first
      replicaStack.addDependency(primaryStack);
    });

    // Add global tags
    cdk.Tags.of(this).add('Project', 'DynamoDB-Global-Tables');
    cdk.Tags.of(this).add('CreatedBy', 'AWS-CDK');
    cdk.Tags.of(this).add('Purpose', 'Multi-Region-Database-Demo');
  }
}

// Create and run the CDK application
const app = new DynamoDBGlobalTableApp();