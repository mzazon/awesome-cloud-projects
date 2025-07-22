#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as path from 'path';

/**
 * Properties for the PersonalizeRecommendationStack
 */
interface PersonalizeRecommendationStackProps extends cdk.StackProps {
  /**
   * Environment prefix for resource naming
   * @default 'personalize-rec'
   */
  readonly environmentPrefix?: string;

  /**
   * Enable automated model retraining
   * @default true
   */
  readonly enableAutomatedRetraining?: boolean;

  /**
   * Retraining schedule expression
   * @default 'rate(7 days)'
   */
  readonly retrainingSchedule?: string;

  /**
   * Lambda function timeout in seconds
   * @default 30
   */
  readonly lambdaTimeout?: number;

  /**
   * Lambda memory size in MB
   * @default 512
   */
  readonly lambdaMemorySize?: number;
}

/**
 * CDK Stack for building comprehensive recommendation systems with Amazon Personalize
 * 
 * This stack creates a complete recommendation system including:
 * - S3 data lake for training data and metadata
 * - IAM roles with least privilege access
 * - Lambda functions for real-time recommendations with A/B testing
 * - EventBridge for automated model retraining
 * - API Gateway for RESTful recommendation endpoints
 * - CloudWatch monitoring and custom metrics
 */
export class PersonalizeRecommendationStack extends cdk.Stack {
  // Core infrastructure resources
  public readonly dataBucket: s3.Bucket;
  public readonly personalizeServiceRole: iam.Role;
  public readonly lambdaExecutionRole: iam.Role;

  // Lambda functions
  public readonly recommendationFunction: lambda.Function;
  public readonly retrainingFunction: lambda.Function;

  // API and automation
  public readonly recommendationApi: apigateway.RestApi;
  public readonly retrainingRule: events.Rule;

