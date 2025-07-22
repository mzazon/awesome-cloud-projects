#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as dms from 'aws-cdk-lib/aws-dms';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Configuration interface for the DMS Migration Stack
 */
interface DmsMigrationStackProps extends cdk.StackProps {
  /**
   * Source database configuration
   */
  sourceDatabase: {
    serverName: string;
    port: number;
    databaseName: string;
    username: string;
    password: string;
    engineName: string;
  };
  /**
   * Target database configuration
   */
  targetDatabase: {
    serverName: string;
    port: number;
    databaseName: string;
    username: string;
    password: string;
    engineName: string;
  };
  /**
   * DMS replication instance configuration
   */
  replicationInstance: {
    instanceClass: string;
    allocatedStorage: number;
    multiAz: boolean;
    publiclyAccessible: boolean;
  };
  /**
   * Migration task configuration
   */
  migrationTask: {
    migrationType: string;
    targetTablePrepMode: string;
  };
}

/**
 * AWS CDK Stack for Database Migration Service (DMS) implementation
 * 
 * This stack creates a complete DMS environment for database migration including:
 * - DMS replication instance with Multi-AZ support
 * - Source and target database endpoints with SSL encryption
 * - Migration task with full load and CDC capabilities
 * - Comprehensive monitoring with CloudWatch alarms
 * - SNS notifications for migration events
 * - Data validation and error handling
 */
