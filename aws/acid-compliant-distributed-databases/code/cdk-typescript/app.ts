#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as qldb from 'aws-cdk-lib/aws-qldb';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as kinesis from 'aws-cdk-lib/aws-kinesis';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Properties for the QLDB Financial Ledger Stack
 */
interface QLDBFinancialLedgerStackProps extends cdk.StackProps {
  /**
   * Environment name for resource naming and tagging
   * @default 'production'
   */
  readonly environmentName?: string;
  
  /**
   * Application name for resource naming and tagging
   * @default 'financial'
   */
  readonly applicationName?: string;
  
  /**
   * Number of shards for the Kinesis stream
   * @default 1
   */
  readonly kinesisShardCount?: number;
  
  /**
   * Whether to enable deletion protection on the QLDB ledger
   * @default true
   */
  readonly enableDeletionProtection?: boolean;
  
  /**
   * Retention period for CloudWatch logs in days
   * @default 30
   */
  readonly logRetentionDays?: number;
}

/**
 * CDK Stack for building ACID-compliant distributed databases with Amazon QLDB
 * 
 * This stack creates:
 * - Amazon QLDB ledger with cryptographic verification capabilities
 * - IAM roles and policies for secure service integration
 * - S3 bucket for journal exports with encryption
 * - Kinesis Data Stream for real-time journal streaming
 * - CloudWatch Log Groups for monitoring and auditing
 */
export class QLDBFinancialLedgerStack extends cdk.Stack {
  /** The QLDB ledger for financial transactions */
  public readonly ledger: qldb.CfnLedger;
  
  /** S3 bucket for journal exports */
  public readonly exportBucket: s3.Bucket;
  
  /** Kinesis stream for real-time journal streaming */
  public readonly journalStream: kinesis.Stream;
  
  /** IAM role for QLDB operations */
  public readonly qldbServiceRole: iam.Role;
  
  /** CloudWatch log group for application logs */
  public readonly logGroup: logs.LogGroup;

