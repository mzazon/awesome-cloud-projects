#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as medialive from 'aws-cdk-lib/aws-medialive';
import * as mediapackage from 'aws-cdk-lib/aws-mediapackage';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import { CfnOutput, RemovalPolicy } from 'aws-cdk-lib';

/**
 * Props for the LiveStreamingStack
 */
export interface LiveStreamingStackProps extends cdk.StackProps {
  /**
   * Name prefix for all resources
   * @default 'live-streaming'
   */
  readonly namePrefix?: string;
  
  /**
   * Enable CloudWatch detailed monitoring
   * @default true
   */
  readonly enableDetailedMonitoring?: boolean;
  
  /**
   * S3 bucket for archiving streams
   * @default Creates a new bucket
   */
  readonly archiveBucket?: s3.IBucket;
  
  /**
   * CIDR blocks allowed to push to MediaLive input
   * @default ['0.0.0.0/0'] - Allow from anywhere (change for production)
   */
  readonly allowedCidrBlocks?: string[];
}

/**
 * CDK Stack for AWS Live Streaming Solution using MediaLive, MediaPackage, and CloudFront
 * 
 * This stack creates a complete live streaming infrastructure including:
 * - MediaLive input security group and RTMP input
 * - MediaLive channel with multi-bitrate encoding
 * - MediaPackage channel with HLS and DASH endpoints
 * - CloudFront distribution for global content delivery
 * - S3 bucket for content archiving
 * - CloudWatch monitoring and alarms
 * - IAM roles with least privilege access
 */
export class LiveStreamingStack extends cdk.Stack {
  public readonly mediaLiveInput: medialive.CfnInput;
  public readonly mediaLiveChannel: medialive.CfnChannel;
  public readonly mediaPackageChannel: mediapackage.CfnChannel;
  public readonly cloudFrontDistribution: cloudfront.Distribution;
  public readonly archiveBucket: s3.Bucket;
  public readonly hlsEndpoint: mediapackage.CfnOriginEndpoint;
  public readonly dashEndpoint: mediapackage.CfnOriginEndpoint;
  
  constructor(scope: Construct, id: string, props: LiveStreamingStackProps = {}) {
    super(scope, id, props);
    
    // Configuration with defaults
    const namePrefix = props.namePrefix || 'live-streaming';
    const enableDetailedMonitoring = props.enableDetailedMonitoring ?? true;
    const allowedCidrBlocks = props.allowedCidrBlocks || ['0.0.0.0/0'];
    
    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8);
    
