import * as cdk from 'aws-cdk-lib';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

export class MultiAzDatabaseStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Get existing default VPC or create a new one
    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVpc', {
      isDefault: true,
    });

    // Create a security group for the RDS cluster
    const databaseSecurityGroup = new ec2.SecurityGroup(this, 'DatabaseSecurityGroup', {
      vpc: vpc,
      description: 'Security group for Multi-AZ RDS cluster',
      allowAllOutbound: false,
    });

    // Allow inbound connections on PostgreSQL port from within VPC
    databaseSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(5432),
      'Allow PostgreSQL access from VPC'
    );

    // Allow inbound connections on MySQL port from within VPC (for flexibility)
    databaseSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(3306),
      'Allow MySQL access from VPC'
    );

    // Create a subnet group for the RDS cluster
    const subnetGroup = new rds.SubnetGroup(this, 'DatabaseSubnetGroup', {
      description: 'Subnet group for Multi-AZ RDS cluster',
      vpc: vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
    });

    // Create enhanced monitoring role for RDS
    const monitoringRole = new iam.Role(this, 'RdsMonitoringRole', {
      assumedBy: new iam.ServicePrincipal('monitoring.rds.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonRDSEnhancedMonitoringRole'),
      ],
    });

    // Create a secret for the database credentials
    const databaseCredentials = new secretsmanager.Secret(this, 'DatabaseCredentials', {
      description: 'Credentials for Multi-AZ RDS cluster',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: 'dbadmin' }),
        generateStringKey: 'password',
        excludeCharacters: '"@/\\',
        passwordLength: 20,
        includeSpace: false,
      },
    });

    // Create a parameter group for the cluster with optimized settings
    const clusterParameterGroup = new rds.ParameterGroup(this, 'ClusterParameterGroup', {
      engine: rds.DatabaseClusterEngine.auroraPostgres({
        version: rds.AuroraPostgresEngineVersion.VER_15_4,
      }),
      description: 'Parameter group for Multi-AZ PostgreSQL cluster',
      parameters: {
        // Enable query logging for monitoring
        'log_statement': 'all',
        'log_min_duration_statement': '1000',
        'shared_preload_libraries': 'pg_stat_statements',
        // Optimize for high availability
        'wal_buffers': '16MB',
        'checkpoint_completion_target': '0.9',
        'max_wal_size': '2GB',
      },
    });

    // Create the Aurora PostgreSQL cluster with Multi-AZ configuration
    const cluster = new rds.DatabaseCluster(this, 'MultiAzCluster', {
      engine: rds.DatabaseClusterEngine.auroraPostgres({
        version: rds.AuroraPostgresEngineVersion.VER_15_4,
      }),
      credentials: rds.Credentials.fromSecret(databaseCredentials),
      instanceProps: {
        instanceType: ec2.InstanceType.of(ec2.InstanceClass.R6G, ec2.InstanceSize.LARGE),
        vpcSubnets: {
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
        vpc: vpc,
        securityGroups: [databaseSecurityGroup],
        enablePerformanceInsights: true,
        performanceInsightRetention: rds.PerformanceInsightRetention.DEFAULT,
        monitoringInterval: cdk.Duration.seconds(60),
        monitoringRole: monitoringRole,
      },
      parameterGroup: clusterParameterGroup,
      subnetGroup: subnetGroup,
      // Multi-AZ configuration
      instances: 3, // 1 writer + 2 readers across different AZs
      storageEncrypted: true,
      // Backup configuration
      backup: {
        retention: cdk.Duration.days(14),
        preferredWindow: '03:00-04:00',
      },
      preferredMaintenanceWindow: 'sun:04:00-sun:05:00',
      // Enable CloudWatch logs export
      cloudwatchLogsExports: ['postgresql'],
      cloudwatchLogsRetention: logs.RetentionDays.ONE_WEEK,
      // Enable deletion protection
      deletionProtection: true,
      // Database name
      defaultDatabaseName: 'testdb',
    });

    // Create CloudWatch alarms for monitoring
    const highConnectionsAlarm = new cloudwatch.Alarm(this, 'HighConnectionsAlarm', {
      metric: cluster.metricDatabaseConnections({
        statistic: 'Maximum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 80,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'High database connections for Multi-AZ cluster',
    });

    const highCpuAlarm = new cloudwatch.Alarm(this, 'HighCpuAlarm', {
      metric: cluster.metricCPUUtilization({
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 80,
      evaluationPeriods: 3,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'High CPU utilization for Multi-AZ cluster',
    });

    // Store database connection information in Systems Manager Parameter Store
    new ssm.StringParameter(this, 'WriterEndpointParameter', {
      parameterName: `/rds/multiaz/${cluster.clusterIdentifier}/writer-endpoint`,
      stringValue: cluster.clusterEndpoint.socketAddress,
      description: 'Writer endpoint for Multi-AZ RDS cluster',
    });

    new ssm.StringParameter(this, 'ReaderEndpointParameter', {
      parameterName: `/rds/multiaz/${cluster.clusterIdentifier}/reader-endpoint`,
      stringValue: cluster.clusterReadEndpoint.socketAddress,
      description: 'Reader endpoint for Multi-AZ RDS cluster',
    });

    new ssm.StringParameter(this, 'DatabaseNameParameter', {
      parameterName: `/rds/multiaz/${cluster.clusterIdentifier}/database-name`,
      stringValue: 'testdb',
      description: 'Database name for Multi-AZ RDS cluster',
    });

    // Create a custom CloudWatch dashboard for comprehensive monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'MultiAzDashboard', {
      dashboardName: `${cluster.clusterIdentifier}-monitoring`,
    });

    // Add widgets to the dashboard
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Database Performance Metrics',
        left: [
          cluster.metricCPUUtilization(),
          cluster.metricDatabaseConnections(),
        ],
        right: [
          cluster.metricFreeableMemory(),
        ],
        width: 12,
        height: 6,
      })
    );

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Database I/O Operations',
        left: [
          cluster.metricReadIOPS(),
          cluster.metricWriteIOPS(),
        ],
        width: 12,
        height: 6,
      })
    );

    // Output important information
    new cdk.CfnOutput(this, 'ClusterIdentifier', {
      value: cluster.clusterIdentifier,
      description: 'RDS Cluster Identifier',
    });

    new cdk.CfnOutput(this, 'ClusterWriterEndpoint', {
      value: cluster.clusterEndpoint.socketAddress,
      description: 'RDS Cluster Writer Endpoint',
    });

    new cdk.CfnOutput(this, 'ClusterReaderEndpoint', {
      value: cluster.clusterReadEndpoint.socketAddress,
      description: 'RDS Cluster Reader Endpoint',
    });

    new cdk.CfnOutput(this, 'DatabaseCredentialsSecretArn', {
      value: databaseCredentials.secretArn,
      description: 'ARN of the secret containing database credentials',
    });

    new cdk.CfnOutput(this, 'DatabaseSecurityGroupId', {
      value: databaseSecurityGroup.securityGroupId,
      description: 'Security Group ID for the database cluster',
    });

    new cdk.CfnOutput(this, 'MonitoringDashboardUrl', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${cluster.clusterIdentifier}-monitoring`,
      description: 'URL to the CloudWatch monitoring dashboard',
    });
  }
}