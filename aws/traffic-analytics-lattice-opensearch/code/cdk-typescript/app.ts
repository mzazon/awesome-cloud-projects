#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as opensearch from 'aws-cdk-lib/aws-opensearchservice';
import * as kinesis from 'aws-cdk-lib/aws-kinesisfirehose';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as vpclattice from 'aws-cdk-lib/aws-vpclattice';
import { Construct } from 'constructs';

/**
 * Properties for the TrafficAnalyticsStack
 */
interface TrafficAnalyticsStackProps extends cdk.StackProps {
  readonly domainName?: string;
  readonly firehoseStreamName?: string;
  readonly serviceNetworkName?: string;
  readonly backupBucketName?: string;
}

/**
 * CDK Stack for VPC Lattice Traffic Analytics with OpenSearch
 * 
 * This stack creates:
 * - OpenSearch Service domain for analytics
 * - Lambda function for log transformation
 * - Kinesis Data Firehose delivery stream
 * - S3 bucket for backup storage
 * - VPC Lattice service network and demo service
 * - Access log subscription configuration
 */
export class TrafficAnalyticsStack extends cdk.Stack {
  public readonly openSearchEndpoint: string;
  public readonly firehoseDeliveryStreamArn: string;
  public readonly serviceNetworkArn: string;

  constructor(scope: Construct, id: string, props?: TrafficAnalyticsStackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 6).toLowerCase();

    // Create S3 bucket for backup and error records
    const backupBucket = new s3.Bucket(this, 'BackupBucket', {
      bucketName: props?.backupBucketName || `vpc-lattice-backup-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      versioned: false,
      lifecycleRules: [
        {
          id: 'DeleteOldBackups',
          enabled: true,
          expiration: cdk.Duration.days(90),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create OpenSearch Service domain for traffic analytics
    const openSearchDomain = new opensearch.Domain(this, 'OpenSearchDomain', {
      domainName: props?.domainName || `traffic-analytics-${uniqueSuffix}`,
      version: opensearch.EngineVersion.OPENSEARCH_2_11,
      capacity: {
        dataNodes: 1,
        dataNodeInstanceType: 't3.small.search',
        masterNodes: 0,
      },
      ebs: {
        volumeSize: 20,
        volumeType: cdk.aws_ec2.EbsDeviceVolumeType.GP3,
      },
      nodeToNodeEncryption: true,
      encryptionAtRest: {
        enabled: true,
      },
      enforceHttps: true,
      logging: {
        slowSearchLogEnabled: true,
        appLogEnabled: true,
        slowIndexLogEnabled: true,
      },
      accessPolicies: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          principals: [new iam.AnyPrincipal()],
          actions: ['es:*'],
          resources: ['*'],
        }),
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Store OpenSearch endpoint for outputs
    this.openSearchEndpoint = openSearchDomain.domainEndpoint;

    // Create Lambda function for traffic log transformation
    const transformFunction = new lambda.Function(this, 'TransformFunction', {
      functionName: `traffic-transform-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      description: 'Transform VPC Lattice access logs for OpenSearch analytics',
      environment: {
        OPENSEARCH_ENDPOINT: openSearchDomain.domainEndpoint,
      },
      code: lambda.Code.fromInline(`
import json
import base64
import gzip
import datetime

def lambda_handler(event, context):
    output = []
    
    for record in event['records']:
        try:
            # Decode and decompress the data
            compressed_payload = base64.b64decode(record['data'])
            uncompressed_payload = gzip.decompress(compressed_payload)
            log_data = json.loads(uncompressed_payload)
            
            # Transform and enrich each log entry
            for log_entry in log_data.get('logEvents', []):
                try:
                    # Parse the log message if it's JSON
                    if log_entry['message'].startswith('{'):
                        parsed_log = json.loads(log_entry['message'])
                        
                        # Add timestamp and enrichment fields
                        parsed_log['@timestamp'] = datetime.datetime.fromtimestamp(
                            log_entry['timestamp'] / 1000
                        ).isoformat()
                        parsed_log['log_group'] = log_data.get('logGroup', '')
                        parsed_log['log_stream'] = log_data.get('logStream', '')
                        
                        # Add derived fields for analytics
                        if 'responseCode' in parsed_log:
                            parsed_log['response_class'] = str(parsed_log['responseCode'])[0] + 'xx'
                            parsed_log['is_error'] = parsed_log['responseCode'] >= 400
                        
                        if 'responseTimeMs' in parsed_log:
                            parsed_log['response_time_bucket'] = categorize_response_time(
                                parsed_log['responseTimeMs']
                            )
                        
                        output_record = {
                            'recordId': record['recordId'],
                            'result': 'Ok',
                            'data': base64.b64encode(
                                (json.dumps(parsed_log) + '\\n').encode('utf-8')
                            ).decode('utf-8')
                        }
                    else:
                        # If not JSON, pass through with minimal processing
                        enhanced_log = {
                            'message': log_entry['message'],
                            '@timestamp': datetime.datetime.fromtimestamp(
                                log_entry['timestamp'] / 1000
                            ).isoformat(),
                            'log_group': log_data.get('logGroup', ''),
                            'log_stream': log_data.get('logStream', '')
                        }
                        
                        output_record = {
                            'recordId': record['recordId'],
                            'result': 'Ok',
                            'data': base64.b64encode(
                                (json.dumps(enhanced_log) + '\\n').encode('utf-8')
                            ).decode('utf-8')
                        }
                    
                    output.append(output_record)
                    
                except Exception as e:
                    # If processing fails, mark as processing failure
                    output.append({
                        'recordId': record['recordId'],
                        'result': 'ProcessingFailed'
                    })
        
        except Exception as e:
            # If record processing fails entirely
            output.append({
                'recordId': record['recordId'],
                'result': 'ProcessingFailed'
            })
    
    return {'records': output}

def categorize_response_time(response_time_ms):
    """Categorize response times for analytics"""
    if response_time_ms < 100:
        return 'fast'
    elif response_time_ms < 500:
        return 'medium'
    elif response_time_ms < 2000:
        return 'slow'
    else:
        return 'very_slow'
      `),
    });

