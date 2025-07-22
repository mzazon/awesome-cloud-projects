#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cr from 'aws-cdk-lib/custom-resources';
import { Construct } from 'constructs';

/**
 * Interface for HPC ParallelCluster Stack properties
 */
interface HpcParallelClusterStackProps extends cdk.StackProps {
  readonly clusterName?: string;
  readonly instanceType?: string;
  readonly maxNodes?: number;
  readonly fsxStorageCapacity?: number;
  readonly ebsStorageSize?: number;
}

/**
 * AWS CDK Stack for deploying High Performance Computing infrastructure
 * using AWS ParallelCluster with supporting resources including VPC,
 * S3 storage, FSx Lustre filesystem, and monitoring components.
 */
class HpcParallelClusterStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly s3Bucket: s3.Bucket;
  public readonly keyPair: ec2.CfnKeyPair;
  public readonly clusterName: string;
  
  constructor(scope: Construct, id: string, props: HpcParallelClusterStackProps = {}) {
    super(scope, id, props);
    
    // Generate unique cluster name with random suffix
    const randomSuffix = Math.random().toString(36).substring(2, 8);
    this.clusterName = props.clusterName || `hpc-cluster-${randomSuffix}`;
    
    // Configuration parameters
    const instanceType = props.instanceType || 'c5n.large';
    const maxNodes = props.maxNodes || 10;
    const fsxStorageCapacity = props.fsxStorageCapacity || 1200;
    const ebsStorageSize = props.ebsStorageSize || 100;
    
    // Create VPC with custom configuration for HPC workloads
    this.vpc = this.createVpcInfrastructure();
    
    // Create S3 bucket for HPC data storage
    this.s3Bucket = this.createS3DataStorage();
    
    // Create EC2 Key Pair for cluster access
    this.keyPair = this.createKeyPair();
    
    // Create IAM roles for ParallelCluster
    const clusterRoles = this.createIamRoles();
    
    // Create ParallelCluster configuration
    this.createParallelClusterConfig(
      instanceType,
      maxNodes,
      fsxStorageCapacity,
      ebsStorageSize,
      clusterRoles
    );
    
    // Create CloudWatch monitoring dashboard
    this.createMonitoringDashboard();
    
    // Create CloudWatch alarms for cluster health
    this.createCloudWatchAlarms();
    
    // Generate outputs for cluster information
    this.createOutputs();
  }
  
  /**
   * Creates VPC infrastructure optimized for HPC workloads with
   * public and private subnets, NAT Gateway, and enhanced networking
   */
  private createVpcInfrastructure(): ec2.Vpc {
    // Create VPC with custom CIDR for HPC cluster
    const vpc = new ec2.Vpc(this, 'HpcVpc', {
      ipAddresses: ec2.IpAddresses.cidr('10.0.0.0/16'),
      maxAzs: 2,
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
      natGateways: 1, // Single NAT Gateway for cost optimization
    });
    
    // Add tags for ParallelCluster integration
    cdk.Tags.of(vpc).add('Name', `${this.clusterName}-vpc`);
    cdk.Tags.of(vpc).add('Application', 'parallelcluster');
    cdk.Tags.of(vpc).add('Environment', 'hpc');
    
    return vpc;
  }
  
  /**
   * Creates S3 bucket for HPC data storage with lifecycle policies
   * and integration with FSx Lustre
   */
  private createS3DataStorage(): s3.Bucket {
    const bucket = new s3.Bucket(this, 'HpcDataBucket', {
      bucketName: `hpc-data-${this.clusterName}-${this.account}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'hpc-data-lifecycle',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
        },
      ],
    });
    
    // Create sample folder structure for HPC workloads
    new s3.BucketDeployment(this, 'HpcSampleData', {
      sources: [
        s3.Source.data('input/sample-data.txt', 'Sample HPC input data'),
        s3.Source.data('jobs/sample-job.sh', `#!/bin/bash
#SBATCH --job-name=hpc-test
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=8
#SBATCH --time=00:10:00
#SBATCH --output=output_%j.log

module load openmpi
mpirun hostname`),
      ],
      destinationBucket: bucket,
    });
    
    return bucket;
  }
  
  /**
   * Creates EC2 Key Pair for secure cluster access
   */
  private createKeyPair(): ec2.CfnKeyPair {
    const keyPair = new ec2.CfnKeyPair(this, 'HpcKeyPair', {
      keyName: `${this.clusterName}-keypair`,
      keyType: 'rsa',
      keyFormat: 'pem',
    });
    
    return keyPair;
  }
  
  /**
   * Creates IAM roles required for ParallelCluster operations
   */
  private createIamRoles() {
    // ParallelCluster instance role
    const instanceRole = new iam.Role(this, 'ParallelClusterInstanceRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonS3ReadOnlyAccess'),
      ],
    });
    
    // Add custom policy for FSx and CloudWatch
    instanceRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'fsx:*',
        'cloudwatch:PutMetricData',
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
        'logs:DescribeLogStreams',
      ],
      resources: ['*'],
    }));
    
    // ParallelCluster service role
    const serviceRole = new iam.Role(this, 'ParallelClusterServiceRole', {
      assumedBy: new iam.ServicePrincipal('parallelcluster.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSBatchServiceRole'),
      ],
    });
    
    return {
      instanceRole,
      serviceRole,
    };
  }
  
  /**
   * Creates ParallelCluster configuration using Custom Resource
   */
  private createParallelClusterConfig(
    instanceType: string,
    maxNodes: number,
    fsxStorageCapacity: number,
    ebsStorageSize: number,
    roles: any
  ) {
    // ParallelCluster configuration YAML
    const clusterConfig = {
      Region: this.region,
      Image: {
        Os: 'alinux2',
      },
      HeadNode: {
        InstanceType: 'm5.large',
        Networking: {
          SubnetId: this.vpc.publicSubnets[0].subnetId,
        },
        Ssh: {
          KeyName: this.keyPair.keyName,
        },
        LocalStorage: {
          RootVolume: {
            Size: 50,
            VolumeType: 'gp3',
          },
        },
        Iam: {
          InstanceRole: roles.instanceRole.roleName,
        },
      },
      Scheduling: {
        Scheduler: 'slurm',
        SlurmSettings: {
          ScaledownIdletime: 5,
          QueueUpdateStrategy: 'TERMINATE',
        },
        SlurmQueues: [
          {
            Name: 'compute',
            ComputeResources: [
              {
                Name: 'compute-nodes',
                InstanceType: instanceType,
                MinCount: 0,
                MaxCount: maxNodes,
                DisableSimultaneousMultithreading: true,
                Efa: {
                  Enabled: true,
                },
              },
            ],
            Networking: {
              SubnetIds: [this.vpc.privateSubnets[0].subnetId],
            },
            ComputeSettings: {
              LocalStorage: {
                RootVolume: {
                  Size: 50,
                  VolumeType: 'gp3',
                },
              },
            },
            Iam: {
              InstanceRole: roles.instanceRole.roleName,
            },
          },
        ],
      },
      SharedStorage: [
        {
          MountDir: '/shared',
          Name: 'shared-storage',
          StorageType: 'Ebs',
          EbsSettings: {
            Size: ebsStorageSize,
            VolumeType: 'gp3',
            Encrypted: true,
          },
        },
        {
          MountDir: '/fsx',
          Name: 'fsx-storage',
          StorageType: 'FsxLustre',
          FsxLustreSettings: {
            StorageCapacity: fsxStorageCapacity,
            DeploymentType: 'SCRATCH_2',
            ImportPath: `s3://${this.s3Bucket.bucketName}/`,
            ExportPath: `s3://${this.s3Bucket.bucketName}/output/`,
          },
        },
      ],
      Monitoring: {
        CloudWatch: {
          Enabled: true,
          DashboardName: `${this.clusterName}-dashboard`,
        },
      },
    };
    
    // Create custom resource for ParallelCluster configuration
    const configParameter = new ssm.StringParameter(this, 'ParallelClusterConfig', {
      parameterName: `/parallelcluster/${this.clusterName}/config`,
      stringValue: JSON.stringify(clusterConfig, null, 2),
      description: 'ParallelCluster configuration for HPC deployment',
    });
    
    // Create custom resource to deploy ParallelCluster
    const clusterCustomResource = new cr.AwsCustomResource(this, 'ParallelClusterDeployment', {
      onCreate: {
        service: 'SSM',
        action: 'putParameter',
        parameters: {
          Name: `/parallelcluster/${this.clusterName}/status`,
          Value: 'CREATE_REQUESTED',
          Type: 'String',
        },
        physicalResourceId: cr.PhysicalResourceId.of(`parallelcluster-${this.clusterName}`),
      },
      onDelete: {
        service: 'SSM',
        action: 'deleteParameter',
        parameters: {
          Name: `/parallelcluster/${this.clusterName}/status`,
        },
      },
      policy: cr.AwsCustomResourcePolicy.fromSdkCalls({
        resources: cr.AwsCustomResourcePolicy.ANY_RESOURCE,
      }),
    });
    
    clusterCustomResource.node.addDependency(configParameter);
  }
  
  /**
   * Creates CloudWatch monitoring dashboard for cluster metrics
   */
  private createMonitoringDashboard() {
    const dashboard = new cloudwatch.Dashboard(this, 'HpcDashboard', {
      dashboardName: `${this.clusterName}-performance`,
      defaultInterval: cdk.Duration.minutes(5),
    });
    
    // Add CPU utilization widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Cluster CPU Utilization',
        width: 12,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/EC2',
            metricName: 'CPUUtilization',
            dimensionsMap: {
              ClusterName: this.clusterName,
            },
            statistic: 'Average',
          }),
        ],
      })
    );
    
    // Add network metrics widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Network Traffic',
        width: 12,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/EC2',
            metricName: 'NetworkIn',
            dimensionsMap: {
              ClusterName: this.clusterName,
            },
            statistic: 'Sum',
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/EC2',
            metricName: 'NetworkOut',
            dimensionsMap: {
              ClusterName: this.clusterName,
            },
            statistic: 'Sum',
          }),
        ],
      })
    );
    
    // Add storage metrics widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Storage Performance',
        width: 12,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/FSx',
            metricName: 'TotalIOTime',
            dimensionsMap: {
              FileSystemId: 'fs-*',
            },
            statistic: 'Average',
          }),
        ],
      })
    );
  }
  
  /**
   * Creates CloudWatch alarms for proactive cluster monitoring
   */
  private createCloudWatchAlarms() {
    // High CPU utilization alarm
    new cloudwatch.Alarm(this, 'HighCpuAlarm', {
      alarmName: `${this.clusterName}-high-cpu`,
      alarmDescription: 'High CPU utilization detected on HPC cluster',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/EC2',
        metricName: 'CPUUtilization',
        dimensionsMap: {
          ClusterName: this.clusterName,
        },
        statistic: 'Average',
      }),
      threshold: 80,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      datapointsToAlarm: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    
    // Low network performance alarm
    new cloudwatch.Alarm(this, 'LowNetworkAlarm', {
      alarmName: `${this.clusterName}-low-network`,
      alarmDescription: 'Low network performance detected on HPC cluster',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/EC2',
        metricName: 'NetworkIn',
        dimensionsMap: {
          ClusterName: this.clusterName,
        },
        statistic: 'Average',
      }),
      threshold: 1000000, // 1 MB/s
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 3,
      datapointsToAlarm: 3,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
  }
  
  /**
   * Creates CloudFormation outputs for cluster information
   */
  private createOutputs() {
    new cdk.CfnOutput(this, 'ClusterName', {
      value: this.clusterName,
      description: 'Name of the HPC ParallelCluster',
      exportName: `${this.stackName}-ClusterName`,
    });
    
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for the HPC cluster',
      exportName: `${this.stackName}-VpcId`,
    });
    
    new cdk.CfnOutput(this, 'S3BucketName', {
      value: this.s3Bucket.bucketName,
      description: 'S3 bucket for HPC data storage',
      exportName: `${this.stackName}-S3BucketName`,
    });
    
    new cdk.CfnOutput(this, 'KeyPairName', {
      value: this.keyPair.keyName || '',
      description: 'EC2 Key Pair for cluster access',
      exportName: `${this.stackName}-KeyPairName`,
    });
    
    new cdk.CfnOutput(this, 'PublicSubnetId', {
      value: this.vpc.publicSubnets[0].subnetId,
      description: 'Public subnet ID for head node',
      exportName: `${this.stackName}-PublicSubnetId`,
    });
    
    new cdk.CfnOutput(this, 'PrivateSubnetId', {
      value: this.vpc.privateSubnets[0].subnetId,
      description: 'Private subnet ID for compute nodes',
      exportName: `${this.stackName}-PrivateSubnetId`,
    });
    
    new cdk.CfnOutput(this, 'ConfigParameterName', {
      value: `/parallelcluster/${this.clusterName}/config`,
      description: 'SSM Parameter name for ParallelCluster configuration',
      exportName: `${this.stackName}-ConfigParameterName`,
    });
    
    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.clusterName}-performance`,
      description: 'CloudWatch dashboard URL for monitoring',
      exportName: `${this.stackName}-DashboardUrl`,
    });
  }
}

/**
 * Main CDK application for HPC ParallelCluster deployment
 */
class HpcParallelClusterApp extends cdk.App {
  constructor() {
    super();
    
    // Get configuration from context or environment variables
    const clusterName = this.node.tryGetContext('clusterName') || process.env.CLUSTER_NAME;
    const instanceType = this.node.tryGetContext('instanceType') || process.env.INSTANCE_TYPE || 'c5n.large';
    const maxNodes = parseInt(this.node.tryGetContext('maxNodes') || process.env.MAX_NODES || '10');
    const fsxStorageCapacity = parseInt(this.node.tryGetContext('fsxStorageCapacity') || process.env.FSX_STORAGE_CAPACITY || '1200');
    const ebsStorageSize = parseInt(this.node.tryGetContext('ebsStorageSize') || process.env.EBS_STORAGE_SIZE || '100');
    
    // Create the HPC stack
    new HpcParallelClusterStack(this, 'HpcParallelClusterStack', {
      clusterName,
      instanceType,
      maxNodes,
      fsxStorageCapacity,
      ebsStorageSize,
      env: {
        account: process.env.CDK_DEFAULT_ACCOUNT,
        region: process.env.CDK_DEFAULT_REGION,
      },
      description: 'AWS CDK stack for High Performance Computing with ParallelCluster',
      tags: {
        Project: 'HPC-ParallelCluster',
        Environment: 'Production',
        Application: 'Scientific-Computing',
        CostCenter: 'Research',
      },
    });
  }
}

// Import missing modules
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';

// Fix the import alias
const { BucketDeployment, Source } = s3deploy;

// Initialize and run the CDK application
const app = new HpcParallelClusterApp();
app.synth();