#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import {
  Stack,
  StackProps,
  Environment,
  RemovalPolicy,
  Duration,
  CfnOutput,
} from 'aws-cdk-lib';
import {
  Vpc,
  SubnetType,
  SecurityGroup,
  Port,
  Peer,
} from 'aws-cdk-lib/aws-ec2';
import {
  DatabaseInstance,
  DatabaseInstanceEngine,
  PostgresEngineVersion,
  ParameterGroup,
  SubnetGroup,
  DatabaseInstanceReadReplica,
  StorageType,
  PerformanceInsightRetention,
  InstanceClass,
  InstanceSize,
} from 'aws-cdk-lib/aws-rds';
import {
  Role,
  ServicePrincipal,
  ManagedPolicy,
  PolicyDocument,
  PolicyStatement,
  Effect,
} from 'aws-cdk-lib/aws-iam';
import {
  Alarm,
  Metric,
  ComparisonOperator,
} from 'aws-cdk-lib/aws-cloudwatch';
import {
  SnsAction,
} from 'aws-cdk-lib/aws-cloudwatch-actions';
import {
  Topic,
} from 'aws-cdk-lib/aws-sns';
import {
  EmailSubscription,
} from 'aws-cdk-lib/aws-sns-subscriptions';
import {
  HostedZone,
  CnameRecord,
  HealthCheck,
  HealthCheckType,
} from 'aws-cdk-lib/aws-route53';
import {
  Secret,
  SecretStringGenerator,
} from 'aws-cdk-lib/aws-secretsmanager';
import { Construct } from 'constructs';

/**
 * Configuration interface for the RDS Multi-AZ application
 */
interface RdsMultiAzConfig {
  primaryRegion: string;
  secondaryRegion: string;
  dbInstanceClass: InstanceClass;
  dbInstanceSize: InstanceSize;
  dbEngine: PostgresEngineVersion;
  dbAllocatedStorage: number;
  dbBackupRetentionDays: number;
  performanceInsightsRetentionDays: PerformanceInsightRetention;
  notificationEmail: string;
  domainName: string;
  environmentName: string;
}

/**
 * Properties for the Primary RDS Stack
 */
interface PrimaryRdsStackProps extends StackProps {
  config: RdsMultiAzConfig;
}

/**
 * Properties for the Secondary RDS Stack
 */
interface SecondaryRdsStackProps extends StackProps {
  config: RdsMultiAzConfig;
  primaryDbInstanceArn: string;
  primaryDbSecurityGroupId: string;
}

/**
 * Primary region RDS Multi-AZ stack with monitoring and networking
 */
class PrimaryRdsStack extends Stack {
  public readonly dbInstance: DatabaseInstance;
  public readonly dbSecurityGroup: SecurityGroup;
  public readonly dbEndpoint: string;
  public readonly vpc: Vpc;

