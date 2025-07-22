import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { DistributedScientificComputingStack } from '../lib/distributed-scientific-computing-stack';

describe('DistributedScientificComputingStack', () => {
  let app: cdk.App;
  let stack: DistributedScientificComputingStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new DistributedScientificComputingStack(app, 'TestStack', {
      nodeCount: 2,
      instanceTypes: ['c5.large'],
      maxvCpus: 64,
    });
    template = Template.fromStack(stack);
  });

  test('Creates VPC with correct configuration', () => {
    template.hasResourceProperties('AWS::EC2::VPC', {
      CidrBlock: '10.0.0.0/16',
      EnableDnsHostnames: true,
      EnableDnsSupport: true,
    });
  });

  test('Creates EFS File System with encryption', () => {
    template.hasResourceProperties('AWS::EFS::FileSystem', {
      Encrypted: true,
      PerformanceMode: 'generalPurpose',
      ThroughputMode: 'provisioned',
      ProvisionedThroughputInMibps: 100,
    });
  });

  test('Creates ECR Repository with image scanning', () => {
    template.hasResourceProperties('AWS::ECR::Repository', {
      ImageScanningConfiguration: {
        ScanOnPush: true,
      },
      ImageTagMutability: 'MUTABLE',
    });
  });

  test('Creates Batch Compute Environment with correct instance types', () => {
    template.hasResourceProperties('AWS::Batch::ComputeEnvironment', {
      Type: 'MANAGED',
      State: 'ENABLED',
      ComputeResources: {
        Type: 'EC2',
        MinvCpus: 0,
        MaxvCpus: 64,
        DesiredvCpus: 0,
        InstanceTypes: ['c5.large'],
      },
    });
  });

  test('Creates Job Queue with correct priority', () => {
    template.hasResourceProperties('AWS::Batch::JobQueue', {
      State: 'ENABLED',
      Priority: 1,
    });
  });

  test('Creates Multi-Node Job Definition', () => {
    template.hasResourceProperties('AWS::Batch::JobDefinition', {
      Type: 'multinode',
      NodeProperties: {
        MainNode: 0,
        NumNodes: 2,
      },
    });
  });

  test('Creates Security Group with MPI communication rules', () => {
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      GroupDescription: 'Security group for multi-node Batch jobs with MPI communication',
    });

    // Check for self-referencing rule (MPI communication)
    template.hasResourceProperties('AWS::EC2::SecurityGroupIngress', {
      IpProtocol: '-1',
      SourceSecurityGroupId: {
        'Fn::GetAtt': [template.findResources('AWS::EC2::SecurityGroup')[0], 'GroupId'],
      },
    });
  });

  test('Creates IAM roles with appropriate policies', () => {
    // Batch service role
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Effect: 'Allow',
            Principal: {
              Service: 'batch.amazonaws.com',
            },
            Action: 'sts:AssumeRole',
          },
        ],
      },
    });

    // Instance role
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Effect: 'Allow',
            Principal: {
              Service: 'ec2.amazonaws.com',
            },
            Action: 'sts:AssumeRole',
          },
        ],
      },
    });
  });

  test('Creates CloudWatch Dashboard for monitoring', () => {
    template.hasResourceProperties('AWS::CloudWatch::Dashboard', {
      DashboardBody: {
        'Fn::Join': ['', [
          '{"widgets":[{"type":"metric","properties":{"metrics":[["AWS/Batch","SubmittedJobs","JobQueue",',
          // Dashboard configuration continues...
        ]],
      },
    });
  });

  test('Creates CloudWatch Alarm for failed jobs', () => {
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      MetricName: 'FailedJobs',
      Namespace: 'AWS/Batch',
      Statistic: 'Sum',
      Threshold: 1,
      ComparisonOperator: 'GreaterThanOrEqualToThreshold',
    });
  });

  test('Creates appropriate outputs', () => {
    const outputs = template.findOutputs('*');
    
    expect(outputs).toHaveProperty('VpcId');
    expect(outputs).toHaveProperty('EfsFileSystemId');
    expect(outputs).toHaveProperty('EcrRepositoryUri');
    expect(outputs).toHaveProperty('BatchComputeEnvironmentName');
    expect(outputs).toHaveProperty('JobQueueName');
    expect(outputs).toHaveProperty('JobDefinitionArn');
    expect(outputs).toHaveProperty('JobSubmissionCommand');
  });

  test('Configures proper resource tags', () => {
    // Check that resources have appropriate tags
    template.hasResourceProperties('AWS::Batch::ComputeEnvironment', {
      ComputeResources: {
        Tags: {
          Environment: 'scientific-computing',
          Purpose: 'multi-node-mpi',
        },
      },
    });
  });

  test('Uses private subnets for compute environment', () => {
    template.hasResourceProperties('AWS::Batch::ComputeEnvironment', {
      ComputeResources: {
        Subnets: [
          {
            Ref: expect.stringMatching(/.*PrivateSubnet.*/)
          },
        ],
      },
    });
  });
});