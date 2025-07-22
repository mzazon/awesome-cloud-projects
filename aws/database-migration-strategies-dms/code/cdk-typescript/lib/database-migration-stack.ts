import * as cdk from 'aws-cdk-lib';
import * as dms from 'aws-cdk-lib/aws-dms';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import { NagSuppressions } from 'cdk-nag';

export interface DatabaseMigrationStackProps extends cdk.StackProps {
  readonly vpcId?: string;
  readonly sourceEndpointConfig?: SourceEndpointConfig;
  readonly targetEndpointConfig?: TargetEndpointConfig;
  readonly replicationInstanceClass?: string;
  readonly allocatedStorage?: number;
  readonly multiAz?: boolean;
}

export interface SourceEndpointConfig {
  readonly engineName: string;
  readonly serverName: string;
  readonly port: number;
  readonly databaseName: string;
  readonly username: string;
  readonly password: string;
  readonly extraConnectionAttributes?: string;
}

export interface TargetEndpointConfig {
  readonly engineName: string;
  readonly serverName: string;
  readonly port: number;
  readonly databaseName: string;
  readonly username: string;
  readonly password: string;
  readonly extraConnectionAttributes?: string;
}

export class DatabaseMigrationStack extends cdk.Stack {
  public readonly replicationInstance: dms.CfnReplicationInstance;
  public readonly sourceEndpoint: dms.CfnEndpoint;
  public readonly targetEndpoint: dms.CfnEndpoint;
  public readonly migrationLoggingBucket: s3.Bucket;
  public readonly cloudWatchLogGroup: logs.LogGroup;
  public readonly alertingTopic: sns.Topic;

