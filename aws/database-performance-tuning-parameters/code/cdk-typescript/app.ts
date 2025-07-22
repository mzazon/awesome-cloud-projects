#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import { Construct } from 'constructs';

/**
 * Stack for implementing comprehensive database performance tuning using RDS Parameter Groups
 * for PostgreSQL optimization with CloudWatch monitoring and Performance Insights
 */
export class DatabasePerformanceTuningStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const randomSuffix = Math.random().toString(36).substring(2, 8);

    // Create VPC with isolated subnets for database deployment
    const vpc = new ec2.Vpc(this, 'PerformanceTuningVpc', {
      cidr: '10.0.0.0/16',
      maxAzs: 2,
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'database-subnet',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
      natGateways: 0, // No NAT gateways for isolated database subnets
    });

    // Create security group for database access
    const databaseSecurityGroup = new ec2.SecurityGroup(this, 'DatabaseSecurityGroup', {
      vpc,
      description: 'Security group for performance tuning database',
      allowAllOutbound: false,
    });

    // Allow PostgreSQL access from within VPC
    databaseSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(5432),
      'PostgreSQL access from VPC'
    );

    // Create database credentials secret
    const databaseCredentials = new secretsmanager.Secret(this, 'DatabaseCredentials', {
      description: 'Database credentials for performance tuning PostgreSQL instance',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: 'dbadmin' }),
        generateStringKey: 'password',
        excludeCharacters: '"@/\\\'',
        passwordLength: 32,
      },
    });

    // Create enhanced monitoring role for RDS
    const monitoringRole = new iam.Role(this, 'RdsMonitoringRole', {
      assumedBy: new iam.ServicePrincipal('monitoring.rds.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonRDSEnhancedMonitoringRole'),
      ],
    });

    // Create custom parameter group optimized for high-performance PostgreSQL workloads
    const parameterGroup = new rds.ParameterGroup(this, 'OptimizedParameterGroup', {
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_15_4,
      }),
      description: 'Performance tuning parameter group for PostgreSQL',
      parameters: {
        // Memory-related parameters optimized for db.t3.medium (4 GB RAM)
        shared_buffers: '1024MB', // 1GB shared buffers for efficient caching
        work_mem: '16MB', // Increased work memory for complex queries
        maintenance_work_mem: '256MB', // Enhanced maintenance operations
        effective_cache_size: '3GB', // Tell PostgreSQL about available OS cache

        // Connection and query optimization parameters
        max_connections: '200', // Increased connection limit
        random_page_cost: '1.1', // Optimized for SSD storage
        seq_page_cost: '1.0', // Sequential scan cost baseline
        effective_io_concurrency: '200', // SSD-optimized I/O concurrency

        // Query planner and statistics parameters
        default_statistics_target: '500', // Enhanced statistics for better query plans
        constraint_exclusion: 'partition', // Enable constraint exclusion for partitions
        cpu_tuple_cost: '0.01', // Fine-tuned CPU cost parameters
        cpu_index_tuple_cost: '0.005', // Optimized index tuple cost

        // Logging and monitoring parameters
        log_min_duration_statement: '1000', // Log slow queries (>1 second)
        log_checkpoints: '1', // Enable checkpoint logging
        log_connections: '1', // Log database connections
        log_disconnections: '1', // Log database disconnections

        // Checkpoint and WAL optimization
        checkpoint_completion_target: '0.9', // Spread out checkpoint I/O
        wal_buffers: '16MB', // Increased WAL buffer size
        checkpoint_timeout: '15min', // Extended checkpoint timeout

        // Advanced parameters for analytical workloads
        from_collapse_limit: '20', // Enhanced query planning limits
        join_collapse_limit: '20',
        geqo_threshold: '15', // Genetic query optimization threshold
        geqo_effort: '8', // Increased GEQO effort

        // Mixed OLTP/OLAP workload optimization
        max_parallel_workers_per_gather: '2', // Enable parallel query execution
        max_parallel_workers: '4', // Total parallel workers
        parallel_tuple_cost: '0.1', // Parallel query cost parameters
        parallel_setup_cost: '1000',

        // Autovacuum optimization for performance
        autovacuum_vacuum_scale_factor: '0.1', // More aggressive vacuum
        autovacuum_analyze_scale_factor: '0.05', // More frequent analyze
        autovacuum_work_mem: '256MB', // Increased autovacuum memory
      },
    });

    // Create subnet group for RDS
    const subnetGroup = new rds.SubnetGroup(this, 'DatabaseSubnetGroup', {
      vpc,
      description: 'Subnet group for performance tuning database',
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
    });

    // Create primary PostgreSQL database instance with performance optimization
    const database = new rds.DatabaseInstance(this, 'PostgreSQLDatabase', {
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_15_4,
      }),
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM),
      credentials: rds.Credentials.fromSecret(databaseCredentials),
      vpc,
      subnetGroup,
      securityGroups: [databaseSecurityGroup],
      parameterGroup,
      
      // Storage configuration optimized for performance
      allocatedStorage: 100,
      storageType: rds.StorageType.GP3,
      storageEncrypted: true,
      
      // Performance monitoring configuration
      enablePerformanceInsights: true,
      performanceInsightRetention: rds.PerformanceInsightRetention.DEFAULT,
      monitoringInterval: cdk.Duration.seconds(60),
      monitoringRole,
      
      // CloudWatch Logs exports for enhanced monitoring
      cloudwatchLogsExports: ['postgresql'],
      
      // Backup and maintenance configuration
      backupRetention: cdk.Duration.days(7),
      copyTagsToSnapshot: true,
      autoMinorVersionUpgrade: false, // Prevent automatic upgrades during tuning
      deletionProtection: false, // Allow deletion for testing purposes
      
      // Enhanced monitoring for detailed metrics
      databaseName: 'postgres',
    });

    // Create read replica with same optimized parameters for read scaling
    const readReplica = new rds.DatabaseInstanceReadReplica(this, 'DatabaseReadReplica', {
      sourceDatabaseInstance: database,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM),
      vpc,
      securityGroups: [databaseSecurityGroup],
      parameterGroup,
      
      // Enable Performance Insights for replica monitoring
      enablePerformanceInsights: true,
      performanceInsightRetention: rds.PerformanceInsightRetention.DEFAULT,
      monitoringInterval: cdk.Duration.seconds(60),
      monitoringRole,
      
      // Auto minor version upgrade disabled for consistency
      autoMinorVersionUpgrade: false,
      deletionProtection: false,
    });

    // Create CloudWatch dashboard for comprehensive performance monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'DatabasePerformanceDashboard', {
      dashboardName: `Database-Performance-Tuning-${randomSuffix}`,
    });

    // Database performance overview widget
    const performanceOverviewWidget = new cloudwatch.GraphWidget({
      title: 'Database Performance Overview',
      width: 12,
      height: 6,
      left: [
        database.metricDatabaseConnections(),
        database.metricCPUUtilization(),
        database.metricFreeableMemory(),
        database.metricReadLatency(),
        database.metricWriteLatency(),
      ],
    });

    // Database I/O performance widget
    const ioPerformanceWidget = new cloudwatch.GraphWidget({
      title: 'Database I/O Performance',
      width: 12,
      height: 6,
      left: [
        database.metricDatabaseConnections(),
        database.metricReadIOPS(),
        database.metricWriteIOPS(),
        database.metricReadThroughput(),
        database.metricWriteThroughput(),
      ],
    });

    // Add widgets to dashboard
    dashboard.addWidgets(performanceOverviewWidget, ioPerformanceWidget);

    // Create CloudWatch alarms for database performance monitoring
    
    // High CPU utilization alarm
    const highCpuAlarm = new cloudwatch.Alarm(this, 'DatabaseHighCpuAlarm', {
      metric: database.metricCPUUtilization(),
      threshold: 80,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'High CPU utilization on tuned database',
    });

    // High connection count alarm
    const highConnectionsAlarm = new cloudwatch.Alarm(this, 'DatabaseHighConnectionsAlarm', {
      metric: database.metricDatabaseConnections(),
      threshold: 150,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'High connection count on tuned database',
    });

    // High read latency alarm
    const highReadLatencyAlarm = new cloudwatch.Alarm(this, 'DatabaseHighReadLatencyAlarm', {
      metric: database.metricReadLatency(),
      threshold: 0.1, // 100ms
      evaluationPeriods: 3,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'High read latency on tuned database',
    });

    // Output important resource information
    new cdk.CfnOutput(this, 'DatabaseEndpoint', {
      value: database.instanceEndpoint.socketAddress,
      description: 'Primary database endpoint for connections',
    });

    new cdk.CfnOutput(this, 'ReadReplicaEndpoint', {
      value: readReplica.instanceEndpoint.socketAddress,
      description: 'Read replica endpoint for read-only connections',
    });

    new cdk.CfnOutput(this, 'DatabaseCredentialsSecret', {
      value: databaseCredentials.secretArn,
      description: 'ARN of the secret containing database credentials',
    });

    new cdk.CfnOutput(this, 'ParameterGroupName', {
      value: parameterGroup.parameterGroupName,
      description: 'Name of the optimized parameter group',
    });

    new cdk.CfnOutput(this, 'DatabaseSecurityGroupId', {
      value: databaseSecurityGroup.securityGroupId,
      description: 'Security group ID for database access',
    });

    new cdk.CfnOutput(this, 'VpcId', {
      value: vpc.vpcId,
      description: 'VPC ID containing the database infrastructure',
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch dashboard URL for performance monitoring',
    });

    // Add tags to all resources for cost tracking and management
    cdk.Tags.of(this).add('Purpose', 'DatabasePerformanceTuning');
    cdk.Tags.of(this).add('Environment', 'Testing');
    cdk.Tags.of(this).add('Recipe', 'database-performance-tuning-parameter-groups');
  }
}

// Create CDK app and instantiate the stack
const app = new cdk.App();
new DatabasePerformanceTuningStack(app, 'DatabasePerformanceTuningStack', {
  description: 'Database Performance Tuning with Parameter Groups - PostgreSQL optimization with monitoring',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});