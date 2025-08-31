#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as vpclattice from 'aws-cdk-lib/aws-vpclattice';
import * as ram from 'aws-cdk-lib/aws-ram';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { AwsSolutionsChecks, NagSuppressions } from 'cdk-nag';

/**
 * Props for the CrossAccountDatabaseSharingStack
 */
interface CrossAccountDatabaseSharingStackProps extends cdk.StackProps {
  /**
   * The AWS account ID that will consume the shared database
   */
  readonly consumerAccountId: string;
  
  /**
   * The external ID for cross-account role assumption (for enhanced security)
   */
  readonly externalId?: string;
  
  /**
   * Whether to enable deletion protection on RDS instance
   * @default true
   */
  readonly deletionProtection?: boolean;
}

/**
 * CDK Stack for Cross-Account Database Sharing with VPC Lattice and RDS
 * 
 * This stack demonstrates how to securely share RDS databases across AWS accounts
 * using VPC Lattice resource configurations, eliminating the need for complex
 * VPC peering setups while maintaining enterprise-grade security.
 * 
 * Architecture:
 * - RDS MySQL database with encryption at rest
 * - VPC Lattice Service Network for governance
 * - Resource Gateway for secure connectivity 
 * - Resource Configuration representing the database endpoint
 * - Cross-account IAM roles with least privilege access
 * - AWS RAM share for cross-account resource sharing
 * - CloudWatch monitoring and logging
 */
export class CrossAccountDatabaseSharingStack extends cdk.Stack {
  
  public readonly vpc: ec2.Vpc;
  public readonly database: rds.DatabaseInstance;
  public readonly serviceNetwork: vpclattice.CfnServiceNetwork;
  public readonly resourceGateway: vpclattice.CfnResourceGateway;
  public readonly resourceConfiguration: vpclattice.CfnResourceConfiguration;
  public readonly crossAccountRole: iam.Role;
  public readonly resourceShare: ram.CfnResourceShare;

  constructor(scope: Construct, id: string, props: CrossAccountDatabaseSharingStackProps) {
    super(scope, id, props);

    // Create VPC with proper subnets for RDS and VPC Lattice
    this.vpc = this.createVpc();
    
    // Create RDS database with security best practices
    this.database = this.createRdsDatabase();
    
    // Create VPC Lattice Service Network for centralized governance
    this.serviceNetwork = this.createServiceNetwork();
    
    // Create Resource Gateway for VPC Lattice connectivity
    this.resourceGateway = this.createResourceGateway();
    
    // Create Resource Configuration representing the database
    this.resourceConfiguration = this.createResourceConfiguration();
    
    // Associate Resource Configuration with Service Network
    this.associateResourceConfigurationWithServiceNetwork();
    
    // Create cross-account IAM role for database access
    this.crossAccountRole = this.createCrossAccountRole(props.consumerAccountId, props.externalId);
    
    // Configure Service Network authentication policy
    this.configureServiceNetworkAuthPolicy();
    
    // Create AWS RAM resource share for cross-account sharing
    this.resourceShare = this.createResourceShare(props.consumerAccountId);
    
    // Set up CloudWatch monitoring
    this.setupCloudWatchMonitoring();
    
    // Apply CDK Nag suppressions for false positives
    this.applyCdkNagSuppressions();
    
    // Output important resource identifiers
    this.createOutputs();
  }

