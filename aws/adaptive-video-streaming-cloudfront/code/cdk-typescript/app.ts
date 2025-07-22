#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as s3Notifications from 'aws-cdk-lib/aws-s3-notifications';
import * as mediaconvert from 'aws-cdk-lib/aws-mediaconvert';
import { NagSuppressions } from 'cdk-nag';

/**
 * Interface for stack properties with customizable parameters
 */
interface AdaptiveBitrateStreamingStackProps extends cdk.StackProps {
  readonly sourceBucketName?: string;
  readonly outputBucketName?: string;
  readonly enableS3WebsiteHosting?: boolean;
  readonly cloudfrontPriceClass?: cloudfront.PriceClass;
  readonly enableThumbnailGeneration?: boolean;
}

/**
 * CDK Stack for Adaptive Bitrate Video Streaming with CloudFront
 * 
 * This stack creates:
 * - S3 buckets for source videos and ABR outputs
 * - MediaConvert job template for multi-bitrate transcoding
 * - Lambda function for automated processing
 * - CloudFront distribution for global content delivery
 * - IAM roles with least privilege access
 */
export class AdaptiveBitrateStreamingStack extends cdk.Stack {
  public readonly sourceBucket: s3.Bucket;
  public readonly outputBucket: s3.Bucket;
  public readonly cloudfrontDistribution: cloudfront.Distribution;
  public readonly processingFunction: lambda.Function;
  public readonly mediaconvertJobTemplate: mediaconvert.CfnJobTemplate;

  constructor(scope: Construct, id: string, props?: AdaptiveBitrateStreamingStackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // Create S3 bucket for source video uploads
    this.sourceBucket = new s3.Bucket(this, 'SourceVideoBucket', {
      bucketName: props?.sourceBucketName || `video-source-${uniqueSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: false,
      lifecycleRules: [
        {
          id: 'DeleteIncompleteMultipartUploads',
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
        },
      ],
    });

    // Create S3 bucket for ABR streaming outputs
    this.outputBucket = new s3.Bucket(this, 'OutputStreamingBucket', {
      bucketName: props?.outputBucketName || `video-abr-output-${uniqueSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: false,
      cors: [
        {
          allowedMethods: [s3.HttpMethods.GET, s3.HttpMethods.HEAD],
          allowedOrigins: ['*'],
          allowedHeaders: ['*'],
          maxAge: 3000,
        },
      ],
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
    });

    // Enable S3 website hosting if requested (for test player)
    if (props?.enableS3WebsiteHosting) {
      this.outputBucket.addToResourcePolicy(
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          principals: [new iam.AnyPrincipal()],
          actions: ['s3:GetObject'],
          resources: [`${this.outputBucket.bucketArn}/*`],
          conditions: {
            StringEquals: {
              's3:ExistingObjectTag/PublicRead': 'true',
            },
          },
        })
      );
    }

