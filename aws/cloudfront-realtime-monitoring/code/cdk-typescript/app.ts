#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as kinesis from 'aws-cdk-lib/aws-kinesis';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as opensearch from 'aws-cdk-lib/aws-opensearchservice';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kinesisfirehose from 'aws-cdk-lib/aws-kinesisfirehose';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as eventsources from 'aws-cdk-lib/aws-lambda-event-sources';
import { RemovalPolicy } from 'aws-cdk-lib';

/**
 * Properties for the CloudFront Real-time Monitoring Stack
 */
interface CloudFrontMonitoringStackProps extends cdk.StackProps {
  /** 
   * Environment name for resource naming and tagging
   * @default 'dev'
   */
  readonly environmentName?: string;
  
  /**
   * OpenSearch instance type for the analytics domain
   * @default 't3.small.search'
   */
  readonly openSearchInstanceType?: string;
  
  /**
   * Number of OpenSearch instances
   * @default 1
   */
  readonly openSearchInstanceCount?: number;
  
  /**
   * OpenSearch EBS volume size in GB
   * @default 20
   */
  readonly openSearchVolumeSize?: number;
  
  /**
   * Kinesis shard count for the main stream
   * @default 2
   */
  readonly kinesisShardCount?: number;
  
  /**
   * Lambda function memory size in MB
   * @default 512
   */
  readonly lambdaMemorySize?: number;
  
  /**
   * CloudFront price class
   * @default PriceClass.PRICE_CLASS_100
   */
  readonly cloudFrontPriceClass?: cloudfront.PriceClass;
  
  /**
   * DynamoDB metrics retention in days
   * @default 7
   */
  readonly metricsRetentionDays?: number;
}

/**
 * CloudFront Real-time Monitoring and Analytics Stack
 * 
 * This stack implements a comprehensive real-time monitoring solution for CloudFront
 * distributions, providing immediate visibility into user behavior, performance metrics,
 * and security events. The architecture includes:
 * 
 * - CloudFront distribution with real-time logging
 * - Kinesis Data Streams for high-throughput log ingestion
 * - Lambda functions for real-time log processing and enrichment
 * - DynamoDB for operational metrics storage
 * - OpenSearch for log analytics and visualization
 * - Kinesis Data Firehose for data delivery to multiple destinations
 * - CloudWatch dashboards and alarms for monitoring
 */
export class CloudFrontMonitoringStack extends cdk.Stack {
  /** S3 bucket for storing content */
  public readonly contentBucket: s3.Bucket;
  
  /** S3 bucket for storing processed logs */
  public readonly logsBucket: s3.Bucket;
  
  /** CloudFront distribution */
  public readonly distribution: cloudfront.Distribution;
  
  /** Primary Kinesis data stream for real-time logs */
  public readonly logStream: kinesis.Stream;
  
  /** Processed data stream */
  public readonly processedStream: kinesis.Stream;
  
  /** Lambda function for log processing */
  public readonly logProcessor: lambda.Function;
  
  /** DynamoDB table for metrics storage */
  public readonly metricsTable: dynamodb.Table;
  
  /** OpenSearch domain for log analytics */
  public readonly openSearchDomain: opensearch.Domain;
  
  /** Kinesis Data Firehose delivery stream */
  public readonly firehoseStream: kinesisfirehose.CfnDeliveryStream;
  
