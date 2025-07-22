import * as cdk from 'aws-cdk-lib';
import * as redshift from 'aws-cdk-lib/aws-redshiftserverless';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Configuration interface for the Redshift Data Warehouse Stack
 */
export interface RedshiftDataWarehouseStackProps extends cdk.StackProps {
  /** Base capacity for Redshift Serverless workgroup (in RPUs) */
  readonly baseCapacity?: number;
  /** Whether to make the workgroup publicly accessible */
  readonly publiclyAccessible?: boolean;
  /** Database name for the default database */
  readonly databaseName?: string;
  /** Admin username for the Redshift cluster */
  readonly adminUsername?: string;
  /** Environment name for resource naming */
  readonly environment?: string;
}

/**
 * AWS CDK Stack for Amazon Redshift Serverless Data Warehousing Solution
 * 
 * This stack creates:
 * - Amazon Redshift Serverless namespace and workgroup
 * - S3 bucket for data storage with lifecycle policies
 * - IAM roles with appropriate permissions
 * - CloudWatch dashboards for monitoring
 * - Sample data loading scripts
 */
export class RedshiftDataWarehouseStack extends cdk.Stack {
  /** The S3 bucket for storing data files */
  public readonly dataBucket: s3.Bucket;
  
  /** The Redshift Serverless namespace */
  public readonly namespace: redshift.CfnNamespace;
  
  /** The Redshift Serverless workgroup */
  public readonly workgroup: redshift.CfnWorkgroup;
  
  /** IAM role for Redshift Serverless to access S3 */
  public readonly redshiftRole: iam.Role;