  constructor(scope: Construct, id: string, props: QLDBFinancialLedgerStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const environmentName = props.environmentName ?? 'production';
    const applicationName = props.applicationName ?? 'financial';
    const kinesisShardCount = props.kinesisShardCount ?? 1;
    const enableDeletionProtection = props.enableDeletionProtection ?? true;
    const logRetentionDays = props.logRetentionDays ?? 30;
    
    // Generate unique suffix for resource naming
    const uniqueSuffix = new cdk.CfnParameter(this, 'UniqueSuffix', {
      type: 'String',
      description: 'Unique suffix for resource names to avoid conflicts',
      default: cdk.Fn.select(2, cdk.Fn.split('-', cdk.Fn.select(0, cdk.Fn.split('.', cdk.Fn.ref('AWS::StackId'))))),
      minLength: 6,
      maxLength: 8,
    });

    // Common tags for all resources
    const commonTags = {
      Environment: environmentName,
      Application: applicationName,
      Project: 'QLDB-Financial-Ledger',
      ManagedBy: 'AWS-CDK',
    };

    // Create CloudWatch Log Group for application logging
    this.logGroup = new logs.LogGroup(this, 'QLDBApplicationLogGroup', {
      logGroupName: `/aws/qldb/${applicationName}-ledger-${uniqueSuffix.valueAsString}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create S3 bucket for journal exports with security best practices
    this.exportBucket = new s3.Bucket(this, 'QLDBExportBucket', {
      bucketName: `qldb-exports-${applicationName}-${uniqueSuffix.valueAsString}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: true,
      lifecycleRules: [
        {
          id: 'delete-old-exports',
          enabled: true,
          expiration: cdk.Duration.days(90), // Delete exports after 90 days
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Apply tags to S3 bucket
    cdk.Tags.of(this.exportBucket).add('Name', `QLDB Export Bucket - ${applicationName}`);
    Object.entries(commonTags).forEach(([key, value]) => {
      cdk.Tags.of(this.exportBucket).add(key, value);
    });

    // Create Kinesis Data Stream for journal streaming
    this.journalStream = new kinesis.Stream(this, 'QLDBJournalStream', {
      streamName: `qldb-journal-stream-${applicationName}-${uniqueSuffix.valueAsString}`,
      shardCount: kinesisShardCount,
      retentionPeriod: cdk.Duration.days(7), // Retain data for 7 days
      encryption: kinesis.StreamEncryption.MANAGED,
    });

    // Apply tags to Kinesis stream
    cdk.Tags.of(this.journalStream).add('Name', `QLDB Journal Stream - ${applicationName}`);
    Object.entries(commonTags).forEach(([key, value]) => {
      cdk.Tags.of(this.journalStream).add(key, value);
    });

    // Create IAM role for QLDB service operations
    this.qldbServiceRole = new iam.Role(this, 'QLDBServiceRole', {
      roleName: `qldb-stream-role-${applicationName}-${uniqueSuffix.valueAsString}`,
      assumedBy: new iam.ServicePrincipal('qldb.amazonaws.com'),
      description: 'Service role for QLDB operations including journal streaming and S3 exports',
    });

    // Add S3 permissions for journal exports
    this.qldbServiceRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:PutObject',
        's3:GetObject',
        's3:ListBucket',
        's3:GetBucketLocation',
      ],
      resources: [
        this.exportBucket.bucketArn,
        this.exportBucket.arnForObjects('*'),
      ],
    }));

    // Add Kinesis permissions for journal streaming
    this.qldbServiceRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'kinesis:PutRecord',
        'kinesis:PutRecords',
        'kinesis:DescribeStream',
        'kinesis:ListShards',
      ],
      resources: [this.journalStream.streamArn],
    }));

    // Add CloudWatch Logs permissions for monitoring
    this.qldbServiceRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
        'logs:DescribeLogGroups',
        'logs:DescribeLogStreams',
      ],
      resources: [this.logGroup.logGroupArn],
    }));

    // Apply tags to IAM role
    cdk.Tags.of(this.qldbServiceRole).add('Name', `QLDB Service Role - ${applicationName}`);
    Object.entries(commonTags).forEach(([key, value]) => {
      cdk.Tags.of(this.qldbServiceRole).add(key, value);
    });

    // Create QLDB ledger with security and compliance configurations
    this.ledger = new qldb.CfnLedger(this, 'FinancialLedger', {
      name: `${applicationName}-ledger-${uniqueSuffix.valueAsString}`,
      permissionsMode: 'STANDARD', // Use STANDARD mode for production workloads
      deletionProtection: enableDeletionProtection,
      kmsKey: 'AWS_OWNED_KMS_KEY', // Use AWS managed encryption
      tags: [
        {
          key: 'Name',
          value: `QLDB Financial Ledger - ${applicationName}`,
        },
        ...Object.entries(commonTags).map(([key, value]) => ({
          key,
          value,
        })),
      ],
    });

    // Output important resource identifiers for reference
    new cdk.CfnOutput(this, 'LedgerName', {
      value: this.ledger.name!,
      description: 'Name of the QLDB ledger for financial transactions',
      exportName: `${this.stackName}-LedgerName`,
    });

    new cdk.CfnOutput(this, 'ExportBucketName', {
      value: this.exportBucket.bucketName,
      description: 'S3 bucket name for QLDB journal exports',
      exportName: `${this.stackName}-ExportBucketName`,
    });

    new cdk.CfnOutput(this, 'JournalStreamName', {
      value: this.journalStream.streamName,
      description: 'Kinesis stream name for QLDB journal streaming',
      exportName: `${this.stackName}-JournalStreamName`,
    });

    new cdk.CfnOutput(this, 'ServiceRoleArn', {
      value: this.qldbServiceRole.roleArn,
      description: 'ARN of the IAM role for QLDB operations',
      exportName: `${this.stackName}-ServiceRoleArn`,
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: this.logGroup.logGroupName,
      description: 'CloudWatch Log Group for QLDB application logs',
      exportName: `${this.stackName}-LogGroupName`,
    });

    // Output CLI commands for quick operations
    new cdk.CfnOutput(this, 'QLDBDigestCommand', {
      value: `aws qldb get-digest --name ${this.ledger.name}`,
      description: 'AWS CLI command to get ledger cryptographic digest',
    });

    new cdk.CfnOutput(this, 'StartStreamingCommand', {
      value: [
        'aws qldb stream-journal-to-kinesis',
        `--ledger-name ${this.ledger.name}`,
        `--role-arn ${this.qldbServiceRole.roleArn}`,
        `--kinesis-configuration StreamArn=${this.journalStream.streamArn},AggregationEnabled=true`,
        '--stream-name financial-journal-stream',
        '--inclusive-start-time $(date -u -d "1 hour ago" +%Y-%m-%dT%H:%M:%SZ)',
      ].join(' \\\n    '),
      description: 'AWS CLI command to start journal streaming to Kinesis',
    });

    new cdk.CfnOutput(this, 'ExportJournalCommand', {
      value: [
        'aws qldb export-journal-to-s3',
        `--name ${this.ledger.name}`,
        '--inclusive-start-time $(date -u -d "2 hours ago" +%Y-%m-%dT%H:%M:%SZ)',
        '--exclusive-end-time $(date -u +%Y-%m-%dT%H:%M:%SZ)',
        `--role-arn ${this.qldbServiceRole.roleArn}`,
        `--s3-export-configuration 'Bucket=${this.exportBucket.bucketName},Prefix=journal-exports/,EncryptionConfiguration={ObjectEncryptionType=SSE_S3}'`,
      ].join(' \\\n    '),
      description: 'AWS CLI command to export journal to S3',
    });
  }
}

/**
 * Main CDK Application
 * 
 * This application creates a complete QLDB infrastructure for building
 * ACID-compliant distributed databases with cryptographic verification,
 * real-time streaming, and comprehensive audit capabilities.
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const environmentName = app.node.tryGetContext('environment') ?? process.env.ENVIRONMENT_NAME ?? 'production';
const applicationName = app.node.tryGetContext('application') ?? process.env.APPLICATION_NAME ?? 'financial';
const kinesisShardCount = Number(app.node.tryGetContext('kinesisShardCount') ?? process.env.KINESIS_SHARD_COUNT ?? '1');
const enableDeletionProtection = (app.node.tryGetContext('enableDeletionProtection') ?? process.env.ENABLE_DELETION_PROTECTION ?? 'true') === 'true';

// Create the QLDB Financial Ledger stack
new QLDBFinancialLedgerStack(app, 'QLDBFinancialLedgerStack', {
  description: 'ACID-compliant distributed database infrastructure using Amazon QLDB with cryptographic verification, real-time streaming, and audit capabilities',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  environmentName,
  applicationName,
  kinesisShardCount,
  enableDeletionProtection,
  terminationProtection: true, // Protect production stack from accidental deletion
});

// Add stack-level tags
cdk.Tags.of(app).add('Project', 'QLDB-Financial-Ledger');
cdk.Tags.of(app).add('Repository', 'aws-recipes');
cdk.Tags.of(app).add('Recipe', 'building-acid-compliant-distributed-databases-amazon-qldb');