export class DmsMigrationStack extends cdk.Stack {
  public readonly replicationInstance: dms.CfnReplicationInstance;
  public readonly sourceEndpoint: dms.CfnEndpoint;
  public readonly targetEndpoint: dms.CfnEndpoint;
  public readonly migrationTask: dms.CfnReplicationTask;
  public readonly alertsTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: DmsMigrationStackProps) {
    super(scope, id, props);

    // Get default VPC or create one if needed
    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVpc', {
      isDefault: true,
    });

    // Create CloudWatch Log Group for DMS logging
    const dmsLogGroup = new logs.LogGroup(this, 'DmsLogGroup', {
      logGroupName: `/aws/dms/migration-${this.stackName.toLowerCase()}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create IAM roles for DMS
    const dmsVpcRole = this.createDmsVpcRole();
    const dmsCloudWatchRole = this.createDmsCloudWatchRole();

    // Create SNS topic for alerts and notifications
    this.alertsTopic = new sns.Topic(this, 'DmsMigrationAlerts', {
      topicName: `dms-migration-alerts-${this.stackName.toLowerCase()}`,
      displayName: 'DMS Migration Alerts',
    });

    // Create DMS subnet group using VPC subnets
    const subnetGroup = new dms.CfnReplicationSubnetGroup(this, 'DmsSubnetGroup', {
      replicationSubnetGroupIdentifier: `dms-subnet-group-${this.stackName.toLowerCase()}`,
      replicationSubnetGroupDescription: 'DMS subnet group for database migration',
      subnetIds: vpc.privateSubnets.length > 0 
        ? vpc.privateSubnets.map(subnet => subnet.subnetId)
        : vpc.publicSubnets.map(subnet => subnet.subnetId),
      tags: [
        { key: 'Name', value: `DMS-SubnetGroup-${this.stackName}` },
        { key: 'Project', value: 'DatabaseMigration' },
        { key: 'Environment', value: 'Production' },
      ],
    });

    // Create DMS replication instance
    this.replicationInstance = new dms.CfnReplicationInstance(this, 'DmsReplicationInstance', {
      replicationInstanceIdentifier: `dms-replication-${this.stackName.toLowerCase()}`,
      replicationInstanceClass: props.replicationInstance.instanceClass,
      allocatedStorage: props.replicationInstance.allocatedStorage,
      replicationSubnetGroupIdentifier: subnetGroup.replicationSubnetGroupIdentifier,
      multiAz: props.replicationInstance.multiAz,
      publiclyAccessible: props.replicationInstance.publiclyAccessible,
      autoMinorVersionUpgrade: true,
      tags: [
        { key: 'Name', value: `DMS-ReplicationInstance-${this.stackName}` },
        { key: 'Project', value: 'DatabaseMigration' },
        { key: 'Environment', value: 'Production' },
      ],
    });

    // Add dependency to ensure subnet group is created first
    this.replicationInstance.addDependency(subnetGroup);

    // Create source database endpoint
    this.sourceEndpoint = new dms.CfnEndpoint(this, 'SourceEndpoint', {
      endpointIdentifier: `dms-source-${this.stackName.toLowerCase()}`,
      endpointType: 'source',
      engineName: props.sourceDatabase.engineName,
      serverName: props.sourceDatabase.serverName,
      port: props.sourceDatabase.port,
      databaseName: props.sourceDatabase.databaseName,
      username: props.sourceDatabase.username,
      password: props.sourceDatabase.password,
      sslMode: 'require',
      tags: [
        { key: 'Name', value: `DMS-SourceEndpoint-${this.stackName}` },
        { key: 'Project', value: 'DatabaseMigration' },
        { key: 'Type', value: 'Source' },
      ],
    });

    // Create target database endpoint
    this.targetEndpoint = new dms.CfnEndpoint(this, 'TargetEndpoint', {
      endpointIdentifier: `dms-target-${this.stackName.toLowerCase()}`,
      endpointType: 'target',
      engineName: props.targetDatabase.engineName,
      serverName: props.targetDatabase.serverName,
      port: props.targetDatabase.port,
      databaseName: props.targetDatabase.databaseName,
      username: props.targetDatabase.username,
      password: props.targetDatabase.password,
      sslMode: 'require',
      tags: [
        { key: 'Name', value: `DMS-TargetEndpoint-${this.stackName}` },
        { key: 'Project', value: 'DatabaseMigration' },
        { key: 'Type', value: 'Target' },
      ],
    });

    // Create table mappings for migration
    const tableMappings = {
      "rules": [
        {
          "rule-type": "selection",
          "rule-id": "1",
          "rule-name": "include-all-tables",
          "object-locator": {
            "schema-name": "%",
            "table-name": "%"
          },
          "rule-action": "include",
          "filters": []
        },
        {
          "rule-type": "transformation",
          "rule-id": "2",
          "rule-name": "add-prefix",
          "rule-target": "table",
          "object-locator": {
            "schema-name": "%",
            "table-name": "%"
          },
          "rule-action": "add-prefix",
          "value": "migrated_"
        }
      ]
    };

    // Create comprehensive replication task settings
    const replicationTaskSettings = {
      "TargetMetadata": {
        "TargetSchema": "",
        "SupportLobs": true,
        "FullLobMode": false,
        "LobChunkSize": 0,
        "LimitedSizeLobMode": true,
        "LobMaxSize": 32,
        "InlineLobMaxSize": 0,
        "LoadMaxFileSize": 0,
        "ParallelLoadThreads": 0,
        "ParallelLoadBufferSize": 0,
        "BatchApplyEnabled": false,
        "TaskRecoveryTableEnabled": false,
        "ParallelApplyThreads": 0,
        "ParallelApplyBufferSize": 0,
        "ParallelApplyQueuesPerThread": 0
      },
      "FullLoadSettings": {
        "TargetTablePrepMode": props.migrationTask.targetTablePrepMode,
        "CreatePkAfterFullLoad": false,
        "StopTaskCachedChangesApplied": false,
        "StopTaskCachedChangesNotApplied": false,
        "MaxFullLoadSubTasks": 8,
        "TransactionConsistencyTimeout": 600,
        "CommitRate": 10000
      },
      "Logging": {
        "EnableLogging": true,
        "CloudWatchLogGroup": dmsLogGroup.logGroupName,
        "CloudWatchLogStream": `dms-task-${this.stackName.toLowerCase()}`,
        "LogComponents": [
          {
            "Id": "SOURCE_UNLOAD",
            "Severity": "LOGGER_SEVERITY_DEFAULT"
          },
          {
            "Id": "TARGET_LOAD",
            "Severity": "LOGGER_SEVERITY_DEFAULT"
          },
          {
            "Id": "SOURCE_CAPTURE",
            "Severity": "LOGGER_SEVERITY_DEFAULT"
          },
          {
            "Id": "TARGET_APPLY",
            "Severity": "LOGGER_SEVERITY_DEFAULT"
          }
        ]
      },
      "ControlTablesSettings": {
        "ControlSchema": "",
        "HistoryTimeslotInMinutes": 5,
        "HistoryTableEnabled": false,
        "SuspendedTablesTableEnabled": false,
        "StatusTableEnabled": false
      },
      "StreamBufferSettings": {
        "StreamBufferCount": 3,
        "StreamBufferSizeInMB": 8,
        "CtrlStreamBufferSizeInMB": 5
      },
      "ChangeProcessingDdlHandlingPolicy": {
        "HandleSourceTableDropped": true,
        "HandleSourceTableTruncated": true,
        "HandleSourceTableAltered": true
      },
      "ErrorBehavior": {
        "DataErrorPolicy": "LOG_ERROR",
        "DataTruncationErrorPolicy": "LOG_ERROR",
        "DataErrorEscalationPolicy": "SUSPEND_TABLE",
        "DataErrorEscalationCount": 0,
        "TableErrorPolicy": "SUSPEND_TABLE",
        "TableErrorEscalationPolicy": "STOP_TASK",
        "TableErrorEscalationCount": 0,
        "RecoverableErrorCount": -1,
        "RecoverableErrorInterval": 5,
        "RecoverableErrorThrottling": true,
        "RecoverableErrorThrottlingMax": 1800,
        "RecoverableErrorStopRetryAfterThrottlingMax": true,
        "ApplyErrorDeletePolicy": "IGNORE_RECORD",
        "ApplyErrorInsertPolicy": "LOG_ERROR",
        "ApplyErrorUpdatePolicy": "LOG_ERROR",
        "ApplyErrorEscalationPolicy": "LOG_ERROR",
        "ApplyErrorEscalationCount": 0,
        "ApplyErrorFailOnTruncationDdl": false,
        "FullLoadIgnoreConflicts": true,
        "FailOnTransactionConsistencyBreached": false,
        "FailOnNoTablesCaptured": true
      },
      "ValidationSettings": {
        "EnableValidation": true,
        "ValidationMode": "ROW_LEVEL",
        "ThreadCount": 5,
        "PartitionSize": 10000,
        "FailureMaxCount": 10000,
        "RecordFailureDelayInMinutes": 5,
        "RecordSuspendDelayInMinutes": 30,
        "MaxKeyColumnSize": 8096,
        "TableFailureMaxCount": 1000,
        "ValidationOnly": false,
        "HandleCollationDiff": false,
        "RecordFailureDelayLimitInMinutes": 0,
        "SkipLobColumns": false,
        "ValidationPartialLobSize": 0,
        "ValidationQueryCdcDelaySeconds": 0
      },
      "ChangeProcessingTuning": {
        "BatchApplyPreserveTransaction": true,
        "BatchApplyTimeoutMin": 1,
        "BatchApplyTimeoutMax": 30,
        "BatchApplyMemoryLimit": 500,
        "BatchSplitSize": 0,
        "MinTransactionSize": 1000,
        "CommitTimeout": 1,
        "MemoryLimitTotal": 1024,
        "MemoryKeepTime": 60,
        "StatementCacheSize": 50
      }
    };

    // Create migration task with full load and CDC
    this.migrationTask = new dms.CfnReplicationTask(this, 'MigrationTask', {
      replicationTaskIdentifier: `dms-migration-task-${this.stackName.toLowerCase()}`,
      sourceEndpointArn: this.sourceEndpoint.ref,
      targetEndpointArn: this.targetEndpoint.ref,
      replicationInstanceArn: this.replicationInstance.ref,
      migrationType: props.migrationTask.migrationType,
      tableMappings: JSON.stringify(tableMappings),
      replicationTaskSettings: JSON.stringify(replicationTaskSettings),
      tags: [
        { key: 'Name', value: `DMS-MigrationTask-${this.stackName}` },
        { key: 'Project', value: 'DatabaseMigration' },
        { key: 'Environment', value: 'Production' },
      ],
    });

    // Add dependencies to ensure proper creation order
    this.migrationTask.addDependency(this.replicationInstance);
    this.migrationTask.addDependency(this.sourceEndpoint);
    this.migrationTask.addDependency(this.targetEndpoint);

    // Create DMS event subscription for monitoring
    const eventSubscription = new dms.CfnEventSubscription(this, 'DmsEventSubscription', {
      subscriptionName: `dms-migration-events-${this.stackName.toLowerCase()}`,
      snsTopicArn: this.alertsTopic.topicArn,
      sourceType: 'replication-task',
      eventCategories: ['failure', 'creation', 'deletion', 'state change'],
      sourceIds: [this.migrationTask.replicationTaskIdentifier!],
      enabled: true,
      tags: [
        { key: 'Name', value: `DMS-EventSubscription-${this.stackName}` },
        { key: 'Project', value: 'DatabaseMigration' },
      ],
    });

    // Add dependency to ensure task is created before subscription
    eventSubscription.addDependency(this.migrationTask);

    // Create CloudWatch alarms for monitoring
    this.createCloudWatchAlarms();

    // Output important resource information
    this.createOutputs();
  }

  /**
   * Creates the DMS VPC role required for DMS to access VPC resources
   */
  private createDmsVpcRole(): iam.Role {
    const role = new iam.Role(this, 'DmsVpcRole', {
      roleName: 'dms-vpc-role',
      assumedBy: new iam.ServicePrincipal('dms.amazonaws.com'),
      description: 'Role for DMS to access VPC resources',
    });

    role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonDMSVPCManagementRole')
    );

    return role;
  }

  /**
   * Creates the DMS CloudWatch role for logging
   */
  private createDmsCloudWatchRole(): iam.Role {
    const role = new iam.Role(this, 'DmsCloudWatchRole', {
      roleName: 'dms-cloudwatch-logs-role',
      assumedBy: new iam.ServicePrincipal('dms.amazonaws.com'),
      description: 'Role for DMS to write to CloudWatch Logs',
    });

    role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonDMSCloudWatchLogsRole')
    );

    return role;
  }

  /**
   * Creates CloudWatch alarms for monitoring migration task performance and health
   */
  private createCloudWatchAlarms(): void {
    // Alarm for task failures
    const taskFailureAlarm = new cloudwatch.Alarm(this, 'DmsTaskFailureAlarm', {
      alarmName: `DMS-Task-Failure-${this.stackName}`,
      alarmDescription: 'Alert when DMS task fails',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/DMS',
        metricName: 'ReplicationTaskStatus',
        dimensionsMap: {
          ReplicationTaskIdentifier: this.migrationTask.replicationTaskIdentifier!,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    taskFailureAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertsTopic));

    // Alarm for high CDC latency
    const highLatencyAlarm = new cloudwatch.Alarm(this, 'DmsHighLatencyAlarm', {
      alarmName: `DMS-High-Latency-${this.stackName}`,
      alarmDescription: 'Alert when DMS replication latency is high',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/DMS',
        metricName: 'CDCLatencySource',
        dimensionsMap: {
          ReplicationTaskIdentifier: this.migrationTask.replicationTaskIdentifier!,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 300, // 5 minutes
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    highLatencyAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertsTopic));

    // Alarm for low free memory on replication instance
    const lowMemoryAlarm = new cloudwatch.Alarm(this, 'DmsLowMemoryAlarm', {
      alarmName: `DMS-Low-Memory-${this.stackName}`,
      alarmDescription: 'Alert when DMS replication instance has low memory',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/DMS',
        metricName: 'FreeableMemory',
        dimensionsMap: {
          ReplicationInstanceIdentifier: this.replicationInstance.replicationInstanceIdentifier!,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 268435456, // 256 MB in bytes
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    lowMemoryAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertsTopic));
  }

  /**
   * Creates stack outputs for important resource identifiers and ARNs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'ReplicationInstanceArn', {
      value: this.replicationInstance.ref,
      description: 'ARN of the DMS replication instance',
      exportName: `${this.stackName}-ReplicationInstanceArn`,
    });

    new cdk.CfnOutput(this, 'SourceEndpointArn', {
      value: this.sourceEndpoint.ref,
      description: 'ARN of the DMS source endpoint',
      exportName: `${this.stackName}-SourceEndpointArn`,
    });

    new cdk.CfnOutput(this, 'TargetEndpointArn', {
      value: this.targetEndpoint.ref,
      description: 'ARN of the DMS target endpoint',
      exportName: `${this.stackName}-TargetEndpointArn`,
    });

    new cdk.CfnOutput(this, 'MigrationTaskArn', {
      value: this.migrationTask.ref,
      description: 'ARN of the DMS migration task',
      exportName: `${this.stackName}-MigrationTaskArn`,
    });

    new cdk.CfnOutput(this, 'AlertsTopicArn', {
      value: this.alertsTopic.topicArn,
      description: 'ARN of the SNS topic for DMS alerts',
      exportName: `${this.stackName}-AlertsTopicArn`,
    });

    new cdk.CfnOutput(this, 'ReplicationInstanceId', {
      value: this.replicationInstance.replicationInstanceIdentifier!,
      description: 'Identifier of the DMS replication instance',
    });

    new cdk.CfnOutput(this, 'MigrationTaskId', {
      value: this.migrationTask.replicationTaskIdentifier!,
      description: 'Identifier of the DMS migration task',
    });
  }
}

/**
 * Main CDK Application
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const sourceDbConfig = {
  serverName: app.node.tryGetContext('sourceServerName') || 'source-db.example.com',
  port: parseInt(app.node.tryGetContext('sourcePort') || '3306'),
  databaseName: app.node.tryGetContext('sourceDatabaseName') || 'sourcedb',
  username: app.node.tryGetContext('sourceUsername') || 'migration_user',
  password: app.node.tryGetContext('sourcePassword') || 'change-me-source-password',
  engineName: app.node.tryGetContext('sourceEngine') || 'mysql',
};

const targetDbConfig = {
  serverName: app.node.tryGetContext('targetServerName') || 'target-db.region.rds.amazonaws.com',
  port: parseInt(app.node.tryGetContext('targetPort') || '3306'),
  databaseName: app.node.tryGetContext('targetDatabaseName') || 'targetdb',
  username: app.node.tryGetContext('targetUsername') || 'admin',
  password: app.node.tryGetContext('targetPassword') || 'change-me-target-password',
  engineName: app.node.tryGetContext('targetEngine') || 'mysql',
};

const replicationConfig = {
  instanceClass: app.node.tryGetContext('replicationInstanceClass') || 'dms.t3.medium',
  allocatedStorage: parseInt(app.node.tryGetContext('allocatedStorage') || '100'),
  multiAz: app.node.tryGetContext('multiAz') === 'true',
  publiclyAccessible: app.node.tryGetContext('publiclyAccessible') !== 'false',
};

const migrationConfig = {
  migrationType: app.node.tryGetContext('migrationType') || 'full-load-and-cdc',
  targetTablePrepMode: app.node.tryGetContext('targetTablePrepMode') || 'DROP_AND_CREATE',
};

// Create the DMS migration stack
new DmsMigrationStack(app, 'DmsMigrationStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'AWS DMS Database Migration Stack - Complete migration solution with monitoring and validation',
  sourceDatabase: sourceDbConfig,
  targetDatabase: targetDbConfig,
  replicationInstance: replicationConfig,
  migrationTask: migrationConfig,
  tags: {
    Project: 'DatabaseMigration',
    Environment: 'Production',
    Owner: 'DataTeam',
    CostCenter: 'Migration',
  },
});

app.synth();