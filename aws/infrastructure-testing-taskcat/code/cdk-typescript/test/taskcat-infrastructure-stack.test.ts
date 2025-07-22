import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { TaskCatInfrastructureStack } from '../lib/taskcat-infrastructure-stack';

describe('TaskCatInfrastructureStack', () => {
  let app: cdk.App;
  let stack: TaskCatInfrastructureStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new TaskCatInfrastructureStack(app, 'TestStack', {
      env: {
        account: '123456789012',
        region: 'us-east-1',
      },
    });
    template = Template.fromStack(stack);
  });

  describe('VPC Resources', () => {
    test('creates VPC with correct configuration', () => {
      template.hasResourceProperties('AWS::EC2::VPC', {
        CidrBlock: '10.0.0.0/16',
        EnableDnsHostnames: true,
        EnableDnsSupport: true,
      });
    });

    test('creates public subnets', () => {
      template.hasResourceProperties('AWS::EC2::Subnet', {
        MapPublicIpOnLaunch: true,
      });
    });

    test('creates private subnets', () => {
      template.hasResourceProperties('AWS::EC2::Subnet', {
        MapPublicIpOnLaunch: Match.absent(),
      });
    });

    test('creates internet gateway', () => {
      template.hasResourceProperties('AWS::EC2::InternetGateway', {});
    });

    test('creates NAT gateway when enabled', () => {
      template.hasResourceProperties('AWS::EC2::NatGateway', {});
    });
  });

  describe('S3 Resources', () => {
    test('creates TaskCat artifacts bucket', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        BucketEncryption: {
          ServerSideEncryptionConfiguration: [
            {
              ServerSideEncryptionByDefault: {
                SSEAlgorithm: 'AES256',
              },
            },
          ],
        },
        PublicAccessBlockConfiguration: {
          BlockPublicAcls: true,
          BlockPublicPolicy: true,
          IgnorePublicAcls: true,
          RestrictPublicBuckets: true,
        },
        VersioningConfiguration: {
          Status: 'Enabled',
        },
      });
    });

    test('creates lifecycle configuration', () => {
      template.hasResourceProperties('AWS::S3::Bucket', {
        LifecycleConfiguration: {
          Rules: Match.arrayWith([
            Match.objectLike({
              Id: 'DeleteOldVersions',
              Status: 'Enabled',
              NoncurrentVersionExpirationInDays: 30,
            }),
          ]),
        },
      });
    });
  });

  describe('IAM Resources', () => {
    test('creates TaskCat testing role', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        AssumeRolePolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Effect: 'Allow',
              Principal: {
                Service: Match.anyValue(),
              },
            }),
          ]),
        },
        ManagedPolicyArns: Match.arrayWith([
          Match.stringLikeRegexp('PowerUserAccess'),
          Match.stringLikeRegexp('IAMFullAccess'),
        ]),
      });
    });

    test('creates inline policy for TaskCat permissions', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        Policies: Match.arrayWith([
          Match.objectLike({
            PolicyName: 'TaskCatSpecificPermissions',
            PolicyDocument: {
              Statement: Match.arrayWith([
                Match.objectLike({
                  Effect: 'Allow',
                  Action: Match.arrayWith([
                    'cloudformation:*',
                    's3:*',
                    'ec2:*',
                    'iam:*',
                  ]),
                  Resource: '*',
                }),
              ]),
            },
          }),
        ]),
      });
    });
  });

  describe('CodeCommit Resources', () => {
    test('creates CloudFormation repository', () => {
      template.hasResourceProperties('AWS::CodeCommit::Repository', {
        RepositoryDescription: Match.stringLikeRegexp(
          'Repository for CloudFormation templates tested with TaskCat'
        ),
      });
    });
  });

  describe('CodeBuild Resources', () => {
    test('creates TaskCat build project', () => {
      template.hasResourceProperties('AWS::CodeBuild::Project', {
        Environment: {
          ComputeType: 'BUILD_GENERAL1_SMALL',
          Image: Match.stringLikeRegexp('aws/codebuild/standard'),
          Type: 'LINUX_CONTAINER',
          EnvironmentVariables: Match.arrayWith([
            Match.objectLike({
              Name: 'TASKCAT_BUCKET',
              Value: Match.anyValue(),
            }),
          ]),
        },
        Source: {
          Type: 'CODECOMMIT',
          BuildSpec: Match.anyValue(),
        },
        TimeoutInMinutes: 60,
      });
    });

    test('includes proper build specification', () => {
      template.hasResourceProperties('AWS::CodeBuild::Project', {
        Source: {
          BuildSpec: Match.serializedJson(
            Match.objectLike({
              version: '0.2',
              phases: {
                install: Match.objectLike({
                  commands: Match.arrayWith([Match.stringLikeRegexp('pip install taskcat')]),
                }),
                build: Match.objectLike({
                  commands: Match.arrayWith([Match.stringLikeRegexp('taskcat test run')]),
                }),
              },
            })
          ),
        },
      });
    });
  });

  describe('Security Group Resources', () => {
    test('creates security group with proper rules', () => {
      template.hasResourceProperties('AWS::EC2::SecurityGroup', {
        GroupDescription: 'Security group for TaskCat testing resources',
        SecurityGroupIngress: Match.arrayWith([
          Match.objectLike({
            IpProtocol: 'tcp',
            FromPort: 80,
            ToPort: 80,
          }),
          Match.objectLike({
            IpProtocol: 'tcp',
            FromPort: 443,
            ToPort: 443,
          }),
        ]),
      });
    });
  });

  describe('Stack Outputs', () => {
    test('exports VPC ID', () => {
      template.hasOutput('VPCId', {
        Description: 'VPC ID for TaskCat testing infrastructure',
        Export: {
          Name: 'TaskCatDemo-VPC-ID',
        },
      });
    });

    test('exports TaskCat bucket name', () => {
      template.hasOutput('TaskCatBucketName', {
        Description: 'S3 bucket for TaskCat artifacts',
      });
    });

    test('exports repository clone URL', () => {
      template.hasOutput('CodeRepositoryCloneUrl', {
        Description: 'HTTPS clone URL for the CloudFormation repository',
      });
    });

    test('exports build project name', () => {
      template.hasOutput('BuildProjectName', {
        Description: 'CodeBuild project name for TaskCat testing',
      });
    });
  });

  describe('Custom Configuration', () => {
    test('accepts custom VPC CIDR', () => {
      const customStack = new TaskCatInfrastructureStack(app, 'CustomStack', {
        vpcCidr: '172.16.0.0/16',
        env: {
          account: '123456789012',
          region: 'us-east-1',
        },
      });

      const customTemplate = Template.fromStack(customStack);
      customTemplate.hasResourceProperties('AWS::EC2::VPC', {
        CidrBlock: '172.16.0.0/16',
      });
    });

    test('accepts custom environment name', () => {
      const customStack = new TaskCatInfrastructureStack(app, 'CustomStack', {
        environmentName: 'CustomEnv',
        env: {
          account: '123456789012',
          region: 'us-east-1',
        },
      });

      const customTemplate = Template.fromStack(customStack);
      customTemplate.hasOutput('VPCId', {
        Export: {
          Name: 'CustomEnv-VPC-ID',
        },
      });
    });

    test('can disable NAT Gateway', () => {
      const noNatStack = new TaskCatInfrastructureStack(app, 'NoNatStack', {
        createNatGateway: false,
        env: {
          account: '123456789012',
          region: 'us-east-1',
        },
      });

      const noNatTemplate = Template.fromStack(noNatStack);
      noNatTemplate.resourceCountIs('AWS::EC2::NatGateway', 0);
    });

    test('can enable automated testing', () => {
      const autoStack = new TaskCatInfrastructureStack(app, 'AutoStack', {
        enableAutomatedTesting: true,
        env: {
          account: '123456789012',
          region: 'us-east-1',
        },
      });

      const autoTemplate = Template.fromStack(autoStack);
      autoTemplate.hasResourceProperties('AWS::Events::Rule', {
        Description: 'Trigger TaskCat testing on CodeCommit push',
        EventPattern: {
          source: ['aws.codecommit'],
          detailType: ['CodeCommit Repository State Change'],
        },
      });
    });
  });

  describe('Resource Tagging', () => {
    test('applies consistent tags to resources', () => {
      // VPC tags
      template.hasResourceProperties('AWS::EC2::VPC', {
        Tags: Match.arrayWith([
          {
            Key: 'Name',
            Value: 'TaskCatDemo-VPC',
          },
          {
            Key: 'Environment',
            Value: 'TaskCatDemo',
          },
        ]),
      });

      // S3 bucket tags
      template.hasResourceProperties('AWS::S3::Bucket', {
        Tags: Match.arrayWith([
          {
            Key: 'Name',
            Value: Match.stringLikeRegexp('TaskCatDemo.*Bucket'),
          },
          {
            Key: 'Environment',
            Value: 'TaskCatDemo',
          },
        ]),
      });
    });
  });

  describe('Resource Count Validation', () => {
    test('creates expected number of resources', () => {
      // Core infrastructure
      template.resourceCountIs('AWS::EC2::VPC', 1);
      template.resourceCountIs('AWS::S3::Bucket', 1);
      template.resourceCountIs('AWS::IAM::Role', 1);
      template.resourceCountIs('AWS::CodeCommit::Repository', 1);
      template.resourceCountIs('AWS::CodeBuild::Project', 1);
      template.resourceCountIs('AWS::EC2::SecurityGroup', 1);

      // VPC components
      template.resourceCountIs('AWS::EC2::InternetGateway', 1);
      template.resourceCountIs('AWS::EC2::VPCGatewayAttachment', 1);
      template.resourceCountIs('AWS::EC2::NatGateway', 1);
      template.resourceCountIs('AWS::EC2::EIP', 1);

      // Should have 4 subnets (2 public, 2 private)
      template.resourceCountIs('AWS::EC2::Subnet', 4);

      // Should have 2 route tables (1 public, 1 private)
      template.resourceCountIs('AWS::EC2::RouteTable', 2);
    });
  });
});