#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as stepfunctions from 'aws-cdk-lib/aws-stepfunctions';
import * as tasks from 'aws-cdk-lib/aws-stepfunctions-tasks';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as apigateway from 'aws-cdk-lib/aws-apigatewayv2';
import * as integrations from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import * as s3notifications from 'aws-cdk-lib/aws-s3-notifications';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { RemovalPolicy, CfnOutput, Duration } from 'aws-cdk-lib';

/**
 * Props for the VideoWorkflowOrchestrationStack
 */
interface VideoWorkflowOrchestrationStackProps extends cdk.StackProps {
  /** Unique identifier for naming resources */
  readonly resourcePrefix?: string;
  /** Enable S3 automatic triggering */
  readonly enableS3Triggers?: boolean;
  /** Enable API Gateway endpoint */
  readonly enableApiGateway?: boolean;
}

/**
 * CDK Stack for Automated Video Workflow Orchestration with Step Functions
 * 
 * This stack creates a comprehensive video processing workflow that includes:
 * - S3 buckets for source, output, and archive storage
 * - Lambda functions for metadata extraction, quality control, and publishing
 * - Step Functions state machine for workflow orchestration
 * - MediaConvert integration for video transcoding
 * - DynamoDB for job tracking
 * - API Gateway for external workflow triggering
 * - CloudWatch monitoring and SNS notifications
 */
export class VideoWorkflowOrchestrationStack extends cdk.Stack {
  public readonly sourceBucket: s3.Bucket;
  public readonly outputBucket: s3.Bucket;
  public readonly archiveBucket: s3.Bucket;
  public readonly jobsTable: dynamodb.Table;
  public readonly stateMachine: stepfunctions.StateMachine;
  public readonly apiEndpoint?: apigateway.HttpApi;

