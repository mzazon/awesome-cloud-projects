#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import {
  Stack,
  StackProps,
  Duration,
  RemovalPolicy,
  CfnOutput,
  aws_s3 as s3,
  aws_cloudfront as cloudfront,
  aws_cloudfront_origins as origins,
  aws_elasticache as elasticache,
  aws_lambda as lambda,
  aws_apigateway as apigateway,
  aws_iam as iam,
  aws_ec2 as ec2,
  aws_logs as logs,
  aws_cloudwatch as cloudwatch,
  BundlingOptions
} from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as path from 'path';

/**
 * Properties for the ContentCachingStack
 */
interface ContentCachingStackProps extends StackProps {
  /** Environment name (dev, staging, prod) */
  readonly environment?: string;
  /** Enable detailed monitoring */
  readonly enableDetailedMonitoring?: boolean;
  /** ElastiCache node type */
  readonly cacheNodeType?: string;
  /** CloudFront price class */
  readonly priceClass?: cloudfront.PriceClass;
}

/**
 * CDK Stack implementing multi-tier caching strategy with CloudFront and ElastiCache
 * 
 * This stack demonstrates:
 * - CloudFront distribution with multiple origins (S3 and API Gateway)
 * - ElastiCache Redis cluster for application-level caching
 * - Lambda function implementing cache-aside pattern
 * - API Gateway for RESTful API endpoints
 * - Comprehensive monitoring and alerting
 */
export class ContentCachingStack extends Stack {
  public readonly distribution: cloudfront.Distribution;
  public readonly cacheCluster: elasticache.CfnCacheCluster;
  public readonly apiEndpoint: string;

  constructor(scope: Construct, id: string, props: ContentCachingStackProps = {}) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.addr.slice(-6).toLowerCase();
    const environment = props.environment || 'dev';

    // VPC for ElastiCache and Lambda
    const vpc = this.createVpc();

    // S3 bucket for static content
    const contentBucket = this.createContentBucket(uniqueSuffix);

    // ElastiCache Redis cluster
    const { cacheCluster, cacheEndpoint } = this.createElastiCacheCluster(
      vpc,
      uniqueSuffix,
      props.cacheNodeType || 'cache.t3.micro'
    );

    // Lambda function for API with caching logic
    const cacheFunction = this.createCachingLambdaFunction(
      vpc,
      cacheEndpoint,
      uniqueSuffix
    );

    // API Gateway
    const api = this.createApiGateway(cacheFunction, uniqueSuffix);

    // CloudFront distribution with multiple origins
    const distribution = this.createCloudFrontDistribution(
      contentBucket,
      api,
      props.priceClass || cloudfront.PriceClass.PRICE_CLASS_100
    );

    // CloudWatch monitoring and alarms
    this.createMonitoring(distribution, cacheCluster, props.enableDetailedMonitoring);

    // Store references
    this.distribution = distribution;
    this.cacheCluster = cacheCluster;
    this.apiEndpoint = api.url;

