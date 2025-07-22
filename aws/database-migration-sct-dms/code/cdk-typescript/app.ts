#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as dms from 'aws-cdk-lib/aws-dms';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as iam from 'aws-cdk-lib/aws-iam';

/**
 * Stack for AWS Database Migration Service with Schema Conversion Tool
 * 
 * This stack creates:
 * - VPC with public and private subnets
 * - DMS replication instance
 * - Target PostgreSQL RDS database
 * - DMS endpoints for source and target databases
 * - CloudWatch monitoring and logging
 * - Security groups and IAM roles
 */
export class DatabaseMigrationStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Parameters for source database configuration
    const sourceDbHost = new cdk.CfnParameter(this, 'SourceDbHost', {
      type: 'String',
      description: 'Source database hostname or IP address',
      default: 'your-source-database-host'
    });

    const sourceDbPort = new cdk.CfnParameter(this, 'SourceDbPort', {
      type: 'Number',
      description: 'Source database port',
      default: 1521
    });

    const sourceDbName = new cdk.CfnParameter(this, 'SourceDbName', {
      type: 'String',
      description: 'Source database name',
      default: 'your-source-database'
    });

    const sourceDbUsername = new cdk.CfnParameter(this, 'SourceDbUsername', {
      type: 'String',
      description: 'Source database username',
      default: 'your-source-username'
    });

    const sourceDbEngine = new cdk.CfnParameter(this, 'SourceDbEngine', {
      type: 'String',
      description: 'Source database engine',
      default: 'oracle',
      allowedValues: ['oracle', 'mysql', 'postgres', 'mariadb', 'aurora', 'aurora-postgresql', 'redshift', 'sqlserver', 'db2', 'azuredb', 'sybase', 'dynamodb', 's3', 'mongodb', 'docdb', 'neptune']
    });

    const replicationInstanceClass = new cdk.CfnParameter(this, 'ReplicationInstanceClass', {
      type: 'String',
      description: 'DMS replication instance class',
      default: 'dms.t3.medium',
      allowedValues: ['dms.t3.micro', 'dms.t3.small', 'dms.t3.medium', 'dms.t3.large', 'dms.c5.large', 'dms.c5.xlarge', 'dms.c5.2xlarge', 'dms.c5.4xlarge']
    });

    const targetDbInstanceClass = new cdk.CfnParameter(this, 'TargetDbInstanceClass', {
      type: 'String',
      description: 'Target RDS instance class',
      default: 'db.t3.medium',
      allowedValues: ['db.t3.micro', 'db.t3.small', 'db.t3.medium', 'db.t3.large', 'db.t3.xlarge', 'db.t3.2xlarge']
    });

    // Generate unique suffix for resource names
    const uniqueSuffix = cdk.Fn.select(2, cdk.Fn.split('-', cdk.Fn.select(2, cdk.Fn.split('/', cdk.Aws.STACK_ID))));

    // Create VPC with public and private subnets
    const vpc = new ec2.Vpc(this, 'DmsMigrationVpc', {
      cidr: '10.0.0.0/16',
      maxAzs: 2,
      enableDnsHostnames: true,
      enableDnsSupport: true,
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
      ],
    });

    // Create security group for DMS replication instance
    const dmsSecurityGroup = new ec2.SecurityGroup(this, 'DmsSecurityGroup', {
      vpc,
      description: 'Security group for DMS replication instance',
      allowAllOutbound: true,
    });

    // Allow DMS to connect to databases
    dmsSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(1521),
      'Oracle database connection'
    );
    dmsSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(5432),
      'PostgreSQL database connection'
    );
    dmsSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(3306),
      'MySQL database connection'
    );

    // Create security group for RDS instance
    const rdsSecurityGroup = new ec2.SecurityGroup(this, 'RdsSecurityGroup', {
      vpc,
      description: 'Security group for RDS PostgreSQL instance',
      allowAllOutbound: false,
    });

    // Allow DMS to connect to RDS
    rdsSecurityGroup.addIngressRule(
      dmsSecurityGroup,
      ec2.Port.tcp(5432),
      'Allow DMS to connect to PostgreSQL'
    );

    // Create secret for target database password
    const targetDbSecret = new secretsmanager.Secret(this, 'TargetDbSecret', {
      description: 'Target database master password',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: 'dbadmin' }),
        generateStringKey: 'password',
        excludeCharacters: '"@/\\',
        passwordLength: 16,
      },
    });

    // Create secret for source database password
    const sourceDbSecret = new secretsmanager.Secret(this, 'SourceDbSecret', {
      description: 'Source database password',
      secretStringValue: cdk.SecretValue.unsafePlainText('your-source-password'),
    });

    // Create RDS subnet group
    const rdsSubnetGroup = new rds.SubnetGroup(this, 'RdsSubnetGroup', {
      description: 'Subnet group for RDS PostgreSQL instance',
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
    });

    // Create target PostgreSQL database
    const targetDatabase = new rds.DatabaseInstance(this, 'TargetDatabase', {
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_14_9,
      }),
      instanceType: ec2.InstanceType.of(
        ec2.InstanceClass.T3,
        ec2.InstanceSize.MEDIUM
      ),
      credentials: rds.Credentials.fromSecret(targetDbSecret),
      databaseName: 'migrationdb',
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      securityGroups: [rdsSecurityGroup],
      subnetGroup: rdsSubnetGroup,
      backupRetention: cdk.Duration.days(7),
      deletionProtection: false,
      allocatedStorage: 100,
      storageType: rds.StorageType.GP3,
      monitoringInterval: cdk.Duration.seconds(60),
      enablePerformanceInsights: true,
      performanceInsightRetention: rds.PerformanceInsightRetention.DEFAULT,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create DMS subnet group
    const dmsSubnetGroup = new dms.CfnReplicationSubnetGroup(this, 'DmsSubnetGroup', {
      replicationSubnetGroupDescription: 'Subnet group for DMS replication instance',
      replicationSubnetGroupIdentifier: `dms-subnet-group-${uniqueSuffix}`,
      subnetIds: vpc.privateSubnets.map(subnet => subnet.subnetId),
      tags: [
        {
          key: 'Name',
          value: 'DMS Migration Subnet Group',
        },
      ],
    });

    // Create IAM role for DMS
    const dmsRole = new iam.Role(this, 'DmsRole', {
      assumedBy: new iam.ServicePrincipal('dms.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonDMSVPCManagementRole'),
      ],
    });

    // Create DMS replication instance
    const replicationInstance = new dms.CfnReplicationInstance(this, 'ReplicationInstance', {
      replicationInstanceClass: replicationInstanceClass.valueAsString,
      replicationInstanceIdentifier: `dms-migration-${uniqueSuffix}`,
      allocatedStorage: 100,
      replicationSubnetGroupIdentifier: dmsSubnetGroup.replicationSubnetGroupIdentifier,
      vpcSecurityGroupIds: [dmsSecurityGroup.securityGroupId],
      publiclyAccessible: false,
      multiAz: false,
      engineVersion: '3.5.2',
      tags: [
        {
          key: 'Name',
          value: 'DMS Migration Instance',
        },
        {
          key: 'Environment',
          value: 'Migration',
        },
      ],
    });

    // Ensure subnet group is created before replication instance
    replicationInstance.addDependency(dmsSubnetGroup);

    // Create CloudWatch log group for DMS
    const dmsLogGroup = new logs.LogGroup(this, 'DmsLogGroup', {
      logGroupName: '/aws/dms/tasks',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create source database endpoint
    const sourceEndpoint = new dms.CfnEndpoint(this, 'SourceEndpoint', {
      endpointIdentifier: `source-endpoint-${uniqueSuffix}`,
      endpointType: 'source',
      engineName: sourceDbEngine.valueAsString,
      serverName: sourceDbHost.valueAsString,
      port: sourceDbPort.valueAsNumber,
      username: sourceDbUsername.valueAsString,
      password: sourceDbSecret.secretValue.unsafeUnwrap(),
      databaseName: sourceDbName.valueAsString,
      tags: [
        {
          key: 'Name',
          value: 'Source Database Endpoint',
        },
        {
          key: 'EndpointType',
          value: 'Source',
        },
      ],
    });

    // Create target database endpoint
    const targetEndpoint = new dms.CfnEndpoint(this, 'TargetEndpoint', {
      endpointIdentifier: `target-endpoint-${uniqueSuffix}`,
      endpointType: 'target',
      engineName: 'postgres',
      serverName: targetDatabase.instanceEndpoint.hostname,
      port: targetDatabase.instanceEndpoint.port,
      username: 'dbadmin',
      password: targetDbSecret.secretValue.unsafeUnwrap(),
      databaseName: 'migrationdb',
      tags: [
        {
          key: 'Name',
          value: 'Target Database Endpoint',
        },
        {
          key: 'EndpointType',
          value: 'Target',
        },
      ],
    });

    // Table mappings configuration for DMS task
    const tableMappings = {
      rules: [
        {
          'rule-type': 'selection',
          'rule-id': '1',
          'rule-name': '1',
          'object-locator': {
            'schema-name': 'HR',
            'table-name': '%',
          },
          'rule-action': 'include',
          filters: [],
        },
        {
          'rule-type': 'transformation',
          'rule-id': '2',
          'rule-name': '2',
          'rule-target': 'schema',
          'object-locator': {
            'schema-name': 'HR',
          },
          'rule-action': 'rename',
          value: 'hr_schema',
        },
      ],
    };

    // Task settings for DMS replication
    const taskSettings = {
      TargetMetadata: {
        TargetSchema: '',
        SupportLobs: true,
        FullLobMode: false,
        LobChunkSize: 0,
        LimitedSizeLobMode: true,
        LobMaxSize: 32,
        LoadMaxFileSize: 0,
        ParallelLoadThreads: 0,
        ParallelLoadBufferSize: 0,
        BatchApplyEnabled: false,
        TaskRecoveryTableEnabled: false,
        ParallelApplyThreads: 0,
        ParallelApplyBufferSize: 0,
        ParallelApplyQueuesPerThread: 0,
      },
      FullLoadSettings: {
        TargetTablePrepMode: 'DROP_AND_CREATE',
        CreatePkAfterFullLoad: false,
        StopTaskCachedChangesApplied: false,
        StopTaskCachedChangesNotApplied: false,
        MaxFullLoadSubTasks: 8,
        TransactionConsistencyTimeout: 600,
        CommitRate: 10000,
      },
      Logging: {
        EnableLogging: true,
        LogComponents: [
          {
            Id: 'TRANSFORMATION',
            Severity: 'LOGGER_SEVERITY_DEFAULT',
          },
          {
            Id: 'SOURCE_UNLOAD',
            Severity: 'LOGGER_SEVERITY_DEFAULT',
          },
          {
            Id: 'TARGET_LOAD',
            Severity: 'LOGGER_SEVERITY_DEFAULT',
          },
        ],
        CloudWatchLogGroup: dmsLogGroup.logGroupName,
        CloudWatchLogStream: null,
      },
      ErrorBehavior: {
        DataErrorPolicy: 'LOG_ERROR',
        DataTruncationErrorPolicy: 'LOG_ERROR',
        DataErrorEscalationPolicy: 'SUSPEND_TABLE',
        DataErrorEscalationCount: 0,
        TableErrorPolicy: 'SUSPEND_TABLE',
        TableErrorEscalationPolicy: 'STOP_TASK',
        TableErrorEscalationCount: 0,
        RecoverableErrorCount: -1,
        RecoverableErrorInterval: 5,
        RecoverableErrorThrottling: true,
        RecoverableErrorThrottlingMax: 1800,
        RecoverableErrorStopRetryAfterThrottlingMax: false,
        ApplyErrorDeletePolicy: 'IGNORE_RECORD',
        ApplyErrorInsertPolicy: 'LOG_ERROR',
        ApplyErrorUpdatePolicy: 'LOG_ERROR',
        ApplyErrorEscalationPolicy: 'LOG_ERROR',
        ApplyErrorEscalationCount: 0,
        ApplyErrorFailOnTruncationDdl: false,
        FullLoadIgnoreConflicts: true,
        FailOnTransactionConsistencyBreached: false,
        FailOnNoTablesCaptured: true,
      },
      ChangeProcessingTuning: {
        BatchApplyPreserveTransaction: true,
        BatchApplyTimeoutMin: 1,
        BatchApplyTimeoutMax: 30,
        BatchApplyMemoryLimit: 500,
        BatchSplitSize: 0,
        MinTransactionSize: 1000,
        CommitTimeout: 1,
        MemoryLimitTotal: 1024,
        MemoryKeepTime: 60,
        StatementCacheSize: 50,
      },
    };

    // Create DMS replication task for full load
    const migrationTask = new dms.CfnReplicationTask(this, 'MigrationTask', {
      replicationTaskIdentifier: `migration-task-${uniqueSuffix}`,
      sourceEndpointArn: sourceEndpoint.ref,
      targetEndpointArn: targetEndpoint.ref,
      replicationInstanceArn: replicationInstance.ref,
      migrationType: 'full-load',
      tableMappings: JSON.stringify(tableMappings),
      replicationTaskSettings: JSON.stringify(taskSettings),
      tags: [
        {
          key: 'Name',
          value: 'Full Load Migration Task',
        },
        {
          key: 'TaskType',
          value: 'FullLoad',
        },
      ],
    });

    // Create DMS replication task for CDC
    const cdcTask = new dms.CfnReplicationTask(this, 'CdcTask', {
      replicationTaskIdentifier: `cdc-task-${uniqueSuffix}`,
      sourceEndpointArn: sourceEndpoint.ref,
      targetEndpointArn: targetEndpoint.ref,
      replicationInstanceArn: replicationInstance.ref,
      migrationType: 'full-load-and-cdc',
      tableMappings: JSON.stringify(tableMappings),
      replicationTaskSettings: JSON.stringify(taskSettings),
      tags: [
        {
          key: 'Name',
          value: 'CDC Replication Task',
        },
        {
          key: 'TaskType',
          value: 'CDC',
        },
      ],
    });

    // Create CloudWatch dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'DmsDashboard', {
      dashboardName: 'DMS-Migration-Dashboard',
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'DMS Replication Instance Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/DMS',
                metricName: 'FreeableMemory',
                dimensionsMap: {
                  ReplicationInstanceIdentifier: replicationInstance.replicationInstanceIdentifier!,
                },
                statistic: 'Average',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/DMS',
                metricName: 'CPUUtilization',
                dimensionsMap: {
                  ReplicationInstanceIdentifier: replicationInstance.replicationInstanceIdentifier!,
                },
                statistic: 'Average',
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'AWS/DMS',
                metricName: 'NetworkTransmitThroughput',
                dimensionsMap: {
                  ReplicationInstanceIdentifier: replicationInstance.replicationInstanceIdentifier!,
                },
                statistic: 'Average',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/DMS',
                metricName: 'NetworkReceiveThroughput',
                dimensionsMap: {
                  ReplicationInstanceIdentifier: replicationInstance.replicationInstanceIdentifier!,
                },
                statistic: 'Average',
              }),
            ],
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Migration Task Throughput',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/DMS',
                metricName: 'FullLoadThroughputBandwidthTarget',
                dimensionsMap: {
                  ReplicationTaskIdentifier: migrationTask.replicationTaskIdentifier!,
                },
                statistic: 'Average',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/DMS',
                metricName: 'FullLoadThroughputRowsTarget',
                dimensionsMap: {
                  ReplicationTaskIdentifier: migrationTask.replicationTaskIdentifier!,
                },
                statistic: 'Average',
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'AWS/DMS',
                metricName: 'CDCThroughputBandwidthTarget',
                dimensionsMap: {
                  ReplicationTaskIdentifier: cdcTask.replicationTaskIdentifier!,
                },
                statistic: 'Average',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/DMS',
                metricName: 'CDCThroughputRowsTarget',
                dimensionsMap: {
                  ReplicationTaskIdentifier: cdcTask.replicationTaskIdentifier!,
                },
                statistic: 'Average',
              }),
            ],
          }),
        ],
      ],
    });

    // Create CloudWatch alarms for monitoring
    const cpuAlarm = new cloudwatch.Alarm(this, 'DmsCpuAlarm', {
      metric: new cloudwatch.Metric({
        namespace: 'AWS/DMS',
        metricName: 'CPUUtilization',
        dimensionsMap: {
          ReplicationInstanceIdentifier: replicationInstance.replicationInstanceIdentifier!,
        },
        statistic: 'Average',
      }),
      threshold: 80,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'DMS replication instance CPU utilization is high',
    });

    const memoryAlarm = new cloudwatch.Alarm(this, 'DmsMemoryAlarm', {
      metric: new cloudwatch.Metric({
        namespace: 'AWS/DMS',
        metricName: 'FreeableMemory',
        dimensionsMap: {
          ReplicationInstanceIdentifier: replicationInstance.replicationInstanceIdentifier!,
        },
        statistic: 'Average',
      }),
      threshold: 200000000, // 200MB in bytes
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'DMS replication instance freeable memory is low',
    });

    // Outputs
    new cdk.CfnOutput(this, 'VpcId', {
      value: vpc.vpcId,
      description: 'VPC ID for the migration environment',
    });

    new cdk.CfnOutput(this, 'ReplicationInstanceId', {
      value: replicationInstance.replicationInstanceIdentifier!,
      description: 'DMS replication instance identifier',
    });

    new cdk.CfnOutput(this, 'TargetDatabaseEndpoint', {
      value: targetDatabase.instanceEndpoint.hostname,
      description: 'Target PostgreSQL database endpoint',
    });

    new cdk.CfnOutput(this, 'TargetDatabasePort', {
      value: targetDatabase.instanceEndpoint.port.toString(),
      description: 'Target PostgreSQL database port',
    });

    new cdk.CfnOutput(this, 'SourceEndpointId', {
      value: sourceEndpoint.endpointIdentifier!,
      description: 'Source database endpoint identifier',
    });

    new cdk.CfnOutput(this, 'TargetEndpointId', {
      value: targetEndpoint.endpointIdentifier!,
      description: 'Target database endpoint identifier',
    });

    new cdk.CfnOutput(this, 'MigrationTaskId', {
      value: migrationTask.replicationTaskIdentifier!,
      description: 'Full load migration task identifier',
    });

    new cdk.CfnOutput(this, 'CdcTaskId', {
      value: cdcTask.replicationTaskIdentifier!,
      description: 'CDC replication task identifier',
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=DMS-Migration-Dashboard`,
      description: 'CloudWatch dashboard URL for monitoring',
    });

    new cdk.CfnOutput(this, 'TargetDbSecretArn', {
      value: targetDbSecret.secretArn,
      description: 'Target database secret ARN',
    });

    new cdk.CfnOutput(this, 'SourceDbSecretArn', {
      value: sourceDbSecret.secretArn,
      description: 'Source database secret ARN',
    });
  }
}

// Create the CDK app
const app = new cdk.App();

// Deploy the stack
new DatabaseMigrationStack(app, 'DatabaseMigrationStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'AWS Database Migration Service with Schema Conversion Tool infrastructure',
  tags: {
    Project: 'DatabaseMigration',
    Environment: 'Migration',
    CreatedBy: 'CDK',
  },
});