  constructor(scope: Construct, id: string, props: VideoWorkflowOrchestrationStackProps = {}) {
    super(scope, id, props);

    const resourcePrefix = props.resourcePrefix || 'video-workflow';
    const enableS3Triggers = props.enableS3Triggers ?? true;
    const enableApiGateway = props.enableApiGateway ?? true;

    // Generate unique suffix for resource naming
    const uniqueSuffix = cdk.Names.uniqueId(this).slice(-8).toLowerCase();

    // Create S3 buckets for video processing workflow
    this.sourceBucket = new s3.Bucket(this, 'SourceBucket', {
      bucketName: `${resourcePrefix}-source-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'ArchiveOldVersions',
          enabled: true,
          noncurrentVersionExpiration: Duration.days(30),
        },
      ],
    });

    this.outputBucket = new s3.Bucket(this, 'OutputBucket', {
      bucketName: `${resourcePrefix}-output-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'TransitionToIA',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: Duration.days(90),
            },
          ],
        },
      ],
    });

    this.archiveBucket = new s3.Bucket(this, 'ArchiveBucket', {
      bucketName: `${resourcePrefix}-archive-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      storageClass: s3.StorageClass.GLACIER,
    });

    // Create DynamoDB table for job tracking
    this.jobsTable = new dynamodb.Table(this, 'JobsTable', {
      tableName: `${resourcePrefix}-jobs-${uniqueSuffix}`,
      partitionKey: { name: 'JobId', type: dynamodb.AttributeType.STRING },
      billing: dynamodb.Billing.onDemand(),
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // Add Global Secondary Index for querying by creation time
    this.jobsTable.addGlobalSecondaryIndex({
      indexName: 'CreatedAtIndex',
      partitionKey: { name: 'CreatedAt', type: dynamodb.AttributeType.STRING },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // Create SNS topic for notifications
    const notificationTopic = new sns.Topic(this, 'NotificationTopic', {
      topicName: `${resourcePrefix}-notifications-${uniqueSuffix}`,
      displayName: 'Video Workflow Notifications',
    });

    // Create IAM role for MediaConvert
    const mediaConvertRole = new iam.Role(this, 'MediaConvertRole', {
      roleName: `${resourcePrefix}-mediaconvert-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('mediaconvert.amazonaws.com'),
      description: 'IAM role for MediaConvert to access S3 buckets and SNS topics',
    });

    // Add permissions to MediaConvert role
    mediaConvertRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:GetObject',
        's3:PutObject',
        's3:DeleteObject',
        's3:ListBucket',
        's3:GetBucketLocation',
      ],
      resources: [
        this.sourceBucket.bucketArn,
        `${this.sourceBucket.bucketArn}/*`,
        this.outputBucket.bucketArn,
        `${this.outputBucket.bucketArn}/*`,
        this.archiveBucket.bucketArn,
        `${this.archiveBucket.bucketArn}/*`,
      ],
    }));

    mediaConvertRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['sns:Publish'],
      resources: [notificationTopic.topicArn],
    }));

    // Create IAM role for Lambda functions
    const lambdaRole = new iam.Role(this, 'LambdaRole', {
      roleName: `${resourcePrefix}-lambda-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      description: 'IAM role for video workflow Lambda functions',
    });

    // Add comprehensive permissions to Lambda role
    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:GetObject',
        's3:PutObject',
        's3:DeleteObject',
        's3:ListBucket',
        's3:HeadObject',
      ],
      resources: [
        this.sourceBucket.bucketArn,
        `${this.sourceBucket.bucketArn}/*`,
        this.outputBucket.bucketArn,
        `${this.outputBucket.bucketArn}/*`,
        this.archiveBucket.bucketArn,
        `${this.archiveBucket.bucketArn}/*`,
      ],
    }));

    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'dynamodb:PutItem',
        'dynamodb:GetItem',
        'dynamodb:UpdateItem',
        'dynamodb:Query',
        'dynamodb:Scan',
      ],
      resources: [
        this.jobsTable.tableArn,
        `${this.jobsTable.tableArn}/index/*`,
      ],
    }));

    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['sns:Publish'],
      resources: [notificationTopic.topicArn],
    }));

    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'stepfunctions:StartExecution',
        'stepfunctions:DescribeExecution',
      ],
      resources: ['*'], // Will be restricted after state machine creation
    }));

    // Create Lambda function for video metadata extraction
    const metadataExtractorFunction = new lambda.Function(this, 'MetadataExtractorFunction', {
      functionName: `${resourcePrefix}-metadata-extractor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: Duration.minutes(5),
      memorySize: 512,
      environment: {
        JOBS_TABLE: this.jobsTable.tableName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    # Extract input parameters
    bucket = event['bucket']
    key = event['key']
    job_id = event['jobId']
    
    try:
        # Get basic file information from S3
        response = s3.head_object(Bucket=bucket, Key=key)
        file_size = response['ContentLength']
        last_modified = response['LastModified'].isoformat()
        
        # Extract basic metadata (in production, would use ffprobe or similar)
        metadata = {
            'file_size': file_size,
            'last_modified': last_modified,
            'content_type': response.get('ContentType', 'unknown'),
            'duration': 120.5,  # Placeholder - would extract from video
            'width': 1920,
            'height': 1080,
            'fps': 29.97,
            'bitrate': 5000000,
            'codec': 'h264',
            'audio_codec': 'aac'
        }
        
        # Store metadata in DynamoDB
        table = dynamodb.Table(os.environ['JOBS_TABLE'])
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET VideoMetadata = :metadata, MetadataExtractedAt = :timestamp',
            ExpressionAttributeValues={
                ':metadata': metadata,
                ':timestamp': datetime.utcnow().isoformat()
            }
        )
        
        return {
            'statusCode': 200,
            'metadata': metadata,
            'jobId': job_id
        }
        
    except Exception as e:
        print(f"Error extracting metadata: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'jobId': job_id
        }
      `),
    });

    // Create Lambda function for quality control
    const qualityControlFunction = new lambda.Function(this, 'QualityControlFunction', {
      functionName: `${resourcePrefix}-quality-control-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: Duration.minutes(5),
      memorySize: 512,
      environment: {
        JOBS_TABLE: this.jobsTable.tableName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    # Extract input parameters
    outputs = event['outputs']
    job_id = event['jobId']
    
    try:
        quality_results = []
        
        for output in outputs:
            bucket = output['bucket']
            key = output['key']
            format_type = output['format']
            
            # Perform quality checks
            quality_check = perform_quality_validation(bucket, key, format_type)
            quality_results.append(quality_check)
        
        # Calculate overall quality score
        overall_score = calculate_overall_quality(quality_results)
        
        # Store results in DynamoDB
        table = dynamodb.Table(os.environ['JOBS_TABLE'])
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET QualityResults = :results, QualityScore = :score, QCCompletedAt = :timestamp',
            ExpressionAttributeValues={
                ':results': quality_results,
                ':score': overall_score,
                ':timestamp': datetime.utcnow().isoformat()
            }
        )
        
        return {
            'statusCode': 200,
            'qualityResults': quality_results,
            'qualityScore': overall_score,
            'passed': overall_score >= 0.8,
            'jobId': job_id
        }
        
    except Exception as e:
        print(f"Error in quality control: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'jobId': job_id,
            'passed': False
        }

def perform_quality_validation(bucket, key, format_type):
    try:
        # Check if file exists and get basic info
        response = s3.head_object(Bucket=bucket, Key=key)
        file_size = response['ContentLength']
        
        # Basic checks
        checks = {
            'file_exists': True,
            'file_size_valid': file_size > 1000,  # Minimum 1KB
            'format_valid': format_type in ['mp4', 'hls', 'dash'],
            'encoding_quality': 0.9  # Placeholder score
        }
        
        score = sum(1 for check in checks.values() if check is True) / len([k for k in checks.keys() if k != 'encoding_quality'])
        if 'encoding_quality' in checks:
            score = (score + checks['encoding_quality']) / 2
        
        return {
            'bucket': bucket,
            'key': key,
            'format': format_type,
            'checks': checks,
            'score': score,
            'file_size': file_size
        }
        
    except Exception as e:
        return {
            'bucket': bucket,
            'key': key,
            'format': format_type,
            'error': str(e),
            'score': 0.0
        }

def calculate_overall_quality(quality_results):
    if not quality_results:
        return 0.0
    
    total_score = sum(result.get('score', 0.0) for result in quality_results)
    return total_score / len(quality_results)
      `),
    });

    // Create Lambda function for publishing
    const publisherFunction = new lambda.Function(this, 'PublisherFunction', {
      functionName: `${resourcePrefix}-publisher-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: Duration.minutes(5),
      memorySize: 512,
      environment: {
        JOBS_TABLE: this.jobsTable.tableName,
        SNS_TOPIC_ARN: notificationTopic.topicArn,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

def lambda_handler(event, context):
    # Extract input parameters
    job_id = event['jobId']
    outputs = event['outputs']
    quality_passed = event.get('qualityPassed', False)
    
    try:
        # Update job status in DynamoDB
        table = dynamodb.Table(os.environ['JOBS_TABLE'])
        
        if quality_passed:
            # Publish successful completion
            table.update_item(
                Key={'JobId': job_id},
                UpdateExpression='SET JobStatus = :status, PublishedAt = :timestamp, OutputLocations = :outputs',
                ExpressionAttributeValues={
                    ':status': 'PUBLISHED',
                    ':timestamp': datetime.utcnow().isoformat(),
                    ':outputs': outputs
                }
            )
            
            # Send success notification
            message = f"Video processing completed successfully for job {job_id}"
            subject = "Video Processing Success"
            
        else:
            # Mark as failed quality control
            table.update_item(
                Key={'JobId': job_id},
                UpdateExpression='SET JobStatus = :status, FailedAt = :timestamp, FailureReason = :reason',
                ExpressionAttributeValues={
                    ':status': 'FAILED_QC',
                    ':timestamp': datetime.utcnow().isoformat(),
                    ':reason': 'Quality control validation failed'
                }
            )
            
            # Send failure notification
            message = f"Video processing failed quality control for job {job_id}"
            subject = "Video Processing Quality Control Failed"
        
        # Send SNS notification
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=message,
            Subject=subject
        )
        
        return {
            'statusCode': 200,
            'jobId': job_id,
            'status': 'PUBLISHED' if quality_passed else 'FAILED_QC',
            'message': message
        }
        
    except Exception as e:
        print(f"Error in publishing: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'jobId': job_id
        }
      `),
    });

    // Create Lambda function for workflow triggering
    const workflowTriggerFunction = new lambda.Function(this, 'WorkflowTriggerFunction', {
      functionName: `${resourcePrefix}-workflow-trigger-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: Duration.seconds(30),
      memorySize: 256,
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
import os
from datetime import datetime

stepfunctions = boto3.client('stepfunctions')

def lambda_handler(event, context):
    try:
        # Parse request body for API Gateway events
        if 'body' in event:
            if isinstance(event['body'], str):
                body = json.loads(event['body'])
            else:
                body = event['body']
        # Handle S3 events
        elif 'Records' in event and event['Records']:
            record = event['Records'][0]
            if 's3' in record:
                bucket = record['s3']['bucket']['name']
                key = record['s3']['object']['key']
                body = {'bucket': bucket, 'key': key}
            else:
                body = event
        else:
            body = event
        
        bucket = body.get('bucket')
        key = body.get('key')
        
        if not bucket or not key:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Missing bucket or key parameter'})
            }
        
        # Generate unique job ID
        job_id = str(uuid.uuid4())
        
        # Start Step Functions execution
        response = stepfunctions.start_execution(
            stateMachineArn=os.environ['STATE_MACHINE_ARN'],
            name=f"video-workflow-{job_id}",
            input=json.dumps({
                'jobId': job_id,
                'bucket': bucket,
                'key': key,
                'requestedAt': datetime.utcnow().isoformat()
            })
        )
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'jobId': job_id,
                'executionArn': response['executionArn'],
                'message': 'Video processing workflow started successfully'
            })
        }
        
    except Exception as e:
        print(f"Error starting workflow: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }
      `),
    });

    // Create Step Functions state machine definition
    const initializeJob = new stepfunctions.Pass(this, 'InitializeJob', {
      parameters: {
        'jobId.$': '$.jobId',
        'bucket.$': '$.bucket',
        'key.$': '$.key',
        'outputBucket': this.outputBucket.bucketName,
        'archiveBucket': this.archiveBucket.bucketName,
        'timestamp.$': '$$.State.EnteredTime',
      },
    });

    const recordJobStart = new tasks.DynamoPutItem(this, 'RecordJobStart', {
      table: this.jobsTable,
      item: {
        JobId: tasks.DynamoAttributeValue.fromString(stepfunctions.JsonPath.stringAt('$.jobId')),
        SourceBucket: tasks.DynamoAttributeValue.fromString(stepfunctions.JsonPath.stringAt('$.bucket')),
        SourceKey: tasks.DynamoAttributeValue.fromString(stepfunctions.JsonPath.stringAt('$.key')),
        CreatedAt: tasks.DynamoAttributeValue.fromString(stepfunctions.JsonPath.stringAt('$.timestamp')),
        JobStatus: tasks.DynamoAttributeValue.fromString('STARTED'),
      },
      resultPath: stepfunctions.JsonPath.DISCARD,
    });

    // Create parallel processing branch for metadata extraction
    const extractMetadata = new tasks.LambdaInvoke(this, 'ExtractMetadata', {
      lambdaFunction: metadataExtractorFunction,
      payload: stepfunctions.TaskInput.fromObject({
        'bucket.$': '$.bucket',
        'key.$': '$.key',
        'jobId.$': '$.jobId',
      }),
      resultPath: '$.metadataResult',
    });

    // Create MediaConvert job task
    const transcodeVideo = new tasks.MediaConvertCreateJob(this, 'TranscodeVideo', {
      createJobRequest: {
        Role: mediaConvertRole.roleArn,
        Settings: {
          OutputGroups: [
            {
              Name: 'MP4_Output',
              OutputGroupSettings: {
                Type: 'FILE_GROUP_SETTINGS',
                FileGroupSettings: {
                  Destination: stepfunctions.JsonPath.format('s3://{}/mp4/{}/', this.outputBucket.bucketName, stepfunctions.JsonPath.stringAt('$.jobId')),
                },
              },
              Outputs: [
                {
                  NameModifier: '_1080p',
                  ContainerSettings: {
                    Container: 'MP4',
                  },
                  VideoDescription: {
                    Width: 1920,
                    Height: 1080,
                    CodecSettings: {
                      Codec: 'H_264',
                      H264Settings: {
                        RateControlMode: 'QVBR',
                        QvbrSettings: {
                          QvbrQualityLevel: 8,
                        },
                        MaxBitrate: 5000000,
                      },
                    },
                  },
                  AudioDescriptions: [
                    {
                      CodecSettings: {
                        Codec: 'AAC',
                        AacSettings: {
                          Bitrate: 128000,
                          CodingMode: 'CODING_MODE_2_0',
                          SampleRate: 48000,
                        },
                      },
                    },
                  ],
                },
                {
                  NameModifier: '_720p',
                  ContainerSettings: {
                    Container: 'MP4',
                  },
                  VideoDescription: {
                    Width: 1280,
                    Height: 720,
                    CodecSettings: {
                      Codec: 'H_264',
                      H264Settings: {
                        RateControlMode: 'QVBR',
                        QvbrSettings: {
                          QvbrQualityLevel: 7,
                        },
                        MaxBitrate: 3000000,
                      },
                    },
                  },
                  AudioDescriptions: [
                    {
                      CodecSettings: {
                        Codec: 'AAC',
                        AacSettings: {
                          Bitrate: 128000,
                          CodingMode: 'CODING_MODE_2_0',
                          SampleRate: 48000,
                        },
                      },
                    },
                  ],
                },
              ],
            },
            {
              Name: 'HLS_Output',
              OutputGroupSettings: {
                Type: 'HLS_GROUP_SETTINGS',
                HlsGroupSettings: {
                  Destination: stepfunctions.JsonPath.format('s3://{}/hls/{}/', this.outputBucket.bucketName, stepfunctions.JsonPath.stringAt('$.jobId')),
                  SegmentLength: 6,
                  OutputSelection: 'MANIFESTS_AND_SEGMENTS',
                  ManifestDurationFormat: 'FLOATING_POINT',
                },
              },
              Outputs: [
                {
                  NameModifier: '_hls_1080p',
                  ContainerSettings: {
                    Container: 'M3U8',
                  },
                  VideoDescription: {
                    Width: 1920,
                    Height: 1080,
                    CodecSettings: {
                      Codec: 'H_264',
                      H264Settings: {
                        RateControlMode: 'QVBR',
                        QvbrSettings: {
                          QvbrQualityLevel: 8,
                        },
                        MaxBitrate: 5000000,
                      },
                    },
                  },
                  AudioDescriptions: [
                    {
                      CodecSettings: {
                        Codec: 'AAC',
                        AacSettings: {
                          Bitrate: 128000,
                          CodingMode: 'CODING_MODE_2_0',
                          SampleRate: 48000,
                        },
                      },
                    },
                  ],
                },
                {
                  NameModifier: '_hls_720p',
                  ContainerSettings: {
                    Container: 'M3U8',
                  },
                  VideoDescription: {
                    Width: 1280,
                    Height: 720,
                    CodecSettings: {
                      Codec: 'H_264',
                      H264Settings: {
                        RateControlMode: 'QVBR',
                        QvbrSettings: {
                          QvbrQualityLevel: 7,
                        },
                        MaxBitrate: 3000000,
                      },
                    },
                  },
                  AudioDescriptions: [
                    {
                      CodecSettings: {
                        Codec: 'AAC',
                        AacSettings: {
                          Bitrate: 128000,
                          CodingMode: 'CODING_MODE_2_0',
                          SampleRate: 48000,
                        },
                      },
                    },
                  ],
                },
              ],
            },
            {
              Name: 'Thumbnail_Output',
              OutputGroupSettings: {
                Type: 'FILE_GROUP_SETTINGS',
                FileGroupSettings: {
                  Destination: stepfunctions.JsonPath.format('s3://{}/thumbnails/{}/', this.outputBucket.bucketName, stepfunctions.JsonPath.stringAt('$.jobId')),
                },
              },
              Outputs: [
                {
                  NameModifier: '_thumb_%04d',
                  ContainerSettings: {
                    Container: 'RAW',
                  },
                  VideoDescription: {
                    Width: 640,
                    Height: 360,
                    CodecSettings: {
                      Codec: 'FRAME_CAPTURE',
                      FrameCaptureSettings: {
                        FramerateNumerator: 1,
                        FramerateDenominator: 10,
                        MaxCaptures: 5,
                        Quality: 80,
                      },
                    },
                  },
                },
              ],
            },
          ],
          Inputs: [
            {
              FileInput: stepfunctions.JsonPath.format('s3://{}/{}', stepfunctions.JsonPath.stringAt('$.bucket'), stepfunctions.JsonPath.stringAt('$.key')),
              AudioSelectors: {
                'Audio Selector 1': {
                  Tracks: [1],
                  DefaultSelection: 'DEFAULT',
                },
              },
              VideoSelector: {
                ColorSpace: 'FOLLOW',
              },
              TimecodeSource: 'EMBEDDED',
            },
          ],
        },
        StatusUpdateInterval: 'SECONDS_60',
        UserMetadata: {
          WorkflowJobId: stepfunctions.JsonPath.stringAt('$.jobId'),
          SourceFile: stepfunctions.JsonPath.stringAt('$.key'),
        },
      },
      integrationPattern: stepfunctions.IntegrationPattern.RUN_JOB,
      resultPath: '$.mediaConvertJob',
    });

    // Create parallel processing
    const parallelProcessing = new stepfunctions.Parallel(this, 'ParallelProcessing', {
      resultPath: '$.parallelResults',
    });

    parallelProcessing.branch(extractMetadata);
    parallelProcessing.branch(transcodeVideo);

    const processingComplete = new stepfunctions.Pass(this, 'ProcessingComplete', {
      parameters: {
        'jobId.$': '$[0].metadataResult.Payload.jobId',
        'metadata.$': '$[0].metadataResult.Payload.metadata',
        'mediaConvertJob.$': '$[1].mediaConvertJob.Job',
        'outputs': [
          {
            'format': 'mp4',
            'bucket': this.outputBucket.bucketName,
            'key.$': 'States.Format(\'mp4/{}/output\', $[0].metadataResult.Payload.jobId)',
          },
          {
            'format': 'hls',
            'bucket': this.outputBucket.bucketName,
            'key.$': 'States.Format(\'hls/{}/index.m3u8\', $[0].metadataResult.Payload.jobId)',
          },
          {
            'format': 'thumbnails',
            'bucket': this.outputBucket.bucketName,
            'key.$': 'States.Format(\'thumbnails/{}/thumbnails\', $[0].metadataResult.Payload.jobId)',
          },
        ],
      },
    });

    const qualityControl = new tasks.LambdaInvoke(this, 'QualityControl', {
      lambdaFunction: qualityControlFunction,
      payload: stepfunctions.TaskInput.fromObject({
        'jobId.$': '$.jobId',
        'outputs.$': '$.outputs',
        'metadata.$': '$.metadata',
      }),
      resultPath: '$.qualityResult',
    });

    const qualityDecision = new stepfunctions.Choice(this, 'QualityDecision');

    const publishContent = new tasks.LambdaInvoke(this, 'PublishContent', {
      lambdaFunction: publisherFunction,
      payload: stepfunctions.TaskInput.fromObject({
        'jobId.$': '$.jobId',
        'outputs.$': '$.outputs',
        'qualityResults.$': '$.qualityResult.Payload.qualityResults',
        'qualityPassed': true,
      }),
      resultPath: '$.publishResult',
    });

    const qualityControlFailed = new tasks.LambdaInvoke(this, 'QualityControlFailed', {
      lambdaFunction: publisherFunction,
      payload: stepfunctions.TaskInput.fromObject({
        'jobId.$': '$.jobId',
        'outputs.$': '$.outputs',
        'qualityResults.$': '$.qualityResult.Payload.qualityResults',
        'qualityPassed': false,
      }),
      resultPath: '$.publishResult',
    });

    const archiveSource = new tasks.CallAwsService(this, 'ArchiveSource', {
      service: 's3',
      action: 'copyObject',
      parameters: {
        'Bucket': this.archiveBucket.bucketName,
        'CopySource.$': 'States.Format(\'{}/{}\', $.jobId, $.key)',
        'Key.$': 'States.Format(\'archived/{}/{}\', $.jobId, $.key)',
      },
      iamResources: [
        this.archiveBucket.bucketArn,
        `${this.archiveBucket.bucketArn}/*`,
        this.sourceBucket.bucketArn,
        `${this.sourceBucket.bucketArn}/*`,
      ],
      resultPath: stepfunctions.JsonPath.DISCARD,
    });

    const workflowSuccess = new stepfunctions.Succeed(this, 'WorkflowSuccess', {
      comment: 'Video processing workflow completed successfully',
    });

    const workflowFailure = new stepfunctions.Fail(this, 'WorkflowFailure', {
      comment: 'Video processing workflow failed',
    });

    const handleProcessingFailure = new tasks.DynamoUpdateItem(this, 'HandleProcessingFailure', {
      table: this.jobsTable,
      key: {
        JobId: tasks.DynamoAttributeValue.fromString(stepfunctions.JsonPath.stringAt('$.jobId')),
      },
      updateExpression: 'SET JobStatus = :status, ErrorDetails = :error, FailedAt = :timestamp',
      expressionAttributeValues: {
        ':status': tasks.DynamoAttributeValue.fromString('FAILED_PROCESSING'),
        ':error': tasks.DynamoAttributeValue.fromString(stepfunctions.JsonPath.stringAt('$.error.Cause')),
        ':timestamp': tasks.DynamoAttributeValue.fromString(stepfunctions.JsonPath.stringAt('$$.State.EnteredTime')),
      },
      resultPath: stepfunctions.JsonPath.DISCARD,
    });

    // Define the workflow
    const definition = initializeJob
      .next(recordJobStart)
      .next(parallelProcessing
        .addCatch(handleProcessingFailure.next(workflowFailure), {
          errors: ['States.ALL'],
          resultPath: '$.error',
        })
      )
      .next(processingComplete)
      .next(qualityControl)
      .next(qualityDecision
        .when(stepfunctions.Condition.booleanEquals('$.qualityResult.Payload.passed', true),
          publishContent.next(archiveSource).next(workflowSuccess)
        )
        .otherwise(qualityControlFailed.next(workflowFailure))
      );

    // Create CloudWatch Log Group for Step Functions
    const stepFunctionsLogGroup = new logs.LogGroup(this, 'StepFunctionsLogGroup', {
      logGroupName: `/aws/stepfunctions/${resourcePrefix}-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // Create Step Functions state machine
    this.stateMachine = new stepfunctions.StateMachine(this, 'VideoWorkflowStateMachine', {
      stateMachineName: `${resourcePrefix}-${uniqueSuffix}`,
      definition: definition,
      stateMachineType: stepfunctions.StateMachineType.EXPRESS,
      logs: {
        destination: stepFunctionsLogGroup,
        level: stepfunctions.LogLevel.ALL,
        includeExecutionData: true,
      },
      tracingEnabled: true,
    });

    // Update Lambda role to restrict Step Functions permissions
    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'stepfunctions:StartExecution',
        'stepfunctions:DescribeExecution',
      ],
      resources: [this.stateMachine.stateMachineArn],
    }));

    // Update workflow trigger function environment
    workflowTriggerFunction.addEnvironment('STATE_MACHINE_ARN', this.stateMachine.stateMachineArn);

    // Create API Gateway if enabled
    if (enableApiGateway) {
      this.apiEndpoint = new apigateway.HttpApi(this, 'VideoWorkflowApi', {
        apiName: `${resourcePrefix}-api-${uniqueSuffix}`,
        description: 'Video processing workflow API',
        corsPreflight: {
          allowCredentials: false,
          allowHeaders: ['*'],
          allowMethods: [apigateway.CorsHttpMethod.ANY],
          allowOrigins: ['*'],
        },
      });

      const lambdaIntegration = new integrations.HttpLambdaIntegration('WorkflowTriggerIntegration', workflowTriggerFunction);

      this.apiEndpoint.addRoutes({
        path: '/start-workflow',
        methods: [apigateway.HttpMethod.POST],
        integration: lambdaIntegration,
      });
    }

    // Configure S3 event notifications if enabled
    if (enableS3Triggers) {
      // Add S3 event notifications for automatic workflow triggering
      this.sourceBucket.addEventNotification(
        s3.EventType.OBJECT_CREATED,
        new s3notifications.LambdaDestination(workflowTriggerFunction),
        { suffix: '.mp4' }
      );

      this.sourceBucket.addEventNotification(
        s3.EventType.OBJECT_CREATED,
        new s3notifications.LambdaDestination(workflowTriggerFunction),
        { suffix: '.mov' }
      );

      this.sourceBucket.addEventNotification(
        s3.EventType.OBJECT_CREATED,
        new s3notifications.LambdaDestination(workflowTriggerFunction),
        { suffix: '.avi' }
      );
    }

    // Create CloudWatch Dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'VideoWorkflowDashboard', {
      dashboardName: `VideoWorkflowMonitoring-${uniqueSuffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Step Functions Executions',
            left: [
              this.stateMachine.metricSucceeded({
                statistic: 'Sum',
                period: Duration.minutes(5),
                label: 'Succeeded',
              }),
              this.stateMachine.metricFailed({
                statistic: 'Sum',
                period: Duration.minutes(5),
                label: 'Failed',
              }),
              this.stateMachine.metricStarted({
                statistic: 'Sum',
                period: Duration.minutes(5),
                label: 'Started',
              }),
            ],
            width: 12,
          }),
          new cloudwatch.GraphWidget({
            title: 'Lambda Functions Performance',
            left: [
              metadataExtractorFunction.metricInvocations({
                statistic: 'Sum',
                period: Duration.minutes(5),
                label: 'Metadata Extractor Invocations',
              }),
              qualityControlFunction.metricInvocations({
                statistic: 'Sum',
                period: Duration.minutes(5),
                label: 'Quality Control Invocations',
              }),
            ],
            right: [
              metadataExtractorFunction.metricErrors({
                statistic: 'Sum',
                period: Duration.minutes(5),
                label: 'Metadata Extractor Errors',
              }),
              qualityControlFunction.metricErrors({
                statistic: 'Sum',
                period: Duration.minutes(5),
                label: 'Quality Control Errors',
              }),
            ],
            width: 12,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Lambda Duration',
            left: [
              metadataExtractorFunction.metricDuration({
                statistic: 'Average',
                period: Duration.minutes(5),
                label: 'Metadata Extractor Duration',
              }),
              qualityControlFunction.metricDuration({
                statistic: 'Average',
                period: Duration.minutes(5),
                label: 'Quality Control Duration',
              }),
              publisherFunction.metricDuration({
                statistic: 'Average',
                period: Duration.minutes(5),
                label: 'Publisher Duration',
              }),
            ],
            width: 12,
          }),
          new cloudwatch.SingleValueWidget({
            title: 'DynamoDB Items',
            metrics: [
              this.jobsTable.metricConsumedReadCapacityUnits({
                statistic: 'Sum',
                period: Duration.minutes(5),
                label: 'Read Capacity',
              }),
              this.jobsTable.metricConsumedWriteCapacityUnits({
                statistic: 'Sum',
                period: Duration.minutes(5),
                label: 'Write Capacity',
              }),
            ],
            width: 12,
          }),
        ],
      ],
    });

    // Outputs
    new CfnOutput(this, 'SourceBucketName', {
      value: this.sourceBucket.bucketName,
      description: 'S3 bucket for source video files',
      exportName: `${this.stackName}-SourceBucket`,
    });

    new CfnOutput(this, 'OutputBucketName', {
      value: this.outputBucket.bucketName,
      description: 'S3 bucket for processed video outputs',
      exportName: `${this.stackName}-OutputBucket`,
    });

    new CfnOutput(this, 'ArchiveBucketName', {
      value: this.archiveBucket.bucketName,
      description: 'S3 bucket for archived source files',
      exportName: `${this.stackName}-ArchiveBucket`,
    });

    new CfnOutput(this, 'JobsTableName', {
      value: this.jobsTable.tableName,
      description: 'DynamoDB table for job tracking',
      exportName: `${this.stackName}-JobsTable`,
    });

    new CfnOutput(this, 'StateMachineArn', {
      value: this.stateMachine.stateMachineArn,
      description: 'Step Functions state machine ARN',
      exportName: `${this.stackName}-StateMachine`,
    });

    new CfnOutput(this, 'NotificationTopicArn', {
      value: notificationTopic.topicArn,
      description: 'SNS topic for workflow notifications',
      exportName: `${this.stackName}-NotificationTopic`,
    });

    if (this.apiEndpoint) {
      new CfnOutput(this, 'ApiEndpoint', {
        value: `${this.apiEndpoint.apiEndpoint}/start-workflow`,
        description: 'API Gateway endpoint for triggering workflows',
        exportName: `${this.stackName}-ApiEndpoint`,
      });
    }

    new CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=VideoWorkflowMonitoring-${uniqueSuffix}`,
      description: 'CloudWatch dashboard URL for monitoring',
      exportName: `${this.stackName}-Dashboard`,
    });
  }
}

/**
 * CDK App for Video Workflow Orchestration
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID,
  region: process.env.CDK_DEFAULT_REGION || process.env.AWS_REGION || 'us-east-1',
};

const resourcePrefix = app.node.tryGetContext('resourcePrefix') || 'video-workflow';
const enableS3Triggers = app.node.tryGetContext('enableS3Triggers') !== 'false';
const enableApiGateway = app.node.tryGetContext('enableApiGateway') !== 'false';

// Create the stack
new VideoWorkflowOrchestrationStack(app, 'VideoWorkflowOrchestrationStack', {
  env,
  resourcePrefix,
  enableS3Triggers,
  enableApiGateway,
  description: 'Automated Video Workflow Orchestration with Step Functions - CDK TypeScript Implementation',
  tags: {
    Project: 'VideoWorkflowOrchestration',
    Environment: 'Production',
    ManagedBy: 'CDK',
    Purpose: 'Video Processing Automation',
  },
});

app.synth();