    // Outputs
    this.createOutputs(distribution, api, contentBucket, cacheEndpoint);
  }

  /**
   * Creates VPC for ElastiCache and Lambda
   */
  private createVpc(): ec2.Vpc {
    return new ec2.Vpc(this, 'CacheVpc', {
      maxAzs: 2,
      natGateways: 1,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });
  }

  /**
   * Creates S3 bucket for static content with proper security settings
   */
  private createContentBucket(uniqueSuffix: string): s3.Bucket {
    const bucket = new s3.Bucket(this, 'ContentBucket', {
      bucketName: `cache-demo-content-${uniqueSuffix}`,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      versioned: false,
      encryption: s3.BucketEncryption.S3_MANAGED,
    });

    // Upload sample content
    new s3.BucketDeployment(this, 'ContentDeployment', {
      sources: [s3.Source.data('index.html', this.getSampleHtmlContent())],
      destinationBucket: bucket,
      retainOnDelete: false,
    });

    return bucket;
  }

  /**
   * Creates ElastiCache Redis cluster with proper subnet group and security
   */
  private createElastiCacheCluster(
    vpc: ec2.Vpc,
    uniqueSuffix: string,
    nodeType: string
  ): { cacheCluster: elasticache.CfnCacheCluster; cacheEndpoint: string } {
    // Security group for ElastiCache
    const cacheSecurityGroup = new ec2.SecurityGroup(this, 'CacheSecurityGroup', {
      vpc,
      description: 'Security group for ElastiCache Redis cluster',
      allowAllOutbound: false,
    });

    // Allow Redis port from Lambda security group
    cacheSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(6379),
      'Allow Redis access from VPC'
    );

    // Subnet group for ElastiCache
    const subnetGroup = new elasticache.CfnSubnetGroup(this, 'CacheSubnetGroup', {
      description: 'Subnet group for ElastiCache cluster',
      subnetIds: vpc.privateSubnets.map(subnet => subnet.subnetId),
      cacheSubnetGroupName: `cache-subnet-group-${uniqueSuffix}`,
    });

    // ElastiCache Redis cluster
    const cacheCluster = new elasticache.CfnCacheCluster(this, 'CacheCluster', {
      cacheNodeType: nodeType,
      engine: 'redis',
      numCacheNodes: 1,
      cacheSubnetGroupName: subnetGroup.cacheSubnetGroupName,
      vpcSecurityGroupIds: [cacheSecurityGroup.securityGroupId],
      port: 6379,
      clusterName: `demo-cache-${uniqueSuffix}`,
      azMode: 'single-az',
      engineVersion: '7.0',
    });

    cacheCluster.addDependency(subnetGroup);

    // Construct endpoint (will be available after deployment)
    const cacheEndpoint = `${cacheCluster.attrRedisEndpointAddress}:${cacheCluster.attrRedisEndpointPort}`;

    return { cacheCluster, cacheEndpoint };
  }

  /**
   * Creates Lambda function with caching logic and VPC configuration
   */
  private createCachingLambdaFunction(
    vpc: ec2.Vpc,
    cacheEndpoint: string,
    uniqueSuffix: string
  ): lambda.Function {
    // Security group for Lambda
    const lambdaSecurityGroup = new ec2.SecurityGroup(this, 'LambdaSecurityGroup', {
      vpc,
      description: 'Security group for Lambda function',
      allowAllOutbound: true,
    });

    // IAM role for Lambda
    const lambdaRole = new iam.Role(this, 'CacheLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaVPCAccessExecutionRole'),
      ],
    });

    // Lambda function
    const cacheFunction = new lambda.Function(this, 'CacheFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(this.getLambdaCode()),
      environment: {
        REDIS_ENDPOINT: cacheEndpoint.split(':')[0], // Extract host only
        REDIS_PORT: '6379',
      },
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      securityGroups: [lambdaSecurityGroup],
      timeout: Duration.seconds(30),
      memorySize: 256,
      role: lambdaRole,
      functionName: `cache-demo-function-${uniqueSuffix}`,
      description: 'Lambda function implementing cache-aside pattern with ElastiCache',
    });

    // Add Redis layer for dependencies
    const redisLayer = new lambda.LayerVersion(this, 'RedisLayer', {
      code: lambda.Code.fromInline(`
# This is a placeholder for the Redis layer
# In a real deployment, you would create a proper layer with redis-py
import json
def lambda_handler(event, context):
    return {'statusCode': 200, 'body': json.dumps('Redis layer placeholder')}
      `),
      compatibleRuntimes: [lambda.Runtime.PYTHON_3_9],
      description: 'Redis library for Python',
    });

    cacheFunction.addLayers(redisLayer);

    return cacheFunction;
  }

  /**
   * Creates API Gateway with Lambda integration
   */
  private createApiGateway(
    cacheFunction: lambda.Function,
    uniqueSuffix: string
  ): apigateway.RestApi {
    const api = new apigateway.RestApi(this, 'CacheApi', {
      restApiName: `cache-demo-api-${uniqueSuffix}`,
      description: 'API Gateway for caching demonstration',
      deployOptions: {
        stageName: 'prod',
        throttlingBurstLimit: 1000,
        throttlingRateLimit: 500,
        cachingEnabled: false, // We'll use CloudFront for caching
        dataTraceEnabled: true,
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
      },
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key'],
      },
      binaryMediaTypes: ['*/*'],
    });

    // Lambda integration
    const lambdaIntegration = new apigateway.LambdaIntegration(cacheFunction, {
      requestTemplates: { 'application/json': '{ "statusCode": "200" }' },
      proxy: true,
    });

    // API resource and method
    const apiResource = api.root.addResource('api');
    const dataResource = apiResource.addResource('data');
    dataResource.addMethod('GET', lambdaIntegration, {
      apiKeyRequired: false,
      authorizationType: apigateway.AuthorizationType.NONE,
    });

    return api;
  }

  /**
   * Creates CloudFront distribution with multiple origins and cache behaviors
   */
  private createCloudFrontDistribution(
    contentBucket: s3.Bucket,
    api: apigateway.RestApi,
    priceClass: cloudfront.PriceClass
  ): cloudfront.Distribution {
    // Origin Access Control for S3
    const oac = new cloudfront.S3OriginAccessControl(this, 'S3OAC', {
      description: 'OAC for S3 bucket access',
    });

    // S3 Origin
    const s3Origin = origins.S3BucketOrigin.withOriginAccessControl(contentBucket, {
      originAccessControl: oac,
    });

    // API Gateway Origin
    const apiOrigin = new origins.RestApiOrigin(api, {
      originPath: '/prod',
    });

    // Cache policies
    const apiCachePolicy = new cloudfront.CachePolicy(this, 'ApiCachePolicy', {
      cachePolicyName: `api-cache-policy-${this.node.addr.slice(-6)}`,
      comment: 'Cache policy for API responses',
      defaultTtl: Duration.seconds(60),
      maxTtl: Duration.seconds(300),
      minTtl: Duration.seconds(0),
      enableAcceptEncodingGzip: true,
      enableAcceptEncodingBrotli: true,
      queryStringBehavior: cloudfront.CacheQueryStringBehavior.all(),
      headerBehavior: cloudfront.CacheHeaderBehavior.allowList('Authorization'),
      cookieBehavior: cloudfront.CacheCookieBehavior.none(),
    });

    // CloudFront distribution
    const distribution = new cloudfront.Distribution(this, 'CacheDistribution', {
      comment: 'Multi-tier caching demonstration',
      defaultBehavior: {
        origin: s3Origin,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD_OPTIONS,
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        compress: true,
      },
      additionalBehaviors: {
        '/api/*': {
          origin: apiOrigin,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          cachePolicy: apiCachePolicy,
          compress: true,
        },
      },
      priceClass,
      enableIpv6: true,
      minimumProtocolVersion: cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
      errorResponses: [
        {
          httpStatus: 404,
          responseHttpStatus: 200,
          responsePagePath: '/index.html',
          ttl: Duration.seconds(300),
        },
      ],
      enableLogging: true,
      logBucket: new s3.Bucket(this, 'CloudFrontLogsBucket', {
        removalPolicy: RemovalPolicy.DESTROY,
        autoDeleteObjects: true,
        blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      }),
      logFilePrefix: 'cloudfront-logs/',
    });

    return distribution;
  }

  /**
   * Creates CloudWatch monitoring and alarms
   */
  private createMonitoring(
    distribution: cloudfront.Distribution,
    cacheCluster: elasticache.CfnCacheCluster,
    enableDetailedMonitoring?: boolean
  ): void {
    // CloudWatch log group
    new logs.LogGroup(this, 'CacheLogGroup', {
      logGroupName: '/aws/cloudfront/cache-demo',
      removalPolicy: RemovalPolicy.DESTROY,
      retention: logs.RetentionDays.ONE_WEEK,
    });

    // CloudFront cache hit ratio alarm
    new cloudwatch.Alarm(this, 'CacheHitRatioAlarm', {
      alarmName: 'CloudFront-CacheHitRatio-Low',
      alarmDescription: 'Alert when CloudFront cache hit ratio is low',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/CloudFront',
        metricName: 'CacheHitRate',
        dimensionsMap: {
          DistributionId: distribution.distributionId,
        },
        statistic: 'Average',
        period: Duration.minutes(5),
      }),
      threshold: 80,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    if (enableDetailedMonitoring) {
      // ElastiCache CPU utilization alarm
      new cloudwatch.Alarm(this, 'CacheCpuAlarm', {
        alarmName: 'ElastiCache-CPU-High',
        alarmDescription: 'Alert when ElastiCache CPU utilization is high',
        metric: new cloudwatch.Metric({
          namespace: 'AWS/ElastiCache',
          metricName: 'CPUUtilization',
          dimensionsMap: {
            CacheClusterId: cacheCluster.ref,
          },
          statistic: 'Average',
          period: Duration.minutes(5),
        }),
        threshold: 75,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        evaluationPeriods: 2,
      });

      // ElastiCache memory utilization alarm
      new cloudwatch.Alarm(this, 'CacheMemoryAlarm', {
        alarmName: 'ElastiCache-Memory-High',
        alarmDescription: 'Alert when ElastiCache memory utilization is high',
        metric: new cloudwatch.Metric({
          namespace: 'AWS/ElastiCache',
          metricName: 'DatabaseMemoryUsagePercentage',
          dimensionsMap: {
            CacheClusterId: cacheCluster.ref,
          },
          statistic: 'Average',
          period: Duration.minutes(5),
        }),
        threshold: 80,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        evaluationPeriods: 2,
      });
    }
  }

  /**
   * Creates stack outputs
   */
  private createOutputs(
    distribution: cloudfront.Distribution,
    api: apigateway.RestApi,
    contentBucket: s3.Bucket,
    cacheEndpoint: string
  ): void {
    new CfnOutput(this, 'CloudFrontDomainName', {
      value: distribution.distributionDomainName,
      description: 'CloudFront distribution domain name',
      exportName: `${this.stackName}-CloudFrontDomain`,
    });

    new CfnOutput(this, 'CloudFrontDistributionId', {
      value: distribution.distributionId,
      description: 'CloudFront distribution ID',
      exportName: `${this.stackName}-DistributionId`,
    });

    new CfnOutput(this, 'ApiGatewayUrl', {
      value: api.url,
      description: 'API Gateway endpoint URL',
      exportName: `${this.stackName}-ApiUrl`,
    });

    new CfnOutput(this, 'S3BucketName', {
      value: contentBucket.bucketName,
      description: 'S3 bucket name for static content',
      exportName: `${this.stackName}-BucketName`,
    });

    new CfnOutput(this, 'ElastiCacheEndpoint', {
      value: cacheEndpoint,
      description: 'ElastiCache Redis endpoint',
      exportName: `${this.stackName}-CacheEndpoint`,
    });

    new CfnOutput(this, 'WebsiteUrl', {
      value: `https://${distribution.distributionDomainName}`,
      description: 'Complete website URL',
      exportName: `${this.stackName}-WebsiteUrl`,
    });
  }

  /**
   * Returns sample HTML content for testing
   */
  private getSampleHtmlContent(): string {
    return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Multi-Tier Caching Demo</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 40px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .api-result {
            background: #f8f9fa;
            border: 1px solid #dee2e6;
            padding: 20px;
            margin: 20px 0;
            border-radius: 5px;
            font-family: monospace;
        }
        .loading {
            color: #6c757d;
        }
        .cache-hit {
            color: #28a745;
        }
        .cache-miss {
            color: #dc3545;
        }
        button {
            background: #007bff;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            margin: 10px 5px;
        }
        button:hover {
            background: #0056b3;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Multi-Tier Caching Demo</h1>
        <p>This page demonstrates CloudFront edge caching combined with ElastiCache application-level caching.</p>
        
        <h2>Caching Architecture</h2>
        <ul>
            <li><strong>CloudFront:</strong> Caches static content and API responses at edge locations</li>
            <li><strong>ElastiCache:</strong> Provides in-memory caching for database queries</li>
            <li><strong>Lambda:</strong> Implements cache-aside pattern for data retrieval</li>
        </ul>

        <h2>Live API Test</h2>
        <button onclick="fetchData()">Fetch Data</button>
        <button onclick="clearResults()">Clear Results</button>
        
        <div id="api-result" class="api-result loading">
            Click "Fetch Data" to test the caching system...
        </div>

        <h2>Performance Benefits</h2>
        <ul>
            <li>Reduced latency through global edge caching</li>
            <li>Lower database load with in-memory caching</li>
            <li>Improved scalability and cost efficiency</li>
            <li>Enhanced user experience worldwide</li>
        </ul>
    </div>

    <script>
        let requestCount = 0;

        async function fetchData() {
            requestCount++;
            const resultDiv = document.getElementById('api-result');
            resultDiv.innerHTML = \`<div class="loading">Request #\${requestCount}: Loading...</div>\`;
            
            try {
                const startTime = performance.now();
                const response = await fetch('/api/data');
                const data = await response.json();
                const endTime = performance.now();
                const duration = Math.round(endTime - startTime);
                
                const cacheStatus = data.cache_hit ? 'cache-hit' : 'cache-miss';
                const cacheLabel = data.cache_hit ? 'Cache HIT' : 'Cache MISS';
                
                resultDiv.innerHTML = \`
                    <div><strong>Request #\${requestCount} (\${duration}ms)</strong></div>
                    <div class="\${cacheStatus}"><strong>\${cacheLabel}</strong> - Source: \${data.source}</div>
                    <div>Timestamp: \${data.timestamp}</div>
                    <div>Message: \${data.message}</div>
                    <div>Query Time: \${data.query_time}</div>
                    <hr>
                    <div><em>Full Response:</em></div>
                    <pre>\${JSON.stringify(data, null, 2)}</pre>
                \`;
            } catch (error) {
                resultDiv.innerHTML = \`
                    <div class="cache-miss"><strong>Error:</strong> \${error.message}</div>
                    <div><em>This may be expected if the infrastructure is still deploying.</em></div>
                \`;
            }
        }

        function clearResults() {
            document.getElementById('api-result').innerHTML = 
                '<div class="loading">Click "Fetch Data" to test the caching system...</div>';
            requestCount = 0;
        }

        // Auto-test on page load after a short delay
        setTimeout(() => {
            fetchData();
        }, 2000);
    </script>
</body>
</html>`;
  }

  /**
   * Returns Lambda function code for cache implementation
   */
  private getLambdaCode(): string {
    return `import json
import os
import time
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Mock Redis implementation for demonstration
# In production, you would install redis-py in a Lambda layer
class MockRedis:
    def __init__(self):
        self.data = {}
        self.expiry = {}
    
    def get(self, key):
        if key in self.expiry and time.time() > self.expiry[key]:
            del self.data[key]
            del self.expiry[key]
            return None
        return self.data.get(key)
    
    def setex(self, key, ttl, value):
        self.data[key] = value
        self.expiry[key] = time.time() + ttl

# Global cache instance (persists across Lambda warm starts)
cache = MockRedis()

def lambda_handler(event, context):
    """
    Lambda function implementing cache-aside pattern with ElastiCache
    """
    try:
        # Extract request information
        http_method = event.get('httpMethod', 'GET')
        path = event.get('path', '')
        
        logger.info(f"Processing {http_method} request to {path}")
        
        # Handle CORS preflight
        if http_method == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
                    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
                    'Access-Control-Max-Age': '86400'
                },
                'body': ''
            }
        
        # Cache key for demonstration
        cache_key = "demo_data_v1"
        
        # Try to get data from cache
        start_time = time.time()
        cached_data = cache.get(cache_key)
        
        if cached_data:
            # Cache hit - return cached data
            logger.info("Cache HIT - returning cached data")
            data = json.loads(cached_data)
            data['cache_hit'] = True
            data['source'] = 'ElastiCache (Mock)'
            data['retrieval_time'] = f"{(time.time() - start_time) * 1000:.1f}ms"
        else:
            # Cache miss - simulate database query
            logger.info("Cache MISS - querying database")
            time.sleep(0.1)  # Simulate database query latency
            
            # Generate fresh data
            data = {
                'timestamp': datetime.now().isoformat(),
                'message': 'Hello from Lambda with caching!',
                'request_id': context.aws_request_id,
                'cache_hit': False,
                'source': 'Database (Simulated)',
                'query_time': '100ms',
                'retrieval_time': f"{(time.time() - start_time) * 1000:.1f}ms",
                'lambda_version': context.function_version,
                'remaining_time': context.get_remaining_time_in_millis()
            }
            
            # Store in cache for 5 minutes (300 seconds)
            cache.setex(cache_key, 300, json.dumps(data))
            logger.info("Data cached for 300 seconds")
        
        # Add request metadata
        data['request_count'] = data.get('request_count', 0) + 1
        data['cache_key'] = cache_key
        
        # Return response with appropriate cache headers
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Cache-Control': 'public, max-age=60, s-maxage=60',  # CloudFront cache for 60 seconds
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
                'X-Cache-Status': 'HIT' if data['cache_hit'] else 'MISS',
                'X-Response-Time': data['retrieval_time']
            },
            'body': json.dumps(data, indent=2)
        }
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        
        # Return error response
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': str(e),
                'message': 'Internal server error',
                'timestamp': datetime.now().isoformat(),
                'request_id': context.aws_request_id if context else 'unknown'
            })
        }`;
  }
}

/**
 * CDK App
 */
const app = new cdk.App();

// Get context values
const environment = app.node.tryGetContext('environment') || 'dev';
const enableDetailedMonitoring = app.node.tryGetContext('enableDetailedMonitoring') === 'true';
const cacheNodeType = app.node.tryGetContext('cacheNodeType') || 'cache.t3.micro';

// Determine price class based on environment
let priceClass: cloudfront.PriceClass;
switch (environment) {
  case 'prod':
    priceClass = cloudfront.PriceClass.PRICE_CLASS_ALL;
    break;
  case 'staging':
    priceClass = cloudfront.PriceClass.PRICE_CLASS_200;
    break;
  default:
    priceClass = cloudfront.PriceClass.PRICE_CLASS_100;
}

// Create stack
new ContentCachingStack(app, 'ContentCachingStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  environment,
  enableDetailedMonitoring,
  cacheNodeType,
  priceClass,
  description: 'Multi-tier caching strategy with CloudFront and ElastiCache',
  tags: {
    Project: 'ContentCaching',
    Environment: environment,
    Owner: 'CDK',
    CostCenter: 'Engineering',
  },
});

app.synth();