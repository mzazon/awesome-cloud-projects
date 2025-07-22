import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { App2ContainerStack } from '../lib/app2container-stack';

describe('App2ContainerStack', () => {
  let app: cdk.App;
  let stack: App2ContainerStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new App2ContainerStack(app, 'TestApp2ContainerStack', {
      appName: 'test-app',
      environment: 'test',
      env: {
        account: '123456789012',
        region: 'us-east-1',
      },
    });
    template = Template.fromStack(stack);
  });

  test('VPC is created with correct configuration', () => {
    template.hasResourceProperties('AWS::EC2::VPC', {
      EnableDnsHostnames: true,
      EnableDnsSupport: true,
    });

    // Check for public and private subnets
    template.resourceCountIs('AWS::EC2::Subnet', 6); // 3 AZs × 2 subnet types
  });

  test('ECS Cluster is created with container insights', () => {
    template.hasResourceProperties('AWS::ECS::Cluster', {
      ClusterSettings: [
        {
          Name: 'containerInsights',
          Value: 'enabled',
        },
      ],
    });
  });

  test('ECR Repository is created with correct configuration', () => {
    template.hasResourceProperties('AWS::ECR::Repository', {
      ImageScanningConfiguration: {
        ScanOnPush: true,
      },
      ImageTagMutability: 'MUTABLE',
      LifecyclePolicy: {
        LifecyclePolicyText: JSON.stringify({
          rules: [
            {
              rulePriority: 1,
              description: 'Keep only 10 latest images',
              selection: {
                tagStatus: 'any',
                countType: 'imageCountMoreThan',
                countNumber: 10,
              },
              action: {
                type: 'expire',
              },
            },
          ],
        }),
      },
    });
  });

  test('Application Load Balancer is created', () => {
    template.hasResourceProperties('AWS::ElasticLoadBalancingV2::LoadBalancer', {
      Scheme: 'internet-facing',
      Type: 'application',
    });

    template.hasResourceProperties('AWS::ElasticLoadBalancingV2::Listener', {
      Port: 80,
      Protocol: 'HTTP',
    });
  });

  test('ECS Fargate service is created with correct configuration', () => {
    template.hasResourceProperties('AWS::ECS::Service', {
      LaunchType: 'FARGATE',
      DesiredCount: 2,
      EnableExecuteCommand: true,
    });
  });

  test('ECS Task Definition has correct resource allocation', () => {
    template.hasResourceProperties('AWS::ECS::TaskDefinition', {
      Cpu: '1024',
      Memory: '2048',
      NetworkMode: 'awsvpc',
      RequiresCompatibilities: ['FARGATE'],
    });
  });

  test('Auto Scaling is configured', () => {
    template.hasResourceProperties('AWS::ApplicationAutoScaling::ScalableTarget', {
      MaxCapacity: 10,
      MinCapacity: 1,
      ScalableDimension: 'ecs:service:DesiredCount',
      ServiceNamespace: 'ecs',
    });

    // Check for CPU and Memory scaling policies
    template.resourceCountIs('AWS::ApplicationAutoScaling::ScalingPolicy', 2);
  });

  test('CodeCommit repository is created', () => {
    template.hasResourceProperties('AWS::CodeCommit::Repository', {
      RepositoryDescription: 'App2Container modernization pipeline repository',
    });
  });

  test('CodeBuild project is created with correct configuration', () => {
    template.hasResourceProperties('AWS::CodeBuild::Project', {
      Environment: {
        ComputeType: 'BUILD_GENERAL1_SMALL',
        Image: 'aws/codebuild/standard:7.0',
        PrivilegedMode: true,
        Type: 'LINUX_CONTAINER',
      },
      Source: {
        Type: 'CODECOMMIT',
      },
    });
  });

  test('CodePipeline is created with three stages', () => {
    template.hasResourceProperties('AWS::CodePipeline::Pipeline', {
      Stages: [
        {
          Name: 'Source',
          Actions: [
            {
              ActionTypeId: {
                Category: 'Source',
                Owner: 'AWS',
                Provider: 'CodeCommit',
                Version: '1',
              },
              Name: 'Source',
            },
          ],
        },
        {
          Name: 'Build',
          Actions: [
            {
              ActionTypeId: {
                Category: 'Build',
                Owner: 'AWS',
                Provider: 'CodeBuild',
                Version: '1',
              },
              Name: 'Build',
            },
          ],
        },
        {
          Name: 'Deploy',
          Actions: [
            {
              ActionTypeId: {
                Category: 'Deploy',
                Owner: 'AWS',
                Provider: 'ECS',
                Version: '1',
              },
              Name: 'Deploy',
            },
          ],
        },
      ],
    });
  });

  test('S3 buckets are created with encryption', () => {
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
    });
  });

  test('CloudWatch Log Group is created', () => {
    template.hasResourceProperties('AWS::Logs::LogGroup', {
      RetentionInDays: 30,
    });
  });

  test('Security Groups are configured correctly', () => {
    // ALB Security Group should allow HTTP/HTTPS
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      SecurityGroupIngress: [
        {
          CidrIp: '0.0.0.0/0',
          FromPort: 80,
          IpProtocol: 'tcp',
          ToPort: 80,
        },
        {
          CidrIp: '0.0.0.0/0',
          FromPort: 443,
          IpProtocol: 'tcp',
          ToPort: 443,
        },
      ],
    });
  });

  test('IAM roles are created with appropriate policies', () => {
    // ECS Task Execution Role
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Action: 'sts:AssumeRole',
            Effect: 'Allow',
            Principal: {
              Service: 'ecs-tasks.amazonaws.com',
            },
          },
        ],
      },
      ManagedPolicyArns: [
        {
          'Fn::Join': [
            '',
            [
              'arn:',
              {
                Ref: 'AWS::Partition',
              },
              ':iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy',
            ],
          ],
        },
      ],
    });

    // CodeBuild Role
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Action: 'sts:AssumeRole',
            Effect: 'Allow',
            Principal: {
              Service: 'codebuild.amazonaws.com',
            },
          },
        ],
      },
    });
  });

  test('CloudWatch Dashboard is created', () => {
    template.hasResourceProperties('AWS::CloudWatch::Dashboard', {
      DashboardBody: {
        'Fn::Join': [
          '',
          [
            '{"widgets":[{"type":"metric","properties":{"metrics":[["AWS/ECS","CPUUtilization","ServiceName","',
            // Dashboard body continues...
          ],
        ],
      },
    });
  });

  test('Stack outputs are defined', () => {
    const outputs = template.findOutputs('*');
    
    expect(outputs).toHaveProperty('VpcId');
    expect(outputs).toHaveProperty('ClusterName');
    expect(outputs).toHaveProperty('ECRRepositoryURI');
    expect(outputs).toHaveProperty('LoadBalancerDNS');
    expect(outputs).toHaveProperty('CodeCommitRepositoryCloneUrl');
    expect(outputs).toHaveProperty('ArtifactsBucketName');
    expect(outputs).toHaveProperty('ServiceName');
  });

  test('Resources have appropriate tags', () => {
    // Check that stack-level tags are applied
    const stackTags = stack.tags.tagValues();
    expect(stackTags).toHaveProperty('Project', 'App2Container-Modernization');
    expect(stackTags).toHaveProperty('Environment', 'test');
    expect(stackTags).toHaveProperty('ManagedBy', 'CDK');
  });

  test('High availability configuration', () => {
    // Verify multi-AZ deployment
    template.resourceCountIs('AWS::EC2::NatGateway', 2); // For high availability
    
    // Verify ECS service is distributed across AZs
    template.hasResourceProperties('AWS::ECS::Service', {
      DesiredCount: 2, // Multiple instances for HA
    });
  });

  test('Container health checks are configured', () => {
    template.hasResourceProperties('AWS::ECS::TaskDefinition', {
      ContainerDefinitions: [
        {
          HealthCheck: {
            Command: ['CMD-SHELL', 'curl -f http://localhost:80/health || exit 1'],
            Interval: 30,
            Timeout: 5,
            Retries: 3,
            StartPeriod: 60,
          },
        },
      ],
    });

    template.hasResourceProperties('AWS::ElasticLoadBalancingV2::TargetGroup', {
      HealthCheckEnabled: true,
      HealthCheckIntervalSeconds: 30,
      HealthCheckPath: '/health',
      HealthCheckProtocol: 'HTTP',
      HealthCheckTimeoutSeconds: 5,
      HealthyThresholdCount: 5,
      UnhealthyThresholdCount: 2,
    });
  });
});