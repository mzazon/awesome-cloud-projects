#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as route53 from 'aws-cdk-lib/aws-route53';

/**
 * Props for configuring the Zero Trust Network Architecture
 */
interface ZeroTrustNetworkProps extends cdk.StackProps {
  /**
   * Environment name for resource tagging
   * @default 'zero-trust'
   */
  readonly environmentName?: string;
  
  /**
   * CIDR block for the consumer VPC
   * @default '10.0.0.0/16'
   */
  readonly consumerVpcCidr?: string;
  
  /**
   * CIDR block for the provider VPC
   * @default '10.1.0.0/16'
   */
  readonly providerVpcCidr?: string;
  
  /**
   * Whether to enable VPC Flow Logs
   * @default true
   */
  readonly enableFlowLogs?: boolean;
  
  /**
   * Whether to create the test Lambda function
   * @default true
   */
  readonly createTestFunction?: boolean;
}

/**
 * Zero Trust Network Architecture Stack using VPC Endpoints and PrivateLink
 * 
 * This stack implements a comprehensive zero trust network architecture that:
 * - Creates isolated VPCs with no internet access
 * - Implements VPC endpoints for AWS services
 * - Sets up PrivateLink for cross-account connectivity
 * - Provides granular security controls through security groups
 * - Enables private DNS resolution
 * - Includes comprehensive monitoring via VPC Flow Logs
 */
export class ZeroTrustNetworkStack extends cdk.Stack {
  public readonly consumerVpc: ec2.Vpc;
  public readonly providerVpc: ec2.Vpc;
  public readonly vpcEndpoints: { [key: string]: ec2.InterfaceVpcEndpoint };
  public readonly endpointService: ec2.VpcEndpointService;
  public readonly privateDnsZone: route53.PrivateHostedZone;

  constructor(scope: Construct, id: string, props: ZeroTrustNetworkProps = {}) {
    super(scope, id, props);

    // Set default values
    const environmentName = props.environmentName ?? 'zero-trust';
    const consumerVpcCidr = props.consumerVpcCidr ?? '10.0.0.0/16';
    const providerVpcCidr = props.providerVpcCidr ?? '10.1.0.0/16';
    const enableFlowLogs = props.enableFlowLogs ?? true;
    const createTestFunction = props.createTestFunction ?? true;

    // Create unique resource suffix
    const resourceSuffix = cdk.Names.uniqueId(this).toLowerCase().slice(-6);

    // === CONSUMER VPC (Zero Trust Network) ===
    this.consumerVpc = new ec2.Vpc(this, 'ConsumerVPC', {
      vpcName: `${environmentName}-consumer-vpc-${resourceSuffix}`,
      ipAddresses: ec2.IpAddresses.cidr(consumerVpcCidr),
      enableDnsHostnames: true,
      enableDnsSupport: true,
      // Create only private subnets for zero trust architecture
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'ZeroTrust-Private-1',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
        {
          cidrMask: 24,
          name: 'ZeroTrust-Private-2',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
      maxAzs: 2,
    });

    // === PROVIDER VPC (Service Provider Network) ===
    this.providerVpc = new ec2.Vpc(this, 'ProviderVPC', {
      vpcName: `${environmentName}-provider-vpc-${resourceSuffix}`,
      ipAddresses: ec2.IpAddresses.cidr(providerVpcCidr),
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Provider-Private',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
      maxAzs: 1,
    });

    // === SECURITY GROUPS ===
    
    // Security group for VPC endpoints (restrictive ingress)
    const endpointSecurityGroup = new ec2.SecurityGroup(this, 'EndpointSecurityGroup', {
      vpc: this.consumerVpc,
      securityGroupName: `zero-trust-endpoint-sg-${resourceSuffix}`,
      description: 'Zero Trust VPC Endpoint Security Group - Allows HTTPS from VPC CIDR',
      allowAllOutbound: false,
    });

    endpointSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(consumerVpcCidr),
      ec2.Port.tcp(443),
      'Allow HTTPS from consumer VPC CIDR'
    );

    // Security group for applications (restrictive egress)
    const applicationSecurityGroup = new ec2.SecurityGroup(this, 'ApplicationSecurityGroup', {
      vpc: this.consumerVpc,
      securityGroupName: `zero-trust-app-sg-${resourceSuffix}`,
      description: 'Zero Trust Application Security Group - Allows outbound to VPC endpoints only',
      allowAllOutbound: false,
    });

    // Allow outbound HTTPS to VPC endpoints only
    applicationSecurityGroup.addEgressRule(
      endpointSecurityGroup,
      ec2.Port.tcp(443),
      'Allow HTTPS to VPC endpoints'
    );

    // Security group for provider services
    const providerSecurityGroup = new ec2.SecurityGroup(this, 'ProviderSecurityGroup', {
      vpc: this.providerVpc,
      securityGroupName: `provider-service-sg-${resourceSuffix}`,
      description: 'Provider Service Security Group - Allows HTTPS from consumer VPC',
      allowAllOutbound: false,
    });

    providerSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(consumerVpcCidr),
      ec2.Port.tcp(443),
      'Allow HTTPS from consumer VPC CIDR'
    );

