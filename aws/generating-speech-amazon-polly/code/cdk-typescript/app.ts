#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * CDK Stack for Amazon Polly Text-to-Speech Application
 * 
 * This stack creates:
 * - S3 bucket for audio output storage
 * - Lambda function for text-to-speech synthesis
 * - API Gateway for REST API interface
 * - IAM roles with least privilege permissions
 * - CloudWatch logs for monitoring
 */
class PollyTextToSpeechStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.slice(-6).toLowerCase();

    // S3 bucket for storing generated audio files
    const audioBucket = new s3.Bucket(this, 'AudioOutputBucket', {
      bucketName: `polly-audio-output-${uniqueSuffix}`,
      // Enable versioning for audio file management
      versioned: true,
      // Automatic cleanup of old versions
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          expiration: cdk.Duration.days(30),
          noncurrentVersionExpiration: cdk.Duration.days(7),
        },
      ],
      // Enable server-side encryption
      encryption: s3.BucketEncryption.S3_MANAGED,
      // Block public access for security
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      // Enable access logging
      serverAccessLogsPrefix: 'access-logs/',
      // Auto-delete bucket contents on stack destruction (for demo purposes)
      autoDeleteObjects: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // CloudWatch log group for Lambda function
    const logGroup = new logs.LogGroup(this, 'PollyLambdaLogGroup', {
      logGroupName: `/aws/lambda/polly-text-to-speech-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // IAM role for Lambda function with Polly and S3 permissions
    const lambdaRole = new iam.Role(this, 'PollyLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for Polly text-to-speech Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        PollyAndS3Access: new iam.PolicyDocument({
          statements: [
            // Amazon Polly permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'polly:SynthesizeSpeech',
                'polly:StartSpeechSynthesisTask',
                'polly:GetSpeechSynthesisTask',
                'polly:ListSpeechSynthesisTasks',
                'polly:DescribeVoices',
                'polly:GetLexicon',
                'polly:ListLexicons',
              ],
              resources: ['*'],
            }),
            // S3 permissions for audio bucket
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:PutObject',
                's3:GetObject',
                's3:DeleteObject',
                's3:ListBucket',
              ],
              resources: [
                audioBucket.bucketArn,
                `${audioBucket.bucketArn}/*`,
              ],
            }),
            // CloudWatch Logs permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: [logGroup.logGroupArn],
            }),
          ],
        }),
      },
    });

    // Lambda function for text-to-speech synthesis
    const pollyFunction = new lambda.Function(this, 'PollyTextToSpeechFunction', {
      functionName: `polly-text-to-speech-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import base64
from botocore.exceptions import ClientError
import logging
import os
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
polly_client = boto3.client('polly')
s3_client = boto3.client('s3')

# Environment variables
AUDIO_BUCKET = os.environ['AUDIO_BUCKET']

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Lambda handler for Amazon Polly text-to-speech synthesis
    
    Supports both synchronous and asynchronous synthesis:
    - Synchronous: Returns base64-encoded audio data
    - Asynchronous: Returns S3 URL for batch processing
    """
    try:
        # Parse request body
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        else:
            body = event.get('body', {})
        
        # Extract parameters with defaults
        text = body.get('text', '')
        voice_id = body.get('voice_id', 'Joanna')
        engine = body.get('engine', 'neural')
        output_format = body.get('output_format', 'mp3')
        text_type = body.get('text_type', 'text')
        lexicon_names = body.get('lexicon_names', [])
        sample_rate = body.get('sample_rate', '24000')
        synthesis_mode = body.get('synthesis_mode', 'sync')  # 'sync' or 'async'
        
        # Validate required parameters
        if not text:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'Text parameter is required',
                    'message': 'Please provide text content for synthesis'
                })
            }
        
        # Validate voice engine compatibility
        if engine == 'neural':
            neural_voices = ['Joanna', 'Matthew', 'Amy', 'Brian', 'Emma', 'Olivia', 'Aria', 'Ayanda']
            if voice_id not in neural_voices:
                logger.warning(f"Voice {voice_id} may not support neural engine, falling back to standard")
                engine = 'standard'
        
        logger.info(f"Processing {synthesis_mode} synthesis request: voice={voice_id}, engine={engine}, format={output_format}")
        
        if synthesis_mode == 'async':
            # Asynchronous synthesis using batch processing
            return handle_async_synthesis(text, voice_id, engine, output_format, text_type, lexicon_names, sample_rate)
        else:
            # Synchronous synthesis
            return handle_sync_synthesis(text, voice_id, engine, output_format, text_type, lexicon_names, sample_rate)
    
    except ClientError as e:
        logger.error(f"AWS service error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'AWS service error',
                'message': str(e)
            })
        }
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal server error',
                'message': str(e)
            })
        }

def handle_sync_synthesis(text: str, voice_id: str, engine: str, output_format: str, 
                         text_type: str, lexicon_names: list, sample_rate: str) -> Dict[str, Any]:
    """Handle synchronous text-to-speech synthesis"""
    try:
        # Prepare synthesis parameters
        synthesis_params = {
            'Text': text,
            'VoiceId': voice_id,
            'Engine': engine,
            'OutputFormat': output_format,
            'TextType': text_type,
            'SampleRate': sample_rate
        }
        
        # Add lexicon names if provided
        if lexicon_names:
            synthesis_params['LexiconNames'] = lexicon_names
        
        # Synthesize speech
        response = polly_client.synthesize_speech(**synthesis_params)
        
        # Read audio data
        audio_data = response['AudioStream'].read()
        
        # Encode audio as base64 for JSON response
        audio_base64 = base64.b64encode(audio_data).decode('utf-8')
        
        # Prepare response
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': 'Speech synthesis completed successfully',
                'audio_data': audio_base64,
                'content_type': f'audio/{output_format}',
                'voice_id': voice_id,
                'engine': engine,
                'text_length': len(text),
                'synthesis_mode': 'synchronous'
            })
        }
        
    except ClientError as e:
        logger.error(f"Polly synthesis error: {e}")
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'Speech synthesis failed',
                'message': str(e)
            })
        }

def handle_async_synthesis(text: str, voice_id: str, engine: str, output_format: str,
                          text_type: str, lexicon_names: list, sample_rate: str) -> Dict[str, Any]:
    """Handle asynchronous text-to-speech synthesis with S3 output"""
    try:
        # Generate unique task identifier
        import uuid
        task_id = str(uuid.uuid4())
        
        # Prepare synthesis task parameters
        task_params = {
            'Text': text,
            'VoiceId': voice_id,
            'Engine': engine,
            'OutputFormat': output_format,
            'TextType': text_type,
            'SampleRate': sample_rate,
            'OutputS3BucketName': AUDIO_BUCKET,
            'OutputS3KeyPrefix': f'async-synthesis/{task_id}'
        }
        
        # Add lexicon names if provided
        if lexicon_names:
            task_params['LexiconNames'] = lexicon_names
        
        # Start synthesis task
        response = polly_client.start_speech_synthesis_task(**task_params)
        
        # Extract task information
        task_info = response['SynthesisTask']
        
        return {
            'statusCode': 202,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': 'Batch synthesis task started successfully',
                'task_id': task_info['TaskId'],
                'task_status': task_info['TaskStatus'],
                'creation_time': task_info['CreationTime'].isoformat(),
                'voice_id': voice_id,
                'engine': engine,
                'text_length': len(text),
                'synthesis_mode': 'asynchronous',
                'output_bucket': AUDIO_BUCKET,
                'output_prefix': f'async-synthesis/{task_id}'
            })
        }
        
    except ClientError as e:
        logger.error(f"Polly async synthesis error: {e}")
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'Batch synthesis task failed',
                'message': str(e)
            })
        }
`),
      timeout: cdk.Duration.seconds(30),
      memorySize: 512,
      role: lambdaRole,
      logGroup: logGroup,
      environment: {
        AUDIO_BUCKET: audioBucket.bucketName,
        PYTHON_LOG_LEVEL: 'INFO',
      },
      description: 'Lambda function for Amazon Polly text-to-speech synthesis',
    });

    // API Gateway REST API
    const api = new apigateway.RestApi(this, 'PollyTextToSpeechApi', {
      restApiName: `polly-text-to-speech-api-${uniqueSuffix}`,
      description: 'REST API for Amazon Polly text-to-speech synthesis',
      // Enable CORS for web applications
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
      // Enable request validation
      requestValidatorOptions: {
        validateRequestBody: true,
        validateRequestParameters: true,
      },
      // Configure API Gateway logging
      deployOptions: {
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
        metricsEnabled: true,
      },
    });

    // Lambda integration for API Gateway
    const lambdaIntegration = new apigateway.LambdaIntegration(pollyFunction, {
      requestTemplates: {
        'application/json': JSON.stringify({
          body: '$util.escapeJavaScript($input.body)',
          headers: {
            '#foreach($header in $input.params().header.keySet())',
            '"$header": "$util.escapeJavaScript($input.params().header.get($header))"',
            '#if($foreach.hasNext),#end',
            '#end',
          },
          method: '$context.httpMethod',
          params: {
            '#foreach($param in $input.params().path.keySet())',
            '"$param": "$util.escapeJavaScript($input.params().path.get($param))"',
            '#if($foreach.hasNext),#end',
            '#end',
          },
          query: {
            '#foreach($queryParam in $input.params().querystring.keySet())',
            '"$queryParam": "$util.escapeJavaScript($input.params().querystring.get($queryParam))"',
            '#if($foreach.hasNext),#end',
            '#end',
          },
        }),
      },
      integrationResponses: [
        {
          statusCode: '200',
          responseHeaders: {
            'Access-Control-Allow-Origin': "'*'",
            'Access-Control-Allow-Headers': "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
            'Access-Control-Allow-Methods': "'GET,POST,PUT,DELETE,OPTIONS'",
          },
        },
        {
          statusCode: '400',
          selectionPattern: '400',
          responseHeaders: {
            'Access-Control-Allow-Origin': "'*'",
          },
        },
        {
          statusCode: '500',
          selectionPattern: '500',
          responseHeaders: {
            'Access-Control-Allow-Origin': "'*'",
          },
        },
      ],
    });

    // Request model for API validation
    const requestModel = api.addModel('SynthesisRequestModel', {
      contentType: 'application/json',
      modelName: 'SynthesisRequest',
      schema: {
        type: apigateway.JsonSchemaType.OBJECT,
        properties: {
          text: {
            type: apigateway.JsonSchemaType.STRING,
            minLength: 1,
            maxLength: 100000,
          },
          voice_id: {
            type: apigateway.JsonSchemaType.STRING,
            enum: ['Joanna', 'Matthew', 'Amy', 'Brian', 'Emma', 'Olivia', 'Aria', 'Ayanda'],
          },
          engine: {
            type: apigateway.JsonSchemaType.STRING,
            enum: ['standard', 'neural'],
          },
          output_format: {
            type: apigateway.JsonSchemaType.STRING,
            enum: ['mp3', 'ogg_vorbis', 'pcm'],
          },
          text_type: {
            type: apigateway.JsonSchemaType.STRING,
            enum: ['text', 'ssml'],
          },
          synthesis_mode: {
            type: apigateway.JsonSchemaType.STRING,
            enum: ['sync', 'async'],
          },
          lexicon_names: {
            type: apigateway.JsonSchemaType.ARRAY,
            items: {
              type: apigateway.JsonSchemaType.STRING,
            },
          },
          sample_rate: {
            type: apigateway.JsonSchemaType.STRING,
            enum: ['8000', '16000', '22050', '24000'],
          },
        },
        required: ['text'],
      },
    });

    // API Gateway resources and methods
    const synthesisResource = api.root.addResource('synthesis');
    
    // POST /synthesis - Main synthesis endpoint
    synthesisResource.addMethod('POST', lambdaIntegration, {
      requestValidator: api.requestValidator,
      requestModels: {
        'application/json': requestModel,
      },
      methodResponses: [
        {
          statusCode: '200',
          responseHeaders: {
            'Access-Control-Allow-Origin': true,
            'Access-Control-Allow-Headers': true,
            'Access-Control-Allow-Methods': true,
          },
        },
        {
          statusCode: '400',
          responseHeaders: {
            'Access-Control-Allow-Origin': true,
          },
        },
        {
          statusCode: '500',
          responseHeaders: {
            'Access-Control-Allow-Origin': true,
          },
        },
      ],
    });

    // Health check endpoint
    const healthResource = api.root.addResource('health');
    healthResource.addMethod('GET', new apigateway.MockIntegration({
      integrationResponses: [
        {
          statusCode: '200',
          responseTemplates: {
            'application/json': JSON.stringify({
              status: 'healthy',
              timestamp: '$context.requestTime',
              service: 'polly-text-to-speech',
            }),
          },
        },
      ],
      requestTemplates: {
        'application/json': JSON.stringify({ statusCode: 200 }),
      },
    }), {
      methodResponses: [
        {
          statusCode: '200',
          responseHeaders: {
            'Access-Control-Allow-Origin': true,
          },
        },
      ],
    });

    // CloudFormation outputs for important resources
    new cdk.CfnOutput(this, 'AudioBucketName', {
      value: audioBucket.bucketName,
      description: 'S3 bucket name for audio output storage',
      exportName: `${this.stackName}-AudioBucket`,
    });

    new cdk.CfnOutput(this, 'ApiGatewayUrl', {
      value: api.url,
      description: 'API Gateway URL for text-to-speech synthesis',
      exportName: `${this.stackName}-ApiUrl`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: pollyFunction.functionName,
      description: 'Lambda function name for text-to-speech processing',
      exportName: `${this.stackName}-LambdaFunction`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: pollyFunction.functionArn,
      description: 'Lambda function ARN for text-to-speech processing',
      exportName: `${this.stackName}-LambdaArn`,
    });

    // Tags for cost allocation and management
    cdk.Tags.of(this).add('Project', 'PollyTextToSpeech');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
    cdk.Tags.of(this).add('CostCenter', 'Development');
  }
}

// CDK Application
const app = new cdk.App();

// Stack instantiation with configuration
new PollyTextToSpeechStack(app, 'PollyTextToSpeechStack', {
  description: 'Amazon Polly Text-to-Speech Application Stack (Recipe: text-to-speech-applications-amazon-polly)',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  terminationProtection: false, // Set to true for production
  // Stack-level tags
  tags: {
    Recipe: 'text-to-speech-applications-amazon-polly',
    Generator: 'CDK-TypeScript',
    Version: '1.0',
  },
});

// Synthesize CloudFormation template
app.synth();