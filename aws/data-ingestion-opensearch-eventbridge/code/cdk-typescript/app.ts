#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as opensearch from 'aws-cdk-lib/aws-opensearchservice';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as scheduler from 'aws-cdk-lib/aws-scheduler';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * CDK Stack for Automated Data Ingestion Pipelines with OpenSearch and EventBridge
 * 
 * This stack creates:
 * - S3 bucket for data storage with encryption and versioning
 * - OpenSearch domain for analytics and search capabilities
 * - IAM roles for OpenSearch Ingestion and EventBridge Scheduler
 * - EventBridge Scheduler for automated pipeline management
 * - CloudWatch Log Groups for monitoring and debugging
 */
export class AutomatedDataIngestionStack extends cdk.Stack {
  public readonly bucket: s3.Bucket;
  public readonly openSearchDomain: opensearch.Domain;
  public readonly ingestionRole: iam.Role;
  public readonly schedulerRole: iam.Role;
  public readonly scheduleGroup: scheduler.CfnScheduleGroup;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().substring(0, 8);

    // Create S3 bucket for data storage
    this.bucket = this.createDataBucket(uniqueSuffix);

    // Create OpenSearch domain for analytics
    this.openSearchDomain = this.createOpenSearchDomain(uniqueSuffix);

    // Create IAM roles for services
    this.ingestionRole = this.createIngestionRole();
    this.schedulerRole = this.createSchedulerRole();

    // Create EventBridge Scheduler resources
    this.scheduleGroup = this.createScheduleGroup(uniqueSuffix);
    this.createPipelineSchedules();

    // Create CloudWatch Log Groups for monitoring
    this.createLogGroups();