  /** CloudWatch dashboard */
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props?: CloudFrontMonitoringStackProps) {
    super(scope, id, props);

    // Extract properties with defaults
    const environmentName = props?.environmentName ?? 'dev';
    const openSearchInstanceType = props?.openSearchInstanceType ?? 't3.small.search';
    const openSearchInstanceCount = props?.openSearchInstanceCount ?? 1;
    const openSearchVolumeSize = props?.openSearchVolumeSize ?? 20;
    const kinesisShardCount = props?.kinesisShardCount ?? 2;
    const lambdaMemorySize = props?.lambdaMemorySize ?? 512;
    const cloudFrontPriceClass = props?.cloudFrontPriceClass ?? cloudfront.PriceClass.PRICE_CLASS_100;
    const metricsRetentionDays = props?.metricsRetentionDays ?? 7;

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8);
    const projectName = `cf-monitoring-${environmentName}-${uniqueSuffix}`;

    // Create S3 buckets
    this.contentBucket = this.createContentBucket(projectName);
    this.logsBucket = this.createLogsBucket(projectName);

    // Create Kinesis streams
    this.logStream = this.createKinesisStream(`${projectName}-logs`, kinesisShardCount);
    this.processedStream = this.createKinesisStream(`${projectName}-processed`, 1);

    // Create DynamoDB table for metrics
    this.metricsTable = this.createMetricsTable(projectName, metricsRetentionDays);

    // Create OpenSearch domain
    this.openSearchDomain = this.createOpenSearchDomain(
      projectName,
      openSearchInstanceType,
      openSearchInstanceCount,
      openSearchVolumeSize
    );

    // Create Lambda function for log processing
    this.logProcessor = this.createLogProcessor(
      projectName,
      this.metricsTable,
      this.processedStream,
      lambdaMemorySize
    );

    // Create event source mapping for Kinesis to Lambda
    this.createEventSourceMapping();

    // Create CloudFront distribution with real-time logging
    this.distribution = this.createCloudFrontDistribution(
      projectName,
      this.contentBucket,
      this.logStream,
      cloudFrontPriceClass
    );

    // Create Kinesis Data Firehose for data delivery
    this.firehoseStream = this.createFirehoseDeliveryStream(
      projectName,
      this.processedStream,
      this.logsBucket,
      this.openSearchDomain
    );

    // Create CloudWatch dashboard
    this.dashboard = this.createCloudWatchDashboard(
      projectName,
      this.distribution,
      this.logStream,
      this.processedStream,
      this.logProcessor
    );

    // Add tags to all resources
    this.addResourceTags(environmentName, projectName);

    // Output important values
    this.createOutputs();
  }

  /**
   * Creates an S3 bucket for storing CloudFront content
   */
  private createContentBucket(projectName: string): s3.Bucket {
    const bucket = new s3.Bucket(this, 'ContentBucket', {
      bucketName: `${projectName}-content`,
      versioned: false,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      cors: [
        {
          allowedHeaders: ['*'],
          allowedMethods: [s3.HttpMethods.GET, s3.HttpMethods.HEAD],
          allowedOrigins: ['*'],
          maxAge: 3600,
        },
      ],
    });

    return bucket;
  }

  /**
   * Creates an S3 bucket for storing processed logs
   */
  private createLogsBucket(projectName: string): s3.Bucket {
    const bucket = new s3.Bucket(this, 'LogsBucket', {
      bucketName: `${projectName}-logs`,
      versioned: false,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'archive-old-logs',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
          expiration: cdk.Duration.days(365),
        },
      ],
    });

    return bucket;
  }

  /**
   * Creates a Kinesis Data Stream
   */
  private createKinesisStream(streamName: string, shardCount: number): kinesis.Stream {
    return new kinesis.Stream(this, `Stream${streamName.replace(/-/g, '')}`, {
      streamName,
      shardCount,
      streamModeDetails: kinesis.StreamMode.provisioned(),
      encryption: kinesis.StreamEncryption.MANAGED,
      retentionPeriod: cdk.Duration.hours(24),
    });
  }

  /**
   * Creates a DynamoDB table for storing metrics
   */
  private createMetricsTable(projectName: string, retentionDays: number): dynamodb.Table {
    return new dynamodb.Table(this, 'MetricsTable', {
      tableName: `${projectName}-metrics`,
      partitionKey: {
        name: 'MetricId',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'Timestamp',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      removalPolicy: RemovalPolicy.DESTROY,
      timeToLiveAttribute: 'TTL',
      pointInTimeRecovery: true,
    });
  }

  /**
   * Creates an OpenSearch domain for log analytics
   */
  private createOpenSearchDomain(
    projectName: string,
    instanceType: string,
    instanceCount: number,
    volumeSize: number
  ): opensearch.Domain {
    return new opensearch.Domain(this, 'OpenSearchDomain', {
      domainName: `${projectName}-analytics`,
      version: opensearch.EngineVersion.OPENSEARCH_2_3,
      capacity: {
        masterNodes: 0,
        dataNodes: instanceCount,
        dataNodeInstanceType: instanceType,
      },
      ebs: {
        volumeSize,
        volumeType: opensearch.EbsDeviceVolumeType.GP3,
      },
      zoneAwareness: {
        enabled: false,
      },
      logging: {
        slowSearchLogEnabled: true,
        appLogEnabled: true,
        slowIndexLogEnabled: true,
      },
      nodeToNodeEncryption: true,
      encryptionAtRest: {
        enabled: true,
      },
      domainEndpointOptions: {
        enforceHttps: true,
        tlsSecurityPolicy: opensearch.TLSSecurityPolicy.TLS_1_2,
      },
      accessPolicies: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          principals: [new iam.AnyPrincipal()],
          actions: ['es:*'],
          resources: ['*'],
          conditions: {
            IpAddress: {
              'aws:SourceIp': ['0.0.0.0/0'], // Note: In production, restrict to specific IPs
            },
          },
        }),
      ],
      removalPolicy: RemovalPolicy.DESTROY,
    });
  }

  /**
   * Creates a Lambda function for real-time log processing
   */
  private createLogProcessor(
    projectName: string,
    metricsTable: dynamodb.Table,
    processedStream: kinesis.Stream,
    memorySize: number
  ): lambda.Function {
    // Create IAM role for Lambda
    const lambdaRole = new iam.Role(this, 'LogProcessorRole', {
      roleName: `${projectName}-lambda-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        LogProcessingPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'kinesis:DescribeStream',
                'kinesis:GetRecords',
                'kinesis:GetShardIterator',
                'kinesis:ListStreams',
                'kinesis:PutRecord',
                'kinesis:PutRecords',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:PutItem',
                'dynamodb:GetItem',
                'dynamodb:UpdateItem',
                'dynamodb:Query',
                'dynamodb:Scan',
              ],
              resources: [metricsTable.tableArn],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['cloudwatch:PutMetricData'],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Lambda function code
    const functionCode = `
const AWS = require('aws-sdk');
const geoip = require('geoip-lite');

const cloudwatch = new AWS.CloudWatch();
const dynamodb = new AWS.DynamoDB.DocumentClient();
const kinesis = new AWS.Kinesis();

const METRICS_TABLE = process.env.METRICS_TABLE;
const PROCESSED_STREAM = process.env.PROCESSED_STREAM;

exports.handler = async (event) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    
    const processedRecords = [];
    const metrics = {
        totalRequests: 0,
        totalBytes: 0,
        errors4xx: 0,
        errors5xx: 0,
        cacheMisses: 0,
        regionCounts: {},
        statusCodes: {},
        userAgents: {}
    };
    
    for (const record of event.Records) {
        try {
            const data = Buffer.from(record.kinesis.data, 'base64').toString('utf-8');
            const logEntries = data.trim().split('\\n');
            
            for (const logEntry of logEntries) {
                const processedLog = await processLogEntry(logEntry, metrics);
                if (processedLog) {
                    processedRecords.push(processedLog);
                }
            }
        } catch (error) {
            console.error('Error processing record:', error);
        }
    }
    
    if (processedRecords.length > 0) {
        await sendToKinesis(processedRecords);
    }
    
    await storeMetrics(metrics);
    await sendCloudWatchMetrics(metrics);
    
    return {
        statusCode: 200,
        processedRecords: processedRecords.length
    };
};

async function processLogEntry(logEntry, metrics) {
    try {
        const fields = logEntry.split('\\t');
        
        if (fields.length < 20) {
            return null;
        }
        
        const timestamp = \`\${fields[0]} \${fields[1]}\`;
        const edgeLocation = fields[2];
        const bytesDownloaded = parseInt(fields[3]) || 0;
        const clientIp = fields[4];
        const method = fields[5];
        const host = fields[6];
        const uri = fields[7];
        const status = parseInt(fields[8]) || 0;
        const referer = fields[9];
        const userAgent = fields[10];
        const edgeResultType = fields[13];
        const timeTaken = parseFloat(fields[18]) || 0;
        
        const geoData = geoip.lookup(clientIp) || {};
        
        metrics.totalRequests++;
        metrics.totalBytes += bytesDownloaded;
        
        if (status >= 400 && status < 500) {
            metrics.errors4xx++;
        } else if (status >= 500) {
            metrics.errors5xx++;
        }
        
        if (edgeResultType === 'Miss') {
            metrics.cacheMisses++;
        }
        
        const region = geoData.region || 'Unknown';
        metrics.regionCounts[region] = (metrics.regionCounts[region] || 0) + 1;
        metrics.statusCodes[status] = (metrics.statusCodes[status] || 0) + 1;
        
        const uaCategory = categorizeUserAgent(userAgent);
        metrics.userAgents[uaCategory] = (metrics.userAgents[uaCategory] || 0) + 1;
        
        return {
            timestamp: new Date(timestamp).toISOString(),
            edgeLocation,
            clientIp,
            method,
            host,
            uri,
            status,
            bytesDownloaded,
            timeTaken,
            edgeResultType,
            userAgent: uaCategory,
            country: geoData.country || 'Unknown',
            region: geoData.region || 'Unknown',
            city: geoData.city || 'Unknown',
            referer: referer !== '-' ? referer : null,
            cacheHit: edgeResultType !== 'Miss',
            isError: status >= 400,
            processingTime: Date.now()
        };
        
    } catch (error) {
        console.error('Error parsing log entry:', error);
        return null;
    }
}

function categorizeUserAgent(userAgent) {
    if (!userAgent || userAgent === '-') return 'Unknown';
    
    const ua = userAgent.toLowerCase();
    if (ua.includes('chrome')) return 'Chrome';
    if (ua.includes('firefox')) return 'Firefox';
    if (ua.includes('safari') && !ua.includes('chrome')) return 'Safari';
    if (ua.includes('edge')) return 'Edge';
    if (ua.includes('bot') || ua.includes('crawler')) return 'Bot';
    if (ua.includes('mobile')) return 'Mobile';
    
    return 'Other';
}

async function sendToKinesis(records) {
    const batchSize = 500;
    
    for (let i = 0; i < records.length; i += batchSize) {
        const batch = records.slice(i, i + batchSize);
        const kinesisRecords = batch.map(record => ({
            Data: JSON.stringify(record),
            PartitionKey: record.edgeLocation || 'default'
        }));
        
        try {
            await kinesis.putRecords({
                StreamName: PROCESSED_STREAM,
                Records: kinesisRecords
            }).promise();
        } catch (error) {
            console.error('Error sending to Kinesis:', error);
        }
    }
}

async function storeMetrics(metrics) {
    const timestamp = new Date().toISOString();
    const ttl = Math.floor(Date.now() / 1000) + (7 * 24 * 60 * 60); // 7 days
    
    try {
        await dynamodb.put({
            TableName: METRICS_TABLE,
            Item: {
                MetricId: \`metrics-\${Date.now()}\`,
                Timestamp: timestamp,
                TotalRequests: metrics.totalRequests,
                TotalBytes: metrics.totalBytes,
                Errors4xx: metrics.errors4xx,
                Errors5xx: metrics.errors5xx,
                CacheMisses: metrics.cacheMisses,
                RegionCounts: metrics.regionCounts,
                StatusCodes: metrics.statusCodes,
                UserAgents: metrics.userAgents,
                TTL: ttl
            }
        }).promise();
    } catch (error) {
        console.error('Error storing metrics:', error);
    }
}

async function sendCloudWatchMetrics(metrics) {
    const metricData = [
        {
            MetricName: 'RequestCount',
            Value: metrics.totalRequests,
            Unit: 'Count',
            Timestamp: new Date()
        },
        {
            MetricName: 'BytesDownloaded',
            Value: metrics.totalBytes,
            Unit: 'Bytes',
            Timestamp: new Date()
        },
        {
            MetricName: 'ErrorRate4xx',
            Value: metrics.totalRequests > 0 ? (metrics.errors4xx / metrics.totalRequests) * 100 : 0,
            Unit: 'Percent',
            Timestamp: new Date()
        },
        {
            MetricName: 'ErrorRate5xx',
            Value: metrics.totalRequests > 0 ? (metrics.errors5xx / metrics.totalRequests) * 100 : 0,
            Unit: 'Percent',
            Timestamp: new Date()
        },
        {
            MetricName: 'CacheMissRate',
            Value: metrics.totalRequests > 0 ? (metrics.cacheMisses / metrics.totalRequests) * 100 : 0,
            Unit: 'Percent',
            Timestamp: new Date()
        }
    ];
    
    try {
        await cloudwatch.putMetricData({
            Namespace: 'CloudFront/RealTime',
            MetricData: metricData
        }).promise();
    } catch (error) {
        console.error('Error sending CloudWatch metrics:', error);
    }
}
`;

    // Create Lambda function
    const logProcessorFunction = new lambda.Function(this, 'LogProcessor', {
      functionName: `${projectName}-log-processor`,
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: lambda.Code.fromInline(functionCode),
      timeout: cdk.Duration.minutes(5),
      memorySize,
      role: lambdaRole,
      environment: {
        METRICS_TABLE: metricsTable.tableName,
        PROCESSED_STREAM: processedStream.streamName,
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    return logProcessorFunction;
  }

  /**
   * Creates event source mapping between Kinesis and Lambda
   */
  private createEventSourceMapping(): void {
    new eventsources.KinesisEventSource(this.logStream, {
      batchSize: 100,
      maxBatchingWindow: cdk.Duration.seconds(5),
      startingPosition: lambda.StartingPosition.LATEST,
    });

    this.logProcessor.addEventSource(
      new eventsources.KinesisEventSource(this.logStream, {
        batchSize: 100,
        maxBatchingWindow: cdk.Duration.seconds(5),
        startingPosition: lambda.StartingPosition.LATEST,
      })
    );
  }

  /**
   * Creates CloudFront distribution with real-time logging
   */
  private createCloudFrontDistribution(
    projectName: string,
    contentBucket: s3.Bucket,
    logStream: kinesis.Stream,
    priceClass: cloudfront.PriceClass
  ): cloudfront.Distribution {
    // Create Origin Access Control
    const originAccessControl = new cloudfront.S3OriginAccessControl(this, 'OAC', {
      description: `Origin Access Control for ${projectName}`,
      originAccessControlName: `${projectName}-oac`,
      signing: cloudfront.Signing.SIGV4_ALWAYS,
    });

    // Create IAM role for CloudFront real-time logs
    const realtimeLogsRole = new iam.Role(this, 'RealtimeLogsRole', {
      roleName: `${projectName}-realtime-logs-role`,
      assumedBy: new iam.ServicePrincipal('cloudfront.amazonaws.com'),
      inlinePolicies: {
        KinesisAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['kinesis:PutRecords', 'kinesis:PutRecord'],
              resources: [logStream.streamArn],
            }),
          ],
        }),
      },
    });

    // Create real-time log configuration
    const realtimeLogConfig = new cloudfront.CfnRealtimeLogConfig(this, 'RealtimeLogConfig', {
      name: `${projectName}-realtime-logs`,
      endPoints: [
        {
          streamType: 'Kinesis',
          kinesisStreamConfig: {
            roleArn: realtimeLogsRole.roleArn,
            streamArn: logStream.streamArn,
          },
        },
      ],
      fields: [
        'timestamp',
        'c-ip',
        'sc-status',
        'cs-method',
        'cs-uri-stem',
        'cs-uri-query',
        'cs-referer',
        'cs-user-agent',
        'cs-cookie',
        'x-edge-location',
        'x-edge-request-id',
        'x-host-header',
        'cs-protocol',
        'cs-bytes',
        'sc-bytes',
        'time-taken',
        'x-forwarded-for',
        'ssl-protocol',
        'ssl-cipher',
        'x-edge-response-result-type',
        'cs-protocol-version',
        'fle-status',
        'fle-encrypted-fields',
        'c-port',
        'time-to-first-byte',
        'x-edge-detailed-result-type',
        'sc-content-type',
        'sc-content-len',
        'sc-range-start',
        'sc-range-end',
      ],
    });

    // Create CloudFront distribution
    const distribution = new cloudfront.Distribution(this, 'Distribution', {
      comment: `CloudFront distribution for ${projectName}`,
      defaultRootObject: 'index.html',
      priceClass,
      httpVersion: cloudfront.HttpVersion.HTTP2_AND_3,
      enableIpv6: true,
      minimumProtocolVersion: cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
      defaultBehavior: {
        origin: origins.S3BucketOrigin.withOriginAccessControl(contentBucket, {
          originAccessControl,
        }),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
        compress: true,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        realtimeLogConfig: realtimeLogConfig,
      },
      additionalBehaviors: {
        '/api/*': {
          origin: origins.S3BucketOrigin.withOriginAccessControl(contentBucket, {
            originAccessControl,
          }),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
          cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
          compress: true,
          cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
          realtimeLogConfig: realtimeLogConfig,
        },
      },
    });

    // Grant CloudFront access to S3 bucket
    contentBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('cloudfront.amazonaws.com')],
        actions: ['s3:GetObject'],
        resources: [contentBucket.arnForObjects('*')],
        conditions: {
          StringEquals: {
            'AWS:SourceArn': distribution.distributionArn,
          },
        },
      })
    );

    return distribution;
  }

  /**
   * Creates Kinesis Data Firehose delivery stream
   */
  private createFirehoseDeliveryStream(
    projectName: string,
    sourceStream: kinesis.Stream,
    destinationBucket: s3.Bucket,
    openSearchDomain: opensearch.Domain
  ): kinesisfirehose.CfnDeliveryStream {
    // Create IAM role for Firehose
    const firehoseRole = new iam.Role(this, 'FirehoseRole', {
      roleName: `${projectName}-firehose-role`,
      assumedBy: new iam.ServicePrincipal('firehose.amazonaws.com'),
      inlinePolicies: {
        FirehoseDeliveryPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:AbortMultipartUpload',
                's3:GetBucketLocation',
                's3:GetObject',
                's3:ListBucket',
                's3:ListBucketMultipartUploads',
                's3:PutObject',
              ],
              resources: [destinationBucket.bucketArn, destinationBucket.arnForObjects('*')],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'es:DescribeElasticsearchDomain',
                'es:DescribeElasticsearchDomains',
                'es:DescribeElasticsearchDomainConfig',
                'es:ESHttpPost',
                'es:ESHttpPut',
              ],
              resources: [openSearchDomain.domainArn, `${openSearchDomain.domainArn}/*`],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['logs:PutLogEvents'],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create log group for Firehose
    const logGroup = new logs.LogGroup(this, 'FirehoseLogGroup', {
      logGroupName: `/aws/kinesisfirehose/${projectName}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // Create Firehose delivery stream
    const deliveryStream = new kinesisfirehose.CfnDeliveryStream(this, 'FirehoseStream', {
      deliveryStreamName: `${projectName}-logs-to-s3-opensearch`,
      deliveryStreamType: 'KinesisStreamAsSource',
      kinesisStreamSourceConfiguration: {
        kinesisStreamArn: sourceStream.streamArn,
        roleArn: firehoseRole.roleArn,
      },
      extendedS3DestinationConfiguration: {
        bucketArn: destinationBucket.bucketArn,
        roleArn: firehoseRole.roleArn,
        prefix: 'cloudfront-logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/',
        bufferingHints: {
          sizeInMBs: 5,
          intervalInSeconds: 60,
        },
        compressionFormat: 'GZIP',
        processingConfiguration: {
          enabled: false,
        },
        cloudWatchLoggingOptions: {
          enabled: true,
          logGroupName: logGroup.logGroupName,
          logStreamName: 'S3Delivery',
        },
      },
    });

    return deliveryStream;
  }

  /**
   * Creates CloudWatch dashboard for monitoring
   */
  private createCloudWatchDashboard(
    projectName: string,
    distribution: cloudfront.Distribution,
    logStream: kinesis.Stream,
    processedStream: kinesis.Stream,
    logProcessor: lambda.Function
  ): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'MonitoringDashboard', {
      dashboardName: `CloudFront-RealTime-Analytics-${projectName}`,
    });

    // Real-time traffic metrics
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Real-time Traffic Volume',
        left: [
          new cloudwatch.Metric({
            namespace: 'CloudFront/RealTime',
            metricName: 'RequestCount',
            statistic: 'Sum',
          }),
        ],
        right: [
          new cloudwatch.Metric({
            namespace: 'CloudFront/RealTime',
            metricName: 'BytesDownloaded',
            statistic: 'Sum',
          }),
        ],
      })
    );

    // Error rates
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Real-time Error Rates',
        left: [
          new cloudwatch.Metric({
            namespace: 'CloudFront/RealTime',
            metricName: 'ErrorRate4xx',
            statistic: 'Average',
          }),
          new cloudwatch.Metric({
            namespace: 'CloudFront/RealTime',
            metricName: 'ErrorRate5xx',
            statistic: 'Average',
          }),
        ],
      })
    );

    // Cache performance
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Cache Performance',
        left: [
          new cloudwatch.Metric({
            namespace: 'CloudFront/RealTime',
            metricName: 'CacheMissRate',
            statistic: 'Average',
          }),
        ],
      })
    );

    // Lambda performance
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Log Processing Performance',
        left: [
          logProcessor.metricDuration(),
          logProcessor.metricInvocations(),
          logProcessor.metricErrors(),
        ],
      })
    );

    // Kinesis metrics
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Kinesis Stream Activity',
        left: [
          logStream.metricIncomingRecords(),
          logStream.metricOutgoingRecords(),
        ],
      })
    );

    // CloudFront standard metrics
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'CloudFront Standard Metrics',
        region: 'us-east-1', // CloudFront metrics are always in us-east-1
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/CloudFront',
            metricName: 'Requests',
            statistic: 'Sum',
            dimensionsMap: {
              DistributionId: distribution.distributionId,
            },
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/CloudFront',
            metricName: 'BytesDownloaded',
            statistic: 'Sum',
            dimensionsMap: {
              DistributionId: distribution.distributionId,
            },
          }),
        ],
      })
    );

    return dashboard;
  }

  /**
   * Adds common tags to all resources
   */
  private addResourceTags(environmentName: string, projectName: string): void {
    cdk.Tags.of(this).add('Environment', environmentName);
    cdk.Tags.of(this).add('Project', 'CloudFront-Monitoring');
    cdk.Tags.of(this).add('Component', projectName);
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }

  /**
   * Creates stack outputs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'ContentBucketName', {
      value: this.contentBucket.bucketName,
      description: 'S3 bucket name for CloudFront content',
      exportName: `${this.stackName}-ContentBucketName`,
    });

    new cdk.CfnOutput(this, 'LogsBucketName', {
      value: this.logsBucket.bucketName,
      description: 'S3 bucket name for processed logs',
      exportName: `${this.stackName}-LogsBucketName`,
    });

    new cdk.CfnOutput(this, 'CloudFrontDistributionId', {
      value: this.distribution.distributionId,
      description: 'CloudFront distribution ID',
      exportName: `${this.stackName}-DistributionId`,
    });

    new cdk.CfnOutput(this, 'CloudFrontDomainName', {
      value: this.distribution.distributionDomainName,
      description: 'CloudFront distribution domain name',
      exportName: `${this.stackName}-DomainName`,
    });

    new cdk.CfnOutput(this, 'OpenSearchDomainEndpoint', {
      value: this.openSearchDomain.domainEndpoint,
      description: 'OpenSearch domain endpoint',
      exportName: `${this.stackName}-OpenSearchEndpoint`,
    });

    new cdk.CfnOutput(this, 'OpenSearchDashboardsUrl', {
      value: `https://${this.openSearchDomain.domainEndpoint}/_dashboards/`,
      description: 'OpenSearch Dashboards URL',
      exportName: `${this.stackName}-DashboardsUrl`,
    });

    new cdk.CfnOutput(this, 'CloudWatchDashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'CloudWatch dashboard URL',
      exportName: `${this.stackName}-CloudWatchDashboard`,
    });

    new cdk.CfnOutput(this, 'MetricsTableName', {
      value: this.metricsTable.tableName,
      description: 'DynamoDB table name for metrics storage',
      exportName: `${this.stackName}-MetricsTable`,
    });

    new cdk.CfnOutput(this, 'LogStreamName', {
      value: this.logStream.streamName,
      description: 'Kinesis stream name for CloudFront logs',
      exportName: `${this.stackName}-LogStream`,
    });
  }
}

