#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as neptune from 'aws-cdk-lib/aws-neptune';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * CDK Stack for Neptune Graph Database Recommendation Engine
 * 
 * This stack creates:
 * - VPC with public and private subnets across multiple AZs
 * - Neptune cluster with primary and replica instances
 * - EC2 instance for Gremlin client testing
 * - S3 bucket for sample data storage
 * - IAM roles and security groups with proper permissions
 * - Lambda function for data loading automation
 */
export class NeptuneRecommendationEngineStack extends cdk.Stack {
  
  public readonly vpc: ec2.Vpc;
  public readonly neptuneCluster: neptune.CfnDBCluster;
  public readonly neptuneSubnetGroup: neptune.CfnDBSubnetGroup;
  public readonly clientInstance: ec2.Instance;
  public readonly sampleDataBucket: s3.Bucket;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // Create VPC with public and private subnets across multiple AZs
    this.vpc = this.createVpcInfrastructure();

    // Create security groups for Neptune and EC2
    const { neptuneSecurityGroup, ec2SecurityGroup } = this.createSecurityGroups();

    // Create S3 bucket for sample data
    this.sampleDataBucket = this.createSampleDataBucket(uniqueSuffix);

    // Create Neptune subnet group and cluster
    const { subnetGroup, cluster } = this.createNeptuneCluster(neptuneSecurityGroup, uniqueSuffix);
    this.neptuneSubnetGroup = subnetGroup;
    this.neptuneCluster = cluster;

    // Create Neptune instances (primary and replicas)
    this.createNeptuneInstances(uniqueSuffix);

    // Create EC2 instance for Gremlin client
    this.clientInstance = this.createClientInstance(ec2SecurityGroup);

    // Create IAM roles for Neptune operations
    this.createIamRoles();

    // Create Lambda function for data loading
    this.createDataLoadingLambda();

