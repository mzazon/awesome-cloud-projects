#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as medialive from 'aws-cdk-lib/aws-medialive';
import * as mediapackage from 'aws-cdk-lib/aws-mediapackage';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Configuration interface for the Video Streaming Platform
 */
interface VideoStreamingPlatformConfig {
  /**
   * Platform name used for resource naming
   */
  platformName: string;

  /**
   * Environment tag for resources
   */
  environment: string;

  /**
   * Enable low latency streaming with CMAF
   */
  enableLowLatency: boolean;

  /**
   * Enable DRM protection for content
   */
  enableDRM: boolean;

  /**
   * Enable content archiving to S3
   */
  enableArchiving: boolean;

  /**
   * Maximum bitrate for encoding (in bps)
   */
  maxBitrate: number;

  /**
   * Number of days to retain archived content
   */
  archiveRetentionDays: number;
}

/**
 * AWS CDK Stack for Enterprise Video Streaming Platform
 * 
 * This stack creates a complete video streaming platform using:
 * - AWS Elemental MediaLive for live video encoding
 * - AWS Elemental MediaPackage for content packaging and origin services
 * - Amazon CloudFront for global content distribution
 * - Amazon S3 for content archiving
 * - AWS Secrets Manager for DRM key management
 * - Amazon CloudWatch for monitoring and alerting
 */
export class VideoStreamingPlatformStack extends cdk.Stack {
  private readonly config: VideoStreamingPlatformConfig;
  private readonly archiveBucket: s3.Bucket;
  private readonly mediaLiveRole: iam.Role;
  private readonly drmSecret: secretsmanager.Secret;
  private readonly inputSecurityGroup: medialive.CfnInputSecurityGroup;
  private readonly internalSecurityGroup: medialive.CfnInputSecurityGroup;
  private readonly mediaPackageChannel: mediapackage.CfnChannel;
  private readonly mediaLiveInputs: { [key: string]: medialive.CfnInput };
  private readonly mediaPackageEndpoints: { [key: string]: mediapackage.CfnOriginEndpoint };
  private readonly mediaLiveChannel: medialive.CfnChannel;
  private readonly cloudFrontDistribution: cloudfront.Distribution;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Configuration with defaults
    this.config = {
      platformName: this.node.tryGetContext('platformName') || 'video-streaming-platform',
      environment: this.node.tryGetContext('environment') || 'production',
      enableLowLatency: this.node.tryGetContext('enableLowLatency') !== false,
      enableDRM: this.node.tryGetContext('enableDRM') !== false,
      enableArchiving: this.node.tryGetContext('enableArchiving') !== false,
      maxBitrate: this.node.tryGetContext('maxBitrate') || 50000000, // 50 Mbps
      archiveRetentionDays: this.node.tryGetContext('archiveRetentionDays') || 90
    };

    // Create foundational resources
    this.createFoundationalResources();
    
    // Create IAM roles and policies
    this.createIAMResources();
    
    // Create MediaLive security groups
    this.createMediaLiveSecurityGroups();
    
    // Create MediaLive inputs
    this.createMediaLiveInputs();
    
    // Create MediaPackage channel
    this.createMediaPackageChannel();
    
    // Create MediaPackage endpoints
    this.createMediaPackageEndpoints();
    
    // Create MediaLive channel
    this.createMediaLiveChannel();
    
    // Create CloudFront distribution
    this.createCloudFrontDistribution();
    
    // Create monitoring and alerting
    this.createMonitoring();
    
