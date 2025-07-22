#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

/**
 * CDK Stack for Content Delivery Networks with CloudFront S3
 * This stack creates a complete CDN solution with:
 * - S3 bucket for content storage
 * - CloudFront distribution with Origin Access Control
 * - S3 bucket for access logs
 * - CloudWatch alarms for monitoring
 * - Sample content deployment
 */
class ContentDeliveryNetworkStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8);

    // Create S3 bucket for content storage
    const contentBucket = new s3.Bucket(this, 'ContentBucket', {
      bucketName: `cdn-content-${uniqueSuffix}`,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create S3 bucket for CloudFront access logs
    const logsBucket = new s3.Bucket(this, 'LogsBucket', {
      bucketName: `cdn-logs-${uniqueSuffix}`,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteOldLogs',
          enabled: true,
          expiration: cdk.Duration.days(90),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create Origin Access Control for secure S3 access
    const originAccessControl = new cloudfront.OriginAccessControl(this, 'OriginAccessControl', {
      description: 'OAC for CDN content bucket',
      originAccessControlOriginType: cloudfront.OriginAccessControlOriginType.S3,
      signingBehavior: cloudfront.SigningBehavior.ALWAYS,
      signingProtocol: cloudfront.SigningProtocol.SIGV4,
    });

    // Create CloudFront distribution
    const distribution = new cloudfront.Distribution(this, 'Distribution', {
      comment: 'CDN for global content delivery',
      defaultRootObject: 'index.html',
      priceClass: cloudfront.PriceClass.PRICE_CLASS_100, // US and Europe only for cost optimization
      httpVersion: cloudfront.HttpVersion.HTTP2,
      enableIpv6: true,
      minimumProtocolVersion: cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
      
      // Default cache behavior
      defaultBehavior: {
        origin: new origins.S3Origin(contentBucket, {
          originAccessControl: originAccessControl,
        }),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
        compress: true,
        cachePolicy: new cloudfront.CachePolicy(this, 'DefaultCachePolicy', {
          cachePolicyName: `default-cache-policy-${uniqueSuffix}`,
          comment: 'Default cache policy for HTML content',
          defaultTtl: cdk.Duration.days(1),
          maxTtl: cdk.Duration.days(365),
          minTtl: cdk.Duration.seconds(0),
          enableAcceptEncodingGzip: true,
          enableAcceptEncodingBrotli: true,
        }),
      },

      // Additional cache behaviors for different content types
      additionalBehaviors: {
        '*.css': {
          origin: new origins.S3Origin(contentBucket, {
            originAccessControl: originAccessControl,
          }),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
          cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
          compress: true,
          cachePolicy: new cloudfront.CachePolicy(this, 'StaticAssetsCachePolicy', {
            cachePolicyName: `static-assets-cache-policy-${uniqueSuffix}`,
            comment: 'Cache policy for static assets like CSS, JS, images',
            defaultTtl: cdk.Duration.days(30),
            maxTtl: cdk.Duration.days(365),
            minTtl: cdk.Duration.seconds(0),
            enableAcceptEncodingGzip: true,
            enableAcceptEncodingBrotli: true,
          }),
        },
        'api/*': {
          origin: new origins.S3Origin(contentBucket, {
            originAccessControl: originAccessControl,
          }),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
          cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
          compress: true,
          cachePolicy: new cloudfront.CachePolicy(this, 'ApiCachePolicy', {
            cachePolicyName: `api-cache-policy-${uniqueSuffix}`,
            comment: 'Cache policy for API responses',
            defaultTtl: cdk.Duration.hours(1),
            maxTtl: cdk.Duration.days(1),
            minTtl: cdk.Duration.seconds(0),
            enableAcceptEncodingGzip: true,
            enableAcceptEncodingBrotli: true,
          }),
        },
      },

      // Custom error responses
      errorResponses: [
        {
          httpStatus: 404,
          responseHttpStatus: 200,
          responsePagePath: '/index.html',
          ttl: cdk.Duration.minutes(5),
        },
      ],

      // Enable access logging
      logBucket: logsBucket,
      logFilePrefix: 'cloudfront-logs/',
      logIncludesCookies: false,
    });

    // Grant CloudFront permission to access the content bucket
    contentBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AllowCloudFrontServicePrincipal',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('cloudfront.amazonaws.com')],
        actions: ['s3:GetObject'],
        resources: [contentBucket.arnForObjects('*')],
        conditions: {
          StringEquals: {
            'AWS:SourceArn': `arn:aws:cloudfront::${this.account}:distribution/${distribution.distributionId}`,
          },
        },
      })
    );

    // Deploy sample content to S3 bucket
    new s3deploy.BucketDeployment(this, 'DeployContent', {
      sources: [
        s3deploy.Source.data('index.html', `<!DOCTYPE html>
<html>
<head>
    <title>CDK CDN Test Page</title>
    <link rel="stylesheet" href="styles.css">
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .container { max-width: 800px; margin: 0 auto; }
        .header { background: #f4f4f4; padding: 20px; border-radius: 5px; }
        .content { padding: 20px 0; }
        .timestamp { color: #666; font-size: 0.9em; }
        .cdk-info { background: #e8f5e8; padding: 15px; border-radius: 5px; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>CloudFront CDN Test - CDK Deployment</h1>
            <p class="timestamp">Deployed via AWS CDK: ${new Date().toISOString()}</p>
        </div>
        <div class="cdk-info">
            <strong>CDK Deployment:</strong> This infrastructure was deployed using AWS CDK TypeScript.
        </div>
        <div class="content">
            <h2>Welcome to Global Content Delivery</h2>
            <p>This content is served via Amazon CloudFront edge locations worldwide.</p>
            <p>CloudFront provides fast, secure content delivery with automatic caching.</p>
            <p>Features implemented:</p>
            <ul>
                <li>Origin Access Control (OAC) for secure S3 access</li>
                <li>Multiple cache behaviors for different content types</li>
                <li>Compression enabled for better performance</li>
                <li>HTTPS redirect for security</li>
                <li>Access logging for monitoring</li>
            </ul>
        </div>
    </div>
</body>
</html>`),
        s3deploy.Source.data('styles.css', `/* CDK CDN Test Styles */
body { 
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    min-height: 100vh;
    display: flex;
    align-items: center;
}
.container { 
    background: rgba(255,255,255,0.1);
    backdrop-filter: blur(10px);
    border-radius: 10px;
    padding: 30px;
}
.header {
    background: rgba(255,255,255,0.2) !important;
    color: white;
}
.cdk-info {
    background: rgba(40,167,69,0.8) !important;
    color: white;
    border: 1px solid rgba(255,255,255,0.3);
}`),
        s3deploy.Source.data('api/api-response.json', `{
    "status": "success",
    "data": {
        "message": "API endpoint cached for 1 hour",
        "timestamp": "${new Date().toISOString()}",
        "cacheable": true,
        "deployment": "AWS CDK TypeScript"
    }
}`),
        s3deploy.Source.data('images/placeholder.txt', 'Placeholder image content for CDK deployment'),
      ],
      destinationBucket: contentBucket,
    });

    // Create CloudWatch alarms for monitoring
    const highErrorRateAlarm = new cloudwatch.Alarm(this, 'HighErrorRateAlarm', {
      alarmName: `CloudFront-HighErrorRate-${distribution.distributionId}`,
      alarmDescription: 'High error rate for CloudFront distribution',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/CloudFront',
        metricName: '4xxErrorRate',
        dimensionsMap: {
          DistributionId: distribution.distributionId,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 5,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const highOriginLatencyAlarm = new cloudwatch.Alarm(this, 'HighOriginLatencyAlarm', {
      alarmName: `CloudFront-HighOriginLatency-${distribution.distributionId}`,
      alarmDescription: 'High origin latency for CloudFront distribution',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/CloudFront',
        metricName: 'OriginLatency',
        dimensionsMap: {
          DistributionId: distribution.distributionId,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1000,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Create CloudWatch dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'CDNDashboard', {
      dashboardName: 'CloudFront-CDN-Performance',
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'CloudFront Performance Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/CloudFront',
                metricName: 'Requests',
                dimensionsMap: {
                  DistributionId: distribution.distributionId,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/CloudFront',
                metricName: 'BytesDownloaded',
                dimensionsMap: {
                  DistributionId: distribution.distributionId,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'AWS/CloudFront',
                metricName: '4xxErrorRate',
                dimensionsMap: {
                  DistributionId: distribution.distributionId,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/CloudFront',
                metricName: '5xxErrorRate',
                dimensionsMap: {
                  DistributionId: distribution.distributionId,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Cache Performance',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/CloudFront',
                metricName: 'CacheHitRate',
                dimensionsMap: {
                  DistributionId: distribution.distributionId,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'AWS/CloudFront',
                metricName: 'OriginLatency',
                dimensionsMap: {
                  DistributionId: distribution.distributionId,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
          }),
        ],
      ],
    });

    // Stack outputs
    new cdk.CfnOutput(this, 'ContentBucketName', {
      value: contentBucket.bucketName,
      description: 'Name of the S3 bucket storing content',
    });

    new cdk.CfnOutput(this, 'LogsBucketName', {
      value: logsBucket.bucketName,
      description: 'Name of the S3 bucket storing CloudFront access logs',
    });

    new cdk.CfnOutput(this, 'DistributionId', {
      value: distribution.distributionId,
      description: 'CloudFront Distribution ID',
    });

    new cdk.CfnOutput(this, 'DistributionDomainName', {
      value: distribution.distributionDomainName,
      description: 'CloudFront Distribution Domain Name',
    });

    new cdk.CfnOutput(this, 'DistributionUrl', {
      value: `https://${distribution.distributionDomainName}`,
      description: 'CloudFront Distribution URL',
    });

    new cdk.CfnOutput(this, 'OriginAccessControlId', {
      value: originAccessControl.originAccessControlId,
      description: 'Origin Access Control ID',
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=CloudFront-CDN-Performance`,
      description: 'CloudWatch Dashboard URL',
    });
  }
}

// CDK App
const app = new cdk.App();

new ContentDeliveryNetworkStack(app, 'ContentDeliveryNetworkStack', {
  description: 'CDN implementation with CloudFront and S3 - Recipe: content-delivery-networks-cloudfront-s3',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Recipe: 'content-delivery-networks-cloudfront-s3',
    Purpose: 'CDN-Implementation',
    Environment: 'Demo',
  },
});