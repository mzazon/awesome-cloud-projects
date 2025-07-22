#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import { RemovalPolicy } from 'aws-cdk-lib';

/**
 * CDK Stack for AWS Elemental MediaConvert Audio Processing Pipeline
 * 
 * This stack creates a complete audio processing pipeline using:
 * - S3 buckets for input and output
 * - Lambda function for processing triggers
 * - IAM roles for MediaConvert service
 * - SNS topic for notifications
 * - CloudWatch dashboard for monitoring
 */
export class AudioProcessingPipelineStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // ======================
    // S3 Buckets
    // ======================
    
    // Input bucket where audio files are uploaded
    const inputBucket = new s3.Bucket(this, 'AudioInputBucket', {
      bucketName: `audio-processing-input-${uniqueSuffix}`,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'DeleteIncompleteMultipartUploads',
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(1),
          enabled: true,
        },
      ],
    });

    // Output bucket for processed audio files
    const outputBucket = new s3.Bucket(this, 'AudioOutputBucket', {
      bucketName: `audio-processing-output-${uniqueSuffix}`,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'TransitionToIA',
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
          enabled: true,
        },
      ],
    });

    // ======================
    // SNS Topic
    // ======================
    
    // SNS topic for job completion notifications
    const notificationTopic = new sns.Topic(this, 'AudioProcessingNotifications', {
      topicName: `audio-processing-notifications-${uniqueSuffix}`,
      displayName: 'Audio Processing Pipeline Notifications',
    });

    // ======================
    // IAM Roles
    // ======================
    
    // MediaConvert service role
    const mediaConvertRole = new iam.Role(this, 'MediaConvertServiceRole', {
      roleName: `MediaConvertRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('mediaconvert.amazonaws.com'),
      description: 'Service role for AWS Elemental MediaConvert to access S3 and SNS',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSElementalMediaConvertReadOnly'),
      ],
      inlinePolicies: {
        MediaConvertS3SNSPolicy: new iam.PolicyDocument({
          statements: [
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
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [notificationTopic.topicArn],
            }),
          ],
        }),
      },
    });

    // Lambda execution role
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `AudioProcessingLambdaRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for audio processing Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        MediaConvertAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'mediaconvert:CreateJob',
                'mediaconvert:GetJob',
                'mediaconvert:ListJobs',
                'mediaconvert:DescribeEndpoints',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['iam:PassRole'],
              resources: [mediaConvertRole.roleArn],
            }),
          ],
        }),
      },
    });

    // ======================
    // Lambda Function
    // ======================
    
    // Lambda function for processing audio files
    const processingFunction = new lambda.Function(this, 'AudioProcessingFunction', {
      functionName: `audio-processing-trigger-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      description: 'Triggers MediaConvert jobs for audio processing',
      environment: {
        MEDIACONVERT_ROLE_ARN: mediaConvertRole.roleArn,
        OUTPUT_BUCKET: outputBucket.bucketName,
        SNS_TOPIC_ARN: notificationTopic.topicArn,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from urllib.parse import unquote_plus

def lambda_handler(event, context):
    """
    Lambda handler to process S3 events and trigger MediaConvert jobs
    """
    try:
        # Initialize MediaConvert client with endpoint discovery
        mediaconvert = boto3.client('mediaconvert')
        
        # Get MediaConvert endpoint
        endpoints = mediaconvert.describe_endpoints()
        endpoint_url = endpoints['Endpoints'][0]['Url']
        
        # Re-initialize client with specific endpoint
        mediaconvert = boto3.client('mediaconvert', endpoint_url=endpoint_url)
        
        # Process each S3 event record
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            # Validate audio file extension
            if not key.lower().endswith(('.mp3', '.wav', '.flac', '.m4a', '.aac')):
                print(f"Skipping non-audio file: {key}")
                continue
            
            # Extract filename without extension for naming
            filename = key.split('/')[-1].split('.')[0]
            
            # Create MediaConvert job settings
            job_settings = {
                "Role": os.environ['MEDIACONVERT_ROLE_ARN'],
                "Settings": {
                    "OutputGroups": [
                        {
                            "Name": "MP3_Output",
                            "OutputGroupSettings": {
                                "Type": "FILE_GROUP_SETTINGS",
                                "FileGroupSettings": {
                                    "Destination": f"s3://{os.environ['OUTPUT_BUCKET']}/mp3/"
                                }
                            },
                            "Outputs": [
                                {
                                    "NameModifier": "_mp3",
                                    "ContainerSettings": {
                                        "Container": "MP3"
                                    },
                                    "AudioDescriptions": [
                                        {
                                            "AudioTypeControl": "FOLLOW_INPUT",
                                            "CodecSettings": {
                                                "Codec": "MP3",
                                                "Mp3Settings": {
                                                    "Bitrate": 128000,
                                                    "Channels": 2,
                                                    "RateControlMode": "CBR",
                                                    "SampleRate": 44100
                                                }
                                            }
                                        }
                                    ]
                                }
                            ]
                        },
                        {
                            "Name": "AAC_Output",
                            "OutputGroupSettings": {
                                "Type": "FILE_GROUP_SETTINGS",
                                "FileGroupSettings": {
                                    "Destination": f"s3://{os.environ['OUTPUT_BUCKET']}/aac/"
                                }
                            },
                            "Outputs": [
                                {
                                    "NameModifier": "_aac",
                                    "ContainerSettings": {
                                        "Container": "MP4"
                                    },
                                    "AudioDescriptions": [
                                        {
                                            "AudioTypeControl": "FOLLOW_INPUT",
                                            "CodecSettings": {
                                                "Codec": "AAC",
                                                "AacSettings": {
                                                    "Bitrate": 128000,
                                                    "CodingMode": "CODING_MODE_2_0",
                                                    "SampleRate": 44100
                                                }
                                            }
                                        }
                                    ]
                                }
                            ]
                        },
                        {
                            "Name": "FLAC_Output",
                            "OutputGroupSettings": {
                                "Type": "FILE_GROUP_SETTINGS",
                                "FileGroupSettings": {
                                    "Destination": f"s3://{os.environ['OUTPUT_BUCKET']}/flac/"
                                }
                            },
                            "Outputs": [
                                {
                                    "NameModifier": "_flac",
                                    "ContainerSettings": {
                                        "Container": "FLAC"
                                    },
                                    "AudioDescriptions": [
                                        {
                                            "AudioTypeControl": "FOLLOW_INPUT",
                                            "CodecSettings": {
                                                "Codec": "FLAC",
                                                "FlacSettings": {
                                                    "Channels": 2,
                                                    "SampleRate": 44100
                                                }
                                            }
                                        }
                                    ]
                                }
                            ]
                        }
                    ],
                    "Inputs": [
                        {
                            "FileInput": f"s3://{bucket}/{key}",
                            "AudioSelectors": {
                                "Audio Selector 1": {
                                    "Tracks": [1],
                                    "DefaultSelection": "DEFAULT"
                                }
                            }
                        }
                    ]
                },
                "StatusUpdateInterval": "SECONDS_60"
            }
            
            # Submit MediaConvert job
            response = mediaconvert.create_job(**job_settings)
            job_id = response['Job']['Id']
            
            print(f"Created MediaConvert job {job_id} for {key}")
            
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Successfully processed audio files',
                'jobCount': len(event['Records'])
            })
        }
        
    except Exception as e:
        print(f"Error processing audio files: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
`),
    });

    // ======================
    // S3 Event Notifications
    // ======================
    
    // Add S3 event notification for audio files
    const audioExtensions = ['.mp3', '.wav', '.flac', '.m4a', '.aac'];
    
    audioExtensions.forEach((extension, index) => {
      inputBucket.addEventNotification(
        s3.EventType.OBJECT_CREATED,
        new s3n.LambdaDestination(processingFunction),
        { suffix: extension }
      );
    });

    // ======================
    // CloudWatch Dashboard
    // ======================
    
    // CloudWatch dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'AudioProcessingDashboard', {
      dashboardName: `AudioProcessingPipeline-${uniqueSuffix}`,
      defaultInterval: cdk.Duration.minutes(5),
    });

    // MediaConvert metrics
    const mediaConvertJobsWidget = new cloudwatch.GraphWidget({
      title: 'MediaConvert Jobs',
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/MediaConvert',
          metricName: 'JobsCompleted',
          statistic: 'Sum',
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/MediaConvert',
          metricName: 'JobsErrored',
          statistic: 'Sum',
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/MediaConvert',
          metricName: 'JobsSubmitted',
          statistic: 'Sum',
        }),
      ],
      width: 12,
      height: 6,
    });

    // Lambda function metrics
    const lambdaMetricsWidget = new cloudwatch.GraphWidget({
      title: 'Lambda Function Metrics',
      left: [
        processingFunction.metricInvocations(),
        processingFunction.metricErrors(),
      ],
      right: [
        processingFunction.metricDuration(),
      ],
      width: 12,
      height: 6,
    });

    // S3 bucket metrics
    const s3MetricsWidget = new cloudwatch.GraphWidget({
      title: 'S3 Bucket Metrics',
      left: [
        inputBucket.metricNumberOfObjects(),
        outputBucket.metricNumberOfObjects(),
      ],
      right: [
        inputBucket.metricBucketSizeBytes(),
        outputBucket.metricBucketSizeBytes(),
      ],
      width: 12,
      height: 6,
    });

    // Add widgets to dashboard
    dashboard.addWidgets(mediaConvertJobsWidget, lambdaMetricsWidget);
    dashboard.addWidgets(s3MetricsWidget);

    // ======================
    // CloudFormation Outputs
    // ======================
    
    new cdk.CfnOutput(this, 'InputBucketName', {
      value: inputBucket.bucketName,
      description: 'Name of the S3 input bucket for audio files',
      exportName: `${this.stackName}-InputBucketName`,
    });

    new cdk.CfnOutput(this, 'OutputBucketName', {
      value: outputBucket.bucketName,
      description: 'Name of the S3 output bucket for processed audio files',
      exportName: `${this.stackName}-OutputBucketName`,
    });

    new cdk.CfnOutput(this, 'MediaConvertRoleArn', {
      value: mediaConvertRole.roleArn,
      description: 'ARN of the MediaConvert service role',
      exportName: `${this.stackName}-MediaConvertRoleArn`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: processingFunction.functionName,
      description: 'Name of the Lambda function for processing triggers',
      exportName: `${this.stackName}-LambdaFunctionName`,
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: notificationTopic.topicArn,
      description: 'ARN of the SNS topic for notifications',
      exportName: `${this.stackName}-SNSTopicArn`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard',
      exportName: `${this.stackName}-DashboardUrl`,
    });

    // ======================
    // Tags
    // ======================
    
    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'AudioProcessingPipeline');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('Owner', 'MediaTeam');
    cdk.Tags.of(this).add('CostCenter', 'MediaProcessing');
  }
}

// ======================
// CDK App
// ======================

const app = new cdk.App();

// Create the stack
new AudioProcessingPipelineStack(app, 'AudioProcessingPipelineStack', {
  description: 'AWS Elemental MediaConvert Audio Processing Pipeline with S3, Lambda, and CloudWatch monitoring',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Application: 'AudioProcessingPipeline',
    CreatedBy: 'CDK',
  },
});

// Synthesize the CloudFormation template
app.synth();