/**
 * CDK Application
 */
const app = new cdk.App();

// Get environment configuration from context or use defaults
const environmentName = app.node.tryGetContext('environment') || 'dev';
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION || 'us-east-1';
const account = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;

// Create the stack
new CloudFrontMonitoringStack(app, 'CloudFrontMonitoringStack', {
  stackName: `cloudfront-monitoring-${environmentName}`,
  description: 'CloudFront Real-time Monitoring and Analytics Infrastructure',
  env: {
    account,
    region,
  },
  environmentName,
  // Customize these properties as needed
  openSearchInstanceType: app.node.tryGetContext('openSearchInstanceType') || 't3.small.search',
  openSearchInstanceCount: app.node.tryGetContext('openSearchInstanceCount') || 1,
  openSearchVolumeSize: app.node.tryGetContext('openSearchVolumeSize') || 20,
  kinesisShardCount: app.node.tryGetContext('kinesisShardCount') || 2,
  lambdaMemorySize: app.node.tryGetContext('lambdaMemorySize') || 512,
  cloudFrontPriceClass: cloudfront.PriceClass.PRICE_CLASS_100,
  metricsRetentionDays: app.node.tryGetContext('metricsRetentionDays') || 7,
  tags: {
    Project: 'CloudFront-Monitoring',
    Environment: environmentName,
    ManagedBy: 'CDK',
  },
});

app.synth();