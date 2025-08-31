#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as vpclattice from 'aws-cdk-lib/aws-vpclattice';
import * as fs from 'fs';
import * as path from 'path';

/**
 * Properties for the Service Performance Cost Analytics Stack
 */
interface ServicePerformanceCostAnalyticsStackProps extends cdk.StackProps {
  /**
   * Unique suffix for resource naming to avoid conflicts
   * @default - A random 6-character string will be generated
   */
  readonly uniqueSuffix?: string;

  /**
   * Environment for resource tagging and identification
   * @default 'demo'
   */
  readonly environment?: string;

  /**
   * CloudWatch Logs retention period in days
   * @default 7
   */
  readonly logRetentionDays?: number;

  /**
   * EventBridge rule schedule expression for analytics execution
   * @default 'rate(6 hours)'
   */
  readonly analyticsSchedule?: string;

  /**
   * Enable Cost Anomaly Detection integration
   * @default true
   */
  readonly enableCostAnomalyDetection?: boolean;
}

/**
 * CDK Stack for Service Performance Cost Analytics with VPC Lattice and CloudWatch Insights
 * 
 * This stack implements an advanced analytics system that correlates VPC Lattice service mesh
 * performance metrics with AWS costs using CloudWatch Insights queries and Cost Explorer API
 * integration. The solution creates automated cost-performance dashboards, identifies optimization
 * opportunities, and generates actionable recommendations through serverless Lambda functions.
 */