  /**
   * Creates a VPC with subnets optimized for RDS and VPC Lattice
   */
  private createVpc(): ec2.Vpc {
    const vpc = new ec2.Vpc(this, 'DatabaseOwnerVpc', {
      ipAddresses: ec2.IpAddresses.cidr('10.0.0.0/16'),
      maxAzs: 2,
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'DatabaseSubnet',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
        {
          cidrMask: 28, // /28 required for VPC Lattice Resource Gateway
          name: 'ResourceGatewaySubnet',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // Add tags for resource identification
    cdk.Tags.of(vpc).add('Name', 'DatabaseOwnerVpc');
    cdk.Tags.of(vpc).add('Purpose', 'CrossAccountDatabaseSharing');

    return vpc;
  }

  /**
   * Creates an RDS MySQL database with security best practices
   */
  private createRdsDatabase(): rds.DatabaseInstance {
    // Create security group for RDS with minimal required access
    const dbSecurityGroup = new ec2.SecurityGroup(this, 'DatabaseSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for shared RDS database',
      allowAllOutbound: false,
    });

    // Allow inbound MySQL traffic from VPC CIDR only
    dbSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(this.vpc.vpcCidrBlock),
      ec2.Port.tcp(3306),
      'Allow MySQL access from VPC'
    );

    // Create DB subnet group using isolated subnets
    const dbSubnetGroup = new rds.SubnetGroup(this, 'DatabaseSubnetGroup', {
      vpc: this.vpc,
      description: 'Subnet group for shared database',
      vpcSubnets: {
        subnetGroupName: 'DatabaseSubnet',
      },
    });

    // Generate secure random password for database
    const databaseCredentials = rds.Credentials.fromGeneratedSecret('admin', {
      excludeCharacters: '"@/\\\'',
      secretName: `${this.stackName}/database-credentials`,
    });

    // Create RDS instance with encryption and best practices
    const database = new rds.DatabaseInstance(this, 'SharedDatabase', {
      engine: rds.DatabaseInstanceEngine.mysql({
        version: rds.MysqlEngineVersion.VER_8_0,
      }),
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      vpc: this.vpc,
      subnetGroup: dbSubnetGroup,
      securityGroups: [dbSecurityGroup],
      credentials: databaseCredentials,
      multiAz: false, // Set to true for production workloads
      storageEncrypted: true,
      storageEncryptionKey: undefined, // Uses default AWS managed key
      deletionProtection: this.node.tryGetContext('deletionProtection') !== false,
      backupRetention: cdk.Duration.days(7),
      deleteAutomatedBackups: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      allocatedStorage: 20,
      maxAllocatedStorage: 100,
      enablePerformanceInsights: true,
      performanceInsightRetention: rds.PerformanceInsightRetention.DEFAULT,
    });

    // Add tags for identification
    cdk.Tags.of(database).add('Name', 'SharedDatabase');
    cdk.Tags.of(database).add('Purpose', 'CrossAccountSharing');

    return database;
  }

  /**
   * Creates VPC Lattice Service Network with IAM authentication
   */
  private createServiceNetwork(): vpclattice.CfnServiceNetwork {
    const serviceNetwork = new vpclattice.CfnServiceNetwork(this, 'DatabaseSharingServiceNetwork', {
      name: `database-sharing-network-${this.stackName}`,
      authType: 'AWS_IAM',
    });

    // Associate VPC with Service Network
    new vpclattice.CfnServiceNetworkVpcAssociation(this, 'ServiceNetworkVpcAssociation', {
      serviceNetworkIdentifier: serviceNetwork.attrId,
      vpcIdentifier: this.vpc.vpcId,
    });

    // Add tags
    cdk.Tags.of(serviceNetwork).add('Name', 'DatabaseSharingServiceNetwork');
    cdk.Tags.of(serviceNetwork).add('Purpose', 'CrossAccountDatabaseSharing');

    return serviceNetwork;
  }

  /**
   * Creates VPC Lattice Resource Gateway for database connectivity
   */
  private createResourceGateway(): vpclattice.CfnResourceGateway {
    // Create security group for Resource Gateway
    const gatewaySecurityGroup = new ec2.SecurityGroup(this, 'ResourceGatewaySecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for VPC Lattice resource gateway',
      allowAllOutbound: true,
    });

    // Allow all traffic within VPC for resource gateway functionality
    gatewaySecurityGroup.addIngressRule(
      ec2.Peer.ipv4(this.vpc.vpcCidrBlock),
      ec2.Port.allTraffic(),
      'Allow all VPC traffic for resource gateway'
    );

    // Get the resource gateway subnet (first subnet with /28 CIDR)
    const resourceGatewaySubnet = this.vpc.selectSubnets({
      subnetGroupName: 'ResourceGatewaySubnet',
    }).subnetIds[0];

    const resourceGateway = new vpclattice.CfnResourceGateway(this, 'DatabaseResourceGateway', {
      name: `rds-gateway-${this.stackName}`,
      vpcIdentifier: this.vpc.vpcId,
      subnetIds: [resourceGatewaySubnet],
      securityGroupIds: [gatewaySecurityGroup.securityGroupId],
    });

    // Add tags
    cdk.Tags.of(resourceGateway).add('Name', 'DatabaseResourceGateway');
    cdk.Tags.of(resourceGateway).add('Purpose', 'CrossAccountDatabaseSharing');

    return resourceGateway;
  }

