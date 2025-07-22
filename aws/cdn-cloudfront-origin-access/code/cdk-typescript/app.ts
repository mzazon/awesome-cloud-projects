#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as wafv2 from 'aws-cdk-lib/aws-wafv2';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as iam from 'aws-cdk-lib/aws-iam';
import { RemovalPolicy, Duration } from 'aws-cdk-lib';

/**
 * Props for the CloudFrontCdnStack
 */
interface CloudFrontCdnStackProps extends cdk.StackProps {
  /** 
   * Whether to enable real-time metrics for CloudFront 
   * @default false
   */
  readonly enableRealtimeMetrics?: boolean;
  
  /** 
   * Rate limit for WAF (requests per 5 minutes) 
   * @default 2000
   */
  readonly rateLimitThreshold?: number;
  
  /** 
   * CloudFront price class 
   * @default PriceClass_All
   */
  readonly priceClass?: cloudfront.PriceClass;
  
  /** 
   * Whether to deploy sample content 
   * @default true
   */
  readonly deploySampleContent?: boolean;
}

/**
 * CDK Stack for building a global content delivery network using CloudFront with Origin Access Control (OAC)
 * 
 * This stack demonstrates AWS best practices for:
 * - Secure content delivery using CloudFront with OAC
 * - S3 bucket protection from direct access
 * - WAF integration for security
 * - Comprehensive monitoring and alerting
 * - Optimized caching behaviors for different content types
 */
export class CloudFrontCdnStack extends cdk.Stack {
  /** The CloudFront distribution */
  public readonly distribution: cloudfront.Distribution;
  
  /** The S3 bucket for content storage */
  public readonly contentBucket: s3.Bucket;
  
  /** The S3 bucket for CloudFront logs */
  public readonly logsBucket: s3.Bucket;
  
  /** The WAF Web ACL */
  public readonly webAcl: wafv2.CfnWebACL;
  
  /** The Origin Access Control */
  public readonly originAccessControl: cloudfront.CfnOriginAccessControl;

