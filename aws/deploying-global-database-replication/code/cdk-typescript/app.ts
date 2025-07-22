#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

/**
 * Configuration interface for Aurora Global Database deployment
 */
interface AuroraGlobalDatabaseConfig {
  /** Primary AWS region for the global database */
  readonly primaryRegion: string;
  /** Secondary AWS regions for read replicas */
  readonly secondaryRegions: string[];
  /** Database engine version */
  readonly engineVersion: string;
  /** Database instance class */
  readonly instanceClass: string;
  /** Database master username */
  readonly masterUsername: string;
  /** Environment name for resource naming */
  readonly environment: string;
}

/**
 * Aurora Global Database Stack
 * 
 * This stack creates an Aurora Global Database with multi-master capabilities
 * using write forwarding to enable applications to write to any region while
 * maintaining strong consistency across all regions.
 */
class AuroraGlobalDatabaseStack extends cdk.Stack {
  public readonly globalCluster: rds.CfnGlobalCluster;
  public readonly databaseSecret: secretsmanager.Secret;
  public readonly primaryCluster: rds.DatabaseCluster;
  public readonly secondaryClusters: rds.DatabaseCluster[] = [];
  public readonly monitoring: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, config: AuroraGlobalDatabaseConfig, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique identifier for resources
    const randomSuffix = Math.random().toString(36).substring(2, 8);
    const resourcePrefix = `aurora-global-${config.environment}-${randomSuffix}`;

