#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Properties for the PostgreSQL High Availability Stack
 */
interface PostgreSQLHAStackProps extends cdk.StackProps {
  /**
   * VPC to deploy the RDS cluster. If not provided, a new VPC will be created
   */
  vpc?: ec2.IVpc;
  
  /**
   * Database name for the PostgreSQL instance
   * @default 'productiondb'
   */
  databaseName?: string;
  
  /**
   * Master username for the database
   * @default 'dbadmin'
   */
  masterUsername?: string;
  
  /**
   * Email address for SNS notifications
   */
  notificationEmail?: string;
  
  /**
   * Enable cross-region disaster recovery
   * @default true
   */
  enableCrossRegionDR?: boolean;
  
  /**
   * Disaster recovery region
   * @default 'us-west-2'
   */
  drRegion?: string;
  
  /**
   * Backup retention period in days
   * @default 35
   */
  backupRetentionDays?: number;
  
  /**
   * Enable RDS Proxy for connection pooling
   * @default true
   */
  enableRdsProxy?: boolean;
  
  /**
   * Environment name (dev, staging, prod)
   * @default 'prod'
   */
  environment?: string;
}

/**
 * CDK Stack for PostgreSQL High Availability Cluster
 * 
 * This stack creates a production-grade PostgreSQL cluster with:
 * - Multi-AZ deployment for automatic failover
 * - Read replicas for scaling and disaster recovery
 * - Cross-region backup replication
 * - Comprehensive monitoring and alerting
 * - RDS Proxy for connection pooling
 * - Security best practices
 */
