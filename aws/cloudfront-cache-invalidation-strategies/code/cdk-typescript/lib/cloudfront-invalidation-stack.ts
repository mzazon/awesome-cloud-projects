import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as lambdaEventSources from 'aws-cdk-lib/aws-lambda-event-sources';
import { Construct } from 'constructs';

/**
 * Configuration interface for the CloudFront Invalidation Stack
 */
export interface CloudFrontInvalidationStackProps extends cdk.StackProps {
  projectName: string;
  enableMonitoring?: boolean;
  enableBatchProcessing?: boolean;
  enableCostOptimization?: boolean;
  lambdaTimeout?: number;
  lambdaMemory?: number;
  batchSize?: number;
  batchWindow?: number;
  priceClass?: string;
  enableCompression?: boolean;
  enableIPv6?: boolean;
  enableOriginAccessControl?: boolean;
  enforceHTTPS?: boolean;
  retentionPeriod?: number;
  dashboardName?: string;
}

/**
 * CloudFront Cache Invalidation Stack
 * 
 * This stack implements an intelligent CloudFront cache invalidation system that:
 * - Automatically detects content changes through S3 events and deployment notifications
 * - Applies selective invalidation patterns based on content types and dependencies
 * - Optimizes costs through intelligent batch processing and path optimization
 * - Provides comprehensive monitoring and audit logging
 * - Maintains cache hit rates above 85% while minimizing invalidation costs
 * 
 * The architecture uses EventBridge for event-driven automation, Lambda functions
 * for intelligent invalidation logic, and CloudWatch for performance tracking.
 */
