import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { HighPerformanceFileSystemsStack } from '../lib/high-performance-file-systems-stack';

describe('HighPerformanceFileSystemsStack', () => {
  let app: cdk.App;
  let stack: HighPerformanceFileSystemsStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new HighPerformanceFileSystemsStack(app, 'TestStack');
    template = Template.fromStack(stack);
  });

  test('Creates FSx for Lustre file system', () => {
    template.hasResourceProperties('AWS::FSx::FileSystem', {
      FileSystemType: 'LUSTRE',
      StorageCapacity: 1200,
      LustreConfiguration: {
        DeploymentType: 'SCRATCH_2',
        PerUnitStorageThroughput: 250,
      },
    });
  });

  test('Creates FSx for Windows file system', () => {
    template.hasResourceProperties('AWS::FSx::FileSystem', {
      FileSystemType: 'WINDOWS',
      StorageCapacity: 32,
      WindowsConfiguration: {
        ThroughputCapacity: 8,
        DeploymentType: 'SINGLE_AZ_1',
      },
    });
  });

  test('Creates S3 bucket for Lustre data repository', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      PublicAccessBlockConfiguration: {
        BlockPublicAcls: true,
        BlockPublicPolicy: true,
        IgnorePublicAcls: true,
        RestrictPublicBuckets: true,
      },
    });
  });

  test('Creates security group with correct ingress rules', () => {
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      SecurityGroupIngress: [
        {
          CidrIp: '10.0.0.0/8',
          FromPort: 988,
          IpProtocol: 'tcp',
          ToPort: 988,
        },
        {
          CidrIp: '10.0.0.0/8',
          FromPort: 445,
          IpProtocol: 'tcp',
          ToPort: 445,
        },
        {
          CidrIp: '10.0.0.0/8',
          FromPort: 111,
          IpProtocol: 'tcp',
          ToPort: 111,
        },
        {
          CidrIp: '10.0.0.0/8',
          FromPort: 2049,
          IpProtocol: 'tcp',
          ToPort: 2049,
        },
      ],
    });
  });

  test('Creates CloudWatch alarms for monitoring', () => {
    // Check for Lustre throughput alarm
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      MetricName: 'ThroughputUtilization',
      Namespace: 'AWS/FSx',
      Threshold: 80,
      ComparisonOperator: 'GreaterThanThreshold',
    });

    // Check for Windows CPU alarm
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      MetricName: 'CPUUtilization',
      Namespace: 'AWS/FSx',
      Threshold: 85,
      ComparisonOperator: 'GreaterThanThreshold',
    });
  });

  test('Creates EC2 instance for testing', () => {
    template.hasResourceProperties('AWS::EC2::Instance', {
      InstanceType: 'c5.large',
    });
  });

  test('Creates IAM role for FSx service', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Action: 'sts:AssumeRole',
            Effect: 'Allow',
            Principal: {
              Service: 'fsx.amazonaws.com',
            },
          },
        ],
      },
    });
  });

  test('Creates CloudWatch log group', () => {
    template.hasResourceProperties('AWS::Logs::LogGroup', {
      RetentionInDays: 7,
    });
  });

  test('Stack should have required outputs', () => {
    template.hasOutput('S3BucketName', {});
    template.hasOutput('LustreFileSystemId', {});
    template.hasOutput('LustreFileSystemDNS', {});
    template.hasOutput('WindowsFileSystemId', {});
    template.hasOutput('WindowsFileSystemDNS', {});
    template.hasOutput('LinuxInstanceId', {});
    template.hasOutput('SecurityGroupId', {});
  });

  test('Stack should have proper tags', () => {
    template.hasResourceProperties('AWS::FSx::FileSystem', {
      Tags: [
        {
          Key: 'Purpose',
          Value: 'HPC-Workloads',
        },
      ],
    });
  });

  test('Stack validates resource count', () => {
    // Should create exactly 2 FSx file systems (Lustre and Windows)
    // ONTAP is conditional based on subnet availability
    const fsxResources = template.findResources('AWS::FSx::FileSystem');
    expect(Object.keys(fsxResources).length).toBeGreaterThanOrEqual(2);
    expect(Object.keys(fsxResources).length).toBeLessThanOrEqual(3);
  });
});