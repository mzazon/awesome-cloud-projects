#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as s3deployment from 'aws-cdk-lib/aws-s3-deployment';
import * as path from 'path';
import { RemovalPolicy } from 'aws-cdk-lib';

/**
 * Stack for Amazon Transcribe Speech Recognition Applications
 * 
 * This stack creates the infrastructure needed for comprehensive speech recognition
 * applications using Amazon Transcribe, including:
 * - S3 buckets for audio files and transcription outputs
 * - IAM roles with appropriate permissions
 * - Lambda functions for processing transcription results
 * - API Gateway for client integration
 * - Custom vocabulary and filter support
 */
export class SpeechRecognitionTranscribeStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // ==========================================
    // S3 Bucket for Audio Files and Outputs
    // ==========================================
    
    const transcribeBucket = new s3.Bucket(this, 'TranscribeBucket', {
      bucketName: `transcribe-demo-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'DeleteOldTranscriptionResults',
          prefix: 'transcription-output/',
          expiration: cdk.Duration.days(30),
        },
        {
          id: 'TransitionToIA',
          prefix: 'audio-input/',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
          ],
        },
      ],
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create folder structure in S3 bucket
    new s3deployment.BucketDeployment(this, 'CreateFolderStructure', {
      sources: [s3deployment.Source.data('audio-input/.keep', '')],
      destinationBucket: transcribeBucket,
      destinationKeyPrefix: 'audio-input/',
    });

    new s3deployment.BucketDeployment(this, 'CreateOutputFolder', {
      sources: [s3deployment.Source.data('transcription-output/.keep', '')],
      destinationBucket: transcribeBucket,
      destinationKeyPrefix: 'transcription-output/',
    });

    new s3deployment.BucketDeployment(this, 'CreateVocabularyFolder', {
      sources: [s3deployment.Source.data('custom-vocabulary/.keep', '')],
      destinationBucket: transcribeBucket,
      destinationKeyPrefix: 'custom-vocabulary/',
    });

    new s3deployment.BucketDeployment(this, 'CreateTrainingFolder', {
      sources: [s3deployment.Source.data('training-data/.keep', '')],
      destinationBucket: transcribeBucket,
      destinationKeyPrefix: 'training-data/',
    });

    // ==========================================
    // IAM Role for Transcribe Service
    // ==========================================
    
    const transcribeServiceRole = new iam.Role(this, 'TranscribeServiceRole', {
      roleName: `TranscribeServiceRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('transcribe.amazonaws.com'),
      description: 'Service role for Amazon Transcribe to access S3 bucket',
    });

    // Policy for S3 access
    const transcribeS3Policy = new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:GetObject',
        's3:PutObject',
        's3:DeleteObject',
        's3:ListBucket',
        's3:GetBucketLocation',
      ],
      resources: [
        transcribeBucket.bucketArn,
        `${transcribeBucket.bucketArn}/*`,
      ],
    });

    transcribeServiceRole.addToPolicy(transcribeS3Policy);

    // ==========================================
    // Lambda Function for Processing Results
    // ==========================================
    
    const transcribeProcessorFunction = new lambda.Function(this, 'TranscribeProcessor', {
      functionName: `transcribe-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      description: 'Process Amazon Transcribe results and trigger downstream workflows',
      environment: {
        TRANSCRIBE_BUCKET: transcribeBucket.bucketName,
        TRANSCRIBE_ROLE_ARN: transcribeServiceRole.roleArn,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from typing import Dict, Any
from botocore.exceptions import ClientError

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process Amazon Transcribe results and trigger downstream workflows
    
    Args:
        event: Lambda event containing job name or S3 notification
        context: Lambda context object
        
    Returns:
        Response dictionary with processing results
    """
    transcribe = boto3.client('transcribe')
    s3 = boto3.client('s3')
    
    print(f"Processing event: {json.dumps(event, default=str)}")
    
    try:
        # Handle different event types
        if 'jobName' in event:
            # Direct job name provided
            job_name = event['jobName']
        elif 'Records' in event:
            # S3 event notification
            # Extract job name from S3 key or metadata
            record = event['Records'][0]
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']
            job_name = key.split('/')[-1].replace('.json', '')
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'Invalid event format',
                    'message': 'Event must contain jobName or S3 Records'
                })
            }
        
        print(f"Processing transcription job: {job_name}")
        
        # Get transcription job details
        try:
            response = transcribe.get_transcription_job(
                TranscriptionJobName=job_name
            )
        except ClientError as e:
            if e.response['Error']['Code'] == 'BadRequestException':
                return {
                    'statusCode': 404,
                    'body': json.dumps({
                        'error': 'Job not found',
                        'jobName': job_name
                    })
                }
            raise
        
        transcription_job = response['TranscriptionJob']
        job_status = transcription_job['TranscriptionJobStatus']
        
        print(f"Job status: {job_status}")
        
        if job_status == 'COMPLETED':
            # Process completed transcription
            transcript_uri = transcription_job['Transcript']['TranscriptFileUri']
            
            # Extract additional metadata
            metadata = {
                'jobName': job_name,
                'status': job_status,
                'transcriptUri': transcript_uri,
                'languageCode': transcription_job.get('LanguageCode'),
                'mediaFormat': transcription_job.get('MediaFormat'),
                'creationTime': transcription_job.get('CreationTime'),
                'completionTime': transcription_job.get('CompletionTime'),
            }
            
            # Add advanced features metadata if available
            if 'Settings' in transcription_job:
                settings = transcription_job['Settings']
                metadata['features'] = {
                    'showSpeakerLabels': settings.get('ShowSpeakerLabels', False),
                    'maxSpeakerLabels': settings.get('MaxSpeakerLabels'),
                    'channelIdentification': settings.get('ChannelIdentification', False),
                    'vocabularyName': settings.get('VocabularyName'),
                    'vocabularyFilterName': settings.get('VocabularyFilterName'),
                    'vocabularyFilterMethod': settings.get('VocabularyFilterMethod'),
                }
            
            # Add content redaction metadata if available
            if 'ContentRedaction' in transcription_job:
                metadata['contentRedaction'] = {
                    'redactionType': transcription_job['ContentRedaction'].get('RedactionType'),
                    'redactionOutput': transcription_job['ContentRedaction'].get('RedactionOutput'),
                }
            
            print(f"Transcription completed successfully: {transcript_uri}")
            
            # Here you can add additional processing logic:
            # - Send notifications
            # - Store metadata in DynamoDB
            # - Trigger downstream workflows
            # - Process the transcript content
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Transcription completed and processed successfully',
                    'metadata': metadata
                }, default=str)
            }
            
        elif job_status == 'FAILED':
            # Handle failed transcription
            failure_reason = transcription_job.get('FailureReason', 'Unknown error')
            
            print(f"Transcription failed: {failure_reason}")
            
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'error': 'Transcription failed',
                    'jobName': job_name,
                    'failureReason': failure_reason
                })
            }
            
        else:
            # Job still in progress
            return {
                'statusCode': 202,
                'body': json.dumps({
                    'message': 'Transcription in progress',
                    'jobName': job_name,
                    'status': job_status
                })
            }
            
    except Exception as e:
        print(f"Error processing transcription: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal server error',
                'message': str(e)
            })
        }
      `),
    });

    // Grant Lambda function permissions
    transcribeBucket.grantReadWrite(transcribeProcessorFunction);
    
    const transcribePolicy = new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'transcribe:GetTranscriptionJob',
        'transcribe:ListTranscriptionJobs',
        'transcribe:StartTranscriptionJob',
        'transcribe:DeleteTranscriptionJob',
      ],
      resources: ['*'],
    });
    
    transcribeProcessorFunction.addToRolePolicy(transcribePolicy);

    // ==========================================
    // API Gateway for Client Integration
    // ==========================================
    
    const api = new apigateway.RestApi(this, 'TranscribeApi', {
      restApiName: `transcribe-api-${uniqueSuffix}`,
      description: 'API for Amazon Transcribe speech recognition operations',
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key'],
      },
    });

    // Lambda integration for API Gateway
    const lambdaIntegration = new apigateway.LambdaIntegration(transcribeProcessorFunction, {
      requestTemplates: {
        'application/json': `{
          "jobName": "$input.params('jobName')",
          "action": "$input.params('action')",
          "body": $input.json('$')
        }`,
      },
    });

    // API Gateway resources and methods
    const transcribeResource = api.root.addResource('transcribe');
    const jobResource = transcribeResource.addResource('job');
    const jobNameResource = jobResource.addResource('{jobName}');
    
    // GET /transcribe/job/{jobName} - Get job status
    jobNameResource.addMethod('GET', lambdaIntegration, {
      requestParameters: {
        'method.request.path.jobName': true,
      },
    });

    // POST /transcribe/job - Process job result
    jobResource.addMethod('POST', lambdaIntegration);

    // ==========================================
    // Transcription Management Lambda
    // ==========================================
    
    const transcriptionManagerFunction = new lambda.Function(this, 'TranscriptionManager', {
      functionName: `transcription-manager-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.minutes(15),
      memorySize: 512,
      description: 'Manage Amazon Transcribe jobs, vocabularies, and streaming operations',
      environment: {
        TRANSCRIBE_BUCKET: transcribeBucket.bucketName,
        TRANSCRIBE_ROLE_ARN: transcribeServiceRole.roleArn,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import uuid
from typing import Dict, Any, Optional, List
from botocore.exceptions import ClientError

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Manage Amazon Transcribe operations including job creation, vocabulary management,
    and streaming setup
    
    Args:
        event: Lambda event containing operation type and parameters
        context: Lambda context object
        
    Returns:
        Response dictionary with operation results
    """
    transcribe = boto3.client('transcribe')
    s3 = boto3.client('s3')
    
    bucket_name = os.environ['TRANSCRIBE_BUCKET']
    role_arn = os.environ['TRANSCRIBE_ROLE_ARN']
    
    print(f"Processing management event: {json.dumps(event, default=str)}")
    
    try:
        operation = event.get('operation')
        
        if operation == 'create_vocabulary':
            return create_custom_vocabulary(transcribe, s3, bucket_name, event)
        elif operation == 'create_vocabulary_filter':
            return create_vocabulary_filter(transcribe, s3, bucket_name, event)
        elif operation == 'start_transcription_job':
            return start_transcription_job(transcribe, bucket_name, role_arn, event)
        elif operation == 'list_jobs':
            return list_transcription_jobs(transcribe, event)
        elif operation == 'delete_job':
            return delete_transcription_job(transcribe, event)
        elif operation == 'get_streaming_config':
            return get_streaming_configuration(event)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'Invalid operation',
                    'validOperations': [
                        'create_vocabulary',
                        'create_vocabulary_filter',
                        'start_transcription_job',
                        'list_jobs',
                        'delete_job',
                        'get_streaming_config'
                    ]
                })
            }
            
    except Exception as e:
        print(f"Error in transcription management: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal server error',
                'message': str(e)
            })
        }

def create_custom_vocabulary(transcribe, s3, bucket_name: str, event: Dict[str, Any]) -> Dict[str, Any]:
    """Create a custom vocabulary for improved transcription accuracy"""
    vocabulary_name = event.get('vocabularyName', f"custom-vocab-{uuid.uuid4().hex[:8]}")
    language_code = event.get('languageCode', 'en-US')
    vocabulary_terms = event.get('vocabularyTerms', [])
    
    # Create vocabulary file content
    vocabulary_content = '\\n'.join(vocabulary_terms)
    
    # Upload vocabulary file to S3
    vocabulary_key = f"custom-vocabulary/{vocabulary_name}.txt"
    s3.put_object(
        Bucket=bucket_name,
        Key=vocabulary_key,
        Body=vocabulary_content.encode('utf-8'),
        ContentType='text/plain'
    )
    
    # Create vocabulary in Transcribe
    vocabulary_uri = f"s3://{bucket_name}/{vocabulary_key}"
    
    try:
        transcribe.create_vocabulary(
            VocabularyName=vocabulary_name,
            LanguageCode=language_code,
            VocabularyFileUri=vocabulary_uri
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Custom vocabulary creation initiated',
                'vocabularyName': vocabulary_name,
                'vocabularyUri': vocabulary_uri,
                'languageCode': language_code
            })
        }
    except ClientError as e:
        if e.response['Error']['Code'] == 'ConflictException':
            return {
                'statusCode': 409,
                'body': json.dumps({
                    'error': 'Vocabulary already exists',
                    'vocabularyName': vocabulary_name
                })
            }
        raise

def create_vocabulary_filter(transcribe, s3, bucket_name: str, event: Dict[str, Any]) -> Dict[str, Any]:
    """Create a vocabulary filter for content filtering"""
    filter_name = event.get('filterName', f"content-filter-{uuid.uuid4().hex[:8]}")
    language_code = event.get('languageCode', 'en-US')
    filter_terms = event.get('filterTerms', [])
    
    # Create filter file content
    filter_content = '\\n'.join(filter_terms)
    
    # Upload filter file to S3
    filter_key = f"custom-vocabulary/{filter_name}.txt"
    s3.put_object(
        Bucket=bucket_name,
        Key=filter_key,
        Body=filter_content.encode('utf-8'),
        ContentType='text/plain'
    )
    
    # Create vocabulary filter in Transcribe
    filter_uri = f"s3://{bucket_name}/{filter_key}"
    
    try:
        transcribe.create_vocabulary_filter(
            VocabularyFilterName=filter_name,
            LanguageCode=language_code,
            VocabularyFilterFileUri=filter_uri
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Vocabulary filter creation initiated',
                'filterName': filter_name,
                'filterUri': filter_uri,
                'languageCode': language_code
            })
        }
    except ClientError as e:
        if e.response['Error']['Code'] == 'ConflictException':
            return {
                'statusCode': 409,
                'body': json.dumps({
                    'error': 'Vocabulary filter already exists',
                    'filterName': filter_name
                })
            }
        raise

def start_transcription_job(transcribe, bucket_name: str, role_arn: str, event: Dict[str, Any]) -> Dict[str, Any]:
    """Start a transcription job with advanced features"""
    job_name = event.get('jobName', f"transcription-job-{uuid.uuid4().hex[:8]}")
    media_uri = event.get('mediaUri')
    media_format = event.get('mediaFormat', 'mp3')
    language_code = event.get('languageCode', 'en-US')
    
    if not media_uri:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'mediaUri is required'
            })
        }
    
    # Build transcription job parameters
    job_params = {
        'TranscriptionJobName': job_name,
        'LanguageCode': language_code,
        'MediaFormat': media_format,
        'Media': {
            'MediaFileUri': media_uri
        },
        'OutputBucketName': bucket_name,
        'OutputKey': f"transcription-output/{job_name}.json"
    }
    
    # Add advanced settings if provided
    settings = {}
    
    if event.get('vocabularyName'):
        settings['VocabularyName'] = event['vocabularyName']
    
    if event.get('showSpeakerLabels'):
        settings['ShowSpeakerLabels'] = True
        settings['MaxSpeakerLabels'] = event.get('maxSpeakerLabels', 4)
    
    if event.get('channelIdentification'):
        settings['ChannelIdentification'] = True
    
    if event.get('vocabularyFilterName'):
        settings['VocabularyFilterName'] = event['vocabularyFilterName']
        settings['VocabularyFilterMethod'] = event.get('vocabularyFilterMethod', 'mask')
    
    if settings:
        job_params['Settings'] = settings
    
    # Add content redaction if requested
    if event.get('enablePiiRedaction'):
        job_params['ContentRedaction'] = {
            'RedactionType': 'PII',
            'RedactionOutput': event.get('redactionOutput', 'redacted_and_unredacted')
        }
    
    try:
        transcribe.start_transcription_job(**job_params)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Transcription job started successfully',
                'jobName': job_name,
                'mediaUri': media_uri,
                'outputLocation': f"s3://{bucket_name}/transcription-output/{job_name}.json"
            })
        }
    except ClientError as e:
        if e.response['Error']['Code'] == 'ConflictException':
            return {
                'statusCode': 409,
                'body': json.dumps({
                    'error': 'Job name already exists',
                    'jobName': job_name
                })
            }
        raise

def list_transcription_jobs(transcribe, event: Dict[str, Any]) -> Dict[str, Any]:
    """List transcription jobs with optional filtering"""
    status_filter = event.get('status')
    max_results = event.get('maxResults', 20)
    
    params = {
        'MaxResults': max_results
    }
    
    if status_filter:
        params['Status'] = status_filter
    
    response = transcribe.list_transcription_jobs(**params)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'jobs': response.get('TranscriptionJobSummaries', []),
            'nextToken': response.get('NextToken')
        }, default=str)
    }

def delete_transcription_job(transcribe, event: Dict[str, Any]) -> Dict[str, Any]:
    """Delete a completed transcription job"""
    job_name = event.get('jobName')
    
    if not job_name:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'jobName is required'
            })
        }
    
    try:
        transcribe.delete_transcription_job(TranscriptionJobName=job_name)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Transcription job deleted successfully',
                'jobName': job_name
            })
        }
    except ClientError as e:
        if e.response['Error']['Code'] == 'BadRequestException':
            return {
                'statusCode': 404,
                'body': json.dumps({
                    'error': 'Job not found',
                    'jobName': job_name
                })
            }
        raise

def get_streaming_configuration(event: Dict[str, Any]) -> Dict[str, Any]:
    """Get configuration for streaming transcription"""
    language_code = event.get('languageCode', 'en-US')
    sample_rate = event.get('sampleRate', 44100)
    media_encoding = event.get('mediaEncoding', 'pcm')
    
    config = {
        'LanguageCode': language_code,
        'MediaSampleRateHertz': sample_rate,
        'MediaEncoding': media_encoding,
        'EnablePartialResultsStabilization': True,
        'PartialResultsStability': 'high'
    }
    
    if event.get('vocabularyName'):
        config['VocabularyName'] = event['vocabularyName']
    
    if event.get('showSpeakerLabels'):
        config['ShowSpeakerLabels'] = True
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'streamingConfig': config,
            'websocketEndpoint': f"wss://transcribestreaming.{os.environ.get('AWS_REGION', 'us-east-1')}.amazonaws.com:8443/stream-transcription-websocket"
        })
    }
      `),
    });

    // Grant additional permissions to transcription manager
    transcribeBucket.grantReadWrite(transcriptionManagerFunction);
    
    const transcribeManagementPolicy = new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'transcribe:*',
      ],
      resources: ['*'],
    });
    
    transcriptionManagerFunction.addToRolePolicy(transcribeManagementPolicy);

    // Add management endpoints to API Gateway
    const managementResource = api.root.addResource('management');
    
    const managementIntegration = new apigateway.LambdaIntegration(transcriptionManagerFunction, {
      requestTemplates: {
        'application/json': `{
          "operation": "$input.params('operation')",
          "body": $input.json('$')
        }`,
      },
    });
    
    const operationResource = managementResource.addResource('{operation}');
    operationResource.addMethod('POST', managementIntegration, {
      requestParameters: {
        'method.request.path.operation': true,
      },
    });

    // ==========================================
    // Outputs
    // ==========================================
    
    new cdk.CfnOutput(this, 'TranscribeBucketName', {
      value: transcribeBucket.bucketName,
      description: 'S3 bucket for audio files and transcription outputs',
    });

    new cdk.CfnOutput(this, 'TranscribeServiceRoleArn', {
      value: transcribeServiceRole.roleArn,
      description: 'IAM role ARN for Amazon Transcribe service',
    });

    new cdk.CfnOutput(this, 'TranscribeProcessorFunctionName', {
      value: transcribeProcessorFunction.functionName,
      description: 'Lambda function for processing transcription results',
    });

    new cdk.CfnOutput(this, 'TranscriptionManagerFunctionName', {
      value: transcriptionManagerFunction.functionName,
      description: 'Lambda function for managing transcription operations',
    });

    new cdk.CfnOutput(this, 'ApiGatewayUrl', {
      value: api.url,
      description: 'API Gateway URL for client integration',
    });

    new cdk.CfnOutput(this, 'ApiGatewayId', {
      value: api.restApiId,
      description: 'API Gateway REST API ID',
    });

    // Example usage outputs
    new cdk.CfnOutput(this, 'ExampleVocabularyCreation', {
      value: `curl -X POST ${api.url}management/create_vocabulary -H "Content-Type: application/json" -d '{"vocabularyName": "my-vocab", "vocabularyTerms": ["AWS", "Transcribe", "CDK"]}'`,
      description: 'Example command to create custom vocabulary',
    });

    new cdk.CfnOutput(this, 'ExampleTranscriptionJob', {
      value: `curl -X POST ${api.url}management/start_transcription_job -H "Content-Type: application/json" -d '{"jobName": "my-job", "mediaUri": "s3://${transcribeBucket.bucketName}/audio-input/sample.mp3", "showSpeakerLabels": true}'`,
      description: 'Example command to start transcription job',
    });

    new cdk.CfnOutput(this, 'ExampleJobStatus', {
      value: `curl -X GET ${api.url}transcribe/job/my-job`,
      description: 'Example command to check job status',
    });
  }
}

// ==========================================
// CDK App
// ==========================================

const app = new cdk.App();

new SpeechRecognitionTranscribeStack(app, 'SpeechRecognitionTranscribeStack', {
  description: 'Amazon Transcribe Speech Recognition Applications - CDK TypeScript Implementation',
  
  // Environment configuration
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Stack tags
  tags: {
    Project: 'SpeechRecognitionTranscribe',
    Environment: 'Development',
    Owner: 'CDK-TypeScript',
    CostCenter: 'ML-Services',
  },
});

// Add stack tags
cdk.Tags.of(app).add('Application', 'SpeechRecognitionTranscribe');
cdk.Tags.of(app).add('Framework', 'CDK');
cdk.Tags.of(app).add('Language', 'TypeScript');