  constructor(scope: Construct, id: string, props?: DatabaseMigrationStackProps) {
    super(scope, id, props);

    // Generate unique identifiers for resources
    const uniqueSuffix = this.node.addr.substring(0, 6);

    // Get or create VPC - use default if not specified
    const vpc = props?.vpcId 
      ? ec2.Vpc.fromLookup(this, 'ExistingVpc', { vpcId: props.vpcId })
      : ec2.Vpc.fromLookup(this, 'DefaultVpc', { isDefault: true });

    // Create S3 bucket for DMS logging with encryption and secure access
    this.migrationLoggingBucket = new s3.Bucket(this, 'MigrationLoggingBucket', {
      bucketName: `dms-migration-logs-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: true,
      lifecycleRules: [
        {
          id: 'DeleteOldLogs',
          enabled: true,
          expiration: cdk.Duration.days(90),
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo purposes
    });

    // Create CloudWatch Log Group for DMS task logging
    this.cloudWatchLogGroup = new logs.LogGroup(this, 'DMSLogGroup', {
      logGroupName: `/aws/dms/tasks/replication-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create SNS topic for alerting
    this.alertingTopic = new sns.Topic(this, 'DMSAlertingTopic', {
      topicName: `dms-alerts-${uniqueSuffix}`,
      displayName: 'DMS Migration Alerts',
    });

    // Create DMS subnet group
    const subnetGroup = new dms.CfnReplicationSubnetGroup(this, 'DMSSubnetGroup', {
      replicationSubnetGroupIdentifier: `dms-subnet-group-${uniqueSuffix}`,
      replicationSubnetGroupDescription: 'DMS subnet group for database migration',
      subnetIds: vpc.privateSubnets.length > 0 
        ? vpc.privateSubnets.map(subnet => subnet.subnetId)
        : vpc.publicSubnets.map(subnet => subnet.subnetId),
      tags: [
        { key: 'Name', value: 'dms-migration-subnet-group' },
        { key: 'Environment', value: 'migration' },
      ],
    });

    // Create IAM role for DMS replication instance
    const dmsRole = new iam.Role(this, 'DMSReplicationRole', {
      assumedBy: new iam.ServicePrincipal('dms.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonDMSVPCManagementRole'),
      ],
    });

    // Grant S3 permissions to DMS for logging
    this.migrationLoggingBucket.grantReadWrite(dmsRole);

    // Create DMS replication instance with Multi-AZ configuration
    this.replicationInstance = new dms.CfnReplicationInstance(this, 'DMSReplicationInstance', {
      replicationInstanceIdentifier: `dms-replication-${uniqueSuffix}`,
      replicationInstanceClass: props?.replicationInstanceClass || 'dms.t3.medium',
      allocatedStorage: props?.allocatedStorage || 100,
      multiAz: props?.multiAz ?? true,
      engineVersion: '3.5.2',
      replicationSubnetGroupIdentifier: subnetGroup.replicationSubnetGroupIdentifier,
      publiclyAccessible: false, // Security best practice
      vpcSecurityGroupIds: [this.createDMSSecurityGroup(vpc).securityGroupId],
      tags: [
        { key: 'Name', value: 'dms-migration-instance' },
        { key: 'Environment', value: 'migration' },
      ],
    });

    // Ensure subnet group is created before replication instance
    this.replicationInstance.addDependency(subnetGroup);

    // Create source endpoint (configurable via props)
    this.sourceEndpoint = new dms.CfnEndpoint(this, 'SourceEndpoint', {
      endpointIdentifier: `source-endpoint-${uniqueSuffix}`,
      endpointType: 'source',
      engineName: props?.sourceEndpointConfig?.engineName || 'mysql',
      serverName: props?.sourceEndpointConfig?.serverName || 'source-db-placeholder',
      port: props?.sourceEndpointConfig?.port || 3306,
      databaseName: props?.sourceEndpointConfig?.databaseName || 'sourcedb',
      username: props?.sourceEndpointConfig?.username || 'source_user',
      password: props?.sourceEndpointConfig?.password || 'change-me-in-production',
      extraConnectionAttributes: props?.sourceEndpointConfig?.extraConnectionAttributes || 
        'initstmt=SET foreign_key_checks=0',
      sslMode: 'require', // Enhanced security
      tags: [
        { key: 'Name', value: 'source-mysql-endpoint' },
        { key: 'Environment', value: 'migration' },
      ],
    });

    // Create target endpoint (configurable via props)
    this.targetEndpoint = new dms.CfnEndpoint(this, 'TargetEndpoint', {
      endpointIdentifier: `target-endpoint-${uniqueSuffix}`,
      endpointType: 'target',
      engineName: props?.targetEndpointConfig?.engineName || 'mysql',
      serverName: props?.targetEndpointConfig?.serverName || 'target-rds-placeholder',
      port: props?.targetEndpointConfig?.port || 3306,
      databaseName: props?.targetEndpointConfig?.databaseName || 'targetdb',
      username: props?.targetEndpointConfig?.username || 'target_user',
      password: props?.targetEndpointConfig?.password || 'change-me-in-production',
      extraConnectionAttributes: props?.targetEndpointConfig?.extraConnectionAttributes || 
        'initstmt=SET foreign_key_checks=0',
      sslMode: 'require', // Enhanced security
      tags: [
        { key: 'Name', value: 'target-rds-endpoint' },
        { key: 'Environment', value: 'migration' },
      ],
    });

    // Create migration task with comprehensive configuration
    const migrationTask = new dms.CfnReplicationTask(this, 'MigrationTask', {
      replicationTaskIdentifier: `migration-task-${uniqueSuffix}`,
      sourceEndpointArn: this.sourceEndpoint.attrEndpointArn,
      targetEndpointArn: this.targetEndpoint.attrEndpointArn,
      replicationInstanceArn: this.replicationInstance.attrReplicationInstanceArn,
      migrationType: 'full-load-and-cdc',
      tableMappings: JSON.stringify(this.getTableMappingRules()),
      replicationTaskSettings: JSON.stringify(this.getTaskSettings(uniqueSuffix)),
      tags: [
        { key: 'Name', value: 'dms-migration-task' },
        { key: 'Environment', value: 'migration' },
      ],
    });

    // Create CDC-only task for ongoing replication
    const cdcTask = new dms.CfnReplicationTask(this, 'CDCTask', {
      replicationTaskIdentifier: `cdc-task-${uniqueSuffix}`,
      sourceEndpointArn: this.sourceEndpoint.attrEndpointArn,
      targetEndpointArn: this.targetEndpoint.attrEndpointArn,
      replicationInstanceArn: this.replicationInstance.attrReplicationInstanceArn,
      migrationType: 'cdc',
      tableMappings: JSON.stringify(this.getTableMappingRules()),
      replicationTaskSettings: JSON.stringify(this.getTaskSettings(uniqueSuffix)),
      tags: [
        { key: 'Name', value: 'dms-cdc-task' },
        { key: 'Environment', value: 'migration' },
      ],
    });

    // Create CloudWatch alarms for monitoring
    this.createCloudWatchAlarms(migrationTask, cdcTask);

    // Output important resource information
    new cdk.CfnOutput(this, 'ReplicationInstanceIdentifier', {
      value: this.replicationInstance.replicationInstanceIdentifier!,
      description: 'DMS Replication Instance Identifier',
    });

    new cdk.CfnOutput(this, 'SourceEndpointIdentifier', {
      value: this.sourceEndpoint.endpointIdentifier!,
      description: 'Source Database Endpoint Identifier',
    });

    new cdk.CfnOutput(this, 'TargetEndpointIdentifier', {
      value: this.targetEndpoint.endpointIdentifier!,
      description: 'Target Database Endpoint Identifier',
    });

    new cdk.CfnOutput(this, 'MigrationLoggingBucket', {
      value: this.migrationLoggingBucket.bucketName,
      description: 'S3 Bucket for DMS Migration Logs',
    });

    new cdk.CfnOutput(this, 'CloudWatchLogGroup', {
      value: this.cloudWatchLogGroup.logGroupName,
      description: 'CloudWatch Log Group for DMS Tasks',
    });

    new cdk.CfnOutput(this, 'AlertingTopicArn', {
      value: this.alertingTopic.topicArn,
      description: 'SNS Topic ARN for DMS Alerts',
    });

    // Apply CDK Nag suppressions for specific violations that are acceptable in this context
    this.addNagSuppressions();
  }

  /**
   * Creates a security group for DMS replication instance
   */
  private createDMSSecurityGroup(vpc: ec2.IVpc): ec2.SecurityGroup {
    const securityGroup = new ec2.SecurityGroup(this, 'DMSSecurityGroup', {
      vpc,
      description: 'Security group for DMS replication instance',
      allowAllOutbound: true, // Required for DMS to connect to endpoints
    });

    // Add ingress rules for database connections (customize as needed)
    securityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(3306),
      'Allow MySQL connections from VPC'
    );

    securityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(5432),
      'Allow PostgreSQL connections from VPC'
    );