    // Create S3 bucket for archiving streams
    this.archiveBucket = props.archiveBucket || new s3.Bucket(this, 'ArchiveBucket', {
      bucketName: `${namePrefix}-archive-${uniqueSuffix}`,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'DeleteOldArchives',
          expiration: cdk.Duration.days(30),
          enabled: true,
        },
      ],
    });
    
    // Create MediaLive input security group
    const inputSecurityGroup = new medialive.CfnInputSecurityGroup(this, 'InputSecurityGroup', {
      whitelistRules: allowedCidrBlocks.map(cidr => ({
        cidr: cidr,
      })),
      tags: {
        Name: `${namePrefix}-input-security-group`,
      },
    });
    
    // Create MediaLive RTMP input
    this.mediaLiveInput = new medialive.CfnInput(this, 'MediaLiveInput', {
      name: `${namePrefix}-rtmp-input`,
      type: 'RTMP_PUSH',
      inputSecurityGroups: [inputSecurityGroup.ref],
      tags: {
        Name: `${namePrefix}-rtmp-input`,
      },
    });
    
    // Create MediaPackage channel
    this.mediaPackageChannel = new mediapackage.CfnChannel(this, 'MediaPackageChannel', {
      id: `${namePrefix}-package-channel-${uniqueSuffix}`,
      description: 'Live streaming MediaPackage channel',
      tags: [
        {
          key: 'Name',
          value: `${namePrefix}-package-channel`,
        },
      ],
    });
    
    // Create MediaPackage HLS endpoint
    this.hlsEndpoint = new mediapackage.CfnOriginEndpoint(this, 'HlsEndpoint', {
      id: `${namePrefix}-hls-${uniqueSuffix}`,
      channelId: this.mediaPackageChannel.id,
      description: 'HLS endpoint for live streaming',
      manifestName: 'index.m3u8',
      hlsPackage: {
        segmentDurationSeconds: 6,
        playlistWindowSeconds: 60,
        playlistType: 'EVENT',
        adMarkers: 'NONE',
        includeIframeOnlyStream: false,
        programDateTimeIntervalSeconds: 0,
        useAudioRenditionGroup: false,
      },
      tags: [
        {
          key: 'Name',
          value: `${namePrefix}-hls-endpoint`,
        },
      ],
    });
    
    // Create MediaPackage DASH endpoint
    this.dashEndpoint = new mediapackage.CfnOriginEndpoint(this, 'DashEndpoint', {
      id: `${namePrefix}-dash-${uniqueSuffix}`,
      channelId: this.mediaPackageChannel.id,
      description: 'DASH endpoint for live streaming',
      manifestName: 'index.mpd',
      dashPackage: {
        segmentDurationSeconds: 6,
        minBufferTimeSeconds: 30,
        minUpdatePeriodSeconds: 15,
        suggestedPresentationDelaySeconds: 25,
        profile: 'NONE',
        streamSelection: {
          streamOrder: 'ORIGINAL',
        },
      },
      tags: [
        {
          key: 'Name',
          value: `${namePrefix}-dash-endpoint`,
        },
      ],
    });
    
    // Create IAM role for MediaLive
    const mediaLiveRole = new iam.Role(this, 'MediaLiveRole', {
      assumedBy: new iam.ServicePrincipal('medialive.amazonaws.com'),
      description: 'IAM role for MediaLive channel operations',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('MediaLiveFullAccess'),
      ],
      inlinePolicies: {
        MediaPackageAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'mediapackage:DescribeChannel',
                'mediapackage:DescribeOriginEndpoint',
              ],
              resources: [
                this.mediaPackageChannel.attrArn,
                `${this.mediaPackageChannel.attrArn}/*`,
              ],
            }),
          ],
        }),
        S3ArchiveAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:PutObject',
                's3:PutObjectAcl',
                's3:GetObject',
                's3:DeleteObject',
              ],
              resources: [
                this.archiveBucket.arnForObjects('*'),
              ],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:ListBucket',
              ],
              resources: [
                this.archiveBucket.bucketArn,
              ],
            }),
          ],
        }),
      },
    });
    
    // Create MediaLive channel with multi-bitrate encoding
    this.mediaLiveChannel = new medialive.CfnChannel(this, 'MediaLiveChannel', {
      name: `${namePrefix}-channel`,
      roleArn: mediaLiveRole.roleArn,
      inputSpecification: {
        codec: 'AVC',
        resolution: 'HD',
        maximumBitrate: 'MAX_10_MBPS',
      },
      inputAttachments: [
        {
          inputId: this.mediaLiveInput.ref,
          inputAttachmentName: 'primary-input',
          inputSettings: {
            sourceEndBehavior: 'CONTINUE',
          },
        },
      ],
      destinations: [
        {
          id: 'mediapackage-destination',
          mediaPackageSettings: [
            {
              channelId: this.mediaPackageChannel.id,
            },
          ],
        },
      ],
      encoderSettings: {
        // Audio configuration
        audioDescriptions: [
          {
            name: 'audio_1',
            audioSelectorName: 'default',
            codecSettings: {
              aacSettings: {
                bitrate: 96000,
                codingMode: 'CODING_MODE_2_0',
                sampleRate: 48000,
              },
            },
          },
        ],
        // Video configurations for adaptive bitrate streaming
        videoDescriptions: [
          {
            name: 'video_1080p',
            codecSettings: {
              h264Settings: {
                bitrate: 6000000,
                framerateControl: 'SPECIFIED',
                framerateNumerator: 30,
                framerateDenominator: 1,
                gopBReference: 'DISABLED',
                gopClosedCadence: 1,
                gopNumBFrames: 2,
                gopSize: 90,
                gopSizeUnits: 'FRAMES',
                profile: 'MAIN',
                rateControlMode: 'CBR',
                syntax: 'DEFAULT',
              },
            },
            width: 1920,
            height: 1080,
            respondToAfd: 'NONE',
            sharpness: 50,
            scalingBehavior: 'DEFAULT',
          },
          {
            name: 'video_720p',
            codecSettings: {
              h264Settings: {
                bitrate: 3000000,
                framerateControl: 'SPECIFIED',
                framerateNumerator: 30,
                framerateDenominator: 1,
                gopBReference: 'DISABLED',
                gopClosedCadence: 1,
                gopNumBFrames: 2,
                gopSize: 90,
                gopSizeUnits: 'FRAMES',
                profile: 'MAIN',
                rateControlMode: 'CBR',
                syntax: 'DEFAULT',
              },
            },
            width: 1280,
            height: 720,
            respondToAfd: 'NONE',
            sharpness: 50,
            scalingBehavior: 'DEFAULT',
          },
          {
            name: 'video_480p',
            codecSettings: {
              h264Settings: {
                bitrate: 1500000,
                framerateControl: 'SPECIFIED',
                framerateNumerator: 30,
                framerateDenominator: 1,
                gopBReference: 'DISABLED',
                gopClosedCadence: 1,
                gopNumBFrames: 2,
                gopSize: 90,
                gopSizeUnits: 'FRAMES',
                profile: 'MAIN',
                rateControlMode: 'CBR',
                syntax: 'DEFAULT',
              },
            },
            width: 854,
            height: 480,
            respondToAfd: 'NONE',
            sharpness: 50,
            scalingBehavior: 'DEFAULT',
          },
        ],
        // Output groups configuration
        outputGroups: [
          {
            name: 'MediaPackage',
            outputGroupSettings: {
              mediaPackageGroupSettings: {
                destination: {
                  destinationRefId: 'mediapackage-destination',
                },
              },
            },
            outputs: [
              {
                outputName: '1080p',
                videoDescriptionName: 'video_1080p',
                audioDescriptionNames: ['audio_1'],
                outputSettings: {
                  mediaPackageOutputSettings: {},
                },
              },
              {
                outputName: '720p',
                videoDescriptionName: 'video_720p',
                audioDescriptionNames: ['audio_1'],
                outputSettings: {
                  mediaPackageOutputSettings: {},
                },
              },
              {
                outputName: '480p',
                videoDescriptionName: 'video_480p',
                audioDescriptionNames: ['audio_1'],
                outputSettings: {
                  mediaPackageOutputSettings: {},
                },
              },
            ],
          },
        ],
        // Timecode configuration
        timecodeConfig: {
          source: 'EMBEDDED',
        },
      },
      tags: {
        Name: `${namePrefix}-channel`,
      },
    });
    
    // Add dependency to ensure MediaPackage channel is created first
    this.mediaLiveChannel.addDependency(this.mediaPackageChannel);
    
    // Create CloudFront distribution for global content delivery
    this.cloudFrontDistribution = new cloudfront.Distribution(this, 'CloudFrontDistribution', {
      comment: 'Live streaming CloudFront distribution',
      defaultBehavior: {
        origin: new origins.HttpOrigin(cdk.Fn.select(2, cdk.Fn.split('/', this.hlsEndpoint.attrUrl)), {
          originPath: `/${cdk.Fn.select(3, cdk.Fn.split('/', this.hlsEndpoint.attrUrl))}`,
          protocolPolicy: cloudfront.OriginProtocolPolicy.HTTPS_ONLY,
        }),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED_FOR_UNCOMPRESSED_OBJECTS,
        originRequestPolicy: cloudfront.OriginRequestPolicy.CORS_S3_ORIGIN,
        compress: false,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD_OPTIONS,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD_OPTIONS,
      },
      additionalBehaviors: {
        '*.mpd': {
          origin: new origins.HttpOrigin(cdk.Fn.select(2, cdk.Fn.split('/', this.dashEndpoint.attrUrl)), {
            originPath: `/${cdk.Fn.select(3, cdk.Fn.split('/', this.dashEndpoint.attrUrl))}`,
            protocolPolicy: cloudfront.OriginProtocolPolicy.HTTPS_ONLY,
          }),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED_FOR_UNCOMPRESSED_OBJECTS,
          originRequestPolicy: cloudfront.OriginRequestPolicy.CORS_S3_ORIGIN,
          compress: false,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD_OPTIONS,
          cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD_OPTIONS,
        },
      },
      priceClass: cloudfront.PriceClass.PRICE_CLASS_ALL,
      enabled: true,
    });
    
    // Create CloudWatch alarms for monitoring
    if (enableDetailedMonitoring) {
      // Create log group for MediaLive channel
      const mediaLiveLogGroup = new logs.LogGroup(this, 'MediaLiveLogGroup', {
        logGroupName: `/aws/medialive/${this.mediaLiveChannel.name}`,
        retention: logs.RetentionDays.ONE_WEEK,
        removalPolicy: RemovalPolicy.DESTROY,
      });
      
      // MediaLive channel errors alarm
      new cloudwatch.Alarm(this, 'MediaLiveChannelErrorsAlarm', {
        alarmName: `${namePrefix}-medialive-channel-errors`,
        alarmDescription: 'MediaLive channel error alarm',
        metric: new cloudwatch.Metric({
          namespace: 'AWS/MediaLive',
          metricName: '4xxErrors',
          dimensionsMap: {
            ChannelId: this.mediaLiveChannel.ref,
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
        threshold: 1,
        evaluationPeriods: 2,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      });
      
      // MediaLive input video freeze alarm
      new cloudwatch.Alarm(this, 'MediaLiveInputVideoFreezeAlarm', {
        alarmName: `${namePrefix}-medialive-input-video-freeze`,
        alarmDescription: 'MediaLive input video freeze alarm',
        metric: new cloudwatch.Metric({
          namespace: 'AWS/MediaLive',
          metricName: 'InputVideoFreeze',
          dimensionsMap: {
            ChannelId: this.mediaLiveChannel.ref,
          },
          statistic: 'Maximum',
          period: cdk.Duration.minutes(5),
        }),
        threshold: 0.5,
        evaluationPeriods: 1,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      });
      
      // CloudFront 4xx errors alarm
      new cloudwatch.Alarm(this, 'CloudFront4xxErrorsAlarm', {
        alarmName: `${namePrefix}-cloudfront-4xx-errors`,
        alarmDescription: 'CloudFront 4xx errors alarm',
        metric: new cloudwatch.Metric({
          namespace: 'AWS/CloudFront',
          metricName: '4xxErrorRate',
          dimensionsMap: {
            DistributionId: this.cloudFrontDistribution.distributionId,
          },
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        }),
        threshold: 5,
        evaluationPeriods: 2,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      });
    }
    
    // Create CloudFormation outputs
    new CfnOutput(this, 'MediaLiveInputId', {
      value: this.mediaLiveInput.ref,
      description: 'MediaLive input ID',
      exportName: `${this.stackName}-MediaLiveInputId`,
    });
    
    new CfnOutput(this, 'MediaLiveChannelId', {
      value: this.mediaLiveChannel.ref,
      description: 'MediaLive channel ID',
      exportName: `${this.stackName}-MediaLiveChannelId`,
    });
    
    new CfnOutput(this, 'MediaPackageChannelId', {
      value: this.mediaPackageChannel.id,
      description: 'MediaPackage channel ID',
      exportName: `${this.stackName}-MediaPackageChannelId`,
    });
    
    new CfnOutput(this, 'HlsEndpointUrl', {
      value: this.hlsEndpoint.attrUrl,
      description: 'MediaPackage HLS endpoint URL',
      exportName: `${this.stackName}-HlsEndpointUrl`,
    });
    
    new CfnOutput(this, 'DashEndpointUrl', {
      value: this.dashEndpoint.attrUrl,
      description: 'MediaPackage DASH endpoint URL',
      exportName: `${this.stackName}-DashEndpointUrl`,
    });
    
    new CfnOutput(this, 'CloudFrontDistributionId', {
      value: this.cloudFrontDistribution.distributionId,
      description: 'CloudFront distribution ID',
      exportName: `${this.stackName}-CloudFrontDistributionId`,
    });
    
    new CfnOutput(this, 'CloudFrontDistributionDomainName', {
      value: this.cloudFrontDistribution.distributionDomainName,
      description: 'CloudFront distribution domain name',
      exportName: `${this.stackName}-CloudFrontDistributionDomainName`,
    });
    
    new CfnOutput(this, 'HlsPlaybackUrl', {
      value: `https://${this.cloudFrontDistribution.distributionDomainName}/out/v1/index.m3u8`,
      description: 'HLS playback URL via CloudFront',
      exportName: `${this.stackName}-HlsPlaybackUrl`,
    });
    
    new CfnOutput(this, 'DashPlaybackUrl', {
      value: `https://${this.cloudFrontDistribution.distributionDomainName}/out/v1/index.mpd`,
      description: 'DASH playback URL via CloudFront',
      exportName: `${this.stackName}-DashPlaybackUrl`,
    });
    
    new CfnOutput(this, 'ArchiveBucketName', {
      value: this.archiveBucket.bucketName,
      description: 'S3 bucket for stream archiving',
      exportName: `${this.stackName}-ArchiveBucketName`,
    });
    
    new CfnOutput(this, 'RtmpInputUrls', {
      value: cdk.Fn.join(', ', this.mediaLiveInput.attrDestinations),
      description: 'RTMP input URLs for streaming',
      exportName: `${this.stackName}-RtmpInputUrls`,
    });
  }
}

// Create the CDK app
const app = new cdk.App();

// Deploy the live streaming stack
new LiveStreamingStack(app, 'LiveStreamingStack', {
  description: 'AWS Live Streaming Solution with MediaLive, MediaPackage, and CloudFront',
  
  // Environment configuration
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Stack configuration
  namePrefix: 'live-streaming',
  enableDetailedMonitoring: true,
  
  // Security configuration - restrict in production
  allowedCidrBlocks: ['0.0.0.0/0'],
  
  // Stack tags
  tags: {
    Project: 'LiveStreamingSolution',
    Environment: 'Development',
    Owner: 'MediaTeam',
    CostCenter: 'Engineering',
  },
});

// Synthesize the stack
app.synth();