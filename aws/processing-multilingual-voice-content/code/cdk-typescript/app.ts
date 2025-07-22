#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as stepfunctions from 'aws-cdk-lib/aws-stepfunctions';
import * as sfnTasks from 'aws-cdk-lib/aws-stepfunctions-tasks';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Multi-Language Voice Processing Pipeline Stack
 * 
 * This stack deploys a comprehensive voice processing solution using:
 * - Amazon Transcribe for speech-to-text conversion and language detection
 * - Amazon Translate for multi-language translation
 * - Amazon Polly for text-to-speech synthesis
 * - AWS Step Functions for workflow orchestration
 * - AWS Lambda for processing logic
 * - Amazon S3 for audio file storage
 * - Amazon DynamoDB for job tracking
 */
export class VoiceProcessingPipelineStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.addr.substring(0, 8);

    // =================
    // S3 BUCKETS
    // =================

    // Input bucket for audio files
    const inputBucket = new s3.Bucket(this, 'InputBucket', {
      bucketName: `voice-input-${uniqueSuffix}`,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteIncompleteUploads',
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(1),
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
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Output bucket for processed files
    const outputBucket = new s3.Bucket(this, 'OutputBucket', {
      bucketName: `voice-output-${uniqueSuffix}`,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
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
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // =================
    // DYNAMODB TABLE
    // =================

    // Table for tracking job progress and metadata
    const jobsTable = new dynamodb.Table(this, 'JobsTable', {
      tableName: `voice-pipeline-jobs-${uniqueSuffix}`,
      partitionKey: {
        name: 'JobId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Global Secondary Index for querying by status
    jobsTable.addGlobalSecondaryIndex({
      indexName: 'StatusIndex',
      partitionKey: {
        name: 'Status',
        type: dynamodb.AttributeType.STRING,
      },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // =================
    // IAM ROLES
    // =================

    // Lambda execution role with necessary permissions
    const lambdaExecutionRole = new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        VoiceProcessingPolicy: new iam.PolicyDocument({
          statements: [
            // S3 permissions
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
            // DynamoDB permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:GetItem',
                'dynamodb:PutItem',
                'dynamodb:UpdateItem',
                'dynamodb:Query',
                'dynamodb:Scan',
              ],
              resources: [
                jobsTable.tableArn,
                `${jobsTable.tableArn}/index/*`,
              ],
            }),
            // Transcribe permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'transcribe:StartTranscriptionJob',
                'transcribe:GetTranscriptionJob',
                'transcribe:ListTranscriptionJobs',
                'transcribe:GetVocabulary',
              ],
              resources: ['*'],
            }),
            // Translate permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'translate:TranslateText',
                'translate:GetTerminology',
                'translate:ListTerminologies',
              ],
              resources: ['*'],
            }),
            // Polly permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'polly:SynthesizeSpeech',
                'polly:DescribeVoices',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Step Functions execution role
    const stepFunctionsRole = new iam.Role(this, 'StepFunctionsRole', {
      assumedBy: new iam.ServicePrincipal('states.amazonaws.com'),
      inlinePolicies: {
        StepFunctionsPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['lambda:InvokeFunction'],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // =================
    // LAMBDA FUNCTIONS
    // =================

    // Language Detection Lambda Function
    const languageDetectorFunction = new lambda.Function(this, 'LanguageDetectorFunction', {
      functionName: `voice-pipeline-language-detector-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      environment: {
        JOBS_TABLE: jobsTable.tableName,
        INPUT_BUCKET: inputBucket.bucketName,
        OUTPUT_BUCKET: outputBucket.bucketName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
from datetime import datetime

transcribe = boto3.client('transcribe')
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    bucket = event['bucket']
    key = event['key']
    job_id = event.get('job_id', str(uuid.uuid4()))
    
    table = dynamodb.Table(event['jobs_table'])
    
    try:
        # Update job status
        table.put_item(
            Item={
                'JobId': job_id,
                'Status': 'LANGUAGE_DETECTION',
                'InputFile': f"s3://{bucket}/{key}",
                'Timestamp': int(datetime.now().timestamp()),
                'Stage': 'language_detection'
            }
        )
        
        # Start language identification job
        job_name = f"lang-detect-{job_id}"
        
        transcribe.start_transcription_job(
            TranscriptionJobName=job_name,
            Media={'MediaFileUri': f"s3://{bucket}/{key}"},
            IdentifyLanguage=True,
            OutputBucketName=bucket,
            OutputKey=f"language-detection/{job_id}/"
        )
        
        return {
            'statusCode': 200,
            'job_id': job_id,
            'transcribe_job_name': job_name,
            'bucket': bucket,
            'key': key,
            'stage': 'language_detection'
        }
        
    except Exception as e:
        table.put_item(
            Item={
                'JobId': job_id,
                'Status': 'FAILED',
                'Error': str(e),
                'Timestamp': int(datetime.now().timestamp()),
                'Stage': 'language_detection'
            }
        )
        
        return {
            'statusCode': 500,
            'error': str(e),
            'job_id': job_id
        }
      `),
    });

    // Transcription Processor Lambda Function
    const transcriptionProcessorFunction = new lambda.Function(this, 'TranscriptionProcessorFunction', {
      functionName: `voice-pipeline-transcription-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      environment: {
        JOBS_TABLE: jobsTable.tableName,
        INPUT_BUCKET: inputBucket.bucketName,
        OUTPUT_BUCKET: outputBucket.bucketName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
from datetime import datetime

transcribe = boto3.client('transcribe')
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    job_id = event['job_id']
    bucket = event['bucket']
    key = event['key']
    detected_language = event.get('detected_language', 'en-US')
    
    table = dynamodb.Table(event['jobs_table'])
    
    try:
        # Update job status
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #stage = :stage, DetectedLanguage = :lang',
            ExpressionAttributeNames={'#status': 'Status', '#stage': 'Stage'},
            ExpressionAttributeValues={
                ':status': 'TRANSCRIBING',
                ':stage': 'transcription',
                ':lang': detected_language
            }
        )
        
        # Configure transcription based on language
        transcribe_config = {
            'TranscriptionJobName': f"transcribe-{job_id}",
            'Media': {'MediaFileUri': f"s3://{bucket}/{key}"},
            'OutputBucketName': bucket,
            'OutputKey': f"transcriptions/{job_id}/",
            'LanguageCode': detected_language
        }
        
        # Add language-specific settings
        if detected_language.startswith('en'):
            transcribe_config['Settings'] = {
                'ShowSpeakerLabels': True,
                'MaxSpeakerLabels': 10,
                'ShowAlternatives': True,
                'MaxAlternatives': 3
            }
        
        # Start transcription job
        transcribe.start_transcription_job(**transcribe_config)
        
        return {
            'statusCode': 200,
            'job_id': job_id,
            'transcribe_job_name': f"transcribe-{job_id}",
            'detected_language': detected_language,
            'bucket': bucket,
            'stage': 'transcription'
        }
        
    except Exception as e:
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #error = :error',
            ExpressionAttributeNames={'#status': 'Status'},
            ExpressionAttributeValues={
                ':status': 'FAILED',
                ':error': str(e)
            }
        )
        
        return {
            'statusCode': 500,
            'error': str(e),
            'job_id': job_id
        }
      `),
    });

    // Translation Processor Lambda Function
    const translationProcessorFunction = new lambda.Function(this, 'TranslationProcessorFunction', {
      functionName: `voice-pipeline-translation-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      environment: {
        JOBS_TABLE: jobsTable.tableName,
        INPUT_BUCKET: inputBucket.bucketName,
        OUTPUT_BUCKET: outputBucket.bucketName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
from datetime import datetime

translate = boto3.client('translate')
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    job_id = event['job_id']
    bucket = event['bucket']
    source_language = event['source_language']
    target_languages = event.get('target_languages', ['es', 'fr', 'de', 'pt'])
    transcription_uri = event['transcription_uri']
    
    table = dynamodb.Table(event['jobs_table'])
    
    try:
        # Update job status
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #stage = :stage',
            ExpressionAttributeNames={'#status': 'Status', '#stage': 'Stage'},
            ExpressionAttributeValues={
                ':status': 'TRANSLATING',
                ':stage': 'translation'
            }
        )
        
        # Download transcription results
        transcript_key = transcription_uri.split(f"s3://{bucket}/")[1]
        transcription_obj = s3.get_object(Bucket=bucket, Key=transcript_key)
        transcription_data = json.loads(transcription_obj['Body'].read().decode('utf-8'))
        
        # Extract transcript text
        transcript = transcription_data['results']['transcripts'][0]['transcript']
        
        # Map language codes
        source_lang_code = map_transcribe_to_translate_language(source_language)
        
        translations = {}
        
        # Translate to each target language
        for target_lang in target_languages:
            if target_lang != source_lang_code:
                try:
                    result = translate.translate_text(
                        Text=transcript,
                        SourceLanguageCode=source_lang_code,
                        TargetLanguageCode=target_lang
                    )
                    
                    translations[target_lang] = {
                        'translated_text': result['TranslatedText'],
                        'source_language': source_lang_code,
                        'target_language': target_lang
                    }
                    
                except Exception as e:
                    print(f"Translation failed for {target_lang}: {str(e)}")
                    translations[target_lang] = {
                        'error': str(e),
                        'source_language': source_lang_code,
                        'target_language': target_lang
                    }
        
        # Store translation results
        translations_key = f"translations/{job_id}/translations.json"
        s3.put_object(
            Bucket=bucket,
            Key=translations_key,
            Body=json.dumps({
                'original_text': transcript,
                'source_language': source_lang_code,
                'translations': translations,
                'timestamp': datetime.now().isoformat()
            }),
            ContentType='application/json'
        )
        
        return {
            'statusCode': 200,
            'job_id': job_id,
            'source_language': source_lang_code,
            'translations': translations,
            'translations_uri': translations_key,
            'stage': 'translation'
        }
        
    except Exception as e:
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #error = :error',
            ExpressionAttributeNames={'#status': 'Status'},
            ExpressionAttributeValues={
                ':status': 'FAILED',
                ':error': str(e)
            }
        )
        
        return {
            'statusCode': 500,
            'error': str(e),
            'job_id': job_id
        }

def map_transcribe_to_translate_language(transcribe_lang):
    # Map Transcribe language codes to Translate language codes
    mapping = {
        'en-US': 'en', 'en-GB': 'en', 'en-AU': 'en',
        'es-US': 'es', 'es-ES': 'es',
        'fr-FR': 'fr', 'fr-CA': 'fr',
        'de-DE': 'de', 'it-IT': 'it',
        'pt-BR': 'pt', 'pt-PT': 'pt',
        'ja-JP': 'ja', 'ko-KR': 'ko',
        'zh-CN': 'zh', 'zh-TW': 'zh-TW',
        'ar-AE': 'ar', 'ar-SA': 'ar',
        'hi-IN': 'hi', 'ru-RU': 'ru',
        'nl-NL': 'nl', 'sv-SE': 'sv'
    }
    return mapping.get(transcribe_lang, transcribe_lang.split('-')[0])
      `),
    });

    // Speech Synthesizer Lambda Function
    const speechSynthesizerFunction = new lambda.Function(this, 'SpeechSynthesizerFunction', {
      functionName: `voice-pipeline-speech-synthesizer-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      environment: {
        JOBS_TABLE: jobsTable.tableName,
        INPUT_BUCKET: inputBucket.bucketName,
        OUTPUT_BUCKET: outputBucket.bucketName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
from datetime import datetime
import re

polly = boto3.client('polly')
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    job_id = event['job_id']
    bucket = event['bucket']
    translations = event['translations']
    
    table = dynamodb.Table(event['jobs_table'])
    
    try:
        # Update job status
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #stage = :stage',
            ExpressionAttributeNames={'#status': 'Status', '#stage': 'Stage'},
            ExpressionAttributeValues={
                ':status': 'SYNTHESIZING',
                ':stage': 'speech_synthesis'
            }
        )
        
        audio_outputs = {}
        
        # Process each translation
        for target_lang, translation_data in translations.items():
            if 'translated_text' in translation_data:
                try:
                    # Select appropriate voice for language
                    voice_id = select_voice_for_language(target_lang)
                    
                    # Prepare text for synthesis
                    text_to_synthesize = prepare_text_for_synthesis(
                        translation_data['translated_text']
                    )
                    
                    # Synthesize speech
                    synthesis_response = polly.synthesize_speech(
                        Text=text_to_synthesize,
                        VoiceId=voice_id,
                        OutputFormat='mp3',
                        Engine='neural' if supports_neural_voice(voice_id) else 'standard',
                        TextType='ssml' if text_to_synthesize.startswith('<speak>') else 'text'
                    )
                    
                    # Save audio to S3
                    audio_key = f"audio-output/{job_id}/{target_lang}.mp3"
                    s3.put_object(
                        Bucket=bucket,
                        Key=audio_key,
                        Body=synthesis_response['AudioStream'].read(),
                        ContentType='audio/mpeg'
                    )
                    
                    audio_outputs[target_lang] = {
                        'audio_uri': f"s3://{bucket}/{audio_key}",
                        'voice_id': voice_id,
                        'text_length': len(translation_data['translated_text']),
                        'audio_format': 'mp3'
                    }
                    
                except Exception as e:
                    print(f"Speech synthesis failed for {target_lang}: {str(e)}")
                    audio_outputs[target_lang] = {
                        'error': str(e)
                    }
        
        # Update job with final results
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #stage = :stage, AudioOutputs = :outputs',
            ExpressionAttributeNames={'#status': 'Status', '#stage': 'Stage'},
            ExpressionAttributeValues={
                ':status': 'COMPLETED',
                ':stage': 'completed',
                ':outputs': audio_outputs
            }
        )
        
        return {
            'statusCode': 200,
            'job_id': job_id,
            'audio_outputs': audio_outputs,
            'stage': 'completed'
        }
        
    except Exception as e:
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #error = :error',
            ExpressionAttributeNames={'#status': 'Status'},
            ExpressionAttributeValues={
                ':status': 'FAILED',
                ':error': str(e)
            }
        )
        
        return {
            'statusCode': 500,
            'error': str(e),
            'job_id': job_id
        }

def select_voice_for_language(language_code):
    # Map language codes to appropriate Polly voices
    voice_mapping = {
        'en': 'Joanna',  # English - Neural voice
        'es': 'Lupe',    # Spanish - Neural voice
        'fr': 'Lea',     # French - Neural voice
        'de': 'Vicki',   # German - Neural voice
        'it': 'Bianca',  # Italian - Neural voice
        'pt': 'Camila',  # Portuguese - Neural voice
        'ja': 'Takumi',  # Japanese - Neural voice
        'ko': 'Seoyeon', # Korean - Standard voice
        'zh': 'Zhiyu',   # Chinese - Neural voice
        'ar': 'Zeina',   # Arabic - Standard voice
        'hi': 'Aditi',   # Hindi - Standard voice
        'ru': 'Tatyana', # Russian - Standard voice
        'nl': 'Lotte',   # Dutch - Standard voice
        'sv': 'Astrid'   # Swedish - Standard voice
    }
    return voice_mapping.get(language_code, 'Joanna')

def supports_neural_voice(voice_id):
    # Neural voices available in Polly
    neural_voices = [
        'Joanna', 'Matthew', 'Ivy', 'Justin', 'Kendra', 'Kimberly', 'Salli',
        'Joey', 'Lupe', 'Lucia', 'Lea', 'Vicki', 'Bianca', 'Camila',
        'Takumi', 'Zhiyu', 'Ruth', 'Stephen'
    ]
    return voice_id in neural_voices

def prepare_text_for_synthesis(text):
    # Add basic SSML for better speech quality
    if len(text) > 1000:
        # For longer texts, add pauses at sentence boundaries
        text = re.sub(r'\\.(\s+)', r'.<break time="500ms"/>\\1', text)
        text = re.sub(r'!(\s+)', r'!<break time="500ms"/>\\1', text)
        text = re.sub(r'\\?(\s+)', r'?<break time="500ms"/>\\1', text)
        text = f'<speak>{text}</speak>'
    
    return text
      `),
    });

    // Job Status Checker Lambda Function
    const jobStatusCheckerFunction = new lambda.Function(this, 'JobStatusCheckerFunction', {
      functionName: `voice-pipeline-job-status-checker-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        JOBS_TABLE: jobsTable.tableName,
        INPUT_BUCKET: inputBucket.bucketName,
        OUTPUT_BUCKET: outputBucket.bucketName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3

transcribe = boto3.client('transcribe')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    job_name = event['transcribe_job_name']
    job_type = event.get('job_type', 'transcription')
    
    try:
        response = transcribe.get_transcription_job(
            TranscriptionJobName=job_name
        )
        
        job_status = response['TranscriptionJob']['TranscriptionJobStatus']
        
        result = {
            'statusCode': 200,
            'job_name': job_name,
            'job_status': job_status,
            'is_complete': job_status in ['COMPLETED', 'FAILED']
        }
        
        if job_status == 'COMPLETED':
            if job_type == 'language_detection':
                # Extract detected language
                language_code = response['TranscriptionJob'].get('LanguageCode')
                result['detected_language'] = language_code
            else:
                # Extract transcription results location
                transcript_uri = response['TranscriptionJob']['Transcript']['TranscriptFileUri']
                result['transcript_uri'] = transcript_uri
                
                # Extract detected language for transcription jobs
                language_code = response['TranscriptionJob'].get('LanguageCode')
                result['source_language'] = language_code
        
        elif job_status == 'FAILED':
            result['failure_reason'] = response['TranscriptionJob'].get('FailureReason', 'Unknown error')
        
        return result
        
    except Exception as e:
        return {
            'statusCode': 500,
            'error': str(e),
            'job_name': job_name
        }
      `),
    });

    // =================
    // STEP FUNCTIONS WORKFLOW
    // =================

    // Define Step Functions tasks
    const initializeJobTask = new stepfunctions.Pass(this, 'InitializeJob', {
      parameters: {
        'bucket.$': '$.bucket',
        'key.$': '$.key',
        'job_id.$': '$.job_id',
        'jobs_table': jobsTable.tableName,
        'target_languages.$': '$.target_languages',
      },
    });

    const detectLanguageTask = new sfnTasks.LambdaInvoke(this, 'DetectLanguage', {
      lambdaFunction: languageDetectorFunction,
      resultPath: '$.language_detection_result',
    });

    const waitForLanguageDetection = new stepfunctions.Wait(this, 'WaitForLanguageDetection', {
      time: stepfunctions.WaitTime.duration(cdk.Duration.seconds(30)),
    });

    const checkLanguageDetectionStatusTask = new sfnTasks.LambdaInvoke(this, 'CheckLanguageDetectionStatus', {
      lambdaFunction: jobStatusCheckerFunction,
      payload: stepfunctions.TaskInput.fromObject({
        'transcribe_job_name.$': '$.language_detection_result.Payload.transcribe_job_name',
        'job_type': 'language_detection',
      }),
      resultPath: '$.language_status',
    });

    const isLanguageDetectionComplete = new stepfunctions.Choice(this, 'IsLanguageDetectionComplete')
      .when(
        stepfunctions.Condition.booleanEquals('$.language_status.Payload.is_complete', true),
        new sfnTasks.LambdaInvoke(this, 'ProcessTranscription', {
          lambdaFunction: transcriptionProcessorFunction,
          payload: stepfunctions.TaskInput.fromObject({
            'job_id.$': '$.job_id',
            'bucket.$': '$.bucket',
            'key.$': '$.key',
            'detected_language.$': '$.language_status.Payload.detected_language',
            'jobs_table': jobsTable.tableName,
          }),
          resultPath: '$.transcription_result',
        })
      )
      .otherwise(waitForLanguageDetection);

    const waitForTranscription = new stepfunctions.Wait(this, 'WaitForTranscription', {
      time: stepfunctions.WaitTime.duration(cdk.Duration.seconds(60)),
    });

    const checkTranscriptionStatusTask = new sfnTasks.LambdaInvoke(this, 'CheckTranscriptionStatus', {
      lambdaFunction: jobStatusCheckerFunction,
      payload: stepfunctions.TaskInput.fromObject({
        'transcribe_job_name.$': '$.transcription_result.Payload.transcribe_job_name',
        'job_type': 'transcription',
      }),
      resultPath: '$.transcription_status',
    });

    const isTranscriptionComplete = new stepfunctions.Choice(this, 'IsTranscriptionComplete')
      .when(
        stepfunctions.Condition.booleanEquals('$.transcription_status.Payload.is_complete', true),
        new sfnTasks.LambdaInvoke(this, 'ProcessTranslation', {
          lambdaFunction: translationProcessorFunction,
          payload: stepfunctions.TaskInput.fromObject({
            'job_id.$': '$.job_id',
            'bucket.$': '$.bucket',
            'source_language.$': '$.transcription_status.Payload.source_language',
            'target_languages.$': '$.target_languages',
            'transcription_uri.$': '$.transcription_status.Payload.transcript_uri',
            'jobs_table': jobsTable.tableName,
          }),
          resultPath: '$.translation_result',
        })
      )
      .otherwise(waitForTranscription);

    const synthesizeSpeechTask = new sfnTasks.LambdaInvoke(this, 'SynthesizeSpeech', {
      lambdaFunction: speechSynthesizerFunction,
      payload: stepfunctions.TaskInput.fromObject({
        'job_id.$': '$.job_id',
        'bucket.$': '$.bucket',
        'translations.$': '$.translation_result.Payload.translations',
        'jobs_table': jobsTable.tableName,
      }),
      resultPath: '$.synthesis_result',
    });

    // Define workflow chain
    waitForLanguageDetection.next(checkLanguageDetectionStatusTask);
    checkLanguageDetectionStatusTask.next(isLanguageDetectionComplete);
    
    waitForTranscription.next(checkTranscriptionStatusTask);
    checkTranscriptionStatusTask.next(isTranscriptionComplete);

    const definition = initializeJobTask
      .next(detectLanguageTask)
      .next(waitForLanguageDetection);

    // Create Step Functions state machine
    const stateMachine = new stepfunctions.StateMachine(this, 'VoiceProcessingStateMachine', {
      stateMachineName: `voice-processing-pipeline-${uniqueSuffix}`,
      definition,
      role: stepFunctionsRole,
      logs: {
        destination: new logs.LogGroup(this, 'StateMachineLogGroup', {
          logGroupName: `/aws/stepfunctions/voice-processing-${uniqueSuffix}`,
          retention: logs.RetentionDays.ONE_WEEK,
          removalPolicy: cdk.RemovalPolicy.DESTROY,
        }),
        level: stepfunctions.LogLevel.ALL,
        includeExecutionData: true,
      },
      timeout: cdk.Duration.hours(2),
    });

    // =================
    // MONITORING & ALERTS
    // =================

    // CloudWatch Dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'VoiceProcessingDashboard', {
      dashboardName: `voice-processing-pipeline-${uniqueSuffix}`,
    });

    // SNS Topic for alerts
    const alertsTopic = new sns.Topic(this, 'AlertsTopic', {
      topicName: `voice-processing-alerts-${uniqueSuffix}`,
      displayName: 'Voice Processing Pipeline Alerts',
    });

    // Lambda function error alarms
    const languageDetectorAlarm = new cloudwatch.Alarm(this, 'LanguageDetectorErrorAlarm', {
      alarmName: `voice-pipeline-language-detector-errors-${uniqueSuffix}`,
      alarmDescription: 'Language detector function error rate',
      metric: languageDetectorFunction.metricErrors({
        period: cdk.Duration.minutes(5),
      }),
      threshold: 5,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    languageDetectorAlarm.addAlarmAction({
      bind: () => ({ alarmActionArn: alertsTopic.topicArn }),
    });

    // Add metrics to dashboard
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Lambda Function Invocations',
        left: [
          languageDetectorFunction.metricInvocations(),
          transcriptionProcessorFunction.metricInvocations(),
          translationProcessorFunction.metricInvocations(),
          speechSynthesizerFunction.metricInvocations(),
        ],
        width: 12,
      }),
      new cloudwatch.GraphWidget({
        title: 'Lambda Function Errors',
        left: [
          languageDetectorFunction.metricErrors(),
          transcriptionProcessorFunction.metricErrors(),
          translationProcessorFunction.metricErrors(),
          speechSynthesizerFunction.metricErrors(),
        ],
        width: 12,
      }),
      new cloudwatch.GraphWidget({
        title: 'Step Functions Executions',
        left: [
          stateMachine.metricStarted(),
          stateMachine.metricSucceeded(),
          stateMachine.metricFailed(),
        ],
        width: 12,
      })
    );

    // =================
    // OUTPUTS
    // =================

    new cdk.CfnOutput(this, 'InputBucketName', {
      description: 'Name of the S3 bucket for input audio files',
      value: inputBucket.bucketName,
    });

    new cdk.CfnOutput(this, 'OutputBucketName', {
      description: 'Name of the S3 bucket for output audio files',
      value: outputBucket.bucketName,
    });

    new cdk.CfnOutput(this, 'JobsTableName', {
      description: 'Name of the DynamoDB table for job tracking',
      value: jobsTable.tableName,
    });

    new cdk.CfnOutput(this, 'StateMachineArn', {
      description: 'ARN of the Step Functions state machine',
      value: stateMachine.stateMachineArn,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      description: 'URL of the CloudWatch dashboard',
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
    });

    new cdk.CfnOutput(this, 'AlertsTopicArn', {
      description: 'ARN of the SNS topic for alerts',
      value: alertsTopic.topicArn,
    });
  }
}

// CDK App
const app = new cdk.App();

new VoiceProcessingPipelineStack(app, 'VoiceProcessingPipelineStack', {
  description: 'Multi-language voice processing pipeline using Amazon Transcribe, Translate, and Polly',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'VoiceProcessingPipeline',
    Environment: 'Development',
    Purpose: 'Multi-language voice processing and translation',
  },
});

app.synth();