    return securityGroup;
  }

  /**
   * Returns table mapping rules for DMS migration
   */
  private getTableMappingRules(): any {
    return {
      rules: [
        {
          'rule-type': 'selection',
          'rule-id': '1',
          'rule-name': 'include-all-tables',
          'object-locator': {
            'schema-name': '%',
            'table-name': '%',
          },
          'rule-action': 'include',
          filters: [],
        },
        {
          'rule-type': 'transformation',
          'rule-id': '2',
          'rule-name': 'rename-schema',
          'rule-target': 'schema',
          'object-locator': {
            'schema-name': '%',
          },
          'rule-action': 'rename',
          value: 'migrated_${schema-name}',
        },
      ],
    };
  }

  /**
   * Returns comprehensive task settings for DMS migration
   */
  private getTaskSettings(uniqueSuffix: string): any {
    return {
      TargetMetadata: {
        TargetSchema: '',
        SupportLobs: true,
        FullLobMode: false,
        LobChunkSize: 0,
        LimitedSizeLobMode: true,
        LobMaxSize: 32,
        InlineLobMaxSize: 0,
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
            Id: 'SOURCE_UNLOAD',
            Severity: 'LOGGER_SEVERITY_DEFAULT',
          },
          {
            Id: 'TARGET_LOAD',
            Severity: 'LOGGER_SEVERITY_DEFAULT',
          },
          {
            Id: 'SOURCE_CAPTURE',
            Severity: 'LOGGER_SEVERITY_DEFAULT',
          },
          {
            Id: 'TARGET_APPLY',
            Severity: 'LOGGER_SEVERITY_DEFAULT',
          },
        ],
        CloudWatchLogGroup: this.cloudWatchLogGroup.logGroupName,
        CloudWatchLogStream: `dms-task-${uniqueSuffix}`,
      },
      ControlTablesSettings: {
        historyTimeslotInMinutes: 5,
        ControlSchema: '',
        HistoryTimeslotInMinutes: 5,
        HistoryTableEnabled: false,
        SuspendedTablesTableEnabled: false,
        StatusTableEnabled: false,
        FullLoadExceptionTableEnabled: false,
      },
      StreamBufferSettings: {
        StreamBufferCount: 3,
        StreamBufferSizeInMB: 8,
        CtrlStreamBufferSizeInMB: 5,
      },
      ChangeProcessingDdlHandlingPolicy: {
        HandleSourceTableDropped: true,
        HandleSourceTableTruncated: true,
        HandleSourceTableAltered: true,
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
        RecoverableErrorStopRetryAfterThrottlingMax: true,
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
      ValidationSettings: {
        EnableValidation: true,
        ValidationMode: 'ROW_LEVEL',
        ThreadCount: 5,
        PartitionSize: 10000,
        FailureMaxCount: 10000,
        RecordFailureDelayLimitInMinutes: 0,
        RecordSuspendDelayInMinutes: 30,
        MaxKeyColumnSize: 8096,
        TableFailureMaxCount: 1000,
        ValidationOnly: false,
        HandleCollationDiff: false,
        RecordFailureDelayInMinutes: 5,
        SkipLobColumns: false,
        ValidationPartialLobSize: 0,
        ValidationQueryCdcDelaySeconds: 0,
      },
    };
  }

  /**
   * Creates CloudWatch alarms for monitoring DMS tasks
   */
  private createCloudWatchAlarms(
    migrationTask: dms.CfnReplicationTask,
    cdcTask: dms.CfnReplicationTask
  ): void {
    // Alarm for migration task failures
    const migrationTaskFailureAlarm = new cloudwatch.Alarm(this, 'MigrationTaskFailureAlarm', {
      alarmName: `DMS-Task-Failure-${migrationTask.replicationTaskIdentifier}`,
      alarmDescription: 'Monitor DMS migration task failures',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/DMS',
        metricName: 'ReplicationTasksState',
        dimensionsMap: {
          ReplicationTaskIdentifier: migrationTask.replicationTaskIdentifier!,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
    });

    // Alarm for CDC latency
    const cdcLatencyAlarm = new cloudwatch.Alarm(this, 'CDCLatencyAlarm', {
      alarmName: `DMS-CDC-Latency-${cdcTask.replicationTaskIdentifier}`,
      alarmDescription: 'Monitor DMS CDC latency',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/DMS',
        metricName: 'CDCLatencyTarget',
        dimensionsMap: {
          ReplicationTaskIdentifier: cdcTask.replicationTaskIdentifier!,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 300, // 5 minutes latency threshold
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
    });

    // Add SNS notifications to alarms
    migrationTaskFailureAlarm.addAlarmAction(
      new cloudwatchActions.SnsAction(this.alertingTopic)
    );
    cdcLatencyAlarm.addAlarmAction(
      new cloudwatchActions.SnsAction(this.alertingTopic)
    );
  }

  /**
   * Add CDK Nag suppressions for acceptable violations
   */
  private addNagSuppressions(): void {
    // Suppress warnings for demo purposes - in production, address these properly
    NagSuppressions.addStackSuppressions(this, [
      {
        id: 'AwsSolutions-S3-1',
        reason: 'S3 server access logging not required for migration logs bucket in demo',
      },
      {
        id: 'AwsSolutions-IAM4',
        reason: 'AWS managed policies are acceptable for DMS service role',
      },
      {
        id: 'AwsSolutions-EC2-23',
        reason: 'Security group allows inbound for database connections within VPC',
      },
      {
        id: 'AwsSolutions-SNS2',
        reason: 'SNS topic encryption not required for demo alerting',
      },
      {
        id: 'AwsSolutions-SNS3',
        reason: 'SNS topic does not require SSL for demo purposes',
      },
    ]);
  }
}