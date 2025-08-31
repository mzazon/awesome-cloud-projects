#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as vpclattice from 'aws-cdk-lib/aws-vpclattice';
import { Construct } from 'constructs';

/**
 * Stack for VPC Lattice TCP Resource Connectivity with CloudWatch Monitoring
 * 
 * This stack demonstrates how to create a VPC Lattice service network that enables
 * secure TCP connectivity to RDS database instances across VPCs with comprehensive
 * CloudWatch monitoring for performance and cost optimization.
 */
class TcpResourceConnectivityStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Parameters for customization
    const dbInstanceClass = new cdk.CfnParameter(this, 'DbInstanceClass', {
      type: 'String',
      default: 'db.t3.micro',
      description: 'RDS instance class for the MySQL database',
      allowedValues: ['db.t3.micro', 'db.t3.small', 'db.t3.medium', 'db.t3.large']
    });

    const dbAllocatedStorage = new cdk.CfnParameter(this, 'DbAllocatedStorage', {
      type: 'Number',
      default: 20,
      minValue: 20,
      maxValue: 100,
      description: 'Allocated storage for RDS instance in GB'
    });

    const dbPort = new cdk.CfnParameter(this, 'DbPort', {
      type: 'Number',
      default: 3306,
      description: 'Port for MySQL database'
    });

    // Use existing default VPC for this demo
    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVpc', {
      isDefault: true
    });

    // Create security group for RDS with restricted access
    const rdsSecurityGroup = new ec2.SecurityGroup(this, 'RdsSecurityGroup', {
      vpc,
      description: 'Security group for RDS instance with VPC Lattice access',
      allowAllOutbound: false
    });

    // Allow MySQL traffic from VPC CIDR (VPC Lattice will manage specific routing)
    rdsSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(dbPort.valueAsNumber),
      'Allow MySQL traffic from VPC CIDR for VPC Lattice'
    );

    // Create DB subnet group using private subnets
    const dbSubnetGroup = new rds.SubnetGroup(this, 'DbSubnetGroup', {
      description: 'Subnet group for RDS instance in private subnets',
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        availabilityZones: vpc.availabilityZones.slice(0, 2) // Use first 2 AZs
      }
    });

    // Create RDS MySQL instance
    const dbInstance = new rds.DatabaseInstance(this, 'DatabaseInstance', {
      engine: rds.DatabaseInstanceEngine.mysql({
        version: rds.MysqlEngineVersion.VER_8_0_35
      }),
      instanceType: ec2.InstanceType.of(
        ec2.InstanceClass.BURSTABLE3,
        ec2.InstanceSize.MICRO
      ),
      vpc,
      subnetGroup: dbSubnetGroup,
      securityGroups: [rdsSecurityGroup],
      multiAz: false, // Single AZ for cost optimization in demo
      allocatedStorage: dbAllocatedStorage.valueAsNumber,
      storageEncrypted: true,
      deletionProtection: false, // Allow deletion for demo cleanup
      backupRetention: cdk.Duration.days(1), // Minimal backup for demo
      deleteAutomatedBackups: true,
      databaseName: 'demodb',
      credentials: rds.Credentials.fromGeneratedSecret('admin', {
        description: 'RDS MySQL admin credentials',
        excludeCharacters: '"@/\\'
      }),
      port: dbPort.valueAsNumber,
      publiclyAccessible: false,
      removalPolicy: cdk.RemovalPolicy.DESTROY // Allow resource cleanup
    });

    // Create IAM role for VPC Lattice service
    const latticeServiceRole = new iam.Role(this, 'VpcLatticeServiceRole', {
      assumedBy: new iam.ServicePrincipal('vpc-lattice.amazonaws.com'),
      description: 'Service role for VPC Lattice operations',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/VPCLatticeServiceRolePolicy')
      ]
    });

    // Create VPC Lattice Service Network
    const serviceNetwork = new vpclattice.CfnServiceNetwork(this, 'DatabaseServiceNetwork', {
      name: `database-service-network-${cdk.Names.uniqueId(this).toLowerCase()}`,
      authType: 'AWS_IAM'
    });

    // Create VPC Lattice Target Group for RDS instance
    const targetGroup = new vpclattice.CfnTargetGroup(this, 'RdsTargetGroup', {
      name: `rds-tcp-targets-${cdk.Names.uniqueId(this).toLowerCase()}`,
      type: 'IP',
      config: {
        port: dbPort.valueAsNumber,
        protocol: 'TCP',
        vpcIdentifier: vpc.vpcId,
        healthCheck: {
          enabled: true,
          protocol: 'TCP',
          port: dbPort.valueAsNumber,
          healthCheckIntervalSeconds: 30,
          healthCheckTimeoutSeconds: 5,
          healthyThresholdCount: 2,
          unhealthyThresholdCount: 2
        }
      },
      targets: [
        {
          id: dbInstance.instanceEndpoint.hostname,
          port: dbPort.valueAsNumber
        }
      ]
    });

    // Create VPC Lattice Service for database access
    const databaseService = new vpclattice.CfnService(this, 'DatabaseService', {
      name: `rds-database-service-${cdk.Names.uniqueId(this).toLowerCase()}`,
      authType: 'AWS_IAM'
    });

    // Create TCP Listener for the database service
    const tcpListener = new vpclattice.CfnListener(this, 'TcpListener', {
      serviceIdentifier: databaseService.attrId,
      name: 'mysql-tcp-listener',
      protocol: 'TCP',
      port: dbPort.valueAsNumber,
      defaultAction: {
        forward: {
          targetGroups: [
            {
              targetGroupIdentifier: targetGroup.attrId,
              weight: 100
            }
          ]
        }
      }
    });

    // Associate service with service network
    const serviceAssociation = new vpclattice.CfnServiceNetworkServiceAssociation(
      this,
      'ServiceNetworkServiceAssociation',
      {
        serviceNetworkIdentifier: serviceNetwork.attrId,
        serviceIdentifier: databaseService.attrId
      }
    );

    // Associate VPC with service network
    const vpcAssociation = new vpclattice.CfnServiceNetworkVpcAssociation(
      this,
      'ServiceNetworkVpcAssociation',
      {
        serviceNetworkIdentifier: serviceNetwork.attrId,
        vpcIdentifier: vpc.vpcId,
        securityGroupIds: [rdsSecurityGroup.securityGroupId]
      }
    );

    // Create CloudWatch Dashboard for VPC Lattice monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'VpcLatticeDashboard', {
      dashboardName: `VPCLattice-Database-Monitoring-${cdk.Names.uniqueId(this)}`,
      widgets: [
        [
          // Connection metrics widget
          new cloudwatch.GraphWidget({
            title: 'Database Connection Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/VpcLattice',
                metricName: 'NewConnectionCount',
                dimensionsMap: {
                  TargetGroup: targetGroup.attrId
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5)
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/VpcLattice',
                metricName: 'ActiveConnectionCount',
                dimensionsMap: {
                  TargetGroup: targetGroup.attrId
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5)
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/VpcLattice',
                metricName: 'ConnectionErrorCount',
                dimensionsMap: {
                  TargetGroup: targetGroup.attrId
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5)
              })
            ],
            width: 12,
            height: 6
          })
        ],
        [
          // Traffic volume widget
          new cloudwatch.GraphWidget({
            title: 'Database Traffic Volume',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/VpcLattice',
                metricName: 'ProcessedBytes',
                dimensionsMap: {
                  TargetGroup: targetGroup.attrId
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5)
              })
            ],
            width: 12,
            height: 6
          })
        ]
      ]
    });

    // Create CloudWatch Alarm for connection errors
    const connectionErrorAlarm = new cloudwatch.Alarm(this, 'ConnectionErrorAlarm', {
      alarmName: `VPCLattice-Database-Connection-Errors-${cdk.Names.uniqueId(this)}`,
      alarmDescription: 'Alert on database connection errors through VPC Lattice',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/VpcLattice',
        metricName: 'ConnectionErrorCount',
        dimensionsMap: {
          TargetGroup: targetGroup.attrId
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 5,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Set up resource dependencies
    targetGroup.node.addDependency(dbInstance);
    tcpListener.node.addDependency(targetGroup);
    serviceAssociation.node.addDependency(databaseService);
    serviceAssociation.node.addDependency(serviceNetwork);
    vpcAssociation.node.addDependency(serviceNetwork);

    // Outputs for verification and integration
    new cdk.CfnOutput(this, 'ServiceNetworkId', {
      value: serviceNetwork.attrId,
      description: 'VPC Lattice Service Network ID',
      exportName: `${this.stackName}-ServiceNetworkId`
    });

    new cdk.CfnOutput(this, 'ServiceNetworkArn', {
      value: serviceNetwork.attrArn,
      description: 'VPC Lattice Service Network ARN',
      exportName: `${this.stackName}-ServiceNetworkArn`
    });

    new cdk.CfnOutput(this, 'DatabaseServiceId', {
      value: databaseService.attrId,
      description: 'VPC Lattice Database Service ID',
      exportName: `${this.stackName}-DatabaseServiceId`
    });

    new cdk.CfnOutput(this, 'DatabaseServiceArn', {
      value: databaseService.attrArn,
      description: 'VPC Lattice Database Service ARN',
      exportName: `${this.stackName}-DatabaseServiceArn`
    });

    new cdk.CfnOutput(this, 'TargetGroupId', {
      value: targetGroup.attrId,
      description: 'VPC Lattice Target Group ID for RDS instance',
      exportName: `${this.stackName}-TargetGroupId`
    });

    new cdk.CfnOutput(this, 'RdsInstanceId', {
      value: dbInstance.instanceIdentifier,
      description: 'RDS MySQL Instance Identifier',
      exportName: `${this.stackName}-RdsInstanceId`
    });

    new cdk.CfnOutput(this, 'RdsEndpoint', {
      value: dbInstance.instanceEndpoint.hostname,
      description: 'RDS MySQL Instance Endpoint',
      exportName: `${this.stackName}-RdsEndpoint`
    });

    new cdk.CfnOutput(this, 'DatabasePort', {
      value: dbPort.valueAsString,
      description: 'Database port number',
      exportName: `${this.stackName}-DatabasePort`
    });

    new cdk.CfnOutput(this, 'ServiceEndpoint', {
      value: `${databaseService.name}.${serviceNetwork.attrId}.vpc-lattice-svcs.${this.region}.on.aws`,
      description: 'VPC Lattice Service Endpoint for database connectivity',
      exportName: `${this.stackName}-ServiceEndpoint`
    });

    new cdk.CfnOutput(this, 'CloudWatchDashboard', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL for VPC Lattice monitoring',
      exportName: `${this.stackName}-CloudWatchDashboard`
    });

    new cdk.CfnOutput(this, 'DatabaseSecretArn', {
      value: dbInstance.secret?.secretArn || 'No secret created',
      description: 'ARN of the RDS database credentials secret',
      exportName: `${this.stackName}-DatabaseSecretArn`
    });

    // Add tags to all resources for cost tracking and governance
    cdk.Tags.of(this).add('Project', 'VPCLatticeDemo');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('Purpose', 'TCP-Resource-Connectivity');
    cdk.Tags.of(this).add('Recipe', 'tcp-resource-connectivity-lattice-cloudwatch');
  }
}

// CDK App
const app = new cdk.App();

// Create stack with environment settings
new TcpResourceConnectivityStack(app, 'TcpResourceConnectivityStack', {
  description: 'VPC Lattice TCP Resource Connectivity with CloudWatch Monitoring (Recipe: tcp-resource-connectivity-lattice-cloudwatch)',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  },
  tags: {
    'Recipe': 'tcp-resource-connectivity-lattice-cloudwatch',
    'Category': 'networking',
    'Difficulty': '300'
  }
});

app.synth();