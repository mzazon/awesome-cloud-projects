#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as dms from 'aws-cdk-lib/aws-dms';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Properties for the Aurora Minimal Downtime Migration Stack
 */
export interface AuroraMinimalDowntimeMigrationStackProps extends cdk.StackProps {
  /**
   * The instance class for Aurora database instances
   * @default db.r6g.large
   */
  readonly auroraInstanceClass?: ec2.InstanceType;

  /**
   * The instance class for DMS replication instance
   * @default dms.t3.medium
   */
  readonly dmsInstanceClass?: string;

  /**
   * Source database configuration
   */
  readonly sourceDatabase: {
    readonly hostname: string;
    readonly port: number;
    readonly username: string;
    readonly password: string;
    readonly databaseName: string;
    readonly engine: 'mysql' | 'postgresql' | 'oracle' | 'sqlserver';
  };

  /**
   * DNS zone name for Route 53 configuration
   * @default db.example.com
   */
  readonly dnsZoneName?: string;

  /**
   * Enable multi-AZ deployment for Aurora
   * @default true
   */
  readonly enableMultiAz?: boolean;

  /**
   * Enable encryption at rest for Aurora
   * @default true
   */
  readonly enableEncryption?: boolean;

  /**
   * Backup retention period in days
   * @default 7
   */
  readonly backupRetentionDays?: number;
}

/**
 * CDK Stack for implementing Aurora Minimal Downtime Migration
 * 
 * This stack creates the complete infrastructure for migrating on-premises databases
 * to Amazon Aurora with minimal downtime using AWS Database Migration Service (DMS).
 */
export class AuroraMinimalDowntimeMigrationStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly auroraCluster: rds.DatabaseCluster;
  public readonly dmsReplicationInstance: dms.CfnReplicationInstance;
  public readonly sourceEndpoint: dms.CfnEndpoint;
  public readonly targetEndpoint: dms.CfnEndpoint;
  public readonly migrationTask: dms.CfnReplicationTask;
  public readonly hostedZone: route53.HostedZone;

  constructor(scope: Construct, id: string, props: AuroraMinimalDowntimeMigrationStackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.addr.substring(0, 6).toLowerCase();

    // Create VPC with public and private subnets across multiple AZs
    this.vpc = this.createVpc();

    // Create security groups for Aurora and DMS
    const { auroraSecurityGroup, dmsSecurityGroup } = this.createSecurityGroups();

    // Create Aurora database credentials in Secrets Manager
    const auroraCredentials = this.createAuroraCredentials(uniqueSuffix);

    // Create Aurora cluster parameter group with optimized settings
    const clusterParameterGroup = this.createAuroraParameterGroup();

    // Create Aurora database cluster
    this.auroraCluster = this.createAuroraCluster(
      auroraSecurityGroup,
      auroraCredentials,
      clusterParameterGroup,
      uniqueSuffix,
      props
    );

    // Create DMS IAM roles
    const dmsVpcRole = this.createDmsVpcRole();

    // Create DMS replication subnet group
    const dmsSubnetGroup = this.createDmsSubnetGroup();

    // Create DMS replication instance
    this.dmsReplicationInstance = this.createDmsReplicationInstance(
      dmsSubnetGroup,
      dmsSecurityGroup,
      uniqueSuffix,
      props
    );

    // Create DMS endpoints
    const { sourceEndpoint, targetEndpoint } = this.createDmsEndpoints(
      uniqueSuffix,
      props,
      auroraCredentials
    );
    this.sourceEndpoint = sourceEndpoint;
    this.targetEndpoint = targetEndpoint;

    // Create DMS migration task
    this.migrationTask = this.createMigrationTask(uniqueSuffix, props);

    // Create Route 53 hosted zone for DNS-based cutover
    this.hostedZone = this.createRoute53HostedZone(props);

    // Create CloudWatch log group for DMS
    this.createCloudWatchLogGroup();

    // Output important information
    this.createOutputs(auroraCredentials);
  }

  /**
   * Creates a VPC with public and private subnets for secure database deployment
   */
  private createVpc(): ec2.Vpc {
    return new ec2.Vpc(this, 'AuroraMigrationVpc', {
      ipAddresses: ec2.IpAddresses.cidr('10.0.0.0/16'),
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
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });
  }

  /**
   * Creates security groups for Aurora and DMS with appropriate rules
   */
  private createSecurityGroups(): {
    auroraSecurityGroup: ec2.SecurityGroup;
    dmsSecurityGroup: ec2.SecurityGroup;
  } {
    // Security group for Aurora cluster
    const auroraSecurityGroup = new ec2.SecurityGroup(this, 'AuroraSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for Aurora cluster in migration',
      allowAllOutbound: false,
    });

    // Security group for DMS replication instance
    const dmsSecurityGroup = new ec2.SecurityGroup(this, 'DmsSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for DMS replication instance',
      allowAllOutbound: true,
    });

    // Allow DMS to connect to Aurora on MySQL port
    auroraSecurityGroup.addIngressRule(
      dmsSecurityGroup,
      ec2.Port.tcp(3306),
      'Allow DMS to access Aurora'
    );

    // Allow Aurora to connect to other Aurora instances for replication
    auroraSecurityGroup.addIngressRule(
      auroraSecurityGroup,
      ec2.Port.tcp(3306),
      'Allow Aurora cluster communication'
    );

    return { auroraSecurityGroup, dmsSecurityGroup };
  }

  /**
   * Creates Aurora database credentials in AWS Secrets Manager
   */
  private createAuroraCredentials(uniqueSuffix: string): secretsmanager.Secret {
    return new secretsmanager.Secret(this, 'AuroraCredentials', {
      secretName: `aurora-migration-credentials-${uniqueSuffix}`,
      description: 'Aurora database credentials for migration',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: 'admin' }),
        generateStringKey: 'password',
        excludeCharacters: '"@/\\\'',
        includeSpace: false,
        passwordLength: 16,
      },
    });
  }

  /**
   * Creates Aurora cluster parameter group with migration-optimized settings
   */
  private createAuroraParameterGroup(): rds.ParameterGroup {
    const parameterGroup = new rds.ParameterGroup(this, 'AuroraClusterParameterGroup', {
      engine: rds.DatabaseClusterEngine.auroraMysql({
        version: rds.AuroraMysqlEngineVersion.VER_8_0_35,
      }),
      description: 'Aurora cluster parameter group optimized for migration',
      parameters: {
        // Optimize buffer pool for better performance
        innodb_buffer_pool_size: '{DBInstanceClassMemory*3/4}',
        // Increase max connections for DMS
        max_connections: '1000',
        // Enable binary logging for potential future replication
        log_bin_trust_function_creators: '1',
        // Optimize for write-heavy workloads during migration
        innodb_flush_log_at_trx_commit: '2',
      },
    });

    return parameterGroup;
  }

  /**
   * Creates Aurora database cluster with high availability and security
   */
  private createAuroraCluster(
    securityGroup: ec2.SecurityGroup,
    credentials: secretsmanager.Secret,
    parameterGroup: rds.ParameterGroup,
    uniqueSuffix: string,
    props: AuroraMinimalDowntimeMigrationStackProps
  ): rds.DatabaseCluster {
    const cluster = new rds.DatabaseCluster(this, 'AuroraCluster', {
      clusterIdentifier: `aurora-migration-${uniqueSuffix}`,
      engine: rds.DatabaseClusterEngine.auroraMysql({
        version: rds.AuroraMysqlEngineVersion.VER_8_0_35,
      }),
      credentials: rds.Credentials.fromSecret(credentials),
      defaultDatabaseName: 'migrationdb',
      instances: 2, // Primary + read replica
      instanceProps: {
        instanceType: props.auroraInstanceClass || ec2.InstanceType.of(
          ec2.InstanceClass.R6G,
          ec2.InstanceSize.LARGE
        ),
        vpcSubnets: {
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
        securityGroups: [securityGroup],
        publiclyAccessible: false,
        enablePerformanceInsights: true,
        performanceInsightRetention: rds.PerformanceInsightRetention.DEFAULT,
      },
      parameterGroup,
      backup: {
        retention: cdk.Duration.days(props.backupRetentionDays || 7),
        preferredWindow: '03:00-04:00',
      },
      preferredMaintenanceWindow: 'sun:04:00-sun:05:00',
      cloudwatchLogsExports: ['error', 'general', 'slowquery'],
      cloudwatchLogsRetention: logs.RetentionDays.ONE_WEEK,
      storageEncrypted: props.enableEncryption !== false,
      monitoringInterval: cdk.Duration.minutes(1),
      deletionProtection: false, // Set to true for production
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Use SNAPSHOT for production
    });

    // Add tags for better resource management
    cdk.Tags.of(cluster).add('Name', `aurora-migration-${uniqueSuffix}`);
    cdk.Tags.of(cluster).add('Purpose', 'database-migration');
    cdk.Tags.of(cluster).add('Environment', 'migration');

    return cluster;
  }

  /**
   * Creates DMS VPC IAM role required for VPC configurations
   */
  private createDmsVpcRole(): iam.Role {
    const role = new iam.Role(this, 'DmsVpcRole', {
      roleName: 'dms-vpc-role',
      assumedBy: new iam.ServicePrincipal('dms.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonDMSVPCManagementRole'),
      ],
      description: 'IAM role for DMS VPC management',
    });

    return role;
  }

  /**
   * Creates DMS replication subnet group
   */
  private createDmsSubnetGroup(): dms.CfnReplicationSubnetGroup {
    const subnetIds = this.vpc.selectSubnets({
      subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
    }).subnetIds;

    return new dms.CfnReplicationSubnetGroup(this, 'DmsSubnetGroup', {
      replicationSubnetGroupIdentifier: 'dms-migration-subnet-group',
      replicationSubnetGroupDescription: 'DMS subnet group for database migration',
      subnetIds: subnetIds,
      tags: [
        { key: 'Name', value: 'dms-migration-subnet-group' },
        { key: 'Purpose', value: 'database-migration' },
      ],
    });
  }

  /**
   * Creates DMS replication instance for data migration
   */
  private createDmsReplicationInstance(
    subnetGroup: dms.CfnReplicationSubnetGroup,
    securityGroup: ec2.SecurityGroup,
    uniqueSuffix: string,
    props: AuroraMinimalDowntimeMigrationStackProps
  ): dms.CfnReplicationInstance {
    const replicationInstance = new dms.CfnReplicationInstance(this, 'DmsReplicationInstance', {
      replicationInstanceIdentifier: `dms-migration-${uniqueSuffix}`,
      replicationInstanceClass: props.dmsInstanceClass || 'dms.t3.medium',
      allocatedStorage: 100,
      autoMinorVersionUpgrade: true,
      engineVersion: '3.5.2',
      multiAz: props.enableMultiAz !== false,
      publiclyAccessible: false,
      replicationSubnetGroupIdentifier: subnetGroup.replicationSubnetGroupIdentifier,
      vpcSecurityGroupIds: [securityGroup.securityGroupId],
      tags: [
        { key: 'Name', value: `dms-migration-${uniqueSuffix}` },
        { key: 'Purpose', value: 'database-migration' },
      ],
    });

    replicationInstance.addDependency(subnetGroup);
    return replicationInstance;
  }

  /**
   * Creates DMS source and target endpoints
   */
  private createDmsEndpoints(
    uniqueSuffix: string,
    props: AuroraMinimalDowntimeMigrationStackProps,
    auroraCredentials: secretsmanager.Secret
  ): {
    sourceEndpoint: dms.CfnEndpoint;
    targetEndpoint: dms.CfnEndpoint;
  } {
    // Source database endpoint
    const sourceEndpoint = new dms.CfnEndpoint(this, 'SourceEndpoint', {
      endpointIdentifier: `source-${props.sourceDatabase.engine}-${uniqueSuffix}`,
      endpointType: 'source',
      engineName: props.sourceDatabase.engine,
      serverName: props.sourceDatabase.hostname,
      port: props.sourceDatabase.port,
      username: props.sourceDatabase.username,
      password: props.sourceDatabase.password,
      databaseName: props.sourceDatabase.databaseName,
      extraConnectionAttributes: this.getSourceExtraConnectionAttributes(props.sourceDatabase.engine),
      tags: [
        { key: 'Name', value: `source-${props.sourceDatabase.engine}-${uniqueSuffix}` },
        { key: 'Purpose', value: 'database-migration-source' },
      ],
    });

    // Target Aurora endpoint
    const targetEndpoint = new dms.CfnEndpoint(this, 'TargetEndpoint', {
      endpointIdentifier: `target-aurora-${uniqueSuffix}`,
      endpointType: 'target',
      engineName: 'aurora-mysql',
      serverName: this.auroraCluster.clusterEndpoint.hostname,
      port: this.auroraCluster.clusterEndpoint.port,
      username: auroraCredentials.secretValueFromJson('username').unsafeUnwrap(),
      password: auroraCredentials.secretValueFromJson('password').unsafeUnwrap(),
      databaseName: 'migrationdb',
      extraConnectionAttributes: 'parallelLoadThreads=8;maxFileSize=512000;',
      tags: [
        { key: 'Name', value: `target-aurora-${uniqueSuffix}` },
        { key: 'Purpose', value: 'database-migration-target' },
      ],
    });

    return { sourceEndpoint, targetEndpoint };
  }

  /**
   * Gets source-specific extra connection attributes for DMS
   */
  private getSourceExtraConnectionAttributes(engine: string): string {
    switch (engine) {
      case 'mysql':
        return 'heartbeatEnable=true;heartbeatFrequency=1;';
      case 'postgresql':
        return 'heartbeatEnable=true;heartbeatFrequency=1;slotName=dms_slot;';
      case 'oracle':
        return 'useLogminerReader=N;numberDataTypeScale=0;retryInterval=5;';
      case 'sqlserver':
        return 'safeguardPolicy=rely_on_sql_server_replication_agent;';
      default:
        return '';
    }
  }

  /**
   * Creates DMS migration task with table mappings and settings
   */
  private createMigrationTask(
    uniqueSuffix: string,
    props: AuroraMinimalDowntimeMigrationStackProps
  ): dms.CfnReplicationTask {
    // Table mapping rules for selective migration
    const tableMappings = {
      rules: [
        {
          'rule-type': 'selection',
          'rule-id': '1',
          'rule-name': '1',
          'object-locator': {
            'schema-name': '%',
            'table-name': '%',
          },
          'rule-action': 'include',
        },
        {
          'rule-type': 'transformation',
          'rule-id': '2',
          'rule-name': '2',
          'rule-target': 'schema',
          'object-locator': {
            'schema-name': '%',
          },
          'rule-action': 'rename',
          value: 'migrationdb',
        },
      ],
    };

    // Task settings optimized for Aurora migration
    const taskSettings = {
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
        BatchApplyEnabled: true,
        TaskRecoveryTableEnabled: false,
        ParallelApplyThreads: 8,
        ParallelApplyBufferSize: 1000,
        ParallelApplyQueuesPerThread: 4,
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
          { Id: 'SOURCE_UNLOAD', Severity: 'LOGGER_SEVERITY_DEFAULT' },
          { Id: 'TARGET_LOAD', Severity: 'LOGGER_SEVERITY_DEFAULT' },
          { Id: 'SOURCE_CAPTURE', Severity: 'LOGGER_SEVERITY_DEFAULT' },
          { Id: 'TARGET_APPLY', Severity: 'LOGGER_SEVERITY_DEFAULT' },
          { Id: 'TASK_MANAGER', Severity: 'LOGGER_SEVERITY_DEFAULT' },
        ],
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
        ApplyErrorDeletePolicy: 'IGNORE_RECORD',
        ApplyErrorInsertPolicy: 'LOG_ERROR',
        ApplyErrorUpdatePolicy: 'LOG_ERROR',
        ApplyErrorEscalationPolicy: 'LOG_ERROR',
        ApplyErrorEscalationCount: 0,
        FullLoadIgnoreConflicts: true,
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

    const migrationTask = new dms.CfnReplicationTask(this, 'MigrationTask', {
      replicationTaskIdentifier: `migration-task-${uniqueSuffix}`,
      sourceEndpointArn: this.sourceEndpoint.ref,
      targetEndpointArn: this.targetEndpoint.ref,
      replicationInstanceArn: this.dmsReplicationInstance.ref,
      migrationType: 'full-load-and-cdc',
      tableMappings: JSON.stringify(tableMappings),
      replicationTaskSettings: JSON.stringify(taskSettings),
      tags: [
        { key: 'Name', value: `migration-task-${uniqueSuffix}` },
        { key: 'Purpose', value: 'database-migration' },
      ],
    });

    migrationTask.addDependency(this.dmsReplicationInstance);
    migrationTask.addDependency(this.sourceEndpoint);
    migrationTask.addDependency(this.targetEndpoint);

    return migrationTask;
  }

  /**
   * Creates Route 53 hosted zone for DNS-based cutover
   */
  private createRoute53HostedZone(props: AuroraMinimalDowntimeMigrationStackProps): route53.HostedZone {
    const zoneName = props.dnsZoneName || 'db.example.com';

    return new route53.HostedZone(this, 'DatabaseHostedZone', {
      zoneName: zoneName,
      comment: 'DNS zone for database migration cutover',
    });
  }

  /**
   * Creates CloudWatch log group for DMS logging
   */
  private createCloudWatchLogGroup(): logs.LogGroup {
    return new logs.LogGroup(this, 'DmsLogGroup', {
      logGroupName: '/aws/dms/migration-logs',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
  }

  /**
   * Creates CloudFormation outputs for important resource information
   */
  private createOutputs(auroraCredentials: secretsmanager.Secret): void {
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for the migration infrastructure',
    });

    new cdk.CfnOutput(this, 'AuroraClusterIdentifier', {
      value: this.auroraCluster.clusterIdentifier,
      description: 'Aurora cluster identifier',
    });

    new cdk.CfnOutput(this, 'AuroraClusterEndpoint', {
      value: this.auroraCluster.clusterEndpoint.hostname,
      description: 'Aurora cluster writer endpoint',
    });

    new cdk.CfnOutput(this, 'AuroraReaderEndpoint', {
      value: this.auroraCluster.clusterReadEndpoint.hostname,
      description: 'Aurora cluster reader endpoint',
    });

    new cdk.CfnOutput(this, 'AuroraCredentialsSecretArn', {
      value: auroraCredentials.secretArn,
      description: 'ARN of the Aurora credentials secret in Secrets Manager',
    });

    new cdk.CfnOutput(this, 'DmsReplicationInstanceIdentifier', {
      value: this.dmsReplicationInstance.replicationInstanceIdentifier!,
      description: 'DMS replication instance identifier',
    });

    new cdk.CfnOutput(this, 'MigrationTaskIdentifier', {
      value: this.migrationTask.replicationTaskIdentifier!,
      description: 'DMS migration task identifier',
    });

    new cdk.CfnOutput(this, 'Route53HostedZoneId', {
      value: this.hostedZone.hostedZoneId,
      description: 'Route 53 hosted zone ID for DNS cutover',
    });

    new cdk.CfnOutput(this, 'Route53HostedZoneName', {
      value: this.hostedZone.zoneName,
      description: 'Route 53 hosted zone name for DNS cutover',
    });
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const sourceConfig = {
  hostname: app.node.tryGetContext('sourceHostname') || process.env.SOURCE_HOSTNAME || 'your-source-server.example.com',
  port: parseInt(app.node.tryGetContext('sourcePort') || process.env.SOURCE_PORT || '3306'),
  username: app.node.tryGetContext('sourceUsername') || process.env.SOURCE_USERNAME || 'your-source-username',
  password: app.node.tryGetContext('sourcePassword') || process.env.SOURCE_PASSWORD || 'your-source-password',
  databaseName: app.node.tryGetContext('sourceDatabaseName') || process.env.SOURCE_DATABASE_NAME || 'your-source-database',
  engine: (app.node.tryGetContext('sourceEngine') || process.env.SOURCE_ENGINE || 'mysql') as 'mysql' | 'postgresql' | 'oracle' | 'sqlserver',
};

// Create the stack
new AuroraMinimalDowntimeMigrationStack(app, 'AuroraMinimalDowntimeMigrationStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  sourceDatabase: sourceConfig,
  auroraInstanceClass: ec2.InstanceType.of(
    ec2.InstanceClass.R6G,
    ec2.InstanceSize.LARGE
  ),
  dmsInstanceClass: 'dms.t3.medium',
  dnsZoneName: app.node.tryGetContext('dnsZoneName') || 'db.example.com',
  enableMultiAz: true,
  enableEncryption: true,
  backupRetentionDays: 7,
  description: 'Infrastructure for Aurora minimal downtime database migration using DMS',
  tags: {
    Project: 'Aurora-Migration',
    Environment: 'Migration',
    ManagedBy: 'CDK',
  },
});

app.synth();