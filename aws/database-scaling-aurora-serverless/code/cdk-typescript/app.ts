#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import { Construct } from 'constructs';

/**
 * Properties for the Aurora Serverless Scaling Stack
 */
interface AuroraServerlessScalingStackProps extends cdk.StackProps {
  /**
   * Minimum Aurora Capacity Units (ACUs) for scaling
   * @default 0.5
   */
  readonly minCapacity?: number;

  /**
   * Maximum Aurora Capacity Units (ACUs) for scaling
   * @default 16
   */
  readonly maxCapacity?: number;

  /**
   * Database name for the Aurora cluster
   * @default 'ecommerce'
   */
  readonly databaseName?: string;

  /**
   * Master username for the Aurora cluster
   * @default 'admin'
   */
  readonly masterUsername?: string;

  /**
   * Whether to create a read replica
   * @default true
   */
  readonly createReadReplica?: boolean;

  /**
   * Enable deletion protection for the cluster
   * @default true
   */
  readonly enableDeletionProtection?: boolean;

  /**
   * VPC CIDR for the database subnet
   * @default '10.0.0.0/16'
   */
  readonly vpcCidr?: string;
}

/**
 * CDK Stack for implementing Aurora Serverless v2 database scaling strategies
 * 
 * This stack creates:
 * - VPC with public and private subnets across multiple AZs
 * - Aurora Serverless v2 MySQL cluster with automatic scaling
 * - Read replica for horizontal scaling
 * - Security groups with least privilege access
 * - CloudWatch monitoring and alarms for capacity management
 * - Performance Insights for database optimization
 * - Secrets Manager for secure credential management
 */
export class AuroraServerlessScalingStack extends cdk.Stack {
  /**
   * The Aurora cluster instance
   */
  public readonly cluster: rds.DatabaseCluster;

  /**
   * The VPC containing the database resources
   */
  public readonly vpc: ec2.Vpc;

  /**
   * Security group for Aurora cluster access
   */
  public readonly databaseSecurityGroup: ec2.SecurityGroup;

  /**
   * CloudWatch alarms for monitoring scaling behavior
   */
  public readonly scalingAlarms: cloudwatch.Alarm[];

