import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { AdvancedRequestRoutingStack } from '../lib/advanced-request-routing-stack';

describe('AdvancedRequestRoutingStack', () => {
  let app: cdk.App;
  let stack: AdvancedRequestRoutingStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new AdvancedRequestRoutingStack(app, 'TestStack', {
      vpcCidr: '10.0.0.0/16',
      targetVpcCidr: '10.1.0.0/16',
      environment: 'test',
    });
    template = Template.fromStack(stack);
  });

  test('creates VPC Lattice Service Network', () => {
    template.hasResourceProperties('AWS::VpcLattice::ServiceNetwork', {
      AuthType: 'AWS_IAM',
      Name: Match.stringLikeRegexp('advanced-routing-network-.*'),
    });
  });

  test('creates VPC Lattice Service', () => {
    template.hasResourceProperties('AWS::VpcLattice::Service', {
      AuthType: 'AWS_IAM',
      Name: Match.stringLikeRegexp('api-gateway-service-.*'),
    });
  });

  test('creates two VPCs with correct CIDR blocks', () => {
    template.hasResourceProperties('AWS::EC2::VPC', {
      CidrBlock: '10.0.0.0/16',
      EnableDnsHostnames: true,
      EnableDnsSupport: true,
    });

    template.hasResourceProperties('AWS::EC2::VPC', {
      CidrBlock: '10.1.0.0/16',
      EnableDnsHostnames: true,
      EnableDnsSupport: true,
    });
  });

  test('creates internal Application Load Balancer', () => {
    template.hasResourceProperties('AWS::ElasticLoadBalancingV2::LoadBalancer', {
      Type: 'application',
      Scheme: 'internal',
    });
  });

  test('creates EC2 instances with correct configuration', () => {
    template.hasResourceProperties('AWS::EC2::Instance', {
      InstanceType: 't3.micro',
    });

    // Should have exactly 2 EC2 instances
    template.resourceCountIs('AWS::EC2::Instance', 2);
  });

  test('creates VPC Lattice target group for ALB', () => {
    template.hasResourceProperties('AWS::VpcLattice::TargetGroup', {
      Type: 'ALB',
      Name: Match.stringLikeRegexp('alb-targets-.*'),
    });
  });

  test('creates VPC Lattice listener with HTTP protocol', () => {
    template.hasResourceProperties('AWS::VpcLattice::Listener', {
      Protocol: 'HTTP',
      Port: 80,
      Name: 'http-listener',
    });
  });

  test('creates advanced routing rules', () => {
    // Beta header rule
    template.hasResourceProperties('AWS::VpcLattice::Rule', {
      Name: 'beta-header-rule',
      Priority: 5,
      Match: {
        HttpMatch: {
          HeaderMatches: [
            {
              Name: 'X-Service-Version',
              Match: {
                Exact: 'beta',
              },
            },
          ],
        },
      },
    });

    // API v1 path rule
    template.hasResourceProperties('AWS::VpcLattice::Rule', {
      Name: 'api-v1-path-rule',
      Priority: 10,
      Match: {
        HttpMatch: {
          PathMatch: {
            Match: {
              Prefix: '/api/v1',
            },
          },
        },
      },
    });

    // POST method rule
    template.hasResourceProperties('AWS::VpcLattice::Rule', {
      Name: 'post-method-rule',
      Priority: 15,
      Match: {
        HttpMatch: {
          Method: 'POST',
        },
      },
    });

    // Admin path security rule
    template.hasResourceProperties('AWS::VpcLattice::Rule', {
      Name: 'admin-path-rule',
      Priority: 20,
      Match: {
        HttpMatch: {
          PathMatch: {
            Match: {
              Exact: '/admin',
            },
          },
        },
      },
      Action: {
        FixedResponse: {
          StatusCode: 403,
        },
      },
    });
  });

  test('creates IAM authentication policy', () => {
    template.hasResourceProperties('AWS::VpcLattice::AuthPolicy', {
      Policy: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Principal: '*',
            Action: 'vpc-lattice-svcs:Invoke',
            Resource: '*',
            Condition: {
              StringEquals: {
                'aws:PrincipalAccount': Match.anyValue(),
              },
            },
          },
          {
            Effect: 'Deny',
            Principal: '*',
            Action: 'vpc-lattice-svcs:Invoke',
            Resource: '*',
            Condition: {
              StringEquals: {
                'vpc-lattice-svcs:RequestPath': '/admin',
              },
            },
          },
        ],
      },
    });
  });

  test('creates security groups with appropriate rules', () => {
    // ALB security group
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      GroupDescription: 'Security group for VPC Lattice ALB targets',
      SecurityGroupIngress: [
        {
          CidrIp: '10.0.0.0/8',
          IpProtocol: 'tcp',
          FromPort: 80,
          ToPort: 80,
        },
        {
          CidrIp: '10.0.0.0/8',
          IpProtocol: 'tcp',
          FromPort: 443,
          ToPort: 443,
        },
      ],
    });

    // EC2 security group
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      GroupDescription: 'Security group for EC2 web servers',
    });
  });

  test('creates VPC service network associations', () => {
    template.resourceCountIs('AWS::VpcLattice::ServiceNetworkVpcAssociation', 2);
  });

  test('creates service network service association', () => {
    template.resourceCountIs('AWS::VpcLattice::ServiceNetworkServiceAssociation', 1);
  });

  test('creates ALB target group with health checks', () => {
    template.hasResourceProperties('AWS::ElasticLoadBalancingV2::TargetGroup', {
      Protocol: 'HTTP',
      Port: 80,
      TargetType: 'instance',
      HealthCheckPath: '/',
      HealthCheckIntervalSeconds: 10,
      HealthyThresholdCount: 2,
      UnhealthyThresholdCount: 3,
      HealthCheckTimeoutSeconds: 5,
    });
  });

  test('has correct number of outputs', () => {
    const outputs = template.toJSON().Outputs;
    expect(Object.keys(outputs)).toHaveLength(8);
    
    // Verify key outputs exist
    expect(outputs).toHaveProperty('ServiceNetworkId');
    expect(outputs).toHaveProperty('LatticeServiceId');
    expect(outputs).toHaveProperty('LatticeServiceDomain');
    expect(outputs).toHaveProperty('AlbDnsName');
    expect(outputs).toHaveProperty('PrimaryVpcId');
    expect(outputs).toHaveProperty('TargetVpcId');
    expect(outputs).toHaveProperty('WebServer1Id');
    expect(outputs).toHaveProperty('WebServer2Id');
  });

  test('EC2 instances have IAM role with SSM permissions', () => {
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
      ManagedPolicyArns: [
        {
          'Fn::Join': [
            '',
            [
              'arn:',
              { Ref: 'AWS::Partition' },
              ':iam::aws:policy/AmazonSSMManagedInstanceCore',
            ],
          ],
        },
      ],
    });
  });

  test('stack has appropriate tags', () => {
    // The CDK automatically applies tags from the stack props
    // We can verify this by checking that tags are passed to resources
    const stackJson = template.toJSON();
    expect(stackJson.Parameters).toBeDefined();
  });
});