    // === VPC ENDPOINTS FOR AWS SERVICES ===
    
    this.vpcEndpoints = {};

    // S3 Interface Endpoint with restrictive policy
    const s3EndpointPolicy = new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          principals: [new iam.AnyPrincipal()],
          actions: [
            's3:GetObject',
            's3:PutObject',
            's3:ListBucket',
          ],
          resources: ['*'],
          conditions: {
            StringEquals: {
              'aws:PrincipalAccount': this.account,
            },
          },
        }),
      ],
    });

    this.vpcEndpoints.s3 = new ec2.InterfaceVpcEndpoint(this, 'S3Endpoint', {
      vpc: this.consumerVpc,
      service: ec2.InterfaceVpcEndpointAwsService.S3,
      subnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      securityGroups: [endpointSecurityGroup],
      privateDnsEnabled: true,
      policyDocument: s3EndpointPolicy,
    });

    // Lambda Interface Endpoint
    this.vpcEndpoints.lambda = new ec2.InterfaceVpcEndpoint(this, 'LambdaEndpoint', {
      vpc: this.consumerVpc,
      service: ec2.InterfaceVpcEndpointAwsService.LAMBDA,
      subnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      securityGroups: [endpointSecurityGroup],
      privateDnsEnabled: true,
    });

    // CloudWatch Logs Interface Endpoint
    this.vpcEndpoints.logs = new ec2.InterfaceVpcEndpoint(this, 'LogsEndpoint', {
      vpc: this.consumerVpc,
      service: ec2.InterfaceVpcEndpointAwsService.CLOUDWATCH_LOGS,
      subnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      securityGroups: [endpointSecurityGroup],
      privateDnsEnabled: true,
    });

    // === NETWORK LOAD BALANCER FOR PRIVATELINK ===
    
    const networkLoadBalancer = new elbv2.NetworkLoadBalancer(this, 'NetworkLoadBalancer', {
      loadBalancerName: `zero-trust-nlb-${resourceSuffix}`,
      vpc: this.providerVpc,
      internetFacing: false,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
    });

    // Target group for custom application
    const targetGroup = new elbv2.NetworkTargetGroup(this, 'TargetGroup', {
      targetGroupName: `zero-trust-tg-${resourceSuffix}`,
      port: 443,
      protocol: elbv2.Protocol.TCP,
      vpc: this.providerVpc,
      targetType: elbv2.TargetType.IP,
      healthCheck: {
        protocol: elbv2.Protocol.TCP,
        port: '443',
      },
    });

    // Listener for NLB
    networkLoadBalancer.addListener('Listener', {
      port: 443,
      protocol: elbv2.Protocol.TCP,
      defaultTargetGroups: [targetGroup],
    });

    // === VPC ENDPOINT SERVICE CONFIGURATION ===
    
    this.endpointService = new ec2.VpcEndpointService(this, 'EndpointService', {
      vpcEndpointServiceLoadBalancers: [networkLoadBalancer],
      acceptanceRequired: true,
      allowedPrincipals: [
        new iam.AccountPrincipal(this.account),
      ],
    });

    // === CUSTOM VPC ENDPOINT FOR PRIVATELINK SERVICE ===
    
    const customServiceEndpoint = new ec2.InterfaceVpcEndpoint(this, 'CustomServiceEndpoint', {
      vpc: this.consumerVpc,
      service: new ec2.InterfaceVpcEndpointService(this.endpointService.vpcEndpointServiceName, 443),
      subnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      securityGroups: [endpointSecurityGroup],
      privateDnsEnabled: false, // Custom services typically don't support private DNS
    });

    this.vpcEndpoints.custom = customServiceEndpoint;

    // === PRIVATE DNS CONFIGURATION ===
    
    this.privateDnsZone = new route53.PrivateHostedZone(this, 'PrivateHostedZone', {
      zoneName: 'zero-trust-service.internal',
      vpc: this.consumerVpc,
      comment: 'Private DNS zone for zero trust service discovery',
    });

    // Create CNAME record for custom service
    new route53.CnameRecord(this, 'ServiceCnameRecord', {
      zone: this.privateDnsZone,
      recordName: 'api',
      domainName: customServiceEndpoint.vpcEndpointDnsEntries[0].domainName,
      ttl: cdk.Duration.minutes(5),
      comment: 'DNS record for custom PrivateLink service',
    });

    // === VPC FLOW LOGS ===
    
    if (enableFlowLogs) {
      // IAM role for VPC Flow Logs
      const flowLogsRole = new iam.Role(this, 'VPCFlowLogsRole', {
        roleName: `VPCFlowLogsRole-${resourceSuffix}`,
        assumedBy: new iam.ServicePrincipal('vpc-flow-logs.amazonaws.com'),
        managedPolicies: [
          iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/VPCFlowLogsDeliveryRolePolicy'),
        ],
      });

      // CloudWatch log group for VPC Flow Logs
      const flowLogsGroup = new logs.LogGroup(this, 'VPCFlowLogsGroup', {
        logGroupName: `/aws/vpc/zero-trust-flowlogs-${resourceSuffix}`,
        retention: logs.RetentionDays.ONE_MONTH,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      });

      // VPC Flow Logs for consumer VPC
      new ec2.FlowLog(this, 'ConsumerVPCFlowLog', {
        resourceType: ec2.FlowLogResourceType.fromVpc(this.consumerVpc),
        trafficType: ec2.FlowLogTrafficType.ALL,
        destination: ec2.FlowLogDestination.toCloudWatchLogs(flowLogsGroup, flowLogsRole),
      });

      // VPC Flow Logs for provider VPC
      new ec2.FlowLog(this, 'ProviderVPCFlowLog', {
        resourceType: ec2.FlowLogResourceType.fromVpc(this.providerVpc),
        trafficType: ec2.FlowLogTrafficType.ALL,
        destination: ec2.FlowLogDestination.toCloudWatchLogs(flowLogsGroup, flowLogsRole),
      });
    }

    // === TEST LAMBDA FUNCTION ===
    
    if (createTestFunction) {
      // IAM role for test Lambda function
      const lambdaRole = new iam.Role(this, 'TestLambdaRole', {
        roleName: `ZeroTrustLambdaRole-${resourceSuffix}`,
        assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
        managedPolicies: [
          iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaVPCAccessExecutionRole'),
        ],
        inlinePolicies: {
          S3Access: new iam.PolicyDocument({
            statements: [
              new iam.PolicyStatement({
                effect: iam.Effect.ALLOW,
                actions: ['s3:ListBuckets'],
                resources: ['*'],
              }),
            ],
          }),
        },
      });

      // Test Lambda function
      const testFunction = new lambda.Function(this, 'TestFunction', {
        functionName: `zero-trust-test-${resourceSuffix}`,
        runtime: lambda.Runtime.PYTHON_3_9,
        handler: 'index.lambda_handler',
        role: lambdaRole,
        vpc: this.consumerVpc,
        vpcSubnets: {
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
        securityGroups: [applicationSecurityGroup],
        timeout: cdk.Duration.seconds(30),
        code: lambda.Code.fromInline(`
import json
import boto3
try:
    import urllib3
except ImportError:
    urllib3 = None

def lambda_handler(event, context):
    """Test function to validate zero trust connectivity"""
    results = {
        'message': 'Zero Trust validation complete',
        's3_access': False,
        'internet_access': False,
        'vpc_endpoint_working': False
    }
    
    try:
        # Test S3 access through VPC endpoint
        s3_client = boto3.client('s3')
        buckets = s3_client.list_buckets()
        results['s3_access'] = True
        results['vpc_endpoint_working'] = True
        print(f"S3 access successful - found {len(buckets['Buckets'])} buckets")
        
    except Exception as e:
        print(f"S3 access failed: {str(e)}")
        results['s3_access'] = False
    
    # Test external HTTP request (should fail in zero trust)
    if urllib3:
        try:
            http = urllib3.PoolManager()
            response = http.request('GET', 'https://httpbin.org/get', timeout=5)
            results['internet_access'] = True
            print("WARNING: Internet access is available - zero trust policy violation!")
        except Exception as e:
            print(f"Internet access blocked (expected): {str(e)}")
            results['internet_access'] = False
    else:
        print("urllib3 not available - cannot test internet access")
    
    return {
        'statusCode': 200,
        'body': json.dumps(results, indent=2)
    }
        `),
      });

      // Output the test function name
      new cdk.CfnOutput(this, 'TestFunctionName', {
        value: testFunction.functionName,
        description: 'Name of the test Lambda function for validation',
      });
    }

    // === TAGGING ===
    
    const tags = {
      Environment: environmentName,
      Project: 'ZeroTrustNetworking',
      ManagedBy: 'CDK',
    };

    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });

    // === OUTPUTS ===
    
    new cdk.CfnOutput(this, 'ConsumerVPCId', {
      value: this.consumerVpc.vpcId,
      description: 'ID of the consumer VPC (zero trust network)',
    });

    new cdk.CfnOutput(this, 'ProviderVPCId', {
      value: this.providerVpc.vpcId,
      description: 'ID of the provider VPC',
    });

    new cdk.CfnOutput(this, 'EndpointServiceName', {
      value: this.endpointService.vpcEndpointServiceName,
      description: 'Name of the VPC endpoint service for PrivateLink',
    });

    new cdk.CfnOutput(this, 'S3EndpointId', {
      value: this.vpcEndpoints.s3.vpcEndpointId,
      description: 'ID of the S3 VPC endpoint',
    });

    new cdk.CfnOutput(this, 'LambdaEndpointId', {
      value: this.vpcEndpoints.lambda.vpcEndpointId,
      description: 'ID of the Lambda VPC endpoint',
    });

    new cdk.CfnOutput(this, 'CustomEndpointId', {
      value: this.vpcEndpoints.custom.vpcEndpointId,
      description: 'ID of the custom service VPC endpoint',
    });

    new cdk.CfnOutput(this, 'PrivateHostedZoneId', {
      value: this.privateDnsZone.hostedZoneId,
      description: 'ID of the private hosted zone for service discovery',
    });

    new cdk.CfnOutput(this, 'CustomServiceDNS', {
      value: customServiceEndpoint.vpcEndpointDnsEntries[0].domainName,
      description: 'DNS name for the custom PrivateLink service',
    });
  }
}

/**
 * CDK Application
 */
const app = new cdk.App();

// Create the Zero Trust Network Architecture stack
const stack = new ZeroTrustNetworkStack(app, 'ZeroTrustNetworkStack', {
  description: 'Zero Trust Network Architecture with VPC Endpoints and PrivateLink',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  // Uncomment to customize configuration
  // environmentName: 'production',
  // consumerVpcCidr: '10.0.0.0/16',
  // providerVpcCidr: '10.1.0.0/16',
  // enableFlowLogs: true,
  // createTestFunction: true,
});

// Add stack-level tags
cdk.Tags.of(stack).add('Recipe', 'zero-trust-network-architecture-vpc-endpoints-privatelink');
cdk.Tags.of(stack).add('GeneratedBy', 'CDK-TypeScript');