export class PostgreSQLHAStack extends cdk.Stack {
  public readonly primaryInstance: rds.DatabaseInstance;
  public readonly readReplica: rds.DatabaseInstanceReadReplica;
  public readonly crossRegionReplica: rds.DatabaseInstanceReadReplica;
  public readonly rdsProxy: rds.DatabaseProxy;
  public readonly databaseSecret: secretsmanager.Secret;
  public readonly vpc: ec2.IVpc;
  public readonly snsTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: PostgreSQLHAStackProps = {}) {
    super(scope, id, props);

    // Configuration with defaults
    const databaseName = props.databaseName || 'productiondb';
    const masterUsername = props.masterUsername || 'dbadmin';
    const enableCrossRegionDR = props.enableCrossRegionDR ?? true;
    const drRegion = props.drRegion || 'us-west-2';
    const backupRetentionDays = props.backupRetentionDays || 35;
    const enableRdsProxy = props.enableRdsProxy ?? true;
    const environment = props.environment || 'prod';

    // Tags for all resources
    const commonTags = {
      Environment: environment,
      Application: 'PostgreSQL-HA-Cluster',
      Recipe: 'high-availability-postgresql-clusters-amazon-rds',
      ManagedBy: 'AWS-CDK'
    };

    // Apply tags to the stack
    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('Application', 'PostgreSQL-HA-Cluster');
    cdk.Tags.of(this).add('Recipe', 'high-availability-postgresql-clusters-amazon-rds');
    cdk.Tags.of(this).add('ManagedBy', 'AWS-CDK');

    // Create or use existing VPC
    this.vpc = props.vpc || new ec2.Vpc(this, 'PostgreSQLVPC', {
      maxAzs: 3,
      natGateways: 2,
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
        {
          cidrMask: 24,
          name: 'Database',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // Create database secret for master password
    this.databaseSecret = new secretsmanager.Secret(this, 'DatabaseSecret', {
      description: 'PostgreSQL master password',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: masterUsername }),
        generateStringKey: 'password',
        excludeCharacters: '"@/\\\'',
        passwordLength: 32,
      },
    });

    // Create security group for RDS instances
    const dbSecurityGroup = new ec2.SecurityGroup(this, 'DatabaseSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for PostgreSQL HA cluster',
      allowAllOutbound: false,
    });

    // Allow PostgreSQL access from within VPC
    dbSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(this.vpc.vpcCidrBlock),
      ec2.Port.tcp(5432),
      'PostgreSQL access from VPC'
    );

    // Allow HTTPS outbound for RDS monitoring
    dbSecurityGroup.addEgressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'HTTPS for RDS monitoring'
    );

    // Create custom parameter group for PostgreSQL optimization
    const parameterGroup = new rds.ParameterGroup(this, 'PostgreSQLParameters', {
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_15_4,
      }),
      description: 'Optimized PostgreSQL parameters for HA cluster',
      parameters: {
        'log_statement': 'all',
        'log_min_duration_statement': '1000',
        'shared_preload_libraries': 'pg_stat_statements',
        'track_activity_query_size': '2048',
        'max_connections': '200',
        'shared_buffers': '{DBInstanceClassMemory/4}',
        'effective_cache_size': '{DBInstanceClassMemory*3/4}',
        'work_mem': '4MB',
        'maintenance_work_mem': '64MB',
        'random_page_cost': '1.1',
        'effective_io_concurrency': '200',
      },
    });

    // Create subnet group for RDS instances
    const subnetGroup = new rds.SubnetGroup(this, 'DatabaseSubnetGroup', {
      vpc: this.vpc,
      description: 'Subnet group for PostgreSQL HA cluster',
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
    });

    // Create SNS topic for alerts
    this.snsTopic = new sns.Topic(this, 'DatabaseAlerts', {
      displayName: 'PostgreSQL HA Cluster Alerts',
      description: 'Notifications for PostgreSQL cluster events and alarms',
    });

    // Subscribe email to SNS topic if provided
    if (props.notificationEmail) {
      this.snsTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(props.notificationEmail)
      );
    }

    // Create CloudWatch log group for PostgreSQL logs
    const logGroup = new logs.LogGroup(this, 'PostgreSQLLogGroup', {
      logGroupName: `/aws/rds/instance/${id.toLowerCase()}-primary/postgresql`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create enhanced monitoring role
    const monitoringRole = new iam.Role(this, 'RDSMonitoringRole', {
      assumedBy: new iam.ServicePrincipal('monitoring.rds.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonRDSEnhancedMonitoringRole'),
      ],
    });

    // Create primary PostgreSQL instance with Multi-AZ
    this.primaryInstance = new rds.DatabaseInstance(this, 'PostgreSQLPrimary', {
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_15_4,
      }),
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.R6G, ec2.InstanceSize.LARGE),
      credentials: rds.Credentials.fromSecret(this.databaseSecret),
      databaseName: databaseName,
      vpc: this.vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      securityGroups: [dbSecurityGroup],
      subnetGroup: subnetGroup,
      parameterGroup: parameterGroup,
      
      // High Availability Configuration
      multiAz: true,
      
      // Storage Configuration
      allocatedStorage: 200,
      storageType: rds.StorageType.GP3,
      storageEncrypted: true,
      storageEncryptionKey: undefined, // Use default KMS key
      
      // Backup Configuration
      backupRetention: cdk.Duration.days(backupRetentionDays),
      preferredBackupWindow: '03:00-04:00',
      preferredMaintenanceWindow: 'sun:04:00-sun:05:00',
      copyTagsToSnapshot: true,
      
      // Monitoring Configuration
      enablePerformanceInsights: true,
      performanceInsightRetention: rds.PerformanceInsightRetention.DEFAULT,
      monitoringInterval: cdk.Duration.seconds(60),
      monitoringRole: monitoringRole,
      
      // Logging Configuration
      cloudwatchLogsExports: ['postgresql'],
      cloudwatchLogsRetention: logs.RetentionDays.ONE_MONTH,
      
      // Security Configuration
      deletionProtection: true,
      
      // Network Configuration
      allowMajorVersionUpgrade: false,
      autoMinorVersionUpgrade: true,
      
      removalPolicy: cdk.RemovalPolicy.SNAPSHOT,
    });

    // Create read replica in same region for read scaling
    this.readReplica = new rds.DatabaseInstanceReadReplica(this, 'PostgreSQLReadReplica', {
      sourceDatabaseInstance: this.primaryInstance,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.R6G, ec2.InstanceSize.LARGE),
      vpc: this.vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      securityGroups: [dbSecurityGroup],
      
      // Monitoring Configuration
      enablePerformanceInsights: true,
      performanceInsightRetention: rds.PerformanceInsightRetention.DEFAULT,
      monitoringInterval: cdk.Duration.seconds(60),
      monitoringRole: monitoringRole,
      
      // Network Configuration
      allowMajorVersionUpgrade: false,
      autoMinorVersionUpgrade: true,
      
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create cross-region read replica for disaster recovery if enabled
    if (enableCrossRegionDR && drRegion !== this.region) {
      this.crossRegionReplica = new rds.DatabaseInstanceReadReplica(this, 'PostgreSQLCrossRegionReplica', {
        sourceDatabaseInstance: this.primaryInstance,
        instanceType: ec2.InstanceType.of(ec2.InstanceClass.R6G, ec2.InstanceSize.LARGE),
        
        // Cross-region configuration
        // Note: Cross-region replicas require manual VPC and subnet configuration in the target region
        // This is a simplified example - in production, you'd need a cross-region VPC setup
        
        // Monitoring Configuration
        enablePerformanceInsights: true,
        performanceInsightRetention: rds.PerformanceInsightRetention.DEFAULT,
        
        // Network Configuration
        allowMajorVersionUpgrade: false,
        autoMinorVersionUpgrade: true,
        
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      });
    }

    // Create RDS Proxy for connection pooling if enabled
    if (enableRdsProxy) {
      // Create IAM role for RDS Proxy
      const proxyRole = new iam.Role(this, 'RDSProxyRole', {
        assumedBy: new iam.ServicePrincipal('rds.amazonaws.com'),
        inlinePolicies: {
          SecretsManagerPolicy: new iam.PolicyDocument({
            statements: [
              new iam.PolicyStatement({
                effect: iam.Effect.ALLOW,
                actions: [
                  'secretsmanager:GetSecretValue',
                  'secretsmanager:DescribeSecret',
                ],
                resources: [this.databaseSecret.secretArn],
              }),
            ],
          }),
        },
      });

      // Create RDS Proxy
      this.rdsProxy = new rds.DatabaseProxy(this, 'PostgreSQLProxy', {
        proxyTarget: rds.ProxyTarget.fromInstance(this.primaryInstance),
        secrets: [this.databaseSecret],
        vpc: this.vpc,
        vpcSubnets: {
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
        securityGroups: [dbSecurityGroup],
        role: proxyRole,
        
        // Proxy Configuration
        maxConnectionsPercent: 100,
        maxIdleConnectionsPercent: 50,
        idleClientTimeout: cdk.Duration.minutes(30),
        requireTLS: true,
        
        // Connection Pooling Configuration
        sessionPinningFilters: [
          rds.SessionPinningFilter.EXCLUDE_VARIABLE_SETS,
        ],
      });
    }

    // Create CloudWatch Alarms for monitoring
    this.createCloudWatchAlarms();

    // Create RDS Event Subscription
    new rds.CfnEventSubscription(this, 'DatabaseEventSubscription', {
      snsTopicArn: this.snsTopic.topicArn,
      sourceType: 'db-instance',
      sourceIds: [
        this.primaryInstance.instanceIdentifier,
        this.readReplica.instanceIdentifier,
      ],
      eventCategories: [
        'availability',
        'backup',
        'configuration change',
        'creation',
        'deletion',
        'failover',
        'failure',
        'low storage',
        'maintenance',
        'notification',
        'recovery',
        'restoration',
      ],
      enabled: true,
    });

    // Output important information
    new cdk.CfnOutput(this, 'PrimaryEndpoint', {
      description: 'PostgreSQL Primary Instance Endpoint',
      value: this.primaryInstance.instanceEndpoint.hostname,
      exportName: `${id}-primary-endpoint`,
    });

    new cdk.CfnOutput(this, 'ReadReplicaEndpoint', {
      description: 'PostgreSQL Read Replica Endpoint',
      value: this.readReplica.instanceEndpoint.hostname,
      exportName: `${id}-read-replica-endpoint`,
    });

    if (this.rdsProxy) {
      new cdk.CfnOutput(this, 'ProxyEndpoint', {
        description: 'RDS Proxy Endpoint for Connection Pooling',
        value: this.rdsProxy.endpoint,
        exportName: `${id}-proxy-endpoint`,
      });
    }

    new cdk.CfnOutput(this, 'DatabaseSecret', {
      description: 'Database credentials secret ARN',
      value: this.databaseSecret.secretArn,
      exportName: `${id}-database-secret`,
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      description: 'SNS Topic for database alerts',
      value: this.snsTopic.topicArn,
      exportName: `${id}-sns-topic`,
    });

    if (this.crossRegionReplica) {
      new cdk.CfnOutput(this, 'CrossRegionReplicaEndpoint', {
        description: 'Cross-Region Disaster Recovery Replica Endpoint',
        value: this.crossRegionReplica.instanceEndpoint.hostname,
        exportName: `${id}-cross-region-replica-endpoint`,
      });
    }
  }

  /**
   * Create comprehensive CloudWatch alarms for database monitoring
   */
  private createCloudWatchAlarms(): void {
    // CPU Utilization Alarm for Primary Instance
    const cpuAlarm = new cloudwatch.Alarm(this, 'PostgreSQLCPUAlarm', {
      metric: this.primaryInstance.metricCPUUtilization({
        period: cdk.Duration.minutes(5),
        statistic: 'Average',
      }),
      threshold: 80,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'PostgreSQL primary instance CPU utilization is high',
    });
    cpuAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.snsTopic));

    // Database Connections Alarm
    const connectionsAlarm = new cloudwatch.Alarm(this, 'PostgreSQLConnectionsAlarm', {
      metric: this.primaryInstance.metricDatabaseConnections({
        period: cdk.Duration.minutes(5),
        statistic: 'Average',
      }),
      threshold: 150,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'PostgreSQL primary instance connection count is high',
    });
    connectionsAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.snsTopic));

    // Free Storage Space Alarm
    const storageAlarm = new cloudwatch.Alarm(this, 'PostgreSQLStorageAlarm', {
      metric: this.primaryInstance.metricFreeStorageSpace({
        period: cdk.Duration.minutes(5),
        statistic: 'Average',
      }),
      threshold: 10 * 1024 * 1024 * 1024, // 10 GB in bytes
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'PostgreSQL primary instance free storage space is low',
    });
    storageAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.snsTopic));

    // Read Replica Lag Alarm
    const replicaLagAlarm = new cloudwatch.Alarm(this, 'PostgreSQLReplicaLagAlarm', {
      metric: this.readReplica.metricReadReplicaLag({
        period: cdk.Duration.minutes(5),
        statistic: 'Average',
      }),
      threshold: 30, // 30 seconds
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'PostgreSQL read replica lag is high',
    });
    replicaLagAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.snsTopic));

    // IOPS Utilization Alarm
    const iopsAlarm = new cloudwatch.Alarm(this, 'PostgreSQLIOPSAlarm', {
      metric: new cloudwatch.Metric({
        namespace: 'AWS/RDS',
        metricName: 'ReadIOPS',
        dimensionsMap: {
          DBInstanceIdentifier: this.primaryInstance.instanceIdentifier,
        },
        period: cdk.Duration.minutes(5),
        statistic: 'Average',
      }).with(
        new cloudwatch.Metric({
          namespace: 'AWS/RDS',
          metricName: 'WriteIOPS',
          dimensionsMap: {
            DBInstanceIdentifier: this.primaryInstance.instanceIdentifier,
          },
          period: cdk.Duration.minutes(5),
          statistic: 'Average',
        }),
        cloudwatch.MathExpression.of('m1 + m2')
      ),
      threshold: 8000, // Adjust based on instance type IOPS limits
      evaluationPeriods: 3,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'PostgreSQL primary instance IOPS utilization is high',
    });
    iopsAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.snsTopic));
  }
}