    // Create IAM role for MediaConvert service
    const mediaconvertRole = new iam.Role(this, 'MediaConvertServiceRole', {
      assumedBy: new iam.ServicePrincipal('mediaconvert.amazonaws.com'),
      description: 'IAM role for MediaConvert to access S3 buckets for ABR processing',
      inlinePolicies: {
        S3AccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
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
              ],
            }),
          ],
        }),
      },
    });

    // Create comprehensive MediaConvert job template for ABR streaming
    this.mediaconvertJobTemplate = new mediaconvert.CfnJobTemplate(this, 'ABRJobTemplate', {
      name: `ABRStreamingTemplate-${uniqueSuffix}`,
      description: 'Adaptive bitrate streaming template with HLS, DASH outputs, and thumbnail generation',
      settingsJson: {
        OutputGroups: [
          // HLS Output Group for iOS and Safari compatibility
          {
            Name: 'HLS_ABR_Package',
            OutputGroupSettings: {
              Type: 'HLS_GROUP_SETTINGS',
              HlsGroupSettings: {
                Destination: `s3://${this.outputBucket.bucketName}/hls/`,
                HlsCdnSettings: {
                  HlsBasicPutSettings: {
                    ConnectionRetryInterval: 1,
                    FilecacheDuration: 300,
                    NumRetries: 10,
                  },
                },
                ManifestDurationFormat: 'FLOATING_POINT',
                OutputSelection: 'MANIFESTS_AND_SEGMENTS',
                SegmentControl: 'SEGMENTED_FILES',
                SegmentLength: 6,
                TimedMetadataId3Frame: 'PRIV',
                TimedMetadataId3Period: 10,
                MinSegmentLength: 0,
                DirectoryStructure: 'SINGLE_DIRECTORY',
              },
            },
            Outputs: this.createHLSOutputs(),
          },
          // DASH Output Group for broader device compatibility
          {
            Name: 'DASH_ABR_Package',
            OutputGroupSettings: {
              Type: 'DASH_ISO_GROUP_SETTINGS',
              DashIsoGroupSettings: {
                Destination: `s3://${this.outputBucket.bucketName}/dash/`,
                FragmentLength: 2,
                SegmentControl: 'SEGMENTED_FILES',
                SegmentLength: 30,
                MpdProfile: 'ON_DEMAND_PROFILE',
                HbbtvCompliance: 'NONE',
              },
            },
            Outputs: this.createDASHOutputs(),
          },
          // Thumbnail Generation Output Group (conditional)
          ...(props?.enableThumbnailGeneration !== false ? [
            {
              Name: 'Thumbnail_Output',
              OutputGroupSettings: {
                Type: 'FILE_GROUP_SETTINGS',
                FileGroupSettings: {
                  Destination: `s3://${this.outputBucket.bucketName}/thumbnails/`,
                },
              },
              Outputs: [
                {
                  NameModifier: '_thumb_%04d',
                  ContainerSettings: {
                    Container: 'RAW',
                  },
                  VideoDescription: {
                    Width: 1280,
                    Height: 720,
                    CodecSettings: {
                      Codec: 'FRAME_CAPTURE',
                      FrameCaptureSettings: {
                        FramerateNumerator: 1,
                        FramerateDenominator: 10,
                        MaxCaptures: 10,
                        Quality: 80,
                      },
                    },
                  },
                },
              ],
            },
          ] : []),
        ],
        Inputs: [
          {
            FileInput: `s3://${this.sourceBucket.bucketName}/`,
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
    });

    // Create Lambda function for automated video processing
    this.processingFunction = new lambda.Function(this, 'VideoProcessingFunction', {
      functionName: `video-abr-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      environment: {
        OUTPUT_BUCKET: this.outputBucket.bucketName,
        JOB_TEMPLATE: this.mediaconvertJobTemplate.name!,
        MEDIACONVERT_ROLE_ARN: mediaconvertRole.roleArn,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from urllib.parse import unquote_plus

def lambda_handler(event, context):
    """
    Lambda function to process S3 video upload events and trigger MediaConvert ABR transcoding.
    
    This function:
    1. Validates incoming S3 events for video files
    2. Extracts video metadata and creates output paths
    3. Submits MediaConvert jobs using the pre-configured ABR template
    4. Returns job details for monitoring and tracking
    """
    
    # Initialize MediaConvert client with region-specific endpoint
    mediaconvert_client = boto3.client('mediaconvert')
    
    # Get MediaConvert endpoint for this region
    try:
        endpoints = mediaconvert_client.describe_endpoints()
        mediaconvert_endpoint = endpoints['Endpoints'][0]['Url']
        mediaconvert = boto3.client('mediaconvert', endpoint_url=mediaconvert_endpoint)
    except Exception as e:
        print(f"Error getting MediaConvert endpoint: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Failed to initialize MediaConvert client'})
        }
    
    # Process each S3 event record
    results = []
    for record in event['Records']:
        try:
            # Extract S3 event details
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            # Validate file extension for video content
            video_extensions = ('.mp4', '.mov', '.avi', '.mkv', '.mxf', '.mts', '.m2ts', '.webm')
            if not key.lower().endswith(video_extensions):
                print(f"Skipping non-video file: {key}")
                continue
            
            # Extract filename for output organization
            file_name = key.split('/')[-1].split('.')[0]
            
            # Create MediaConvert job for ABR processing
            job_settings = {
                'JobTemplate': os.environ['JOB_TEMPLATE'],
                'Role': os.environ['MEDIACONVERT_ROLE_ARN'],
                'Settings': {
                    'Inputs': [
                        {
                            'FileInput': f's3://{bucket}/{key}',
                            'AudioSelectors': {
                                'Audio Selector 1': {
                                    'Tracks': [1],
                                    'DefaultSelection': 'DEFAULT'
                                }
                            },
                            'VideoSelector': {
                                'ColorSpace': 'FOLLOW'
                            },
                            'TimecodeSource': 'EMBEDDED'
                        }
                    ],
                    'OutputGroups': [
                        {
                            'OutputGroupSettings': {
                                'Type': 'HLS_GROUP_SETTINGS',
                                'HlsGroupSettings': {
                                    'Destination': f's3://{os.environ["OUTPUT_BUCKET"]}/hls/{file_name}/'
                                }
                            }
                        },
                        {
                            'OutputGroupSettings': {
                                'Type': 'DASH_ISO_GROUP_SETTINGS',
                                'DashIsoGroupSettings': {
                                    'Destination': f's3://{os.environ["OUTPUT_BUCKET"]}/dash/{file_name}/'
                                }
                            }
                        },
                        {
                            'OutputGroupSettings': {
                                'Type': 'FILE_GROUP_SETTINGS',
                                'FileGroupSettings': {
                                    'Destination': f's3://{os.environ["OUTPUT_BUCKET"]}/thumbnails/{file_name}/'
                                }
                            }
                        }
                    ]
                },
                'StatusUpdateInterval': 'SECONDS_60',
                'UserMetadata': {
                    'SourceFile': key,
                    'ProcessingType': 'ABR_Streaming',
                    'StackName': '${this.stackName}'
                }
            }
            
            # Submit MediaConvert job
            response = mediaconvert.create_job(**job_settings)
            job_id = response['Job']['Id']
            
            print(f"Successfully created ABR processing job {job_id} for {key}")
            
            # Track successful job creation
            results.append({
                'jobId': job_id,
                'sourceFile': key,
                'hlsOutput': f's3://{os.environ["OUTPUT_BUCKET"]}/hls/{file_name}/',
                'dashOutput': f's3://{os.environ["OUTPUT_BUCKET"]}/dash/{file_name}/',
                'status': 'SUBMITTED'
            })
            
        except Exception as e:
            print(f"Error processing {key}: {str(e)}")
            results.append({
                'sourceFile': key,
                'error': str(e),
                'status': 'FAILED'
            })
    
    # Return processing results
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Processed {len(results)} files',
            'results': results
        })
    }
      `),
    });

    // Grant Lambda function necessary permissions
    this.processingFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'mediaconvert:CreateJob',
          'mediaconvert:GetJob',
          'mediaconvert:ListJobs',
          'mediaconvert:GetJobTemplate',
          'mediaconvert:DescribeEndpoints',
        ],
        resources: ['*'],
      })
    );

    // Allow Lambda to pass the MediaConvert role
    this.processingFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['iam:PassRole'],
        resources: [mediaconvertRole.roleArn],
      })
    );

    // Configure S3 event notification to trigger Lambda
    this.sourceBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3Notifications.LambdaDestination(this.processingFunction),
      {
        suffix: '.mp4',
      }
    );

    // Add notification for additional video formats
    const videoFormats = ['.mov', '.avi', '.mkv', '.mxf', '.webm'];
    videoFormats.forEach(format => {
      this.sourceBucket.addEventNotification(
        s3.EventType.OBJECT_CREATED,
        new s3Notifications.LambdaDestination(this.processingFunction),
        {
          suffix: format,
        }
      );
    });

    // Create CloudFront distribution for global content delivery
    this.cloudfrontDistribution = new cloudfront.Distribution(this, 'StreamingDistribution', {
      comment: 'Adaptive Bitrate Streaming Distribution for global video delivery',
      defaultBehavior: {
        origin: new origins.S3Origin(this.outputBucket),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        compress: false,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
      },
      additionalBehaviors: {
        // HLS manifest files - short cache for adaptive switching
        '*.m3u8': {
          origin: new origins.S3Origin(this.outputBucket),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          cachePolicy: new cloudfront.CachePolicy(this, 'HLSManifestCachePolicy', {
            cachePolicyName: `HLS-Manifest-Cache-${uniqueSuffix}`,
            comment: 'Cache policy for HLS manifest files with short TTL',
            defaultTtl: cdk.Duration.seconds(5),
            maxTtl: cdk.Duration.seconds(60),
            minTtl: cdk.Duration.seconds(0),
            headerBehavior: cloudfront.CacheHeaderBehavior.none(),
            queryStringBehavior: cloudfront.CacheQueryStringBehavior.none(),
            cookieBehavior: cloudfront.CacheCookieBehavior.none(),
          }),
          compress: false,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
        },
        // DASH manifest files - short cache for adaptive switching
        '*.mpd': {
          origin: new origins.S3Origin(this.outputBucket),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          cachePolicy: new cloudfront.CachePolicy(this, 'DASHManifestCachePolicy', {
            cachePolicyName: `DASH-Manifest-Cache-${uniqueSuffix}`,
            comment: 'Cache policy for DASH manifest files with short TTL',
            defaultTtl: cdk.Duration.seconds(5),
            maxTtl: cdk.Duration.seconds(60),
            minTtl: cdk.Duration.seconds(0),
            headerBehavior: cloudfront.CacheHeaderBehavior.none(),
            queryStringBehavior: cloudfront.CacheQueryStringBehavior.none(),
            cookieBehavior: cloudfront.CacheCookieBehavior.none(),
          }),
          compress: false,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
        },
        // Video segments - long cache for efficiency
        '*.ts': {
          origin: new origins.S3Origin(this.outputBucket),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          cachePolicy: new cloudfront.CachePolicy(this, 'VideoSegmentCachePolicy', {
            cachePolicyName: `Video-Segment-Cache-${uniqueSuffix}`,
            comment: 'Cache policy for video segments with long TTL',
            defaultTtl: cdk.Duration.hours(24),
            maxTtl: cdk.Duration.hours(24),
            minTtl: cdk.Duration.seconds(0),
            headerBehavior: cloudfront.CacheHeaderBehavior.none(),
            queryStringBehavior: cloudfront.CacheQueryStringBehavior.none(),
            cookieBehavior: cloudfront.CacheCookieBehavior.none(),
          }),
          compress: false,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
        },
        // MP4 segments for DASH
        '*.mp4': {
          origin: new origins.S3Origin(this.outputBucket),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
          compress: false,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
        },
      },
      priceClass: props?.cloudfrontPriceClass || cloudfront.PriceClass.PRICE_CLASS_ALL,
      httpVersion: cloudfront.HttpVersion.HTTP2_AND_3,
      enableIpv6: true,
      minimumProtocolVersion: cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
    });

    // Add CDK Nag suppressions for security best practices
    NagSuppressions.addResourceSuppressions(
      this.processingFunction,
      [
        {
          id: 'AwsSolutions-IAM4',
          reason: 'Lambda execution role uses AWS managed policy for basic execution permissions',
        },
        {
          id: 'AwsSolutions-IAM5',
          reason: 'MediaConvert operations require wildcard permissions for job management',
        },
      ]
    );

    NagSuppressions.addResourceSuppressions(
      mediaconvertRole,
      [
        {
          id: 'AwsSolutions-IAM5',
          reason: 'MediaConvert role requires broad S3 permissions for accessing user-uploaded content',
        },
      ]
    );

    // Stack Outputs for integration and monitoring
    new cdk.CfnOutput(this, 'SourceBucketName', {
      value: this.sourceBucket.bucketName,
      description: 'S3 bucket name for uploading source videos',
      exportName: `${this.stackName}-SourceBucket`,
    });

    new cdk.CfnOutput(this, 'OutputBucketName', {
      value: this.outputBucket.bucketName,
      description: 'S3 bucket name containing ABR streaming outputs',
      exportName: `${this.stackName}-OutputBucket`,
    });

    new cdk.CfnOutput(this, 'CloudFrontDistributionId', {
      value: this.cloudfrontDistribution.distributionId,
      description: 'CloudFront distribution ID for global content delivery',
      exportName: `${this.stackName}-DistributionId`,
    });

    new cdk.CfnOutput(this, 'CloudFrontDomainName', {
      value: this.cloudfrontDistribution.distributionDomainName,
      description: 'CloudFront domain name for accessing streaming content',
      exportName: `${this.stackName}-DistributionDomain`,
    });

    new cdk.CfnOutput(this, 'StreamingURLPattern', {
      value: `https://${this.cloudfrontDistribution.distributionDomainName}/hls/{video-name}/index.m3u8`,
      description: 'URL pattern for HLS streaming (replace {video-name} with actual video name)',
    });

    new cdk.CfnOutput(this, 'DASHStreamingURLPattern', {
      value: `https://${this.cloudfrontDistribution.distributionDomainName}/dash/{video-name}/index.mpd`,
      description: 'URL pattern for DASH streaming (replace {video-name} with actual video name)',
    });

    new cdk.CfnOutput(this, 'ProcessingFunctionName', {
      value: this.processingFunction.functionName,
      description: 'Lambda function name for video processing',
      exportName: `${this.stackName}-ProcessingFunction`,
    });

    new cdk.CfnOutput(this, 'JobTemplateName', {
      value: this.mediaconvertJobTemplate.name!,
      description: 'MediaConvert job template name for ABR processing',
      exportName: `${this.stackName}-JobTemplate`,
    });
  }

  /**
   * Creates HLS output configurations for multiple bitrates and resolutions
   * Following industry best practices for adaptive bitrate ladders
   */
  private createHLSOutputs(): any[] {
    const hlsBaseSettings = {
      Container: 'M3U8',
      M3u8Settings: {
        PcrControl: 'PCR_EVERY_PES_PACKET',
        PmtPid: 480,
        PrivateMetadataPid: 503,
        ProgramNumber: 1,
        PatInterval: 0,
        PmtInterval: 0,
        VideoPid: 481,
        AudioPids: [482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492],
      },
    };

    const audioSettings = {
      AudioTypeControl: 'FOLLOW_INPUT',
      CodecSettings: {
        Codec: 'AAC',
        AacSettings: {
          CodingMode: 'CODING_MODE_2_0',
          SampleRate: 48000,
        },
      },
    };

    return [
      // 1080p High Quality
      {
        NameModifier: '_1080p',
        ContainerSettings: hlsBaseSettings,
        VideoDescription: {
          Width: 1920,
          Height: 1080,
          CodecSettings: {
            Codec: 'H_264',
            H264Settings: {
              RateControlMode: 'QVBR',
              QvbrSettings: { QvbrQualityLevel: 8 },
              MaxBitrate: 5000000,
              FramerateControl: 'INITIALIZE_FROM_SOURCE',
              GopClosedCadence: 1,
              GopSize: 90,
              GopSizeUnits: 'FRAMES',
              ParControl: 'INITIALIZE_FROM_SOURCE',
              QualityTuningLevel: 'SINGLE_PASS',
              SceneChangeDetect: 'ENABLED',
            },
          },
        },
        AudioDescriptions: [{ ...audioSettings, CodecSettings: { ...audioSettings.CodecSettings, AacSettings: { ...audioSettings.CodecSettings.AacSettings, Bitrate: 128000 } } }],
      },
      // 720p Medium Quality
      {
        NameModifier: '_720p',
        ContainerSettings: hlsBaseSettings,
        VideoDescription: {
          Width: 1280,
          Height: 720,
          CodecSettings: {
            Codec: 'H_264',
            H264Settings: {
              RateControlMode: 'QVBR',
              QvbrSettings: { QvbrQualityLevel: 7 },
              MaxBitrate: 3000000,
              FramerateControl: 'INITIALIZE_FROM_SOURCE',
              GopClosedCadence: 1,
              GopSize: 90,
              GopSizeUnits: 'FRAMES',
              ParControl: 'INITIALIZE_FROM_SOURCE',
              QualityTuningLevel: 'SINGLE_PASS',
              SceneChangeDetect: 'ENABLED',
            },
          },
        },
        AudioDescriptions: [{ ...audioSettings, CodecSettings: { ...audioSettings.CodecSettings, AacSettings: { ...audioSettings.CodecSettings.AacSettings, Bitrate: 128000 } } }],
      },
      // 480p Low Quality
      {
        NameModifier: '_480p',
        ContainerSettings: hlsBaseSettings,
        VideoDescription: {
          Width: 854,
          Height: 480,
          CodecSettings: {
            Codec: 'H_264',
            H264Settings: {
              RateControlMode: 'QVBR',
              QvbrSettings: { QvbrQualityLevel: 6 },
              MaxBitrate: 1500000,
              FramerateControl: 'INITIALIZE_FROM_SOURCE',
              GopClosedCadence: 1,
              GopSize: 90,
              GopSizeUnits: 'FRAMES',
              ParControl: 'INITIALIZE_FROM_SOURCE',
              QualityTuningLevel: 'SINGLE_PASS',
              SceneChangeDetect: 'ENABLED',
            },
          },
        },
        AudioDescriptions: [{ ...audioSettings, CodecSettings: { ...audioSettings.CodecSettings, AacSettings: { ...audioSettings.CodecSettings.AacSettings, Bitrate: 96000 } } }],
      },
      // 360p Mobile Quality
      {
        NameModifier: '_360p',
        ContainerSettings: hlsBaseSettings,
        VideoDescription: {
          Width: 640,
          Height: 360,
          CodecSettings: {
            Codec: 'H_264',
            H264Settings: {
              RateControlMode: 'QVBR',
              QvbrSettings: { QvbrQualityLevel: 5 },
              MaxBitrate: 800000,
              FramerateControl: 'INITIALIZE_FROM_SOURCE',
              GopClosedCadence: 1,
              GopSize: 90,
              GopSizeUnits: 'FRAMES',
              ParControl: 'INITIALIZE_FROM_SOURCE',
              QualityTuningLevel: 'SINGLE_PASS',
              SceneChangeDetect: 'ENABLED',
            },
          },
        },
        AudioDescriptions: [{ ...audioSettings, CodecSettings: { ...audioSettings.CodecSettings, AacSettings: { ...audioSettings.CodecSettings.AacSettings, Bitrate: 64000 } } }],
      },
    ];
  }

  /**
   * Creates DASH output configurations for broader device compatibility
   * Optimized for web and Android platforms
   */
  private createDASHOutputs(): any[] {
    const dashBaseSettings = {
      Container: 'MP4',
      Mp4Settings: {
        CslgAtom: 'INCLUDE',
        FreeSpaceBox: 'EXCLUDE',
        MoovPlacement: 'PROGRESSIVE_DOWNLOAD',
      },
    };

    const audioSettings = {
      AudioTypeControl: 'FOLLOW_INPUT',
      CodecSettings: {
        Codec: 'AAC',
        AacSettings: {
          CodingMode: 'CODING_MODE_2_0',
          SampleRate: 48000,
        },
      },
    };

    return [
      // 1080p DASH
      {
        NameModifier: '_dash_1080p',
        ContainerSettings: dashBaseSettings,
        VideoDescription: {
          Width: 1920,
          Height: 1080,
          CodecSettings: {
            Codec: 'H_264',
            H264Settings: {
              RateControlMode: 'QVBR',
              QvbrSettings: { QvbrQualityLevel: 8 },
              MaxBitrate: 5000000,
              FramerateControl: 'INITIALIZE_FROM_SOURCE',
              GopClosedCadence: 1,
              GopSize: 90,
              GopSizeUnits: 'FRAMES',
              ParControl: 'INITIALIZE_FROM_SOURCE',
              QualityTuningLevel: 'SINGLE_PASS',
              SceneChangeDetect: 'ENABLED',
            },
          },
        },
        AudioDescriptions: [{ ...audioSettings, CodecSettings: { ...audioSettings.CodecSettings, AacSettings: { ...audioSettings.CodecSettings.AacSettings, Bitrate: 128000 } } }],
      },
      // 720p DASH
      {
        NameModifier: '_dash_720p',
        ContainerSettings: dashBaseSettings,
        VideoDescription: {
          Width: 1280,
          Height: 720,
          CodecSettings: {
            Codec: 'H_264',
            H264Settings: {
              RateControlMode: 'QVBR',
              QvbrSettings: { QvbrQualityLevel: 7 },
              MaxBitrate: 3000000,
              FramerateControl: 'INITIALIZE_FROM_SOURCE',
              GopClosedCadence: 1,
              GopSize: 90,
              GopSizeUnits: 'FRAMES',
              ParControl: 'INITIALIZE_FROM_SOURCE',
              QualityTuningLevel: 'SINGLE_PASS',
              SceneChangeDetect: 'ENABLED',
            },
          },
        },
        AudioDescriptions: [{ ...audioSettings, CodecSettings: { ...audioSettings.CodecSettings, AacSettings: { ...audioSettings.CodecSettings.AacSettings, Bitrate: 128000 } } }],
      },
    ];
  }
}

