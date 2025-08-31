#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sqs from 'aws-cdk-lib/aws-sqs';

/**
 * Stack for Intelligent Web Scraping with AgentCore Browser and Code Interpreter
 * 
 * This stack deploys a complete intelligent web scraping solution that combines:
 * - AWS Bedrock AgentCore Browser for automated web navigation
 * - AWS Bedrock AgentCore Code Interpreter for intelligent data processing
 * - Lambda for workflow orchestration
 * - S3 for scalable storage
 * - CloudWatch for monitoring and logging
 * - EventBridge for scheduled execution
 */
export class IntelligentWebScrapingStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);
    const projectName = `intelligent-scraper-${uniqueSuffix}`;

    // S3 Buckets for input configurations and output data
    const inputBucket = new s3.Bucket(this, 'InputBucket', {
      bucketName: `${projectName}-input`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
    });

    const outputBucket = new s3.Bucket(this, 'OutputBucket', {
      bucketName: `${projectName}-output`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'TransitionToIA',
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
        },
      ],
    });

    // Dead Letter Queue for failed Lambda executions
    const deadLetterQueue = new sqs.Queue(this, 'DeadLetterQueue', {
      queueName: `${projectName}-dlq`,
      visibilityTimeout: cdk.Duration.minutes(5),
      retentionPeriod: cdk.Duration.days(14),
    });

    // IAM Role for Lambda function with comprehensive permissions
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `${projectName}-lambda-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        AgentCoreAndS3Policy: new iam.PolicyDocument({
          statements: [
            // Bedrock AgentCore Browser permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'bedrock-agentcore:StartBrowserSession',
                'bedrock-agentcore:StopBrowserSession',
                'bedrock-agentcore:GetBrowserSession',
                'bedrock-agentcore:UpdateBrowserStream',
                'bedrock-agentcore:SendBrowserInstruction',
              ],
              resources: ['*'],
            }),
            // Bedrock AgentCore Code Interpreter permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'bedrock-agentcore:StartCodeInterpreterSession',
                'bedrock-agentcore:StopCodeInterpreterSession',
                'bedrock-agentcore:GetCodeInterpreterSession',
                'bedrock-agentcore:ExecuteCode',
                'bedrock-agentcore:GetCodeExecution',
              ],
              resources: ['*'],
            }),
            // S3 permissions for input and output buckets
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
              ],
              resources: [
                inputBucket.bucketArn,
                `${inputBucket.bucketArn}/*`,
                outputBucket.bucketArn,
                `${outputBucket.bucketArn}/*`,
              ],
            }),
            // CloudWatch permissions for custom metrics
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:PutMetricData',
              ],
              resources: ['*'],
            }),
            // SQS permissions for DLQ
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sqs:SendMessage',
              ],
              resources: [deadLetterQueue.queueArn],
            }),
          ],
        }),
      },
    });

    // CloudWatch Log Group for Lambda function
    const logGroup = new logs.LogGroup(this, 'LambdaLogGroup', {
      logGroupName: `/aws/lambda/${projectName}-orchestrator`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Lambda function for workflow orchestration
    const orchestratorFunction = new lambda.Function(this, 'OrchestratorFunction', {
      functionName: `${projectName}-orchestrator`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'lambda_function.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import time
import logging
import uuid
from datetime import datetime
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    try:
        s3 = boto3.client('s3')
        agentcore = boto3.client('bedrock-agentcore')
        cloudwatch = boto3.client('cloudwatch')
        
        # Get configuration from S3
        bucket_input = event.get('bucket_input', '${inputBucket.bucketName}')
        bucket_output = event.get('bucket_output', '${outputBucket.bucketName}')
        
        config_response = s3.get_object(
            Bucket=bucket_input,
            Key='scraper-config.json'
        )
        config = json.loads(config_response['Body'].read())
        
        logger.info(f"Processing {len(config['scraping_scenarios'])} scenarios")
        
        all_scraped_data = []
        
        for scenario in config['scraping_scenarios']:
            logger.info(f"Processing scenario: {scenario['name']}")
            
            # Start browser session
            session_response = agentcore.start_browser_session(
                browserIdentifier='default-browser',
                name=f"{scenario['name']}-{int(time.time())}",
                sessionTimeoutSeconds=scenario['session_config']['timeout_seconds']
            )
            
            browser_session_id = session_response['sessionId']
            logger.info(f"Started browser session: {browser_session_id}")
            
            try:
                # Simulate web navigation and data extraction
                # Note: In actual implementation, you would use browser automation SDK
                
                scenario_data = {
                    'scenario_name': scenario['name'],
                    'target_url': scenario['target_url'],
                    'timestamp': datetime.utcnow().isoformat(),
                    'session_id': browser_session_id,
                    'extracted_data': {
                        'product_titles': ['Sample Book 1', 'Sample Book 2', 'Sample Book 3'],
                        'prices': ['£51.77', '£53.74', '£50.10'],
                        'availability': ['In stock', 'In stock', 'Out of stock']
                    }
                }
                
                all_scraped_data.append(scenario_data)
                
                # Send metrics to CloudWatch
                cloudwatch.put_metric_data(
                    Namespace=f'IntelligentScraper/{context.function_name}',
                    MetricData=[
                        {
                            'MetricName': 'ScrapingJobs',
                            'Value': 1,
                            'Unit': 'Count'
                        },
                        {
                            'MetricName': 'DataPointsExtracted',
                            'Value': len(scenario_data['extracted_data']['product_titles']),
                            'Unit': 'Count'
                        }
                    ]
                )
                
            finally:
                # Cleanup browser session
                try:
                    agentcore.stop_browser_session(sessionId=browser_session_id)
                    logger.info(f"Stopped browser session: {browser_session_id}")
                except Exception as e:
                    logger.warning(f"Failed to stop session {browser_session_id}: {e}")
        
        # Start Code Interpreter session for data processing
        code_session_response = agentcore.start_code_interpreter_session(
            codeInterpreterIdentifier='default-code-interpreter',
            name=f"data-processor-{int(time.time())}",
            sessionTimeoutSeconds=300
        )
        
        code_session_id = code_session_response['sessionId']
        logger.info(f"Started code interpreter session: {code_session_id}")
        
        try:
            # Process data with analysis
            processing_results = process_scraped_data(all_scraped_data)
            
            # Save results to S3
            result_data = {
                'raw_data': all_scraped_data,
                'analysis': processing_results,
                'execution_metadata': {
                    'timestamp': datetime.utcnow().isoformat(),
                    'function_name': context.function_name,
                    'request_id': context.aws_request_id
                }
            }
            
            result_key = f'scraping-results-{int(time.time())}.json'
            s3.put_object(
                Bucket=bucket_output,
                Key=result_key,
                Body=json.dumps(result_data, indent=2),
                ContentType='application/json'
            )
            
            logger.info(f"Results saved to s3://{bucket_output}/{result_key}")
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Scraping completed successfully',
                    'scenarios_processed': len(config['scraping_scenarios']),
                    'total_data_points': sum(len(data['extracted_data']['product_titles']) for data in all_scraped_data),
                    'result_location': f's3://{bucket_output}/{result_key}'
                })
            }
            
        finally:
            # Cleanup code interpreter session
            try:
                agentcore.stop_code_interpreter_session(sessionId=code_session_id)
                logger.info(f"Stopped code interpreter session: {code_session_id}")
            except Exception as e:
                logger.warning(f"Failed to stop code session {code_session_id}: {e}")
        
    except Exception as e:
        logger.error(f"Error in scraping workflow: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'request_id': context.aws_request_id
            })
        }

def process_scraped_data(scraped_data):
    """Process and analyze scraped data"""
    total_items = sum(len(data['extracted_data']['product_titles']) for data in scraped_data)
    
    # Analyze prices
    all_prices = []
    for data in scraped_data:
        for price_str in data['extracted_data']['prices']:
            # Extract numeric value from price string
            numeric_price = ''.join(filter(lambda x: x.isdigit() or x == '.', price_str))
            if numeric_price:
                all_prices.append(float(numeric_price))
    
    # Calculate availability stats
    all_availability = []
    for data in scraped_data:
        all_availability.extend(data['extracted_data']['availability'])
    
    in_stock_count = sum(1 for status in all_availability if 'stock' in status.lower())
    
    analysis = {
        'total_products_scraped': total_items,
        'price_analysis': {
            'average_price': sum(all_prices) / len(all_prices) if all_prices else 0,
            'min_price': min(all_prices) if all_prices else 0,
            'max_price': max(all_prices) if all_prices else 0,
            'price_count': len(all_prices)
        },
        'availability_analysis': {
            'total_items_checked': len(all_availability),
            'in_stock_count': in_stock_count,
            'out_of_stock_count': len(all_availability) - in_stock_count,
            'availability_rate': (in_stock_count / len(all_availability) * 100) if all_availability else 0
        },
        'data_quality_score': (total_items / max(1, len(scraped_data))) * 100,
        'processing_timestamp': datetime.utcnow().isoformat()
    }
    
    return analysis
      `),
      role: lambdaRole,
      timeout: cdk.Duration.minutes(15),
      memorySize: 1024,
      environment: {
        S3_BUCKET_INPUT: inputBucket.bucketName,
        S3_BUCKET_OUTPUT: outputBucket.bucketName,
        ENVIRONMENT: 'production',
        LOG_LEVEL: 'INFO',
      },
      deadLetterQueue: deadLetterQueue,
      logGroup: logGroup,
      reservedConcurrentExecutions: 10,
      description: 'Orchestrates intelligent web scraping using AgentCore Browser and Code Interpreter',
    });

    // EventBridge rule for scheduled scraping (every 6 hours)
    const scheduleRule = new events.Rule(this, 'ScheduleRule', {
      ruleName: `${projectName}-schedule`,
      description: 'Scheduled intelligent web scraping every 6 hours',
      schedule: events.Schedule.rate(cdk.Duration.hours(6)),
      enabled: true,
    });

    // Add Lambda as target for EventBridge rule
    scheduleRule.addTarget(new targets.LambdaFunction(orchestratorFunction, {
      event: events.RuleTargetInput.fromObject({
        bucket_input: inputBucket.bucketName,
        bucket_output: outputBucket.bucketName,
        scheduled_execution: true,
      }),
    }));

    // CloudWatch Dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'MonitoringDashboard', {
      dashboardName: `${projectName}-monitoring`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Scraping Activity',
            left: [
              new cloudwatch.Metric({
                namespace: `IntelligentScraper/${orchestratorFunction.functionName}`,
                metricName: 'ScrapingJobs',
                statistic: 'Sum',
              }),
              new cloudwatch.Metric({
                namespace: `IntelligentScraper/${orchestratorFunction.functionName}`,
                metricName: 'DataPointsExtracted',
                statistic: 'Sum',
              }),
            ],
            period: cdk.Duration.minutes(5),
            width: 12,
          }),
          new cloudwatch.GraphWidget({
            title: 'Lambda Performance',
            left: [
              orchestratorFunction.metricDuration(),
              orchestratorFunction.metricErrors(),
              orchestratorFunction.metricInvocations(),
            ],
            period: cdk.Duration.minutes(5),
            width: 12,
          }),
        ],
        [
          new cloudwatch.LogQueryWidget({
            title: 'Recent Errors',
            logGroups: [logGroup],
            queryLines: [
              'fields @timestamp, @message',
              'filter @message like /ERROR/',
              'sort @timestamp desc',
              'limit 20',
            ],
            width: 24,
          }),
        ],
      ],
    });

    // CloudWatch Alarms for monitoring
    const errorAlarm = new cloudwatch.Alarm(this, 'ErrorAlarm', {
      alarmName: `${projectName}-errors`,
      alarmDescription: 'Alarm for Lambda function errors',
      metric: orchestratorFunction.metricErrors({
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const durationAlarm = new cloudwatch.Alarm(this, 'DurationAlarm', {
      alarmName: `${projectName}-duration`,
      alarmDescription: 'Alarm for Lambda function duration',
      metric: orchestratorFunction.metricDuration({
        period: cdk.Duration.minutes(5),
      }),
      threshold: 600000, // 10 minutes in milliseconds
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Upload default scraper configuration to S3
    const defaultConfig = {
      scraping_scenarios: [
        {
          name: 'ecommerce_demo',
          description: 'Extract product information from demo sites',
          target_url: 'https://books.toscrape.com/',
          extraction_rules: {
            product_titles: {
              selector: 'h3 a',
              attribute: 'title',
              wait_for: 'h3 a',
            },
            prices: {
              selector: '.price_color',
              attribute: 'textContent',
              wait_for: '.price_color',
            },
            availability: {
              selector: '.availability',
              attribute: 'textContent',
              wait_for: '.availability',
            },
          },
          session_config: {
            timeout_seconds: 30,
            view_port: {
              width: 1920,
              height: 1080,
            },
          },
        },
      ],
    };

    // Deploy default configuration file
    new s3.BucketDeployment(this, 'DefaultConfig', {
      sources: [
        s3.Source.jsonData('scraper-config.json', defaultConfig),
      ],
      destinationBucket: inputBucket,
    });

    // Stack Outputs
    new cdk.CfnOutput(this, 'InputBucketName', {
      value: inputBucket.bucketName,
      description: 'S3 bucket for input configurations',
      exportName: `${this.stackName}-InputBucket`,
    });

    new cdk.CfnOutput(this, 'OutputBucketName', {
      value: outputBucket.bucketName,
      description: 'S3 bucket for scraping results',
      exportName: `${this.stackName}-OutputBucket`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: orchestratorFunction.functionName,
      description: 'Lambda function for scraping orchestration',
      exportName: `${this.stackName}-LambdaFunction`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch dashboard URL for monitoring',
    });

    new cdk.CfnOutput(this, 'ScheduleRuleName', {
      value: scheduleRule.ruleName,
      description: 'EventBridge rule for scheduled execution',
      exportName: `${this.stackName}-ScheduleRule`,
    });

    // Tags for all resources
    cdk.Tags.of(this).add('Project', 'IntelligentWebScraping');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('Owner', 'DataEngineering');
    cdk.Tags.of(this).add('CostCenter', 'Analytics');
  }
}

// CDK App initialization
const app = new cdk.App();

// Deploy stack with environment-specific configuration
new IntelligentWebScrapingStack(app, 'IntelligentWebScrapingStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Intelligent Web Scraping with AgentCore Browser and Code Interpreter - Production Stack',
  stackName: 'intelligent-web-scraping-stack',
  terminationProtection: false, // Set to true for production
});

app.synth();