    // Add stack outputs
    this.createOutputs();
  }

  /**
   * Create foundational resources including S3 bucket and DRM secrets
   */
  private createFoundationalResources(): void {
    // Create S3 bucket for content archiving
    if (this.config.enableArchiving) {
      this.archiveBucket = new s3.Bucket(this, 'StreamingArchiveBucket', {
        bucketName: `${this.config.platformName}-archives-${this.account}`,
        versioned: true,
        lifecycleRules: [
          {
            id: 'streaming-content-lifecycle',
            enabled: true,
            transitions: [
              {
                storageClass: s3.StorageClass.INFREQUENT_ACCESS,
                transitionAfter: cdk.Duration.days(30)
              },
              {
                storageClass: s3.StorageClass.GLACIER,
                transitionAfter: cdk.Duration.days(90)
              },
              {
                storageClass: s3.StorageClass.DEEP_ARCHIVE,
                transitionAfter: cdk.Duration.days(365)
              }
            ],
            expiration: cdk.Duration.days(this.config.archiveRetentionDays)
          }
        ],
        removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
        autoDeleteObjects: true, // For demo purposes
        tags: {
          Environment: this.config.environment,
          Service: 'VideoStreaming',
          Component: 'Archive'
        }
      });
    }

    // Create DRM secret for content protection
    if (this.config.enableDRM) {
      this.drmSecret = new secretsmanager.Secret(this, 'DRMSecret', {
        secretName: `${this.config.platformName}-drm-key`,
        description: 'DRM encryption key for video streaming platform',
        generateSecretString: {
          secretStringTemplate: JSON.stringify({ username: 'admin' }),
          generateStringKey: 'key',
          excludeCharacters: ' %+~`#$&*()|[]{}:;<>?!\'/@"\\',
          includeSpace: false,
          passwordLength: 32
        }
      });
    }
  }

  /**
   * Create IAM roles and policies for MediaLive service
   */
  private createIAMResources(): void {
    // Create comprehensive MediaLive service role
    this.mediaLiveRole = new iam.Role(this, 'MediaLiveServiceRole', {
      roleName: `${this.config.platformName}-medialive-role`,
      assumedBy: new iam.ServicePrincipal('medialive.amazonaws.com'),
      description: 'Service role for MediaLive with comprehensive permissions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchLogsFullAccess')
      ],
      inlinePolicies: {
        MediaLivePlatformPolicy: new iam.PolicyDocument({
          statements: [
            // MediaPackage permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'mediapackage:*'
              ],
              resources: ['*']
            }),
            // S3 permissions for archiving
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
                's3:GetBucketLocation'
              ],
              resources: this.config.enableArchiving ? [
                this.archiveBucket.bucketArn,
                `${this.archiveBucket.bucketArn}/*`
              ] : ['*']
            }),
            // Secrets Manager permissions for DRM
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'secretsmanager:GetSecretValue',
                'secretsmanager:CreateSecret'
              ],
              resources: this.config.enableDRM ? [this.drmSecret.secretArn] : ['*']
            }),
            // CloudWatch permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:PutMetricData',
                'cloudwatch:GetMetricStatistics',
                'cloudwatch:ListMetrics'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });
  }

  /**
   * Create MediaLive input security groups for network access control
   */
  private createMediaLiveSecurityGroups(): void {
    // Create public input security group for general streaming
    this.inputSecurityGroup = new medialive.CfnInputSecurityGroup(this, 'PublicInputSecurityGroup', {
      whitelistRules: [
        {
          cidr: '0.0.0.0/0' // Allow from anywhere - restrict in production
        }
      ],
      tags: {
        Name: `${this.config.platformName}-public-sg`,
        Environment: this.config.environment
      }
    });

    // Create internal input security group for private networks
    this.internalSecurityGroup = new medialive.CfnInputSecurityGroup(this, 'InternalInputSecurityGroup', {
      whitelistRules: [
        { cidr: '10.0.0.0/8' },     // Private network ranges
        { cidr: '172.16.0.0/12' },  // Private network ranges
        { cidr: '192.168.0.0/16' }  // Private network ranges
      ],
      tags: {
        Name: `${this.config.platformName}-internal-sg`,
        Environment: this.config.environment
      }
    });
  }

  /**
   * Create multiple MediaLive inputs for different streaming sources
   */
  private createMediaLiveInputs(): void {
    this.mediaLiveInputs = {};

    // Create RTMP Push input for live streaming applications
    this.mediaLiveInputs.rtmp = new medialive.CfnInput(this, 'RTMPInput', {
      name: `${this.config.platformName}-rtmp-input`,
      type: 'RTMP_PUSH',
      inputSecurityGroups: [this.inputSecurityGroup.ref],
      tags: {
        Name: `${this.config.platformName}-rtmp`,
        Type: 'Live',
        Environment: this.config.environment
      }
    });

    // Create HLS Pull input for remote streaming sources
    this.mediaLiveInputs.hls = new medialive.CfnInput(this, 'HLSInput', {
      name: `${this.config.platformName}-hls-input`,
      type: 'URL_PULL',
      sources: [
        {
          url: 'https://example.com/stream.m3u8'
        }
      ],
      tags: {
        Name: `${this.config.platformName}-hls`,
        Type: 'Remote',
        Environment: this.config.environment
      }
    });

    // Create RTP Push input for professional broadcasting equipment
    this.mediaLiveInputs.rtp = new medialive.CfnInput(this, 'RTPInput', {
      name: `${this.config.platformName}-rtp-input`,
      type: 'RTP_PUSH',
      inputSecurityGroups: [this.internalSecurityGroup.ref],
      tags: {
        Name: `${this.config.platformName}-rtp`,
        Type: 'Professional',
        Environment: this.config.environment
      }
    });
  }

  /**
   * Create MediaPackage channel for content origin services
   */
  private createMediaPackageChannel(): void {
    this.mediaPackageChannel = new mediapackage.CfnChannel(this, 'MediaPackageChannel', {
      id: `${this.config.platformName}-channel`,
      description: 'Enterprise streaming platform MediaPackage channel',
      tags: [
        {
          key: 'Name',
          value: `${this.config.platformName}-channel`
        },
        {
          key: 'Environment',
          value: this.config.environment
        },
        {
          key: 'Service',
          value: 'VideoStreaming'
        }
      ]
    });
  }

  /**
   * Create MediaPackage origin endpoints for different streaming protocols
   */
  private createMediaPackageEndpoints(): void {
    this.mediaPackageEndpoints = {};

    // Create HLS endpoint with advanced adaptive bitrate features
    this.mediaPackageEndpoints.hls = new mediapackage.CfnOriginEndpoint(this, 'HLSEndpoint', {
      channelId: this.mediaPackageChannel.id,
      id: `${this.config.platformName}-hls-advanced`,
      manifestName: 'master.m3u8',
      startoverWindowSeconds: 3600, // 1 hour start-over window
      timeDelaySeconds: 10,
      hlsPackage: {
        segmentDurationSeconds: 4,
        playlistType: 'EVENT',
        playlistWindowSeconds: 300,
        programDateTimeIntervalSeconds: 60,
        adMarkers: 'SCTE35_ENHANCED',
        includeIframeOnlyStream: true,
        useAudioRenditionGroup: true
      },
      tags: [
        { key: 'Type', value: 'HLS' },
        { key: 'Quality', value: 'Advanced' },
        { key: 'Environment', value: this.config.environment }
      ]
    });

    // Create DASH endpoint with DRM support
    if (this.config.enableDRM) {
      this.mediaPackageEndpoints.dash = new mediapackage.CfnOriginEndpoint(this, 'DASHEndpoint', {
        channelId: this.mediaPackageChannel.id,
        id: `${this.config.platformName}-dash-drm`,
        manifestName: 'manifest.mpd',
        startoverWindowSeconds: 3600,
        timeDelaySeconds: 10,
        dashPackage: {
          segmentDurationSeconds: 4,
          minBufferTimeSeconds: 20,
          minUpdatePeriodSeconds: 10,
          suggestedPresentationDelaySeconds: 30,
          profile: 'NONE',
          periodTriggers: ['ADS']
        },
        tags: [
          { key: 'Type', value: 'DASH' },
          { key: 'DRM', value: 'Enabled' },
          { key: 'Environment', value: this.config.environment }
        ]
      });
    }

    // Create CMAF endpoint for low-latency streaming
    if (this.config.enableLowLatency) {
      this.mediaPackageEndpoints.cmaf = new mediapackage.CfnOriginEndpoint(this, 'CMAFEndpoint', {
        channelId: this.mediaPackageChannel.id,
        id: `${this.config.platformName}-cmaf-ll`,
        manifestName: 'index.m3u8',
        startoverWindowSeconds: 1800, // 30 minutes for low latency
        timeDelaySeconds: 2,
        cmafPackage: {
          segmentDurationSeconds: 2,
          segmentPrefix: 'segment',
          hlsManifests: [
            {
              id: 'low-latency',
              manifestName: 'll.m3u8',
              playlistType: 'EVENT',
              playlistWindowSeconds: 60,
              programDateTimeIntervalSeconds: 60,
              adMarkers: 'SCTE35_ENHANCED'
            }
          ]
        },
        tags: [
          { key: 'Type', value: 'CMAF' },
          { key: 'Latency', value: 'Low' },
          { key: 'Environment', value: this.config.environment }
        ]
      });
    }
  }

  /**
   * Create comprehensive MediaLive channel with multiple bitrate encoding
   */
  private createMediaLiveChannel(): void {
    // Define comprehensive encoder settings for multiple bitrates
    const encoderSettings: medialive.CfnChannel.EncoderSettingsProperty = {
      audioDescriptions: [
        {
          name: 'audio_stereo',
          audioSelectorName: 'default',
          audioTypeControl: 'FOLLOW_INPUT',
          languageCodeControl: 'FOLLOW_INPUT',
          codecSettings: {
            aacSettings: {
              bitrate: 128000,
              codingMode: 'CODING_MODE_2_0',
              sampleRate: 48000,
              spec: 'MPEG4'
            }
          }
        },
        {
          name: 'audio_surround',
          audioSelectorName: 'default',
          audioTypeControl: 'FOLLOW_INPUT',
          languageCodeControl: 'FOLLOW_INPUT',
          codecSettings: {
            aacSettings: {
              bitrate: 256000,
              codingMode: 'CODING_MODE_5_1',
              sampleRate: 48000,
              spec: 'MPEG4'
            }
          }
        }
      ],
      videoDescriptions: [
        // 4K UHD (2160p) encoding
        {
          name: 'video_2160p',
          width: 3840,
          height: 2160,
          codecSettings: {
            h264Settings: {
              bitrate: 15000000,
              framerateControl: 'SPECIFIED',
              framerateNumerator: 30,
              framerateDenominator: 1,
              gopBReference: 'ENABLED',
              gopClosedCadence: 1,
              gopNumBFrames: 3,
              gopSize: 90,
              gopSizeUnits: 'FRAMES',
              profile: 'HIGH',
              level: 'H264_LEVEL_5_1',
              rateControlMode: 'CBR',
              syntax: 'DEFAULT',
              adaptiveQuantization: 'HIGH',
              afdSignaling: 'NONE',
              colorMetadata: 'INSERT',
              entropyEncoding: 'CABAC',
              flickerAq: 'ENABLED',
              forceFieldPictures: 'DISABLED',
              temporalAq: 'ENABLED',
              spatialAq: 'ENABLED'
            }
          },
          respondToAfd: 'RESPOND',
          scalingBehavior: 'DEFAULT',
          sharpness: 50
        },
        // Full HD (1080p) encoding
        {
          name: 'video_1080p',
          width: 1920,
          height: 1080,
          codecSettings: {
            h264Settings: {
              bitrate: 6000000,
              framerateControl: 'SPECIFIED',
              framerateNumerator: 30,
              framerateDenominator: 1,
              gopBReference: 'ENABLED',
              gopClosedCadence: 1,
              gopNumBFrames: 3,
              gopSize: 90,
              gopSizeUnits: 'FRAMES',
              profile: 'HIGH',
              level: 'H264_LEVEL_4_1',
              rateControlMode: 'CBR',
              syntax: 'DEFAULT',
              adaptiveQuantization: 'HIGH',
              temporalAq: 'ENABLED',
              spatialAq: 'ENABLED'
            }
          },
          respondToAfd: 'RESPOND',
          scalingBehavior: 'DEFAULT',
          sharpness: 50
        },
        // HD (720p) encoding
        {
          name: 'video_720p',
          width: 1280,
          height: 720,
          codecSettings: {
            h264Settings: {
              bitrate: 3000000,
              framerateControl: 'SPECIFIED',
              framerateNumerator: 30,
              framerateDenominator: 1,
              gopBReference: 'ENABLED',
              gopClosedCadence: 1,
              gopNumBFrames: 2,
              gopSize: 90,
              gopSizeUnits: 'FRAMES',
              profile: 'HIGH',
              level: 'H264_LEVEL_3_1',
              rateControlMode: 'CBR',
              syntax: 'DEFAULT',
              adaptiveQuantization: 'MEDIUM',
              temporalAq: 'ENABLED',
              spatialAq: 'ENABLED'
            }
          },
          respondToAfd: 'RESPOND',
          scalingBehavior: 'DEFAULT',
          sharpness: 50
        },
        // SD (480p) encoding
        {
          name: 'video_480p',
          width: 854,
          height: 480,
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
              level: 'H264_LEVEL_3_0',
              rateControlMode: 'CBR',
              syntax: 'DEFAULT',
              adaptiveQuantization: 'MEDIUM'
            }
          },
          respondToAfd: 'RESPOND',
          scalingBehavior: 'DEFAULT',
          sharpness: 50
        },
        // Mobile (240p) encoding
        {
          name: 'video_240p',
          width: 426,
          height: 240,
          codecSettings: {
            h264Settings: {
              bitrate: 500000,
              framerateControl: 'SPECIFIED',
              framerateNumerator: 30,
              framerateDenominator: 1,
              gopBReference: 'DISABLED',
              gopClosedCadence: 1,
              gopNumBFrames: 1,
              gopSize: 90,
              gopSizeUnits: 'FRAMES',
              profile: 'BASELINE',
              level: 'H264_LEVEL_2_0',
              rateControlMode: 'CBR',
              syntax: 'DEFAULT'
            }
          },
          respondToAfd: 'RESPOND',
          scalingBehavior: 'DEFAULT',
          sharpness: 50
        }
      ],
      outputGroups: [
        // MediaPackage output group for adaptive bitrate streaming
        {
          name: 'MediaPackage-ABR',
          outputGroupSettings: {
            mediaPackageGroupSettings: {
              destination: {
                destinationRefId: 'mediapackage-destination'
              }
            }
          },
          outputs: [
            {
              outputName: '4K-UHD',
              videoDescriptionName: 'video_2160p',
              audioDescriptionNames: ['audio_surround'],
              outputSettings: {
                mediaPackageOutputSettings: {}
              }
            },
            {
              outputName: '1080p-HD',
              videoDescriptionName: 'video_1080p',
              audioDescriptionNames: ['audio_stereo'],
              outputSettings: {
                mediaPackageOutputSettings: {}
              }
            },
            {
              outputName: '720p-HD',
              videoDescriptionName: 'video_720p',
              audioDescriptionNames: ['audio_stereo'],
              outputSettings: {
                mediaPackageOutputSettings: {}
              }
            },
            {
              outputName: '480p-SD',
              videoDescriptionName: 'video_480p',
              audioDescriptionNames: ['audio_stereo'],
              outputSettings: {
                mediaPackageOutputSettings: {}
              }
            },
            {
              outputName: '240p-Mobile',
              videoDescriptionName: 'video_240p',
              audioDescriptionNames: ['audio_stereo'],
              outputSettings: {
                mediaPackageOutputSettings: {}
              }
            }
          ]
        }
      ],
      timecodeConfig: {
        source: 'EMBEDDED'
      },
      captionDescriptions: [
        {
          captionSelectorName: 'default',
          name: 'captions',
          languageCode: 'en',
          languageDescription: 'English'
        }
      ]
    };

    // Add S3 archive output group if archiving is enabled
    if (this.config.enableArchiving) {
      encoderSettings.outputGroups!.push({
        name: 'S3-Archive',
        outputGroupSettings: {
          archiveGroupSettings: {
            destination: {
              destinationRefId: 's3-archive-destination'
            },
            rolloverInterval: 3600 // 1 hour rollover
          }
        },
        outputs: [
          {
            outputName: 'archive-source',
            videoDescriptionName: 'video_1080p',
            audioDescriptionNames: ['audio_stereo'],
            outputSettings: {
              archiveOutputSettings: {
                nameModifier: '-archive',
                extension: 'm2ts'
              }
            }
          }
        ]
      });
    }

    // Create destinations array
    const destinations: medialive.CfnChannel.OutputDestinationProperty[] = [
      {
        id: 'mediapackage-destination',
        mediaPackageSettings: [
          {
            channelId: this.mediaPackageChannel.id
          }
        ]
      }
    ];

    // Add S3 destination if archiving is enabled
    if (this.config.enableArchiving) {
      destinations.push({
        id: 's3-archive-destination',
        s3Settings: [
          {
            bucketName: this.archiveBucket.bucketName,
            fileNamePrefix: 'archives/',
            roleArn: this.mediaLiveRole.roleArn
          }
        ]
      });
    }

    // Create MediaLive channel with comprehensive configuration
    this.mediaLiveChannel = new medialive.CfnChannel(this, 'MediaLiveChannel', {
      name: `${this.config.platformName}-channel`,
      roleArn: this.mediaLiveRole.roleArn,
      inputSpecification: {
        codec: 'AVC',
        resolution: 'HD',
        maximumBitrate: 'MAX_50_MBPS'
      },
      inputAttachments: [
        {
          inputId: this.mediaLiveInputs.rtmp.ref,
          inputAttachmentName: 'primary-rtmp',
          inputSettings: {
            sourceEndBehavior: 'CONTINUE',
            inputFilter: 'AUTO',
            filterStrength: 1,
            deblockFilter: 'ENABLED',
            denoiseFilter: 'ENABLED'
          }
        },
        {
          inputId: this.mediaLiveInputs.hls.ref,
          inputAttachmentName: 'backup-hls',
          inputSettings: {
            sourceEndBehavior: 'CONTINUE',
            inputFilter: 'AUTO',
            filterStrength: 1
          }
        }
      ],
      destinations: destinations,
      encoderSettings: encoderSettings,
      tags: {
        Environment: this.config.environment,
        Service: 'VideoStreaming',
        Component: 'MediaLive'
      }
    });
  }

  /**
   * Create CloudFront distribution for global content delivery
   */
  private createCloudFrontDistribution(): void {
    // Create multiple origins for different MediaPackage endpoints
    const origins: { [key: string]: cloudfront.IOrigin } = {};
    
    // HLS origin
    origins.hls = new origins.HttpOrigin(
      cdk.Fn.select(2, cdk.Fn.split('/', this.mediaPackageEndpoints.hls.attrUrl)),
      {
        originPath: `/${cdk.Fn.select(3, cdk.Fn.split('/', this.mediaPackageEndpoints.hls.attrUrl))}`.replace(/\/[^\/]*$/, ''),
        customHeaders: {
          'X-MediaPackage-CDNIdentifier': `${this.config.platformName}-hls`
        },
        protocolPolicy: cloudfront.OriginProtocolPolicy.HTTPS_ONLY,
        httpsPort: 443
      }
    );

    // DASH origin (if DRM enabled)
    if (this.config.enableDRM && this.mediaPackageEndpoints.dash) {
      origins.dash = new origins.HttpOrigin(
        cdk.Fn.select(2, cdk.Fn.split('/', this.mediaPackageEndpoints.dash.attrUrl)),
        {
          originPath: `/${cdk.Fn.select(3, cdk.Fn.split('/', this.mediaPackageEndpoints.dash.attrUrl))}`.replace(/\/[^\/]*$/, ''),
          customHeaders: {
            'X-MediaPackage-CDNIdentifier': `${this.config.platformName}-dash`
          },
          protocolPolicy: cloudfront.OriginProtocolPolicy.HTTPS_ONLY,
          httpsPort: 443
        }
      );
    }

    // CMAF origin (if low latency enabled)
    if (this.config.enableLowLatency && this.mediaPackageEndpoints.cmaf) {
      origins.cmaf = new origins.HttpOrigin(
        cdk.Fn.select(2, cdk.Fn.split('/', this.mediaPackageEndpoints.cmaf.attrUrl)),
        {
          originPath: `/${cdk.Fn.select(3, cdk.Fn.split('/', this.mediaPackageEndpoints.cmaf.attrUrl))}`.replace(/\/[^\/]*$/, ''),
          customHeaders: {
            'X-MediaPackage-CDNIdentifier': `${this.config.platformName}-cmaf`
          },
          protocolPolicy: cloudfront.OriginProtocolPolicy.HTTPS_ONLY,
          httpsPort: 443
        }
      );
    }

    // Create cache behaviors for different content types
    const additionalBehaviors: { [key: string]: cloudfront.BehaviorOptions } = {};

    // DASH manifest behavior (if DRM enabled)
    if (this.config.enableDRM && origins.dash) {
      additionalBehaviors['*.mpd'] = {
        origin: origins.dash,
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED_FOR_UNCOMPRESSED_OBJECTS,
        originRequestPolicy: cloudfront.OriginRequestPolicy.CORS_S3_ORIGIN,
        compress: true,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD
      };
    }

    // Low latency behavior (if enabled)
    if (this.config.enableLowLatency && origins.cmaf) {
      additionalBehaviors['*/ll.m3u8'] = {
        origin: origins.cmaf,
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED, // No caching for low latency
        originRequestPolicy: cloudfront.OriginRequestPolicy.CORS_S3_ORIGIN,
        compress: true,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD
      };
    }

    // Video segment behavior
    additionalBehaviors['*.ts'] = {
      origin: origins.hls,
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
      originRequestPolicy: cloudfront.OriginRequestPolicy.CORS_S3_ORIGIN,
      compress: false, // Don't compress video segments
      allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
      cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD
    };

    // Create CloudFront distribution
    this.cloudFrontDistribution = new cloudfront.Distribution(this, 'StreamingDistribution', {
      comment: `Enterprise Video Streaming Platform - ${this.config.platformName}`,
      defaultBehavior: {
        origin: origins.hls,
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED_FOR_UNCOMPRESSED_OBJECTS,
        originRequestPolicy: cloudfront.OriginRequestPolicy.CORS_S3_ORIGIN,
        compress: true,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD
      },
      additionalBehaviors: additionalBehaviors,
      enabled: true,
      priceClass: cloudfront.PriceClass.PRICE_CLASS_ALL,
      httpVersion: cloudfront.HttpVersion.HTTP2,
      enableIpv6: true,
      certificate: cloudfront.Certificate.fromCloudfrontDefaultCertificate(),
      minimumProtocolVersion: cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021
    });

    // Add tags to CloudFront distribution
    cdk.Tags.of(this.cloudFrontDistribution).add('Environment', this.config.environment);
    cdk.Tags.of(this.cloudFrontDistribution).add('Service', 'VideoStreaming');
    cdk.Tags.of(this.cloudFrontDistribution).add('Component', 'CDN');
  }

  /**
   * Create comprehensive monitoring and alerting for the platform
   */
  private createMonitoring(): void {
    // Create CloudWatch log group for platform logs
    const logGroup = new logs.LogGroup(this, 'PlatformLogGroup', {
      logGroupName: `/aws/medialive/${this.config.platformName}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // MediaLive input loss alarm
    new cloudwatch.Alarm(this, 'MediaLiveInputLossAlarm', {
      alarmName: `MediaLive-${this.config.platformName}-InputLoss`,
      alarmDescription: 'MediaLive channel input loss detection',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/MediaLive',
        metricName: 'InputVideoFreeze',
        dimensionsMap: {
          ChannelId: this.mediaLiveChannel.ref
        },
        statistic: 'Maximum',
        period: cdk.Duration.minutes(1)
      }),
      threshold: 0.5,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING
    });

    // MediaPackage egress error alarm
    new cloudwatch.Alarm(this, 'MediaPackageEgressErrorAlarm', {
      alarmName: `MediaPackage-${this.config.platformName}-EgressErrors`,
      alarmDescription: 'MediaPackage egress error detection',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/MediaPackage',
        metricName: 'EgressRequestCount',
        dimensionsMap: {
          Channel: this.mediaPackageChannel.id
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 100,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2
    });

    // CloudFront error rate alarm
    new cloudwatch.Alarm(this, 'CloudFrontErrorRateAlarm', {
      alarmName: `CloudFront-${this.config.platformName}-ErrorRate`,
      alarmDescription: 'CloudFront 4xx/5xx error rate monitoring',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/CloudFront',
        metricName: '4xxErrorRate',
        dimensionsMap: {
          DistributionId: this.cloudFrontDistribution.distributionId
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 5,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2
    });

    // Create custom dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'StreamingPlatformDashboard', {
      dashboardName: `${this.config.platformName}-monitoring`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'MediaLive Channel Status',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/MediaLive',
                metricName: 'ActiveOutputs',
                dimensionsMap: {
                  ChannelId: this.mediaLiveChannel.ref
                },
                statistic: 'Average'
              })
            ],
            width: 12,
            height: 6
          })
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'MediaPackage Request Count',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/MediaPackage',
                metricName: 'EgressRequestCount',
                dimensionsMap: {
                  Channel: this.mediaPackageChannel.id
                },
                statistic: 'Sum'
              })
            ],
            width: 12,
            height: 6
          })
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'CloudFront Request Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/CloudFront',
                metricName: 'Requests',
                dimensionsMap: {
                  DistributionId: this.cloudFrontDistribution.distributionId
                },
                statistic: 'Sum'
              })
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'AWS/CloudFront',
                metricName: '4xxErrorRate',
                dimensionsMap: {
                  DistributionId: this.cloudFrontDistribution.distributionId
                },
                statistic: 'Average'
              })
            ],
            width: 12,
            height: 6
          })
        ]
      ]
    });
  }

  /**
   * Create comprehensive stack outputs for external integration
   */
  private createOutputs(): void {
    // Platform information outputs
    new cdk.CfnOutput(this, 'PlatformName', {
      value: this.config.platformName,
      description: 'Video streaming platform name'
    });

    new cdk.CfnOutput(this, 'Environment', {
      value: this.config.environment,
      description: 'Deployment environment'
    });

    // MediaLive outputs
    new cdk.CfnOutput(this, 'MediaLiveChannelId', {
      value: this.mediaLiveChannel.ref,
      description: 'MediaLive channel ID for streaming operations'
    });

    new cdk.CfnOutput(this, 'RTMPInputEndpoint', {
      value: cdk.Fn.select(0, this.mediaLiveInputs.rtmp.attrDestinations),
      description: 'Primary RTMP input endpoint for live streaming'
    });

    new cdk.CfnOutput(this, 'RTMPBackupEndpoint', {
      value: cdk.Fn.select(1, this.mediaLiveInputs.rtmp.attrDestinations),
      description: 'Backup RTMP input endpoint for redundancy'
    });

    // MediaPackage outputs
    new cdk.CfnOutput(this, 'MediaPackageChannelId', {
      value: this.mediaPackageChannel.id,
      description: 'MediaPackage channel ID for content packaging'
    });

    new cdk.CfnOutput(this, 'HLSPlaybackUrl', {
      value: `https://${this.cloudFrontDistribution.distributionDomainName}/out/v1/master.m3u8`,
      description: 'HLS playback URL for adaptive bitrate streaming'
    });

    if (this.config.enableDRM && this.mediaPackageEndpoints.dash) {
      new cdk.CfnOutput(this, 'DASHPlaybackUrl', {
        value: `https://${this.cloudFrontDistribution.distributionDomainName}/out/v1/manifest.mpd`,
        description: 'DASH playback URL with DRM support'
      });
    }

    if (this.config.enableLowLatency && this.mediaPackageEndpoints.cmaf) {
      new cdk.CfnOutput(this, 'LowLatencyPlaybackUrl', {
        value: `https://${this.cloudFrontDistribution.distributionDomainName}/out/v1/ll.m3u8`,
        description: 'Low latency CMAF playback URL'
      });
    }

    // CloudFront outputs
    new cdk.CfnOutput(this, 'CloudFrontDistributionId', {
      value: this.cloudFrontDistribution.distributionId,
      description: 'CloudFront distribution ID for global content delivery'
    });

    new cdk.CfnOutput(this, 'CloudFrontDomainName', {
      value: this.cloudFrontDistribution.distributionDomainName,
      description: 'CloudFront distribution domain name'
    });

    // Archive bucket output (if archiving enabled)
    if (this.config.enableArchiving) {
      new cdk.CfnOutput(this, 'ArchiveBucketName', {
        value: this.archiveBucket.bucketName,
        description: 'S3 bucket name for content archiving'
      });
    }

    // DRM secret output (if DRM enabled)
    if (this.config.enableDRM) {
      new cdk.CfnOutput(this, 'DRMSecretArn', {
        value: this.drmSecret.secretArn,
        description: 'DRM secret ARN for content protection'
      });
    }

    // Feature flags outputs
    new cdk.CfnOutput(this, 'FeaturesEnabled', {
      value: JSON.stringify({
        lowLatency: this.config.enableLowLatency,
        drm: this.config.enableDRM,
        archiving: this.config.enableArchiving
      }),
      description: 'Enabled platform features'
    });

    // Streaming instructions output
    new cdk.CfnOutput(this, 'StreamingInstructions', {
      value: [
        'To start streaming:',
        '1. Start the MediaLive channel',
        '2. Configure your encoder with the RTMP endpoint',
        '3. Use stream key: "live"',
        '4. Test playback with the provided URLs'
      ].join(' | '),
      description: 'Quick start instructions for streaming'
    });
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Create the video streaming platform stack
new VideoStreamingPlatformStack(app, 'VideoStreamingPlatformStack', {
  description: 'Enterprise Video Streaming Platform with MediaLive, MediaPackage, and CloudFront',
  
  // Environment configuration
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },
  
  // Stack tags
  tags: {
    Project: 'VideoStreamingPlatform',
    Environment: app.node.tryGetContext('environment') || 'production',
    ManagedBy: 'AWS-CDK',
    Version: '1.0.0'
  }
});

// Add application-level tags
cdk.Tags.of(app).add('Application', 'VideoStreamingPlatform');
cdk.Tags.of(app).add('Owner', 'MediaTeam');
cdk.Tags.of(app).add('CostCenter', 'Media-Services');