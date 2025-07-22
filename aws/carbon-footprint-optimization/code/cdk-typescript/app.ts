#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as scheduler from 'aws-cdk-lib/aws-scheduler';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as cur from 'aws-cdk-lib/aws-cur';
import * as path from 'path';

/**
 * Properties for the CarbonFootprintOptimizationStack
 */
interface CarbonFootprintOptimizationStackProps extends cdk.StackProps {
  /** Email address for notifications */
  notificationEmail?: string;
  /** Project name prefix for resources */
  projectName?: string;
  /** Environment type (production, staging, development) */
  environmentType?: string;
}

/**
 * CDK Stack for automated carbon footprint optimization using AWS Sustainability Scanner and Cost Explorer.
 * This stack creates a comprehensive solution for monitoring and optimizing cloud infrastructure's
 * environmental impact while maintaining cost efficiency.
 */
export class CarbonFootprintOptimizationStack extends cdk.Stack {
  public readonly dataStorageBucket: s3.Bucket;
  public readonly metricsTable: dynamodb.Table;
  public readonly optimizationFunction: lambda.Function;
  public readonly notificationTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: CarbonFootprintOptimizationStackProps = {}) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const randomSuffix = Math.random().toString(36).substring(2, 8);
    const projectName = props.projectName || `carbon-optimizer-${randomSuffix}`;

    // Tags to apply to all resources
    const commonTags = {
      Project: projectName,
      Purpose: 'CarbonFootprintOptimization',
      Environment: props.environmentType || 'production',
      CreatedBy: 'CDK-TypeScript'
    };

    // Apply common tags to the stack
    cdk.Tags.of(this).add('Project', commonTags.Project);
    cdk.Tags.of(this).add('Purpose', commonTags.Purpose);
    cdk.Tags.of(this).add('Environment', commonTags.Environment);
    cdk.Tags.of(this).add('CreatedBy', commonTags.CreatedBy);

    // Create S3 bucket for data storage with sustainability optimizations
    this.dataStorageBucket = new s3.Bucket(this, 'DataStorageBucket', {
      bucketName: `${projectName}-data`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For development - change for production
      autoDeleteObjects: true, // For development - remove for production
      // Sustainability optimizations
      intelligentTieringConfigurations: [{
        id: 'OptimizeStorage',
        status: s3.IntelligentTieringStatus.ENABLED,
        optionalFields: [s3.IntelligentTieringOptionalFields.BUCKET_KEY_STATUS]
      }],
      lifecycleRules: [
        {
          id: 'TransitionToIA',
          enabled: true,
          transitions: [{
            storageClass: s3.StorageClass.INFREQUENT_ACCESS,
            transitionAfter: cdk.Duration.days(30)
          }]
        },
        {
          id: 'TransitionToGlacier',
          enabled: true,
          transitions: [{
            storageClass: s3.StorageClass.GLACIER,
            transitionAfter: cdk.Duration.days(90)
          }]
        }
      ]
    });

    // Create DynamoDB table for metrics storage with on-demand billing for sustainability
    this.metricsTable = new dynamodb.Table(this, 'MetricsTable', {
      tableName: `${projectName}-metrics`,
      partitionKey: {
        name: 'MetricType',
        type: dynamodb.AttributeType.STRING
      },
      sortKey: {
        name: 'Timestamp',
        type: dynamodb.AttributeType.STRING
      },
      billingMode: dynamodb.BillingMode.ON_DEMAND, // More sustainable than provisioned for variable workloads
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For development - change for production
      pointInTimeRecovery: true,
      // Global Secondary Index for service-based queries
      globalSecondaryIndexes: [{
        indexName: 'ServiceCarbonIndex',
        partitionKey: {
          name: 'ServiceName',
          type: dynamodb.AttributeType.STRING
        },
        sortKey: {
          name: 'CarbonIntensity',
          type: dynamodb.AttributeType.NUMBER
        }
      }]
    });

    // Create SNS topic for notifications
    this.notificationTopic = new sns.Topic(this, 'NotificationTopic', {
      topicName: `${projectName}-notifications`,
      displayName: 'Carbon Footprint Optimization Notifications'
    });

    // Add email subscription if provided
    if (props.notificationEmail) {
      this.notificationTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(props.notificationEmail)
      );
    }

    // Create IAM role for Lambda function with comprehensive permissions
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `${projectName}-lambda-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        CarbonOptimizationPolicy: new iam.PolicyDocument({
          statements: [
            // Cost Explorer permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ce:GetCostAndUsage',
                'ce:GetDimensions',
                'ce:GetUsageReport',
                'ce:ListCostCategoryDefinitions',
                'cur:DescribeReportDefinitions'
              ],
              resources: ['*']
            }),
            // S3 permissions for data storage
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket'
              ],
              resources: [
                this.dataStorageBucket.bucketArn,
                `${this.dataStorageBucket.bucketArn}/*`
              ]
            }),
            // DynamoDB permissions for metrics storage
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:PutItem',
                'dynamodb:GetItem',
                'dynamodb:UpdateItem',
                'dynamodb:Query',
                'dynamodb:Scan'
              ],
              resources: [
                this.metricsTable.tableArn,
                `${this.metricsTable.tableArn}/index/*`
              ]
            }),
            // SNS permissions for notifications
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [this.notificationTopic.topicArn]
            }),
            // Systems Manager permissions for configuration
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ssm:GetParameter',
                'ssm:PutParameter',
                'ssm:GetParameters'
              ],
              resources: [`arn:aws:ssm:${this.region}:${this.account}:parameter/${projectName}/*`]
            })
          ]
        })
      }
    });

    // Create Lambda function for carbon footprint analysis
    this.optimizationFunction = new lambda.Function(this, 'CarbonOptimizationFunction', {
      functionName: `${projectName}-analyzer`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime, timedelta
from decimal import Decimal
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
ce_client = boto3.client('ce')
dynamodb = boto3.resource('dynamodb')
s3_client = boto3.client('s3')
sns_client = boto3.client('sns')
ssm_client = boto3.client('ssm')

# Environment variables
TABLE_NAME = os.environ['DYNAMODB_TABLE']
S3_BUCKET = os.environ['S3_BUCKET']
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']

table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    """
    Main handler for carbon footprint optimization analysis
    """
    try:
        logger.info("Starting carbon footprint optimization analysis")
        
        # Get current date range for analysis
        end_date = datetime.now().date()
        start_date = end_date - timedelta(days=30)
        
        # Fetch cost and usage data
        cost_data = get_cost_and_usage_data(start_date, end_date)
        
        # Analyze carbon footprint correlations
        carbon_analysis = analyze_carbon_footprint(cost_data)
        
        # Store metrics in DynamoDB
        store_metrics(carbon_analysis)
        
        # Generate optimization recommendations
        recommendations = generate_recommendations(carbon_analysis)
        
        # Send notifications if significant findings
        if recommendations['high_impact_actions']:
            send_optimization_notifications(recommendations)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Carbon footprint analysis completed successfully',
                'recommendations_count': len(recommendations['all_actions']),
                'high_impact_count': len(recommendations['high_impact_actions'])
            })
        }
        
    except Exception as e:
        logger.error(f"Error in carbon footprint analysis: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def get_cost_and_usage_data(start_date, end_date):
    """
    Retrieve cost and usage data from Cost Explorer
    """
    try:
        response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['BlendedCost', 'UsageQuantity'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'},
                {'Type': 'DIMENSION', 'Key': 'REGION'}
            ]
        )
        
        return response['ResultsByTime']
        
    except Exception as e:
        logger.error(f"Error retrieving cost data: {str(e)}")
        raise

def analyze_carbon_footprint(cost_data):
    """
    Analyze carbon footprint patterns based on cost and usage data
    """
    analysis = {
        'total_cost': 0,
        'estimated_carbon_kg': 0,
        'services': {},
        'regions': {},
        'optimization_potential': 0
    }
    
    # Carbon intensity factors (kg CO2e per USD) by service type
    carbon_factors = {
        'Amazon Elastic Compute Cloud': 0.5,
        'Amazon Simple Storage Service': 0.1,
        'Amazon Relational Database Service': 0.7,
        'AWS Lambda': 0.05,
        'Amazon CloudFront': 0.02
    }
    
    # Regional carbon intensity factors (kg CO2e per kWh)
    regional_factors = {
        'us-east-1': 0.4,  # Virginia - renewable energy mix
        'us-west-2': 0.2,  # Oregon - high renewable content
        'eu-west-1': 0.3,  # Ireland - moderate renewable mix
        'ap-southeast-2': 0.8  # Sydney - higher carbon intensity
    }
    
    for time_period in cost_data:
        for group in time_period.get('Groups', []):
            service = group['Keys'][0]
            region = group['Keys'][1] if len(group['Keys']) > 1 else 'global'
            
            cost = float(group['Metrics']['BlendedCost']['Amount'])
            analysis['total_cost'] += cost
            
            # Calculate estimated carbon footprint
            service_factor = carbon_factors.get(service, 0.3)
            regional_factor = regional_factors.get(region, 0.5)
            
            estimated_carbon = cost * service_factor * regional_factor
            analysis['estimated_carbon_kg'] += estimated_carbon
            
            # Track by service
            if service not in analysis['services']:
                analysis['services'][service] = {
                    'cost': 0, 'carbon_kg': 0, 'optimization_score': 0
                }
            
            analysis['services'][service]['cost'] += cost
            analysis['services'][service]['carbon_kg'] += estimated_carbon
            
            # Calculate optimization score (higher is better opportunity)
            analysis['services'][service]['optimization_score'] = (
                estimated_carbon / cost if cost > 0 else 0
            )
    
    return analysis

def generate_recommendations(analysis):
    """
    Generate carbon footprint optimization recommendations
    """
    recommendations = {
        'all_actions': [],
        'high_impact_actions': [],
        'estimated_savings': {'cost': 0, 'carbon_kg': 0}
    }
    
    # Analyze services with high carbon intensity
    for service, metrics in analysis['services'].items():
        if metrics['optimization_score'] > 0.5:  # High carbon per dollar
            recommendation = {
                'service': service,
                'current_cost': metrics['cost'],
                'current_carbon_kg': metrics['carbon_kg'],
                'action': determine_optimization_action(service, metrics),
                'estimated_cost_savings': metrics['cost'] * 0.2,
                'estimated_carbon_reduction': metrics['carbon_kg'] * 0.3
            }
            
            recommendations['all_actions'].append(recommendation)
            
            if metrics['cost'] > 100:  # High impact threshold
                recommendations['high_impact_actions'].append(recommendation)
                recommendations['estimated_savings']['cost'] += recommendation['estimated_cost_savings']
                recommendations['estimated_savings']['carbon_kg'] += recommendation['estimated_carbon_reduction']
    
    return recommendations

def determine_optimization_action(service, metrics):
    """
    Determine specific optimization action for a service
    """
    action_map = {
        'Amazon Elastic Compute Cloud': 'Consider rightsizing instances or migrating to Graviton processors',
        'Amazon Simple Storage Service': 'Implement Intelligent Tiering and lifecycle policies',
        'Amazon Relational Database Service': 'Evaluate Aurora Serverless or instance rightsizing',
        'AWS Lambda': 'Optimize memory allocation and enable Provisioned Concurrency',
        'Amazon CloudFront': 'Review caching strategies and origin optimization'
    }
    
    return action_map.get(service, 'Review resource utilization and consider sustainable alternatives')

def store_metrics(analysis):
    """
    Store analysis results in DynamoDB
    """
    timestamp = datetime.now().isoformat()
    
    # Store overall metrics
    table.put_item(
        Item={
            'MetricType': 'OVERALL_ANALYSIS',
            'Timestamp': timestamp,
            'TotalCost': Decimal(str(analysis['total_cost'])),
            'EstimatedCarbonKg': Decimal(str(analysis['estimated_carbon_kg'])),
            'ServiceCount': len(analysis['services'])
        }
    )
    
    # Store service-specific metrics
    for service, metrics in analysis['services'].items():
        table.put_item(
            Item={
                'MetricType': f'SERVICE_{service.replace(" ", "_").upper()}',
                'Timestamp': timestamp,
                'ServiceName': service,
                'Cost': Decimal(str(metrics['cost'])),
                'CarbonKg': Decimal(str(metrics['carbon_kg'])),
                'CarbonIntensity': Decimal(str(metrics['optimization_score']))
            }
        )

def send_optimization_notifications(recommendations):
    """
    Send notifications about optimization opportunities
    """
    message = f"""
Carbon Footprint Optimization Report

High-Impact Opportunities Found: {len(recommendations['high_impact_actions'])}

Estimated Monthly Savings:
- Cost: ${recommendations['estimated_savings']['cost']:.2f}
- Carbon: {recommendations['estimated_savings']['carbon_kg']:.2f} kg CO2e

Top Recommendations:
"""
    
    for i, action in enumerate(recommendations['high_impact_actions'][:3], 1):
        message += f"""
{i}. {action['service']}
   Current Cost: ${action['current_cost']:.2f}
   Carbon Impact: {action['current_carbon_kg']:.2f} kg CO2e
   Action: {action['action']}
"""
    
    try:
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject='Carbon Footprint Optimization Report',
            Message=message
        )
    except Exception as e:
        logger.error(f"Error sending notification: {str(e)}")
      `),
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      environment: {
        DYNAMODB_TABLE: this.metricsTable.tableName,
        S3_BUCKET: this.dataStorageBucket.bucketName,
        SNS_TOPIC_ARN: this.notificationTopic.topicArn
      },
      description: 'Analyzes carbon footprint and generates optimization recommendations'
    });

    // Create EventBridge schedules for automated analysis
    const schedulerRole = new iam.Role(this, 'SchedulerExecutionRole', {
      assumedBy: new iam.ServicePrincipal('scheduler.amazonaws.com'),
      inlinePolicies: {
        LambdaInvokePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['lambda:InvokeFunction'],
              resources: [this.optimizationFunction.functionArn]
            })
          ]
        })
      }
    });

    // Monthly comprehensive analysis schedule
    new scheduler.CfnSchedule(this, 'MonthlyAnalysisSchedule', {
      name: `${projectName}-monthly-analysis`,
      scheduleExpression: 'rate(30 days)',
      target: {
        arn: this.optimizationFunction.functionArn,
        roleArn: schedulerRole.roleArn
      },
      flexibleTimeWindow: {
        mode: 'OFF'
      },
      description: 'Monthly carbon footprint optimization analysis'
    });

    // Weekly trend monitoring schedule
    new scheduler.CfnSchedule(this, 'WeeklyTrendsSchedule', {
      name: `${projectName}-weekly-trends`,
      scheduleExpression: 'rate(7 days)',
      target: {
        arn: this.optimizationFunction.functionArn,
        roleArn: schedulerRole.roleArn
      },
      flexibleTimeWindow: {
        mode: 'OFF'
      },
      description: 'Weekly carbon footprint trend monitoring'
    });

    // Create Systems Manager parameter for sustainability scanner configuration
    new ssm.StringParameter(this, 'ScannerConfiguration', {
      parameterName: `/${projectName}/scanner-config`,
      stringValue: JSON.stringify({
        rules: [
          'ec2-instance-types',
          'storage-optimization',
          'graviton-processors',
          'regional-efficiency'
        ],
        severity: 'medium',
        auto_fix: false
      }),
      description: 'Sustainability Scanner configuration for carbon optimization'
    });

    // Create Cost and Usage Report (CUR) configuration
    new cur.CfnReportDefinition(this, 'CarbonOptimizationCUR', {
      reportName: 'carbon-optimization-detailed-report',
      timeUnit: 'DAILY',
      format: 'Parquet',
      compression: 'GZIP',
      additionalSchemaElements: ['RESOURCES', 'SPLIT_COST_ALLOCATION_DATA'],
      s3Bucket: this.dataStorageBucket.bucketName,
      s3Prefix: 'cost-usage-reports/',
      s3Region: this.region,
      additionalArtifacts: ['ATHENA'],
      refreshClosedReports: true,
      reportVersioning: 'OVERWRITE_REPORT'
    });

    // Output important resource information
    new cdk.CfnOutput(this, 'DataStorageBucketName', {
      value: this.dataStorageBucket.bucketName,
      description: 'S3 bucket for carbon footprint data storage'
    });

    new cdk.CfnOutput(this, 'MetricsTableName', {
      value: this.metricsTable.tableName,
      description: 'DynamoDB table for sustainability metrics'
    });

    new cdk.CfnOutput(this, 'OptimizationFunctionName', {
      value: this.optimizationFunction.functionName,
      description: 'Lambda function for carbon footprint analysis'
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'SNS topic for optimization notifications'
    });

    new cdk.CfnOutput(this, 'ProjectName', {
      value: projectName,
      description: 'Project identifier for all resources'
    });
  }
}

/**
 * CDK Application for Carbon Footprint Optimization
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const notificationEmail = app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL;
const projectName = app.node.tryGetContext('projectName') || process.env.PROJECT_NAME;
const environmentType = app.node.tryGetContext('environmentType') || process.env.ENVIRONMENT_TYPE || 'production';

// Create the stack
new CarbonFootprintOptimizationStack(app, 'CarbonFootprintOptimizationStack', {
  notificationEmail,
  projectName,
  environmentType,
  description: 'Automated carbon footprint optimization with AWS Sustainability Scanner and Cost Explorer',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },
  tags: {
    Application: 'CarbonFootprintOptimization',
    CreatedBy: 'CDK-TypeScript',
    Purpose: 'Sustainability'
  }
});

// Synthesize the app
app.synth();