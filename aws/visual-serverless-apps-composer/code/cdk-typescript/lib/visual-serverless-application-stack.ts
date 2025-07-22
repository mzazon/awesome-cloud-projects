import * as cdk from 'aws-cdk-lib';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

export interface VisualServerlessApplicationStackProps extends cdk.StackProps {
  stage: string;
}

/**
 * Visual Serverless Application Stack
 * 
 * This stack creates a serverless application that can be visually designed
 * with AWS Application Composer and deployed via CodeCatalyst CI/CD pipelines.
 * 
 * Components:
 * - API Gateway REST API with CORS support
 * - Lambda function for user CRUD operations
 * - DynamoDB table with encryption and backup
 * - SQS Dead Letter Queue for error handling
 * - CloudWatch Log Groups with retention policies
 * - X-Ray tracing for observability
 */
export class VisualServerlessApplicationStack extends cdk.Stack {
  public readonly api: apigateway.RestApi;
  public readonly usersFunction: lambda.Function;
  public readonly usersTable: dynamodb.Table;
  public readonly deadLetterQueue: sqs.Queue;

  constructor(scope: Construct, id: string, props: VisualServerlessApplicationStackProps) {
    super(scope, id, props);

    const { stage } = props;

    // Create Dead Letter Queue for failed Lambda invocations
    this.deadLetterQueue = new sqs.Queue(this, 'UsersDeadLetterQueue', {
      queueName: `${stage}-users-dlq`,
      retentionPeriod: cdk.Duration.days(14),
      visibilityTimeout: cdk.Duration.seconds(60),
      encryption: sqs.QueueEncryption.SQS_MANAGED,
      enforceSSL: true,
    });

    // Create DynamoDB table for user data
    this.usersTable = new dynamodb.Table(this, 'UsersTable', {
      tableName: `${stage}-users-table`,
      partitionKey: {
        name: 'id',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: stage === 'prod' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
      deletionProtection: stage === 'prod',
    });

    // Create CloudWatch Log Group for Lambda function
    const usersLogGroup = new logs.LogGroup(this, 'UsersLogGroup', {
      logGroupName: `/aws/lambda/${stage}-users-function`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create Lambda function for user operations
    this.usersFunction = new lambda.Function(this, 'UsersFunction', {
      functionName: `${stage}-users-function`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'users.lambda_handler',
      code: lambda.Code.fromAsset('../../src/handlers'),
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      reservedConcurrentExecutions: 100,
      environment: {
        TABLE_NAME: this.usersTable.tableName,
        LOG_LEVEL: 'INFO',
        STAGE: stage,
      },
      tracing: lambda.Tracing.ACTIVE,
      logGroup: usersLogGroup,
      deadLetterQueue: this.deadLetterQueue,
      description: 'Handle CRUD operations for users in visual serverless application',
    });

    // Grant Lambda function permissions to access DynamoDB table
    this.usersTable.grantReadWriteData(this.usersFunction);

    // Grant Lambda function permissions for X-Ray tracing
    this.usersFunction.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'xray:PutTraceSegments',
        'xray:PutTelemetryRecords',
      ],
      resources: ['*'],
    }));

