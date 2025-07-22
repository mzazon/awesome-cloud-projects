#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as opensearch from 'aws-cdk-lib/aws-opensearchservice';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import { Construct } from 'constructs';

/**
 * Properties for the OpenSearch Search Solutions Stack
 */
interface OpenSearchStackProps extends cdk.StackProps {
  /** Domain name for the OpenSearch cluster */
  domainName?: string;
  /** Instance type for data nodes */
  instanceType?: string;
  /** Number of data nodes */
  instanceCount?: number;
  /** Instance type for dedicated master nodes */
  masterInstanceType?: string;
  /** Number of dedicated master nodes */
  masterInstanceCount?: number;
  /** EBS volume size in GB */
  volumeSize?: number;
  /** Environment name for resource tagging */
  environment?: string;
}

/**
 * AWS CDK Stack for Amazon OpenSearch Service Search Solutions
 * 
 * This stack creates a production-ready OpenSearch domain with:
 * - Multi-AZ deployment with dedicated master nodes
 * - Automated data indexing pipeline using Lambda
 * - Comprehensive monitoring and alerting
 * - Security best practices with encryption and fine-grained access control
 * - S3 integration for data storage and processing
 */
export class OpenSearchSearchSolutionsStack extends cdk.Stack {
  /** The OpenSearch domain */
  public readonly domain: opensearch.Domain;
  
  /** S3 bucket for data storage */
  public readonly dataBucket: s3.Bucket;
  
  /** Lambda function for data indexing */
  public readonly indexerFunction: lambda.Function;
  