  // Monitoring
  public readonly abTestDashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: PersonalizeRecommendationStackProps = {}) {
    super(scope, id, props);

    const environmentPrefix = props.environmentPrefix || 'personalize-rec';
    const randomSuffix = Math.random().toString(36).substring(2, 10);

    // ========================================
    // S3 DATA LAKE INFRASTRUCTURE
    // ========================================

    // Create S3 bucket for training data, metadata, and batch outputs
    this.dataBucket = new s3.Bucket(this, 'PersonalizeDataBucket', {
      bucketName: `${environmentPrefix}-data-${randomSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'TrainingDataLifecycle',
          prefix: 'training-data/',
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
        {
          id: 'BatchOutputCleanup',
          prefix: 'batch-output/',
          expiration: cdk.Duration.days(30),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Add CORS configuration for web applications
    this.dataBucket.addCorsRule({
      allowedMethods: [s3.HttpMethods.GET, s3.HttpMethods.PUT, s3.HttpMethods.POST],
      allowedOrigins: ['*'],
      allowedHeaders: ['*'],
      maxAge: 3000,
    });

    // ========================================
    // IAM ROLES AND POLICIES
    // ========================================

    // Create service role for Amazon Personalize
    this.personalizeServiceRole = new iam.Role(this, 'PersonalizeServiceRole', {
      roleName: `PersonalizeServiceRole-${randomSuffix}`,
      assumedBy: new iam.ServicePrincipal('personalize.amazonaws.com'),
      description: 'Service role for Amazon Personalize to access S3 data and perform ML operations',
    });

    // Add comprehensive S3 access policy for Personalize
    this.personalizeServiceRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          's3:GetObject',
          's3:ListBucket',
          's3:PutObject',
          's3:DeleteObject',
        ],
        resources: [
          this.dataBucket.bucketArn,
          `${this.dataBucket.bucketArn}/*`,
        ],
      })
    );

    // Create Lambda execution role with Personalize and CloudWatch permissions
    this.lambdaExecutionRole = new iam.Role(this, 'LambdaRecommendationRole', {
      roleName: `LambdaRecommendationRole-${randomSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for recommendation Lambda functions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Add Personalize runtime permissions
    this.lambdaExecutionRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'personalize:GetRecommendations',
          'personalize:GetPersonalizedRanking',
          'personalize:DescribeCampaign',
          'personalize:DescribeFilter',
          'personalize:CreateSolutionVersion',
          'personalize:DescribeSolution',
          'personalize:DescribeSolutionVersion',
          'personalize:ListSolutions',
          'personalize:ListSolutionVersions',
          'personalize:CreateBatchInferenceJob',
          'personalize:DescribeBatchInferenceJob',
        ],
        resources: ['*'], // Personalize doesn't support resource-level permissions
      })
    );

    // Add CloudWatch metrics permissions for A/B testing
    this.lambdaExecutionRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'cloudwatch:PutMetricData',
          'cloudwatch:GetMetricStatistics',
          'cloudwatch:ListMetrics',
        ],
        resources: ['*'],
      })
    );

    // ========================================
    // LAMBDA FUNCTIONS
    // ========================================

    // Create comprehensive recommendation function with A/B testing
    this.recommendationFunction = new lambda.Function(this, 'RecommendationFunction', {
      functionName: `${environmentPrefix}-recommendation-api-${randomSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import logging
from datetime import datetime
import hashlib

logger = logging.getLogger()
logger.setLevel(logging.INFO)

personalize_runtime = boto3.client('personalize-runtime')
cloudwatch = boto3.client('cloudwatch')

# A/B Testing Configuration
AB_TEST_CONFIG = {
    'user_personalization': 0.4,  # 40% traffic
    'similar_items': 0.2,         # 20% traffic
    'trending_now': 0.2,          # 20% traffic
    'popularity': 0.2             # 20% traffic
}

def get_recommendation_strategy(user_id):
    """Determine recommendation strategy based on consistent hashing for A/B testing"""
    if not user_id:
        return 'popularity'  # Default for anonymous users
    
    # Use consistent hashing for stable user assignment
    hash_value = int(hashlib.md5(user_id.encode()).hexdigest(), 16) % 100
    cumulative_prob = 0
    
    for strategy, probability in AB_TEST_CONFIG.items():
        cumulative_prob += probability * 100
        if hash_value < cumulative_prob:
            return strategy
    
    return 'user_personalization'  # Default fallback

def get_recommendations(campaign_arn, user_id, num_results=10, filter_arn=None, filter_values=None):
    """Get recommendations from Personalize campaign with error handling"""
    try:
        params = {
            'campaignArn': campaign_arn,
            'userId': user_id,
            'numResults': num_results
        }
        
        if filter_arn and filter_values:
            params['filterArn'] = filter_arn
            params['filterValues'] = filter_values
        
        response = personalize_runtime.get_recommendations(**params)
        return response
        
    except Exception as e:
        logger.error(f"Error getting recommendations: {str(e)}")
        raise

def get_similar_items(campaign_arn, item_id, num_results=10):
    """Get similar items recommendations"""
    try:
        response = personalize_runtime.get_recommendations(
            campaignArn=campaign_arn,
            itemId=item_id,
            numResults=num_results
        )
        return response
        
    except Exception as e:
        logger.error(f"Error getting similar items: {str(e)}")
        raise

def send_ab_test_metrics(strategy, user_id, response_time, num_results, error_occurred=False):
    """Send comprehensive A/B testing metrics to CloudWatch"""
    try:
        metrics = [
            {
                'MetricName': 'RecommendationRequests',
                'Dimensions': [
                    {'Name': 'Strategy', 'Value': strategy},
                    {'Name': 'Environment', 'Value': os.environ.get('ENVIRONMENT', 'production')}
                ],
                'Value': 1,
                'Unit': 'Count'
            },
            {
                'MetricName': 'ResponseTime',
                'Dimensions': [
                    {'Name': 'Strategy', 'Value': strategy}
                ],
                'Value': response_time,
                'Unit': 'Milliseconds'
            },
            {
                'MetricName': 'NumResults',
                'Dimensions': [
                    {'Name': 'Strategy', 'Value': strategy}
                ],
                'Value': num_results,
                'Unit': 'Count'
            }
        ]
        
        if error_occurred:
            metrics.append({
                'MetricName': 'RecommendationErrors',
                'Dimensions': [
                    {'Name': 'Strategy', 'Value': strategy}
                ],
                'Value': 1,
                'Unit': 'Count'
            })
        
        cloudwatch.put_metric_data(
            Namespace='PersonalizeABTest',
            MetricData=metrics
        )
        
    except Exception as e:
        logger.error(f"Error sending metrics: {str(e)}")

def lambda_handler(event, context):
    """Main Lambda handler for recommendation API with comprehensive error handling"""
    start_time = datetime.now()
    strategy = 'unknown'
    error_occurred = False
    
    try:
        # Extract parameters from API Gateway event
        path_params = event.get('pathParameters') or {}
        query_params = event.get('queryStringParameters') or {}
        
        user_id = path_params.get('userId')
        item_id = path_params.get('itemId')
        recommendation_type = path_params.get('type', 'personalized')
        
        num_results = min(int(query_params.get('numResults', 10)), 50)  # Cap at 50
        category = query_params.get('category')
        min_price = query_params.get('minPrice')
        max_price = query_params.get('maxPrice')
        
        logger.info(f"Processing recommendation request: userId={user_id}, type={recommendation_type}")
        
        # Determine strategy based on A/B testing
        if recommendation_type == 'personalized' and user_id:
            strategy = get_recommendation_strategy(user_id)
        else:
            strategy = recommendation_type
        
        # Map strategies to campaign ARNs from environment variables
        campaign_mapping = {
            'user_personalization': os.environ.get('USER_PERSONALIZATION_CAMPAIGN_ARN'),
            'similar_items': os.environ.get('SIMILAR_ITEMS_CAMPAIGN_ARN'),
            'trending_now': os.environ.get('TRENDING_NOW_CAMPAIGN_ARN'),
            'popularity': os.environ.get('POPULARITY_CAMPAIGN_ARN')
        }
        
        campaign_arn = campaign_mapping.get(strategy)
        if not campaign_arn:
            raise ValueError(f"No campaign ARN configured for strategy: {strategy}")
        
        # Handle different recommendation types
        if strategy == 'similar_items' and item_id:
            response = get_similar_items(campaign_arn, item_id, num_results)
        elif user_id:
            # Apply filters if specified
            filter_arn = None
            filter_values = {}
            
            if category:
                filter_arn = os.environ.get('CATEGORY_FILTER_ARN')
                filter_values['$CATEGORY'] = f'"{category}"'
            elif min_price and max_price:
                filter_arn = os.environ.get('PRICE_FILTER_ARN')
                filter_values['$MIN_PRICE'] = min_price
                filter_values['$MAX_PRICE'] = max_price
            
            response = get_recommendations(
                campaign_arn, user_id, num_results, filter_arn, filter_values
            )
        else:
            raise ValueError("Either userId or itemId must be provided")
        
        # Calculate response time
        response_time = (datetime.now() - start_time).total_seconds() * 1000
        
        # Format recommendations
        recommendations = []
        for item in response.get('itemList', []):
            recommendations.append({
                'itemId': item['itemId'],
                'score': round(item.get('score', 0), 4)
            })
        
        # Send success metrics
        send_ab_test_metrics(strategy, user_id, response_time, len(recommendations))
        
        logger.info(f"Successfully generated {len(recommendations)} recommendations using {strategy}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
                'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
            },
            'body': json.dumps({
                'userId': user_id,
                'itemId': item_id,
                'strategy': strategy,
                'recommendations': recommendations,
                'responseTime': round(response_time, 2),
                'requestId': context.aws_request_id,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        error_occurred = True
        response_time = (datetime.now() - start_time).total_seconds() * 1000
        
        # Send error metrics
        send_ab_test_metrics(strategy, user_id or 'unknown', response_time, 0, error_occurred=True)
        
        logger.error(f"Error in recommendation handler: {str(e)}")
        
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'message': str(e),
                'requestId': context.aws_request_id,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
      `),
      handler: 'index.lambda_handler',
      role: this.lambdaExecutionRole,
      timeout: cdk.Duration.seconds(props.lambdaTimeout || 30),
      memorySize: props.lambdaMemorySize || 512,
      description: 'Comprehensive recommendation API with A/B testing and monitoring',
      environment: {
        ENVIRONMENT: this.stackName,
        // Campaign ARNs will be set after Personalize resources are created manually
        // These would typically be set through parameter store or systems manager
        USER_PERSONALIZATION_CAMPAIGN_ARN: 'SET_AFTER_PERSONALIZE_SETUP',
        SIMILAR_ITEMS_CAMPAIGN_ARN: 'SET_AFTER_PERSONALIZE_SETUP',
        TRENDING_NOW_CAMPAIGN_ARN: 'SET_AFTER_PERSONALIZE_SETUP',
        POPULARITY_CAMPAIGN_ARN: 'SET_AFTER_PERSONALIZE_SETUP',
        CATEGORY_FILTER_ARN: 'SET_AFTER_PERSONALIZE_SETUP',
        PRICE_FILTER_ARN: 'SET_AFTER_PERSONALIZE_SETUP',
        EXCLUDE_PURCHASED_FILTER_ARN: 'SET_AFTER_PERSONALIZE_SETUP',
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Create automated retraining function
    this.retrainingFunction = new lambda.Function(this, 'RetrainingFunction', {
      functionName: `${environmentPrefix}-retraining-${randomSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

personalize = boto3.client('personalize')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """Automated retraining function for Personalize models"""
    
    # Solution ARNs from environment variables
    solutions = [
        {
            'arn': os.environ.get('USER_PERSONALIZATION_ARN'),
            'name': 'User-Personalization'
        },
        {
            'arn': os.environ.get('SIMILAR_ITEMS_ARN'),
            'name': 'Similar-Items'
        },
        {
            'arn': os.environ.get('TRENDING_NOW_ARN'),
            'name': 'Trending-Now'
        },
        {
            'arn': os.environ.get('POPULARITY_ARN'),
            'name': 'Popularity-Count'
        }
    ]
    
    retraining_results = []
    successful_retraining = 0
    
    for solution in solutions:
        solution_arn = solution['arn']
        solution_name = solution['name']
        
        if not solution_arn or solution_arn == 'SET_AFTER_PERSONALIZE_SETUP':
            logger.warning(f"Solution ARN not configured for {solution_name}")
            continue
            
        try:
            # Check if there's already an active solution version being created
            response = personalize.list_solution_versions(
                solutionArn=solution_arn,
                maxResults=1
            )
            
            latest_version = response.get('solutionVersions', [])
            if latest_version:
                latest_status = latest_version[0]['status']
                if latest_status in ['CREATE_PENDING', 'CREATE_IN_PROGRESS']:
                    logger.info(f"Skipping {solution_name} - already training")
                    retraining_results.append({
                        'solutionArn': solution_arn,
                        'solutionName': solution_name,
                        'status': 'SKIPPED_ALREADY_TRAINING'
                    })
                    continue
            
            # Create new solution version for incremental retraining
            create_response = personalize.create_solution_version(
                solutionArn=solution_arn,
                trainingMode='UPDATE'  # Incremental training
            )
            
            retraining_results.append({
                'solutionArn': solution_arn,
                'solutionName': solution_name,
                'solutionVersionArn': create_response['solutionVersionArn'],
                'status': 'INITIATED'
            })
            
            successful_retraining += 1
            logger.info(f"Successfully initiated retraining for {solution_name}")
            
        except Exception as e:
            logger.error(f"Error retraining {solution_name}: {str(e)}")
            retraining_results.append({
                'solutionArn': solution_arn,
                'solutionName': solution_name,
                'status': 'FAILED',
                'error': str(e)
            })
    
    # Send metrics to CloudWatch
    try:
        cloudwatch.put_metric_data(
            Namespace='PersonalizeRetraining',
            MetricData=[
                {
                    'MetricName': 'RetrainingJobsInitiated',
                    'Value': successful_retraining,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                },
                {
                    'MetricName': 'RetrainingJobsTotal',
                    'Value': len([r for r in retraining_results if r.get('status') != 'SKIPPED_ALREADY_TRAINING']),
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
    except Exception as e:
        logger.error(f"Error sending CloudWatch metrics: {str(e)}")
    
    logger.info(f"Retraining automation completed. Initiated: {successful_retraining}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Automated retraining process completed',
            'results': retraining_results,
            'successfulRetraining': successful_retraining,
            'timestamp': datetime.utcnow().isoformat()
        })
    }
      `),
      handler: 'index.lambda_handler',
      role: this.lambdaExecutionRole,
      timeout: cdk.Duration.minutes(5),
      description: 'Automated model retraining for Personalize solutions',
      environment: {
        // Solution ARNs will be set after Personalize resources are created
        USER_PERSONALIZATION_ARN: 'SET_AFTER_PERSONALIZE_SETUP',
        SIMILAR_ITEMS_ARN: 'SET_AFTER_PERSONALIZE_SETUP',
        TRENDING_NOW_ARN: 'SET_AFTER_PERSONALIZE_SETUP',
        POPULARITY_ARN: 'SET_AFTER_PERSONALIZE_SETUP',
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // ========================================
    // API GATEWAY CONFIGURATION
    // ========================================

    // Create REST API for recommendations
    this.recommendationApi = new apigateway.RestApi(this, 'RecommendationApi', {
      restApiName: `${environmentPrefix}-recommendation-api-${randomSuffix}`,
      description: 'RESTful API for Amazon Personalize recommendations with A/B testing',
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: [
          'Content-Type',
          'X-Amz-Date',
          'Authorization',
          'X-Api-Key',
          'X-Amz-Security-Token',
        ],
      },
      deployOptions: {
        stageName: 'prod',
        throttle: {
          rateLimit: 100,
          burstLimit: 200,
        },
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
        metricsEnabled: true,
      },
    });

    // Create Lambda integration
    const recommendationIntegration = new apigateway.LambdaIntegration(
      this.recommendationFunction,
      {
        requestTemplates: {
          'application/json': '{ "statusCode": "200" }',
        },
        proxy: true,
      }
    );

    // Add resource paths for different recommendation types
    // GET /recommendations/{userId} - User personalized recommendations
    const recommendationsResource = this.recommendationApi.root.addResource('recommendations');
    const userResource = recommendationsResource.addResource('{userId}');
    userResource.addMethod('GET', recommendationIntegration);

    // GET /recommendations/{userId}/{type} - Specific recommendation type
    const typeResource = userResource.addResource('{type}');
    typeResource.addMethod('GET', recommendationIntegration);

    // GET /similar/{itemId} - Similar items recommendations
    const similarResource = this.recommendationApi.root.addResource('similar');
    const itemResource = similarResource.addResource('{itemId}');
    itemResource.addMethod('GET', recommendationIntegration);

    // Add usage plan for API throttling and monitoring
    const usagePlan = this.recommendationApi.addUsagePlan('RecommendationUsagePlan', {
      name: `${environmentPrefix}-usage-plan`,
      throttle: {
        rateLimit: 100,
        burstLimit: 200,
      },
      quota: {
        limit: 10000,
        period: apigateway.Period.DAY,
      },
    });

    usagePlan.addApiStage({
      stage: this.recommendationApi.deploymentStage,
    });

    // ========================================
    // EVENTBRIDGE AUTOMATION
    // ========================================

    if (props.enableAutomatedRetraining !== false) {
      // Create EventBridge rule for automated retraining
      this.retrainingRule = new events.Rule(this, 'RetrainingRule', {
        ruleName: `${environmentPrefix}-retraining-${randomSuffix}`,
        description: 'Trigger automated Personalize model retraining',
        schedule: events.Schedule.expression(props.retrainingSchedule || 'rate(7 days)'),
      });

      // Add Lambda target to the rule
      this.retrainingRule.addTarget(new targets.LambdaFunction(this.retrainingFunction));
    }

    // ========================================
    // CLOUDWATCH MONITORING
    // ========================================

    // Create comprehensive dashboard for A/B testing and system monitoring
    this.abTestDashboard = new cloudwatch.Dashboard(this, 'ABTestDashboard', {
      dashboardName: `${environmentPrefix}-ab-test-dashboard-${randomSuffix}`,
    });

    // Add widgets for recommendation metrics
    this.abTestDashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Recommendation Requests by Strategy',
        left: [
          new cloudwatch.Metric({
            namespace: 'PersonalizeABTest',
            metricName: 'RecommendationRequests',
            dimensionsMap: { Strategy: 'user_personalization' },
            statistic: 'Sum',
          }),
          new cloudwatch.Metric({
            namespace: 'PersonalizeABTest',
            metricName: 'RecommendationRequests',
            dimensionsMap: { Strategy: 'similar_items' },
            statistic: 'Sum',
          }),
          new cloudwatch.Metric({
            namespace: 'PersonalizeABTest',
            metricName: 'RecommendationRequests',
            dimensionsMap: { Strategy: 'trending_now' },
            statistic: 'Sum',
          }),
          new cloudwatch.Metric({
            namespace: 'PersonalizeABTest',
            metricName: 'RecommendationRequests',
            dimensionsMap: { Strategy: 'popularity' },
            statistic: 'Sum',
          }),
        ],
        width: 12,
      }),
      new cloudwatch.GraphWidget({
        title: 'Response Time by Strategy',
        left: [
          new cloudwatch.Metric({
            namespace: 'PersonalizeABTest',
            metricName: 'ResponseTime',
            dimensionsMap: { Strategy: 'user_personalization' },
            statistic: 'Average',
          }),
          new cloudwatch.Metric({
            namespace: 'PersonalizeABTest',
            metricName: 'ResponseTime',
            dimensionsMap: { Strategy: 'similar_items' },
            statistic: 'Average',
          }),
          new cloudwatch.Metric({
            namespace: 'PersonalizeABTest',
            metricName: 'ResponseTime',
            dimensionsMap: { Strategy: 'trending_now' },
            statistic: 'Average',
          }),
          new cloudwatch.Metric({
            namespace: 'PersonalizeABTest',
            metricName: 'ResponseTime',
            dimensionsMap: { Strategy: 'popularity' },
            statistic: 'Average',
          }),
        ],
        width: 12,
      })
    );

    // Add Lambda monitoring widgets
    this.abTestDashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Lambda Function Performance',
        left: [
          this.recommendationFunction.metricDuration(),
          this.recommendationFunction.metricErrors(),
          this.recommendationFunction.metricInvocations(),
        ],
        width: 12,
      }),
      new cloudwatch.GraphWidget({
        title: 'API Gateway Metrics',
        left: [
          this.recommendationApi.metricCount(),
          this.recommendationApi.metricLatency(),
          this.recommendationApi.metricClientError(),
          this.recommendationApi.metricServerError(),
        ],
        width: 12,
      })
    );

    // ========================================
    // STACK OUTPUTS
    // ========================================

    new cdk.CfnOutput(this, 'DataBucketName', {
      value: this.dataBucket.bucketName,
      description: 'S3 bucket for training data and metadata',
      exportName: `${this.stackName}-DataBucket`,
    });

    new cdk.CfnOutput(this, 'PersonalizeServiceRoleArn', {
      value: this.personalizeServiceRole.roleArn,
      description: 'IAM role ARN for Amazon Personalize service',
      exportName: `${this.stackName}-PersonalizeRole`,
    });

    new cdk.CfnOutput(this, 'RecommendationApiUrl', {
      value: this.recommendationApi.url,
      description: 'API Gateway endpoint for recommendations',
      exportName: `${this.stackName}-ApiUrl`,
    });

    new cdk.CfnOutput(this, 'RecommendationFunctionArn', {
      value: this.recommendationFunction.functionArn,
      description: 'Lambda function ARN for recommendations',
      exportName: `${this.stackName}-RecommendationFunction`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.abTestDashboard.dashboardName}`,
      description: 'CloudWatch dashboard URL for monitoring',
    });

    // Output sample API calls for testing
    new cdk.CfnOutput(this, 'SampleApiCalls', {
      value: JSON.stringify({
        userRecommendations: `${this.recommendationApi.url}recommendations/user_0001?numResults=10`,
        categoryFiltered: `${this.recommendationApi.url}recommendations/user_0001?category=electronics&numResults=10`,
        priceFiltered: `${this.recommendationApi.url}recommendations/user_0001?minPrice=50&maxPrice=200&numResults=10`,
        similarItems: `${this.recommendationApi.url}similar/item_0001?numResults=10`,
        trendingNow: `${this.recommendationApi.url}recommendations/user_0001/trending_now?numResults=10`,
      }),
      description: 'Sample API calls for testing different recommendation types',
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'PersonalizeRecommendationSystem');
    cdk.Tags.of(this).add('Environment', environmentPrefix);
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Create the recommendation system stack
new PersonalizeRecommendationStack(app, 'PersonalizeRecommendationStack', {
  description: 'Comprehensive recommendation system with Amazon Personalize, A/B testing, and automated retraining',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Stack configuration options
  environmentPrefix: app.node.tryGetContext('environmentPrefix') || 'personalize-rec',
  enableAutomatedRetraining: app.node.tryGetContext('enableAutomatedRetraining') !== false,
  retrainingSchedule: app.node.tryGetContext('retrainingSchedule') || 'rate(7 days)',
  lambdaTimeout: app.node.tryGetContext('lambdaTimeout') || 30,
  lambdaMemorySize: app.node.tryGetContext('lambdaMemorySize') || 512,
  
  // Add stack-level tags
  tags: {
    'CostCenter': 'MachineLearning',
    'Owner': 'DataScience',
    'Application': 'RecommendationEngine',
  },
});

// Synthesize the app
app.synth();