/**
 * CDK Application entry point
 * 
 * This creates the CDK app and instantiates the adaptive bitrate streaming stack
 * with configurable properties for different deployment scenarios.
 */
const app = new cdk.App();

// Get configuration from CDK context or use defaults
const stackProps: AdaptiveBitrateStreamingStackProps = {
  description: 'Adaptive Bitrate Streaming infrastructure with MediaConvert and CloudFront',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  // Configurable properties from CDK context
  sourceBucketName: app.node.tryGetContext('sourceBucketName'),
  outputBucketName: app.node.tryGetContext('outputBucketName'),
  enableS3WebsiteHosting: app.node.tryGetContext('enableS3WebsiteHosting') ?? false,
  cloudfrontPriceClass: app.node.tryGetContext('cloudfrontPriceClass') === 'US_EUROPE' 
    ? cloudfront.PriceClass.PRICE_CLASS_100 
    : app.node.tryGetContext('cloudfrontPriceClass') === 'US_EUROPE_ASIA'
    ? cloudfront.PriceClass.PRICE_CLASS_200
    : cloudfront.PriceClass.PRICE_CLASS_ALL,
  enableThumbnailGeneration: app.node.tryGetContext('enableThumbnailGeneration') ?? true,
  tags: {
    Project: 'AdaptiveBitrateStreaming',
    Environment: app.node.tryGetContext('environment') || 'development',
    CostCenter: app.node.tryGetContext('costCenter') || 'media-services',
  },
};

// Create the main stack
new AdaptiveBitrateStreamingStack(app, 'AdaptiveBitrateStreamingStack', stackProps);

// Synthesize the CDK app
app.synth();