  /**
   * Creates VPC Lattice Resource Configuration for the RDS database
   */
  private createResourceConfiguration(): vpclattice.CfnResourceConfiguration {
    const resourceConfiguration = new vpclattice.CfnResourceConfiguration(this, 'RdsResourceConfiguration', {
      name: `rds-resource-config-${this.stackName}`,
      type: 'SINGLE',
      resourceGatewayIdentifier: this.resourceGateway.attrId,
      resourceConfigurationDefinition: {
        ipResource: {
          ipAddress: this.database.instanceEndpoint.hostname,
        },
      },
      protocol: 'TCP',
      portRanges: ['3306'],
      allowAssociationToShareableServiceNetwork: true,
    });

    // Ensure proper dependency order
    resourceConfiguration.addDependency(this.resourceGateway);
    resourceConfiguration.addDependency(this.database.node.defaultChild as cdk.CfnResource);

    // Add tags
    cdk.Tags.of(resourceConfiguration).add('Name', 'RdsResourceConfiguration');
    cdk.Tags.of(resourceConfiguration).add('Purpose', 'CrossAccountDatabaseSharing');

    return resourceConfiguration;
  }

  /**
   * Associates Resource Configuration with Service Network
   */
  private associateResourceConfigurationWithServiceNetwork(): void {
    const association = new vpclattice.CfnResourceConfigurationAssociation(this, 'ResourceConfigurationAssociation', {
      resourceConfigurationIdentifier: this.resourceConfiguration.attrId,
      serviceNetworkIdentifier: this.serviceNetwork.attrId,
    });

    // Ensure proper dependency order
    association.addDependency(this.resourceConfiguration);
    association.addDependency(this.serviceNetwork);
  }

