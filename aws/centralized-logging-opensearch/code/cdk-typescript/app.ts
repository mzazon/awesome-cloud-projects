#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as opensearch from 'aws-cdk-lib/aws-opensearchservice';
import * as kinesis from 'aws-cdk-lib/aws-kinesis';
import * as kinesisFirehose from 'aws-cdk-lib/aws-kinesisfirehose';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cwActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import { EventSourceMapping } from 'aws-cdk-lib/aws-lambda';

/**
 * Configuration interface for the Centralized Logging Stack
 */
interface CentralizedLoggingStackProps extends cdk.StackProps {
  /** OpenSearch domain name */
  readonly domainName?: string;
  /** Kinesis stream name */
  readonly kinesisStreamName?: string;
  /** Kinesis Firehose delivery stream name */
  readonly firehoseStreamName?: string;
  /** S3 backup bucket name */
  readonly backupBucketName?: string;
  /** OpenSearch instance type for data nodes */
  readonly instanceType?: string;
  /** Number of data nodes */
  readonly instanceCount?: number;
  /** OpenSearch version */
  readonly opensearchVersion?: string;
  /** EBS volume size for each node (GB) */
  readonly volumeSize?: number;
  /** Email address for alerts */
  readonly alertEmail?: string;
}

/**
 * CDK Stack for Centralized Logging with OpenSearch Service
 * 
 * This stack creates a comprehensive logging architecture that includes:
 * - Amazon OpenSearch Service domain for log analytics and visualization
 * - Kinesis Data Streams for scalable log ingestion
 * - Lambda function for log processing and enrichment
 * - Kinesis Data Firehose for reliable log delivery
 * - S3 bucket for backup storage of failed deliveries
 * - CloudWatch alarms and SNS notifications for monitoring
 * - IAM roles with least privilege access
 */
export class CentralizedLoggingStack extends cdk.Stack {
  /** OpenSearch Service domain */
  public readonly opensearchDomain: opensearch.Domain;
  
  /** Kinesis Data Stream for log ingestion */
  public readonly kinesisStream: kinesis.Stream;
  
  /** Lambda function for log processing */
  public readonly logProcessorFunction: lambda.Function;
  
  /** Kinesis Data Firehose delivery stream */
  public readonly firehoseDeliveryStream: kinesisFirehose.CfnDeliveryStream;
  
  /** S3 bucket for backup storage */
  public readonly backupBucket: s3.Bucket;
  