export class ServicePerformanceCostAnalyticsStack extends cdk.Stack {
  public readonly serviceNetwork: vpclattice.CfnServiceNetwork;
  public readonly performanceAnalyzer: lambda.Function;
  public readonly costCorrelator: lambda.Function;
  public readonly reportGenerator: lambda.Function;
  public readonly analyticsRole: iam.Role;
  public readonly logGroup: logs.LogGroup;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: ServicePerformanceCostAnalyticsStackProps = {}) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = props.uniqueSuffix || this.generateRandomSuffix();
    const environment = props.environment || 'demo';
    const logRetentionDays = props.logRetentionDays || 7;
    const analyticsSchedule = props.analyticsSchedule || 'rate(6 hours)';

    // Add stack-level tags
    cdk.Tags.of(this).add('Purpose', 'PerformanceCostAnalytics');
    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('Stack', 'ServicePerformanceCostAnalytics');

    // Create CloudWatch Log Group for VPC Lattice logs
    this.logGroup = new logs.LogGroup(this, 'VpcLatticeLogGroup', {
      logGroupName: `/aws/vpclattice/performance-analytics`,
      retention: logs.RetentionDays[`DAYS_${logRetentionDays}` as keyof typeof logs.RetentionDays],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create IAM role for Lambda functions with comprehensive permissions
    this.analyticsRole = this.createAnalyticsRole(uniqueSuffix);

    // Create VPC Lattice Service Network
    this.serviceNetwork = this.createServiceNetwork(uniqueSuffix);

    // Configure CloudWatch Logs integration for VPC Lattice
    this.configureVpcLatticeLogging();

    // Create Lambda functions for analytics pipeline
    this.performanceAnalyzer = this.createPerformanceAnalyzer(uniqueSuffix);
    this.costCorrelator = this.createCostCorrelator(uniqueSuffix);
    this.reportGenerator = this.createReportGenerator(uniqueSuffix);

    // Create sample VPC Lattice service for testing
    this.createSampleService(uniqueSuffix);

    // Set up automated scheduling with EventBridge
    this.createScheduledAnalytics(analyticsSchedule, uniqueSuffix);

    // Create CloudWatch Dashboard for performance cost analytics
    this.dashboard = this.createPerformanceDashboard(uniqueSuffix);

    // Configure Cost Anomaly Detection if enabled
    if (props.enableCostAnomalyDetection !== false) {
      this.createCostAnomalyDetection(uniqueSuffix);
    }

    // Output important resource information
    this.createStackOutputs(uniqueSuffix);
  }

  /**
   * Generate a random 6-character suffix for resource naming
   */
  private generateRandomSuffix(): string {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    let result = '';
    for (let i = 0; i < 6; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return result;
  }

  /**
   * Create IAM role for Lambda functions with necessary permissions
   */
  private createAnalyticsRole(uniqueSuffix: string): iam.Role {
    const role = new iam.Role(this, 'LatticeAnalyticsRole', {
      roleName: `lattice-analytics-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for VPC Lattice performance cost analytics Lambda functions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchLogsFullAccess'),
      ],
    });

    // Create custom policy for Cost Explorer and VPC Lattice access
    const customPolicy = new iam.Policy(this, 'CostExplorerAnalyticsPolicy', {
      policyName: `CostExplorerAnalyticsPolicy-${uniqueSuffix}`,
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'ce:GetCostAndUsage',
            'ce:GetDimensionValues',
            'ce:GetMetricsAndUsage',
            'ce:ListCostCategoryDefinitions',
            'ce:GetUsageReport',
            'ce:GetAnomalyDetectors',
            'ce:GetAnomalySubscriptions',
          ],
          resources: ['*'],
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'cloudwatch:PutMetricData',
            'logs:StartQuery',
            'logs:GetQueryResults',
            'vpc-lattice:GetService',
            'vpc-lattice:GetServiceNetwork',
            'vpc-lattice:ListServices',
            'vpc-lattice:ListServiceNetworks',
          ],
          resources: ['*'],
        }),
      ],
    });

    role.attachInlinePolicy(customPolicy);
    return role;
  }

  /**
   * Create VPC Lattice Service Network with monitoring enabled
   */
  private createServiceNetwork(uniqueSuffix: string): vpclattice.CfnServiceNetwork {
    const serviceNetwork = new vpclattice.CfnServiceNetwork(this, 'AnalyticsServiceNetwork', {
      name: `analytics-mesh-${uniqueSuffix}`,
      authType: 'AWS_IAM',
      tags: [
        { key: 'Purpose', value: 'PerformanceCostAnalytics' },
        { key: 'Environment', value: 'Demo' },
      ],
    });

    return serviceNetwork;
  }

  /**
   * Configure CloudWatch Logs integration for VPC Lattice
   */
  private configureVpcLatticeLogging(): void {
    // Configure access logs for the service network
    new vpclattice.CfnAccessLogSubscription(this, 'VpcLatticeAccessLogSubscription', {
      resourceIdentifier: this.serviceNetwork.attrArn,
      destinationArn: this.logGroup.logGroupArn,
      tags: [
        { key: 'Purpose', value: 'PerformanceCostAnalytics' },
      ],
    });
  }

  /**
   * Create Performance Metrics Analyzer Lambda Function
   */
  private createPerformanceAnalyzer(uniqueSuffix: string): lambda.Function {
    const functionCode = this.getPerformanceAnalyzerCode();

    return new lambda.Function(this, 'PerformanceAnalyzer', {
      functionName: `performance-analyzer-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(functionCode),
      role: this.analyticsRole,
      timeout: cdk.Duration.seconds(90),
      memorySize: 256,
      description: 'Analyzes VPC Lattice performance metrics using CloudWatch Insights',
      environment: {
        LOG_GROUP_NAME: this.logGroup.logGroupName,
      },
      retryAttempts: 2,
    });
  }

  /**
   * Create Cost Correlation Lambda Function
   */
  private createCostCorrelator(uniqueSuffix: string): lambda.Function {
    const functionCode = this.getCostCorrelatorCode();

    return new lambda.Function(this, 'CostCorrelator', {
      functionName: `cost-correlator-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(functionCode),
      role: this.analyticsRole,
      timeout: cdk.Duration.seconds(120),
      memorySize: 512,
      description: 'Correlates VPC Lattice performance with AWS costs',
      retryAttempts: 2,
    });
  }

  /**
   * Create Report Generator Lambda Function
   */
  private createReportGenerator(uniqueSuffix: string): lambda.Function {
    const functionCode = this.getReportGeneratorCode();

    return new lambda.Function(this, 'ReportGenerator', {
      functionName: `report-generator-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(functionCode),
      role: this.analyticsRole,
      timeout: cdk.Duration.seconds(180),
      memorySize: 256,
      description: 'Orchestrates performance and cost analysis reporting',
      environment: {
        PERFORMANCE_ANALYZER_FUNCTION: this.performanceAnalyzer.functionName,
        COST_CORRELATOR_FUNCTION: this.costCorrelator.functionName,
      },
      retryAttempts: 2,
    });

    // Grant invoke permissions between Lambda functions
    this.performanceAnalyzer.grantInvoke(this.reportGenerator);
    this.costCorrelator.grantInvoke(this.reportGenerator);

    return this.reportGenerator;
  }

  /**
   * Create sample VPC Lattice service for testing
   */
  private createSampleService(uniqueSuffix: string): vpclattice.CfnService {
    const sampleService = new vpclattice.CfnService(this, 'SampleAnalyticsService', {
      name: `sample-analytics-service-${uniqueSuffix}`,
      tags: [
        { key: 'Purpose', value: 'AnalyticsDemo' },
        { key: 'CostCenter', value: 'Analytics' },
      ],
    });

    // Associate service with the service network
    new vpclattice.CfnServiceNetworkServiceAssociation(this, 'SampleServiceAssociation', {
      serviceNetworkIdentifier: this.serviceNetwork.attrId,
      serviceIdentifier: sampleService.attrId,
      tags: [
        { key: 'Purpose', value: 'AnalyticsDemo' },
      ],
    });

    return sampleService;
  }

  /**
   * Set up automated scheduling with EventBridge
   */
  private createScheduledAnalytics(scheduleExpression: string, uniqueSuffix: string): void {
    const analyticsRule = new events.Rule(this, 'AnalyticsScheduler', {
      ruleName: `analytics-scheduler-${uniqueSuffix}`,
      schedule: events.Schedule.expression(scheduleExpression),
      description: 'Trigger VPC Lattice performance cost analytics on schedule',
      enabled: true,
    });

    analyticsRule.addTarget(new targets.LambdaFunction(this.reportGenerator, {
      event: events.RuleTargetInput.fromObject({
        suffix: uniqueSuffix,
        log_group: this.logGroup.logGroupName,
      }),
    }));
  }

  /**
   * Create CloudWatch Dashboard for performance cost analytics
   */
  private createPerformanceDashboard(uniqueSuffix: string): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'PerformanceDashboard', {
      dashboardName: `VPC-Lattice-Performance-Cost-Analytics-${uniqueSuffix}`,
      defaultInterval: cdk.Duration.hours(1),
    });

    // Add VPC Lattice performance metrics widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'VPC Lattice Performance Metrics',
        width: 12,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/VPCLattice',
            metricName: 'NewConnectionCount',
            dimensionsMap: {
              ServiceNetwork: `analytics-mesh-${uniqueSuffix}`,
            },
            statistic: 'Sum',
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/VPCLattice',
            metricName: 'ActiveConnectionCount',
            dimensionsMap: {
              ServiceNetwork: `analytics-mesh-${uniqueSuffix}`,
            },
            statistic: 'Average',
          }),
        ],
        right: [
          new cloudwatch.Metric({
            namespace: 'VPCLattice/Performance',
            metricName: 'AverageResponseTime',
            dimensionsMap: {
              ServiceName: `sample-analytics-service-${uniqueSuffix}`,
            },
            statistic: 'Average',
          }),
        ],
      })
    );

    // Add Lambda function metrics widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Analytics Functions Performance',
        width: 12,
        height: 6,
        left: [
          this.performanceAnalyzer.metricDuration(),
          this.costCorrelator.metricDuration(),
          this.reportGenerator.metricDuration(),
        ],
        right: [
          this.performanceAnalyzer.metricErrors(),
          this.costCorrelator.metricErrors(),
          this.reportGenerator.metricErrors(),
        ],
      })
    );

    // Add logs insights widget
    dashboard.addWidgets(
      new cloudwatch.LogQueryWidget({
        title: 'Service Response Time Analysis',
        width: 24,
        height: 6,
        logGroups: [this.logGroup],
        queryLines: [
          'fields @timestamp, targetService, responseTime, requestSize',
          'filter @message like /requestId/',
          'stats avg(responseTime) as avgResponseTime by targetService',
          'sort avgResponseTime desc',
        ],
      })
    );

    return dashboard;
  }

  /**
   * Configure Cost Anomaly Detection for proactive alerting
   */
  private createCostAnomalyDetection(uniqueSuffix: string): void {
    // Note: Cost Anomaly Detection resources are created using custom resources
    // as CDK doesn't have native L2 constructs for these services yet
    
    const costAnomalyDetector = new cdk.CustomResource(this, 'CostAnomalyDetector', {
      serviceToken: this.createCostAnomalyDetectorProvider().serviceToken,
      properties: {
        AnomalyDetectorName: `vpc-lattice-cost-anomalies-${uniqueSuffix}`,
        MonitorType: 'DIMENSIONAL',
        DimensionKey: 'SERVICE',
        DimensionValues: ['Amazon Virtual Private Cloud'],
      },
    });

    // Output the anomaly detector ARN for reference
    new cdk.CfnOutput(this, 'CostAnomalyDetectorArn', {
      value: costAnomalyDetector.getAttString('AnomalyDetectorArn'),
      description: 'ARN of the Cost Anomaly Detector for VPC Lattice services',
    });
  }

  /**
   * Create custom resource provider for Cost Anomaly Detection
   */
  private createCostAnomalyDetectorProvider(): cdk.CustomResourceProvider {
    return cdk.CustomResourceProvider.getOrCreateProvider(this, 'CostAnomalyDetectorProvider', {
      codeDirectory: path.join(__dirname, 'custom-resources'),
      runtime: cdk.CustomResourceProviderRuntime.NODEJS_18_X,
      description: 'Custom resource provider for Cost Anomaly Detection',
    });
  }

  /**
   * Create stack outputs for important resource information
   */
  private createStackOutputs(uniqueSuffix: string): void {
    new cdk.CfnOutput(this, 'ServiceNetworkId', {
      value: this.serviceNetwork.attrId,
      description: 'VPC Lattice Service Network ID',
      exportName: `ServiceNetworkId-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'ServiceNetworkArn', {
      value: this.serviceNetwork.attrArn,
      description: 'VPC Lattice Service Network ARN',
      exportName: `ServiceNetworkArn-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: this.logGroup.logGroupName,
      description: 'CloudWatch Log Group for VPC Lattice access logs',
      exportName: `LogGroupName-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'PerformanceAnalyzerFunctionName', {
      value: this.performanceAnalyzer.functionName,
      description: 'Performance Analyzer Lambda Function Name',
      exportName: `PerformanceAnalyzerFunction-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'CostCorrelatorFunctionName', {
      value: this.costCorrelator.functionName,
      description: 'Cost Correlator Lambda Function Name',
      exportName: `CostCorrelatorFunction-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'ReportGeneratorFunctionName', {
      value: this.reportGenerator.functionName,
      description: 'Report Generator Lambda Function Name',
      exportName: `ReportGeneratorFunction-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL for Performance Cost Analytics',
    });

    new cdk.CfnOutput(this, 'UniqueSuffix', {
      value: uniqueSuffix,
      description: 'Unique suffix used for resource naming',
      exportName: `UniqueSuffix-${uniqueSuffix}`,
    });
  }

  /**
   * Get Performance Analyzer Lambda function code
   */
  private getPerformanceAnalyzerCode(): string {
    return `
import json
import boto3
import time
from datetime import datetime, timedelta

def lambda_handler(event, context):
    logs_client = boto3.client('logs')
    cloudwatch = boto3.client('cloudwatch')
    
    try:
        # Calculate time range for analysis (last 24 hours)
        end_time = datetime.now()
        start_time = end_time - timedelta(hours=24)
        
        # CloudWatch Insights query for VPC Lattice performance
        query = """
        fields @timestamp, sourceVpc, targetService, responseTime, requestSize, responseSize
        | filter @message like /requestId/
        | stats avg(responseTime) as avgResponseTime, 
                sum(requestSize) as totalRequests,
                sum(responseSize) as totalBytes,
                count() as requestCount by targetService
        | sort avgResponseTime desc
        """
        
        # Start CloudWatch Insights query
        query_response = logs_client.start_query(
            logGroupName=event.get('log_group', '/aws/vpclattice/performance-analytics'),
            startTime=int(start_time.timestamp()),
            endTime=int(end_time.timestamp()),
            queryString=query
        )
        
        query_id = query_response['queryId']
        
        # Wait for query completion
        for attempt in range(30):  # Wait up to 30 seconds
            query_status = logs_client.get_query_results(queryId=query_id)
            if query_status['status'] == 'Complete':
                break
            elif query_status['status'] == 'Failed':
                raise Exception(f"Query failed: {query_status.get('statistics', {})}")
            time.sleep(1)
        else:
            raise Exception("Query timeout after 30 seconds")
        
        # Process results and publish custom metrics
        performance_data = []
        for result in query_status.get('results', []):
            service_metrics = {}
            for field in result:
                service_metrics[field['field']] = field['value']
            
            if service_metrics:
                performance_data.append(service_metrics)
                
                # Publish custom CloudWatch metrics
                if 'targetService' in service_metrics and 'avgResponseTime' in service_metrics:
                    try:
                        cloudwatch.put_metric_data(
                            Namespace='VPCLattice/Performance',
                            MetricData=[
                                {
                                    'MetricName': 'AverageResponseTime',
                                    'Dimensions': [
                                        {
                                            'Name': 'ServiceName',
                                            'Value': service_metrics['targetService']
                                        }
                                    ],
                                    'Value': float(service_metrics['avgResponseTime']),
                                    'Unit': 'Milliseconds',
                                    'Timestamp': datetime.now()
                                }
                            ]
                        )
                    except Exception as metric_error:
                        print(f"Error publishing metrics: {metric_error}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Performance analysis completed',
                'services_analyzed': len(performance_data),
                'performance_data': performance_data,
                'query_id': query_id
            })
        }
        
    except Exception as e:
        print(f"Error in performance analysis: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Performance analysis failed'
            })
        }
`;
  }

  /**
   * Get Cost Correlator Lambda function code
   */
  private getCostCorrelatorCode(): string {
    return `
import json
import boto3
from datetime import datetime, timedelta

def lambda_handler(event, context):
    ce_client = boto3.client('ce')
    
    try:
        # Calculate date range for cost analysis
        end_date = datetime.now()
        start_date = end_date - timedelta(days=7)
        
        # Get cost and usage data for VPC Lattice and related services
        cost_response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['BlendedCost', 'UsageQuantity'],
            GroupBy=[
                {
                    'Type': 'DIMENSION',
                    'Key': 'SERVICE'
                }
            ],
            Filter={
                'Dimensions': {
                    'Key': 'SERVICE',
                    'Values': ['Amazon Virtual Private Cloud', 'Amazon Elastic Compute Cloud - Compute', 'AWS Lambda'],
                    'MatchOptions': ['EQUALS']
                }
            }
        )
        
        # Process cost data
        cost_analysis = {}
        total_cost = 0.0
        
        for result_by_time in cost_response['ResultsByTime']:
            date = result_by_time['TimePeriod']['Start']
            cost_analysis[date] = {}
            
            for group in result_by_time['Groups']:
                service = group['Keys'][0]
                cost = float(group['Metrics']['BlendedCost']['Amount'])
                usage = float(group['Metrics']['UsageQuantity']['Amount'])
                
                cost_analysis[date][service] = {
                    'cost': cost,
                    'usage': usage,
                    'cost_per_unit': cost / usage if usage > 0 else 0
                }
                total_cost += cost
        
        # Correlate with performance data from event
        performance_data = event.get('performance_data', [])
        
        correlations = []
        for service_perf in performance_data:
            service_name = service_perf.get('targetService', 'unknown')
            avg_response_time = float(service_perf.get('avgResponseTime', 0)) if service_perf.get('avgResponseTime') else 0
            request_count = int(service_perf.get('requestCount', 0)) if service_perf.get('requestCount') else 0
            
            # Calculate cost efficiency metric
            vpc_cost = sum(
                day_data.get('Amazon Virtual Private Cloud', {}).get('cost', 0) 
                for day_data in cost_analysis.values()
            )
            
            if request_count > 0 and avg_response_time > 0:
                cost_per_request = vpc_cost / request_count if request_count > 0 else 0
                # Efficiency score: higher is better (inverse relationship with cost and response time)
                efficiency_score = 1000 / (avg_response_time * (cost_per_request + 0.001)) if (avg_response_time > 0 and cost_per_request >= 0) else 0
            else:
                cost_per_request = 0
                efficiency_score = 0
            
            correlations.append({
                'service': service_name,
                'avg_response_time': avg_response_time,
                'request_count': request_count,
                'estimated_cost': vpc_cost,
                'cost_per_request': cost_per_request,
                'efficiency_score': efficiency_score
            })
        
        # Sort by efficiency score to identify optimization opportunities
        correlations.sort(key=lambda x: x['efficiency_score'], reverse=True)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'cost_analysis': cost_analysis,
                'total_cost_analyzed': total_cost,
                'service_correlations': correlations,
                'optimization_candidates': [
                    corr for corr in correlations 
                    if corr['efficiency_score'] < 50  # Low efficiency threshold
                ]
            })
        }
        
    except Exception as e:
        print(f"Error in cost correlation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Cost correlation analysis failed'
            })
        }
`;
  }

  /**
   * Get Report Generator Lambda function code
   */
  private getReportGeneratorCode(): string {
    return `
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    lambda_client = boto3.client('lambda')
    
    try:
        suffix = event.get('suffix', '')
        log_group = event.get('log_group', '/aws/vpclattice/performance-analytics')
        
        # Get function names from environment variables
        perf_function = os.environ.get('PERFORMANCE_ANALYZER_FUNCTION', f"performance-analyzer-{suffix}")
        cost_function = os.environ.get('COST_CORRELATOR_FUNCTION', f"cost-correlator-{suffix}")
        
        # Invoke performance analyzer
        perf_response = lambda_client.invoke(
            FunctionName=perf_function,
            InvocationType='RequestResponse',
            Payload=json.dumps({
                'log_group': log_group
            })
        )
        
        perf_data = json.loads(perf_response['Payload'].read())
        
        # Check for errors in performance analysis
        if perf_data.get('statusCode') != 200:
            raise Exception(f"Performance analysis failed: {perf_data.get('body', 'Unknown error')}")
        
        perf_body = json.loads(perf_data.get('body', '{}'))
        
        # Invoke cost correlator with performance data
        cost_response = lambda_client.invoke(
            FunctionName=cost_function,
            InvocationType='RequestResponse',
            Payload=json.dumps({
                'performance_data': perf_body.get('performance_data', [])
            })
        )
        
        cost_data = json.loads(cost_response['Payload'].read())
        
        # Check for errors in cost analysis
        if cost_data.get('statusCode') != 200:
            raise Exception(f"Cost analysis failed: {cost_data.get('body', 'Unknown error')}")
        
        cost_body = json.loads(cost_data.get('body', '{}'))
        
        # Generate comprehensive report
        optimization_candidates = cost_body.get('optimization_candidates', [])
        
        report = {
            'timestamp': datetime.now().isoformat(),
            'summary': {
                'services_analyzed': perf_body.get('services_analyzed', 0),
                'optimization_opportunities': len(optimization_candidates),
                'total_cost_analyzed': cost_body.get('total_cost_analyzed', 0),
                'analysis_period': '24 hours (performance) / 7 days (cost)'
            },
            'performance_insights': perf_body.get('performance_data', []),
            'cost_correlations': cost_body.get('service_correlations', []),
            'optimization_recommendations': optimization_candidates
        }
        
        # Generate actionable recommendations
        recommendations = []
        for candidate in optimization_candidates:
            service_name = candidate.get('service', 'unknown')
            avg_response_time = candidate.get('avg_response_time', 0)
            cost_per_request = candidate.get('cost_per_request', 0)
            
            if avg_response_time > 500:  # High response time threshold
                recommendations.append(f"Service {service_name}: Consider optimizing for performance (avg response time: {avg_response_time:.2f}ms)")
            
            if cost_per_request > 0.01:  # High cost per request threshold
                recommendations.append(f"Service {service_name}: Review resource allocation (cost per request: ${cost_per_request:.4f})")
            
            if candidate.get('efficiency_score', 0) < 10:  # Very low efficiency
                recommendations.append(f"Service {service_name}: Critical efficiency review needed (efficiency score: {candidate.get('efficiency_score', 0):.2f})")
        
        if not recommendations:
            recommendations.append("No critical optimization opportunities identified. Continue monitoring for trends.")
        
        report['actionable_recommendations'] = recommendations
        
        return {
            'statusCode': 200,
            'body': json.dumps(report, default=str, indent=2)
        }
        
    except Exception as e:
        print(f"Error in report generation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Report generation failed',
                'timestamp': datetime.now().isoformat()
            })
        }
`;
  }
}

/**
 * CDK Application
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
};

const stackProps: ServicePerformanceCostAnalyticsStackProps = {
  env,
  description: 'Service Performance Cost Analytics with VPC Lattice and CloudWatch Insights',
  uniqueSuffix: app.node.tryGetContext('uniqueSuffix'),
  environment: app.node.tryGetContext('environment') || 'demo',
  logRetentionDays: app.node.tryGetContext('logRetentionDays') || 7,
  analyticsSchedule: app.node.tryGetContext('analyticsSchedule') || 'rate(6 hours)',
  enableCostAnomalyDetection: app.node.tryGetContext('enableCostAnomalyDetection') !== false,
};

new ServicePerformanceCostAnalyticsStack(app, 'ServicePerformanceCostAnalyticsStack', stackProps);

app.synth();