    // Create database credentials secret
    this.databaseSecret = new secretsmanager.Secret(this, 'DatabaseSecret', {
      secretName: `${resourcePrefix}-credentials`,
      description: 'Master credentials for Aurora Global Database',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: config.masterUsername }),
        generateStringKey: 'password',
        excludeCharacters: '"@/\\',
        passwordLength: 16,
        requireEachIncludedType: true,
      },
    });

    // Create Aurora Global Database cluster
    this.globalCluster = new rds.CfnGlobalCluster(this, 'GlobalCluster', {
      globalClusterIdentifier: `${resourcePrefix}-global`,
      engine: 'aurora-mysql',
      engineVersion: config.engineVersion,
      storageEncrypted: true,
      deletionProtection: false, // Set to true for production
    });

    // Create primary cluster in the primary region
    this.primaryCluster = this.createPrimaryCluster(
      resourcePrefix,
      config,
      this.globalCluster,
      this.databaseSecret
    );

    // Create secondary clusters in secondary regions
    config.secondaryRegions.forEach((region, index) => {
      const secondaryCluster = this.createSecondaryCluster(
        resourcePrefix,
        config,
        this.globalCluster,
        region,
        index
      );
      this.secondaryClusters.push(secondaryCluster);
    });

    // Create monitoring dashboard
    this.monitoring = this.createMonitoringDashboard(
      resourcePrefix,
      this.primaryCluster,
      this.secondaryClusters
    );

    // Output important information
    this.createOutputs(resourcePrefix, config);
  }

  /**
   * Creates the primary Aurora cluster in the primary region
   */
  private createPrimaryCluster(
    resourcePrefix: string,
    config: AuroraGlobalDatabaseConfig,
    globalCluster: rds.CfnGlobalCluster,
    secret: secretsmanager.Secret
  ): rds.DatabaseCluster {
    // Create VPC for the primary cluster
    const vpc = new ec2.Vpc(this, 'PrimaryVPC', {
      maxAzs: 3,
      natGateways: 1,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
        {
          cidrMask: 24,
          name: 'isolated',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // Create security group for Aurora cluster
    const securityGroup = new ec2.SecurityGroup(this, 'PrimaryClusterSecurityGroup', {
      vpc,
      description: 'Security group for Aurora Global Database primary cluster',
      allowAllOutbound: true,
    });

    // Allow inbound connections from VPC
    securityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(3306),
      'MySQL/Aurora access from VPC'
    );

    // Create subnet group for Aurora cluster
    const subnetGroup = new rds.SubnetGroup(this, 'PrimarySubnetGroup', {
      vpc,
      description: 'Subnet group for Aurora Global Database primary cluster',
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
    });

    // Create parameter group for Aurora MySQL
    const parameterGroup = new rds.ParameterGroup(this, 'PrimaryParameterGroup', {
      engine: rds.DatabaseClusterEngine.auroraMysql({
        version: rds.AuroraMysqlEngineVersion.VER_8_0_MYSQL_3_02_0,
      }),
      description: 'Parameter group for Aurora Global Database primary cluster',
      parameters: {
        // Enable binlog for replication
        log_bin_trust_function_creators: '1',
        // Enable performance insights
        performance_insights_retention_period: '7',
        // Optimize for write forwarding
        aurora_replica_read_consistency: 'session',
      },
    });

    // Create the primary Aurora cluster
    const primaryCluster = new rds.DatabaseCluster(this, 'PrimaryCluster', {
      engine: rds.DatabaseClusterEngine.auroraMysql({
        version: rds.AuroraMysqlEngineVersion.VER_8_0_MYSQL_3_02_0,
      }),
      clusterIdentifier: `${resourcePrefix}-primary`,
      credentials: rds.Credentials.fromSecret(secret),
      instanceProps: {
        instanceType: ec2.InstanceType.of(
          ec2.InstanceClass.R5,
          ec2.InstanceSize.LARGE
        ),
        vpc,
        securityGroups: [securityGroup],
        enablePerformanceInsights: true,
        performanceInsightRetention: rds.PerformanceInsightRetention.DEFAULT,
      },
      instances: 2, // One writer, one reader
      subnetGroup,
      parameterGroup,
      backup: {
        retention: cdk.Duration.days(7),
        preferredWindow: '07:00-09:00',
      },
      preferredMaintenanceWindow: 'sun:09:00-sun:11:00',
      storageEncrypted: true,
      monitoringInterval: cdk.Duration.seconds(60),
      monitoringRole: this.createMonitoringRole(),
      deletionProtection: false, // Set to true for production
    });

    // Associate the primary cluster with the global cluster
    const cfnCluster = primaryCluster.node.defaultChild as rds.CfnDBCluster;
    cfnCluster.globalClusterIdentifier = globalCluster.ref;

    // Add dependency to ensure global cluster is created first
    primaryCluster.node.addDependency(globalCluster);

    return primaryCluster;
  }

  /**
   * Creates a secondary Aurora cluster in a specified region
   */
  private createSecondaryCluster(
    resourcePrefix: string,
    config: AuroraGlobalDatabaseConfig,
    globalCluster: rds.CfnGlobalCluster,
    region: string,
    index: number
  ): rds.DatabaseCluster {
    // Create VPC for the secondary cluster
    const vpc = new ec2.Vpc(this, `SecondaryVPC${index}`, {
      maxAzs: 3,
      natGateways: 1,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
        {
          cidrMask: 24,
          name: 'isolated',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // Create security group for secondary cluster
    const securityGroup = new ec2.SecurityGroup(this, `SecondaryClusterSecurityGroup${index}`, {
      vpc,
      description: `Security group for Aurora Global Database secondary cluster ${index}`,
      allowAllOutbound: true,
    });

    // Allow inbound connections from VPC
    securityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(3306),
      'MySQL/Aurora access from VPC'
    );

    // Create subnet group for secondary cluster
    const subnetGroup = new rds.SubnetGroup(this, `SecondarySubnetGroup${index}`, {
      vpc,
      description: `Subnet group for Aurora Global Database secondary cluster ${index}`,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
    });

    // Create parameter group for secondary cluster
    const parameterGroup = new rds.ParameterGroup(this, `SecondaryParameterGroup${index}`, {
      engine: rds.DatabaseClusterEngine.auroraMysql({
        version: rds.AuroraMysqlEngineVersion.VER_8_0_MYSQL_3_02_0,
      }),
      description: `Parameter group for Aurora Global Database secondary cluster ${index}`,
      parameters: {
        // Enable write forwarding for secondary cluster
        aurora_replica_read_consistency: 'session',
        // Enable performance insights
        performance_insights_retention_period: '7',
      },
    });

    // Create the secondary Aurora cluster
    const secondaryCluster = new rds.DatabaseCluster(this, `SecondaryCluster${index}`, {
      engine: rds.DatabaseClusterEngine.auroraMysql({
        version: rds.AuroraMysqlEngineVersion.VER_8_0_MYSQL_3_02_0,
      }),
      clusterIdentifier: `${resourcePrefix}-secondary-${region}`,
      instanceProps: {
        instanceType: ec2.InstanceType.of(
          ec2.InstanceClass.R5,
          ec2.InstanceSize.LARGE
        ),
        vpc,
        securityGroups: [securityGroup],
        enablePerformanceInsights: true,
        performanceInsightRetention: rds.PerformanceInsightRetention.DEFAULT,
      },
      instances: 2, // One writer with write forwarding, one reader
      subnetGroup,
      parameterGroup,
      storageEncrypted: true,
      monitoringInterval: cdk.Duration.seconds(60),
      monitoringRole: this.createMonitoringRole(),
      deletionProtection: false, // Set to true for production
    });

    // Configure the secondary cluster for global database and write forwarding
    const cfnCluster = secondaryCluster.node.defaultChild as rds.CfnDBCluster;
    cfnCluster.globalClusterIdentifier = globalCluster.ref;
    cfnCluster.enableGlobalWriteForwarding = true;

    // Add dependency to ensure global cluster and primary cluster are created first
    secondaryCluster.node.addDependency(globalCluster);
    secondaryCluster.node.addDependency(this.primaryCluster);

    return secondaryCluster;
  }

  /**
   * Creates an IAM role for enhanced monitoring
   */
  private createMonitoringRole(): iam.Role {
    return new iam.Role(this, 'MonitoringRole', {
      assumedBy: new iam.ServicePrincipal('monitoring.rds.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonRDSEnhancedMonitoringRole'),
      ],
    });
  }

  /**
   * Creates a CloudWatch dashboard for monitoring the global database
   */
  private createMonitoringDashboard(
    resourcePrefix: string,
    primaryCluster: rds.DatabaseCluster,
    secondaryClusters: rds.DatabaseCluster[]
  ): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'GlobalDatabaseDashboard', {
      dashboardName: `${resourcePrefix}-aurora-global-db`,
    });

    // Add metrics for primary cluster
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Primary Cluster - Database Connections',
        width: 12,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/RDS',
            metricName: 'DatabaseConnections',
            dimensionsMap: {
              DBClusterIdentifier: primaryCluster.clusterIdentifier,
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
          }),
        ],
      }),
      new cloudwatch.GraphWidget({
        title: 'Primary Cluster - CPU Utilization',
        width: 12,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/RDS',
            metricName: 'CPUUtilization',
            dimensionsMap: {
              DBClusterIdentifier: primaryCluster.clusterIdentifier,
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
          }),
        ],
      })
    );

    // Add replication lag metrics for secondary clusters
    if (secondaryClusters.length > 0) {
      const replicationLagMetrics = secondaryClusters.map(
        (cluster, index) =>
          new cloudwatch.Metric({
            namespace: 'AWS/RDS',
            metricName: 'AuroraGlobalDBReplicationLag',
            dimensionsMap: {
              DBClusterIdentifier: cluster.clusterIdentifier,
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
            label: `Secondary Cluster ${index + 1}`,
          })
      );

      dashboard.addWidgets(
        new cloudwatch.GraphWidget({
          title: 'Global Database Replication Lag',
          width: 24,
          height: 6,
          left: replicationLagMetrics,
        })
      );
    }

    return dashboard;
  }

  /**
   * Creates CloudFormation outputs for important resources
   */
  private createOutputs(resourcePrefix: string, config: AuroraGlobalDatabaseConfig): void {
    new cdk.CfnOutput(this, 'GlobalClusterIdentifier', {
      value: this.globalCluster.ref,
      description: 'Aurora Global Database cluster identifier',
      exportName: `${resourcePrefix}-global-cluster-id`,
    });

    new cdk.CfnOutput(this, 'PrimaryClusterEndpoint', {
      value: this.primaryCluster.clusterEndpoint.hostname,
      description: 'Primary cluster writer endpoint',
      exportName: `${resourcePrefix}-primary-writer-endpoint`,
    });

    new cdk.CfnOutput(this, 'PrimaryClusterReaderEndpoint', {
      value: this.primaryCluster.clusterReadEndpoint.hostname,
      description: 'Primary cluster reader endpoint',
      exportName: `${resourcePrefix}-primary-reader-endpoint`,
    });

    new cdk.CfnOutput(this, 'DatabaseSecretArn', {
      value: this.databaseSecret.secretArn,
      description: 'ARN of the secret containing database credentials',
      exportName: `${resourcePrefix}-database-secret-arn`,
    });

    new cdk.CfnOutput(this, 'MonitoringDashboardUrl', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${config.primaryRegion}#dashboards:name=${resourcePrefix}-aurora-global-db`,
      description: 'URL to the CloudWatch monitoring dashboard',
    });

    // Output secondary cluster endpoints
    this.secondaryClusters.forEach((cluster, index) => {
      new cdk.CfnOutput(this, `SecondaryCluster${index}Endpoint`, {
        value: cluster.clusterEndpoint.hostname,
        description: `Secondary cluster ${index + 1} writer endpoint with write forwarding`,
        exportName: `${resourcePrefix}-secondary-${index}-writer-endpoint`,
      });

      new cdk.CfnOutput(this, `SecondaryCluster${index}ReaderEndpoint`, {
        value: cluster.clusterReadEndpoint.hostname,
        description: `Secondary cluster ${index + 1} reader endpoint`,
        exportName: `${resourcePrefix}-secondary-${index}-reader-endpoint`,
      });
    });
  }
}

/**
 * Main CDK Application
 */
class AuroraGlobalDatabaseApp extends cdk.App {
  constructor() {
    super();

    // Configuration for the Aurora Global Database
    const config: AuroraGlobalDatabaseConfig = {
      primaryRegion: 'us-east-1',
      secondaryRegions: ['eu-west-1', 'ap-southeast-1'],
      engineVersion: '8.0.mysql_aurora.3.02.0',
      instanceClass: 'db.r5.large',
      masterUsername: 'globaladmin',
      environment: 'production',
    };

    // Create the Aurora Global Database stack
    new AuroraGlobalDatabaseStack(this, 'AuroraGlobalDatabaseStack', config, {
      env: {
        account: process.env.CDK_DEFAULT_ACCOUNT,
        region: config.primaryRegion,
      },
      description: 'Aurora Global Database with multi-master replication using write forwarding',
      tags: {
        Environment: config.environment,
        Application: 'Aurora Global Database',
        Purpose: 'Multi-master database replication',
      },
    });
  }
}

// Initialize and run the CDK application
const app = new AuroraGlobalDatabaseApp();
app.synth();