  constructor(scope: Construct, id: string, props: RedshiftDataWarehouseStackProps = {}) {
    super(scope, id, props);

    // Configuration with defaults
    const config = {
      baseCapacity: props.baseCapacity ?? 128,
      publiclyAccessible: props.publiclyAccessible ?? true,
      databaseName: props.databaseName ?? 'sampledb',
      adminUsername: props.adminUsername ?? 'awsuser',
      environment: props.environment ?? 'development',
    };

    // Generate unique suffix for resource names
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().slice(-8);

    // Create S3 bucket for data storage with security best practices
    this.dataBucket = new s3.Bucket(this, 'DataBucket', {
      bucketName: `redshift-data-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'DataLifecycleRule',
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
      removalPolicy: config.environment === 'production' 
        ? cdk.RemovalPolicy.RETAIN 
        : cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: config.environment !== 'production',
    });

    // Create IAM role for Redshift Serverless with least privilege permissions
    this.redshiftRole = new iam.Role(this, 'RedshiftRole', {
      roleName: `RedshiftServerlessRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('redshift.amazonaws.com'),
      description: 'IAM role for Redshift Serverless to access S3 and other AWS services',
      managedPolicies: [
        // Note: In production, consider using more restrictive policies
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonS3ReadOnlyAccess'),
      ],
    });

    // Grant additional S3 permissions for data loading
    this.dataBucket.grantRead(this.redshiftRole);
    this.dataBucket.grantReadWrite(this.redshiftRole, 'unload/*');

    // Add CloudWatch Logs permissions for query logging
    this.redshiftRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'logs:CreateLogGroup',
          'logs:CreateLogStream',
          'logs:PutLogEvents',
          'logs:DescribeLogGroups',
          'logs:DescribeLogStreams',
        ],
        resources: [`arn:aws:logs:${this.region}:${this.account}:log-group:/aws/redshift/*`],
      })
    );

    // Generate a secure random password using CloudFormation intrinsic functions
    const adminPassword = new cdk.CfnParameter(this, 'AdminPassword', {
      type: 'String',
      description: 'Admin password for Redshift Serverless (minimum 8 characters)',
      minLength: 8,
      maxLength: 64,
      noEcho: true,
      default: 'TempPassword123!',
      constraintDescription: 'Password must be 8-64 characters with at least one uppercase, lowercase, number, and special character',
    });

    // Create Redshift Serverless namespace (storage layer)
    this.namespace = new redshift.CfnNamespace(this, 'Namespace', {
      namespaceName: `data-warehouse-ns-${uniqueSuffix}`,
      adminUsername: config.adminUsername,
      adminUserPassword: adminPassword.valueAsString,
      dbName: config.databaseName,
      defaultIamRoleArn: this.redshiftRole.roleArn,
      iamRoles: [this.redshiftRole.roleArn],
      kmsKeyId: 'alias/aws/redshift', // Use AWS managed KMS key
      logExports: ['userlog', 'connectionlog', 'useractivitylog'],
      tags: [
        {
          key: 'Name',
          value: `RedshiftNamespace-${uniqueSuffix}`,
        },
        {
          key: 'Environment',
          value: config.environment,
        },
        {
          key: 'Service',
          value: 'RedshiftServerless',
        },
      ],
    });

    // Create Redshift Serverless workgroup (compute layer)
    this.workgroup = new redshift.CfnWorkgroup(this, 'Workgroup', {
      workgroupName: `data-warehouse-wg-${uniqueSuffix}`,
      namespaceName: this.namespace.namespaceName,
      baseCapacity: config.baseCapacity,
      publiclyAccessible: config.publiclyAccessible,
      enhancedVpcRouting: false, // Set to true for VPC routing if using private subnets
      configParameters: [
        {
          parameterKey: 'max_query_execution_time',
          parameterValue: '14400', // 4 hours in seconds
        },
        {
          parameterKey: 'query_group',
          parameterValue: 'default',
        },
      ],
      tags: [
        {
          key: 'Name',
          value: `RedshiftWorkgroup-${uniqueSuffix}`,
        },
        {
          key: 'Environment',
          value: config.environment,
        },
        {
          key: 'Service',
          value: 'RedshiftServerless',
        },
      ],
    });

    // Ensure workgroup is created after namespace
    this.workgroup.addDependsOn(this.namespace);

    // Create CloudWatch Log Group for Redshift logs
    const logGroup = new logs.LogGroup(this, 'RedshiftLogGroup', {
      logGroupName: `/aws/redshift/serverless/${this.workgroup.workgroupName}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: config.environment === 'production' 
        ? cdk.RemovalPolicy.RETAIN 
        : cdk.RemovalPolicy.DESTROY,
    });

    // Create CloudWatch Dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'RedshiftDashboard', {
      dashboardName: `RedshiftServerless-${uniqueSuffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Redshift Serverless Compute Usage',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/Redshift-Serverless',
                metricName: 'ComputeCapacity',
                dimensionsMap: {
                  WorkgroupName: this.workgroup.workgroupName,
                },
                statistic: 'Average',
              }),
            ],
          }),
          new cloudwatch.GraphWidget({
            title: 'Query Runtime',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/Redshift-Serverless',
                metricName: 'QueryDuration',
                dimensionsMap: {
                  WorkgroupName: this.workgroup.workgroupName,
                },
                statistic: 'Average',
              }),
            ],
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Data Scanned',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/Redshift-Serverless',
                metricName: 'DataScannedInBytes',
                dimensionsMap: {
                  WorkgroupName: this.workgroup.workgroupName,
                },
                statistic: 'Sum',
              }),
            ],
          }),
          new cloudwatch.GraphWidget({
            title: 'Active Queries',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/Redshift-Serverless',
                metricName: 'QueryCount',
                dimensionsMap: {
                  WorkgroupName: this.workgroup.workgroupName,
                },
                statistic: 'Sum',
              }),
            ],
          }),
        ],
      ],
    });

    // CloudFormation Outputs for reference
    new cdk.CfnOutput(this, 'DataBucketName', {
      value: this.dataBucket.bucketName,
      description: 'S3 bucket name for storing data files',
      exportName: `${this.stackName}-DataBucketName`,
    });

    new cdk.CfnOutput(this, 'RedshiftNamespace', {
      value: this.namespace.namespaceName,
      description: 'Redshift Serverless namespace name',
      exportName: `${this.stackName}-NamespaceName`,
    });

    new cdk.CfnOutput(this, 'RedshiftWorkgroup', {
      value: this.workgroup.workgroupName,
      description: 'Redshift Serverless workgroup name',
      exportName: `${this.stackName}-WorkgroupName`,
    });

    new cdk.CfnOutput(this, 'RedshiftEndpoint', {
      value: this.workgroup.attrWorkgroupEndpointAddress,
      description: 'Redshift Serverless workgroup endpoint',
      exportName: `${this.stackName}-WorkgroupEndpoint`,
    });

    new cdk.CfnOutput(this, 'RedshiftRoleArn', {
      value: this.redshiftRole.roleArn,
      description: 'IAM role ARN for Redshift Serverless',
      exportName: `${this.stackName}-RedshiftRoleArn`,
    });

    new cdk.CfnOutput(this, 'DatabaseName', {
      value: config.databaseName,
      description: 'Default database name',
      exportName: `${this.stackName}-DatabaseName`,
    });

    new cdk.CfnOutput(this, 'AdminUsername', {
      value: config.adminUsername,
      description: 'Admin username for Redshift Serverless',
      exportName: `${this.stackName}-AdminUsername`,
    });

    new cdk.CfnOutput(this, 'CloudWatchDashboard', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL for monitoring',
    });

    new cdk.CfnOutput(this, 'QueryEditorV2Url', {
      value: `https://${this.region}.console.aws.amazon.com/sqlworkbench/home?region=${this.region}`,
      description: 'Amazon Redshift Query Editor v2 URL',
    });

    // Add deployment instructions as a custom resource description
    new cdk.CfnOutput(this, 'DeploymentInstructions', {
      value: 'After deployment, upload sample data to S3 bucket and use Query Editor v2 to create tables and load data',
      description: 'Next steps for completing the data warehouse setup',
    });
  }
}