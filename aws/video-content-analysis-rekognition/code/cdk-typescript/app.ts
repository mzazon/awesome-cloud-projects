#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as sns_subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as stepfunctions from 'aws-cdk-lib/aws-stepfunctions';
import * as sfn_tasks from 'aws-cdk-lib/aws-stepfunctions-tasks';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatch_actions from 'aws-cdk-lib/aws-cloudwatch-actions';
import { Duration, RemovalPolicy } from 'aws-cdk-lib';

/**
 * Stack for deploying a comprehensive video content analysis solution
 * using Amazon Rekognition, Step Functions, and Lambda.
 * 
 * This stack implements an automated video processing pipeline that:
 * - Analyzes video content for moderation and segment detection
 * - Orchestrates processing with Step Functions
 * - Stores results in DynamoDB and S3
 * - Provides notifications via SNS/SQS
 * - Includes monitoring and alerting
 */
export class VideoContentAnalysisStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate a unique suffix for resource names
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // ========================================
    // S3 Buckets for video processing pipeline
    // ========================================
    
    // Source bucket for raw video uploads
    const sourceBucket = new s3.Bucket(this, 'VideoSourceBucket', {
      bucketName: `video-source-${uniqueSuffix}`,
      versioned: false,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVideos',
          expiration: Duration.days(30),
          abortIncompleteMultipartUploadAfter: Duration.days(7),
        },
      ],
    });

    // Results bucket for processed analysis output
    const resultsBucket = new s3.Bucket(this, 'VideoResultsBucket', {
      bucketName: `video-results-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'TransitionToIA',
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

    // Temporary bucket for intermediate processing
    const tempBucket = new s3.Bucket(this, 'VideoTempBucket', {
      bucketName: `video-temp-${uniqueSuffix}`,
      versioned: false,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'DeleteTempFiles',
          expiration: Duration.days(7),
        },
      ],
    });

    // ========================================
    // DynamoDB table for tracking analysis jobs
    // ========================================
    
    const analysisTable = new dynamodb.Table(this, 'VideoAnalysisTable', {
      tableName: `video-analysis-results-${uniqueSuffix}`,
      partitionKey: { name: 'VideoId', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'Timestamp', type: dynamodb.AttributeType.NUMBER },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      removalPolicy: RemovalPolicy.DESTROY,
      pointInTimeRecovery: true,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
    });

    // Global Secondary Index for querying by job status
    analysisTable.addGlobalSecondaryIndex({
      indexName: 'JobStatusIndex',
      partitionKey: { name: 'JobStatus', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'Timestamp', type: dynamodb.AttributeType.NUMBER },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // ========================================
    // SNS Topic and SQS Queue for notifications
    // ========================================
    
    const notificationTopic = new sns.Topic(this, 'VideoAnalysisNotificationTopic', {
      topicName: `video-analysis-notifications-${uniqueSuffix}`,
      displayName: 'Video Analysis Notifications',
      fifo: false,
    });

    const notificationQueue = new sqs.Queue(this, 'VideoAnalysisNotificationQueue', {
      queueName: `video-analysis-queue-${uniqueSuffix}`,
      visibilityTimeout: Duration.seconds(300),
      retentionPeriod: Duration.days(14),
      deadLetterQueue: {
        maxReceiveCount: 3,
        queue: new sqs.Queue(this, 'VideoAnalysisDeadLetterQueue', {
          queueName: `video-analysis-dlq-${uniqueSuffix}`,
        }),
      },
    });

    // Subscribe SQS queue to SNS topic
    notificationTopic.addSubscription(
      new sns_subscriptions.SqsSubscription(notificationQueue)
    );

    // ========================================
    // IAM Roles for Lambda functions
    // ========================================
    
    // Lambda execution role with comprehensive permissions
    const lambdaRole = new iam.Role(this, 'VideoAnalysisLambdaRole', {
      roleName: `VideoAnalysisLambdaRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Custom policy for video analysis operations
    const videoAnalysisPolicy = new iam.Policy(this, 'VideoAnalysisPolicy', {
      policyName: `VideoAnalysisPolicy-${uniqueSuffix}`,
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'rekognition:StartMediaAnalysisJob',
            'rekognition:GetMediaAnalysisJob',
            'rekognition:StartContentModeration',
            'rekognition:GetContentModeration',
            'rekognition:StartSegmentDetection',
            'rekognition:GetSegmentDetection',
            'rekognition:StartTextDetection',
            'rekognition:GetTextDetection',
          ],
          resources: ['*'],
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            's3:GetObject',
            's3:PutObject',
            's3:DeleteObject',
          ],
          resources: [
            sourceBucket.bucketArn + '/*',
            resultsBucket.bucketArn + '/*',
            tempBucket.bucketArn + '/*',
          ],
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'dynamodb:PutItem',
            'dynamodb:GetItem',
            'dynamodb:UpdateItem',
            'dynamodb:Query',
            'dynamodb:Scan',
          ],
          resources: [
            analysisTable.tableArn,
            analysisTable.tableArn + '/index/*',
          ],
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: ['sns:Publish'],
          resources: [notificationTopic.topicArn],
        }),
      ],
    });

    lambdaRole.attachInlinePolicy(videoAnalysisPolicy);

    // ========================================
    // Lambda Functions for video processing
    // ========================================
    
    // Lambda function for video analysis initialization
    const initFunction = new lambda.Function(this, 'VideoAnalysisInitFunction', {
      functionName: `VideoAnalysisInitFunction-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
from datetime import datetime
import os

def lambda_handler(event, context):
    """
    Initialize video analysis job
    """
    try:
        # Extract video information from S3 event
        s3_bucket = event['Records'][0]['s3']['bucket']['name']
        s3_key = event['Records'][0]['s3']['object']['key']
        
        # Generate unique job ID
        job_id = str(uuid.uuid4())
        
        # Initialize DynamoDB record
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(os.environ['ANALYSIS_TABLE'])
        
        # Store initial job information
        table.put_item(
            Item={
                'VideoId': f"{s3_bucket}/{s3_key}",
                'Timestamp': int(datetime.now().timestamp()),
                'JobId': job_id,
                'JobStatus': 'INITIATED',
                'S3Bucket': s3_bucket,
                'S3Key': s3_key,
                'CreatedAt': datetime.now().isoformat()
            }
        )
        
        return {
            'statusCode': 200,
            'body': {
                'jobId': job_id,
                'videoId': f"{s3_bucket}/{s3_key}",
                's3Bucket': s3_bucket,
                's3Key': s3_key,
                'status': 'INITIATED'
            }
        }
        
    except Exception as e:
        print(f"Error initializing video analysis: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': str(e)
            }
        }
      `),
      timeout: Duration.seconds(60),
      memorySize: 256,
      environment: {
        ANALYSIS_TABLE: analysisTable.tableName,
      },
      role: lambdaRole,
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Lambda function for content moderation
    const moderationFunction = new lambda.Function(this, 'VideoAnalysisModerationFunction', {
      functionName: `VideoAnalysisModerationFunction-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Start content moderation analysis
    """
    try:
        rekognition = boto3.client('rekognition')
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(os.environ['ANALYSIS_TABLE'])
        
        # Extract job information
        job_id = event['jobId']
        s3_bucket = event['s3Bucket']
        s3_key = event['s3Key']
        video_id = event['videoId']
        
        # Start content moderation job
        response = rekognition.start_content_moderation(
            Video={
                'S3Object': {
                    'Bucket': s3_bucket,
                    'Name': s3_key
                }
            },
            MinConfidence=50.0,
            NotificationChannel={
                'SNSTopicArn': os.environ['SNS_TOPIC_ARN'],
                'RoleArn': os.environ['LAMBDA_ROLE_ARN']
            }
        )
        
        moderation_job_id = response['JobId']
        
        # Update DynamoDB with moderation job ID
        table.update_item(
            Key={
                'VideoId': video_id,
                'Timestamp': int(datetime.now().timestamp())
            },
            UpdateExpression='SET ModerationJobId = :mjid, JobStatus = :status',
            ExpressionAttributeValues={
                ':mjid': moderation_job_id,
                ':status': 'MODERATION_IN_PROGRESS'
            }
        )
        
        return {
            'statusCode': 200,
            'body': {
                'jobId': job_id,
                'moderationJobId': moderation_job_id,
                'videoId': video_id,
                'status': 'MODERATION_IN_PROGRESS'
            }
        }
        
    except Exception as e:
        print(f"Error starting content moderation: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': str(e)
            }
        }
      `),
      timeout: Duration.seconds(60),
      memorySize: 256,
      environment: {
        ANALYSIS_TABLE: analysisTable.tableName,
        SNS_TOPIC_ARN: notificationTopic.topicArn,
        LAMBDA_ROLE_ARN: lambdaRole.roleArn,
      },
      role: lambdaRole,
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Lambda function for segment detection
    const segmentFunction = new lambda.Function(this, 'VideoAnalysisSegmentFunction', {
      functionName: `VideoAnalysisSegmentFunction-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Start segment detection analysis
    """
    try:
        rekognition = boto3.client('rekognition')
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(os.environ['ANALYSIS_TABLE'])
        
        # Extract job information
        job_id = event['jobId']
        s3_bucket = event['s3Bucket']
        s3_key = event['s3Key']
        video_id = event['videoId']
        
        # Start segment detection job
        response = rekognition.start_segment_detection(
            Video={
                'S3Object': {
                    'Bucket': s3_bucket,
                    'Name': s3_key
                }
            },
            SegmentTypes=['TECHNICAL_CUE', 'SHOT'],
            NotificationChannel={
                'SNSTopicArn': os.environ['SNS_TOPIC_ARN'],
                'RoleArn': os.environ['LAMBDA_ROLE_ARN']
            }
        )
        
        segment_job_id = response['JobId']
        
        # Update DynamoDB with segment job ID
        table.update_item(
            Key={
                'VideoId': video_id,
                'Timestamp': int(datetime.now().timestamp())
            },
            UpdateExpression='SET SegmentJobId = :sjid, JobStatus = :status',
            ExpressionAttributeValues={
                ':sjid': segment_job_id,
                ':status': 'SEGMENT_DETECTION_IN_PROGRESS'
            }
        )
        
        return {
            'statusCode': 200,
            'body': {
                'jobId': job_id,
                'segmentJobId': segment_job_id,
                'videoId': video_id,
                'status': 'SEGMENT_DETECTION_IN_PROGRESS'
            }
        }
        
    except Exception as e:
        print(f"Error starting segment detection: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': str(e)
            }
        }
      `),
      timeout: Duration.seconds(60),
      memorySize: 256,
      environment: {
        ANALYSIS_TABLE: analysisTable.tableName,
        SNS_TOPIC_ARN: notificationTopic.topicArn,
        LAMBDA_ROLE_ARN: lambdaRole.roleArn,
      },
      role: lambdaRole,
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Lambda function for results aggregation
    const aggregationFunction = new lambda.Function(this, 'VideoAnalysisAggregationFunction', {
      functionName: `VideoAnalysisAggregationFunction-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Aggregate and store analysis results
    """
    try:
        rekognition = boto3.client('rekognition')
        dynamodb = boto3.resource('dynamodb')
        s3 = boto3.client('s3')
        
        table = dynamodb.Table(os.environ['ANALYSIS_TABLE'])
        
        # Extract job information
        job_id = event['jobId']
        video_id = event['videoId']
        moderation_job_id = event.get('moderationJobId')
        segment_job_id = event.get('segmentJobId')
        
        results = {
            'jobId': job_id,
            'videoId': video_id,
            'processedAt': datetime.now().isoformat(),
            'moderation': {},
            'segments': {},
            'summary': {}
        }
        
        # Get content moderation results
        if moderation_job_id:
            try:
                moderation_response = rekognition.get_content_moderation(
                    JobId=moderation_job_id
                )
                results['moderation'] = {
                    'jobStatus': moderation_response['JobStatus'],
                    'labels': moderation_response.get('ModerationLabels', [])
                }
            except Exception as e:
                print(f"Error getting moderation results: {str(e)}")
        
        # Get segment detection results
        if segment_job_id:
            try:
                segment_response = rekognition.get_segment_detection(
                    JobId=segment_job_id
                )
                results['segments'] = {
                    'jobStatus': segment_response['JobStatus'],
                    'technicalCues': segment_response.get('TechnicalCues', []),
                    'shotSegments': segment_response.get('Segments', [])
                }
            except Exception as e:
                print(f"Error getting segment results: {str(e)}")
        
        # Create summary
        moderation_labels = results['moderation'].get('labels', [])
        segment_count = len(results['segments'].get('shotSegments', []))
        
        results['summary'] = {
            'moderationLabelsCount': len(moderation_labels),
            'segmentCount': segment_count,
            'hasInappropriateContent': len(moderation_labels) > 0,
            'analysisComplete': True
        }
        
        # Store results in S3
        results_key = f"analysis-results/{job_id}/results.json"
        s3.put_object(
            Bucket=os.environ['RESULTS_BUCKET'],
            Key=results_key,
            Body=json.dumps(results, indent=2),
            ContentType='application/json'
        )
        
        # Update DynamoDB with final results
        table.update_item(
            Key={
                'VideoId': video_id,
                'Timestamp': int(datetime.now().timestamp())
            },
            UpdateExpression='SET JobStatus = :status, ResultsS3Key = :s3key, Summary = :summary',
            ExpressionAttributeValues={
                ':status': 'COMPLETED',
                ':s3key': results_key,
                ':summary': results['summary']
            }
        )
        
        return {
            'statusCode': 200,
            'body': {
                'jobId': job_id,
                'videoId': video_id,
                'resultsLocation': f"s3://{os.environ['RESULTS_BUCKET']}/{results_key}",
                'summary': results['summary'],
                'status': 'COMPLETED'
            }
        }
        
    except Exception as e:
        print(f"Error aggregating results: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': str(e)
            }
        }
      `),
      timeout: Duration.seconds(300),
      memorySize: 512,
      environment: {
        ANALYSIS_TABLE: analysisTable.tableName,
        RESULTS_BUCKET: resultsBucket.bucketName,
      },
      role: lambdaRole,
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // ========================================
    // Step Functions State Machine
    // ========================================
    
    // Step Functions execution role
    const stepFunctionsRole = new iam.Role(this, 'VideoAnalysisStepFunctionsRole', {
      roleName: `VideoAnalysisStepFunctionsRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('states.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSStepFunctionsRole'),
      ],
    });

    // Custom policy for Step Functions
    const stepFunctionsPolicy = new iam.Policy(this, 'VideoAnalysisStepFunctionsPolicy', {
      policyName: `VideoAnalysisStepFunctionsPolicy-${uniqueSuffix}`,
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: ['lambda:InvokeFunction'],
          resources: [
            initFunction.functionArn,
            moderationFunction.functionArn,
            segmentFunction.functionArn,
            aggregationFunction.functionArn,
          ],
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: ['sns:Publish'],
          resources: [notificationTopic.topicArn],
        }),
      ],
    });

    stepFunctionsRole.attachInlinePolicy(stepFunctionsPolicy);

    // Define Step Functions workflow
    const initTask = new sfn_tasks.LambdaInvoke(this, 'InitializeAnalysis', {
      lambdaFunction: initFunction,
      outputPath: '$.Payload',
      retryOnServiceExceptions: true,
    });

    const moderationTask = new sfn_tasks.LambdaInvoke(this, 'ContentModeration', {
      lambdaFunction: moderationFunction,
      inputPath: '$.body',
      outputPath: '$.Payload',
      retryOnServiceExceptions: true,
    });

    const segmentTask = new sfn_tasks.LambdaInvoke(this, 'SegmentDetection', {
      lambdaFunction: segmentFunction,
      inputPath: '$.body',
      outputPath: '$.Payload',
      retryOnServiceExceptions: true,
    });

    const waitTask = new stepfunctions.Wait(this, 'WaitForCompletion', {
      time: stepfunctions.WaitTime.duration(Duration.seconds(60)),
    });

    const aggregationTask = new sfn_tasks.LambdaInvoke(this, 'AggregateResults', {
      lambdaFunction: aggregationFunction,
      payload: stepfunctions.TaskInput.fromObject({
        'jobId.$': '$[0].body.jobId',
        'videoId.$': '$[0].body.videoId',
        'moderationJobId.$': '$[0].body.moderationJobId',
        'segmentJobId.$': '$[1].body.segmentJobId',
      }),
      outputPath: '$.Payload',
      retryOnServiceExceptions: true,
    });

    const notificationTask = new sfn_tasks.SnsPublish(this, 'NotifyCompletion', {
      topic: notificationTopic,
      message: stepfunctions.TaskInput.fromJsonPathAt('$.body'),
    });

    // Define parallel processing branch
    const parallelAnalysis = new stepfunctions.Parallel(this, 'ParallelAnalysis')
      .branch(moderationTask)
      .branch(segmentTask);

    // Define the workflow
    const definition = initTask
      .next(parallelAnalysis)
      .next(waitTask)
      .next(aggregationTask)
      .next(notificationTask);

    // Create the state machine
    const stateMachine = new stepfunctions.StateMachine(this, 'VideoAnalysisWorkflow', {
      stateMachineName: `VideoAnalysisWorkflow-${uniqueSuffix}`,
      definition,
      role: stepFunctionsRole,
      timeout: Duration.hours(2),
      logs: {
        destination: new logs.LogGroup(this, 'VideoAnalysisStateMachineLogGroup', {
          logGroupName: `/aws/stepfunctions/VideoAnalysisWorkflow-${uniqueSuffix}`,
          retention: logs.RetentionDays.ONE_WEEK,
          removalPolicy: RemovalPolicy.DESTROY,
        }),
        level: stepfunctions.LogLevel.ALL,
      },
    });

    // ========================================
    // S3 Event Trigger
    // ========================================
    
    // Lambda function for S3 event trigger
    const triggerFunction = new lambda.Function(this, 'VideoAnalysisTriggerFunction', {
      functionName: `VideoAnalysisTriggerFunction-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import os

def lambda_handler(event, context):
    """
    Trigger video analysis workflow when new video is uploaded
    """
    try:
        stepfunctions = boto3.client('stepfunctions')
        
        # Extract S3 event information
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']
            
            # Only process video files
            if not key.lower().endswith(('.mp4', '.avi', '.mov', '.mkv', '.wmv')):
                continue
            
            # Start Step Functions execution
            response = stepfunctions.start_execution(
                stateMachineArn=os.environ['STATE_MACHINE_ARN'],
                input=json.dumps({
                    'Records': [record]
                })
            )
            
            print(f"Started analysis for {bucket}/{key}: {response['executionArn']}")
        
        return {
            'statusCode': 200,
            'body': 'Video analysis workflow triggered successfully'
        }
        
    except Exception as e:
        print(f"Error triggering workflow: {str(e)}")
        return {
            'statusCode': 500,
            'body': str(e)
        }
      `),
      timeout: Duration.seconds(60),
      memorySize: 256,
      environment: {
        STATE_MACHINE_ARN: stateMachine.stateMachineArn,
      },
      role: lambdaRole,
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Grant Step Functions execution permissions to trigger function
    stateMachine.grantStartExecution(triggerFunction);

    // Add S3 event notification
    sourceBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(triggerFunction),
      { suffix: '.mp4' }
    );

    // ========================================
    // CloudWatch Monitoring and Alarms
    // ========================================
    
    // CloudWatch dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'VideoAnalysisDashboard', {
      dashboardName: `VideoAnalysisDashboard-${uniqueSuffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Lambda Function Duration',
            left: [
              initFunction.metricDuration(),
              moderationFunction.metricDuration(),
              segmentFunction.metricDuration(),
              aggregationFunction.metricDuration(),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Step Functions Executions',
            left: [
              stateMachine.metricSucceeded(),
              stateMachine.metricFailed(),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'DynamoDB Operations',
            left: [
              analysisTable.metricConsumedReadCapacityUnits(),
              analysisTable.metricConsumedWriteCapacityUnits(),
            ],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // CloudWatch alarm for failed executions
    const failedExecutionsAlarm = new cloudwatch.Alarm(this, 'VideoAnalysisFailedExecutionsAlarm', {
      alarmName: `VideoAnalysisFailedExecutions-${uniqueSuffix}`,
      alarmDescription: 'Alert when Step Functions executions fail',
      metric: stateMachine.metricFailed(),
      threshold: 1,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add SNS action to the alarm
    failedExecutionsAlarm.addAlarmAction(
      new cloudwatch_actions.SnsAction(notificationTopic)
    );

    // ========================================
    // Stack Outputs
    // ========================================
    
    new cdk.CfnOutput(this, 'SourceBucketName', {
      value: sourceBucket.bucketName,
      description: 'S3 bucket for uploading videos to analyze',
      exportName: `VideoAnalysis-SourceBucket-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'ResultsBucketName', {
      value: resultsBucket.bucketName,
      description: 'S3 bucket containing analysis results',
      exportName: `VideoAnalysis-ResultsBucket-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'AnalysisTableName', {
      value: analysisTable.tableName,
      description: 'DynamoDB table tracking analysis jobs',
      exportName: `VideoAnalysis-AnalysisTable-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'StateMachineArn', {
      value: stateMachine.stateMachineArn,
      description: 'Step Functions state machine ARN',
      exportName: `VideoAnalysis-StateMachine-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: notificationTopic.topicArn,
      description: 'SNS topic for video analysis notifications',
      exportName: `VideoAnalysis-NotificationTopic-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'NotificationQueueUrl', {
      value: notificationQueue.queueUrl,
      description: 'SQS queue for video analysis notifications',
      exportName: `VideoAnalysis-NotificationQueue-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch dashboard URL for monitoring',
      exportName: `VideoAnalysis-Dashboard-${uniqueSuffix}`,
    });
  }
}

// ========================================
// CDK App Entry Point
// ========================================

const app = new cdk.App();

// Create the stack with default configuration
new VideoContentAnalysisStack(app, 'VideoContentAnalysisStack', {
  description: 'Comprehensive video content analysis solution using Amazon Rekognition and Step Functions',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'VideoContentAnalysis',
    Environment: 'Production',
    Owner: 'DevOps Team',
    CostCenter: 'Media Services',
  },
});

// Synthesize the CloudFormation template
app.synth();