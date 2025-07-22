#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as mediaconnect from 'aws-cdk-lib/aws-mediaconnect';
import * as medialive from 'aws-cdk-lib/aws-medialive';
import * as mediapackage from 'aws-cdk-lib/aws-mediapackage';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Properties for the Live Event Broadcasting Stack
 */
export interface LiveEventBroadcastingStackProps extends cdk.StackProps {
  /**
   * The name prefix for all resources
   * @default 'live-event'
   */
  readonly namePrefix?: string;
  
  /**
   * The availability zones for MediaConnect flows
   * @default ['us-east-1a', 'us-east-1b']
   */
  readonly availabilityZones?: string[];
  
  /**
   * Enable detailed monitoring
   * @default true
   */
  readonly enableDetailedMonitoring?: boolean;
  
  /**
   * The CIDR block for allowed source IPs
   * @default '0.0.0.0/0'
   */
  readonly allowedSourceCidr?: string;
}

/**
 * Stack for Live Event Broadcasting with AWS Elemental MediaConnect
 * 
 * This stack creates a complete live event broadcasting pipeline using:
 * - MediaConnect flows for reliable video transport
 * - MediaLive for video encoding and processing  
 * - MediaPackage for scalable content distribution
 * - CloudWatch for comprehensive monitoring
 */
export class LiveEventBroadcastingStack extends cdk.Stack {
  
  public readonly primaryFlowArn: string;
  public readonly backupFlowArn: string;
  public readonly medialiveChannelId: string;
  public readonly mediapackageChannelId: string;
  public readonly hlsEndpointUrl: string;
  public readonly primaryIngestEndpoint: string;
  public readonly backupIngestEndpoint: string;

  constructor(scope: Construct, id: string, props: LiveEventBroadcastingStackProps = {}) {
    super(scope, id, props);

    // Configuration
    const namePrefix = props.namePrefix || 'live-event';
    const availabilityZones = props.availabilityZones || ['us-east-1a', 'us-east-1b'];
    const enableDetailedMonitoring = props.enableDetailedMonitoring ?? true;
    const allowedSourceCidr = props.allowedSourceCidr || '0.0.0.0/0';

    // Generate unique suffix for resource names
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);
    
