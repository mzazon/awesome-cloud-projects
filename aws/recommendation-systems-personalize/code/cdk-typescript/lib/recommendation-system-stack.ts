import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import { Construct } from 'constructs';

export interface RecommendationSystemStackProps extends cdk.StackProps {
  config: {
    region: string;
    account?: string;
    solutionName: string;
    campaignName: string;
    minProvisionedTPS: number;
    enableDetailedMonitoring: boolean;
    enableXRayTracing: boolean;
    lambdaMemorySize: number;
    lambdaTimeout: number;
    apiStageName: string;
    corsOrigins: string;
    enableApiCaching: boolean;
    enableThrottling: boolean;
    burstLimit: number;
    rateLimit: number;
  };
}

export class RecommendationSystemStack extends cdk.Stack {
  public readonly s3Bucket: s3.Bucket;
  public readonly personalizeRole: iam.Role;
  public readonly lambdaFunction: lambda.Function;
  public readonly api: apigateway.RestApi;
  public readonly apiUrl: string;

  constructor(scope: Construct, id: string, props: RecommendationSystemStackProps) {
    super(scope, id, props);

    const { config } = props;

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8);

    // Create S3 bucket for training data
    this.s3Bucket = new s3.Bucket(this, 'PersonalizeDataBucket', {
      bucketName: `personalize-demo-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create IAM role for Amazon Personalize
    this.personalizeRole = new iam.Role(this, 'PersonalizeExecutionRole', {
      roleName: `PersonalizeExecutionRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('personalize.amazonaws.com'),
      description: 'IAM role for Amazon Personalize to access S3 training data',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonPersonalizeFullAccess'),
      ],
      inlinePolicies: {
        S3Access: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:ListBucket',
              ],
              resources: [
                this.s3Bucket.bucketArn,
                this.s3Bucket.arnForObjects('*'),
              ],
            }),
          ],
        }),
      },
    });

    // Upload sample training data to S3
    new s3deploy.BucketDeployment(this, 'DeployTrainingData', {
      sources: [s3deploy.Source.data('training-data/interactions.csv', this.generateSampleData())],
      destinationBucket: this.s3Bucket,
      destinationKeyPrefix: 'training-data/',
    });

    // Create Lambda execution role
    const lambdaRole = new iam.Role(this, 'LambdaPersonalizeRole', {
      roleName: `LambdaPersonalizeRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for Lambda to access Amazon Personalize',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        PersonalizeAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'personalize:GetRecommendations',
                'personalize:DescribeCampaign',
              ],
              resources: [
                `arn:aws:personalize:${config.region}:${this.account}:campaign/*`,
              ],
            }),
          ],
        }),
      },
    });

    // Create Lambda function for recommendation API
    this.lambdaFunction = new lambda.Function(this, 'RecommendationHandler', {
      functionName: `recommendation-api-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'recommendation-handler.lambda_handler',
      code: lambda.Code.fromInline(this.getLambdaCode()),
      role: lambdaRole,
      timeout: cdk.Duration.seconds(config.lambdaTimeout),
      memorySize: config.lambdaMemorySize,
      description: 'Lambda function to handle recommendation API requests',
      environment: {
        CAMPAIGN_ARN: '', // Will be updated after campaign creation
        REGION: config.region,
        LOG_LEVEL: 'INFO',
      },
      tracing: config.enableXRayTracing ? lambda.Tracing.ACTIVE : lambda.Tracing.DISABLED,
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Create API Gateway REST API
    this.api = new apigateway.RestApi(this, 'RecommendationAPI', {
      restApiName: `recommendation-api-${uniqueSuffix}`,
      description: 'Real-time recommendation API powered by Amazon Personalize',
      endpointConfiguration: {
        types: [apigateway.EndpointType.REGIONAL],
      },
      deployOptions: {
        stageName: config.apiStageName,
        metricsEnabled: config.enableDetailedMonitoring,
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
        tracingEnabled: config.enableXRayTracing,
        cachingEnabled: config.enableApiCaching,
        cacheClusterEnabled: config.enableApiCaching,
        cacheClusterSize: config.enableApiCaching ? '0.5' : undefined,
        throttlingBurstLimit: config.enableThrottling ? config.burstLimit : undefined,
        throttlingRateLimit: config.enableThrottling ? config.rateLimit : undefined,
      },
      defaultCorsPreflightOptions: {
        allowOrigins: config.corsOrigins === '*' ? apigateway.Cors.ALL_ORIGINS : [config.corsOrigins],
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: [
          'Content-Type',
          'X-Amz-Date',
          'Authorization',
          'X-Api-Key',
          'X-Amz-Security-Token',
          'X-Amz-User-Agent',
        ],
      },
      cloudWatchRole: true,
    });

    // Create API Gateway resources and methods
    const recommendationsResource = this.api.root.addResource('recommendations');
    const userResource = recommendationsResource.addResource('{userId}');

    // Create Lambda integration
    const lambdaIntegration = new apigateway.LambdaIntegration(this.lambdaFunction, {
      requestTemplates: {
        'application/json': '{"statusCode": "200"}',
      },
      proxy: true,
    });

    // Add GET method to user resource
    userResource.addMethod('GET', lambdaIntegration, {
      operationName: 'GetRecommendations',
      requestParameters: {
        'method.request.path.userId': true,
        'method.request.querystring.numResults': false,
      },
      requestValidatorOptions: {
        requestValidatorName: 'RecommendationRequestValidator',
        validateRequestParameters: true,
      },
      methodResponses: [
        {
          statusCode: '200',
          responseModels: {
            'application/json': apigateway.Model.EMPTY_MODEL,
          },
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
            'method.response.header.Access-Control-Allow-Headers': true,
            'method.response.header.Access-Control-Allow-Methods': true,
          },
        },
        {
          statusCode: '400',
          responseModels: {
            'application/json': apigateway.Model.ERROR_MODEL,
          },
        },
        {
          statusCode: '500',
          responseModels: {
            'application/json': apigateway.Model.ERROR_MODEL,
          },
        },
      ],
    });

    // Create CloudWatch alarms for monitoring
    if (config.enableDetailedMonitoring) {
      this.createCloudWatchAlarms(uniqueSuffix);
    }

    // Store API URL for outputs
    this.apiUrl = this.api.url;

    // Outputs
    new cdk.CfnOutput(this, 'S3BucketName', {
      value: this.s3Bucket.bucketName,
      description: 'S3 bucket name for training data',
      exportName: `${this.stackName}-S3BucketName`,
    });

    new cdk.CfnOutput(this, 'PersonalizeRoleArn', {
      value: this.personalizeRole.roleArn,
      description: 'IAM role ARN for Amazon Personalize',
      exportName: `${this.stackName}-PersonalizeRoleArn`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: this.lambdaFunction.functionName,
      description: 'Lambda function name for recommendation API',
      exportName: `${this.stackName}-LambdaFunctionName`,
    });

    new cdk.CfnOutput(this, 'ApiGatewayUrl', {
      value: this.apiUrl,
      description: 'API Gateway URL for recommendation API',
      exportName: `${this.stackName}-ApiGatewayUrl`,
    });

    new cdk.CfnOutput(this, 'TestEndpoint', {
      value: `${this.apiUrl}recommendations/{userId}`,
      description: 'Test endpoint for recommendations (replace {userId} with actual user ID)',
      exportName: `${this.stackName}-TestEndpoint`,
    });

    new cdk.CfnOutput(this, 'DataBucketPath', {
      value: `s3://${this.s3Bucket.bucketName}/training-data/interactions.csv`,
      description: 'S3 path to training data file',
      exportName: `${this.stackName}-DataBucketPath`,
    });

    new cdk.CfnOutput(this, 'NextSteps', {
      value: [
        '1. Create Personalize Dataset Group using the AWS Console or CLI',
        '2. Create Schema and Dataset using the provided S3 data',
        '3. Create Solution and train the model',
        '4. Create Campaign with the trained model',
        '5. Update Lambda environment variable CAMPAIGN_ARN',
        '6. Test the API endpoint',
      ].join(' | '),
      description: 'Next steps to complete the setup',
    });
  }

  private createCloudWatchAlarms(uniqueSuffix: string): void {
    // API Gateway 4XX errors alarm
    new cloudwatch.Alarm(this, 'ApiGateway4xxErrorsAlarm', {
      alarmName: `RecommendationAPI-4xxErrors-${uniqueSuffix}`,
      alarmDescription: 'Monitor 4xx errors in recommendation API',
      metric: this.api.metricClientError({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      }),
      threshold: 5,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // API Gateway 5XX errors alarm
    new cloudwatch.Alarm(this, 'ApiGateway5xxErrorsAlarm', {
      alarmName: `RecommendationAPI-5xxErrors-${uniqueSuffix}`,
      alarmDescription: 'Monitor 5xx errors in recommendation API',
      metric: this.api.metricServerError({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      }),
      threshold: 1,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Lambda errors alarm
    new cloudwatch.Alarm(this, 'LambdaErrorsAlarm', {
      alarmName: `RecommendationLambda-Errors-${uniqueSuffix}`,
      alarmDescription: 'Monitor Lambda function errors',
      metric: this.lambdaFunction.metricErrors({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      }),
      threshold: 1,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Lambda duration alarm
    new cloudwatch.Alarm(this, 'LambdaDurationAlarm', {
      alarmName: `RecommendationLambda-Duration-${uniqueSuffix}`,
      alarmDescription: 'Monitor Lambda function duration',
      metric: this.lambdaFunction.metricDuration({
        period: cdk.Duration.minutes(5),
        statistic: 'Average',
      }),
      threshold: 10000, // 10 seconds
      evaluationPeriods: 3,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
  }

  private generateSampleData(): string {
    // Generate sample interaction data in CSV format
    const interactions = [
      'USER_ID,ITEM_ID,TIMESTAMP,EVENT_TYPE',
      'user1,item101,1640995200,purchase',
      'user1,item102,1640995260,view',
      'user1,item103,1640995320,purchase',
      'user2,item101,1640995380,view',
      'user2,item104,1640995440,purchase',
      'user2,item105,1640995500,view',
      'user3,item102,1640995560,purchase',
      'user3,item103,1640995620,view',
      'user3,item106,1640995680,purchase',
      'user4,item101,1640995740,view',
      'user4,item107,1640995800,purchase',
      'user5,item108,1640995860,view',
      'user5,item109,1640995920,purchase',
      'user6,item110,1640995980,view',
      'user6,item111,1641000040,purchase',
      'user7,item101,1641000100,view',
      'user7,item112,1641000160,purchase',
      'user8,item103,1641000220,view',
      'user8,item113,1641000280,purchase',
      'user9,item104,1641000340,view',
      'user9,item114,1641000400,purchase',
      'user10,item105,1641000460,view',
      'user10,item115,1641000520,purchase',
    ];

    return interactions.join('\n');
  }

  private getLambdaCode(): string {
    return `
import json
import boto3
import os
import logging
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize Personalize client
personalize = boto3.client('personalize-runtime', region_name=os.environ.get('REGION'))

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for recommendation API requests.
    
    Args:
        event: API Gateway event containing request data
        context: Lambda context object
        
    Returns:
        API Gateway response with recommendations or error
    """
    try:
        # Log the incoming request
        logger.info(f"Received request: {json.dumps(event, default=str)}")
        
        # Extract user ID from path parameters
        path_params = event.get('pathParameters', {})
        if not path_params or 'userId' not in path_params:
            logger.error("Missing userId in path parameters")
            return create_error_response(400, "Missing userId in path parameters")
        
        user_id = path_params['userId']
        
        # Validate user ID
        if not user_id or user_id.strip() == '':
            logger.error("Invalid or empty userId")
            return create_error_response(400, "Invalid or empty userId")
        
        # Get query parameters
        query_params = event.get('queryStringParameters') or {}
        num_results = int(query_params.get('numResults', 10))
        
        # Validate numResults parameter
        if num_results < 1 or num_results > 100:
            logger.error(f"Invalid numResults: {num_results}")
            return create_error_response(400, "numResults must be between 1 and 100")
        
        # Get campaign ARN from environment
        campaign_arn = os.environ.get('CAMPAIGN_ARN')
        if not campaign_arn:
            logger.error("CAMPAIGN_ARN environment variable not set")
            return create_error_response(500, "Campaign not configured")
        
        # Get recommendations from Personalize
        logger.info(f"Getting recommendations for user: {user_id}")
        
        personalize_response = personalize.get_recommendations(
            campaignArn=campaign_arn,
            userId=user_id,
            numResults=num_results
        )
        
        # Format response
        recommendations = []
        for item in personalize_response.get('itemList', []):
            recommendations.append({
                'itemId': item['itemId'],
                'score': round(float(item['score']), 4)
            })
        
        response_data = {
            'userId': user_id,
            'recommendations': recommendations,
            'numResults': len(recommendations),
            'requestId': personalize_response['ResponseMetadata']['RequestId']
        }
        
        logger.info(f"Successfully retrieved {len(recommendations)} recommendations for user: {user_id}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
                'Access-Control-Allow-Methods': 'GET,OPTIONS',
                'Cache-Control': 'no-cache'
            },
            'body': json.dumps(response_data)
        }
        
    except personalize.exceptions.ResourceNotFoundException as e:
        logger.error(f"Campaign not found: {str(e)}")
        return create_error_response(404, "Campaign not found or not active")
        
    except personalize.exceptions.InvalidInputException as e:
        logger.error(f"Invalid input to Personalize: {str(e)}")
        return create_error_response(400, "Invalid request parameters")
        
    except ValueError as e:
        logger.error(f"Value error: {str(e)}")
        return create_error_response(400, "Invalid parameter value")
        
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return create_error_response(500, "Internal server error")

def create_error_response(status_code: int, message: str) -> Dict[str, Any]:
    """
    Create standardized error response.
    
    Args:
        status_code: HTTP status code
        message: Error message
        
    Returns:
        API Gateway error response
    """
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
            'Access-Control-Allow-Methods': 'GET,OPTIONS'
        },
        'body': json.dumps({
            'error': message,
            'statusCode': status_code
        })
    }
`;
  }
}