  constructor(scope: Construct, id: string, props: PrimaryRdsStackProps) {
    super(scope, id, props);

    const { config } = props;

    // Create VPC with Multi-AZ subnets
    this.vpc = new Vpc(this, 'FinancialVpc', {
      maxAzs: 3,
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'private-subnet',
          subnetType: SubnetType.PRIVATE_WITH_EGRESS,
        },
        {
          cidrMask: 24,
          name: 'public-subnet',
          subnetType: SubnetType.PUBLIC,
        },
        {
          cidrMask: 28,
          name: 'database-subnet',
          subnetType: SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // Create security group for RDS
    this.dbSecurityGroup = new SecurityGroup(this, 'DbSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for Financial RDS instance',
      allowAllOutbound: false,
    });

    // Allow PostgreSQL access from application security groups
    this.dbSecurityGroup.addIngressRule(
      Peer.ipv4(this.vpc.vpcCidrBlock),
      Port.tcp(5432),
      'Allow PostgreSQL access from VPC'
    );

    // Create database secret
    const dbSecret = new Secret(this, 'DbSecret', {
      description: 'Database master user credentials',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: 'dbadmin' }),
        generateStringKey: 'password',
        excludeCharacters: '"@/\\\'',
        passwordLength: 32,
        requireEachIncludedType: true,
      },
    });

    // Create enhanced monitoring role
    const monitoringRole = new Role(this, 'RdsMonitoringRole', {
      assumedBy: new ServicePrincipal('monitoring.rds.amazonaws.com'),
      managedPolicies: [
        ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonRDSEnhancedMonitoringRole'),
      ],
    });

    // Create custom parameter group
    const parameterGroup = new ParameterGroup(this, 'DbParameterGroup', {
      engine: DatabaseInstanceEngine.postgres({
        version: config.dbEngine,
      }),
      description: 'Financial DB optimized parameters for high availability',
      parameters: {
        'log_statement': 'all',
        'log_min_duration_statement': '1000',
        'checkpoint_completion_target': '0.9',
        'shared_preload_libraries': 'pg_stat_statements',
        'track_activity_query_size': '2048',
        'log_lock_waits': 'on',
        'log_temp_files': '0',
        'track_functions': 'all',
        'track_io_timing': 'on',
      },
    });

    // Create subnet group
    const subnetGroup = new SubnetGroup(this, 'DbSubnetGroup', {
      vpc: this.vpc,
      description: 'Financial DB subnet group',
      vpcSubnets: {
        subnetType: SubnetType.PRIVATE_ISOLATED,
      },
    });

    // Create primary Multi-AZ RDS instance
    this.dbInstance = new DatabaseInstance(this, 'PrimaryDatabase', {
      engine: DatabaseInstanceEngine.postgres({
        version: config.dbEngine,
      }),
      instanceType: cdk.aws_ec2.InstanceType.of(config.dbInstanceClass, config.dbInstanceSize),
      credentials: {
        username: 'dbadmin',
        password: dbSecret.secretValueFromJson('password'),
      },
      vpc: this.vpc,
      securityGroups: [this.dbSecurityGroup],
      subnetGroup: subnetGroup,
      parameterGroup: parameterGroup,
      
      // Multi-AZ configuration
      multiAz: true,
      
      // Storage configuration
      allocatedStorage: config.dbAllocatedStorage,
      storageType: StorageType.GP3,
      storageEncrypted: true,
      
      // Backup configuration
      backupRetention: Duration.days(config.dbBackupRetentionDays),
      preferredBackupWindow: '03:00-04:00',
      preferredMaintenanceWindow: 'sun:04:00-sun:05:00',
      
      // Monitoring configuration
      monitoringInterval: Duration.minutes(1),
      monitoringRole: monitoringRole,
      enablePerformanceInsights: true,
      performanceInsightRetention: config.performanceInsightsRetentionDays,
      
      // Security configuration
      deletionProtection: true,
      
      // Logging configuration
      cloudwatchLogsExports: ['postgresql'],
      
      removalPolicy: RemovalPolicy.SNAPSHOT,
    });

    // Store the endpoint for cross-stack reference
    this.dbEndpoint = this.dbInstance.instanceEndpoint.hostname;

    // Create SNS topic for alerts
    const alertTopic = new Topic(this, 'DbAlertTopic', {
      displayName: 'Financial Database Alerts',
    });

    alertTopic.addSubscription(new EmailSubscription(config.notificationEmail));

    // Create CloudWatch alarms
    this.createCloudWatchAlarms(alertTopic);

    // Create hosted zone for DNS failover
    const hostedZone = new HostedZone(this, 'DatabaseHostedZone', {
      zoneName: config.domainName,
      comment: 'Private hosted zone for database failover',
    });

    // Create health check for primary database
    const primaryHealthCheck = new HealthCheck(this, 'PrimaryHealthCheck', {
      type: HealthCheckType.CALCULATED,
      childHealthCheckIds: [], // This would be populated with actual endpoint health checks
      healthThreshold: 1,
      inverted: false,
    });

    // Create primary DNS record with failover routing
    new CnameRecord(this, 'PrimaryDnsRecord', {
      zone: hostedZone,
      recordName: 'db',
      domainName: this.dbEndpoint,
      ttl: Duration.seconds(60),
      setIdentifier: 'primary',
      // Note: CDK doesn't directly support Route53 failover records
      // This would need to be implemented using CfnRecordSet
    });

    // Output important values
    new CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for cross-region reference',
      exportName: `${config.environmentName}-VpcId`,
    });

    new CfnOutput(this, 'DbInstanceId', {
      value: this.dbInstance.instanceIdentifier,
      description: 'Primary database instance identifier',
      exportName: `${config.environmentName}-DbInstanceId`,
    });

    new CfnOutput(this, 'DbInstanceArn', {
      value: this.dbInstance.instanceArn,
      description: 'Primary database instance ARN',
      exportName: `${config.environmentName}-DbInstanceArn`,
    });

    new CfnOutput(this, 'DbEndpoint', {
      value: this.dbEndpoint,
      description: 'Primary database endpoint',
      exportName: `${config.environmentName}-DbEndpoint`,
    });

    new CfnOutput(this, 'DbSecurityGroupId', {
      value: this.dbSecurityGroup.securityGroupId,
      description: 'Database security group ID',
      exportName: `${config.environmentName}-DbSecurityGroupId`,
    });

    new CfnOutput(this, 'HostedZoneId', {
      value: hostedZone.hostedZoneId,
      description: 'Route53 hosted zone ID',
      exportName: `${config.environmentName}-HostedZoneId`,
    });
  }

  /**
   * Create CloudWatch alarms for database monitoring
   */
  private createCloudWatchAlarms(alertTopic: Topic): void {
    // Database connection alarm
    new Alarm(this, 'DatabaseConnectionAlarm', {
      metric: new Metric({
        namespace: 'AWS/RDS',
        metricName: 'DatabaseConnections',
        dimensionsMap: {
          DBInstanceIdentifier: this.dbInstance.instanceIdentifier,
        },
        statistic: 'Maximum',
        period: Duration.minutes(5),
      }),
      threshold: 80,
      comparisonOperator: ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      alarmDescription: 'Alert when database connections exceed 80',
      treatMissingData: cdk.aws_cloudwatch.TreatMissingData.NOT_BREACHING,
    }).addAlarmAction(new SnsAction(alertTopic));

    // CPU utilization alarm
    new Alarm(this, 'DatabaseCpuAlarm', {
      metric: new Metric({
        namespace: 'AWS/RDS',
        metricName: 'CPUUtilization',
        dimensionsMap: {
          DBInstanceIdentifier: this.dbInstance.instanceIdentifier,
        },
        statistic: 'Average',
        period: Duration.minutes(5),
      }),
      threshold: 80,
      comparisonOperator: ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 3,
      alarmDescription: 'Alert when CPU utilization exceeds 80%',
      treatMissingData: cdk.aws_cloudwatch.TreatMissingData.NOT_BREACHING,
    }).addAlarmAction(new SnsAction(alertTopic));

    // Free storage space alarm
    new Alarm(this, 'DatabaseStorageAlarm', {
      metric: new Metric({
        namespace: 'AWS/RDS',
        metricName: 'FreeStorageSpace',
        dimensionsMap: {
          DBInstanceIdentifier: this.dbInstance.instanceIdentifier,
        },
        statistic: 'Average',
        period: Duration.minutes(5),
      }),
      threshold: 10 * 1024 * 1024 * 1024, // 10 GB in bytes
      comparisonOperator: ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 2,
      alarmDescription: 'Alert when free storage space is less than 10 GB',
      treatMissingData: cdk.aws_cloudwatch.TreatMissingData.NOT_BREACHING,
    }).addAlarmAction(new SnsAction(alertTopic));
  }
}

