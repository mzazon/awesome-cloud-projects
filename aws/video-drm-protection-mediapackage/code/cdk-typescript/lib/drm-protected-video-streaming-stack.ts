import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as medialive from 'aws-cdk-lib/aws-medialive';
import * as mediapackage from 'aws-cdk-lib/aws-mediapackage';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import { Construct } from 'constructs';
import { NodejsFunction } from 'aws-cdk-lib/aws-lambda-nodejs';
import * as path from 'path';

export class DrmProtectedVideoStreamingStack extends cdk.Stack {
  public readonly drmKmsKey: kms.Key;
  public readonly drmSecret: secretsmanager.Secret;
  public readonly spekeFunction: lambda.Function;
  public readonly mediaLiveChannel: medialive.CfnChannel;
  public readonly mediaPackageChannel: mediapackage.CfnChannel;
  public readonly hlsDrmEndpoint: mediapackage.CfnOriginEndpoint;
  public readonly dashDrmEndpoint: mediapackage.CfnOriginEndpoint;
  public readonly cloudFrontDistribution: cloudfront.Distribution;
  public readonly testPlayerBucket: s3.Bucket;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const randomSuffix = Math.random().toString(36).substring(2, 10);

    // Create KMS key for DRM encryption
    this.drmKmsKey = new kms.Key(this, 'DrmKmsKey', {
      description: 'DRM content encryption key',
      keyUsage: kms.KeyUsage.ENCRYPT_DECRYPT,
      keySpec: kms.KeySpec.SYMMETRIC_DEFAULT,
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    // Create KMS key alias
    new kms.Alias(this, 'DrmKmsKeyAlias', {
      aliasName: `alias/drm-content-${randomSuffix}`,
      targetKey: this.drmKmsKey,
    });

    // Create DRM configuration secret
    const drmConfig = {
      widevine_provider: 'speke-reference',
      playready_provider: 'speke-reference',
      fairplay_provider: 'speke-reference',
      content_id_template: 'urn:uuid:',
      key_rotation_interval_seconds: 3600,
      license_duration_seconds: 86400,
    };

    this.drmSecret = new secretsmanager.Secret(this, 'DrmSecret', {
      description: 'DRM configuration and keys',
      encryptionKey: this.drmKmsKey,
      secretObjectValue: {
        widevine_provider: cdk.SecretValue.unsafePlainText(drmConfig.widevine_provider),
        playready_provider: cdk.SecretValue.unsafePlainText(drmConfig.playready_provider),
        fairplay_provider: cdk.SecretValue.unsafePlainText(drmConfig.fairplay_provider),
        content_id_template: cdk.SecretValue.unsafePlainText(drmConfig.content_id_template),
        key_rotation_interval_seconds: cdk.SecretValue.unsafePlainText(drmConfig.key_rotation_interval_seconds.toString()),
        license_duration_seconds: cdk.SecretValue.unsafePlainText(drmConfig.license_duration_seconds.toString()),
      },
    });

    // Create SPEKE key provider Lambda function
    this.spekeFunction = new NodejsFunction(this, 'SpekeFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import base64
import uuid
import os
from datetime import datetime, timedelta

def lambda_handler(event, context):
    print(f"SPEKE request: {json.dumps(event, indent=2)}")
    
    # Parse SPEKE request
    if 'body' in event:
        body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
    else:
        body = event
    
    # Extract content ID and DRM systems
    content_id = body.get('content_id', str(uuid.uuid4()))
    drm_systems = body.get('drm_systems', [])
    
    # Initialize response
    response = {
        "content_id": content_id,
        "drm_systems": []
    }
    
    # Generate keys for each requested DRM system
    for drm_system in drm_systems:
        system_id = drm_system.get('system_id')
        
        if system_id == 'edef8ba9-79d6-4ace-a3c8-27dcd51d21ed':  # Widevine
            drm_response = generate_widevine_keys(content_id)
        elif system_id == '9a04f079-9840-4286-ab92-e65be0885f95':  # PlayReady  
            drm_response = generate_playready_keys(content_id)
        elif system_id == '94ce86fb-07ff-4f43-adb8-93d2fa968ca2':  # FairPlay
            drm_response = generate_fairplay_keys(content_id)
        else:
            continue
        
        response['drm_systems'].append(drm_response)
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(response)
    }

def generate_widevine_keys(content_id):
    # Generate 16-byte content key
    content_key = os.urandom(16)
    key_id = os.urandom(16)
    
    return {
        "system_id": "edef8ba9-79d6-4ace-a3c8-27dcd51d21ed",
        "key_id": base64.b64encode(key_id).decode('utf-8'),
        "content_key": base64.b64encode(content_key).decode('utf-8'),
        "url": f"https://proxy.uat.widevine.com/proxy?provider=widevine_test",
        "pssh": generate_widevine_pssh(key_id)
    }

def generate_playready_keys(content_id):
    content_key = os.urandom(16)
    key_id = os.urandom(16)
    
    return {
        "system_id": "9a04f079-9840-4286-ab92-e65be0885f95", 
        "key_id": base64.b64encode(key_id).decode('utf-8'),
        "content_key": base64.b64encode(content_key).decode('utf-8'),
        "url": f"https://playready-license.test.com/rightsmanager.asmx",
        "pssh": generate_playready_pssh(key_id, content_key)
    }

def generate_fairplay_keys(content_id):
    content_key = os.urandom(16) 
    key_id = os.urandom(16)
    iv = os.urandom(16)
    
    return {
        "system_id": "94ce86fb-07ff-4f43-adb8-93d2fa968ca2",
        "key_id": base64.b64encode(key_id).decode('utf-8'),
        "content_key": base64.b64encode(content_key).decode('utf-8'),
        "url": f"skd://fairplay-license.test.com/license",
        "certificate_url": f"https://fairplay-license.test.com/cert",
        "iv": base64.b64encode(iv).decode('utf-8')
    }

def generate_widevine_pssh(key_id):
    # Simplified Widevine PSSH generation
    pssh_data = {
        "key_ids": [base64.b64encode(key_id).decode('utf-8')],
        "provider": "widevine_test",
        "content_id": base64.b64encode(key_id).decode('utf-8')
    }
    return base64.b64encode(json.dumps(pssh_data).encode()).decode('utf-8')

def generate_playready_pssh(key_id, content_key):
    # Simplified PlayReady PSSH generation
    pssh_data = f"""
    <WRMHEADER xmlns="http://schemas.microsoft.com/DRM/2007/03/PlayReadyHeader" version="4.0.0.0">
        <DATA>
            <PROTECTINFO>
                <KEYLEN>16</KEYLEN>
                <ALGID>AESCTR</ALGID>
            </PROTECTINFO>
            <KID>{base64.b64encode(key_id).decode('utf-8')}</KID>
            <CHECKSUM></CHECKSUM>
        </DATA>
    </WRMHEADER>
    """
    return base64.b64encode(pssh_data.encode()).decode('utf-8')
`),
      timeout: cdk.Duration.seconds(30),
      environment: {
        DRM_SECRET_ARN: this.drmSecret.secretArn,
      },
      deadLetterQueue: undefined,
      retryAttempts: 2,
    });

    // Grant SPEKE function permissions
    this.drmSecret.grantRead(this.spekeFunction);
    this.drmKmsKey.grantDecrypt(this.spekeFunction);

    // Create function URL for SPEKE endpoint
    const spekeFunctionUrl = this.spekeFunction.addFunctionUrl({
      authType: lambda.FunctionUrlAuthType.NONE,
      cors: {
        allowCredentials: false,
        allowedHeaders: ['*'],
        allowedMethods: [lambda.HttpMethod.ALL],
        allowedOrigins: ['*'],
      },
    });

    // Create MediaLive input security group
    const inputSecurityGroup = new medialive.CfnInputSecurityGroup(this, 'InputSecurityGroup', {
      whitelistRules: [
        {
          cidr: '0.0.0.0/0',
        },
      ],
      tags: {
        Name: `DRMSecurityGroup-${randomSuffix}`,
        Environment: 'Production',
      },
    });

    // Create MediaLive input
    const mediaLiveInput = new medialive.CfnInput(this, 'MediaLiveInput', {
      name: `drm-protected-channel-${randomSuffix}-input`,
      type: 'RTMP_PUSH',
      inputSecurityGroups: [inputSecurityGroup.ref],
      tags: {
        Name: `DRMInput-${randomSuffix}`,
        Type: 'Live',
      },
    });

    // Create MediaPackage channel
    this.mediaPackageChannel = new mediapackage.CfnChannel(this, 'MediaPackageChannel', {
      id: `drm-package-channel-${randomSuffix}`,
      description: 'DRM-protected streaming channel',
      tags: [
        {
          key: 'Name',
          value: `DRMChannel-${randomSuffix}`,
        },
        {
          key: 'Environment',
          value: 'Production',
        },
      ],
    });

    // Create HLS DRM-protected endpoint
    this.hlsDrmEndpoint = new mediapackage.CfnOriginEndpoint(this, 'HlsDrmEndpoint', {
      channelId: this.mediaPackageChannel.id,
      id: `${this.mediaPackageChannel.id}-hls-drm`,
      manifestName: 'index.m3u8',
      hlsPackage: {
        segmentDurationSeconds: 6,
        playlistType: 'EVENT',
        playlistWindowSeconds: 300,
        programDateTimeIntervalSeconds: 60,
        adMarkers: 'SCTE35_ENHANCED',
        includeIframeOnlyStream: false,
        useAudioRenditionGroup: true,
        encryption: {
          spekeKeyProvider: {
            url: spekeFunctionUrl.url,
            resourceId: `${this.mediaPackageChannel.id}-hls`,
            systemIds: [
              'edef8ba9-79d6-4ace-a3c8-27dcd51d21ed', // Widevine
              '9a04f079-9840-4286-ab92-e65be0885f95', // PlayReady
              '94ce86fb-07ff-4f43-adb8-93d2fa968ca2', // FairPlay
            ],
          },
          keyRotationIntervalSeconds: 3600,
        },
      },
      tags: [
        {
          key: 'Type',
          value: 'HLS',
        },
        {
          key: 'DRM',
          value: 'MultiDRM',
        },
        {
          key: 'Environment',
          value: 'Production',
        },
      ],
    });

    // Create DASH DRM-protected endpoint
    this.dashDrmEndpoint = new mediapackage.CfnOriginEndpoint(this, 'DashDrmEndpoint', {
      channelId: this.mediaPackageChannel.id,
      id: `${this.mediaPackageChannel.id}-dash-drm`,
      manifestName: 'index.mpd',
      dashPackage: {
        segmentDurationSeconds: 6,
        minBufferTimeSeconds: 30,
        minUpdatePeriodSeconds: 15,
        suggestedPresentationDelaySeconds: 30,
        profile: 'NONE',
        periodTriggers: ['ADS'],
        encryption: {
          spekeKeyProvider: {
            url: spekeFunctionUrl.url,
            resourceId: `${this.mediaPackageChannel.id}-dash`,
            systemIds: [
              'edef8ba9-79d6-4ace-a3c8-27dcd51d21ed', // Widevine
              '9a04f079-9840-4286-ab92-e65be0885f95', // PlayReady
            ],
          },
          keyRotationIntervalSeconds: 3600,
        },
      },
      tags: [
        {
          key: 'Type',
          value: 'DASH',
        },
        {
          key: 'DRM',
          value: 'MultiDRM',
        },
        {
          key: 'Environment',
          value: 'Production',
        },
      ],
    });

    // Create IAM role for MediaLive
    const mediaLiveRole = new iam.Role(this, 'MediaLiveRole', {
      assumedBy: new iam.ServicePrincipal('medialive.amazonaws.com'),
      description: 'Role for MediaLive to access MediaPackage and DRM services',
      inlinePolicies: {
        MediaLiveDRMPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['mediapackage:*'],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'secretsmanager:GetSecretValue',
                'secretsmanager:DescribeSecret',
              ],
              resources: [this.drmSecret.secretArn],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'kms:Decrypt',
                'kms:GenerateDataKey',
              ],
              resources: [this.drmKmsKey.keyArn],
            }),
          ],
        }),
      },
    });

    // Create MediaLive channel
    this.mediaLiveChannel = new medialive.CfnChannel(this, 'MediaLiveChannel', {
      name: `drm-protected-channel-${randomSuffix}`,
      roleArn: mediaLiveRole.roleArn,
      inputSpecification: {
        codec: 'AVC',
        resolution: 'HD',
        maximumBitrate: 'MAX_20_MBPS',
      },
      inputAttachments: [
        {
          inputId: mediaLiveInput.ref,
          inputAttachmentName: 'primary-input',
          inputSettings: {
            sourceEndBehavior: 'CONTINUE',
            inputFilter: 'AUTO',
            filterStrength: 1,
            deblockFilter: 'ENABLED',
            denoiseFilter: 'ENABLED',
          },
        },
      ],
      destinations: [
        {
          id: 'mediapackage-drm-destination',
          mediaPackageSettings: [
            {
              channelId: this.mediaPackageChannel.id,
            },
          ],
        },
      ],
      encoderSettings: {
        audioDescriptions: [
          {
            name: 'audio_aac',
            audioSelectorName: 'default',
            audioTypeControl: 'FOLLOW_INPUT',
            languageCodeControl: 'FOLLOW_INPUT',
            codecSettings: {
              aacSettings: {
                bitrate: 128000,
                codingMode: 'CODING_MODE_2_0',
                sampleRate: 48000,
                spec: 'MPEG4',
              },
            },
          },
        ],
        videoDescriptions: [
          {
            name: 'video_1080p_drm',
            width: 1920,
            height: 1080,
            codecSettings: {
              h264Settings: {
                bitrate: 5000000,
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
                colorMetadata: 'INSERT',
                entropyEncoding: 'CABAC',
                flickerAq: 'ENABLED',
                forceFieldPictures: 'DISABLED',
                temporalAq: 'ENABLED',
                spatialAq: 'ENABLED',
              },
            },
            respondToAfd: 'RESPOND',
            scalingBehavior: 'DEFAULT',
            sharpness: 50,
          },
          {
            name: 'video_720p_drm',
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
                gopNumBFrames: 3,
                gopSize: 90,
                gopSizeUnits: 'FRAMES',
                profile: 'HIGH',
                level: 'H264_LEVEL_3_1',
                rateControlMode: 'CBR',
                syntax: 'DEFAULT',
                adaptiveQuantization: 'HIGH',
                temporalAq: 'ENABLED',
                spatialAq: 'ENABLED',
              },
            },
            respondToAfd: 'RESPOND',
            scalingBehavior: 'DEFAULT',
            sharpness: 50,
          },
          {
            name: 'video_480p_drm',
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
                adaptiveQuantization: 'MEDIUM',
              },
            },
            respondToAfd: 'RESPOND',
            scalingBehavior: 'DEFAULT',
            sharpness: 50,
          },
        ],
        outputGroups: [
          {
            name: 'MediaPackage-DRM-ABR',
            outputGroupSettings: {
              mediaPackageGroupSettings: {
                destination: {
                  destinationRefId: 'mediapackage-drm-destination',
                },
              },
            },
            outputs: [
              {
                outputName: '1080p-protected',
                videoDescriptionName: 'video_1080p_drm',
                audioDescriptionNames: ['audio_aac'],
                outputSettings: {
                  mediaPackageOutputSettings: {},
                },
              },
              {
                outputName: '720p-protected',
                videoDescriptionName: 'video_720p_drm',
                audioDescriptionNames: ['audio_aac'],
                outputSettings: {
                  mediaPackageOutputSettings: {},
                },
              },
              {
                outputName: '480p-protected',
                videoDescriptionName: 'video_480p_drm',
                audioDescriptionNames: ['audio_aac'],
                outputSettings: {
                  mediaPackageOutputSettings: {},
                },
              },
            ],
          },
        ],
        timecodeConfig: {
          source: 'EMBEDDED',
        },
      },
      tags: {
        Environment: 'Production',
        Service: 'DRM-Protected-Streaming',
        Component: 'MediaLive',
      },
    });

    // Create CloudFront distribution for DRM content delivery
    this.cloudFrontDistribution = new cloudfront.Distribution(this, 'DrmDistribution', {
      comment: 'DRM-protected content distribution with geo-restrictions',
      defaultBehavior: {
        origin: new origins.HttpOrigin(cdk.Fn.select(2, cdk.Fn.split('/', this.hlsDrmEndpoint.attrUrl)), {
          protocolPolicy: cloudfront.OriginProtocolPolicy.HTTPS_ONLY,
          customHeaders: {
            'X-MediaPackage-CDNIdentifier': `drm-protected-${randomSuffix}`,
          },
        }),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
        compress: false,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED_FOR_UNCOMPRESSED_OBJECTS,
        originRequestPolicy: cloudfront.OriginRequestPolicy.CORS_S3_ORIGIN,
      },
      additionalBehaviors: {
        '*.mpd': {
          origin: new origins.HttpOrigin(cdk.Fn.select(2, cdk.Fn.split('/', this.dashDrmEndpoint.attrUrl)), {
            protocolPolicy: cloudfront.OriginProtocolPolicy.HTTPS_ONLY,
            customHeaders: {
              'X-MediaPackage-CDNIdentifier': `drm-protected-${randomSuffix}`,
            },
          }),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
          cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
          compress: false,
          cachePolicy: new cloudfront.CachePolicy(this, 'ManifestCachePolicy', {
            cachePolicyName: `manifest-cache-policy-${randomSuffix}`,
            comment: 'Cache policy for DRM manifests',
            defaultTtl: cdk.Duration.seconds(5),
            maxTtl: cdk.Duration.seconds(60),
            minTtl: cdk.Duration.seconds(0),
          }),
        },
        '*/license/*': {
          origin: new origins.HttpOrigin(cdk.Fn.select(2, cdk.Fn.split('/', this.hlsDrmEndpoint.attrUrl)), {
            protocolPolicy: cloudfront.OriginProtocolPolicy.HTTPS_ONLY,
          }),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
          cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
          compress: false,
          cachePolicy: new cloudfront.CachePolicy(this, 'LicenseCachePolicy', {
            cachePolicyName: `license-cache-policy-${randomSuffix}`,
            comment: 'Cache policy for DRM licenses',
            defaultTtl: cdk.Duration.seconds(0),
            maxTtl: cdk.Duration.seconds(0),
            minTtl: cdk.Duration.seconds(0),
          }),
        },
      },
      enabled: true,
      priceClass: cloudfront.PriceClass.PRICE_CLASS_ALL,
      geoRestriction: cloudfront.GeoRestriction.blacklist('CN', 'RU'),
      httpVersion: cloudfront.HttpVersion.HTTP2,
      enableIpv6: true,
    });

    // Create S3 bucket for test player
    this.testPlayerBucket = new s3.Bucket(this, 'TestPlayerBucket', {
      bucketName: `drm-test-content-${randomSuffix}`,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ACLS,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      websiteIndexDocument: 'index.html',
      websiteErrorDocument: 'error.html',
    });

    // Make bucket public for static website hosting
    this.testPlayerBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        principals: [new iam.AnyPrincipal()],
        actions: ['s3:GetObject'],
        resources: [this.testPlayerBucket.arnForObjects('*')],
      })
    );

    // Deploy test player HTML
    new s3deploy.BucketDeployment(this, 'DeployTestPlayer', {
      sources: [
        s3deploy.Source.data(
          'drm-player.html',
          this.generateTestPlayerHtml(this.cloudFrontDistribution.distributionDomainName, spekeFunctionUrl.url)
        ),
      ],
      destinationBucket: this.testPlayerBucket,
      contentType: 'text/html',
    });

    // Output important values
    new cdk.CfnOutput(this, 'SpekeFunctionUrl', {
      value: spekeFunctionUrl.url,
      description: 'SPEKE endpoint URL for DRM key provider',
    });

    new cdk.CfnOutput(this, 'MediaLiveInputEndpoints', {
      value: cdk.Fn.join(' | ', mediaLiveInput.attrDestinations),
      description: 'MediaLive RTMP input endpoints',
    });

    new cdk.CfnOutput(this, 'HlsDrmEndpoint', {
      value: this.hlsDrmEndpoint.attrUrl,
      description: 'HLS DRM-protected streaming endpoint',
    });

    new cdk.CfnOutput(this, 'DashDrmEndpoint', {
      value: this.dashDrmEndpoint.attrUrl,
      description: 'DASH DRM-protected streaming endpoint',
    });

    new cdk.CfnOutput(this, 'CloudFrontDistributionDomain', {
      value: this.cloudFrontDistribution.distributionDomainName,
      description: 'CloudFront distribution domain for DRM content delivery',
    });

    new cdk.CfnOutput(this, 'TestPlayerUrl', {
      value: `http://${this.testPlayerBucket.bucketWebsiteUrl}/drm-player.html`,
      description: 'DRM test player URL',
    });