export class CloudFrontInvalidationStack extends cdk.Stack {
  public readonly originBucket: s3.Bucket;
  public readonly distribution: cloudfront.Distribution;
  public readonly invalidationFunction: lambda.Function;
  public readonly eventBus: events.EventBus;
  public readonly invalidationQueue: sqs.Queue;
  public readonly invalidationTable: dynamodb.Table;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: CloudFrontInvalidationStackProps) {
    super(scope, id, props);

    // Generate unique resource names
    const resourceName = (name: string) => `${props.projectName}-${name}`;

    // Create S3 bucket for origin content
    this.originBucket = new s3.Bucket(this, 'OriginBucket', {
      bucketName: resourceName('origin-content'),
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
      eventBridgeEnabled: true, // Enable EventBridge notifications
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo purposes
    });

    // Create DynamoDB table for invalidation audit logging
    this.invalidationTable = new dynamodb.Table(this, 'InvalidationTable', {
      tableName: resourceName('invalidation-log'),
      partitionKey: {
        name: 'InvalidationId',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'Timestamp',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      timeToLiveAttribute: 'TTL',
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    // Create SQS queues for batch processing
    const deadLetterQueue = new sqs.Queue(this, 'InvalidationDLQ', {
      queueName: resourceName('invalidation-dlq'),
      encryption: sqs.QueueEncryption.SQS_MANAGED,
      retentionPeriod: cdk.Duration.days(14),
    });

    this.invalidationQueue = new sqs.Queue(this, 'InvalidationQueue', {
      queueName: resourceName('invalidation-queue'),
      encryption: sqs.QueueEncryption.SQS_MANAGED,
      visibilityTimeout: cdk.Duration.seconds(props.lambdaTimeout || 300),
      retentionPeriod: cdk.Duration.days(14),
      receiveMessageWaitTime: cdk.Duration.seconds(20),
      deadLetterQueue: {
        queue: deadLetterQueue,
        maxReceiveCount: 3,
      },
    });

    // Create EventBridge custom bus for invalidation events
    this.eventBus = new events.EventBus(this, 'InvalidationEventBus', {
      eventBusName: resourceName('invalidation-events'),
    });

    // Create Lambda function for intelligent invalidation processing
    this.invalidationFunction = new lambda.Function(this, 'InvalidationFunction', {
      functionName: resourceName('invalidation-processor'),
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: lambda.Code.fromInline(this.getLambdaCode()),
      timeout: cdk.Duration.seconds(props.lambdaTimeout || 300),
      memorySize: props.lambdaMemory || 256,
      environment: {
        DDB_TABLE_NAME: this.invalidationTable.tableName,
        QUEUE_URL: this.invalidationQueue.queueUrl,
        DISTRIBUTION_ID: '', // Will be set after distribution creation
        BATCH_SIZE: (props.batchSize || 10).toString(),
        ENABLE_COST_OPTIMIZATION: (props.enableCostOptimization !== false).toString(),
      },
      logRetention: logs.RetentionDays.ONE_MONTH,
      description: 'Intelligent CloudFront cache invalidation processor with cost optimization and batch processing capabilities',
    });

    // Create CloudFront Origin Access Control (OAC)
    const oac = new cloudfront.OriginAccessControl(this, 'OriginAccessControl', {
      description: 'Origin Access Control for CloudFront invalidation demo',
      originAccessControlOriginType: cloudfront.OriginAccessControlOriginType.S3,
      signingBehavior: cloudfront.SigningBehavior.ALWAYS,
      signingProtocol: cloudfront.SigningProtocol.SIGV4,
    });

    // Create CloudFront distribution with optimized cache behaviors
    this.distribution = new cloudfront.Distribution(this, 'Distribution', {
      comment: 'CloudFront distribution for intelligent cache invalidation demo',
      defaultBehavior: {
        origin: new origins.S3Origin(this.originBucket, {
          originAccessControl: oac,
        }),
        viewerProtocolPolicy: props.enforceHTTPS !== false 
          ? cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS 
          : cloudfront.ViewerProtocolPolicy.ALLOW_ALL,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        compress: props.enableCompression !== false,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
      },
      additionalBehaviors: {
        // API content with shorter TTL
        '/api/*': {
          origin: new origins.S3Origin(this.originBucket, {
            originAccessControl: oac,
          }),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
          cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
          compress: true,
        },
        // Static assets with longer TTL
        '/css/*': {
          origin: new origins.S3Origin(this.originBucket, {
            originAccessControl: oac,
          }),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
          cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED_FOR_UNCOMPRESSED_OBJECTS,
          compress: true,
        },
        '/js/*': {
          origin: new origins.S3Origin(this.originBucket, {
            originAccessControl: oac,
          }),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
          cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED_FOR_UNCOMPRESSED_OBJECTS,
          compress: true,
        },
      },
      priceClass: this.mapPriceClass(props.priceClass || 'PriceClass_100'),
      enableIpv6: props.enableIPv6 !== false,
      defaultRootObject: 'index.html',
      httpVersion: cloudfront.HttpVersion.HTTP2,
      minimumProtocolVersion: cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
    });

    // Update Lambda environment with distribution ID
    this.invalidationFunction.addEnvironment('DISTRIBUTION_ID', this.distribution.distributionId);

    // Grant Lambda permissions to CloudFront, DynamoDB, and SQS
    this.invalidationFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'cloudfront:CreateInvalidation',
          'cloudfront:GetInvalidation',
          'cloudfront:ListInvalidations',
        ],
        resources: ['*'],
      })
    );

    this.invalidationTable.grantReadWriteData(this.invalidationFunction);
    this.invalidationQueue.grantConsumeMessages(this.invalidationFunction);
    this.invalidationQueue.grantSendMessages(this.invalidationFunction);

    // Create EventBridge rules for different event sources
    const s3EventRule = new events.Rule(this, 'S3EventRule', {
      eventBus: this.eventBus,
      ruleName: resourceName('s3-events'),
      description: 'Rule for S3 object creation and deletion events',
      eventPattern: {
        source: ['aws.s3'],
        detailType: ['Object Created', 'Object Deleted'],
        detail: {
          bucket: {
            name: [this.originBucket.bucketName],
          },
        },
      },
    });

    const deploymentEventRule = new events.Rule(this, 'DeploymentEventRule', {
      eventBus: this.eventBus,
      ruleName: resourceName('deployment-events'),
      description: 'Rule for deployment and custom application events',
      eventPattern: {
        source: ['aws.codedeploy', 'custom.app'],
        detailType: ['Deployment State-change Notification', 'Application Deployment'],
      },
    });

    // Add Lambda as target for EventBridge rules
    s3EventRule.addTarget(new targets.LambdaFunction(this.invalidationFunction));
    deploymentEventRule.addTarget(new targets.LambdaFunction(this.invalidationFunction));

    // Add SQS event source for batch processing
    if (props.enableBatchProcessing !== false) {
      this.invalidationFunction.addEventSource(
        new lambdaEventSources.SqsEventSource(this.invalidationQueue, {
          batchSize: props.batchSize || 10,
          maxBatchingWindow: cdk.Duration.seconds(props.batchWindow || 30),
        })
      );
    }

    // Deploy sample content to S3 bucket
    new s3deploy.BucketDeployment(this, 'DeployContent', {
      sources: [s3deploy.Source.data('index.html', '<html><body><h1>CloudFront Invalidation Demo</h1><p>Version 1.0</p></body></html>')],
      destinationBucket: this.originBucket,
      distribution: this.distribution,
      distributionPaths: ['/*'],
    });

    // Create CloudWatch dashboard for monitoring
    if (props.enableMonitoring !== false) {
      this.dashboard = this.createMonitoringDashboard(props.dashboardName || 'CloudFront-Invalidation-Dashboard');
    }

    // Create CloudWatch alarms for cost and performance monitoring
    this.createCloudWatchAlarms();

    // Output important resource information
    new cdk.CfnOutput(this, 'OriginBucketName', {
      value: this.originBucket.bucketName,
      description: 'Name of the S3 bucket serving as CloudFront origin',
    });

    new cdk.CfnOutput(this, 'DistributionId', {
      value: this.distribution.distributionId,
      description: 'CloudFront distribution ID',
    });

    new cdk.CfnOutput(this, 'DistributionDomainName', {
      value: this.distribution.distributionDomainName,
      description: 'CloudFront distribution domain name',
    });

    new cdk.CfnOutput(this, 'InvalidationFunctionName', {
      value: this.invalidationFunction.functionName,
      description: 'Name of the Lambda function processing invalidations',
    });

    new cdk.CfnOutput(this, 'EventBusName', {
      value: this.eventBus.eventBusName,
      description: 'Name of the EventBridge custom bus',
    });

    new cdk.CfnOutput(this, 'QueueUrl', {
      value: this.invalidationQueue.queueUrl,
      description: 'URL of the SQS queue for batch processing',
    });

    new cdk.CfnOutput(this, 'TableName', {
      value: this.invalidationTable.tableName,
      description: 'Name of the DynamoDB table for invalidation logging',
    });

    if (this.dashboard) {
      new cdk.CfnOutput(this, 'DashboardUrl', {
        value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
        description: 'URL to the CloudWatch dashboard',
      });
    }
  }

  /**
   * Maps string price class to CloudFront PriceClass enum
   */
  private mapPriceClass(priceClass: string): cloudfront.PriceClass {
    switch (priceClass.toUpperCase()) {
      case 'PRICECLASS_ALL':
        return cloudfront.PriceClass.PRICE_CLASS_ALL;
      case 'PRICECLASS_200':
        return cloudfront.PriceClass.PRICE_CLASS_200;
      case 'PRICECLASS_100':
      default:
        return cloudfront.PriceClass.PRICE_CLASS_100;
    }
  }

  /**
   * Creates a comprehensive CloudWatch dashboard for monitoring
   */
  private createMonitoringDashboard(dashboardName: string): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'MonitoringDashboard', {
      dashboardName: dashboardName,
    });

    // CloudFront metrics
    const cloudFrontWidget = new cloudwatch.GraphWidget({
      title: 'CloudFront Performance',
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/CloudFront',
          metricName: 'Requests',
          dimensionsMap: {
            DistributionId: this.distribution.distributionId,
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/CloudFront',
          metricName: 'CacheHitRate',
          dimensionsMap: {
            DistributionId: this.distribution.distributionId,
          },
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        }),
      ],
      width: 12,
      height: 6,
    });

    // Lambda metrics
    const lambdaWidget = new cloudwatch.GraphWidget({
      title: 'Invalidation Function Performance',
      left: [
        this.invalidationFunction.metricDuration({
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        }),
        this.invalidationFunction.metricInvocations({
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
        this.invalidationFunction.metricErrors({
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
      ],
      width: 12,
      height: 6,
    });

    // Event processing metrics
    const eventWidget = new cloudwatch.GraphWidget({
      title: 'Event Processing Volume',
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/Events',
          metricName: 'MatchedEvents',
          dimensionsMap: {
            EventBusName: this.eventBus.eventBusName,
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/SQS',
          metricName: 'NumberOfMessagesSent',
          dimensionsMap: {
            QueueName: this.invalidationQueue.queueName,
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
      ],
      width: 24,
      height: 6,
    });

    // DynamoDB metrics
    const dynamoWidget = new cloudwatch.GraphWidget({
      title: 'Invalidation Audit Log',
      left: [
        this.invalidationTable.metricConsumedReadCapacityUnits({
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
        this.invalidationTable.metricConsumedWriteCapacityUnits({
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
      ],
      width: 12,
      height: 6,
    });

    // Add widgets to dashboard
    dashboard.addWidgets(cloudFrontWidget, lambdaWidget);
    dashboard.addWidgets(eventWidget);
    dashboard.addWidgets(dynamoWidget);

    return dashboard;
  }

  /**
   * Creates CloudWatch alarms for monitoring and alerting
   */
  private createCloudWatchAlarms(): void {
    // Alarm for high Lambda error rate
    const lambdaErrorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
      metric: this.invalidationFunction.metricErrors({
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 10,
      evaluationPeriods: 2,
      alarmDescription: 'High error rate in invalidation function',
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Alarm for low cache hit rate
    const cacheHitRateAlarm = new cloudwatch.Alarm(this, 'CacheHitRateAlarm', {
      metric: new cloudwatch.Metric({
        namespace: 'AWS/CloudFront',
        metricName: 'CacheHitRate',
        dimensionsMap: {
          DistributionId: this.distribution.distributionId,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(15),
      }),
      threshold: 70,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 3,
      alarmDescription: 'CloudFront cache hit rate below 70%',
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Alarm for high Lambda duration
    const lambdaDurationAlarm = new cloudwatch.Alarm(this, 'LambdaDurationAlarm', {
      metric: this.invalidationFunction.metricDuration({
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 30000, // 30 seconds
      evaluationPeriods: 2,
      alarmDescription: 'High duration in invalidation function',
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
  }

  /**
   * Returns the Lambda function code for intelligent invalidation processing
   */
  private getLambdaCode(): string {
    return `
const AWS = require('aws-sdk');
const cloudfront = new AWS.CloudFront();
const dynamodb = new AWS.DynamoDB.DocumentClient();
const sqs = new AWS.SQS();

const TABLE_NAME = process.env.DDB_TABLE_NAME;
const QUEUE_URL = process.env.QUEUE_URL;
const DISTRIBUTION_ID = process.env.DISTRIBUTION_ID;
const BATCH_SIZE = parseInt(process.env.BATCH_SIZE || '10');
const ENABLE_COST_OPTIMIZATION = process.env.ENABLE_COST_OPTIMIZATION === 'true';

exports.handler = async (event) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    
    try {
        let invalidationPaths = [];
        
        // Process different event sources
        if (event.source === 'aws.s3') {
            invalidationPaths = await processS3Event(event);
        } else if (event.source === 'aws.codedeploy' || event.source === 'custom.app') {
            invalidationPaths = await processDeploymentEvent(event);
        } else if (event.Records) {
            // SQS batch processing
            invalidationPaths = await processSQSBatch(event);
        }
        
        if (invalidationPaths.length === 0) {
            console.log('No invalidation paths to process');
            return { statusCode: 200, body: 'No invalidation needed' };
        }
        
        // Optimize paths using intelligent grouping
        const optimizedPaths = ENABLE_COST_OPTIMIZATION ? 
            optimizeInvalidationPaths(invalidationPaths) : invalidationPaths;
        
        // Create invalidation batches
        const batches = createBatches(optimizedPaths, BATCH_SIZE);
        
        const results = [];
        for (const batch of batches) {
            const result = await createInvalidation(batch);
            results.push(result);
            
            // Log invalidation to DynamoDB
            await logInvalidation(result.Invalidation.Id, batch, event);
        }
        
        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Invalidations created successfully',
                invalidations: results.length,
                paths: optimizedPaths.length
            })
        };
        
    } catch (error) {
        console.error('Error processing invalidation:', error);
        throw error;
    }
};

async function processS3Event(event) {
    const paths = [];
    
    if (event.detail && event.detail.object) {
        const objectKey = event.detail.object.key;
        
        // Smart path invalidation based on content type
        if (objectKey.endsWith('.html')) {
            paths.push('/' + objectKey);
            // Also invalidate directory index
            if (objectKey.includes('/')) {
                const dir = objectKey.substring(0, objectKey.lastIndexOf('/'));
                paths.push('/' + dir + '/');
            }
        } else if (objectKey.match(/\\.(css|js|json)$/)) {
            paths.push('/' + objectKey);
            
            // For CSS/JS changes, also invalidate HTML pages
            if (objectKey.includes('css/') || objectKey.includes('js/')) {
                paths.push('/index.html');
                paths.push('/');
            }
        } else if (objectKey.match(/\\.(jpg|jpeg|png|gif|webp|svg)$/)) {
            paths.push('/' + objectKey);
        }
    }
    
    return [...new Set(paths)];
}

async function processDeploymentEvent(event) {
    const deploymentPaths = [
        '/',
        '/index.html',
        '/css/*',
        '/js/*',
        '/api/*'
    ];
    
    if (event.detail && event.detail.changedFiles) {
        event.detail.changedFiles.forEach(file => {
            deploymentPaths.push('/' + file);
        });
    }
    
    return deploymentPaths;
}

async function processSQSBatch(event) {
    const paths = [];
    
    for (const record of event.Records) {
        try {
            const body = JSON.parse(record.body);
            if (body.paths && Array.isArray(body.paths)) {
                paths.push(...body.paths);
            }
        } catch (error) {
            console.error('Error parsing SQS message:', error);
        }
    }
    
    return [...new Set(paths)];
}

function optimizeInvalidationPaths(paths) {
    const optimized = new Set();
    const sorted = paths.sort();
    
    for (const path of sorted) {
        let isRedundant = false;
        
        // Check if this path is covered by an existing wildcard
        for (const existing of optimized) {
            if (existing.endsWith('/*') && path.startsWith(existing.slice(0, -1))) {
                isRedundant = true;
                break;
            }
        }
        
        if (!isRedundant) {
            optimized.add(path);
        }
    }
    
    return Array.from(optimized);
}

function createBatches(paths, batchSize) {
    const batches = [];
    for (let i = 0; i < paths.length; i += batchSize) {
        batches.push(paths.slice(i, i + batchSize));
    }
    return batches;
}

async function createInvalidation(paths) {
    const params = {
        DistributionId: DISTRIBUTION_ID,
        InvalidationBatch: {
            Paths: {
                Quantity: paths.length,
                Items: paths
            },
            CallerReference: 'invalidation-' + Date.now() + '-' + Math.random().toString(36).substr(2, 9)
        }
    };
    
    console.log('Creating invalidation for paths:', paths);
    return await cloudfront.createInvalidation(params).promise();
}

async function logInvalidation(invalidationId, paths, originalEvent) {
    const params = {
        TableName: TABLE_NAME,
        Item: {
            InvalidationId: invalidationId,
            Timestamp: new Date().toISOString(),
            Paths: paths,
            PathCount: paths.length,
            Source: originalEvent.source || 'unknown',
            EventType: originalEvent['detail-type'] || 'unknown',
            Status: 'InProgress',
            TTL: Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60) // 30 days
        }
    };
    
    await dynamodb.put(params).promise();
}
`;
  }
}