  constructor(scope: Construct, id: string, props: CloudFrontCdnStackProps = {}) {
    super(scope, id, props);

    // Create unique suffix for resource naming
    const uniqueSuffix = this.node.addr.slice(-8).toLowerCase();

    // Create S3 bucket for content storage
    this.contentBucket = new s3.Bucket(this, 'ContentBucket', {
      bucketName: `cdn-content-${uniqueSuffix}`,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      versioned: false,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create S3 bucket for CloudFront logs
    this.logsBucket = new s3.Bucket(this, 'LogsBucket', {
      bucketName: `cdn-logs-${uniqueSuffix}`,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'DeleteOldLogs',
          enabled: true,
          expiration: Duration.days(90),
        },
      ],
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create WAF Web ACL for CloudFront protection
    this.webAcl = new wafv2.CfnWebACL(this, 'CdnWebAcl', {
      name: `cdn-waf-${uniqueSuffix}`,
      scope: 'CLOUDFRONT',
      defaultAction: { allow: {} },
      rules: [
        {
          name: 'AWSManagedRulesCommonRuleSet',
          priority: 1,
          overrideAction: { none: {} },
          statement: {
            managedRuleGroupStatement: {
              vendorName: 'AWS',
              name: 'AWSManagedRulesCommonRuleSet',
            },
          },
          visibilityConfig: {
            sampledRequestsEnabled: true,
            cloudWatchMetricsEnabled: true,
            metricName: 'CommonRuleSetMetric',
          },
        },
        {
          name: 'AWSManagedRulesKnownBadInputsRuleSet',
          priority: 2,
          overrideAction: { none: {} },
          statement: {
            managedRuleGroupStatement: {
              vendorName: 'AWS',
              name: 'AWSManagedRulesKnownBadInputsRuleSet',
            },
          },
          visibilityConfig: {
            sampledRequestsEnabled: true,
            cloudWatchMetricsEnabled: true,
            metricName: 'KnownBadInputsMetric',
          },
        },
        {
          name: 'RateLimitRule',
          priority: 3,
          action: { block: {} },
          statement: {
            rateBasedStatement: {
              limit: props.rateLimitThreshold || 2000,
              aggregateKeyType: 'IP',
            },
          },
          visibilityConfig: {
            sampledRequestsEnabled: true,
            cloudWatchMetricsEnabled: true,
            metricName: 'RateLimitMetric',
          },
        },
      ],
      visibilityConfig: {
        sampledRequestsEnabled: true,
        cloudWatchMetricsEnabled: true,
        metricName: 'CDNWebACL',
      },
    });

    // Create Origin Access Control (OAC)
    this.originAccessControl = new cloudfront.CfnOriginAccessControl(this, 'OriginAccessControl', {
      originAccessControlConfig: {
        name: `cdn-oac-${uniqueSuffix}`,
        description: `Origin Access Control for ${this.contentBucket.bucketName}`,
        originAccessControlOriginType: 's3',
        signingBehavior: 'always',
        signingProtocol: 'sigv4',
      },
    });

    // Create CloudFront distribution
    this.distribution = new cloudfront.Distribution(this, 'CdnDistribution', {
      comment: `CDN Distribution ${uniqueSuffix}`,
      defaultRootObject: 'index.html',
      enabled: true,
      httpVersion: cloudfront.HttpVersion.HTTP2_AND_3,
      priceClass: props.priceClass || cloudfront.PriceClass.PRICE_CLASS_ALL,
      enableIpv6: true,
      minimumProtocolVersion: cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
      
      // Default behavior for HTML content
      defaultBehavior: {
        origin: new origins.S3Origin(this.contentBucket),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        originRequestPolicy: cloudfront.OriginRequestPolicy.CORS_S3_ORIGIN,
        responseHeadersPolicy: cloudfront.ResponseHeadersPolicy.SECURITY_HEADERS,
        compress: true,
      },

      // Additional cache behaviors for different content types
      additionalBehaviors: {
        '/images/*': {
          origin: new origins.S3Origin(this.contentBucket),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
          compress: true,
        },
        '/css/*': {
          origin: new origins.S3Origin(this.contentBucket),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
          compress: true,
        },
        '/js/*': {
          origin: new origins.S3Origin(this.contentBucket),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
          compress: true,
        },
      },

      // Custom error responses for SPA support
      errorResponses: [
        {
          httpStatus: 404,
          responseHttpStatus: 200,
          responsePagePath: '/index.html',
          ttl: Duration.minutes(5),
        },
        {
          httpStatus: 403,
          responseHttpStatus: 200,
          responsePagePath: '/index.html',
          ttl: Duration.minutes(5),
        },
      ],

      // Enable access logging
      logBucket: this.logsBucket,
      logFilePrefix: 'cloudfront-logs/',
      logIncludesCookies: false,

      // Associate WAF Web ACL
      webAclId: this.webAcl.attrArn,
    });

    // Update Origin Access Control in CloudFormation
    const cfnDistribution = this.distribution.node.defaultChild as cloudfront.CfnDistribution;
    cfnDistribution.addPropertyOverride('DistributionConfig.Origins.0.OriginAccessControlId', this.originAccessControl.ref);
    cfnDistribution.addPropertyOverride('DistributionConfig.Origins.0.S3OriginConfig.OriginAccessIdentity', '');

    // Add bucket policy to allow CloudFront OAC access
    this.contentBucket.addToResourcePolicy(new iam.PolicyStatement({
      sid: 'AllowCloudFrontServicePrincipalReadOnly',
      effect: iam.Effect.ALLOW,
      principals: [new iam.ServicePrincipal('cloudfront.amazonaws.com')],
      actions: ['s3:GetObject'],
      resources: [this.contentBucket.arnForObjects('*')],
      conditions: {
        StringEquals: {
          'AWS:SourceArn': `arn:aws:cloudfront::${this.account}:distribution/${this.distribution.distributionId}`,
        },
      },
    }));

    // Create CloudWatch alarms for monitoring
    this.createCloudWatchAlarms();

    // Deploy sample content if requested
    if (props.deploySampleContent !== false) {
      this.deploySampleContent();
    }

    // Enable real-time metrics if requested
    if (props.enableRealtimeMetrics) {
      this.enableRealtimeMetrics();
    }

    // Output important values
    new cdk.CfnOutput(this, 'DistributionId', {
      value: this.distribution.distributionId,
      description: 'CloudFront Distribution ID',
    });

    new cdk.CfnOutput(this, 'DistributionDomainName', {
      value: this.distribution.distributionDomainName,
      description: 'CloudFront Distribution Domain Name',
    });

    new cdk.CfnOutput(this, 'ContentBucketName', {
      value: this.contentBucket.bucketName,
      description: 'S3 Content Bucket Name',
    });

    new cdk.CfnOutput(this, 'LogsBucketName', {
      value: this.logsBucket.bucketName,
      description: 'S3 Logs Bucket Name',
    });

    new cdk.CfnOutput(this, 'WebAclArn', {
      value: this.webAcl.attrArn,
      description: 'WAF Web ACL ARN',
    });

    new cdk.CfnOutput(this, 'SampleUrls', {
      value: [
        `https://${this.distribution.distributionDomainName}`,
        `https://${this.distribution.distributionDomainName}/css/styles.css`,
        `https://${this.distribution.distributionDomainName}/js/main.js`,
        `https://${this.distribution.distributionDomainName}/images/test-image.jpg`,
      ].join('\n'),
      description: 'Sample URLs to test the CDN',
    });
  }

  /**
   * Create CloudWatch alarms for monitoring distribution health
   */
  private createCloudWatchAlarms(): void {
    // Alarm for high 4xx error rate
    new cloudwatch.Alarm(this, 'HighErrorRateAlarm', {
      alarmName: `CloudFront-4xx-Errors-${this.distribution.distributionId}`,
      alarmDescription: 'High 4xx error rate for CloudFront distribution',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/CloudFront',
        metricName: '4xxErrorRate',
        dimensionsMap: {
          DistributionId: this.distribution.distributionId,
        },
        statistic: 'Average',
        period: Duration.minutes(5),
      }),
      threshold: 5.0,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Alarm for low cache hit rate
    new cloudwatch.Alarm(this, 'LowCacheHitRateAlarm', {
      alarmName: `CloudFront-Low-Cache-Hit-Rate-${this.distribution.distributionId}`,
      alarmDescription: 'Low cache hit rate for CloudFront distribution',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/CloudFront',
        metricName: 'CacheHitRate',
        dimensionsMap: {
          DistributionId: this.distribution.distributionId,
        },
        statistic: 'Average',
        period: Duration.minutes(5),
      }),
      threshold: 80.0,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 3,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
  }

  /**
   * Deploy sample content to the S3 bucket for testing
   */
  private deploySampleContent(): void {
    new s3deploy.BucketDeployment(this, 'SampleContentDeployment', {
      sources: [
        s3deploy.Source.data('index.html', `<!DOCTYPE html>
<html>
<head>
    <title>CDN Test Page</title>
    <link rel="stylesheet" href="/css/styles.css">
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body>
    <h1>CloudFront CDN Test</h1>
    <p>This page is served through CloudFront CDN with Origin Access Control.</p>
    <img src="/images/test-image.jpg" alt="Test Image" style="max-width: 100%; height: auto;">
    <script src="/js/main.js"></script>
</body>
</html>`),
        s3deploy.Source.data('css/styles.css', `body {
    font-family: Arial, sans-serif;
    margin: 40px;
    background-color: #f5f5f5;
    color: #333;
}

h1 {
    color: #232F3E;
    border-bottom: 2px solid #FF9900;
    padding-bottom: 10px;
}

img {
    max-width: 100%;
    height: auto;
    border: 1px solid #ddd;
    border-radius: 4px;
    padding: 5px;
    margin: 20px 0;
}

p {
    line-height: 1.6;
    margin: 20px 0;
}`),
        s3deploy.Source.data('js/main.js', `console.log('CDN assets loaded successfully via CloudFront');

document.addEventListener('DOMContentLoaded', function() {
    const timestamp = new Date().toISOString();
    console.log('Page loaded at:', timestamp);
    
    // Add a small indicator that JavaScript loaded
    const indicator = document.createElement('p');
    indicator.textContent = 'JavaScript loaded successfully at ' + timestamp;
    indicator.style.color = '#FF9900';
    indicator.style.fontSize = '0.9em';
    document.body.appendChild(indicator);
});`),
        s3deploy.Source.data('images/test-image.jpg', 
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', // 1x1 transparent PNG in base64
        ),
      ],
      destinationBucket: this.contentBucket,
      contentType: 'text/html',
      metadata: {
        'Cache-Control': 'max-age=31536000',
      },
    });
  }

  /**
   * Enable real-time metrics for the CloudFront distribution
   */
  private enableRealtimeMetrics(): void {
    new cloudfront.CfnMonitoringSubscription(this, 'RealtimeMetrics', {
      distributionId: this.distribution.distributionId,
      monitoringSubscription: {
        realtimeMetricsSubscriptionConfig: {
          realtimeMetricsSubscriptionStatus: 'Enabled',
        },
      },
    });
  }
}

/**
 * CDK Application
 */
class CdnApp extends cdk.App {
  constructor() {
    super();

    // Get configuration from context or environment variables
    const enableRealtimeMetrics = this.node.tryGetContext('enableRealtimeMetrics') === 'true' || 
                                 process.env.ENABLE_REALTIME_METRICS === 'true';
    
    const rateLimitThreshold = parseInt(this.node.tryGetContext('rateLimitThreshold') || 
                                      process.env.RATE_LIMIT_THRESHOLD || '2000');
    
    const deploySampleContent = this.node.tryGetContext('deploySampleContent') !== 'false' && 
                               process.env.DEPLOY_SAMPLE_CONTENT !== 'false';

    // Create the main stack
    new CloudFrontCdnStack(this, 'CloudFrontCdnStack', {
      description: 'Global content delivery network with CloudFront and Origin Access Control (uksb-1tupboc58)',
      enableRealtimeMetrics,
      rateLimitThreshold,
      deploySampleContent,
      env: {
        account: process.env.CDK_DEFAULT_ACCOUNT,
        region: process.env.CDK_DEFAULT_REGION || 'us-east-1', // CloudFront is global but console is in us-east-1
      },
      tags: {
        Project: 'CloudFront-CDN',
        Purpose: 'Global Content Delivery',
        Environment: process.env.ENVIRONMENT || 'development',
      },
    });
  }
}

// Initialize the CDK app
new CdnApp();