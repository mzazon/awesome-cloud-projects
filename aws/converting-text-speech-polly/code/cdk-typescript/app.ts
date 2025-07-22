#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as logs from 'aws-cdk-lib/aws-logs';
import { RemovalPolicy } from 'aws-cdk-lib';

/**
 * Stack for Converting Text to Speech with Polly
 * This stack provides comprehensive text-to-speech capabilities including:
 * - S3 bucket for storing audio files and input text
 * - Lambda function for batch processing with Polly
 * - CloudFront distribution for global audio delivery
 * - IAM roles with least privilege access
 * - S3 event triggers for automated processing
 */
export class TextToSpeechPollyStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.account.substring(this.account.length - 6);

    // S3 bucket for storing audio files and input documents
    const audioStorageBucket = new s3.Bucket(this, 'AudioStorageBucket', {
      bucketName: `polly-audio-storage-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'DeleteIncompleteMultipartUploads',
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
        },
        {
          id: 'TransitionToIA',
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
    new s3.BucketDeployment(this, 'CreateFolderStructure', {
      sources: [s3deploy.Source.data('input/.gitkeep', ''), s3deploy.Source.data('audio/.gitkeep', ''), s3deploy.Source.data('voice-samples/.gitkeep', ''), s3deploy.Source.data('long-form/.gitkeep', '')],
      destinationBucket: audioStorageBucket,
    });

    // IAM role for Lambda function with least privilege access
    const pollyProcessorRole = new iam.Role(this, 'PollyProcessorRole', {
      roleName: `PollyProcessorRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for Lambda function to process text-to-speech with Polly',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        PollyAccess: new iam.PolicyDocument({
          statements: [
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
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
              ],
              resources: [
                audioStorageBucket.bucketArn,
                `${audioStorageBucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
      },
    });

    // Lambda function for batch text-to-speech processing
    const pollyBatchProcessor = new lambda.Function(this, 'PollyBatchProcessor', {
      functionName: `polly-batch-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'lambda_function.lambda_handler',
      role: pollyProcessorRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      environment: {
        BUCKET_NAME: audioStorageBucket.bucketName,
        DEFAULT_VOICE_ID: 'Joanna',
        DEFAULT_ENGINE: 'neural',
        OUTPUT_FORMAT: 'mp3',
      },
      description: 'Lambda function for processing text-to-speech requests using Amazon Polly',
      code: lambda.Code.fromInline(`
import boto3
import json
import os
import logging
from urllib.parse import unquote_plus
from typing import Dict, Any, Optional
import uuid
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
polly_client = boto3.client('polly')
s3_client = boto3.client('s3')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for processing text-to-speech requests.
    
    Supports both S3-triggered events and direct invocations.
    Processes text content and generates speech using Amazon Polly.
    """
    try:
        bucket_name = os.environ['BUCKET_NAME']
        default_voice = os.environ.get('DEFAULT_VOICE_ID', 'Joanna')
        default_engine = os.environ.get('DEFAULT_ENGINE', 'neural')
        output_format = os.environ.get('OUTPUT_FORMAT', 'mp3')
        
        # Handle different event types
        if 'Records' in event:
            # S3 event trigger
            return handle_s3_event(event, bucket_name, default_voice, default_engine, output_format)
        else:
            # Direct invocation
            return handle_direct_invocation(event, context, bucket_name, default_voice, default_engine, output_format)
            
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def handle_s3_event(event: Dict[str, Any], bucket_name: str, default_voice: str, 
                   default_engine: str, output_format: str) -> Dict[str, Any]:
    """Handle S3 event-triggered processing."""
    results = []
    
    for record in event['Records']:
        try:
            # Extract S3 object information
            source_bucket = record['s3']['bucket']['name']
            object_key = unquote_plus(record['s3']['object']['key'])
            
            logger.info(f"Processing S3 object: s3://{source_bucket}/{object_key}")
            
            # Skip if not a text file
            if not object_key.lower().endswith(('.txt', '.ssml')):
                logger.info(f"Skipping non-text file: {object_key}")
                continue
            
            # Read text content from S3
            response = s3_client.get_object(Bucket=source_bucket, Key=object_key)
            text_content = response['Body'].read().decode('utf-8')
            
            # Determine text type (SSML or plain text)
            text_type = 'ssml' if object_key.lower().endswith('.ssml') else 'text'
            
            # Process the content
            audio_url = synthesize_and_store(
                text_content, bucket_name, default_voice, default_engine, 
                output_format, text_type, object_key
            )
            
            results.append({
                'source_object': object_key,
                'audio_url': audio_url,
                'characters_processed': len(text_content),
                'status': 'success'
            })
            
        except Exception as e:
            logger.error(f"Error processing S3 record: {str(e)}")
            results.append({
                'source_object': object_key if 'object_key' in locals() else 'unknown',
                'status': 'error',
                'error': str(e)
            })
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'S3 batch processing completed',
            'results': results,
            'processed_count': len(results)
        })
    }

def handle_direct_invocation(event: Dict[str, Any], context: Any, bucket_name: str,
                           default_voice: str, default_engine: str, output_format: str) -> Dict[str, Any]:
    """Handle direct Lambda invocation."""
    text_content = event.get('text', 'Hello from Amazon Polly! This is a test of the text-to-speech service.')
    voice_id = event.get('voice_id', default_voice)
    engine = event.get('engine', default_engine)
    text_type = event.get('text_type', 'text')
    
    logger.info(f"Processing direct invocation with voice: {voice_id}, engine: {engine}")
    
    # Generate unique output key
    output_key = f"audio/direct-{context.aws_request_id}.{output_format}"
    
    # Synthesize and store audio
    audio_url = synthesize_and_store(
        text_content, bucket_name, voice_id, engine, output_format, text_type, output_key
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Speech synthesis completed successfully',
            'audio_url': audio_url,
            'characters_processed': len(text_content),
            'voice_used': voice_id,
            'engine_used': engine,
            'request_id': context.aws_request_id
        })
    }

def synthesize_and_store(text_content: str, bucket_name: str, voice_id: str, 
                        engine: str, output_format: str, text_type: str, 
                        output_key: Optional[str] = None) -> str:
    """
    Synthesize speech using Amazon Polly and store in S3.
    
    Args:
        text_content: Text to synthesize
        bucket_name: S3 bucket for storage
        voice_id: Polly voice ID
        engine: Polly engine type
        output_format: Audio output format
        text_type: 'text' or 'ssml'
        output_key: S3 key for output file
    
    Returns:
        S3 URL of generated audio file
    """
    # Generate output key if not provided
    if not output_key:
        timestamp = datetime.utcnow().strftime('%Y%m%d-%H%M%S')
        file_id = str(uuid.uuid4())[:8]
        output_key = f"audio/{timestamp}-{file_id}.{output_format}"
    
    # Prepare Polly synthesis parameters
    synthesis_params = {
        'Text': text_content,
        'OutputFormat': output_format,
        'VoiceId': voice_id,
        'Engine': engine
    }
    
    # Add text type if SSML
    if text_type == 'ssml':
        synthesis_params['TextType'] = 'ssml'
    
    logger.info(f"Synthesizing speech with params: {synthesis_params}")
    
    # Call Polly to synthesize speech
    response = polly_client.synthesize_speech(**synthesis_params)
    
    # Read audio stream
    audio_data = response['AudioStream'].read()
    
    # Store audio file in S3
    s3_client.put_object(
        Bucket=bucket_name,
        Key=output_key,
        Body=audio_data,
        ContentType=f'audio/{output_format}',
        Metadata={
            'voice-id': voice_id,
            'engine': engine,
            'text-type': text_type,
            'character-count': str(len(text_content)),
            'generated-timestamp': datetime.utcnow().isoformat()
        }
    )
    
    # Return S3 URL
    audio_url = f"s3://{bucket_name}/{output_key}"
    logger.info(f"Audio file stored at: {audio_url}")
    
    return audio_url

def get_available_voices(language_code: Optional[str] = None) -> Dict[str, Any]:
    """Get available Polly voices, optionally filtered by language."""
    try:
        params = {}
        if language_code:
            params['LanguageCode'] = language_code
            
        response = polly_client.describe_voices(**params)
        return response['Voices']
    except Exception as e:
        logger.error(f"Error retrieving voices: {str(e)}")
        return []
      `),
    });

    // S3 event notification to trigger Lambda for text file uploads
    audioStorageBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(pollyBatchProcessor),
      { prefix: 'input/', suffix: '.txt' }
    );

    // S3 event notification to trigger Lambda for SSML file uploads
    audioStorageBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(pollyBatchProcessor),
      { prefix: 'input/', suffix: '.ssml' }
    );

    // CloudFront distribution for global audio delivery
    const audioDeliveryDistribution = new cloudfront.Distribution(this, 'AudioDeliveryDistribution', {
      comment: 'CloudFront distribution for Polly-generated audio files',
      defaultBehavior: {
        origin: new origins.S3Origin(audioStorageBucket, {
          originAccessIdentity: new cloudfront.OriginAccessIdentity(this, 'OAI', {
            comment: 'OAI for Polly audio bucket access',
          }),
        }),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
      },
      priceClass: cloudfront.PriceClass.PRICE_CLASS_100,
      enableLogging: true,
      logBucket: new s3.Bucket(this, 'CloudFrontLogsBucket', {
        bucketName: `polly-cloudfront-logs-${uniqueSuffix}`,
        lifecycleRules: [
          {
            id: 'DeleteOldLogs',
            expiration: cdk.Duration.days(90),
          },
        ],
        removalPolicy: RemovalPolicy.DESTROY,
        autoDeleteObjects: true,
      }),
      logFilePrefix: 'cloudfront-logs/',
    });

    // Lambda function for voice management and synthesis tasks
    const voiceManagerFunction = new lambda.Function(this, 'VoiceManagerFunction', {
      functionName: `polly-voice-manager-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'voice_manager.lambda_handler',
      role: pollyProcessorRole,
      timeout: cdk.Duration.minutes(2),
      memorySize: 256,
      environment: {
        BUCKET_NAME: audioStorageBucket.bucketName,
      },
      description: 'Lambda function for managing Polly voices and synthesis tasks',
      code: lambda.Code.fromInline(`
import boto3
import json
import os
import logging
from typing import Dict, Any, List, Optional
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
polly_client = boto3.client('polly')
s3_client = boto3.client('s3')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Voice management and utility Lambda handler.
    
    Supports operations:
    - list_voices: Get available Polly voices
    - create_lexicon: Create custom pronunciation lexicon
    - start_long_form_task: Start long-form synthesis task
    - get_synthesis_tasks: Get status of synthesis tasks
    """
    try:
        operation = event.get('operation', 'list_voices')
        
        if operation == 'list_voices':
            return handle_list_voices(event)
        elif operation == 'create_lexicon':
            return handle_create_lexicon(event)
        elif operation == 'start_long_form_task':
            return handle_start_long_form_task(event)
        elif operation == 'get_synthesis_tasks':
            return handle_get_synthesis_tasks(event)
        elif operation == 'create_voice_samples':
            return handle_create_voice_samples(event)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': f'Unknown operation: {operation}',
                    'supported_operations': ['list_voices', 'create_lexicon', 'start_long_form_task', 'get_synthesis_tasks', 'create_voice_samples']
                })
            }
            
    except Exception as e:
        logger.error(f"Error in voice manager: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def handle_list_voices(event: Dict[str, Any]) -> Dict[str, Any]:
    """List available Polly voices with filtering options."""
    try:
        language_code = event.get('language_code')
        engine = event.get('engine')
        
        params = {}
        if language_code:
            params['LanguageCode'] = language_code
            
        response = polly_client.describe_voices(**params)
        voices = response['Voices']
        
        # Filter by engine if specified
        if engine:
            voices = [v for v in voices if engine in v.get('SupportedEngines', [])]
        
        # Group voices by language and engine
        grouped_voices = {}
        for voice in voices:
            lang = voice['LanguageCode']
            if lang not in grouped_voices:
                grouped_voices[lang] = {'neural': [], 'standard': [], 'long-form': [], 'generative': []}
            
            for supported_engine in voice.get('SupportedEngines', []):
                if supported_engine in grouped_voices[lang]:
                    grouped_voices[lang][supported_engine].append({
                        'id': voice['Id'],
                        'name': voice['Name'],
                        'gender': voice['Gender']
                    })
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'voices_by_language': grouped_voices,
                'total_voices': len(voices),
                'filtered_by': {
                    'language_code': language_code,
                    'engine': engine
                }
            })
        }
        
    except Exception as e:
        logger.error(f"Error listing voices: {str(e)}")
        raise

def handle_create_lexicon(event: Dict[str, Any]) -> Dict[str, Any]:
    """Create or update a custom pronunciation lexicon."""
    try:
        lexicon_name = event.get('lexicon_name', 'DefaultLexicon')
        lexicon_content = event.get('lexicon_content')
        
        if not lexicon_content:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'lexicon_content is required'})
            }
        
        # Put lexicon
        polly_client.put_lexicon(
            Name=lexicon_name,
            Content=lexicon_content
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Lexicon {lexicon_name} created successfully',
                'lexicon_name': lexicon_name
            })
        }
        
    except Exception as e:
        logger.error(f"Error creating lexicon: {str(e)}")
        raise

def handle_start_long_form_task(event: Dict[str, Any]) -> Dict[str, Any]:
    """Start a long-form synthesis task for large content."""
    try:
        bucket_name = os.environ['BUCKET_NAME']
        
        text_content = event.get('text')
        voice_id = event.get('voice_id', 'Joanna')
        output_format = event.get('output_format', 'mp3')
        output_key_prefix = event.get('output_key_prefix', 'long-form/')
        
        if not text_content:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'text content is required'})
            }
        
        # Start speech synthesis task
        response = polly_client.start_speech_synthesis_task(
            Text=text_content,
            OutputFormat=output_format,
            VoiceId=voice_id,
            Engine='long-form',
            OutputS3BucketName=bucket_name,
            OutputS3KeyPrefix=output_key_prefix
        )
        
        task_id = response['SynthesisTask']['TaskId']
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Long-form synthesis task started',
                'task_id': task_id,
                'task_status': response['SynthesisTask']['TaskStatus'],
                'output_uri': response['SynthesisTask'].get('OutputUri')
            })
        }
        
    except Exception as e:
        logger.error(f"Error starting long-form task: {str(e)}")
        raise

def handle_get_synthesis_tasks(event: Dict[str, Any]) -> Dict[str, Any]:
    """Get status of synthesis tasks."""
    try:
        task_id = event.get('task_id')
        
        params = {}
        if task_id:
            params['TaskId'] = task_id
            
        response = polly_client.list_speech_synthesis_tasks(**params)
        
        tasks = []
        for task in response['SynthesisTasks']:
            tasks.append({
                'task_id': task['TaskId'],
                'status': task['TaskStatus'],
                'creation_time': task['CreationTime'].isoformat(),
                'voice_id': task['VoiceId'],
                'output_uri': task.get('OutputUri'),
                'task_status_reason': task.get('TaskStatusReason')
            })
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'synthesis_tasks': tasks,
                'task_count': len(tasks)
            })
        }
        
    except Exception as e:
        logger.error(f"Error getting synthesis tasks: {str(e)}")
        raise

def handle_create_voice_samples(event: Dict[str, Any]) -> Dict[str, Any]:
    """Create voice comparison samples."""
    try:
        bucket_name = os.environ['BUCKET_NAME']
        sample_text = event.get('sample_text', 'This is a voice comparison sample.')
        voices = event.get('voices', ['Joanna', 'Matthew', 'Ivy', 'Kevin'])
        output_format = event.get('output_format', 'mp3')
        
        results = []
        
        for voice_id in voices:
            try:
                # Synthesize speech
                response = polly_client.synthesize_speech(
                    Text=sample_text,
                    OutputFormat=output_format,
                    VoiceId=voice_id,
                    Engine='neural'
                )
                
                # Generate S3 key
                output_key = f"voice-samples/voice_{voice_id}.{output_format}"
                
                # Store in S3
                s3_client.put_object(
                    Bucket=bucket_name,
                    Key=output_key,
                    Body=response['AudioStream'].read(),
                    ContentType=f'audio/{output_format}',
                    Metadata={
                        'voice-id': voice_id,
                        'sample-text': sample_text,
                        'generated-timestamp': datetime.utcnow().isoformat()
                    }
                )
                
                results.append({
                    'voice_id': voice_id,
                    'status': 'success',
                    'audio_url': f's3://{bucket_name}/{output_key}'
                })
                
            except Exception as e:
                logger.error(f"Error creating sample for voice {voice_id}: {str(e)}")
                results.append({
                    'voice_id': voice_id,
                    'status': 'error',
                    'error': str(e)
                })
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Voice samples created',
                'results': results,
                'sample_text': sample_text
            })
        }
        
    except Exception as e:
        logger.error(f"Error creating voice samples: {str(e)}")
        raise
      `),
    });

    // CloudWatch log groups for better log management
    new logs.LogGroup(this, 'PollyBatchProcessorLogGroup', {
      logGroupName: `/aws/lambda/${pollyBatchProcessor.functionName}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    new logs.LogGroup(this, 'VoiceManagerLogGroup', {
      logGroupName: `/aws/lambda/${voiceManagerFunction.functionName}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // Output key information for users
    new cdk.CfnOutput(this, 'AudioStorageBucketName', {
      value: audioStorageBucket.bucketName,
      description: 'S3 bucket name for storing audio files and input text',
      exportName: `${this.stackName}-AudioStorageBucket`,
    });

    new cdk.CfnOutput(this, 'PollyBatchProcessorFunctionName', {
      value: pollyBatchProcessor.functionName,
      description: 'Lambda function name for batch text-to-speech processing',
      exportName: `${this.stackName}-PollyBatchProcessor`,
    });

    new cdk.CfnOutput(this, 'VoiceManagerFunctionName', {
      value: voiceManagerFunction.functionName,
      description: 'Lambda function name for voice management operations',
      exportName: `${this.stackName}-VoiceManager`,
    });

    new cdk.CfnOutput(this, 'CloudFrontDistributionDomain', {
      value: audioDeliveryDistribution.distributionDomainName,
      description: 'CloudFront distribution domain for global audio delivery',
      exportName: `${this.stackName}-CloudFrontDomain`,
    });

    new cdk.CfnOutput(this, 'CloudFrontDistributionId', {
      value: audioDeliveryDistribution.distributionId,
      description: 'CloudFront distribution ID',
      exportName: `${this.stackName}-CloudFrontDistributionId`,
    });

    // Add tags to all resources for better organization
    cdk.Tags.of(this).add('Project', 'TextToSpeechSolutions');
    cdk.Tags.of(this).add('Service', 'AmazonPolly');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('Cost-Center', 'Innovation');
  }
}

// Create the CDK application
const app = new cdk.App();

// Deploy the stack with environment-specific settings
new TextToSpeechPollyStack(app, 'TextToSpeechPollyStack', {
  description: 'CDK Stack for implementing comprehensive text-to-speech solutions with Amazon Polly, S3, Lambda, and CloudFront',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'TextToSpeechSolutions',
    Service: 'AmazonPolly',
    IaC: 'CDK-TypeScript',
  },
});

// Synthesize the CloudFormation template
app.synth();