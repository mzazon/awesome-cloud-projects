#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as vpclattice from 'aws-cdk-lib/aws-vpclattice';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * VPC Lattice Cost Analytics Stack
 * 
 * This CDK stack deploys a comprehensive cost analytics platform for VPC Lattice
 * service meshes. It combines CloudWatch metrics, Cost Explorer APIs, and automated
 * analysis to provide insights into service mesh economics and optimization opportunities.
 */
export class VpcLatticeCostAnalyticsStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique identifier for resource naming
    const uniqueId = this.node.addr.substring(0, 8).toLowerCase();

    // Create S3 bucket for analytics data storage
    const analyticsBucket = new s3.Bucket(this, 'AnalyticsBucket', {
      bucketName: `lattice-analytics-${uniqueId}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'cost-reports-lifecycle',
          prefix: 'cost-reports/',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
          expiration: cdk.Duration.days(365),
        },
      ],
    });

    // Apply cost allocation tags to the bucket
    cdk.Tags.of(analyticsBucket).add('CostCenter', 'engineering');
    cdk.Tags.of(analyticsBucket).add('Project', 'lattice-cost-analytics');
    cdk.Tags.of(analyticsBucket).add('Environment', 'production');
    cdk.Tags.of(analyticsBucket).add('ServiceMesh', 'vpc-lattice');

    // Create IAM role for the Lambda function with least privilege access
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `LatticeAnalyticsRole-${uniqueId}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for VPC Lattice cost analytics Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        CostAnalyticsPolicy: new iam.PolicyDocument({
          statements: [
            // Cost Explorer permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ce:GetCostAndUsage',
                'ce:GetUsageReport',
                'ce:ListCostCategoryDefinitions',
                'ce:GetCostCategories',
                'ce:GetRecommendations',
              ],
              resources: ['*'],
            }),
            // CloudWatch permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:GetMetricStatistics',
                'cloudwatch:GetMetricData',
                'cloudwatch:ListMetrics',
                'cloudwatch:PutMetricData',
              ],
              resources: ['*'],
            }),
            // VPC Lattice permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'vpc-lattice:GetService',
                'vpc-lattice:GetServiceNetwork',
                'vpc-lattice:ListServices',
                'vpc-lattice:ListServiceNetworks',
              ],
              resources: ['*'],
            }),
            // S3 permissions for analytics bucket
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
              ],
              resources: [analyticsBucket.arnForObjects('*')],
            }),
          ],
        }),
      },
    });

    // Apply cost allocation tags to the IAM role
    cdk.Tags.of(lambdaRole).add('CostCenter', 'engineering');
    cdk.Tags.of(lambdaRole).add('Project', 'lattice-cost-analytics');

    // Create Lambda function for cost analytics processing
    const costAnalyticsFunction = new lambda.Function(this, 'CostAnalyticsFunction', {
      functionName: `lattice-cost-processor-${uniqueId}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'lambda_function.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      description: 'VPC Lattice cost analytics processor with Cost Explorer integration',
      environment: {
        BUCKET_NAME: analyticsBucket.bucketName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import datetime
from decimal import Decimal
import os

def lambda_handler(event, context):
    ce_client = boto3.client('ce')
    cw_client = boto3.client('cloudwatch')
    s3_client = boto3.client('s3')
    lattice_client = boto3.client('vpc-lattice')
    
    bucket_name = os.environ['BUCKET_NAME']
    
    # Calculate date range for cost analysis
    end_date = datetime.datetime.now().date()
    start_date = end_date - datetime.timedelta(days=7)
    
    try:
        # Get VPC Lattice service networks
        service_networks = lattice_client.list_service_networks()
        
        cost_data = {}
        
        # Query Cost Explorer for VPC Lattice related costs
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
            ],
            Filter={
                'Or': [
                    {
                        'Dimensions': {
                            'Key': 'SERVICE',
                            'Values': ['Amazon Virtual Private Cloud']
                        }
                    },
                    {
                        'Dimensions': {
                            'Key': 'SERVICE',
                            'Values': ['VPC Lattice', 'Amazon VPC Lattice']
                        }
                    }
                ]
            }
        )
        
        # Process cost data
        for result in response['ResultsByTime']:
            date = result['TimePeriod']['Start']
            for group in result['Groups']:
                service = group['Keys'][0]
                region = group['Keys'][1]
                amount = float(group['Metrics']['BlendedCost']['Amount'])
                
                cost_data[f"{date}_{service}_{region}"] = {
                    'date': date,
                    'service': service,
                    'region': region,
                    'cost': amount,
                    'currency': group['Metrics']['BlendedCost']['Unit']
                }
        
        # Get VPC Lattice CloudWatch metrics
        metrics_data = {}
        for network in service_networks.get('items', []):
            network_id = network['id']
            network_name = network.get('name', network_id)
            
            # Get request count metrics for service network
            metric_response = cw_client.get_metric_statistics(
                Namespace='AWS/VpcLattice',
                MetricName='TotalRequestCount',
                Dimensions=[
                    {'Name': 'ServiceNetwork', 'Value': network_id}
                ],
                StartTime=datetime.datetime.combine(start_date, datetime.time.min),
                EndTime=datetime.datetime.combine(end_date, datetime.time.min),
                Period=86400,  # Daily
                Statistics=['Sum']
            )
            
            total_requests = sum([point['Sum'] for point in metric_response['Datapoints']])
            
            metrics_data[network_id] = {
                'network_name': network_name,
                'request_count': total_requests
            }
        
        # Combine cost and metrics data
        analytics_report = {
            'report_date': end_date.isoformat(),
            'time_period': {
                'start': start_date.isoformat(),
                'end': end_date.isoformat()
            },
            'cost_data': cost_data,
            'metrics_data': metrics_data,
            'summary': {
                'total_cost': sum([item['cost'] for item in cost_data.values()]),
                'total_requests': sum([item['request_count'] for item in metrics_data.values()]),
                'cost_per_request': 0
            }
        }
        
        # Calculate cost per request if requests exist
        if analytics_report['summary']['total_requests'] > 0:
            analytics_report['summary']['cost_per_request'] = (
                analytics_report['summary']['total_cost'] / 
                analytics_report['summary']['total_requests']
            )
        
        # Store analytics report in S3
        report_key = f"cost-reports/{end_date.isoformat()}_lattice_analytics.json"
        s3_client.put_object(
            Bucket=bucket_name,
            Key=report_key,
            Body=json.dumps(analytics_report, indent=2),
            ContentType='application/json'
        )
        
        # Create CloudWatch custom metrics
        cw_client.put_metric_data(
            Namespace='VPCLattice/CostAnalytics',
            MetricData=[
                {
                    'MetricName': 'TotalCost',
                    'Value': analytics_report['summary']['total_cost'],
                    'Unit': 'None'
                },
                {
                    'MetricName': 'TotalRequests',
                    'Value': analytics_report['summary']['total_requests'],
                    'Unit': 'Count'
                },
                {
                    'MetricName': 'CostPerRequest',
                    'Value': analytics_report['summary']['cost_per_request'],
                    'Unit': 'None'
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost analytics completed successfully',
                'report_location': f's3://{bucket_name}/{report_key}',
                'summary': analytics_report['summary']
            })
        }
        
    except Exception as e:
        print(f"Error processing cost analytics: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
`),
    });

    // Apply cost allocation tags to the Lambda function
    cdk.Tags.of(costAnalyticsFunction).add('CostCenter', 'engineering');
    cdk.Tags.of(costAnalyticsFunction).add('Project', 'lattice-cost-analytics');
    cdk.Tags.of(costAnalyticsFunction).add('Environment', 'production');

    // Create CloudWatch log group for Lambda function with retention policy
    new logs.LogGroup(this, 'CostAnalyticsLogGroup', {
      logGroupName: `/aws/lambda/${costAnalyticsFunction.functionName}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create demo VPC Lattice service network for testing
    const demoServiceNetwork = new vpclattice.CfnServiceNetwork(this, 'DemoServiceNetwork', {
      name: `cost-demo-network-${uniqueId}`,
      authType: 'AWS_IAM',
      tags: [
        {
          key: 'Project',
          value: 'lattice-cost-analytics',
        },
        {
          key: 'Environment',
          value: 'demo',
        },
        {
          key: 'CostCenter',
          value: 'engineering',
        },
      ],
    });

    // Create demo service within the network
    const demoService = new vpclattice.CfnService(this, 'DemoService', {
      name: `demo-service-${uniqueId}`,
      authType: 'AWS_IAM',
      tags: [
        {
          key: 'Project',
          value: 'lattice-cost-analytics',
        },
        {
          key: 'ServiceType',
          value: 'demo',
        },
      ],
    });

    // Associate service with service network
    new vpclattice.CfnServiceNetworkServiceAssociation(this, 'DemoServiceAssociation', {
      serviceNetworkIdentifier: demoServiceNetwork.attrId,
      serviceIdentifier: demoService.attrId,
      tags: [
        {
          key: 'Project',
          value: 'lattice-cost-analytics',
        },
      ],
    });

    // Create EventBridge rule for daily cost analysis
    const costAnalysisRule = new events.Rule(this, 'DailyCostAnalysisRule', {
      ruleName: `lattice-cost-analysis-${uniqueId}`,
      description: 'Daily VPC Lattice cost analysis trigger',
      schedule: events.Schedule.rate(cdk.Duration.days(1)),
      enabled: true,
    });

    // Add Lambda function as target for EventBridge rule
    costAnalysisRule.addTarget(new targets.LambdaFunction(costAnalyticsFunction));

    // Create CloudWatch dashboard for cost visualization
    const dashboard = new cloudwatch.Dashboard(this, 'CostAnalyticsDashboard', {
      dashboardName: `VPCLattice-CostAnalytics-${uniqueId}`,
      widgets: [
        [
          // Cost and traffic overview widget
          new cloudwatch.GraphWidget({
            title: 'VPC Lattice Cost and Traffic Overview',
            left: [
              new cloudwatch.Metric({
                namespace: 'VPCLattice/CostAnalytics',
                metricName: 'TotalCost',
                statistic: 'Sum',
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'VPCLattice/CostAnalytics',
                metricName: 'TotalRequests',
                statistic: 'Sum',
              }),
            ],
            period: cdk.Duration.days(1),
            width: 12,
            height: 6,
          }),
          // Cost per request efficiency widget
          new cloudwatch.GraphWidget({
            title: 'Cost Per Request Efficiency',
            left: [
              new cloudwatch.Metric({
                namespace: 'VPCLattice/CostAnalytics',
                metricName: 'CostPerRequest',
                statistic: 'Average',
              }),
            ],
            period: cdk.Duration.days(1),
            width: 12,
            height: 6,
          }),
        ],
        [
          // VPC Lattice service network traffic metrics
          new cloudwatch.GraphWidget({
            title: 'VPC Lattice Service Network Traffic Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/VpcLattice',
                metricName: 'TotalRequestCount',
                dimensionsMap: {
                  ServiceNetwork: demoServiceNetwork.attrId,
                },
                statistic: 'Sum',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/VpcLattice',
                metricName: 'ActiveConnectionCount',
                dimensionsMap: {
                  ServiceNetwork: demoServiceNetwork.attrId,
                },
                statistic: 'Sum',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/VpcLattice',
                metricName: 'TotalConnectionCount',
                dimensionsMap: {
                  ServiceNetwork: demoServiceNetwork.attrId,
                },
                statistic: 'Sum',
              }),
            ],
            period: cdk.Duration.minutes(5),
            width: 24,
            height: 6,
          }),
        ],
      ],
    });

    // Output important resource information
    new cdk.CfnOutput(this, 'AnalyticsBucketName', {
      value: analyticsBucket.bucketName,
      description: 'S3 bucket for storing cost analytics reports',
      exportName: `${this.stackName}-AnalyticsBucket`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: costAnalyticsFunction.functionName,
      description: 'Lambda function for cost analytics processing',
      exportName: `${this.stackName}-LambdaFunction`,
    });

    new cdk.CfnOutput(this, 'ServiceNetworkId', {
      value: demoServiceNetwork.attrId,
      description: 'Demo VPC Lattice service network ID',
      exportName: `${this.stackName}-ServiceNetwork`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch dashboard URL for cost analytics',
      exportName: `${this.stackName}-Dashboard`,
    });

    new cdk.CfnOutput(this, 'ManualTestCommand', {
      value: `aws lambda invoke --function-name ${costAnalyticsFunction.functionName} --payload '{}' response.json`,
      description: 'AWS CLI command to manually test the cost analytics function',
      exportName: `${this.stackName}-TestCommand`,
    });
  }
}

// Create the CDK application
const app = new cdk.App();

// Deploy the VPC Lattice Cost Analytics stack
new VpcLatticeCostAnalyticsStack(app, 'VpcLatticeCostAnalyticsStack', {
  description: 'Service mesh cost analytics with VPC Lattice and Cost Explorer integration',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'lattice-cost-analytics',
    CostCenter: 'engineering',
    Environment: 'production',
    ServiceMesh: 'vpc-lattice',
    ManagedBy: 'cdk',
  },
});

// Synthesize the CloudFormation template
app.synth();