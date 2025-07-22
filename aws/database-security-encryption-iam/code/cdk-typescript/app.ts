#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';

/**
 * Stack for implementing comprehensive database security with encryption and IAM authentication
 * 
 * This stack creates:
 * - Customer-managed KMS key for encryption
 * - VPC with private subnets for database isolation
 * - RDS PostgreSQL instance with encryption and IAM authentication
 * - RDS Proxy for enhanced security and connection pooling
 * - IAM roles and policies for database access
 * - CloudWatch monitoring and alarms
 * - Security groups with restrictive access
 */
export class DatabaseSecurityStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // Create customer-managed KMS key for RDS encryption
    const kmsKey = new kms.Key(this, 'RDSEncryptionKey', {
      description: 'Customer managed key for RDS encryption',
      enableKeyRotation: true,
      keySpec: kms.KeySpec.SYMMETRIC_DEFAULT,
      keyUsage: kms.KeyUsage.ENCRYPT_DECRYPT,
      policy: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            sid: 'EnableIAMUserPermissions',
            effect: iam.Effect.ALLOW,
            principals: [new iam.AccountRootPrincipal()],
            actions: ['kms:*'],
            resources: ['*'],
          }),
          new iam.PolicyStatement({
            sid: 'AllowRDSService',
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('rds.amazonaws.com')],
            actions: [
              'kms:Decrypt',
              'kms:GenerateDataKey',
              'kms:DescribeKey',
            ],
            resources: ['*'],
            conditions: {
              StringEquals: {
                'kms:ViaService': `rds.${this.region}.amazonaws.com`,
              },
            },
          }),
        ],
      }),
    });

    // Create KMS key alias for easier reference
    const kmsKeyAlias = new kms.Alias(this, 'RDSEncryptionKeyAlias', {
      aliasName: `alias/rds-security-key-${uniqueSuffix}`,
      targetKey: kmsKey,
    });

    // Create VPC with private subnets for database isolation
    const vpc = new ec2.Vpc(this, 'DatabaseVPC', {
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
        {
          cidrMask: 24,
          name: 'Database',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // Create security group for database access
    const dbSecurityGroup = new ec2.SecurityGroup(this, 'DatabaseSecurityGroup', {
      vpc,
      description: 'Security group for secure RDS instance',
      allowAllOutbound: false,
    });

    // Allow PostgreSQL access within the security group
    dbSecurityGroup.addIngressRule(
      dbSecurityGroup,
      ec2.Port.tcp(5432),
      'Allow PostgreSQL access from within security group'
    );

    // Create security group for RDS Proxy
    const proxySecurityGroup = new ec2.SecurityGroup(this, 'ProxySecurityGroup', {
      vpc,
      description: 'Security group for RDS Proxy',
      allowAllOutbound: true,
    });

    // Allow proxy to connect to database
    proxySecurityGroup.addIngressRule(
      proxySecurityGroup,
      ec2.Port.tcp(5432),
      'Allow proxy access from within security group'
    );

    // Create parameter group for enhanced security
    const parameterGroup = new rds.ParameterGroup(this, 'SecureParameterGroup', {
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_15_7,
      }),
      description: 'Security-enhanced PostgreSQL parameters',
      parameters: {
        'rds.force_ssl': '1',
        'log_connections': '1',
        'log_disconnections': '1',
        'log_checkpoints': '1',
        'log_lock_waits': '1',
        'log_temp_files': '0',
        'log_autovacuum_min_duration': '0',
        'log_error_verbosity': 'default',
        'log_line_prefix': '%m [%p] %q%u@%d ',
        'log_statement': 'ddl',
        'log_min_duration_statement': '1000',
      },
    });

    // Create IAM role for enhanced monitoring
    const monitoringRole = new iam.Role(this, 'RDSMonitoringRole', {
      assumedBy: new iam.ServicePrincipal('monitoring.rds.amazonaws.com'),
      description: 'Role for RDS enhanced monitoring',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName(
          'service-role/AmazonRDSEnhancedMonitoringRole'
        ),
      ],
    });

    // Create database credentials using Secrets Manager
    const dbCredentials = new secretsmanager.Secret(this, 'DatabaseCredentials', {
      description: 'Master credentials for RDS PostgreSQL instance',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: 'dbadmin' }),
        generateStringKey: 'password',
        excludeCharacters: '"@/\\',
        passwordLength: 32,
      },
    });

    // Create RDS subnet group
    const subnetGroup = new rds.SubnetGroup(this, 'DatabaseSubnetGroup', {
      description: 'Subnet group for secure database',
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
    });

    // Create RDS instance with comprehensive security configuration
    const database = new rds.DatabaseInstance(this, 'SecureDatabase', {
      instanceIdentifier: `secure-db-${uniqueSuffix}`,
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_15_7,
      }),
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.R5, ec2.InstanceSize.LARGE),
      credentials: rds.Credentials.fromSecret(dbCredentials),
      vpc,
      subnetGroup,
      securityGroups: [dbSecurityGroup],
      parameterGroup,
      storageEncrypted: true,
      storageEncryptionKey: kmsKey,
      allocatedStorage: 100,
      storageType: rds.StorageType.GP3,
      backupRetention: cdk.Duration.days(7),
      preferredBackupWindow: '03:00-04:00',
      preferredMaintenanceWindow: 'sun:04:00-sun:05:00',
      iamAuthentication: true,
      monitoringInterval: cdk.Duration.minutes(1),
      monitoringRole,
      enablePerformanceInsights: true,
      performanceInsightEncryptionKey: kmsKey,
      performanceInsightRetention: rds.PerformanceInsightRetention.DEFAULT,
      deletionProtection: true,
      cloudwatchLogsExports: ['postgresql'],
      cloudwatchLogsRetention: logs.RetentionDays.ONE_MONTH,
    });

    // Create IAM policy for database access
    const dbAccessPolicy = new iam.ManagedPolicy(this, 'DatabaseAccessPolicy', {
      description: 'Policy for IAM database authentication',
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: ['rds-db:connect'],
          resources: [
            `arn:aws:rds-db:${this.region}:${this.account}:dbuser:${database.instanceIdentifier}/app_user`,
          ],
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'rds:DescribeDBInstances',
            'rds:DescribeDBProxies',
          ],
          resources: ['*'],
        }),
      ],
    });

    // Create IAM role for database access
    const dbAccessRole = new iam.Role(this, 'DatabaseAccessRole', {
      roleName: `DatabaseAccessRole-${uniqueSuffix}`,
      assumedBy: new iam.CompositePrincipal(
        new iam.ServicePrincipal('lambda.amazonaws.com'),
        new iam.ServicePrincipal('ec2.amazonaws.com')
      ),
      description: 'Role for applications to access database with IAM authentication',
      managedPolicies: [dbAccessPolicy],
    });

    // Create RDS Proxy for enhanced security and connection pooling
    const proxy = new rds.DatabaseProxy(this, 'DatabaseProxy', {
      proxyTarget: rds.ProxyTarget.fromInstance(database),
      secrets: [dbCredentials],
      vpc,
      securityGroups: [proxySecurityGroup],
      requireTLS: true,
      idleClientTimeout: cdk.Duration.minutes(30),
      maxConnectionsPercent: 100,
      maxIdleConnectionsPercent: 50,
      debugLogging: true,
      role: new iam.Role(this, 'ProxyRole', {
        assumedBy: new iam.ServicePrincipal('rds.amazonaws.com'),
        managedPolicies: [
          iam.ManagedPolicy.fromAwsManagedPolicyName(
            'service-role/AmazonRDSProxyRole'
          ),
        ],
      }),
    });

    // Create CloudWatch log group for database monitoring
    const dbLogGroup = new logs.LogGroup(this, 'DatabaseLogGroup', {
      logGroupName: `/aws/rds/instance/${database.instanceIdentifier}/postgresql`,
      retention: logs.RetentionDays.ONE_MONTH,
      encryptionKey: kmsKey,
    });

    // Create CloudWatch alarm for high CPU usage
    const cpuAlarm = new cloudwatch.Alarm(this, 'HighCPUAlarm', {
      alarmName: `RDS-HighCPU-${database.instanceIdentifier}`,
      alarmDescription: 'High CPU usage on RDS instance',
      metric: database.metricCPUUtilization({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.AVERAGE,
      }),
      threshold: 80,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Create CloudWatch alarm for database connections
    const connectionsAlarm = new cloudwatch.Alarm(this, 'HighConnectionsAlarm', {
      alarmName: `RDS-HighConnections-${database.instanceIdentifier}`,
      alarmDescription: 'High number of database connections',
      metric: database.metricDatabaseConnections({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.AVERAGE,
      }),
      threshold: 50,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Create CloudWatch alarm for failed authentications
    const authFailureAlarm = new cloudwatch.Alarm(this, 'AuthFailureAlarm', {
      alarmName: `RDS-AuthFailures-${database.instanceIdentifier}`,
      alarmDescription: 'Authentication failures detected',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/RDS',
        metricName: 'LoginFailures',
        dimensionsMap: {
          DBInstanceIdentifier: database.instanceIdentifier,
        },
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Statistic.SUM,
      }),
      threshold: 5,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('Purpose', 'Database Security');
    cdk.Tags.of(this).add('Recipe', 'database-security-encryption-iam');

    // Output important resource information
    new cdk.CfnOutput(this, 'DatabaseEndpoint', {
      value: database.instanceEndpoint.hostname,
      description: 'RDS PostgreSQL instance endpoint',
    });

    new cdk.CfnOutput(this, 'DatabasePort', {
      value: database.instanceEndpoint.port.toString(),
      description: 'RDS PostgreSQL instance port',
    });

    new cdk.CfnOutput(this, 'ProxyEndpoint', {
      value: proxy.endpoint,
      description: 'RDS Proxy endpoint for secure connections',
    });

    new cdk.CfnOutput(this, 'KMSKeyId', {
      value: kmsKey.keyId,
      description: 'KMS key ID used for encryption',
    });

    new cdk.CfnOutput(this, 'KMSKeyAlias', {
      value: kmsKeyAlias.aliasName,
      description: 'KMS key alias',
    });

    new cdk.CfnOutput(this, 'DatabaseAccessRoleArn', {
      value: dbAccessRole.roleArn,
      description: 'IAM role ARN for database access',
    });

    new cdk.CfnOutput(this, 'DatabaseCredentialsSecretArn', {
      value: dbCredentials.secretArn,
      description: 'Secrets Manager ARN for database credentials',
    });

    new cdk.CfnOutput(this, 'SecurityGroupId', {
      value: dbSecurityGroup.securityGroupId,
      description: 'Security group ID for database access',
    });

    new cdk.CfnOutput(this, 'VpcId', {
      value: vpc.vpcId,
      description: 'VPC ID where database is deployed',
    });

    new cdk.CfnOutput(this, 'DatabaseSubnetGroupName', {
      value: subnetGroup.subnetGroupName,
      description: 'Database subnet group name',
    });

    // Output connection commands for validation
    new cdk.CfnOutput(this, 'IAMAuthCommand', {
      value: `aws rds generate-db-auth-token --hostname ${database.instanceEndpoint.hostname} --port 5432 --region ${this.region} --username app_user`,
      description: 'Command to generate IAM authentication token',
    });

    new cdk.CfnOutput(this, 'ProxyConnectionCommand', {
      value: `PGPASSWORD=$(aws rds generate-db-auth-token --hostname ${proxy.endpoint} --port 5432 --region ${this.region} --username app_user) psql -h ${proxy.endpoint} -U app_user -d postgres -p 5432`,
      description: 'Command to connect via RDS Proxy with IAM authentication',
    });
  }
}

// Create the CDK app
const app = new cdk.App();

// Create the stack
new DatabaseSecurityStack(app, 'DatabaseSecurityStack', {
  description: 'Comprehensive database security implementation with encryption and IAM authentication',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

// Synthesize the CloudFormation template
app.synth();