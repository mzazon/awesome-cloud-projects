#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as logs from 'aws-cdk-lib/aws-logs';
import { NagSuppressions } from 'cdk-nag';

/**
 * Stack for building video processing workflows with S3, Lambda, and MediaConvert
 * 
 * This stack creates:
 * - S3 buckets for video source and output
 * - Lambda functions for video processing orchestration
 * - IAM roles with appropriate permissions
 * - EventBridge rules for job completion handling
 * - CloudFront distribution for content delivery
 */
export class VideoProcessingWorkflowStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // S3 Buckets for video processing
    const sourceBucket = new s3.Bucket(this, 'VideoSourceBucket', {
      bucketName: `video-source-${uniqueSuffix}`,
      versioned: true,
      enforceSSL: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteIncompleteMultipartUploads',
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(1),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    const outputBucket = new s3.Bucket(this, 'VideoOutputBucket', {
      bucketName: `video-output-${uniqueSuffix}`,
      versioned: true,
      enforceSSL: true,
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
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // IAM Role for MediaConvert
    const mediaConvertRole = new iam.Role(this, 'MediaConvertRole', {
      roleName: `MediaConvertRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('mediaconvert.amazonaws.com'),
      description: 'Role for MediaConvert to access S3 buckets',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonS3ReadOnlyAccess'),
      ],
    });

    // Grant MediaConvert write access to output bucket
    outputBucket.grantWrite(mediaConvertRole);

    // IAM Role for Lambda functions
    const lambdaRole = new iam.Role(this, 'LambdaRole', {
      roleName: `LambdaVideoProcessorRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for Lambda functions to orchestrate video processing',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Custom policy for Lambda to access MediaConvert and S3
    const lambdaPolicy = new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'mediaconvert:*',
            's3:GetObject',
            's3:PutObject',
            'iam:PassRole',
          ],
          resources: ['*'],
        }),
      ],
    });

    lambdaRole.attachInlinePolicy(new iam.Policy(this, 'LambdaMediaConvertPolicy', {
      policyName: `LambdaMediaConvertPolicy-${uniqueSuffix}`,
      document: lambdaPolicy,
    }));

    // Lambda function for video processing
    const videoProcessorFunction = new lambda.Function(this, 'VideoProcessorFunction', {
      functionName: `video-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import urllib.parse
import os

def lambda_handler(event, context):
    # Initialize MediaConvert client
    mediaconvert = boto3.client('mediaconvert', 
        endpoint_url=os.environ['MEDIACONVERT_ENDPOINT'])
    
    # Parse S3 event
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(record['s3']['object']['key'])
        
        # Skip if not a video file
        if not key.lower().endswith(('.mp4', '.mov', '.avi', '.mkv', '.m4v')):
            continue
        
        # Create job settings
        job_settings = {
            "Role": os.environ['MEDIACONVERT_ROLE_ARN'],
            "Settings": {
                "Inputs": [{
                    "AudioSelectors": {
                        "Audio Selector 1": {
                            "Offset": 0,
                            "DefaultSelection": "DEFAULT",
                            "ProgramSelection": 1
                        }
                    },
                    "VideoSelector": {
                        "ColorSpace": "FOLLOW"
                    },
                    "FilterEnable": "AUTO",
                    "PsiControl": "USE_PSI",
                    "FilterStrength": 0,
                    "DeblockFilter": "DISABLED",
                    "DenoiseFilter": "DISABLED",
                    "TimecodeSource": "EMBEDDED",
                    "FileInput": f"s3://{bucket}/{key}"
                }],
                "OutputGroups": [
                    {
                        "Name": "Apple HLS",
                        "OutputGroupSettings": {
                            "Type": "HLS_GROUP_SETTINGS",
                            "HlsGroupSettings": {
                                "ManifestDurationFormat": "INTEGER",
                                "Destination": f"s3://{os.environ['S3_OUTPUT_BUCKET']}/hls/{key.split('.')[0]}/",
                                "TimedMetadataId3Frame": "PRIV",
                                "CodecSpecification": "RFC_4281",
                                "OutputSelection": "MANIFESTS_AND_SEGMENTS",
                                "ProgramDateTimePeriod": 600,
                                "MinSegmentLength": 0,
                                "DirectoryStructure": "SINGLE_DIRECTORY",
                                "ProgramDateTime": "EXCLUDE",
                                "SegmentLength": 10,
                                "ManifestCompression": "NONE",
                                "ClientCache": "ENABLED",
                                "AudioOnlyHeader": "INCLUDE"
                            }
                        },
                        "Outputs": [
                            {
                                "VideoDescription": {
                                    "ScalingBehavior": "DEFAULT",
                                    "TimecodeInsertion": "DISABLED",
                                    "AntiAlias": "ENABLED",
                                    "Sharpness": 50,
                                    "CodecSettings": {
                                        "Codec": "H_264",
                                        "H264Settings": {
                                            "InterlaceMode": "PROGRESSIVE",
                                            "NumberReferenceFrames": 3,
                                            "Syntax": "DEFAULT",
                                            "Softness": 0,
                                            "GopClosedCadence": 1,
                                            "GopSize": 90,
                                            "Slices": 1,
                                            "GopBReference": "DISABLED",
                                            "SlowPal": "DISABLED",
                                            "SpatialAdaptiveQuantization": "ENABLED",
                                            "TemporalAdaptiveQuantization": "ENABLED",
                                            "FlickerAdaptiveQuantization": "DISABLED",
                                            "EntropyEncoding": "CABAC",
                                            "Bitrate": 2000000,
                                            "FramerateControl": "SPECIFIED",
                                            "RateControlMode": "CBR",
                                            "CodecProfile": "MAIN",
                                            "Telecine": "NONE",
                                            "MinIInterval": 0,
                                            "AdaptiveQuantization": "HIGH",
                                            "CodecLevel": "AUTO",
                                            "FieldEncoding": "PAFF",
                                            "SceneChangeDetect": "ENABLED",
                                            "QualityTuningLevel": "SINGLE_PASS",
                                            "FramerateConversionAlgorithm": "DUPLICATE_DROP",
                                            "UnregisteredSeiTimecode": "DISABLED",
                                            "GopSizeUnits": "FRAMES",
                                            "ParControl": "SPECIFIED",
                                            "NumberBFramesBetweenReferenceFrames": 2,
                                            "RepeatPps": "DISABLED",
                                            "FramerateNumerator": 30,
                                            "FramerateDenominator": 1,
                                            "ParNumerator": 1,
                                            "ParDenominator": 1
                                        }
                                    },
                                    "AfdSignaling": "NONE",
                                    "DropFrameTimecode": "ENABLED",
                                    "RespondToAfd": "NONE",
                                    "ColorMetadata": "INSERT",
                                    "Width": 1280,
                                    "Height": 720
                                },
                                "AudioDescriptions": [
                                    {
                                        "AudioTypeControl": "FOLLOW_INPUT",
                                        "CodecSettings": {
                                            "Codec": "AAC",
                                            "AacSettings": {
                                                "AudioDescriptionBroadcasterMix": "NORMAL",
                                                "Bitrate": 96000,
                                                "RateControlMode": "CBR",
                                                "CodecProfile": "LC",
                                                "CodingMode": "CODING_MODE_2_0",
                                                "RawFormat": "NONE",
                                                "SampleRate": 48000,
                                                "Specification": "MPEG4"
                                            }
                                        },
                                        "AudioSourceName": "Audio Selector 1",
                                        "LanguageCodeControl": "FOLLOW_INPUT"
                                    }
                                ],
                                "OutputSettings": {
                                    "HlsSettings": {
                                        "AudioGroupId": "program_audio",
                                        "AudioTrackType": "ALTERNATE_AUDIO_AUTO_SELECT_DEFAULT",
                                        "IFrameOnlyManifest": "EXCLUDE"
                                    }
                                },
                                "NameModifier": "_720p"
                            }
                        ]
                    },
                    {
                        "Name": "File Group",
                        "OutputGroupSettings": {
                            "Type": "FILE_GROUP_SETTINGS",
                            "FileGroupSettings": {
                                "Destination": f"s3://{os.environ['S3_OUTPUT_BUCKET']}/mp4/"
                            }
                        },
                        "Outputs": [
                            {
                                "VideoDescription": {
                                    "Width": 1280,
                                    "Height": 720,
                                    "CodecSettings": {
                                        "Codec": "H_264",
                                        "H264Settings": {
                                            "Bitrate": 2000000,
                                            "RateControlMode": "CBR",
                                            "CodecProfile": "MAIN",
                                            "GopSize": 90,
                                            "FramerateControl": "SPECIFIED",
                                            "FramerateNumerator": 30,
                                            "FramerateDenominator": 1
                                        }
                                    }
                                },
                                "AudioDescriptions": [
                                    {
                                        "CodecSettings": {
                                            "Codec": "AAC",
                                            "AacSettings": {
                                                "Bitrate": 96000,
                                                "SampleRate": 48000
                                            }
                                        },
                                        "AudioSourceName": "Audio Selector 1"
                                    }
                                ],
                                "ContainerSettings": {
                                    "Container": "MP4",
                                    "Mp4Settings": {
                                        "CslgAtom": "INCLUDE",
                                        "FreeSpaceBox": "EXCLUDE",
                                        "MoovPlacement": "PROGRESSIVE_DOWNLOAD"
                                    }
                                },
                                "NameModifier": "_720p"
                            }
                        ]
                    }
                ]
            }
        }
        
        # Create MediaConvert job
        try:
            response = mediaconvert.create_job(**job_settings)
            job_id = response['Job']['Id']
            print(f"Created MediaConvert job: {job_id} for {key}")
            
        except Exception as e:
            print(f"Error creating MediaConvert job: {str(e)}")
            raise
    
    return {
        'statusCode': 200,
        'body': json.dumps('Video processing initiated successfully')
    }
`),
      role: lambdaRole,
      timeout: cdk.Duration.seconds(60),
      environment: {
        'MEDIACONVERT_ENDPOINT': `https://${uniqueSuffix}.mediaconvert.${this.region}.amazonaws.com`,
        'MEDIACONVERT_ROLE_ARN': mediaConvertRole.roleArn,
        'S3_OUTPUT_BUCKET': outputBucket.bucketName,
      },
      logRetention: logs.RetentionDays.ONE_MONTH,
      description: 'Lambda function to orchestrate video processing with MediaConvert',
    });

    // Grant Lambda access to S3 buckets
    sourceBucket.grantRead(videoProcessorFunction);
    outputBucket.grantReadWrite(videoProcessorFunction);

    // Lambda function for job completion handling
    const completionHandlerFunction = new lambda.Function(this, 'CompletionHandlerFunction', {
      functionName: `completion-handler-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3

def lambda_handler(event, context):
    print(f"MediaConvert job completed: {json.dumps(event)}")
    
    # Extract job details
    job_id = event['detail']['jobId']
    status = event['detail']['status']
    
    # Here you can add additional processing logic:
    # - Send notifications
    # - Update database records
    # - Trigger additional workflows
    
    print(f"Job {job_id} completed with status: {status}")
    
    return {
        'statusCode': 200,
        'body': json.dumps('Job completion handled successfully')
    }
`),
      role: lambdaRole,
      timeout: cdk.Duration.seconds(30),
      logRetention: logs.RetentionDays.ONE_MONTH,
      description: 'Lambda function to handle MediaConvert job completion events',
    });

    // S3 event notification to trigger video processing
    sourceBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(videoProcessorFunction),
      {
        suffix: '.mp4',
      }
    );

    // EventBridge rule for MediaConvert job completion
    const jobCompletionRule = new events.Rule(this, 'MediaConvertJobCompletionRule', {
      ruleName: `MediaConvert-JobComplete-${uniqueSuffix}`,
      description: 'Trigger when MediaConvert job completes',
      eventPattern: {
        source: ['aws.mediaconvert'],
        detailType: ['MediaConvert Job State Change'],
        detail: {
          status: ['COMPLETE'],
        },
      },
    });

    // Add Lambda target to EventBridge rule
    jobCompletionRule.addTarget(new targets.LambdaFunction(completionHandlerFunction));

    // CloudFront Origin Access Identity for S3 access
    const originAccessIdentity = new cloudfront.OriginAccessIdentity(this, 'OriginAccessIdentity', {
      comment: `OAI for video output bucket ${outputBucket.bucketName}`,
    });

    // Grant CloudFront read access to output bucket
    outputBucket.grantRead(originAccessIdentity);

    // CloudFront distribution for video delivery
    const distribution = new cloudfront.Distribution(this, 'VideoDistribution', {
      comment: 'Video streaming distribution',
      defaultBehavior: {
        origin: new origins.S3Origin(outputBucket, {
          originAccessIdentity: originAccessIdentity,
        }),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
        compress: true,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED_FOR_UNCOMPRESSED_OBJECTS,
      },
      priceClass: cloudfront.PriceClass.PRICE_CLASS_100,
      enableIpv6: true,
      httpVersion: cloudfront.HttpVersion.HTTP2,
      enabled: true,
    });

    // CDK Nag suppressions for security compliance
    NagSuppressions.addResourceSuppressions(lambdaRole, [
      {
        id: 'AwsSolutions-IAM4',
        reason: 'AWS managed policies are used for Lambda basic execution role',
      },
    ]);

    NagSuppressions.addResourceSuppressions(lambdaPolicy, [
      {
        id: 'AwsSolutions-IAM5',
        reason: 'Wildcard permissions required for MediaConvert operations across different resources',
      },
    ]);

    // CloudFormation outputs
    new cdk.CfnOutput(this, 'SourceBucketName', {
      value: sourceBucket.bucketName,
      description: 'Name of the S3 bucket for video source files',
      exportName: `${this.stackName}-SourceBucketName`,
    });

    new cdk.CfnOutput(this, 'OutputBucketName', {
      value: outputBucket.bucketName,
      description: 'Name of the S3 bucket for processed video outputs',
      exportName: `${this.stackName}-OutputBucketName`,
    });

    new cdk.CfnOutput(this, 'VideoProcessorFunctionName', {
      value: videoProcessorFunction.functionName,
      description: 'Name of the Lambda function for video processing',
      exportName: `${this.stackName}-VideoProcessorFunctionName`,
    });

    new cdk.CfnOutput(this, 'CompletionHandlerFunctionName', {
      value: completionHandlerFunction.functionName,
      description: 'Name of the Lambda function for completion handling',
      exportName: `${this.stackName}-CompletionHandlerFunctionName`,
    });

    new cdk.CfnOutput(this, 'MediaConvertRoleArn', {
      value: mediaConvertRole.roleArn,
      description: 'ARN of the IAM role for MediaConvert',
      exportName: `${this.stackName}-MediaConvertRoleArn`,
    });

    new cdk.CfnOutput(this, 'CloudFrontDistributionId', {
      value: distribution.distributionId,
      description: 'ID of the CloudFront distribution for video delivery',
      exportName: `${this.stackName}-CloudFrontDistributionId`,
    });

    new cdk.CfnOutput(this, 'CloudFrontDomainName', {
      value: distribution.distributionDomainName,
      description: 'Domain name of the CloudFront distribution',
      exportName: `${this.stackName}-CloudFrontDomainName`,
    });

    new cdk.CfnOutput(this, 'VideoProcessingInstructions', {
      value: `Upload video files to s3://${sourceBucket.bucketName}/ to trigger automatic processing. Processed videos will be available at https://${distribution.distributionDomainName}/`,
      description: 'Instructions for using the video processing pipeline',
    });
  }
}

// CDK App
const app = new cdk.App();

// Stack instantiation
new VideoProcessingWorkflowStack(app, 'VideoProcessingWorkflowStack', {
  description: 'Video processing workflow with S3, Lambda, and MediaConvert (uksb-1tupboc57)',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'VideoProcessingWorkflow',
    Environment: 'Development',
    CostCenter: 'Media',
  },
});

// Synthesize the app
app.synth();