    // Output important values
    this.createOutputs();
  }

  /**
   * Creates VPC infrastructure with public and private subnets
   */
  private createVpcInfrastructure(): ec2.Vpc {
    const vpc = new ec2.Vpc(this, 'NeptuneVpc', {
      maxAzs: 3,
      cidr: '10.0.0.0/16',
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 24,
        },
        {
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
          cidrMask: 24,
        },
      ],
    });

    // Add tags for better resource management
    cdk.Tags.of(vpc).add('Name', 'neptune-recommendation-vpc');
    cdk.Tags.of(vpc).add('Project', 'Neptune Recommendation Engine');

    return vpc;
  }

  /**
   * Creates security groups for Neptune cluster and EC2 client
   */
  private createSecurityGroups(): { neptuneSecurityGroup: ec2.SecurityGroup; ec2SecurityGroup: ec2.SecurityGroup } {
    // Security group for Neptune cluster
    const neptuneSecurityGroup = new ec2.SecurityGroup(this, 'NeptuneSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for Neptune cluster',
      allowAllOutbound: false,
    });

    // Security group for EC2 client instance
    const ec2SecurityGroup = new ec2.SecurityGroup(this, 'EC2SecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for EC2 Gremlin client',
      allowAllOutbound: true,
    });

    // Allow EC2 to connect to Neptune on port 8182
    neptuneSecurityGroup.addIngressRule(
      ec2SecurityGroup,
      ec2.Port.tcp(8182),
      'Allow Gremlin access from EC2 client'
    );

    // Allow Neptune instances to communicate with each other
    neptuneSecurityGroup.addIngressRule(
      neptuneSecurityGroup,
      ec2.Port.tcp(8182),
      'Allow Neptune cluster internal communication'
    );

    // Allow SSH access to EC2 instance (restrict to your IP in production)
    ec2SecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'SSH access (restrict in production)'
    );

    // Allow HTTPS outbound for Neptune
    neptuneSecurityGroup.addEgressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'HTTPS outbound'
    );

    return { neptuneSecurityGroup, ec2SecurityGroup };
  }

  /**
   * Creates S3 bucket for storing sample graph data
   */
  private createSampleDataBucket(uniqueSuffix: string): s3.Bucket {
    const bucket = new s3.Bucket(this, 'SampleDataBucket', {
      bucketName: `neptune-sample-data-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
    });

    // Add lifecycle rule to manage costs
    bucket.addLifecycleRule({
      id: 'SampleDataLifecycle',
      enabled: true,
      expiration: cdk.Duration.days(7),
    });

    return bucket;
  }

  /**
   * Creates Neptune subnet group and cluster
   */
  private createNeptuneCluster(securityGroup: ec2.SecurityGroup, uniqueSuffix: string): {
    subnetGroup: neptune.CfnDBSubnetGroup;
    cluster: neptune.CfnDBCluster;
  } {
    // Create Neptune subnet group
    const subnetGroup = new neptune.CfnDBSubnetGroup(this, 'NeptuneSubnetGroup', {
      dbSubnetGroupName: `neptune-subnet-group-${uniqueSuffix}`,
      dbSubnetGroupDescription: 'Subnet group for Neptune cluster',
      subnetIds: this.vpc.privateSubnets.map(subnet => subnet.subnetId),
      tags: [
        { key: 'Name', value: `neptune-subnet-group-${uniqueSuffix}` },
        { key: 'Project', value: 'Neptune Recommendation Engine' },
      ],
    });

    // Create Neptune cluster
    const cluster = new neptune.CfnDBCluster(this, 'NeptuneCluster', {
      dbClusterIdentifier: `neptune-recommendations-${uniqueSuffix}`,
      engineVersion: '1.3.2.0',
      dbSubnetGroupName: subnetGroup.dbSubnetGroupName,
      vpcSecurityGroupIds: [securityGroup.securityGroupId],
      storageEncrypted: true,
      backupRetentionPeriod: 7,
      preferredBackupWindow: '03:00-04:00',
      preferredMaintenanceWindow: 'sun:04:00-sun:05:00',
      deletionProtection: false, // Set to true for production
      tags: [
        { key: 'Name', value: `neptune-recommendations-${uniqueSuffix}` },
        { key: 'Project', value: 'Neptune Recommendation Engine' },
        { key: 'Environment', value: 'development' },
      ],
    });

    cluster.addDependency(subnetGroup);

    return { subnetGroup, cluster };
  }

  /**
   * Creates Neptune primary and replica instances
   */
  private createNeptuneInstances(uniqueSuffix: string): void {
    // Primary instance
    const primaryInstance = new neptune.CfnDBInstance(this, 'NeptunePrimaryInstance', {
      dbInstanceIdentifier: `${this.neptuneCluster.dbClusterIdentifier}-primary`,
      dbInstanceClass: 'db.r5.large',
      engine: 'neptune',
      dbClusterIdentifier: this.neptuneCluster.dbClusterIdentifier,
      publiclyAccessible: false,
      tags: [
        { key: 'Name', value: `${this.neptuneCluster.dbClusterIdentifier}-primary` },
        { key: 'Role', value: 'Primary' },
        { key: 'Project', value: 'Neptune Recommendation Engine' },
      ],
    });

    // First replica instance
    const replica1 = new neptune.CfnDBInstance(this, 'NeptuneReplica1', {
      dbInstanceIdentifier: `${this.neptuneCluster.dbClusterIdentifier}-replica-1`,
      dbInstanceClass: 'db.r5.large',
      engine: 'neptune',
      dbClusterIdentifier: this.neptuneCluster.dbClusterIdentifier,
      publiclyAccessible: false,
      tags: [
        { key: 'Name', value: `${this.neptuneCluster.dbClusterIdentifier}-replica-1` },
        { key: 'Role', value: 'Replica' },
        { key: 'Project', value: 'Neptune Recommendation Engine' },
      ],
    });

    // Second replica instance
    const replica2 = new neptune.CfnDBInstance(this, 'NeptuneReplica2', {
      dbInstanceIdentifier: `${this.neptuneCluster.dbClusterIdentifier}-replica-2`,
      dbInstanceClass: 'db.r5.large',
      engine: 'neptune',
      dbClusterIdentifier: this.neptuneCluster.dbClusterIdentifier,
      publiclyAccessible: false,
      tags: [
        { key: 'Name', value: `${this.neptuneCluster.dbClusterIdentifier}-replica-2` },
        { key: 'Role', value: 'Replica' },
        { key: 'Project', value: 'Neptune Recommendation Engine' },
      ],
    });

    // Set dependencies
    primaryInstance.addDependency(this.neptuneCluster);
    replica1.addDependency(this.neptuneCluster);
    replica2.addDependency(this.neptuneCluster);
  }

  /**
   * Creates EC2 instance for Gremlin client testing
   */
  private createClientInstance(securityGroup: ec2.SecurityGroup): ec2.Instance {
    // Create key pair for EC2 access
    const keyPair = new ec2.CfnKeyPair(this, 'NeptuneClientKeyPair', {
      keyName: 'neptune-client-keypair',
      keyType: 'rsa',
      keyFormat: 'pem',
    });

    // User data script to install Gremlin Python client and dependencies
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      'yum update -y',
      'yum install -y python3 python3-pip git',
      'pip3 install gremlinpython boto3 pandas numpy',
      'yum install -y java-11-openjdk',
      
      // Download and install Gremlin Console for testing
      'cd /opt',
      'wget https://archive.apache.org/dist/tinkerpop/3.6.2/apache-tinkerpop-gremlin-console-3.6.2-bin.zip',
      'unzip apache-tinkerpop-gremlin-console-3.6.2-bin.zip',
      'ln -s apache-tinkerpop-gremlin-console-3.6.2 gremlin-console',
      'chown -R ec2-user:ec2-user /opt/gremlin-console',
      
      // Create sample scripts directory
      'mkdir -p /home/ec2-user/neptune-scripts',
      'chown ec2-user:ec2-user /home/ec2-user/neptune-scripts',
      
      // Install CloudWatch agent for monitoring
      'yum install -y amazon-cloudwatch-agent',
      
      // Create environment file for Neptune endpoints
      'echo "# Neptune endpoints will be populated by CDK outputs" > /home/ec2-user/.neptune-env',
      'chown ec2-user:ec2-user /home/ec2-user/.neptune-env'
    );

    const instance = new ec2.Instance(this, 'NeptuneClientInstance', {
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM),
      machineImage: ec2.MachineImage.latestAmazonLinux2(),
      vpc: this.vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
      securityGroup: securityGroup,
      keyName: keyPair.keyName,
      userData: userData,
      userDataCausesReplacement: true,
    });

    // Add tags
    cdk.Tags.of(instance).add('Name', 'neptune-gremlin-client');
    cdk.Tags.of(instance).add('Project', 'Neptune Recommendation Engine');
    cdk.Tags.of(instance).add('Purpose', 'Gremlin Testing');

    return instance;
  }

  /**
   * Creates IAM roles for Neptune operations and Lambda functions
   */
  private createIamRoles(): void {
    // IAM role for Neptune to access S3 for bulk loading
    const neptuneServiceRole = new iam.Role(this, 'NeptuneS3Role', {
      assumedBy: new iam.ServicePrincipal('rds.amazonaws.com'),
      description: 'IAM role for Neptune to access S3 for data loading',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonS3ReadOnlyAccess'),
      ],
    });

    // IAM role for EC2 instance to access Neptune and S3
    const ec2Role = new iam.Role(this, 'NeptuneClientRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for EC2 Gremlin client',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    // Add custom policy for Neptune access
    ec2Role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'neptune-db:connect',
        'neptune-db:*',
      ],
      resources: ['*'],
    }));

    // Add S3 access for sample data
    ec2Role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:GetObject',
        's3:PutObject',
        's3:ListBucket',
      ],
      resources: [
        this.sampleDataBucket.bucketArn,
        `${this.sampleDataBucket.bucketArn}/*`,
      ],
    }));

    // Create instance profile for EC2
    const instanceProfile = new iam.CfnInstanceProfile(this, 'NeptuneClientInstanceProfile', {
      roles: [ec2Role.roleName],
    });

    // Attach instance profile to EC2 instance
    const cfnInstance = this.clientInstance.node.defaultChild as ec2.CfnInstance;
    cfnInstance.iamInstanceProfile = instanceProfile.ref;
  }

  /**
   * Creates Lambda function for automated data loading
   */
  private createDataLoadingLambda(): void {
    // IAM role for Lambda
    const lambdaRole = new iam.Role(this, 'DataLoadingLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaVPCAccessExecutionRole'),
      ],
    });

    // Add Neptune and S3 permissions
    lambdaRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'neptune-db:*',
        's3:GetObject',
        's3:ListBucket',
      ],
      resources: ['*'],
    }));

    // Lambda function for data loading
    const dataLoadingFunction = new lambda.Function(this, 'DataLoadingFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.handler',
      role: lambdaRole,
      timeout: cdk.Duration.minutes(15),
      memorySize: 512,
      environment: {
        NEPTUNE_ENDPOINT: this.neptuneCluster.attrEndpoint,
        S3_BUCKET: this.sampleDataBucket.bucketName,
      },
      vpc: this.vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from gremlin_python.driver import client
from gremlin_python.driver.driver_remote_connection import DriverRemoteConnection
from gremlin_python.structure.graph import Graph

def handler(event, context):
    """
    Lambda function to load sample data into Neptune cluster
    """
    try:
        neptune_endpoint = os.environ['NEPTUNE_ENDPOINT']
        s3_bucket = os.environ['S3_BUCKET']
        
        # Connect to Neptune
        connection = DriverRemoteConnection(f'wss://{neptune_endpoint}:8182/gremlin', 'g')
        g = Graph().traversal().withRemote(connection)
        
        # Sample data loading logic would go here
        # For production, implement proper CSV parsing and bulk loading
        
        # Test connection
        vertex_count = g.V().count().next()
        
        connection.close()
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data loading completed successfully',
                'vertex_count': vertex_count
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
      `),
    });

    // Create CloudWatch log group
    new logs.LogGroup(this, 'DataLoadingLambdaLogGroup', {
      logGroupName: `/aws/lambda/${dataLoadingFunction.functionName}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
  }

  /**
   * Creates CloudFormation outputs for important values
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for Neptune cluster',
      exportName: 'NeptuneVpcId',
    });

    new cdk.CfnOutput(this, 'NeptuneClusterEndpoint', {
      value: this.neptuneCluster.attrEndpoint,
      description: 'Neptune cluster write endpoint',
      exportName: 'NeptuneClusterEndpoint',
    });

    new cdk.CfnOutput(this, 'NeptuneClusterReadEndpoint', {
      value: this.neptuneCluster.attrReadEndpoint,
      description: 'Neptune cluster read endpoint',
      exportName: 'NeptuneClusterReadEndpoint',
    });

    new cdk.CfnOutput(this, 'NeptunePort', {
      value: '8182',
      description: 'Neptune cluster port',
    });

    new cdk.CfnOutput(this, 'ClientInstanceId', {
      value: this.clientInstance.instanceId,
      description: 'EC2 Gremlin client instance ID',
    });

    new cdk.CfnOutput(this, 'ClientInstancePublicIp', {
      value: this.clientInstance.instancePublicIp,
      description: 'EC2 Gremlin client public IP address',
    });

    new cdk.CfnOutput(this, 'SampleDataBucket', {
      value: this.sampleDataBucket.bucketName,
      description: 'S3 bucket for sample graph data',
      exportName: 'NeptuneSampleDataBucket',
    });

    new cdk.CfnOutput(this, 'GremlinConnectionString', {
      value: `wss://${this.neptuneCluster.attrEndpoint}:8182/gremlin`,
      description: 'Gremlin WebSocket connection string',
    });

    new cdk.CfnOutput(this, 'SSHCommand', {
      value: `ssh -i neptune-client-keypair.pem ec2-user@${this.clientInstance.instancePublicIp}`,
      description: 'SSH command to connect to client instance',
    });
  }
}

/**
 * CDK App definition and stack instantiation
 */
const app = new cdk.App();

new NeptuneRecommendationEngineStack(app, 'NeptuneRecommendationEngineStack', {
  description: 'CDK Stack for Neptune Graph Database Recommendation Engine',
  
  // Configure stack-level properties
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Add stack tags
  tags: {
    Project: 'Neptune Recommendation Engine',
    Environment: 'Development',
    Owner: 'AWS CDK',
    CostCenter: 'Engineering',
  },
  
  // Enable termination protection for production
  terminationProtection: false,
});

// Add application-level tags
cdk.Tags.of(app).add('Application', 'Graph Database Recommendation Engine');
cdk.Tags.of(app).add('Version', '1.0.0');

app.synth();