    // Create API Gateway REST API
    this.api = new apigateway.RestApi(this, 'ServerlessAPI', {
      restApiName: `${stage}-serverless-api`,
      description: `Serverless API for ${stage} environment - Visual Serverless Application`,
      deployOptions: {
        stageName: stage,
        tracingEnabled: true,
        dataTraceEnabled: true,
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        metricsEnabled: true,
        throttlingBurstLimit: 1000,
        throttlingRateLimit: 500,
      },
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
        allowHeaders: [
          'Content-Type',
          'X-Amz-Date',
          'Authorization',
          'X-Api-Key',
          'X-Amz-Security-Token',
        ],
        maxAge: cdk.Duration.hours(1),
      },
      cloudWatchRole: true,
      endpointTypes: [apigateway.EndpointType.REGIONAL],
    });

    // Create Lambda integration for API Gateway
    const usersIntegration = new apigateway.LambdaIntegration(this.usersFunction, {
      requestTemplates: {
        'application/json': JSON.stringify({
          httpMethod: '$context.httpMethod',
          body: '$input.json(\'$\')',
          headers: {
            '#foreach($header in $input.params().header.keySet())',
            '"$header": "$util.escapeJavaScript($input.params().header.get($header))"',
            '#if($foreach.hasNext),#end',
            '#end',
          },
          queryStringParameters: {
            '#foreach($queryParam in $input.params().querystring.keySet())',
            '"$queryParam": "$util.escapeJavaScript($input.params().querystring.get($queryParam))"',
            '#if($foreach.hasNext),#end',
            '#end',
          },
          pathParameters: {
            '#foreach($pathParam in $input.params().path.keySet())',
            '"$pathParam": "$util.escapeJavaScript($input.params().path.get($pathParam))"',
            '#if($foreach.hasNext),#end',
            '#end',
          },
        }),
      },
      integrationResponses: [
        {
          statusCode: '200',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': "'*'",
            'method.response.header.Access-Control-Allow-Headers': "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
            'method.response.header.Access-Control-Allow-Methods': "'GET,POST,PUT,DELETE,OPTIONS'",
          },
        },
        {
          statusCode: '400',
          selectionPattern: '4\\d{2}',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': "'*'",
          },
        },
        {
          statusCode: '500',
          selectionPattern: '5\\d{2}',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': "'*'",
          },
        },
      ],
    });

    // Create /users resource
    const usersResource = this.api.root.addResource('users');

    // Add GET method to retrieve users
    usersResource.addMethod('GET', usersIntegration, {
      methodResponses: [
        {
          statusCode: '200',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
            'method.response.header.Access-Control-Allow-Headers': true,
            'method.response.header.Access-Control-Allow-Methods': true,
          },
        },
        {
          statusCode: '400',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
        {
          statusCode: '500',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
      ],
      requestValidator: new apigateway.RequestValidator(this, 'GetUsersRequestValidator', {
        restApi: this.api,
        validateRequestParameters: true,
      }),
    });

    // Add POST method to create users
    usersResource.addMethod('POST', usersIntegration, {
      methodResponses: [
        {
          statusCode: '201',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
            'method.response.header.Access-Control-Allow-Headers': true,
            'method.response.header.Access-Control-Allow-Methods': true,
          },
        },
        {
          statusCode: '400',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
        {
          statusCode: '500',
          responseParameters: {
            'method.response.header.Access-Control-Allow-Origin': true,
          },
        },
      ],
      requestValidator: new apigateway.RequestValidator(this, 'PostUsersRequestValidator', {
        restApi: this.api,
        validateRequestBody: true,
      }),
      requestModels: {
        'application/json': new apigateway.Model(this, 'PostUsersModel', {
          restApi: this.api,
          contentType: 'application/json',
          schema: {
            type: apigateway.JsonSchemaType.OBJECT,
            properties: {
              id: {
                type: apigateway.JsonSchemaType.STRING,
                minLength: 1,
              },
              name: {
                type: apigateway.JsonSchemaType.STRING,
                minLength: 1,
              },
              email: {
                type: apigateway.JsonSchemaType.STRING,
                format: 'email',
              },
            },
            required: ['id', 'name'],
          },
        }),
      },
    });

    // Create CloudWatch Dashboard for monitoring
    const dashboard = new cdk.aws_cloudwatch.Dashboard(this, 'VisualServerlessAppDashboard', {
      dashboardName: `${stage}-visual-serverless-app-dashboard`,
    });

    // Add API Gateway metrics to dashboard
    dashboard.addWidgets(
      new cdk.aws_cloudwatch.GraphWidget({
        title: 'API Gateway Requests',
        left: [this.api.metricCount()],
        right: [this.api.metricLatency()],
        width: 12,
      }),
      new cdk.aws_cloudwatch.GraphWidget({
        title: 'Lambda Function Metrics',
        left: [this.usersFunction.metricInvocations()],
        right: [this.usersFunction.metricDuration()],
        width: 12,
      }),
      new cdk.aws_cloudwatch.GraphWidget({
        title: 'DynamoDB Metrics',
        left: [this.usersTable.metricConsumedReadCapacityUnits()],
        right: [this.usersTable.metricConsumedWriteCapacityUnits()],
        width: 12,
      })
    );

    // Stack outputs
    new cdk.CfnOutput(this, 'ApiEndpoint', {
      value: this.api.url,
      description: 'API Gateway endpoint URL',
      exportName: `${this.stackName}-ApiEndpoint`,
    });

    new cdk.CfnOutput(this, 'DynamoDBTableName', {
      value: this.usersTable.tableName,
      description: 'DynamoDB table name for users',
      exportName: `${this.stackName}-UsersTable`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: this.usersFunction.functionArn,
      description: 'Lambda function ARN',
      exportName: `${this.stackName}-UsersFunction`,
    });

    new cdk.CfnOutput(this, 'DeadLetterQueueUrl', {
      value: this.deadLetterQueue.queueUrl,
      description: 'Dead Letter Queue URL',
      exportName: `${this.stackName}-DeadLetterQueue`,
    });

    new cdk.CfnOutput(this, 'CloudWatchDashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL',
    });
  }
}