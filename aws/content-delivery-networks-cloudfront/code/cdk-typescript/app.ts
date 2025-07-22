#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as wafv2 from 'aws-cdk-lib/aws-wafv2';
import * as kinesis from 'aws-cdk-lib/aws-kinesis';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { RemovalPolicy, Duration, CfnOutput } from 'aws-cdk-lib';

interface ContentDeliveryNetworkStackProps extends cdk.StackProps {
  /**
   * Environment for deployment (dev, staging, prod)
   */
  environment?: string;
  
  /**
   * Project name for resource naming
   */
  projectName?: string;
  
  /**
   * Enable real-time logging
   */
  enableRealTimeLogs?: boolean;
  
  /**
   * Enable WAF protection
   */
  enableWaf?: boolean;
  
  /**
   * Price class for CloudFront distribution
   */
  priceClass?: cloudfront.PriceClass;
}

/**
 * Advanced CloudFront CDN Stack with multiple origins, edge functions, and security controls
 * 
 * This stack creates a sophisticated content delivery network with:
 * - Multiple origins (S3, custom origins)
 * - CloudFront Functions for request processing
 * - Lambda@Edge for response manipulation
 * - AWS WAF for security protection
 * - Real-time logging and monitoring
 * - KeyValueStore for dynamic configuration
 */
export class ContentDeliveryNetworkStack extends cdk.Stack {
  public readonly distribution: cloudfront.Distribution;
  public readonly contentBucket: s3.Bucket;
  public readonly webAcl: wafv2.CfnWebACL;
  
  constructor(scope: Construct, id: string, props: ContentDeliveryNetworkStackProps = {}) {
    super(scope, id, props);
    
    // Configuration
    const environment = props.environment || 'dev';
    const projectName = props.projectName || 'advanced-cdn';
    const enableRealTimeLogs = props.enableRealTimeLogs ?? true;
    const enableWaf = props.enableWaf ?? true;
    const priceClass = props.priceClass || cloudfront.PriceClass.PRICE_CLASS_ALL;
    
    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8);
    
    // S3 Bucket for static content
    this.contentBucket = this.createContentBucket(projectName, uniqueSuffix);
    
    // Deploy sample content to S3
    this.deploySampleContent();
    
    // CloudFront Function for request processing
    const requestFunction = this.createCloudFrontFunction(projectName, uniqueSuffix);
    
    // Lambda@Edge function for response processing
    const responseFunction = this.createLambdaEdgeFunction(projectName, uniqueSuffix);
    
    // AWS WAF Web ACL for security
    this.webAcl = enableWaf ? this.createWebAcl(projectName, uniqueSuffix) : undefined!;
    
    // CloudFront KeyValueStore for dynamic configuration
    const keyValueStore = this.createKeyValueStore(projectName, uniqueSuffix);
    
    // Origin Access Control for S3
    const originAccessControl = this.createOriginAccessControl(projectName);
    
    // Real-time logging resources
    const { kinesisStream, logGroup } = enableRealTimeLogs 
      ? this.createRealTimeLogging(projectName, uniqueSuffix) 
      : { kinesisStream: undefined, logGroup: undefined };
    
    // CloudFront Distribution
    this.distribution = this.createDistribution({
      contentBucket: this.contentBucket,
      originAccessControl,
      requestFunction,
      responseFunction,
      webAcl: this.webAcl,
      kinesisStream,
      priceClass,
      projectName,
      uniqueSuffix
    });
    
    // Configure S3 bucket policy for CloudFront access
    this.configureBucketPolicy();
    
    // CloudWatch Dashboard for monitoring
    this.createMonitoringDashboard(projectName, uniqueSuffix);
    
