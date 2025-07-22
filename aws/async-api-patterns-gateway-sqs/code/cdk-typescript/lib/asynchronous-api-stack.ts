import * as cdk from 'aws-cdk-lib';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambdaEventSources from 'aws-cdk-lib/aws-lambda-event-sources';
import { Construct } from 'constructs';
import * as path from 'path';

export interface AsynchronousApiStackProps extends cdk.StackProps {
  readonly environment: string;
  readonly projectName: string;
}

export class AsynchronousApiStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: AsynchronousApiStackProps) {
    super(scope, id, props);

    const { environment, projectName } = props;

    // S3 bucket for storing job results
    const resultsBucket = new s3.Bucket(this, 'ResultsBucket', {
      bucketName: `${projectName}-${environment}-results-${cdk.Aws.ACCOUNT_ID}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: false,
    });

    // Dead Letter Queue for failed message processing
    const deadLetterQueue = new sqs.Queue(this, 'DeadLetterQueue', {
      queueName: `${projectName}-${environment}-dlq`,
      retentionPeriod: cdk.Duration.days(14),
      visibilityTimeout: cdk.Duration.minutes(5),
    });

    // Main processing queue with dead letter queue configuration
    const mainQueue = new sqs.Queue(this, 'MainQueue', {
      queueName: `${projectName}-${environment}-main-queue`,
      retentionPeriod: cdk.Duration.days(14),
      visibilityTimeout: cdk.Duration.minutes(5),
      deadLetterQueue: {
        queue: deadLetterQueue,
        maxReceiveCount: 3,
      },
    });

    // DynamoDB table for job tracking
    const jobsTable = new dynamodb.Table(this, 'JobsTable', {
      tableName: `${projectName}-${environment}-jobs`,
      partitionKey: {
        name: 'jobId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      pointInTimeRecovery: true,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
    });

    // IAM role for API Gateway to send messages to SQS
    const apiGatewayRole = new iam.Role(this, 'ApiGatewayRole', {
      roleName: `${projectName}-${environment}-api-gateway-role`,
      assumedBy: new iam.ServicePrincipal('apigateway.amazonaws.com'),
      inlinePolicies: {
        SQSAccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sqs:SendMessage',
                'sqs:GetQueueAttributes',
              ],
              resources: [mainQueue.queueArn],
            }),
          ],
        }),
      },
    });

    // Lambda execution role with comprehensive permissions
    const lambdaRole = new iam.Role(this, 'LambdaRole', {
      roleName: `${projectName}-${environment}-lambda-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        LambdaAccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:PutItem',
                'dynamodb:GetItem',
                'dynamodb:UpdateItem',
                'dynamodb:Query',
                'dynamodb:Scan',
              ],
              resources: [jobsTable.tableArn],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:PutObject',
                's3:GetObject',
                's3:DeleteObject',
              ],
              resources: [`${resultsBucket.bucketArn}/*`],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sqs:ReceiveMessage',
                'sqs:DeleteMessage',
                'sqs:GetQueueAttributes',
              ],
              resources: [mainQueue.queueArn],
            }),
          ],
        }),
      },
    });

    // Job processor Lambda function
    const jobProcessorFunction = new lambda.Function(this, 'JobProcessorFunction', {
      functionName: `${projectName}-${environment}-job-processor`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'job-processor.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import time
from datetime import datetime, timezone

dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    table_name = os.environ['JOBS_TABLE_NAME']
    results_bucket = os.environ['RESULTS_BUCKET_NAME']
    
    table = dynamodb.Table(table_name)
    
    for record in event['Records']:
        try:
            # Parse message from SQS
            message_body = json.loads(record['body'])
            job_id = message_body['jobId']
            job_data = message_body['data']
            
            # Update job status to processing
            table.update_item(
                Key={'jobId': job_id},
                UpdateExpression='SET #status = :status, #updatedAt = :timestamp',
                ExpressionAttributeNames={
                    '#status': 'status',
                    '#updatedAt': 'updatedAt'
                },
                ExpressionAttributeValues={
                    ':status': 'processing',
                    ':timestamp': datetime.now(timezone.utc).isoformat()
                }
            )
            
            # Simulate processing work (replace with actual processing logic)
            time.sleep(10)  # Simulate work
            
            # Generate result
            result = {
                'jobId': job_id,
                'result': f'Processed data: {job_data}',
                'processedAt': datetime.now(timezone.utc).isoformat()
            }
            
            # Store result in S3
            s3.put_object(
                Bucket=results_bucket,
                Key=f'results/{job_id}.json',
                Body=json.dumps(result),
                ContentType='application/json'
            )
            
            # Update job status to completed
            table.update_item(
                Key={'jobId': job_id},
                UpdateExpression='SET #status = :status, #result = :result, #updatedAt = :timestamp',
                ExpressionAttributeNames={
                    '#status': 'status',
                    '#result': 'result',
                    '#updatedAt': 'updatedAt'
                },
                ExpressionAttributeValues={
                    ':status': 'completed',
                    ':result': f's3://{results_bucket}/results/{job_id}.json',
                    ':timestamp': datetime.now(timezone.utc).isoformat()
                }
            )
            
            print(f"Successfully processed job {job_id}")
            
        except Exception as e:
            print(f"Error processing job: {str(e)}")
            # Update job status to failed
            table.update_item(
                Key={'jobId': job_id},
                UpdateExpression='SET #status = :status, #error = :error, #updatedAt = :timestamp',
                ExpressionAttributeNames={
                    '#status': 'status',
                    '#error': 'error',
                    '#updatedAt': 'updatedAt'
                },
                ExpressionAttributeValues={
                    ':status': 'failed',
                    ':error': str(e),
                    ':timestamp': datetime.now(timezone.utc).isoformat()
                }
            )
            raise

    return {'statusCode': 200, 'body': 'Processing complete'}
      `),
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      environment: {
        JOBS_TABLE_NAME: jobsTable.tableName,
        RESULTS_BUCKET_NAME: resultsBucket.bucketName,
      },
    });

    // Status checker Lambda function
    const statusCheckerFunction = new lambda.Function(this, 'StatusCheckerFunction', {
      functionName: `${projectName}-${environment}-status-checker`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'status-checker.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    table_name = os.environ['JOBS_TABLE_NAME']
    table = dynamodb.Table(table_name)
    
    job_id = event['pathParameters']['jobId']
    
    try:
        response = table.get_item(Key={'jobId': job_id})
        
        if 'Item' not in response:
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Job not found'})
            }
        
        job = response['Item']
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'jobId': job['jobId'],
                'status': job['status'],
                'createdAt': job['createdAt'],
                'updatedAt': job.get('updatedAt', job['createdAt']),
                'result': job.get('result'),
                'error': job.get('error')
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }
      `),
      role: lambdaRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        JOBS_TABLE_NAME: jobsTable.tableName,
      },
    });

    // Add SQS event source mapping to trigger job processor
    jobProcessorFunction.addEventSource(
      new lambdaEventSources.SqsEventSource(mainQueue, {
        batchSize: 10,
        maxBatchingWindow: cdk.Duration.seconds(5),
      })
    );

    // REST API Gateway
    const api = new apigateway.RestApi(this, 'AsynchronousApi', {
      restApiName: `${projectName}-${environment}-api`,
      description: 'Asynchronous API with SQS integration',
      endpointTypes: [apigateway.EndpointType.REGIONAL],
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key'],
      },
    });

    // Create /submit resource
    const submitResource = api.root.addResource('submit');

    // Add POST method for /submit with SQS integration
    submitResource.addMethod('POST', new apigateway.AwsIntegration({
      service: 'sqs',
      path: `${cdk.Aws.ACCOUNT_ID}/${mainQueue.queueName}`,
      integrationHttpMethod: 'POST',
      options: {
        credentialsRole: apiGatewayRole,
        requestParameters: {
          'integration.request.header.Content-Type': "'application/x-amz-json-1.0'",
          'integration.request.querystring.Action': "'SendMessage'",
          'integration.request.querystring.MessageBody': 'method.request.body',
        },
        requestTemplates: {
          'application/json': JSON.stringify({
            jobId: '$context.requestId',
            data: '$input.json(\'$\')',
            timestamp: '$context.requestTime',
          }),
        },
        integrationResponses: [
          {
            statusCode: '200',
            responseTemplates: {
              'application/json': JSON.stringify({
                jobId: '$context.requestId',
                status: 'queued',
                message: 'Job submitted successfully',
              }),
            },
          },
        ],
      },
    }), {
      methodResponses: [
        {
          statusCode: '200',
          responseModels: {
            'application/json': apigateway.Model.EMPTY_MODEL,
          },
        },
      ],
    });

    // Create /status resource
    const statusResource = api.root.addResource('status');
    const statusJobResource = statusResource.addResource('{jobId}');

    // Add GET method for /status/{jobId} with Lambda proxy integration
    statusJobResource.addMethod('GET', new apigateway.LambdaIntegration(statusCheckerFunction, {
      proxy: true,
    }), {
      requestParameters: {
        'method.request.path.jobId': true,
      },
    });

    // Create job status tracking function that initializes jobs in DynamoDB
    const jobInitializerFunction = new lambda.Function(this, 'JobInitializerFunction', {
      functionName: `${projectName}-${environment}-job-initializer`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'job-initializer.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime, timezone

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    table_name = os.environ['JOBS_TABLE_NAME']
    table = dynamodb.Table(table_name)
    
    # Initialize job record in DynamoDB
    job_id = event['jobId']
    
    table.put_item(
        Item={
            'jobId': job_id,
            'status': 'queued',
            'createdAt': datetime.now(timezone.utc).isoformat(),
            'updatedAt': datetime.now(timezone.utc).isoformat()
        }
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({'message': 'Job initialized'})
    }
      `),
      role: lambdaRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        JOBS_TABLE_NAME: jobsTable.tableName,
      },
    });

    // Outputs for verification and integration
    new cdk.CfnOutput(this, 'ApiEndpoint', {
      value: api.url,
      description: 'API Gateway endpoint URL',
      exportName: `${id}-ApiEndpoint`,
    });

    new cdk.CfnOutput(this, 'MainQueueUrl', {
      value: mainQueue.queueUrl,
      description: 'Main processing queue URL',
      exportName: `${id}-MainQueueUrl`,
    });

    new cdk.CfnOutput(this, 'DeadLetterQueueUrl', {
      value: deadLetterQueue.queueUrl,
      description: 'Dead letter queue URL',
      exportName: `${id}-DeadLetterQueueUrl`,
    });

    new cdk.CfnOutput(this, 'JobsTableName', {
      value: jobsTable.tableName,
      description: 'DynamoDB jobs table name',
      exportName: `${id}-JobsTableName`,
    });

    new cdk.CfnOutput(this, 'ResultsBucketName', {
      value: resultsBucket.bucketName,
      description: 'S3 results bucket name',
      exportName: `${id}-ResultsBucketName`,
    });

    new cdk.CfnOutput(this, 'SubmitEndpoint', {
      value: `${api.url}submit`,
      description: 'Job submission endpoint',
      exportName: `${id}-SubmitEndpoint`,
    });

    new cdk.CfnOutput(this, 'StatusEndpoint', {
      value: `${api.url}status/{jobId}`,
      description: 'Job status check endpoint',
      exportName: `${id}-StatusEndpoint`,
    });
  }
}