  constructor(scope: Construct, id: string, props: AuroraServerlessScalingStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const minCapacity = props.minCapacity ?? 0.5;
    const maxCapacity = props.maxCapacity ?? 16;
    const databaseName = props.databaseName ?? 'ecommerce';
    const masterUsername = props.masterUsername ?? 'admin';
    const createReadReplica = props.createReadReplica ?? true;
    const enableDeletionProtection = props.enableDeletionProtection ?? true;
    const vpcCidr = props.vpcCidr ?? '10.0.0.0/16';

    // Validate capacity settings
    if (minCapacity < 0.5 || minCapacity > maxCapacity) {
      throw new Error('Invalid capacity settings: minCapacity must be >= 0.5 and <= maxCapacity');
    }

    // Create VPC with public and private subnets for high availability
    this.vpc = new ec2.Vpc(this, 'AuroraVpc', {
      ipAddresses: ec2.IpAddresses.cidr(vpcCidr),
      maxAzs: 3,
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'PublicSubnet',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'PrivateSubnet',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // Create security group for Aurora cluster with least privilege access
    this.databaseSecurityGroup = new ec2.SecurityGroup(this, 'AuroraSecurity', {
      vpc: this.vpc,
      description: 'Security group for Aurora Serverless cluster',
      allowAllOutbound: false,
    });

    // Allow MySQL access from within VPC only
    this.databaseSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(this.vpc.vpcCidrBlock),
      ec2.Port.tcp(3306),
      'Allow MySQL access from VPC'
    );

    // Create enhanced monitoring role for Performance Insights
    const enhancedMonitoringRole = new iam.Role(this, 'EnhancedMonitoringRole', {
      assumedBy: new iam.ServicePrincipal('monitoring.rds.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonRDSEnhancedMonitoringRole'),
      ],
      description: 'Role for RDS Enhanced Monitoring and Performance Insights',
    });

    // Create database credentials in Secrets Manager for security
    const databaseCredentials = new secretsmanager.Secret(this, 'DatabaseCredentials', {
      description: 'Aurora Serverless cluster credentials',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: masterUsername }),
        generateStringKey: 'password',
        excludeCharacters: '"@/\\\'',
        passwordLength: 20,
        requireEachIncludedType: true,
      },
    });

    // Create custom DB parameter group for optimization
    const parameterGroup = new rds.ParameterGroup(this, 'AuroraParameterGroup', {
      engine: rds.DatabaseClusterEngine.auroraMysql({
        version: rds.AuroraMysqlEngineVersion.VER_8_0_MYSQL_3_02_0,
      }),
      description: 'Custom parameter group for Aurora Serverless optimization',
      parameters: {
        // Optimize for serverless scaling
        max_connections: '1000',
        innodb_buffer_pool_size: '{DBInstanceClassMemory*3/4}',
        query_cache_size: '0', // Disabled for better scaling performance
        innodb_flush_log_at_trx_commit: '2', // Balanced durability and performance
      },
    });

    // Create Aurora Serverless v2 cluster with automatic scaling
    this.cluster = new rds.DatabaseCluster(this, 'AuroraCluster', {
      engine: rds.DatabaseClusterEngine.auroraMysql({
        version: rds.AuroraMysqlEngineVersion.VER_8_0_MYSQL_3_02_0,
      }),
      vpc: this.vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      securityGroups: [this.databaseSecurityGroup],
      credentials: rds.Credentials.fromSecret(databaseCredentials),
      defaultDatabaseName: databaseName,
      parameterGroup: parameterGroup,
      
      // Serverless v2 scaling configuration
      serverlessV2MinCapacity: minCapacity,
      serverlessV2MaxCapacity: maxCapacity,
      
      // Backup and maintenance configuration
      backup: {
        retention: cdk.Duration.days(7),
        preferredWindow: '03:00-04:00',
      },
      preferredMaintenanceWindow: 'sun:04:00-sun:05:00',
      
      // Security and monitoring
      deletionProtection: enableDeletionProtection,
      storageEncrypted: true,
      monitoringInterval: cdk.Duration.seconds(60),
      monitoringRole: enhancedMonitoringRole,
      
      // CloudWatch logs export for comprehensive monitoring
      cloudwatchLogsExports: ['error', 'general', 'slowquery'],
      cloudwatchLogsRetention: cloudwatch.RetentionDays.ONE_WEEK,
      
      // Performance Insights for query optimization
      enablePerformanceInsights: true,
      performanceInsightRetention: rds.PerformanceInsightRetention.DEFAULT,
      
      // Instance configuration for writer
      writer: rds.ClusterInstance.serverlessV2('Writer', {
        enablePerformanceInsights: true,
        parameterGroup: rds.ParameterGroup.fromParameterGroupName(
          this,
          'WriterParams',
          'default.aurora-mysql8.0'
        ),
      }),
      
      // Add read replica if requested for horizontal scaling
      readers: createReadReplica ? [
        rds.ClusterInstance.serverlessV2('Reader', {
          enablePerformanceInsights: true,
          parameterGroup: rds.ParameterGroup.fromParameterGroupName(
            this,
            'ReaderParams',
            'default.aurora-mysql8.0'
          ),
        }),
      ] : [],
    });

    // Create CloudWatch alarms for proactive scaling monitoring
    this.scalingAlarms = [];

    // High ACU utilization alarm
    const highAcuAlarm = new cloudwatch.Alarm(this, 'HighAcuUtilization', {
      metric: this.cluster.metricServerlessDatabaseCapacity({
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: maxCapacity * 0.8, // Alert at 80% of max capacity
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'Aurora Serverless ACU usage is approaching maximum capacity',
      alarmName: `Aurora-${this.cluster.clusterIdentifier}-High-ACU`,
    });

    // Low ACU utilization alarm for cost optimization
    const lowAcuAlarm = new cloudwatch.Alarm(this, 'LowAcuUtilization', {
      metric: this.cluster.metricServerlessDatabaseCapacity({
        statistic: 'Average',
        period: cdk.Duration.minutes(15),
      }),
      threshold: minCapacity + 0.5, // Alert when consistently using minimal capacity
      evaluationPeriods: 4,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'Aurora Serverless ACU usage is consistently low - consider optimizing minimum capacity',
      alarmName: `Aurora-${this.cluster.clusterIdentifier}-Low-ACU`,
    });

    // Database connection alarm
    const connectionAlarm = new cloudwatch.Alarm(this, 'HighConnectionCount', {
      metric: this.cluster.metricDatabaseConnections({
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 800, // Alert before reaching max_connections
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'Aurora cluster connection count is high',
      alarmName: `Aurora-${this.cluster.clusterIdentifier}-High-Connections`,
    });

    this.scalingAlarms.push(highAcuAlarm, lowAcuAlarm, connectionAlarm);

    // Create CloudWatch dashboard for monitoring scaling behavior
    const dashboard = new cloudwatch.Dashboard(this, 'AuroraScalingDashboard', {
      dashboardName: `Aurora-Serverless-Scaling-${this.cluster.clusterIdentifier}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Aurora Serverless Capacity (ACUs)',
            left: [this.cluster.metricServerlessDatabaseCapacity()],
            width: 12,
            height: 6,
            period: cdk.Duration.minutes(5),
          }),
          new cloudwatch.GraphWidget({
            title: 'Database Connections',
            left: [this.cluster.metricDatabaseConnections()],
            width: 12,
            height: 6,
            period: cdk.Duration.minutes(5),
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'CPU Utilization',
            left: [this.cluster.metricCPUUtilization()],
            width: 12,
            height: 6,
            period: cdk.Duration.minutes(5),
          }),
          new cloudwatch.GraphWidget({
            title: 'Query Response Time',
            left: [this.cluster.metricSelectLatency()],
            width: 12,
            height: 6,
            period: cdk.Duration.minutes(5),
          }),
        ],
      ],
    });

    // Output important information for application integration
    new cdk.CfnOutput(this, 'ClusterEndpoint', {
      value: this.cluster.clusterEndpoint.socketAddress,
      description: 'Aurora cluster writer endpoint',
      exportName: `${this.stackName}-ClusterEndpoint`,
    });

    new cdk.CfnOutput(this, 'ClusterReadEndpoint', {
      value: this.cluster.clusterReadEndpoint.socketAddress,
      description: 'Aurora cluster reader endpoint',
      exportName: `${this.stackName}-ClusterReadEndpoint`,
    });

    new cdk.CfnOutput(this, 'ClusterIdentifier', {
      value: this.cluster.clusterIdentifier,
      description: 'Aurora cluster identifier',
      exportName: `${this.stackName}-ClusterIdentifier`,
    });

    new cdk.CfnOutput(this, 'DatabaseName', {
      value: databaseName,
      description: 'Default database name',
      exportName: `${this.stackName}-DatabaseName`,
    });

    new cdk.CfnOutput(this, 'SecretsManagerArn', {
      value: databaseCredentials.secretArn,
      description: 'Secrets Manager ARN for database credentials',
      exportName: `${this.stackName}-SecretsManagerArn`,
    });

    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID containing the Aurora cluster',
      exportName: `${this.stackName}-VpcId`,
    });

    new cdk.CfnOutput(this, 'SecurityGroupId', {
      value: this.databaseSecurityGroup.securityGroupId,
      description: 'Security Group ID for Aurora cluster',
      exportName: `${this.stackName}-SecurityGroupId`,
    });

    new cdk.CfnOutput(this, 'ScalingConfiguration', {
      value: `Min: ${minCapacity} ACUs, Max: ${maxCapacity} ACUs`,
      description: 'Aurora Serverless v2 scaling configuration',
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL for monitoring',
    });

    // Add tags for resource management and cost tracking
    cdk.Tags.of(this).add('Project', 'Aurora-Serverless-Scaling');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('CostCenter', 'Database');
    cdk.Tags.of(this).add('AutoShutdown', 'false');
  }
}

/**
 * Main CDK application entry point
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const minCapacity = app.node.tryGetContext('minCapacity') || 
                   (process.env.MIN_CAPACITY ? parseFloat(process.env.MIN_CAPACITY) : 0.5);
const maxCapacity = app.node.tryGetContext('maxCapacity') || 
                   (process.env.MAX_CAPACITY ? parseFloat(process.env.MAX_CAPACITY) : 16);
const databaseName = app.node.tryGetContext('databaseName') || 
                    process.env.DATABASE_NAME || 'ecommerce';
const enableDeletionProtection = app.node.tryGetContext('enableDeletionProtection') !== false;

// Create the stack with environment-specific configuration
new AuroraServerlessScalingStack(app, 'AuroraServerlessScalingStack', {
  minCapacity,
  maxCapacity,
  databaseName,
  enableDeletionProtection,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Aurora Serverless v2 database scaling strategies implementation with CDK TypeScript',
  tags: {
    Recipe: 'database-scaling-strategies-aurora-serverless',
    Version: '1.2',
    Generator: 'CDK-TypeScript',
  },
});

// Synthesize the CloudFormation template
app.synth();