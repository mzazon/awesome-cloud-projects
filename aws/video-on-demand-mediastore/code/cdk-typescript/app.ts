#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as mediastore from 'aws-cdk-lib/aws-mediastore';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Stack for Video-on-Demand Platform using AWS Elemental MediaStore
 * 
 * This stack creates a complete video streaming infrastructure including:
 * - MediaStore container for optimized video storage
 * - CloudFront distribution for global content delivery
 * - S3 staging bucket for content uploads
 * - IAM roles and policies for secure access
 * - CloudWatch monitoring and alarms
 * 
 * Note: AWS Elemental MediaStore support will end on November 13, 2025.
 * Consider migrating to S3 with CloudFront for new implementations.
 */
export class VideoOnDemandPlatformStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);
    
    // Stack parameters
    const containerName = `vod-platform-${uniqueSuffix}`;
    const stagingBucketName = `vod-staging-${uniqueSuffix}`;
    const distributionComment = `VOD Platform Distribution - ${uniqueSuffix}`;

    // S3 staging bucket for content uploads
    const stagingBucket = new s3.Bucket(this, 'StagingBucket', {
      bucketName: stagingBucketName,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'DeleteIncompleteMultipartUploads',
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
          enabled: true,
        },
        {
          id: 'DeleteOldVersions',
          noncurrentVersionExpiration: cdk.Duration.days(30),
          enabled: true,
        }
      ]
    });

    // MediaStore container for video content storage
    const mediaStoreContainer = new mediastore.CfnContainer(this, 'MediaStoreContainer', {
      containerName: containerName,
      accessLoggingEnabled: true,
      // Container policy for secure access
      policy: JSON.stringify({
        Version: '2012-10-17',
        Statement: [
          {
            Sid: 'MediaStoreFullAccess',
            Effect: 'Allow',
            Principal: '*',
            Action: [
              'mediastore:GetObject',
              'mediastore:DescribeObject'
            ],
            Resource: '*',
            Condition: {
              Bool: {
                'aws:SecureTransport': 'true'
              }
            }
          },
          {
            Sid: 'MediaStoreUploadAccess',
            Effect: 'Allow',
            Principal: {
              AWS: `arn:aws:iam::${this.account}:root`
            },
            Action: [
              'mediastore:PutObject',
              'mediastore:DeleteObject'
            ],
            Resource: '*'
          }
        ]
      }),
      // CORS policy for web applications
      corsPolicy: [
        {
          allowedOrigins: ['*'],
          allowedMethods: ['GET', 'HEAD'],
          allowedHeaders: ['*'],
          maxAgeSeconds: 3000,
          exposeHeaders: ['Date', 'Server']
        }
      ],
      // Lifecycle policy for cost optimization
      lifecyclePolicy: JSON.stringify({
        rules: [
          {
            objectGroup: '/videos/temp/*',
            objectGroupName: 'TempVideos',
            lifecycle: {
              transitionToIA: 'AFTER_30_DAYS',
              expirationInDays: 90
            }
          },
          {
            objectGroup: '/videos/archive/*',
            objectGroupName: 'ArchiveVideos',
            lifecycle: {
              transitionToIA: 'AFTER_7_DAYS',
              expirationInDays: 365
            }
          }
        ]
      }),
      // Metric policy for monitoring
      metricPolicy: JSON.stringify({
        containerLevelMetrics: 'ENABLED',
        metricPolicyRules: [
          {
            objectGroup: '/*',
            objectGroupName: 'AllObjects'
          }
        ]
      })
    });

    // IAM role for MediaStore access
    const mediaStoreAccessRole = new iam.Role(this, 'MediaStoreAccessRole', {
      roleName: `MediaStoreAccessRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('mediastore.amazonaws.com'),
      description: 'Role for MediaStore container access',
      inlinePolicies: {
        MediaStoreAccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'mediastore:GetObject',
                'mediastore:PutObject',
                'mediastore:DeleteObject',
                'mediastore:DescribeObject',
                'mediastore:ListItems'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });

    // Extract domain name from MediaStore endpoint
    const mediaStoreDomainName = cdk.Fn.select(2, cdk.Fn.split('/', mediaStoreContainer.attrEndpoint));

    // CloudFront origin for MediaStore
    const mediaStoreOrigin = new origins.HttpOrigin(mediaStoreDomainName, {
      protocolPolicy: cloudfront.OriginProtocolPolicy.HTTPS_ONLY,
      httpsPort: 443,
      originSslProtocols: [cloudfront.OriginSslPolicy.TLS_V1_2],
      customHeaders: {
        'User-Agent': 'Amazon CloudFront'
      }
    });

    // CloudFront distribution for global content delivery
    const distribution = new cloudfront.Distribution(this, 'CloudFrontDistribution', {
      comment: distributionComment,
      defaultBehavior: {
        origin: mediaStoreOrigin,
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
        compress: true,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED_FOR_UNCOMPRESSED_OBJECTS,
        originRequestPolicy: cloudfront.OriginRequestPolicy.CORS_S3_ORIGIN,
        responseHeadersPolicy: cloudfront.ResponseHeadersPolicy.CORS_ALLOW_ALL_ORIGINS
      },
      additionalBehaviors: {
        // Optimized caching for video content
        '/videos/*': {
          origin: mediaStoreOrigin,
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
          cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
          compress: true,
          cachePolicy: new cloudfront.CachePolicy(this, 'VideoCachePolicy', {
            cachePolicyName: `video-cache-policy-${uniqueSuffix}`,
            comment: 'Optimized caching for video content',
            defaultTtl: cdk.Duration.days(1),
            maxTtl: cdk.Duration.days(365),
            minTtl: cdk.Duration.seconds(0),
            headerBehavior: cloudfront.CacheHeaderBehavior.allowList(
              'Origin',
              'Access-Control-Request-Headers',
              'Access-Control-Request-Method'
            ),
            queryStringBehavior: cloudfront.CacheQueryStringBehavior.none(),
            cookieBehavior: cloudfront.CacheCookieBehavior.none(),
            enableAcceptEncodingGzip: true,
            enableAcceptEncodingBrotli: true
          })
        }
      },
      priceClass: cloudfront.PriceClass.PRICE_CLASS_ALL,
      httpVersion: cloudfront.HttpVersion.HTTP2_AND_3,
      minimumProtocolVersion: cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
      enableIpv6: true
    });

    // CloudWatch log group for application logs
    const logGroup = new logs.LogGroup(this, 'VodPlatformLogGroup', {
      logGroupName: `/aws/vodplatform/${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // CloudWatch alarms for monitoring
    const highRequestAlarm = new cloudwatch.Alarm(this, 'HighRequestRateAlarm', {
      alarmName: `MediaStore-HighRequestRate-${uniqueSuffix}`,
      alarmDescription: 'High request rate on MediaStore container',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/MediaStore',
        metricName: 'RequestCount',
        dimensionsMap: {
          ContainerName: containerName
        },
        statistic: cloudwatch.Statistic.SUM,
        period: cdk.Duration.minutes(5)
      }),
      threshold: 1000,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    const errorRateAlarm = new cloudwatch.Alarm(this, 'ErrorRateAlarm', {
      alarmName: `MediaStore-ErrorRate-${uniqueSuffix}`,
      alarmDescription: 'High error rate on MediaStore container',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/MediaStore',
        metricName: '4xxErrorCount',
        dimensionsMap: {
          ContainerName: containerName
        },
        statistic: cloudwatch.Statistic.SUM,
        period: cdk.Duration.minutes(5)
      }),
      threshold: 10,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Stack outputs
    new cdk.CfnOutput(this, 'MediaStoreContainerName', {
      value: mediaStoreContainer.containerName!,
      description: 'MediaStore container name',
      exportName: `${this.stackName}-MediaStoreContainerName`
    });

    new cdk.CfnOutput(this, 'MediaStoreEndpoint', {
      value: mediaStoreContainer.attrEndpoint,
      description: 'MediaStore container endpoint URL',
      exportName: `${this.stackName}-MediaStoreEndpoint`
    });

    new cdk.CfnOutput(this, 'CloudFrontDistributionId', {
      value: distribution.distributionId,
      description: 'CloudFront distribution ID',
      exportName: `${this.stackName}-CloudFrontDistributionId`
    });

    new cdk.CfnOutput(this, 'CloudFrontDomainName', {
      value: distribution.distributionDomainName,
      description: 'CloudFront distribution domain name',
      exportName: `${this.stackName}-CloudFrontDomainName`
    });

    new cdk.CfnOutput(this, 'CloudFrontDistributionUrl', {
      value: `https://${distribution.distributionDomainName}`,
      description: 'CloudFront distribution URL',
      exportName: `${this.stackName}-CloudFrontDistributionUrl`
    });

    new cdk.CfnOutput(this, 'StagingBucketName', {
      value: stagingBucket.bucketName,
      description: 'S3 staging bucket name',
      exportName: `${this.stackName}-StagingBucketName`
    });

    new cdk.CfnOutput(this, 'StagingBucketArn', {
      value: stagingBucket.bucketArn,
      description: 'S3 staging bucket ARN',
      exportName: `${this.stackName}-StagingBucketArn`
    });

    new cdk.CfnOutput(this, 'IAMRoleName', {
      value: mediaStoreAccessRole.roleName,
      description: 'IAM role name for MediaStore access',
      exportName: `${this.stackName}-IAMRoleName`
    });

    new cdk.CfnOutput(this, 'IAMRoleArn', {
      value: mediaStoreAccessRole.roleArn,
      description: 'IAM role ARN for MediaStore access',
      exportName: `${this.stackName}-IAMRoleArn`
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: logGroup.logGroupName,
      description: 'CloudWatch log group name',
      exportName: `${this.stackName}-LogGroupName`
    });

    new cdk.CfnOutput(this, 'HighRequestAlarmName', {
      value: highRequestAlarm.alarmName,
      description: 'CloudWatch alarm for high request rate',
      exportName: `${this.stackName}-HighRequestAlarmName`
    });

    new cdk.CfnOutput(this, 'ErrorRateAlarmName', {
      value: errorRateAlarm.alarmName,
      description: 'CloudWatch alarm for error rate',
      exportName: `${this.stackName}-ErrorRateAlarmName`
    });

    // Testing and validation outputs
    new cdk.CfnOutput(this, 'TestVideoUrl', {
      value: `https://${distribution.distributionDomainName}/videos/sample-video.mp4`,
      description: 'Test video URL for validation',
      exportName: `${this.stackName}-TestVideoUrl`
    });

    new cdk.CfnOutput(this, 'MediaStoreConsoleUrl', {
      value: `https://console.aws.amazon.com/mediastore/home?region=${this.region}#/containers/${containerName}`,
      description: 'AWS Console URL for MediaStore container',
      exportName: `${this.stackName}-MediaStoreConsoleUrl`
    });

    new cdk.CfnOutput(this, 'CloudFrontConsoleUrl', {
      value: `https://console.aws.amazon.com/cloudfront/v3/home?region=${this.region}#/distributions/${distribution.distributionId}`,
      description: 'AWS Console URL for CloudFront distribution',
      exportName: `${this.stackName}-CloudFrontConsoleUrl`
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'VideoOnDemandPlatform');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('Service', 'MediaStreaming');
    cdk.Tags.of(this).add('CostCenter', 'MediaServices');
    cdk.Tags.of(this).add('Owner', 'MediaTeam');
  }
}

// CDK Application
const app = new cdk.App();

// Environment configuration
const env: cdk.Environment = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
};

// Create the stack
new VideoOnDemandPlatformStack(app, 'VideoOnDemandPlatformStack', {
  env,
  description: 'Video-on-Demand Platform with AWS Elemental MediaStore and CloudFront (uksb-1tthgi812) (tag:video-on-demand-platforms-aws-elemental-mediastore)',
  terminationProtection: false,
  stackName: 'video-on-demand-platform-stack'
});

// Synthesize the application
app.synth();