  /** SNS topic for alerts */
  public readonly alertsTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: CentralizedLoggingStackProps = {}) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = cdk.Names.uniqueId(this).slice(-8).toLowerCase();

    // Configuration with defaults
    const config = {
      domainName: props.domainName || `central-logging-${uniqueSuffix}`,
      kinesisStreamName: props.kinesisStreamName || `log-stream-${uniqueSuffix}`,
      firehoseStreamName: props.firehoseStreamName || `log-delivery-${uniqueSuffix}`,
      backupBucketName: props.backupBucketName || `central-logging-backup-${uniqueSuffix}`,
      instanceType: props.instanceType || 't3.small.search',
      instanceCount: props.instanceCount || 3,
      opensearchVersion: props.opensearchVersion || 'OpenSearch_2.9',
      volumeSize: props.volumeSize || 20,
      alertEmail: props.alertEmail,
    };

    // Create S3 bucket for backup storage
    this.backupBucket = this.createBackupBucket(config.backupBucketName);

    // Create Kinesis Data Stream for log ingestion
    this.kinesisStream = this.createKinesisStream(config.kinesisStreamName);

    // Create OpenSearch Service domain
    this.opensearchDomain = this.createOpenSearchDomain(config);

    // Create log processing Lambda function
    this.logProcessorFunction = this.createLogProcessorFunction(config, this.kinesisStream, this.backupBucket);

    // Create Kinesis Data Firehose delivery stream
    this.firehoseDeliveryStream = this.createFirehoseDeliveryStream(
      config,
      this.opensearchDomain,
      this.backupBucket
    );

    // Create EventSourceMapping for Lambda and Kinesis
    this.createEventSourceMapping();

    // Create monitoring and alerting
    this.alertsTopic = this.createMonitoringAndAlerting(config.alertEmail);

    // Create CloudWatch Logs roles for automatic subscription filters
    this.createCloudWatchLogsRole();

    // Add stack outputs
    this.createOutputs(config);

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'CentralizedLogging');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }

  /**
   * Creates S3 bucket for backup storage with encryption and lifecycle policies
   */
  private createBackupBucket(bucketName: string): s3.Bucket {
    const bucket = new s3.Bucket(this, 'BackupBucket', {
      bucketName,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'TransitionToIA',
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
            {
              storageClass: s3.StorageClass.DEEP_ARCHIVE,
              transitionAfter: cdk.Duration.days(365),
            },
          ],
        },
      ],
    });

    return bucket;
  }

  /**
   * Creates Kinesis Data Stream with multiple shards for scalable log ingestion
   */
  private createKinesisStream(streamName: string): kinesis.Stream {
    const stream = new kinesis.Stream(this, 'LogStream', {
      streamName,
      shardCount: 2,
      retentionPeriod: cdk.Duration.hours(24),
      encryption: kinesis.StreamEncryption.MANAGED,
    });

    return stream;
  }

  /**
   * Creates OpenSearch Service domain with production-ready configuration
   */
  private createOpenSearchDomain(config: any): opensearch.Domain {
    // Create service-linked role for OpenSearch
    const serviceRole = new iam.Role(this, 'OpenSearchServiceRole', {
      assumedBy: new iam.ServicePrincipal('opensearch.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonOpenSearchServiceRolePolicy'),
      ],
    });

    const domain = new opensearch.Domain(this, 'OpenSearchDomain', {
      domainName: config.domainName,
      version: opensearch.EngineVersion.openSearch(config.opensearchVersion.replace('OpenSearch_', '')),
      capacity: {
        dataNodes: config.instanceCount,
        dataNodeInstanceType: config.instanceType,
        masterNodes: 3,
        masterNodeInstanceType: config.instanceType,
      },
      ebs: {
        volumeSize: config.volumeSize,
        volumeType: opensearch.EbsDeviceVolumeType.GP3,
      },
      zoneAwareness: {
        enabled: true,
        availabilityZoneCount: 3,
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
      enforceHttps: true,
      tlsSecurityPolicy: opensearch.TLSSecurityPolicy.TLS_1_2,
      accessPolicies: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          principals: [new iam.AccountRootPrincipal()],
          actions: ['es:*'],
          resources: ['*'],
        }),
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Add custom resource to wait for domain to be ready
    const customResource = new cdk.CustomResource(this, 'WaitForOpenSearch', {
      serviceToken: this.createWaitForDomainFunction().functionArn,
      properties: {
        DomainName: config.domainName,
        Region: this.region,
      },
    });
    customResource.node.addDependency(domain);

    return domain;
  }

  /**
   * Creates Lambda function to wait for OpenSearch domain to be ready
   */
  private createWaitForDomainFunction(): lambda.Function {
    const waitFunction = new lambda.Function(this, 'WaitForDomainFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.handler',
      timeout: cdk.Duration.minutes(15),
      code: lambda.Code.fromInline(`
import boto3
import json
import time
import cfnresponse

def handler(event, context):
    try:
        domain_name = event['ResourceProperties']['DomainName']
        region = event['ResourceProperties']['Region']
        
        client = boto3.client('opensearch', region_name=region)
        
        if event['RequestType'] == 'Delete':
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            return
        
        # Wait for domain to be available
        max_attempts = 60  # 30 minutes with 30-second intervals
        for attempt in range(max_attempts):
            try:
                response = client.describe_domain(DomainName=domain_name)
                domain_status = response['DomainStatus']
                
                if not domain_status.get('Processing', True):
                    print(f"Domain {domain_name} is ready!")
                    cfnresponse.send(event, context, cfnresponse.SUCCESS, {
                        'DomainEndpoint': domain_status.get('Endpoint', ''),
                        'DomainArn': domain_status.get('ARN', '')
                    })
                    return
                    
                print(f"Attempt {attempt + 1}: Domain still processing...")
                time.sleep(30)
                
            except Exception as e:
                print(f"Error checking domain status: {str(e)}")
                time.sleep(30)
        
        # Timeout reached
        cfnresponse.send(event, context, cfnresponse.FAILED, {}, 
                        reason="Timeout waiting for OpenSearch domain to be ready")
        
    except Exception as e:
        print(f"Error in wait function: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {}, 
                        reason=str(e))
      `),
    });

    waitFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['opensearch:DescribeDomain'],
        resources: ['*'],
      })
    );

    return waitFunction;
  }

  /**
   * Creates Lambda function for log processing and enrichment
   */
  private createLogProcessorFunction(
    config: any,
    kinesisStream: kinesis.Stream,
    backupBucket: s3.Bucket
  ): lambda.Function {
    const logProcessorFunction = new lambda.Function(this, 'LogProcessorFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      environment: {
        FIREHOSE_STREAM_NAME: config.firehoseStreamName,
        AWS_REGION: this.region,
      },
      code: lambda.Code.fromInline(`
import json
import base64
import gzip
import boto3
import datetime
import os
import re
from typing import Dict, List, Any

firehose = boto3.client('firehose')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Process CloudWatch Logs data from Kinesis stream
    Enrich logs and forward to Kinesis Data Firehose
    """
    records_to_firehose = []
    error_count = 0
    
    for record in event['Records']:
        try:
            # Decode Kinesis data
            compressed_payload = base64.b64decode(record['kinesis']['data'])
            uncompressed_payload = gzip.decompress(compressed_payload)
            log_data = json.loads(uncompressed_payload)
            
            # Process each log event
            for log_event in log_data.get('logEvents', []):
                enriched_log = enrich_log_event(log_event, log_data)
                
                # Convert to JSON string for Firehose
                json_record = json.dumps(enriched_log) + '\\n'
                
                records_to_firehose.append({
                    'Data': json_record
                })
                
        except Exception as e:
            print(f"Error processing record: {str(e)}")
            error_count += 1
            continue
    
    # Send processed records to Firehose
    if records_to_firehose:
        try:
            response = firehose.put_record_batch(
                DeliveryStreamName=os.environ['FIREHOSE_STREAM_NAME'],
                Records=records_to_firehose
            )
            
            failed_records = response.get('FailedPutCount', 0)
            if failed_records > 0:
                print(f"Failed to process {failed_records} records")
                
        except Exception as e:
            print(f"Error sending to Firehose: {str(e)}")
            error_count += len(records_to_firehose)
    
    # Send metrics to CloudWatch
    if error_count > 0:
        cloudwatch.put_metric_data(
            Namespace='CentralLogging/Processing',
            MetricData=[
                {
                    'MetricName': 'ProcessingErrors',
                    'Value': error_count,
                    'Unit': 'Count',
                    'Timestamp': datetime.datetime.utcnow()
                }
            ]
        )
    
    return {
        'statusCode': 200,
        'processedRecords': len(records_to_firehose),
        'errorCount': error_count
    }

def enrich_log_event(log_event: Dict, log_data: Dict) -> Dict:
    """
    Enrich log events with additional metadata and parsing
    """
    enriched = {
        '@timestamp': datetime.datetime.fromtimestamp(
            log_event['timestamp'] / 1000
        ).isoformat() + 'Z',
        'message': log_event.get('message', ''),
        'log_group': log_data.get('logGroup', ''),
        'log_stream': log_data.get('logStream', ''),
        'aws_account_id': log_data.get('owner', ''),
        'aws_region': os.environ.get('AWS_REGION', ''),
        'source_type': determine_source_type(log_data.get('logGroup', ''))
    }
    
    # Parse structured logs (JSON)
    try:
        if log_event['message'].strip().startswith('{'):
            parsed_message = json.loads(log_event['message'])
            enriched['parsed_message'] = parsed_message
            
            # Extract common fields
            if 'level' in parsed_message:
                enriched['log_level'] = parsed_message['level'].upper()
            if 'timestamp' in parsed_message:
                enriched['original_timestamp'] = parsed_message['timestamp']
                
    except (json.JSONDecodeError, KeyError):
        pass
    
    # Extract log level from message
    if 'log_level' not in enriched:
        enriched['log_level'] = extract_log_level(log_event['message'])
    
    # Add security context for security-related logs
    if is_security_related(log_event['message'], log_data.get('logGroup', '')):
        enriched['security_event'] = True
        enriched['priority'] = 'high'
    
    return enriched

def determine_source_type(log_group: str) -> str:
    """Determine the type of service generating the logs"""
    if '/aws/lambda/' in log_group:
        return 'lambda'
    elif '/aws/apigateway/' in log_group:
        return 'api-gateway'
    elif '/aws/rds/' in log_group:
        return 'rds'
    elif '/aws/vpc/flowlogs' in log_group:
        return 'vpc-flow-logs'
    elif 'cloudtrail' in log_group.lower():
        return 'cloudtrail'
    else:
        return 'application'

def extract_log_level(message: str) -> str:
    """Extract log level from message content"""
    log_levels = ['ERROR', 'WARN', 'WARNING', 'INFO', 'DEBUG', 'TRACE']
    message_upper = message.upper()
    
    for level in log_levels:
        if level in message_upper:
            return level
    
    return 'INFO'

def is_security_related(message: str, log_group: str) -> bool:
    """Identify potentially security-related log events"""
    security_keywords = [
        'authentication failed', 'access denied', 'unauthorized',
        'security group', 'iam', 'login failed', 'brute force',
        'suspicious', 'blocked', 'firewall', 'intrusion'
    ]
    
    message_lower = message.lower()
    log_group_lower = log_group.lower()
    
    # Check for security keywords
    for keyword in security_keywords:
        if keyword in message_lower:
            return True
    
    # Security-related log groups
    if any(term in log_group_lower for term in ['cloudtrail', 'security', 'auth', 'iam']):
        return True
    
    return False
      `),
    });

    // Grant permissions to the Lambda function
    kinesisStream.grantRead(logProcessorFunction);
    backupBucket.grantReadWrite(logProcessorFunction);

    // Add permission to write to Firehose
    logProcessorFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['firehose:PutRecord', 'firehose:PutRecordBatch'],
        resources: [`arn:aws:firehose:${this.region}:${this.account}:deliverystream/*`],
      })
    );

    // Add permission to publish CloudWatch metrics
    logProcessorFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['cloudwatch:PutMetricData'],
        resources: ['*'],
      })
    );

    return logProcessorFunction;
  }

  /**
   * Creates Kinesis Data Firehose delivery stream to OpenSearch
   */
  private createFirehoseDeliveryStream(
    config: any,
    opensearchDomain: opensearch.Domain,
    backupBucket: s3.Bucket
  ): kinesisFirehose.CfnDeliveryStream {
    // Create IAM role for Firehose
    const firehoseRole = new iam.Role(this, 'FirehoseDeliveryRole', {
      assumedBy: new iam.ServicePrincipal('firehose.amazonaws.com'),
    });

    // Add permissions for OpenSearch
    firehoseRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['es:ESHttpPost', 'es:ESHttpPut'],
        resources: [`${opensearchDomain.domainArn}/*`],
      })
    );

    // Add permissions for S3 backup
    backupBucket.grantReadWrite(firehoseRole);

    // Add permissions for CloudWatch Logs
    firehoseRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['logs:PutLogEvents'],
        resources: [`arn:aws:logs:${this.region}:${this.account}:log-group:/aws/kinesisfirehose/*`],
      })
    );

    const deliveryStream = new kinesisFirehose.CfnDeliveryStream(this, 'FirehoseDeliveryStream', {
      deliveryStreamName: config.firehoseStreamName,
      deliveryStreamType: 'DirectPut',
      amazonopensearchserviceDestinationConfiguration: {
        roleArn: firehoseRole.roleArn,
        domainArn: opensearchDomain.domainArn,
        indexName: 'logs-%Y-%m-%d',
        indexRotationPeriod: 'OneDay',
        typeName: '_doc',
        retryDuration: 300,
        s3BackupMode: 'FailedDocumentsOnly',
        s3Configuration: {
          roleArn: firehoseRole.roleArn,
          bucketArn: backupBucket.bucketArn,
          prefix: 'failed-logs/',
          errorOutputPrefix: 'errors/',
          bufferingHints: {
            sizeInMBs: 5,
            intervalInSeconds: 300,
          },
          compressionFormat: 'GZIP',
        },
        processingConfiguration: {
          enabled: false,
        },
        cloudWatchLoggingOptions: {
          enabled: true,
          logGroupName: `/aws/kinesisfirehose/${config.firehoseStreamName}`,
        },
      },
    });

    return deliveryStream;
  }

  /**
   * Creates EventSourceMapping between Kinesis and Lambda
   */
  private createEventSourceMapping(): EventSourceMapping {
    return new EventSourceMapping(this, 'KinesisEventSourceMapping', {
      target: this.logProcessorFunction,
      eventSourceArn: this.kinesisStream.streamArn,
      startingPosition: lambda.StartingPosition.LATEST,
      batchSize: 100,
      maxBatchingWindow: cdk.Duration.seconds(10),
      retryAttempts: 3,
      parallelizationFactor: 1,
    });
  }

  /**
   * Creates CloudWatch alarms and SNS notifications for monitoring
   */
  private createMonitoringAndAlerting(alertEmail?: string): sns.Topic {
    // Create SNS topic for alerts
    const alertsTopic = new sns.Topic(this, 'AlertsTopic', {
      displayName: 'Centralized Logging Alerts',
    });

    // Add email subscription if provided
    if (alertEmail) {
      alertsTopic.addSubscription(new snsSubscriptions.EmailSubscription(alertEmail));
    }

    // Create CloudWatch alarms

    // Lambda function error alarm
    const lambdaErrorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
      metric: this.logProcessorFunction.metricErrors(),
      threshold: 5,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'Lambda function errors in log processing',
    });
    lambdaErrorAlarm.addAlarmAction(new cwActions.SnsAction(alertsTopic));

    // Lambda function duration alarm
    const lambdaDurationAlarm = new cloudwatch.Alarm(this, 'LambdaDurationAlarm', {
      metric: this.logProcessorFunction.metricDuration(),
      threshold: 60000, // 60 seconds
      evaluationPeriods: 3,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'Lambda function duration is too high',
    });
    lambdaDurationAlarm.addAlarmAction(new cwActions.SnsAction(alertsTopic));

    // Kinesis stream incoming records alarm (too few records might indicate an issue)
    const kinesisLowThroughputAlarm = new cloudwatch.Alarm(this, 'KinesisLowThroughputAlarm', {
      metric: this.kinesisStream.metricIncomingRecords({
        statistic: cloudwatch.Statistic.SUM,
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING,
      alarmDescription: 'Kinesis stream is receiving very few records',
    });
    kinesisLowThroughputAlarm.addAlarmAction(new cwActions.SnsAction(alertsTopic));

    // OpenSearch cluster health alarm
    const opensearchHealthAlarm = new cloudwatch.Alarm(this, 'OpenSearchHealthAlarm', {
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ES',
        metricName: 'ClusterStatus.red',
        dimensionsMap: {
          DomainName: this.opensearchDomain.domainName,
          ClientId: this.account,
        },
        statistic: cloudwatch.Statistic.MAXIMUM,
        period: cdk.Duration.minutes(1),
      }),
      threshold: 0,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'OpenSearch cluster is in red status',
    });
    opensearchHealthAlarm.addAlarmAction(new cwActions.SnsAction(alertsTopic));

    return alertsTopic;
  }

  /**
   * Creates IAM role for CloudWatch Logs to write to Kinesis
   */
  private createCloudWatchLogsRole(): iam.Role {
    const role = new iam.Role(this, 'CloudWatchLogsRole', {
      assumedBy: new iam.ServicePrincipal('logs.amazonaws.com'),
    });

    role.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['kinesis:PutRecord', 'kinesis:PutRecords'],
        resources: [this.kinesisStream.streamArn],
      })
    );

    return role;
  }

  /**
   * Creates CloudFormation outputs for the stack
   */
  private createOutputs(config: any): void {
    new cdk.CfnOutput(this, 'OpenSearchDomainEndpoint', {
      value: this.opensearchDomain.domainEndpoint,
      description: 'OpenSearch domain endpoint for accessing OpenSearch Dashboards',
      exportName: `${this.stackName}-OpenSearchEndpoint`,
    });

    new cdk.CfnOutput(this, 'OpenSearchDashboardsUrl', {
      value: `https://${this.opensearchDomain.domainEndpoint}/_dashboards/`,
      description: 'URL for OpenSearch Dashboards',
      exportName: `${this.stackName}-DashboardsUrl`,
    });

    new cdk.CfnOutput(this, 'KinesisStreamName', {
      value: this.kinesisStream.streamName,
      description: 'Kinesis Data Stream name for log ingestion',
      exportName: `${this.stackName}-KinesisStreamName`,
    });

    new cdk.CfnOutput(this, 'KinesisStreamArn', {
      value: this.kinesisStream.streamArn,
      description: 'Kinesis Data Stream ARN for CloudWatch Logs subscription filters',
      exportName: `${this.stackName}-KinesisStreamArn`,
    });

    new cdk.CfnOutput(this, 'LogProcessorFunctionName', {
      value: this.logProcessorFunction.functionName,
      description: 'Lambda function name for log processing',
      exportName: `${this.stackName}-LogProcessorFunction`,
    });

    new cdk.CfnOutput(this, 'BackupBucketName', {
      value: this.backupBucket.bucketName,
      description: 'S3 bucket for backup storage of failed log deliveries',
      exportName: `${this.stackName}-BackupBucket`,
    });

    new cdk.CfnOutput(this, 'FirehoseDeliveryStreamName', {
      value: this.firehoseDeliveryStream.deliveryStreamName!,
      description: 'Kinesis Data Firehose delivery stream name',
      exportName: `${this.stackName}-FirehoseStream`,
    });

    new cdk.CfnOutput(this, 'AlertsTopicArn', {
      value: this.alertsTopic.topicArn,
      description: 'SNS topic ARN for centralized logging alerts',
      exportName: `${this.stackName}-AlertsTopic`,
    });

    // Output sample CLI commands for setting up subscription filters
    new cdk.CfnOutput(this, 'SampleSubscriptionFilterCommand', {
      value: `aws logs put-subscription-filter --log-group-name "/aws/lambda/my-function" --filter-name "CentralLoggingFilter" --filter-pattern "" --destination-arn "${this.kinesisStream.streamArn}" --role-arn "CLOUDWATCH_LOGS_ROLE_ARN"`,
      description: 'Sample CLI command to create CloudWatch Logs subscription filter',
    });
  }
}

/**
 * Main CDK application
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const domainName = app.node.tryGetContext('domainName');
const alertEmail = app.node.tryGetContext('alertEmail') || process.env.ALERT_EMAIL;
const environment = app.node.tryGetContext('environment') || 'dev';

new CentralizedLoggingStack(app, `CentralizedLoggingStack-${environment}`, {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
  },
  description: 'Centralized logging solution with Amazon OpenSearch Service, Kinesis, and Lambda',
  domainName,
  alertEmail,
  tags: {
    Project: 'CentralizedLogging',
    Environment: environment,
    ManagedBy: 'CDK',
  },
});

app.synth();