  /**
   * Creates cross-account IAM role for database access
   */
  private createCrossAccountRole(consumerAccountId: string, externalId?: string): iam.Role {
    // Create trust policy for cross-account access
    const trustPolicyDocument = new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          principals: [new iam.AccountPrincipal(consumerAccountId)],
          actions: ['sts:AssumeRole'],
          conditions: externalId ? {
            StringEquals: {
              'sts:ExternalId': externalId,
            },
          } : undefined,
        }),
      ],
    });

    // Create the cross-account role
    const crossAccountRole = new iam.Role(this, 'DatabaseAccessRole', {
      roleName: `DatabaseAccessRole-${this.stackName}`,
      assumedBy: new iam.AccountPrincipal(consumerAccountId),
      externalIds: externalId ? [externalId] : undefined,
      description: 'Cross-account role for VPC Lattice database access',
      maxSessionDuration: cdk.Duration.hours(1),
    });

    // Add policy for VPC Lattice access
    crossAccountRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['vpc-lattice:Invoke'],
        resources: ['*'],
      })
    );

    // Add tags
    cdk.Tags.of(crossAccountRole).add('Name', 'DatabaseAccessRole');
    cdk.Tags.of(crossAccountRole).add('Purpose', 'CrossAccountDatabaseSharing');

    return crossAccountRole;
  }

  /**
   * Configures Service Network authentication policy
   */
  private configureServiceNetworkAuthPolicy(): void {
    const authPolicy = new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          principals: [this.crossAccountRole],
          actions: ['vpc-lattice:Invoke'],
          resources: ['*'],
        }),
      ],
    });

    new vpclattice.CfnAuthPolicy(this, 'ServiceNetworkAuthPolicy', {
      resourceIdentifier: this.serviceNetwork.attrId,
      policy: authPolicy.toJSON(),
    });
  }

  /**
   * Creates AWS RAM resource share for cross-account sharing
   */
  private createResourceShare(consumerAccountId: string): ram.CfnResourceShare {
    const resourceShare = new ram.CfnResourceShare(this, 'DatabaseResourceShare', {
      name: `DatabaseResourceShare-${this.stackName}`,
      resourceArns: [
        `arn:aws:vpc-lattice:${this.region}:${this.account}:resourceconfiguration/${this.resourceConfiguration.attrId}`,
      ],
      principals: [consumerAccountId],
      allowExternalPrincipals: true,
    });

    // Ensure proper dependency
    resourceShare.addDependency(this.resourceConfiguration);

    // Add tags
    cdk.Tags.of(resourceShare).add('Name', 'DatabaseResourceShare');
    cdk.Tags.of(resourceShare).add('Purpose', 'CrossAccountDatabaseSharing');

    return resourceShare;
  }

  /**
   * Sets up CloudWatch monitoring and logging
   */
  private setupCloudWatchMonitoring(): void {
    // Create log group for VPC Lattice
    const logGroup = new logs.LogGroup(this, 'VpcLatticeLogGroup', {
      logGroupName: `/aws/vpc-lattice/servicenetwork/${this.serviceNetwork.attrId}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create CloudWatch dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'DatabaseSharingDashboard', {
      dashboardName: `DatabaseSharingMonitoring-${this.stackName}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Database Access Metrics',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/VpcLattice',
                metricName: 'RequestCount',
                dimensionsMap: {
                  ServiceNetwork: this.serviceNetwork.attrId,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/VpcLattice',
                metricName: 'ResponseTime',
                dimensionsMap: {
                  ServiceNetwork: this.serviceNetwork.attrId,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
          }),
        ],
      ],
    });

    // Add tags
    cdk.Tags.of(logGroup).add('Purpose', 'CrossAccountDatabaseSharing');
    cdk.Tags.of(dashboard).add('Purpose', 'CrossAccountDatabaseSharing');
  }

  /**
   * Applies CDK Nag suppressions for known false positives
   */
  private applyCdkNagSuppressions(): void {
    // Suppress warning about RDS instance not being in multiple AZs (acceptable for demo)
    NagSuppressions.addResourceSuppressions(
      this.database,
      [
        {
          id: 'AwsSolutions-RDS2',
          reason: 'Multi-AZ deployment not required for demo purposes, but should be enabled for production workloads',
        },
        {
          id: 'AwsSolutions-RDS3',
          reason: 'Backup retention period is set to 7 days which is appropriate for demo purposes',
        },
      ]
    );

    // Suppress warning about security group allowing all protocols (required for resource gateway)
    NagSuppressions.addResourceSuppressions(
      this.node.findChild('ResourceGatewaySecurityGroup'),
      [
        {
          id: 'AwsSolutions-EC23',
          reason: 'Resource gateway requires all protocol access within VPC for proper functionality',
        },
      ]
    );

    // Suppress IAM policy wildcard resource (required for VPC Lattice invoke action)
    NagSuppressions.addResourceSuppressions(
      this.crossAccountRole,
      [
        {
          id: 'AwsSolutions-IAM5',
          reason: 'VPC Lattice invoke action requires wildcard resource access pattern',
        },
      ]
    );
  }

  /**
   * Creates CloudFormation outputs for important resource identifiers
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID where database and resource gateway are deployed',
      exportName: `${this.stackName}-VpcId`,
    });

    new cdk.CfnOutput(this, 'DatabaseEndpoint', {
      value: this.database.instanceEndpoint.hostname,
      description: 'RDS database endpoint hostname',
      exportName: `${this.stackName}-DatabaseEndpoint`,
    });

    new cdk.CfnOutput(this, 'DatabaseSecretArn', {
      value: this.database.secret?.secretArn || 'N/A',
      description: 'ARN of the database credentials secret',
      exportName: `${this.stackName}-DatabaseSecretArn`,
    });

    new cdk.CfnOutput(this, 'ServiceNetworkId', {
      value: this.serviceNetwork.attrId,
      description: 'VPC Lattice Service Network ID',
      exportName: `${this.stackName}-ServiceNetworkId`,
    });

    new cdk.CfnOutput(this, 'ResourceGatewayId', {
      value: this.resourceGateway.attrId,
      description: 'VPC Lattice Resource Gateway ID',
      exportName: `${this.stackName}-ResourceGatewayId`,
    });

    new cdk.CfnOutput(this, 'ResourceConfigurationId', {
      value: this.resourceConfiguration.attrId,
      description: 'VPC Lattice Resource Configuration ID',
      exportName: `${this.stackName}-ResourceConfigurationId`,
    });

    new cdk.CfnOutput(this, 'CrossAccountRoleArn', {
      value: this.crossAccountRole.roleArn,
      description: 'ARN of the cross-account role for database access',
      exportName: `${this.stackName}-CrossAccountRoleArn`,
    });

    new cdk.CfnOutput(this, 'ResourceShareArn', {
      value: this.resourceShare.attrArn,
      description: 'ARN of the AWS RAM resource share',
      exportName: `${this.stackName}-ResourceShareArn`,
    });
  }
}

/**
 * CDK App for Cross-Account Database Sharing
 */
const app = new cdk.App();

// Get configuration from CDK context
const consumerAccountId = app.node.tryGetContext('consumerAccountId') || '123456789012';
const externalId = app.node.tryGetContext('externalId') || 'unique-external-id-12345';
const environment = app.node.tryGetContext('environment') || 'development';

// Create the main stack
const stack = new CrossAccountDatabaseSharingStack(app, 'CrossAccountDatabaseSharingStack', {
  consumerAccountId,
  externalId,
  description: 'Cross-Account Database Sharing with VPC Lattice and RDS - demonstrates secure database sharing across AWS accounts using VPC Lattice resource configurations',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'CrossAccountDatabaseSharing',
    Environment: environment,
    ManagedBy: 'CDK',
  },
});

// Apply CDK Nag to ensure security best practices
// Conditionally apply CDK Nag based on environment variable or context
if (app.node.tryGetContext('enableCdkNag') !== false && process.env.ENABLE_CDK_NAG !== 'false') {
  cdk.Aspects.of(stack).add(new AwsSolutionsChecks({ verbose: true }));
}

// Synthesize the app
app.synth();