    // Stack outputs
    this.createOutputs();
  }
  
  /**
   * Create S3 bucket for static content with security best practices
   */
  private createContentBucket(projectName: string, uniqueSuffix: string): s3.Bucket {
    const bucket = new s3.Bucket(this, 'ContentBucket', {
      bucketName: `${projectName}-content-${uniqueSuffix}`,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      versioned: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          expiration: Duration.days(90),
          noncurrentVersionExpiration: Duration.days(30),
        }
      ],
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });
    
    // Add server access logging
    const accessLogsBucket = new s3.Bucket(this, 'AccessLogsBucket', {
      bucketName: `${projectName}-access-logs-${uniqueSuffix}`,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'DeleteLogs',
          expiration: Duration.days(30),
        }
      ],
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });
    
    bucket.addToResourcePolicy(new iam.PolicyStatement({
      sid: 'AllowCloudFrontLogging',
      effect: iam.Effect.ALLOW,
      principals: [new iam.ServicePrincipal('logging.s3.amazonaws.com')],
      actions: ['s3:PutObject'],
      resources: [`${accessLogsBucket.bucketArn}/cloudfront-logs/*`],
    }));
    
    return bucket;
  }
  
  /**
   * Deploy sample content to S3 bucket for testing
   */
  private deploySampleContent(): void {
    new s3deploy.BucketDeployment(this, 'SampleContent', {
      sources: [s3deploy.Source.data('index.html', `
        <!DOCTYPE html>
        <html>
        <head>
          <title>Advanced CDN Demo</title>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
            .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
            h1 { color: #232f3e; }
            .status { background: #e8f5e8; padding: 15px; border-radius: 4px; margin: 20px 0; }
            .feature { background: #f0f8ff; padding: 10px; margin: 10px 0; border-left: 4px solid #007dbc; }
          </style>
        </head>
        <body>
          <div class="container">
            <h1>Advanced CloudFront CDN</h1>
            <div class="status">
              <strong>Status:</strong> CDN is operational<br>
              <strong>Version:</strong> 1.0<br>
              <strong>Timestamp:</strong> ${new Date().toISOString()}
            </div>
            <h2>Features Enabled</h2>
            <div class="feature">✅ CloudFront Functions for request processing</div>
            <div class="feature">✅ Lambda@Edge for response security headers</div>
            <div class="feature">✅ AWS WAF protection</div>
            <div class="feature">✅ Real-time logging and monitoring</div>
            <div class="feature">✅ Multiple origin support</div>
            <div class="feature">✅ KeyValueStore for dynamic configuration</div>
          </div>
        </body>
        </html>
      `)],
      destinationBucket: this.contentBucket,
    });
    
    // Deploy additional test content
    new s3deploy.BucketDeployment(this, 'ApiContent', {
      sources: [
        s3deploy.Source.data('api/index.html', `
          <html><body><h1>API Documentation</h1><p>Version: 2.0</p></body></html>
        `),
        s3deploy.Source.data('api/status.json', `
          {"message": "Hello from API", "timestamp": "${new Date().toISOString()}"}
        `),
        s3deploy.Source.data('static/style.css', `
          body { font-family: Arial, sans-serif; margin: 0; padding: 20px; }
          .header { background: #232f3e; color: white; padding: 20px; }
        `)
      ],
      destinationBucket: this.contentBucket,
    });
  }
  
  /**
   * Create CloudFront Function for request processing
   */
  private createCloudFrontFunction(projectName: string, uniqueSuffix: string): cloudfront.Function {
    const functionCode = `
function handler(event) {
    var request = event.request;
    var headers = request.headers;
    
    // Add security headers
    headers['x-forwarded-proto'] = {value: 'https'};
    headers['x-request-id'] = {value: generateRequestId()};
    
    // Normalize cache key by removing tracking parameters
    var uri = request.uri;
    var querystring = request.querystring;
    
    // Remove tracking parameters to improve cache hit ratio
    delete querystring.utm_source;
    delete querystring.utm_medium;
    delete querystring.utm_campaign;
    delete querystring.fbclid;
    
    // Redirect old paths to new structure
    if (uri.startsWith('/old-api/')) {
        uri = uri.replace('/old-api/', '/api/');
        request.uri = uri;
    }
    
    return request;
}

function generateRequestId() {
    return 'req-' + Math.random().toString(36).substr(2, 9);
}
    `.trim();
    
    return new cloudfront.Function(this, 'RequestProcessingFunction', {
      functionName: `${projectName}-request-processor-${uniqueSuffix}`,
      comment: 'Request processing function for advanced CDN',
      code: cloudfront.FunctionCode.fromInline(functionCode),
      runtime: cloudfront.FunctionRuntime.JS_2_0,
    });
  }
  
  /**
   * Create Lambda@Edge function for response processing
   */
  private createLambdaEdgeFunction(projectName: string, uniqueSuffix: string): lambda.EdgeFunction {
    const functionCode = `
const handler = async (event, context) => {
    const response = event.Records[0].cf.response;
    const request = event.Records[0].cf.request;
    const headers = response.headers;
    
    // Add comprehensive security headers
    headers['strict-transport-security'] = [{
        key: 'Strict-Transport-Security',
        value: 'max-age=31536000; includeSubDomains; preload'
    }];
    
    headers['x-content-type-options'] = [{
        key: 'X-Content-Type-Options',
        value: 'nosniff'
    }];
    
    headers['x-frame-options'] = [{
        key: 'X-Frame-Options',
        value: 'SAMEORIGIN'
    }];
    
    headers['x-xss-protection'] = [{
        key: 'X-XSS-Protection',
        value: '1; mode=block'
    }];
    
    headers['referrer-policy'] = [{
        key: 'Referrer-Policy',
        value: 'strict-origin-when-cross-origin'
    }];
    
    headers['content-security-policy'] = [{
        key: 'Content-Security-Policy',
        value: "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'"
    }];
    
    // Add CORS headers for API paths
    if (request.uri.startsWith('/api/')) {
        headers['access-control-allow-origin'] = [{
            key: 'Access-Control-Allow-Origin',
            value: '*'
        }];
        headers['access-control-allow-methods'] = [{
            key: 'Access-Control-Allow-Methods',
            value: 'GET, POST, OPTIONS, PUT, DELETE'
        }];
        headers['access-control-allow-headers'] = [{
            key: 'Access-Control-Allow-Headers',
            value: 'Content-Type, Authorization, X-Requested-With'
        }];
    }
    
    // Add performance headers
    headers['x-edge-location'] = [{
        key: 'X-Edge-Location',
        value: event.Records[0].cf.config.distributionId
    }];
    
    headers['x-cache-status'] = [{
        key: 'X-Cache-Status',
        value: 'PROCESSED'
    }];
    
    return response;
};

exports.handler = handler;
    `.trim();
    
    return new lambda.EdgeFunction(this, 'ResponseProcessingFunction', {
      functionName: `${projectName}-edge-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: lambda.Code.fromInline(functionCode),
      timeout: Duration.seconds(5),
      memorySize: 128,
      description: 'Lambda@Edge function for security header injection and response processing',
    });
  }
  
  /**
   * Create AWS WAF Web ACL for security protection
   */
  private createWebAcl(projectName: string, uniqueSuffix: string): wafv2.CfnWebACL {
    return new wafv2.CfnWebACL(this, 'WebAcl', {
      name: `${projectName}-security-${uniqueSuffix}`,
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
            metricName: 'KnownBadInputsRuleSetMetric',
          },
        },
        {
          name: 'RateLimitRule',
          priority: 3,
          action: { block: {} },
          statement: {
            rateBasedStatement: {
              limit: 2000,
              aggregateKeyType: 'IP',
            },
          },
          visibilityConfig: {
            sampledRequestsEnabled: true,
            cloudWatchMetricsEnabled: true,
            metricName: 'RateLimitRuleMetric',
          },
        },
      ],
      visibilityConfig: {
        sampledRequestsEnabled: true,
        cloudWatchMetricsEnabled: true,
        metricName: `${projectName}-waf-${uniqueSuffix}`,
      },
      description: 'Web ACL for advanced CloudFront CDN protection',
    });
  }
  
  /**
   * Create CloudFront KeyValueStore for dynamic configuration
   */
  private createKeyValueStore(projectName: string, uniqueSuffix: string): cloudfront.KeyValueStore {
    return new cloudfront.KeyValueStore(this, 'ConfigStore', {
      keyValueStoreName: `${projectName}-config-${uniqueSuffix}`,
      comment: 'Dynamic configuration store for CDN',
      source: cloudfront.ImportSource.fromInline({
        'maintenance_mode': 'false',
        'feature_flags': JSON.stringify({ new_ui: true, beta_features: false }),
        'redirect_rules': JSON.stringify({ old_domain: 'new_domain.com', legacy_path: '/new-path' }),
      }),
    });
  }
  
  /**
   * Create Origin Access Control for S3 security
   */
  private createOriginAccessControl(projectName: string): cloudfront.S3OriginAccessControl {
    return new cloudfront.S3OriginAccessControl(this, 'OriginAccessControl', {
      description: `Origin Access Control for ${projectName} S3 bucket`,
      originAccessControlName: `${projectName}-oac`,
      signing: cloudfront.Signing.SIGV4_ALWAYS,
    });
  }
  
  /**
   * Create real-time logging resources
   */
  private createRealTimeLogging(projectName: string, uniqueSuffix: string) {
    // CloudWatch log group for real-time logs
    const logGroup = new logs.LogGroup(this, 'RealTimeLogGroup', {
      logGroupName: `/aws/cloudfront/realtime-logs/${projectName}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: RemovalPolicy.DESTROY,
    });
    
    // Kinesis Data Stream for real-time logs
    const kinesisStream = new kinesis.Stream(this, 'RealTimeLogStream', {
      streamName: `cloudfront-realtime-logs-${uniqueSuffix}`,
      shardCount: 1,
      retentionPeriod: Duration.days(1),
    });
    
    // IAM role for CloudFront real-time logs
    const realtimeLogsRole = new iam.Role(this, 'RealTimeLogsRole', {
      roleName: `CloudFront-RealTimeLogs-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('cloudfront.amazonaws.com'),
      inlinePolicies: {
        KinesisAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['kinesis:PutRecords', 'kinesis:PutRecord'],
              resources: [kinesisStream.streamArn],
            }),
          ],
        }),
      },
    });
    
    return { kinesisStream, logGroup, realtimeLogsRole };
  }
  
  /**
   * Create CloudFront Distribution with advanced configuration
   */
  private createDistribution(config: {
    contentBucket: s3.Bucket;
    originAccessControl: cloudfront.S3OriginAccessControl;
    requestFunction: cloudfront.Function;
    responseFunction: lambda.EdgeFunction;
    webAcl?: wafv2.CfnWebACL;
    kinesisStream?: kinesis.Stream;
    priceClass: cloudfront.PriceClass;
    projectName: string;
    uniqueSuffix: string;
  }): cloudfront.Distribution {
    
    // Define origins
    const s3Origin = new origins.S3Origin(config.contentBucket, {
      originAccessControl: config.originAccessControl,
    });
    
    const customOrigin = new origins.HttpOrigin('httpbin.org', {
      protocolPolicy: cloudfront.OriginProtocolPolicy.HTTPS_ONLY,
      httpsPort: 443,
      originSslProtocols: [cloudfront.OriginSslPolicy.TLS_V1_2],
    });
    
    // Create distribution
    const distribution = new cloudfront.Distribution(this, 'Distribution', {
      comment: 'Advanced CDN with multiple origins and edge functions',
      defaultBehavior: {
        origin: s3Origin,
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
        compress: true,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        originRequestPolicy: cloudfront.OriginRequestPolicy.CORS_S3_ORIGIN,
        functionAssociations: [
          {
            function: config.requestFunction,
            eventType: cloudfront.FunctionEventType.VIEWER_REQUEST,
          },
        ],
        edgeLambdas: [
          {
            functionVersion: config.responseFunction.currentVersion,
            eventType: cloudfront.LambdaEdgeEventType.ORIGIN_RESPONSE,
          },
        ],
      },
      additionalBehaviors: {
        '/api/*': {
          origin: customOrigin,
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
          cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
          compress: true,
          cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
          originRequestPolicy: cloudfront.OriginRequestPolicy.CORS_S3_ORIGIN,
          edgeLambdas: [
            {
              functionVersion: config.responseFunction.currentVersion,
              eventType: cloudfront.LambdaEdgeEventType.ORIGIN_RESPONSE,
            },
          ],
        },
        '/static/*': {
          origin: s3Origin,
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
          cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
          compress: true,
          cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED_FOR_UNCOMPRESSED_OBJECTS,
        },
      },
      errorResponses: [
        {
          httpStatus: 404,
          responseHttpStatus: 404,
          responsePagePath: '/404.html',
          ttl: Duration.minutes(5),
        },
        {
          httpStatus: 500,
          responseHttpStatus: 500,
          responsePagePath: '/500.html',
          ttl: Duration.seconds(0),
        },
      ],
      priceClass: config.priceClass,
      enableIpv6: true,
      httpVersion: cloudfront.HttpVersion.HTTP2_AND_3,
      defaultRootObject: 'index.html',
      webAclId: config.webAcl?.attrArn,
      enableLogging: true,
      logBucket: config.contentBucket,
      logFilePrefix: 'cloudfront-logs/',
      logIncludesCookies: false,
    });
    
    return distribution;
  }
  
  /**
   * Configure S3 bucket policy for CloudFront access
   */
  private configureBucketPolicy(): void {
    this.contentBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AllowCloudFrontServicePrincipal',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('cloudfront.amazonaws.com')],
        actions: ['s3:GetObject'],
        resources: [`${this.contentBucket.bucketArn}/*`],
        conditions: {
          StringEquals: {
            'AWS:SourceArn': `arn:aws:cloudfront::${this.account}:distribution/${this.distribution.distributionId}`,
          },
        },
      })
    );
  }
  
  /**
   * Create CloudWatch Dashboard for monitoring
   */
  private createMonitoringDashboard(projectName: string, uniqueSuffix: string): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'MonitoringDashboard', {
      dashboardName: `CloudFront-Advanced-CDN-${uniqueSuffix}`,
    });
    
    // CloudFront metrics
    const requestsMetric = new cloudwatch.Metric({
      namespace: 'AWS/CloudFront',
      metricName: 'Requests',
      dimensionsMap: {
        DistributionId: this.distribution.distributionId,
      },
      statistic: 'Sum',
      period: Duration.minutes(5),
    });
    
    const errorRateMetric = new cloudwatch.Metric({
      namespace: 'AWS/CloudFront',
      metricName: '4xxErrorRate',
      dimensionsMap: {
        DistributionId: this.distribution.distributionId,
      },
      statistic: 'Average',
      period: Duration.minutes(5),
    });
    
    const cacheHitRateMetric = new cloudwatch.Metric({
      namespace: 'AWS/CloudFront',
      metricName: 'CacheHitRate',
      dimensionsMap: {
        DistributionId: this.distribution.distributionId,
      },
      statistic: 'Average',
      period: Duration.minutes(5),
    });
    
    // Add widgets to dashboard
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'CloudFront Traffic',
        left: [requestsMetric],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'Error Rates',
        left: [errorRateMetric],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'Cache Hit Rate',
        left: [cacheHitRateMetric],
        width: 12,
        height: 6,
      })
    );
    
    if (this.webAcl) {
      const wafAllowedMetric = new cloudwatch.Metric({
        namespace: 'AWS/WAFV2',
        metricName: 'AllowedRequests',
        dimensionsMap: {
          WebACL: this.webAcl.name!,
          Rule: 'ALL',
          Region: 'CloudFront',
        },
        statistic: 'Sum',
        period: Duration.minutes(5),
      });
      
      dashboard.addWidgets(
        new cloudwatch.GraphWidget({
          title: 'WAF Activity',
          left: [wafAllowedMetric],
          width: 12,
          height: 6,
        })
      );
    }
    
    return dashboard;
  }
  
  /**
   * Create stack outputs for important resources
   */
  private createOutputs(): void {
    new CfnOutput(this, 'DistributionDomainName', {
      value: this.distribution.distributionDomainName,
      description: 'CloudFront distribution domain name',
      exportName: `${this.stackName}-DistributionDomainName`,
    });
    
    new CfnOutput(this, 'DistributionId', {
      value: this.distribution.distributionId,
      description: 'CloudFront distribution ID',
      exportName: `${this.stackName}-DistributionId`,
    });
    
    new CfnOutput(this, 'ContentBucketName', {
      value: this.contentBucket.bucketName,
      description: 'S3 bucket name for content storage',
      exportName: `${this.stackName}-ContentBucketName`,
    });
    
    new CfnOutput(this, 'DistributionUrl', {
      value: `https://${this.distribution.distributionDomainName}`,
      description: 'CloudFront distribution URL',
      exportName: `${this.stackName}-DistributionUrl`,
    });
    
    if (this.webAcl) {
      new CfnOutput(this, 'WebAclArn', {
        value: this.webAcl.attrArn,
        description: 'AWS WAF Web ACL ARN',
        exportName: `${this.stackName}-WebAclArn`,
      });
    }
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev';
const projectName = app.node.tryGetContext('projectName') || process.env.PROJECT_NAME || 'advanced-cdn';
const enableRealTimeLogs = app.node.tryGetContext('enableRealTimeLogs') !== 'false';
const enableWaf = app.node.tryGetContext('enableWaf') !== 'false';

// Determine price class based on environment
let priceClass: cloudfront.PriceClass;
switch (environment) {
  case 'prod':
    priceClass = cloudfront.PriceClass.PRICE_CLASS_ALL;
    break;
  case 'staging':
    priceClass = cloudfront.PriceClass.PRICE_CLASS_100;
    break;
  default:
    priceClass = cloudfront.PriceClass.PRICE_CLASS_100;
}

// Create the stack
new ContentDeliveryNetworkStack(app, `ContentDeliveryNetwork-${environment}`, {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1', // CloudFront requires us-east-1 for Lambda@Edge
  },
  environment,
  projectName,
  enableRealTimeLogs,
  enableWaf,
  priceClass,
  description: `Advanced CloudFront CDN infrastructure for ${environment} environment`,
  tags: {
    Environment: environment,
    Project: projectName,
    ManagedBy: 'CDK',
    Purpose: 'ContentDeliveryNetwork',
  },
});

app.synth();