    new cdk.CfnOutput(this, 'DrmKmsKeyId', {
      value: this.drmKmsKey.keyId,
      description: 'KMS key ID for DRM encryption',
    });

    new cdk.CfnOutput(this, 'MediaLiveChannelId', {
      value: this.mediaLiveChannel.ref,
      description: 'MediaLive channel ID',
    });
  }

  private generateTestPlayerHtml(distributionDomain: string, spekeUrl: string): string {
    return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DRM-Protected Video Player</title>
    <script src="https://vjs.zencdn.net/8.0.4/video.min.js"></script>
    <link href="https://vjs.zencdn.net/8.0.4/video-js.css" rel="stylesheet">
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            max-width: 1400px;
            margin: 0 auto;
            padding: 20px;
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: white;
            min-height: 100vh;
        }
        .container {
            background: rgba(255, 255, 255, 0.1);
            padding: 30px;
            border-radius: 15px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
            backdrop-filter: blur(10px);
        }
        .header {
            text-align: center;
            margin-bottom: 30px;
        }
        .shield-icon {
            font-size: 60px;
            color: #ffd700;
            margin-bottom: 10px;
        }
        .player-wrapper {
            margin: 20px 0;
            position: relative;
        }
        .info-panel {
            background: rgba(255, 255, 255, 0.1);
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
            border-left: 4px solid #ffd700;
        }
        .tech-details {
            background: rgba(0, 0, 0, 0.3);
            padding: 15px;
            border-radius: 8px;
            font-family: monospace;
            font-size: 12px;
            overflow-x: auto;
            margin: 15px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="shield-icon">🛡️</div>
            <h1>DRM-Protected Video Streaming Test Player</h1>
            <p>Advanced content protection with multi-DRM support</p>
        </div>
        
        <div class="info-panel">
            <h3>Security Features Enabled</h3>
            <ul>
                <li>Multi-DRM Support (Widevine, PlayReady, FairPlay)</li>
                <li>HTTPS-Only Content Delivery</li>
                <li>Geographic Content Restrictions</li>
                <li>Device Authentication</li>
                <li>Encrypted Content Keys</li>
            </ul>
        </div>
        
        <div class="player-wrapper">
            <video
                id="drm-player"
                class="video-js vjs-default-skin"
                controls
                preload="auto"
                width="1340"
                height="754"
                data-setup='{"fluid": true, "responsive": true}'>
                <p class="vjs-no-js">
                    To view this DRM-protected content, please enable JavaScript and ensure your browser supports the required DRM systems.
                </p>
            </video>
        </div>
        
        <div class="tech-details">
            <h4>Technical Information</h4>
            <div id="drmTechInfo">
                <p><strong>CDN Domain:</strong> ${distributionDomain}</p>
                <p><strong>SPEKE Endpoint:</strong> ${spekeUrl}</p>
                <p><strong>Geographic Restrictions:</strong> Blocked in CN, RU</p>
                <p><strong>HLS Endpoint:</strong> https://${distributionDomain}/out/v1/index.m3u8</p>
                <p><strong>DASH Endpoint:</strong> https://${distributionDomain}/out/v1/index.mpd</p>
            </div>
        </div>
        
        <div class="info-panel">
            <h3>Testing Instructions</h3>
            <ol>
                <li>Start your MediaLive channel to begin streaming</li>
                <li>Use the generated URLs above to test protected content</li>
                <li>Load the stream and verify license acquisition</li>
                <li>Test playback quality and adaptive switching</li>
            </ol>
        </div>
    </div>
    
    <script>
        const player = videojs('drm-player', {
            html5: {
                vhs: {
                    enableLowInitialPlaylist: true,
                    experimentalBufferBasedABR: true,
                    useDevicePixelRatio: true,
                    overrideNative: true
                }
            },
            playbackRates: [0.5, 1, 1.25, 1.5, 2],
            responsive: true,
            fluid: true
        });
        
        // Load default HLS stream
        player.src({
            src: 'https://${distributionDomain}/out/v1/index.m3u8',
            type: 'application/x-mpegURL'
        });
        
        player.on('error', (e) => {
            console.error('Player error:', e);
        });
        
        player.on('loadstart', () => {
            console.log('DRM stream loading started');
        });
        
        player.on('canplay', () => {
            console.log('DRM-protected stream ready to play');
        });
    </script>
</body>
</html>`;
  }
}