    // Output important values
    this.createOutputs();
  }

  /**
   * Creates an S3 bucket with security best practices for data storage
   */
  private createDataBucket(uniqueSuffix: string): s3.Bucket {
    const bucket = new s3.Bucket(this, 'DataIngestionBucket', {
      bucketName: `data-ingestion-${uniqueSuffix}`,
      // Enable versioning for data protection
      versioned: true,
      // Enable server-side encryption
      encryption: s3.BucketEncryption.S3_MANAGED,
      // Enable secure transport only
      enforceSSL: true,
      // Block public access for security
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      // Lifecycle rules for cost optimization
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
          ],
        },
      ],
      // Automatic cleanup for old versions
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Add notification configuration for ingestion triggers
    bucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new cdk.aws_s3_notifications.SqsDestination(
        new cdk.aws_sqs.Queue(this, 'IngestionQueue', {
          queueName: `ingestion-queue-${uniqueSuffix}`,
          visibilityTimeout: cdk.Duration.minutes(5),
          retentionPeriod: cdk.Duration.days(14),
        })
      ),
      { prefix: 'logs/' }
    );

    // Tag the bucket for cost allocation and governance
    cdk.Tags.of(bucket).add('Environment', 'Development');
    cdk.Tags.of(bucket).add('Project', 'DataIngestion');
    cdk.Tags.of(bucket).add('Purpose', 'RawDataStorage');

    return bucket;
  }

  /**
   * Creates an OpenSearch domain with security and performance configurations
   */
  private createOpenSearchDomain(uniqueSuffix: string): opensearch.Domain {
    const domain = new opensearch.Domain(this, 'AnalyticsDomain', {
      domainName: `analytics-domain-${uniqueSuffix}`,
      // Use latest OpenSearch version
      version: opensearch.EngineVersion.OPENSEARCH_2_3,
      // Configure cluster for development workloads
      capacity: {
        dataNodes: 1,
        dataNodeInstanceType: 't3.small.search',
        masterNodes: 0, // No dedicated master for development
      },
      // Configure EBS storage
      ebs: {
        volumeSize: 20,
        volumeType: cdk.aws_ec2.EbsDeviceVolumeType.GP3,
      },
      // Enable encryption for security
      encryptionAtRest: {
        enabled: true,
      },
      nodeToNodeEncryption: true,
      enforceHttps: true,
      // Configure access policy
      accessPolicies: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          principals: [new iam.AccountRootPrincipal()],
          actions: ['es:*'],
          resources: ['*'],
        }),
      ],
      // Enable fine-grained access control
      fineGrainedAccessControl: {
        masterUserArn: `arn:aws:iam::${cdk.Stack.of(this).account}:root`,
      },
      // Configure logging
      logging: {
        slowSearchLogEnabled: true,
        appLogEnabled: true,
        slowIndexLogEnabled: true,
      },
      // Automatic cleanup for development
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Tag the domain
    cdk.Tags.of(domain).add('Environment', 'Development');
    cdk.Tags.of(domain).add('Project', 'DataIngestion');
    cdk.Tags.of(domain).add('Purpose', 'Analytics');

    return domain;
  }

  /**
   * Creates IAM role for OpenSearch Ingestion pipeline
   */
  private createIngestionRole(): iam.Role {
    const role = new iam.Role(this, 'OpenSearchIngestionRole', {
      roleName: `OpenSearchIngestionRole-${cdk.Names.uniqueId(this).substring(0, 8)}`,
      assumedBy: new iam.ServicePrincipal('osis-pipelines.amazonaws.com'),
      description: 'IAM role for OpenSearch Ingestion pipeline operations',
    });

    // Add policy for S3 access
    role.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['s3:GetObject', 's3:ListBucket'],
        resources: [this.bucket.bucketArn, `${this.bucket.bucketArn}/*`],
      })
    );

    // Add policy for OpenSearch access
    role.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['es:ESHttpPost', 'es:ESHttpPut'],
        resources: [`${this.openSearchDomain.domainArn}/*`],
      })
    );

    // Add policy for CloudWatch Logs
    role.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'logs:CreateLogGroup',
          'logs:CreateLogStream',
          'logs:PutLogEvents',
          'logs:DescribeLogGroups',
          'logs:DescribeLogStreams',
        ],
        resources: [`arn:aws:logs:${cdk.Stack.of(this).region}:${cdk.Stack.of(this).account}:*`],
      })
    );

    return role;
  }

  /**
   * Creates IAM role for EventBridge Scheduler
   */
  private createSchedulerRole(): iam.Role {
    const role = new iam.Role(this, 'EventBridgeSchedulerRole', {
      roleName: `EventBridgeSchedulerRole-${cdk.Names.uniqueId(this).substring(0, 8)}`,
      assumedBy: new iam.ServicePrincipal('scheduler.amazonaws.com'),
      description: 'IAM role for EventBridge Scheduler to manage OpenSearch Ingestion pipelines',
    });

    // Add policy for OpenSearch Ingestion pipeline control
    role.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'osis:StartPipeline',
          'osis:StopPipeline',
          'osis:GetPipeline',
        ],
        resources: [
          `arn:aws:osis:${cdk.Stack.of(this).region}:${cdk.Stack.of(this).account}:pipeline/*`,
        ],
      })
    );

    return role;
  }

  /**
   * Creates EventBridge Scheduler schedule group
   */
  private createScheduleGroup(uniqueSuffix: string): scheduler.CfnScheduleGroup {
    const scheduleGroup = new scheduler.CfnScheduleGroup(this, 'IngestionScheduleGroup', {
      name: `ingestion-schedules-${uniqueSuffix}`,
      tags: [
        {
          key: 'Environment',
          value: 'Development',
        },
        {
          key: 'Service',
          value: 'DataIngestion',
        },
      ],
    });

    return scheduleGroup;
  }

  /**
   * Creates pipeline start and stop schedules
   */
  private createPipelineSchedules(): void {
    // Note: Pipeline name will need to be provided as a parameter or created separately
    // as OpenSearch Ingestion pipelines are not yet supported in CDK
    const pipelineName = `data-pipeline-${cdk.Names.uniqueId(this).substring(0, 8)}`;

    // Schedule to start pipeline daily at 8 AM UTC
    new scheduler.CfnSchedule(this, 'StartPipelineSchedule', {
      name: 'start-ingestion-pipeline',
      groupName: this.scheduleGroup.name,
      scheduleExpression: 'cron(0 8 * * ? *)',
      target: {
        arn: `arn:aws:osis:${cdk.Stack.of(this).region}:${cdk.Stack.of(this).account}:pipeline/${pipelineName}`,
        roleArn: this.schedulerRole.roleArn,
        input: JSON.stringify({ action: 'start' }),
        retryPolicy: {
          maximumRetryAttempts: 3,
          maximumEventAge: 3600,
        },
      },
      flexibleTimeWindow: {
        mode: 'FLEXIBLE',
        maximumWindowInMinutes: 15,
      },
      description: 'Daily start of data ingestion pipeline at 8 AM UTC',
    });

    // Schedule to stop pipeline daily at 6 PM UTC
    new scheduler.CfnSchedule(this, 'StopPipelineSchedule', {
      name: 'stop-ingestion-pipeline',
      groupName: this.scheduleGroup.name,
      scheduleExpression: 'cron(0 18 * * ? *)',
      target: {
        arn: `arn:aws:osis:${cdk.Stack.of(this).region}:${cdk.Stack.of(this).account}:pipeline/${pipelineName}`,
        roleArn: this.schedulerRole.roleArn,
        input: JSON.stringify({ action: 'stop' }),
        retryPolicy: {
          maximumRetryAttempts: 3,
          maximumEventAge: 3600,
        },
      },
      flexibleTimeWindow: {
        mode: 'FLEXIBLE',
        maximumWindowInMinutes: 15,
      },
      description: 'Daily stop of data ingestion pipeline at 6 PM UTC',
    });
  }

  /**
   * Creates CloudWatch Log Groups for monitoring
   */
  private createLogGroups(): void {
    // Log group for OpenSearch Ingestion pipeline
    new logs.LogGroup(this, 'IngestionPipelineLogGroup', {
      logGroupName: '/aws/opensearch/ingestion/pipeline',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Log group for EventBridge Scheduler
    new logs.LogGroup(this, 'SchedulerLogGroup', {
      logGroupName: '/aws/events/scheduler',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
  }

  /**
   * Creates stack outputs for important values
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'BucketName', {
      value: this.bucket.bucketName,
      description: 'Name of the S3 bucket for data storage',
      exportName: `${cdk.Stack.of(this).stackName}-BucketName`,
    });

    new cdk.CfnOutput(this, 'OpenSearchDomainName', {
      value: this.openSearchDomain.domainName,
      description: 'Name of the OpenSearch domain',
      exportName: `${cdk.Stack.of(this).stackName}-OpenSearchDomainName`,
    });

    new cdk.CfnOutput(this, 'OpenSearchDomainEndpoint', {
      value: this.openSearchDomain.domainEndpoint,
      description: 'Endpoint of the OpenSearch domain',
      exportName: `${cdk.Stack.of(this).stackName}-OpenSearchDomainEndpoint`,
    });

    new cdk.CfnOutput(this, 'IngestionRoleArn', {
      value: this.ingestionRole.roleArn,
      description: 'ARN of the IAM role for OpenSearch Ingestion',
      exportName: `${cdk.Stack.of(this).stackName}-IngestionRoleArn`,
    });

    new cdk.CfnOutput(this, 'SchedulerRoleArn', {
      value: this.schedulerRole.roleArn,
      description: 'ARN of the IAM role for EventBridge Scheduler',
      exportName: `${cdk.Stack.of(this).stackName}-SchedulerRoleArn`,
    });

    new cdk.CfnOutput(this, 'ScheduleGroupName', {
      value: this.scheduleGroup.name!,
      description: 'Name of the EventBridge Scheduler schedule group',
      exportName: `${cdk.Stack.of(this).stackName}-ScheduleGroupName`,
    });

    // Output sample CLI commands for pipeline creation
    new cdk.CfnOutput(this, 'PipelineCreationCommand', {
      value: `aws osis create-pipeline --pipeline-name data-pipeline-\${SUFFIX} --min-units 1 --max-units 4 --pipeline-configuration-body file://pipeline-config.yaml`,
      description: 'Sample CLI command to create OpenSearch Ingestion pipeline',
    });
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Create the stack with environment configuration
new AutomatedDataIngestionStack(app, 'AutomatedDataIngestionStack', {
  description: 'Automated Data Ingestion Pipelines with OpenSearch Ingestion and EventBridge Scheduler',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'DataIngestion',
    Environment: 'Development',
    ManagedBy: 'CDK',
  },
});

// Add stack-level tags
cdk.Tags.of(app).add('Project', 'AutomatedDataIngestion');
cdk.Tags.of(app).add('Repository', 'recipes');
cdk.Tags.of(app).add('CDKVersion', '2.100.0');