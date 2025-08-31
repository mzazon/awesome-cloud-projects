#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as redshift from 'aws-cdk-lib/aws-redshift';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import { Construct } from 'constructs';

/**
 * Stack for Oracle Database@AWS Enterprise Connectivity with VPC Lattice and S3
 * 
 * This stack creates the infrastructure for:
 * - S3 bucket for Oracle database backups with lifecycle policies
 * - Amazon Redshift cluster for analytics
 * - IAM roles and policies for secure access
 * - CloudWatch monitoring dashboard and log groups
 * - Secrets Manager for secure credential storage
 */
export class OracleEnterpriseConnectivityStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // Create S3 bucket for Oracle database backups
    const oracleBackupBucket = new s3.Bucket(this, 'OracleBackupBucket', {
      bucketName: `oracle-enterprise-backup-${uniqueSuffix}`,
      versioned: true, // Enable versioning for backup protection
      encryption: s3.BucketEncryption.S3_MANAGED, // Server-side encryption
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL, // Security best practice
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo purposes
      lifecycleRules: [
        {
          id: 'OracleBackupLifecycle',
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
    });

    // Create Secrets Manager secret for Redshift credentials
    const redshiftSecret = new secretsmanager.Secret(this, 'RedshiftSecret', {
      secretName: `oracle-redshift-credentials-${uniqueSuffix}`,
      description: 'Credentials for Oracle Analytics Redshift cluster',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: 'oracleadmin' }),
        generateStringKey: 'password',
        excludeCharacters: ' %+~`#$&*()|[]{}:;<>?!\'/@"\\',
        passwordLength: 16,
      },
    });

    // Create IAM role for Redshift cluster
    const redshiftRole = new iam.Role(this, 'RedshiftRole', {
      roleName: `RedshiftOracleRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('redshift.amazonaws.com'),
      description: 'IAM role for Redshift cluster to access S3 and other AWS services',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonS3ReadOnlyAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonRedshiftAllCommandsFullAccess'),
      ],
    });

    // Grant Redshift role access to the Oracle backup bucket
    oracleBackupBucket.grantRead(redshiftRole);

    // Create Redshift subnet group
    const redshiftSubnetGroup = new redshift.CfnClusterSubnetGroup(this, 'RedshiftSubnetGroup', {
      description: 'Subnet group for Oracle Analytics Redshift cluster',
      subnetIds: [
        // Note: In a real deployment, you would reference actual subnet IDs
        // For this demo, we'll use a placeholder that needs to be updated
        'subnet-placeholder-1', 
        'subnet-placeholder-2'
      ],
      subnetGroupName: `oracle-redshift-subnet-group-${uniqueSuffix}`,
    });

    // Create Redshift parameter group
    const redshiftParameterGroup = new redshift.CfnClusterParameterGroup(this, 'RedshiftParameterGroup', {
      description: 'Parameter group for Oracle Analytics Redshift cluster',
      parameterGroupFamily: 'redshift-1.0',
      parameterGroupName: `oracle-redshift-params-${uniqueSuffix}`,
      parameters: [
        {
          parameterName: 'enable_user_activity_logging',
          parameterValue: 'true',
        },
        {
          parameterName: 'max_concurrency_scaling_clusters',
          parameterValue: '1',
        },
      ],
    });

    // Create Redshift cluster
    const redshiftCluster = new redshift.CfnCluster(this, 'RedshiftCluster', {
      clusterIdentifier: `oracle-analytics-${uniqueSuffix}`,
      clusterType: 'single-node',
      nodeType: 'dc2.large',
      dbName: 'oracleanalytics',
      masterUsername: redshiftSecret.secretValueFromJson('username').unsafeUnwrap(),
      masterUserPassword: redshiftSecret.secretValueFromJson('password').unsafeUnwrap(),
      port: 5439,
      encrypted: true,
      kmsKeyId: 'alias/aws/redshift', // Use AWS managed key
      iamRoles: [redshiftRole.roleArn],
      clusterSubnetGroupName: redshiftSubnetGroup.subnetGroupName,
      clusterParameterGroupName: redshiftParameterGroup.parameterGroupName,
      automatedSnapshotRetentionPeriod: 7,
      preferredMaintenanceWindow: 'sun:05:00-sun:06:00',
      allowVersionUpgrade: true,
      publiclyAccessible: false, // Security best practice
    });

    // Ensure dependencies
    redshiftCluster.addDependency(redshiftSubnetGroup);
    redshiftCluster.addDependency(redshiftParameterGroup);

    // Create CloudWatch log group for Oracle operations
    const oracleLogGroup = new logs.LogGroup(this, 'OracleLogGroup', {
      logGroupName: `/aws/oracle-database/enterprise-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    // Create CloudWatch dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'OracleDashboard', {
      dashboardName: `OracleAWSIntegration-${uniqueSuffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'S3 Bucket Requests',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/S3',
                metricName: 'NumberOfObjects',
                dimensionsMap: {
                  BucketName: oracleBackupBucket.bucketName,
                  StorageType: 'AllStorageTypes',
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Redshift Cluster Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/Redshift',
                metricName: 'CPUUtilization',
                dimensionsMap: {
                  ClusterIdentifier: redshiftCluster.clusterIdentifier!,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'AWS/Redshift',
                metricName: 'DatabaseConnections',
                dimensionsMap: {
                  ClusterIdentifier: redshiftCluster.clusterIdentifier!,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // Create IAM policy for Oracle Database@AWS S3 access
    const oracleS3Policy = new iam.ManagedPolicy(this, 'OracleS3Policy', {
      managedPolicyName: `OracleS3Access-${uniqueSuffix}`,
      description: 'Policy for Oracle Database@AWS to access S3 backup bucket',
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            's3:GetObject',
            's3:PutObject',
            's3:DeleteObject',
            's3:ListBucket',
          ],
          resources: [
            oracleBackupBucket.bucketArn,
            `${oracleBackupBucket.bucketArn}/*`,
          ],
        }),
      ],
    });

    // CloudFormation outputs for important resources
    new cdk.CfnOutput(this, 'OracleBackupBucketName', {
      value: oracleBackupBucket.bucketName,
      description: 'Name of the S3 bucket for Oracle database backups',
      exportName: `OracleBackupBucket-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'RedshiftClusterIdentifier', {
      value: redshiftCluster.clusterIdentifier!,
      description: 'Identifier of the Redshift cluster for analytics',
      exportName: `RedshiftCluster-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'RedshiftEndpoint', {
      value: redshiftCluster.attrEndpointAddress,
      description: 'Endpoint address of the Redshift cluster',
      exportName: `RedshiftEndpoint-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'RedshiftRoleArn', {
      value: redshiftRole.roleArn,
      description: 'ARN of the IAM role for Redshift cluster',
      exportName: `RedshiftRole-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'OracleLogGroupName', {
      value: oracleLogGroup.logGroupName,
      description: 'Name of the CloudWatch log group for Oracle operations',
      exportName: `OracleLogGroup-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard for monitoring',
      exportName: `DashboardUrl-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'OracleS3PolicyArn', {
      value: oracleS3Policy.managedPolicyArn,
      description: 'ARN of the IAM policy for Oracle Database@AWS S3 access',
      exportName: `OracleS3Policy-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'RedshiftSecretArn', {
      value: redshiftSecret.secretArn,
      description: 'ARN of the Secrets Manager secret for Redshift credentials',
      exportName: `RedshiftSecret-${uniqueSuffix}`,
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'OracleEnterpriseConnectivity');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('Owner', 'DataEngineering');
    cdk.Tags.of(this).add('CostCenter', 'Analytics');
  }
}

// Create the CDK app and stack
const app = new cdk.App();

new OracleEnterpriseConnectivityStack(app, 'OracleEnterpriseConnectivityStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Oracle Database@AWS Enterprise Connectivity with VPC Lattice and S3 integration',
});

app.synth();