    // Create IAM role for MediaLive
    const mediaLiveRole = new iam.Role(this, 'MediaLiveRole', {
      roleName: `MediaLiveAccessRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('medialive.amazonaws.com'),
      description: 'IAM role for MediaLive service to access MediaConnect and MediaPackage',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('MediaLiveFullAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('MediaConnectFullAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('MediaPackageFullAccess'),
      ],
    });

    // Create MediaConnect flows for redundant video transport
    const primaryFlow = new mediaconnect.CfnFlow(this, 'PrimaryFlow', {
      name: `${namePrefix}-primary-${uniqueSuffix}`,
      description: 'Primary flow for live event broadcasting',
      availabilityZone: availabilityZones[0],
      source: {
        name: 'PrimarySource',
        protocol: 'rtp',
        ingestPort: 5000,
        whitelistCidr: allowedSourceCidr,
        description: 'Primary encoder input',
      },
    });

    const backupFlow = new mediaconnect.CfnFlow(this, 'BackupFlow', {
      name: `${namePrefix}-backup-${uniqueSuffix}`,
      description: 'Backup flow for live event broadcasting',
      availabilityZone: availabilityZones[1],
      source: {
        name: 'BackupSource',
        protocol: 'rtp',
        ingestPort: 5001,
        whitelistCidr: allowedSourceCidr,
        description: 'Backup encoder input',
      },
    });

    // Add outputs to MediaConnect flows for MediaLive integration
    new mediaconnect.CfnFlowOutput(this, 'PrimaryFlowOutput', {
      flowArn: primaryFlow.attrFlowArn,
      name: 'MediaLiveOutput',
      protocol: 'rtp-fec',
      destination: '0.0.0.0',
      port: 5002,
      description: 'Output to MediaLive primary input',
    });

    new mediaconnect.CfnFlowOutput(this, 'BackupFlowOutput', {
      flowArn: backupFlow.attrFlowArn,
      name: 'MediaLiveOutput',
      protocol: 'rtp-fec',
      destination: '0.0.0.0',
      port: 5003,
      description: 'Output to MediaLive backup input',
    });

    // Create MediaPackage channel for content distribution
    const mediapackageChannel = new mediapackage.CfnChannel(this, 'MediaPackageChannel', {
      id: `${namePrefix}-package-${uniqueSuffix}`,
      description: 'Live event broadcasting channel',
    });

    // Create MediaLive inputs for video ingestion
    const primaryInput = new medialive.CfnInput(this, 'PrimaryInput', {
      name: `${namePrefix}-primary-${uniqueSuffix}-input`,
      type: 'MEDIACONNECT',
      mediaConnectFlows: [
        {
          flowArn: primaryFlow.attrFlowArn,
        },
      ],
      roleArn: mediaLiveRole.roleArn,
    });

    const backupInput = new medialive.CfnInput(this, 'BackupInput', {
      name: `${namePrefix}-backup-${uniqueSuffix}-input`,
      type: 'MEDIACONNECT',
      mediaConnectFlows: [
        {
          flowArn: backupFlow.attrFlowArn,
        },
      ],
      roleArn: mediaLiveRole.roleArn,
    });

    // Create MediaLive channel for video encoding
    const medialiveChannel = new medialive.CfnChannel(this, 'MediaLiveChannel', {
      name: `${namePrefix}-channel-${uniqueSuffix}`,
      roleArn: mediaLiveRole.roleArn,
      inputAttachments: [
        {
          inputAttachmentName: 'primary-input',
          inputId: primaryInput.ref,
          inputSettings: {
            audioSelectors: [
              {
                name: 'default',
                selectorSettings: {
                  audioPidSelection: {
                    pid: 256,
                  },
                },
              },
            ],
            videoSelector: {
              programId: 1,
            },
          },
        },
        {
          inputAttachmentName: 'backup-input',
          inputId: backupInput.ref,
          inputSettings: {
            audioSelectors: [
              {
                name: 'default',
                selectorSettings: {
                  audioPidSelection: {
                    pid: 256,
                  },
                },
              },
            ],
            videoSelector: {
              programId: 1,
            },
          },
        },
      ],
      destinations: [
        {
          id: 'mediapackage-destination',
          mediaPackageSettings: [
            {
              channelId: mediapackageChannel.ref,
            },
          ],
        },
      ],
      encoderSettings: {
        audioDescriptions: [
          {
            audioSelectorName: 'default',
            codecSettings: {
              aacSettings: {
                bitrate: 128000,
                codingMode: 'CODING_MODE_2_0',
                inputType: 'BROADCASTER_MIXED_AD',
                profile: 'LC',
                sampleRate: 48000,
              },
            },
            name: 'audio_1',
          },
        ],
        videoDescriptions: [
          {
            codecSettings: {
              h264Settings: {
                bitrate: 2000000,
                framerateControl: 'SPECIFIED',
                framerateDenominator: 1,
                framerateNumerator: 30,
                gopBReference: 'DISABLED',
                gopClosedCadence: 1,
                gopNumBFrames: 2,
                gopSize: 90,
                gopSizeUnits: 'FRAMES',
                level: 'H264_LEVEL_4_1',
                lookAheadRateControl: 'MEDIUM',
                maxBitrate: 2000000,
                numRefFrames: 3,
                parControl: 'INITIALIZE_FROM_SOURCE',
                profile: 'MAIN',
                rateControlMode: 'CBR',
                syntax: 'DEFAULT',
              },
            },
            height: 720,
            name: 'video_720p30',
            respondToAfd: 'NONE',
            sharpness: 50,
            width: 1280,
          },
        ],
        outputGroups: [
          {
            name: 'mediapackage-output-group',
            outputGroupSettings: {
              mediaPackageGroupSettings: {
                destination: {
                  destinationRefId: 'mediapackage-destination',
                },
              },
            },
            outputs: [
              {
                audioDescriptionNames: ['audio_1'],
                outputName: '720p30',
                outputSettings: {
                  mediaPackageOutputSettings: {},
                },
                videoDescriptionName: 'video_720p30',
              },
            ],
          },
        ],
      },
      inputSpecification: {
        codec: 'AVC',
        resolution: 'HD',
        maximumBitrate: 'MAX_10_MBPS',
      },
    });

    // Create MediaPackage HLS origin endpoint
    const hlsEndpoint = new mediapackage.CfnOriginEndpoint(this, 'HLSEndpoint', {
      channelId: mediapackageChannel.ref,
      id: `${namePrefix}-package-${uniqueSuffix}-hls`,
      description: 'HLS endpoint for live event broadcasting',
      hlsPackage: {
        adMarkers: 'NONE',
        includeIframeOnlyStream: false,
        playlistType: 'EVENT',
        playlistWindowSeconds: 60,
        programDateTimeIntervalSeconds: 0,
        segmentDurationSeconds: 6,
        streamSelection: {
          maxVideoBitsPerSecond: 2147483647,
          minVideoBitsPerSecond: 0,
          streamOrder: 'ORIGINAL',
        },
      },
    });

    // Create CloudWatch Log Groups for monitoring
    if (enableDetailedMonitoring) {
      new logs.LogGroup(this, 'PrimaryFlowLogGroup', {
        logGroupName: `/aws/mediaconnect/${namePrefix}-primary-${uniqueSuffix}`,
        retention: logs.RetentionDays.ONE_WEEK,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      });

      new logs.LogGroup(this, 'BackupFlowLogGroup', {
        logGroupName: `/aws/mediaconnect/${namePrefix}-backup-${uniqueSuffix}`,
        retention: logs.RetentionDays.ONE_WEEK,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      });

      // Create CloudWatch alarms for monitoring
      new cloudwatch.Alarm(this, 'PrimaryFlowSourceErrorsAlarm', {
        alarmName: `${namePrefix}-primary-${uniqueSuffix}-source-errors`,
        alarmDescription: 'Alert on MediaConnect primary flow source errors',
        metric: new cloudwatch.Metric({
          namespace: 'AWS/MediaConnect',
          metricName: 'SourceConnectionErrors',
          dimensionsMap: {
            FlowName: `${namePrefix}-primary-${uniqueSuffix}`,
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
        threshold: 1,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        evaluationPeriods: 1,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      });

      new cloudwatch.Alarm(this, 'MediaLiveChannelInputErrorsAlarm', {
        alarmName: `${namePrefix}-channel-${uniqueSuffix}-input-errors`,
        alarmDescription: 'Alert on MediaLive channel input errors',
        metric: new cloudwatch.Metric({
          namespace: 'AWS/MediaLive',
          metricName: 'InputVideoFrameRate',
          dimensionsMap: {
            ChannelId: medialiveChannel.ref,
          },
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        }),
        threshold: 1,
        comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
        evaluationPeriods: 2,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      });
    }

    // Add resource tags for better organization
    const resourceTags = {
      Environment: 'Production',
      Application: 'LiveBroadcast',
      MonitoringLevel: enableDetailedMonitoring ? 'Detailed' : 'Basic',
      CreatedBy: 'CDK',
    };

    cdk.Tags.of(primaryFlow).add('ResourceType', 'MediaConnect-Primary');
    cdk.Tags.of(backupFlow).add('ResourceType', 'MediaConnect-Backup');
    cdk.Tags.of(medialiveChannel).add('ResourceType', 'MediaLive-Channel');
    cdk.Tags.of(mediapackageChannel).add('ResourceType', 'MediaPackage-Channel');
    cdk.Tags.of(hlsEndpoint).add('ResourceType', 'MediaPackage-Endpoint');

    Object.entries(resourceTags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });

    // Store important values for outputs
    this.primaryFlowArn = primaryFlow.attrFlowArn;
    this.backupFlowArn = backupFlow.attrFlowArn;
    this.medialiveChannelId = medialiveChannel.ref;
    this.mediapackageChannelId = mediapackageChannel.ref;
    this.hlsEndpointUrl = hlsEndpoint.attrUrl;
    this.primaryIngestEndpoint = primaryFlow.attrSourceIngestIp;
    this.backupIngestEndpoint = backupFlow.attrSourceIngestIp;

    // Create stack outputs
    new cdk.CfnOutput(this, 'PrimaryFlowArn', {
      value: this.primaryFlowArn,
      description: 'ARN of the primary MediaConnect flow',
      exportName: `${this.stackName}-PrimaryFlowArn`,
    });

    new cdk.CfnOutput(this, 'BackupFlowArn', {
      value: this.backupFlowArn,
      description: 'ARN of the backup MediaConnect flow',
      exportName: `${this.stackName}-BackupFlowArn`,
    });

    new cdk.CfnOutput(this, 'MediaLiveChannelId', {
      value: this.medialiveChannelId,
      description: 'ID of the MediaLive channel',
      exportName: `${this.stackName}-MediaLiveChannelId`,
    });

    new cdk.CfnOutput(this, 'MediaPackageChannelId', {
      value: this.mediapackageChannelId,
      description: 'ID of the MediaPackage channel',
      exportName: `${this.stackName}-MediaPackageChannelId`,
    });

    new cdk.CfnOutput(this, 'HLSEndpointUrl', {
      value: this.hlsEndpointUrl,
      description: 'URL of the HLS playback endpoint',
      exportName: `${this.stackName}-HLSEndpointUrl`,
    });

    new cdk.CfnOutput(this, 'PrimaryIngestEndpoint', {
      value: `${this.primaryIngestEndpoint}:5000`,
      description: 'Primary flow ingest endpoint (IP:Port)',
      exportName: `${this.stackName}-PrimaryIngestEndpoint`,
    });

    new cdk.CfnOutput(this, 'BackupIngestEndpoint', {
      value: `${this.backupIngestEndpoint}:5001`,
      description: 'Backup flow ingest endpoint (IP:Port)',
      exportName: `${this.stackName}-BackupIngestEndpoint`,
    });

    new cdk.CfnOutput(this, 'MediaLiveRoleArn', {
      value: mediaLiveRole.roleArn,
      description: 'ARN of the MediaLive IAM role',
      exportName: `${this.stackName}-MediaLiveRoleArn`,
    });
  }
}

// CDK App
const app = new cdk.App();

// Create the Live Event Broadcasting stack
new LiveEventBroadcastingStack(app, 'LiveEventBroadcastingStack', {
  description: 'Live Event Broadcasting with AWS Elemental MediaConnect - CDK TypeScript',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  // Optional: Customize stack properties
  namePrefix: process.env.NAME_PREFIX,
  enableDetailedMonitoring: process.env.ENABLE_DETAILED_MONITORING !== 'false',
  allowedSourceCidr: process.env.ALLOWED_SOURCE_CIDR,
});

// Synthesize the CloudFormation template
app.synth();