/**
 * Main CDK Application
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID,
  region: process.env.CDK_DEFAULT_REGION || process.env.AWS_REGION || 'us-east-1',
};

const stackName = app.node.tryGetContext('stackName') || 'PostgreSQLHACluster';
const environment = app.node.tryGetContext('environment') || 'prod';
const notificationEmail = app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL;
const enableCrossRegionDR = app.node.tryGetContext('enableCrossRegionDR') !== 'false';
const drRegion = app.node.tryGetContext('drRegion') || 'us-west-2';

// Create the PostgreSQL HA stack
new PostgreSQLHAStack(app, stackName, {
  env: env,
  description: 'High-Availability PostgreSQL Cluster with Multi-AZ, Read Replicas, and Comprehensive Monitoring',
  
  // Stack configuration
  notificationEmail: notificationEmail,
  enableCrossRegionDR: enableCrossRegionDR,
  drRegion: drRegion,
  environment: environment,
  
  // Termination protection for production environments
  terminationProtection: environment === 'prod',
  
  // Stack tags
  tags: {
    Environment: environment,
    Application: 'PostgreSQL-HA-Cluster',
    Recipe: 'high-availability-postgresql-clusters-amazon-rds',
    ManagedBy: 'AWS-CDK',
    CostCenter: 'Database-Infrastructure',
    Backup: 'Required',
    Monitoring: 'Enhanced',
  },
});

// Synthesize the CDK app
app.synth();