/**
 * Secondary region RDS read replica stack
 */
class SecondaryRdsStack extends Stack {
  public readonly readReplica: DatabaseInstanceReadReplica;
  public readonly vpc: Vpc;

  constructor(scope: Construct, id: string, props: SecondaryRdsStackProps) {
    super(scope, id, props);

    const { config, primaryDbInstanceArn } = props;

    // Create VPC in secondary region
    this.vpc = new Vpc(this, 'SecondaryVpc', {
      maxAzs: 3,
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'private-subnet',
          subnetType: SubnetType.PRIVATE_WITH_EGRESS,
        },
        {
          cidrMask: 24,
          name: 'public-subnet',
          subnetType: SubnetType.PUBLIC,
        },
        {
          cidrMask: 28,
          name: 'database-subnet',
          subnetType: SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // Create security group for read replica
    const replicaSecurityGroup = new SecurityGroup(this, 'ReplicaSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for Financial RDS read replica',
      allowAllOutbound: false,
    });

    replicaSecurityGroup.addIngressRule(
      Peer.ipv4(this.vpc.vpcCidrBlock),
      Port.tcp(5432),
      'Allow PostgreSQL access from VPC'
    );

    // Create subnet group for replica
    const replicaSubnetGroup = new SubnetGroup(this, 'ReplicaSubnetGroup', {
      vpc: this.vpc,
      description: 'Financial DB replica subnet group',
      vpcSubnets: {
        subnetType: SubnetType.PRIVATE_ISOLATED,
      },
    });

    // Create enhanced monitoring role for replica
    const monitoringRole = new Role(this, 'ReplicaMonitoringRole', {
      assumedBy: new ServicePrincipal('monitoring.rds.amazonaws.com'),
      managedPolicies: [
        ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonRDSEnhancedMonitoringRole'),
      ],
    });

    // Create cross-region read replica
    this.readReplica = new DatabaseInstanceReadReplica(this, 'ReadReplica', {
      sourceDatabaseInstance: DatabaseInstance.fromDatabaseInstanceAttributes(this, 'SourceDb', {
        instanceIdentifier: 'source-db',
        instanceEndpointAddress: 'placeholder',
        port: 5432,
        securityGroups: [],
      }),
      instanceType: cdk.aws_ec2.InstanceType.of(config.dbInstanceClass, config.dbInstanceSize),
      vpc: this.vpc,
      securityGroups: [replicaSecurityGroup],
      subnetGroup: replicaSubnetGroup,
      
      // Storage configuration
      storageEncrypted: true,
      
      // Monitoring configuration
      monitoringInterval: Duration.minutes(1),
      monitoringRole: monitoringRole,
      enablePerformanceInsights: true,
      performanceInsightRetention: config.performanceInsightsRetentionDays,
      
      // Security configuration
      deletionProtection: true,
      
      removalPolicy: RemovalPolicy.SNAPSHOT,
    });

    // Create SNS topic for replica alerts
    const replicaAlertTopic = new Topic(this, 'ReplicaAlertTopic', {
      displayName: 'Financial Database Replica Alerts',
    });

    replicaAlertTopic.addSubscription(new EmailSubscription(config.notificationEmail));

    // Create replica lag alarm
    new Alarm(this, 'ReplicaLagAlarm', {
      metric: new Metric({
        namespace: 'AWS/RDS',
        metricName: 'ReplicaLag',
        dimensionsMap: {
          DBInstanceIdentifier: this.readReplica.instanceIdentifier,
        },
        statistic: 'Average',
        period: Duration.minutes(5),
      }),
      threshold: 300, // 5 minutes
      comparisonOperator: ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      alarmDescription: 'Alert when replica lag exceeds 5 minutes',
      treatMissingData: cdk.aws_cloudwatch.TreatMissingData.NOT_BREACHING,
    }).addAlarmAction(new SnsAction(replicaAlertTopic));

    // Output replica information
    new CfnOutput(this, 'ReadReplicaEndpoint', {
      value: this.readReplica.instanceEndpoint.hostname,
      description: 'Read replica database endpoint',
      exportName: `${config.environmentName}-ReadReplicaEndpoint`,
    });

    new CfnOutput(this, 'ReadReplicaId', {
      value: this.readReplica.instanceIdentifier,
      description: 'Read replica instance identifier',
      exportName: `${config.environmentName}-ReadReplicaId`,
    });
  }
}

/**
 * Main CDK application
 */
class RdsMultiAzApp extends cdk.App {
  constructor() {
    super();

    // Configuration
    const config: RdsMultiAzConfig = {
      primaryRegion: this.node.tryGetContext('primaryRegion') || 'us-east-1',
      secondaryRegion: this.node.tryGetContext('secondaryRegion') || 'us-west-2',
      dbInstanceClass: InstanceClass.R5,
      dbInstanceSize: InstanceSize.XLARGE,
      dbEngine: PostgresEngineVersion.VER_15_4,
      dbAllocatedStorage: 500,
      dbBackupRetentionDays: 30,
      performanceInsightsRetentionDays: PerformanceInsightRetention.DEFAULT,
      notificationEmail: this.node.tryGetContext('notificationEmail') || 'admin@example.com',
      domainName: this.node.tryGetContext('domainName') || 'financial-db.internal',
      environmentName: this.node.tryGetContext('environmentName') || 'financial-prod',
    };

    // Primary region environment
    const primaryEnv: Environment = {
      account: process.env.CDK_DEFAULT_ACCOUNT,
      region: config.primaryRegion,
    };

    // Secondary region environment
    const secondaryEnv: Environment = {
      account: process.env.CDK_DEFAULT_ACCOUNT,
      region: config.secondaryRegion,
    };

    // Create primary stack
    const primaryStack = new PrimaryRdsStack(this, 'PrimaryRdsStack', {
      env: primaryEnv,
      config: config,
      description: 'Primary RDS Multi-AZ stack with monitoring and networking',
      tags: {
        Environment: config.environmentName,
        Application: 'FinancialDatabase',
        Stack: 'Primary',
      },
    });

    // Create secondary stack
    const secondaryStack = new SecondaryRdsStack(this, 'SecondaryRdsStack', {
      env: secondaryEnv,
      config: config,
      primaryDbInstanceArn: primaryStack.dbInstance.instanceArn,
      primaryDbSecurityGroupId: primaryStack.dbSecurityGroup.securityGroupId,
      description: 'Secondary RDS read replica stack for disaster recovery',
      tags: {
        Environment: config.environmentName,
        Application: 'FinancialDatabase',
        Stack: 'Secondary',
      },
    });

    // Add dependency to ensure primary stack deploys first
    secondaryStack.addDependency(primaryStack);
  }
}

// Instantiate and run the application
new RdsMultiAzApp();