    // Create IAM role for Kinesis Data Firehose
    const firehoseRole = new iam.Role(this, 'FirehoseRole', {
      roleName: `firehose-opensearch-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('firehose.amazonaws.com'),
      inlinePolicies: {
        FirehoseOpenSearchPolicy: new iam.PolicyDocument({
          statements: [
            // OpenSearch permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'es:DescribeDomain',
                'es:DescribeDomains',
                'es:DescribeDomainConfig',
                'es:ESHttpPost',
                'es:ESHttpPut',
              ],
              resources: [openSearchDomain.domainArn, `${openSearchDomain.domainArn}/*`],
            }),
            // S3 permissions
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
              resources: [backupBucket.bucketArn, `${backupBucket.bucketArn}/*`],
            }),
            // Lambda permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'lambda:InvokeFunction',
                'lambda:GetFunctionConfiguration',
              ],
              resources: [transformFunction.functionArn],
            }),
            // CloudWatch Logs permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create CloudWatch Log Group for Firehose
    const firehoseLogGroup = new logs.LogGroup(this, 'FirehoseLogGroup', {
      logGroupName: `/aws/kinesisfirehose/${props?.firehoseStreamName || `vpc-lattice-stream-${uniqueSuffix}`}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create Kinesis Data Firehose delivery stream
    const deliveryStream = new kinesis.CfnDeliveryStream(this, 'DeliveryStream', {
      deliveryStreamName: props?.firehoseStreamName || `vpc-lattice-stream-${uniqueSuffix}`,
      deliveryStreamType: 'DirectPut',
      amazonopensearchserviceDestinationConfiguration: {
        roleArn: firehoseRole.roleArn,
        domainArn: openSearchDomain.domainArn,
        indexName: 'vpc-lattice-traffic',
        s3Configuration: {
          roleArn: firehoseRole.roleArn,
          bucketArn: backupBucket.bucketArn,
          prefix: 'firehose-backup/',
          bufferingHints: {
            sizeInMBs: 1,
            intervalInSeconds: 60,
          },
          compressionFormat: 'GZIP',
        },
        processingConfiguration: {
          enabled: true,
          processors: [
            {
              type: 'Lambda',
              parameters: [
                {
                  parameterName: 'LambdaArn',
                  parameterValue: transformFunction.functionArn,
                },
              ],
            },
          ],
        },
        cloudWatchLoggingOptions: {
          enabled: true,
          logGroupName: firehoseLogGroup.logGroupName,
        },
        bufferingHints: {
          sizeInMBs: 1,
          intervalInSeconds: 60,
        },
        retryOptions: {
          durationInSeconds: 3600,
        },
      },
    });

    // Store delivery stream ARN for outputs
    this.firehoseDeliveryStreamArn = deliveryStream.attrArn;

    // Create VPC Lattice service network
    const serviceNetwork = new vpclattice.CfnServiceNetwork(this, 'ServiceNetwork', {
      name: props?.serviceNetworkName || `demo-network-${uniqueSuffix}`,
      authType: 'AWS_IAM',
    });

    // Store service network ARN for outputs
    this.serviceNetworkArn = serviceNetwork.attrArn;

    // Create demo VPC Lattice service
    const demoService = new vpclattice.CfnService(this, 'DemoService', {
      name: `demo-service-${uniqueSuffix}`,
      authType: 'AWS_IAM',
    });

    // Associate demo service with service network
    new vpclattice.CfnServiceNetworkServiceAssociation(this, 'ServiceAssociation', {
      serviceNetworkIdentifier: serviceNetwork.attrId,
      serviceIdentifier: demoService.attrId,
    });

    // Create access log subscription for traffic capture
    new vpclattice.CfnAccessLogSubscription(this, 'AccessLogSubscription', {
      resourceIdentifier: serviceNetwork.attrArn,
      destinationArn: deliveryStream.attrArn,
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'TrafficAnalytics');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('Recipe', 'traffic-analytics-lattice-opensearch');

    // Outputs for verification and integration
    new cdk.CfnOutput(this, 'OpenSearchDomainEndpoint', {
      value: `https://${openSearchDomain.domainEndpoint}`,
      description: 'OpenSearch domain endpoint for traffic analytics',
      exportName: `${this.stackName}-OpenSearchEndpoint`,
    });

    new cdk.CfnOutput(this, 'OpenSearchDashboardsUrl', {
      value: `https://${openSearchDomain.domainEndpoint}/_dashboards`,
      description: 'OpenSearch Dashboards URL for visualization',
      exportName: `${this.stackName}-DashboardsUrl`,
    });

    new cdk.CfnOutput(this, 'FirehoseDeliveryStreamName', {
      value: deliveryStream.deliveryStreamName!,
      description: 'Kinesis Data Firehose delivery stream name',
      exportName: `${this.stackName}-FirehoseStreamName`,
    });

    new cdk.CfnOutput(this, 'ServiceNetworkArn', {
      value: serviceNetwork.attrArn,
      description: 'VPC Lattice service network ARN',
      exportName: `${this.stackName}-ServiceNetworkArn`,
    });

    new cdk.CfnOutput(this, 'ServiceNetworkId', {
      value: serviceNetwork.attrId,
      description: 'VPC Lattice service network ID',
      exportName: `${this.stackName}-ServiceNetworkId`,
    });

    new cdk.CfnOutput(this, 'BackupBucketName', {
      value: backupBucket.bucketName,
      description: 'S3 bucket for backup storage',
      exportName: `${this.stackName}-BackupBucket`,
    });

    new cdk.CfnOutput(this, 'TransformFunctionName', {
      value: transformFunction.functionName,
      description: 'Lambda function for log transformation',
      exportName: `${this.stackName}-TransformFunction`,
    });
  }
}

// Main CDK application
const app = new cdk.App();

// Get configuration from context or use defaults
const domainName = app.node.tryGetContext('domainName');
const firehoseStreamName = app.node.tryGetContext('firehoseStreamName');
const serviceNetworkName = app.node.tryGetContext('serviceNetworkName');
const backupBucketName = app.node.tryGetContext('backupBucketName');
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION,
};

// Create the stack
new TrafficAnalyticsStack(app, 'TrafficAnalyticsStack', {
  env,
  domainName,
  firehoseStreamName,
  serviceNetworkName,
  backupBucketName,
  description: 'VPC Lattice Traffic Analytics with OpenSearch - CDK TypeScript implementation',
  stackName: 'traffic-analytics-lattice-opensearch',
  tags: {
    Project: 'TrafficAnalytics',
    Recipe: 'traffic-analytics-lattice-opensearch',
    IaC: 'CDK-TypeScript',
  },
});

// Synthesize the app
app.synth();