  /** CloudWatch dashboard for monitoring */
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: OpenSearchStackProps = {}) {
    super(scope, id, props);

    // Extract configuration with defaults
    const domainName = props.domainName || 'search-solutions-domain';
    const instanceType = props.instanceType || 'm6g.large.search';
    const instanceCount = props.instanceCount || 3;
    const masterInstanceType = props.masterInstanceType || 'm6g.medium.search';
    const masterInstanceCount = props.masterInstanceCount || 3;
    const volumeSize = props.volumeSize || 100;
    const environment = props.environment || 'production';

    // Create S3 bucket for data storage
    this.dataBucket = this.createDataBucket(environment);

    // Create IAM role for OpenSearch Service
    const openSearchServiceRole = this.createOpenSearchServiceRole();

    // Create CloudWatch log groups for OpenSearch logging
    const logGroups = this.createLogGroups(domainName);

    // Create the OpenSearch domain
    this.domain = this.createOpenSearchDomain({
      domainName,
      instanceType,
      instanceCount,
      masterInstanceType,
      masterInstanceCount,
      volumeSize,
      environment,
      logGroups,
      serviceRole: openSearchServiceRole
    });

    // Create Lambda function for data indexing
    this.indexerFunction = this.createIndexerLambda(environment);

    // Configure S3 event notifications to trigger Lambda
    this.configureS3EventNotifications();

    // Create CloudWatch dashboard and alarms
    this.dashboard = this.createMonitoringDashboard(domainName);
    this.createCloudWatchAlarms(domainName);

    // Output important information
    this.createOutputs();

    // Apply consistent tags
    this.applyTags(environment);
  }

  /**
   * Creates an S3 bucket for storing data files
   */
  private createDataBucket(environment: string): s3.Bucket {
    return new s3.Bucket(this, 'DataBucket', {
      bucketName: `opensearch-data-${environment}-${this.account}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'delete-old-versions',
          noncurrentVersionExpiration: cdk.Duration.days(30),
          enabled: true
        }
      ],
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      notificationsHandlerRole: undefined // Will be set later
    });
  }

  /**
   * Creates IAM role for OpenSearch Service
   */
  private createOpenSearchServiceRole(): iam.Role {
    return new iam.Role(this, 'OpenSearchServiceRole', {
      assumedBy: new iam.ServicePrincipal('opensearch.amazonaws.com'),
      description: 'IAM role for OpenSearch Service domain',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonOpenSearchServiceRolePolicy')
      ]
    });
  }

  /**
   * Creates CloudWatch log groups for OpenSearch logging
   */
  private createLogGroups(domainName: string): { indexSlowLogs: logs.LogGroup; searchSlowLogs: logs.LogGroup; applicationLogs: logs.LogGroup } {
    const indexSlowLogs = new logs.LogGroup(this, 'IndexSlowLogs', {
      logGroupName: `/aws/opensearch/domains/${domainName}/index-slow-logs`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    const searchSlowLogs = new logs.LogGroup(this, 'SearchSlowLogs', {
      logGroupName: `/aws/opensearch/domains/${domainName}/search-slow-logs`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    const applicationLogs = new logs.LogGroup(this, 'ApplicationLogs', {
      logGroupName: `/aws/opensearch/domains/${domainName}/application-logs`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    return { indexSlowLogs, searchSlowLogs, applicationLogs };
  }

  /**
   * Creates the OpenSearch domain with production-ready configuration
   */
  private createOpenSearchDomain(config: {
    domainName: string;
    instanceType: string;
    instanceCount: number;
    masterInstanceType: string;
    masterInstanceCount: number;
    volumeSize: number;
    environment: string;
    logGroups: { indexSlowLogs: logs.LogGroup; searchSlowLogs: logs.LogGroup; applicationLogs: logs.LogGroup };
    serviceRole: iam.Role;
  }): opensearch.Domain {
    
    // Create access policy for the domain
    const accessPolicy = new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          principals: [new iam.AccountRootPrincipal()],
          actions: ['es:*'],
          resources: [`arn:aws:es:${this.region}:${this.account}:domain/${config.domainName}/*`]
        })
      ]
    });

    return new opensearch.Domain(this, 'OpenSearchDomain', {
      domainName: config.domainName,
      version: opensearch.EngineVersion.OPENSEARCH_2_11,
      
      // Cluster configuration with dedicated masters and multi-AZ
      capacity: {
        masterNodes: config.masterInstanceCount,
        masterNodeInstanceType: config.masterInstanceType,
        dataNodes: config.instanceCount,
        dataNodeInstanceType: config.instanceType,
        multiAzWithStandbyEnabled: false // Use traditional multi-AZ for this recipe
      },

      // EBS configuration with GP3 for optimal performance
      ebs: {
        volumeSize: config.volumeSize,
        volumeType: cdk.aws_ec2.EbsDeviceVolumeType.GP3,
        iops: 3000,
        throughput: 125
      },

      // Zone awareness for high availability
      zoneAwareness: {
        enabled: true,
        availabilityZoneCount: 3
      },

      // Security configuration
      encryptionAtRest: {
        enabled: true
      },
      nodeToNodeEncryption: true,
      enforceHttps: true,
      tlsSecurityPolicy: opensearch.TLSSecurityPolicy.TLS_1_2,

      // Fine-grained access control
      fineGrainedAccessControl: {
        masterUserName: 'admin',
        masterUserPassword: cdk.SecretValue.unsafePlainText('TempPassword123!') // In production, use Secrets Manager
      },

      // Access policies
      accessPolicies: [accessPolicy],

      // Logging configuration
      logging: {
        slowSearchLogEnabled: true,
        slowSearchLogGroup: config.logGroups.searchSlowLogs,
        slowIndexLogEnabled: true,
        slowIndexLogGroup: config.logGroups.indexSlowLogs,
        appLogEnabled: true,
        appLogGroup: config.logGroups.applicationLogs
      },

      // Advanced options for better performance
      advancedOptions: {
        'rest.action.multi.allow_explicit_index': 'true',
        'indices.fielddata.cache.size': '20%',
        'indices.query.bool.max_clause_count': '1024'
      },

      // Automated snapshots
      automatedSnapshotStartHour: 2,

      // Removal policy for development (change to RETAIN for production)
      removalPolicy: config.environment === 'production' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY
    });
  }

  /**
   * Creates Lambda function for automated data indexing
   */
  private createIndexerLambda(environment: string): lambda.Function {
    // Create execution role for Lambda
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for OpenSearch indexer Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        S3Access: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:GetObject', 's3:ListBucket'],
              resources: [
                this.dataBucket.bucketArn,
                `${this.dataBucket.bucketArn}/*`
              ]
            })
          ]
        }),
        OpenSearchAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'es:ESHttpPost',
                'es:ESHttpPut',
                'es:ESHttpGet',
                'es:ESHttpDelete'
              ],
              resources: [`${this.domain.domainArn}/*`]
            })
          ]
        })
      }
    });

    // Lambda function code
    const lambdaCode = `
import json
import boto3
import urllib3
from urllib3.util.retry import Retry
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Create HTTP pool manager with retry strategy
retry_strategy = Retry(
    total=3,
    backoff_factor=1,
    status_forcelist=[429, 500, 502, 503, 504]
)
http = urllib3.PoolManager(retries=retry_strategy)

def lambda_handler(event, context):
    """
    Lambda function to index data from S3 into OpenSearch
    """
    try:
        # Get OpenSearch endpoint from environment
        opensearch_endpoint = os.environ['OPENSEARCH_ENDPOINT']
        
        # Process S3 event records
        if 'Records' in event:
            s3_client = boto3.client('s3')
            
            for record in event['Records']:
                bucket_name = record['s3']['bucket']['name']
                object_key = record['s3']['object']['key']
                
                logger.info(f"Processing file: s3://{bucket_name}/{object_key}")
                
                # Download and parse JSON data from S3
                try:
                    response = s3_client.get_object(Bucket=bucket_name, Key=object_key)
                    content = response['Body'].read().decode('utf-8')
                    data = json.loads(content)
                    
                    # Handle both single documents and arrays
                    documents = data if isinstance(data, list) else [data]
                    
                    # Index each document
                    for doc in documents:
                        if 'id' in doc:
                            index_document(opensearch_endpoint, doc)
                        else:
                            logger.warning(f"Document missing 'id' field: {doc}")
                            
                except Exception as e:
                    logger.error(f"Error processing S3 object {object_key}: {str(e)}")
                    raise
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data indexing completed successfully',
                'processed_records': len(event.get('Records', []))
            })
        }
        
    except Exception as e:
        logger.error(f"Lambda execution failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def index_document(endpoint, document):
    """
    Index a single document into OpenSearch
    """
    try:
        doc_id = document['id']
        index_name = 'products'  # Default index name
        
        # Construct the URL for document indexing
        url = f"https://{endpoint}/{index_name}/_doc/{doc_id}"
        
        # Prepare headers
        headers = {
            'Content-Type': 'application/json'
        }
        
        # Make PUT request to index the document
        response = http.request(
            'PUT',
            url,
            headers=headers,
            body=json.dumps(document)
        )
        
        if response.status in [200, 201]:
            logger.info(f"Successfully indexed document {doc_id}")
        else:
            logger.error(f"Failed to index document {doc_id}: HTTP {response.status}")
            logger.error(f"Response: {response.data.decode()}")
            
    except Exception as e:
        logger.error(f"Error indexing document {document.get('id', 'unknown')}: {str(e)}")
        raise
`;

    return new lambda.Function(this, 'IndexerFunction', {
      functionName: `opensearch-indexer-${environment}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(lambdaCode),
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      environment: {
        OPENSEARCH_ENDPOINT: this.domain.domainEndpoint
      },
      description: 'Automatically indexes data from S3 into OpenSearch Service'
    });
  }

  /**
   * Configures S3 event notifications to trigger Lambda indexing
   */
  private configureS3EventNotifications(): void {
    this.dataBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(this.indexerFunction),
      { suffix: '.json' }
    );
  }

  /**
   * Creates CloudWatch dashboard for monitoring
   */
  private createMonitoringDashboard(domainName: string): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'OpenSearchDashboard', {
      dashboardName: `OpenSearch-${domainName}-Dashboard`
    });

    // Performance metrics widget
    const performanceWidget = new cloudwatch.GraphWidget({
      title: 'OpenSearch Performance Metrics',
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/ES',
          metricName: 'SearchLatency',
          dimensionsMap: {
            DomainName: domainName,
            ClientId: this.account
          },
          statistic: 'Average'
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/ES',
          metricName: 'IndexingLatency',
          dimensionsMap: {
            DomainName: domainName,
            ClientId: this.account
          },
          statistic: 'Average'
        })
      ],
      right: [
        new cloudwatch.Metric({
          namespace: 'AWS/ES',
          metricName: 'SearchRate',
          dimensionsMap: {
            DomainName: domainName,
            ClientId: this.account
          },
          statistic: 'Average'
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/ES',
          metricName: 'IndexingRate',
          dimensionsMap: {
            DomainName: domainName,
            ClientId: this.account
          },
          statistic: 'Average'
        })
      ]
    });

    // Cluster health widget
    const healthWidget = new cloudwatch.GraphWidget({
      title: 'OpenSearch Cluster Health',
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/ES',
          metricName: 'ClusterStatus.yellow',
          dimensionsMap: {
            DomainName: domainName,
            ClientId: this.account
          },
          statistic: 'Maximum'
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/ES',
          metricName: 'ClusterStatus.red',
          dimensionsMap: {
            DomainName: domainName,
            ClientId: this.account
          },
          statistic: 'Maximum'
        })
      ],
      right: [
        new cloudwatch.Metric({
          namespace: 'AWS/ES',
          metricName: 'StorageUtilization',
          dimensionsMap: {
            DomainName: domainName,
            ClientId: this.account
          },
          statistic: 'Average'
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/ES',
          metricName: 'CPUUtilization',
          dimensionsMap: {
            DomainName: domainName,
            ClientId: this.account
          },
          statistic: 'Average'
        })
      ]
    });

    dashboard.addWidgets(performanceWidget, healthWidget);
    return dashboard;
  }

  /**
   * Creates CloudWatch alarms for monitoring
   */
  private createCloudWatchAlarms(domainName: string): void {
    // High search latency alarm
    new cloudwatch.Alarm(this, 'HighSearchLatencyAlarm', {
      alarmName: `OpenSearch-High-Search-Latency-${domainName}`,
      alarmDescription: 'Alert when search latency exceeds 1000ms',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ES',
        metricName: 'SearchLatency',
        dimensionsMap: {
          DomainName: domainName,
          ClientId: this.account
        },
        statistic: 'Average'
      }),
      threshold: 1000,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
    });

    // Cluster status red alarm
    new cloudwatch.Alarm(this, 'ClusterStatusRedAlarm', {
      alarmName: `OpenSearch-Cluster-Status-Red-${domainName}`,
      alarmDescription: 'Alert when cluster status is red',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ES',
        metricName: 'ClusterStatus.red',
        dimensionsMap: {
          DomainName: domainName,
          ClientId: this.account
        },
        statistic: 'Maximum'
      }),
      threshold: 0,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
    });

    // High storage utilization alarm
    new cloudwatch.Alarm(this, 'HighStorageUtilizationAlarm', {
      alarmName: `OpenSearch-High-Storage-Utilization-${domainName}`,
      alarmDescription: 'Alert when storage utilization exceeds 85%',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ES',
        metricName: 'StorageUtilization',
        dimensionsMap: {
          DomainName: domainName,
          ClientId: this.account
        },
        statistic: 'Average'
      }),
      threshold: 85,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
    });
  }

  /**
   * Creates CloudFormation outputs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'OpenSearchDomainEndpoint', {
      value: this.domain.domainEndpoint,
      description: 'OpenSearch domain endpoint URL',
      exportName: `${this.stackName}-OpenSearchEndpoint`
    });

    new cdk.CfnOutput(this, 'OpenSearchDomainArn', {
      value: this.domain.domainArn,
      description: 'OpenSearch domain ARN',
      exportName: `${this.stackName}-OpenSearchArn`
    });

    new cdk.CfnOutput(this, 'OpenSearchDashboardsUrl', {
      value: `https://${this.domain.domainEndpoint}/_dashboards/`,
      description: 'OpenSearch Dashboards URL',
      exportName: `${this.stackName}-DashboardsUrl`
    });

    new cdk.CfnOutput(this, 'DataBucketName', {
      value: this.dataBucket.bucketName,
      description: 'S3 bucket name for data storage',
      exportName: `${this.stackName}-DataBucket`
    });

    new cdk.CfnOutput(this, 'IndexerFunctionName', {
      value: this.indexerFunction.functionName,
      description: 'Lambda function name for data indexing',
      exportName: `${this.stackName}-IndexerFunction`
    });

    new cdk.CfnOutput(this, 'CloudWatchDashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL',
      exportName: `${this.stackName}-DashboardUrl`
    });
  }

  /**
   * Applies consistent tags to all resources
   */
  private applyTags(environment: string): void {
    cdk.Tags.of(this).add('Project', 'OpenSearch-Search-Solutions');
    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('CreatedBy', 'CDK');
    cdk.Tags.of(this).add('Recipe', 'search-solutions-amazon-opensearch-service');
  }
}

/**
 * CDK Application
 */
const app = new cdk.App();

// Get configuration from context or use defaults
const environment = app.node.tryGetContext('environment') || 'development';
const domainName = app.node.tryGetContext('domainName') || `search-demo-${environment}`;

new OpenSearchSearchSolutionsStack(app, 'OpenSearchSearchSolutionsStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'AWS CDK Stack for Amazon OpenSearch Service Search Solutions (Recipe: search-solutions-amazon-opensearch-service)',
  domainName: domainName,
  environment: environment,
  stackName: `opensearch-search-solutions-${environment}`
});

app.synth();