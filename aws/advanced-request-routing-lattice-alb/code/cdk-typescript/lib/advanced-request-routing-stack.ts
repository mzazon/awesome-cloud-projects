import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as vpclattice from 'aws-cdk-lib/aws-vpclattice';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import { Construct } from 'constructs';

export interface AdvancedRequestRoutingStackProps extends cdk.StackProps {
  vpcCidr: string;
  targetVpcCidr: string;
  environment: string;
}

/**
 * Advanced Request Routing Stack
 * 
 * This stack demonstrates sophisticated layer 7 routing using VPC Lattice
 * integrated with Application Load Balancers across multiple VPCs.
 * 
 * Architecture:
 * - VPC Lattice Service Network for cross-VPC communication
 * - Internal ALBs as VPC Lattice targets
 * - EC2 instances serving different content for routing demonstration
 * - Advanced routing rules based on paths, headers, and methods
 * - IAM-based authentication and authorization
 */
export class AdvancedRequestRoutingStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: AdvancedRequestRoutingStackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // Create primary VPC for API services
    const primaryVpc = new ec2.Vpc(this, 'PrimaryVpc', {
      ipAddresses: ec2.IpAddresses.cidr(props.vpcCidr),
      maxAzs: 2, // ALB requires at least 2 AZs
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
      ],
    });

    // Create target VPC for demonstration of cross-VPC routing
    const targetVpc = new ec2.Vpc(this, 'TargetVpc', {
      ipAddresses: ec2.IpAddresses.cidr(props.targetVpcCidr),
      maxAzs: 1, // Minimal setup for demonstration
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
      ],
    });

    // Security group for ALB - allows HTTP/HTTPS from VPC Lattice
    const albSecurityGroup = new ec2.SecurityGroup(this, 'AlbSecurityGroup', {
      vpc: primaryVpc,
      description: 'Security group for VPC Lattice ALB targets',
      allowAllOutbound: true,
    });

    // Allow HTTP traffic from VPC Lattice (using private IP ranges)
    albSecurityGroup.addIngressRule(
      ec2.Peer.ipv4('10.0.0.0/8'),
      ec2.Port.tcp(80),
      'Allow HTTP from VPC Lattice'
    );

    // Allow HTTPS traffic from VPC Lattice
    albSecurityGroup.addIngressRule(
      ec2.Peer.ipv4('10.0.0.0/8'),
      ec2.Port.tcp(443),
      'Allow HTTPS from VPC Lattice'
    );

    // Security group for EC2 instances
    const ec2SecurityGroup = new ec2.SecurityGroup(this, 'Ec2SecurityGroup', {
      vpc: primaryVpc,
      description: 'Security group for EC2 web servers',
      allowAllOutbound: true,
    });

    // Allow HTTP from ALB security group
    ec2SecurityGroup.addIngressRule(
      albSecurityGroup,
      ec2.Port.tcp(80),
      'Allow HTTP from ALB'
    );

    // Allow SSH access (optional, for debugging)
    ec2SecurityGroup.addIngressRule(
      ec2.Peer.ipv4(props.vpcCidr),
      ec2.Port.tcp(22),
      'Allow SSH from VPC'
    );

    // IAM role for EC2 instances
    const ec2Role = new iam.Role(this, 'Ec2Role', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    // User data script for web servers with routing demonstration content
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      '#!/bin/bash',
      'dnf update -y',
      'dnf install -y httpd',
      'systemctl start httpd',
      'systemctl enable httpd',
      '',
      '# Create different content for routing demonstration',
      'mkdir -p /var/www/html/api/v1',
      'echo "<h1>API V1 Service</h1><p>Path: /api/v1/</p><p>Instance: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>" > /var/www/html/api/v1/index.html',
      'echo "<h1>Default Service</h1><p>Default routing target</p><p>Instance: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>" > /var/www/html/index.html',
      'echo "<h1>Beta Service</h1><p>X-Service-Version: beta</p><p>Instance: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>" > /var/www/html/beta.html',
      '',
      '# Configure virtual hosts for header-based routing',
      'cat >> /etc/httpd/conf/httpd.conf << \'VHOST\'',
      '<VirtualHost *:80>',
      '    DocumentRoot /var/www/html',
      '    RewriteEngine On',
      '    RewriteCond %{HTTP:X-Service-Version} beta',
      '    RewriteRule ^(.*)$ /beta.html [L]',
      '</VirtualHost>',
      'VHOST',
      '',
      'systemctl restart httpd'
    );

    // Get latest Amazon Linux 2023 AMI
    const amiId = ssm.StringParameter.valueForStringParameter(
      this,
      '/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64'
    );

    // Launch EC2 instances for ALB targets
    const webServer1 = new ec2.Instance(this, 'WebServer1', {
      vpc: primaryVpc,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      machineImage: ec2.MachineImage.genericLinux({ [this.region]: amiId }),
      securityGroup: ec2SecurityGroup,
      role: ec2Role,
      userData,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
    });

    const webServer2 = new ec2.Instance(this, 'WebServer2', {
      vpc: primaryVpc,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      machineImage: ec2.MachineImage.genericLinux({ [this.region]: amiId }),
      securityGroup: ec2SecurityGroup,
      role: ec2Role,
      userData,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
    });

    // Create internal Application Load Balancer
    const alb = new elbv2.ApplicationLoadBalancer(this, 'InternalAlb', {
      vpc: primaryVpc,
      internetFacing: false,
      securityGroup: albSecurityGroup,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
    });

    // Create target group for API services
    const targetGroup = new elbv2.ApplicationTargetGroup(this, 'ApiTargetGroup', {
      vpc: primaryVpc,
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.INSTANCE,
      healthCheck: {
        path: '/',
        interval: cdk.Duration.seconds(10),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
        timeout: cdk.Duration.seconds(5),
      },
      targets: [
        new elbv2.InstanceTarget(webServer1.instanceId),
        new elbv2.InstanceTarget(webServer2.instanceId),
      ],
    });

    // Create ALB listener
    const listener = alb.addListener('HttpListener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultTargetGroups: [targetGroup],
    });

    // Create VPC Lattice Service Network
    const serviceNetwork = new vpclattice.CfnServiceNetwork(this, 'ServiceNetwork', {
      name: `advanced-routing-network-${uniqueSuffix}`,
      authType: 'AWS_IAM',
    });

    // Associate VPCs with the service network
    const primaryVpcAssociation = new vpclattice.CfnServiceNetworkVpcAssociation(
      this,
      'PrimaryVpcAssociation',
      {
        serviceNetworkIdentifier: serviceNetwork.attrId,
        vpcIdentifier: primaryVpc.vpcId,
      }
    );

    const targetVpcAssociation = new vpclattice.CfnServiceNetworkVpcAssociation(
      this,
      'TargetVpcAssociation',
      {
        serviceNetworkIdentifier: serviceNetwork.attrId,
        vpcIdentifier: targetVpc.vpcId,
      }
    );

    // Create VPC Lattice Service
    const latticeService = new vpclattice.CfnService(this, 'LatticeService', {
      name: `api-gateway-service-${uniqueSuffix}`,
      authType: 'AWS_IAM',
    });

    // Associate service with service network
    const serviceAssociation = new vpclattice.CfnServiceNetworkServiceAssociation(
      this,
      'ServiceAssociation',
      {
        serviceNetworkIdentifier: serviceNetwork.attrId,
        serviceIdentifier: latticeService.attrId,
      }
    );

    // Create VPC Lattice target group for ALB
    const latticeTargetGroup = new vpclattice.CfnTargetGroup(this, 'LatticeTargetGroup', {
      name: `alb-targets-${uniqueSuffix}`,
      type: 'ALB',
      config: {
        vpcIdentifier: primaryVpc.vpcId,
      },
      targets: [
        {
          id: alb.loadBalancerArn,
        },
      ],
    });

    // Create HTTP listener for VPC Lattice service
    const latticeListener = new vpclattice.CfnListener(this, 'LatticeListener', {
      serviceIdentifier: latticeService.attrId,
      name: 'http-listener',
      protocol: 'HTTP',
      port: 80,
      defaultAction: {
        forward: {
          targetGroups: [
            {
              targetGroupIdentifier: latticeTargetGroup.attrId,
            },
          ],
        },
      },
    });

    // Create advanced routing rules

    // 1. Header-based routing rule for beta service version (highest priority)
    const betaHeaderRule = new vpclattice.CfnRule(this, 'BetaHeaderRule', {
      serviceIdentifier: latticeService.attrId,
      listenerIdentifier: latticeListener.attrId,
      name: 'beta-header-rule',
      priority: 5,
      match: {
        httpMatch: {
          headerMatches: [
            {
              name: 'X-Service-Version',
              match: {
                exact: 'beta',
              },
            },
          ],
        },
      },
      action: {
        forward: {
          targetGroups: [
            {
              targetGroupIdentifier: latticeTargetGroup.attrId,
            },
          ],
        },
      },
    });

    // 2. Path-based routing rule for API v1
    const apiV1PathRule = new vpclattice.CfnRule(this, 'ApiV1PathRule', {
      serviceIdentifier: latticeService.attrId,
      listenerIdentifier: latticeListener.attrId,
      name: 'api-v1-path-rule',
      priority: 10,
      match: {
        httpMatch: {
          pathMatch: {
            match: {
              prefix: '/api/v1',
            },
          },
        },
      },
      action: {
        forward: {
          targetGroups: [
            {
              targetGroupIdentifier: latticeTargetGroup.attrId,
            },
          ],
        },
      },
    });

    // 3. Method-based routing rule for POST requests
    const postMethodRule = new vpclattice.CfnRule(this, 'PostMethodRule', {
      serviceIdentifier: latticeService.attrId,
      listenerIdentifier: latticeListener.attrId,
      name: 'post-method-rule',
      priority: 15,
      match: {
        httpMatch: {
          method: 'POST',
        },
      },
      action: {
        forward: {
          targetGroups: [
            {
              targetGroupIdentifier: latticeTargetGroup.attrId,
            },
          ],
        },
      },
    });

    // 4. Path-based security rule for admin endpoints (blocks access)
    const adminPathRule = new vpclattice.CfnRule(this, 'AdminPathRule', {
      serviceIdentifier: latticeService.attrId,
      listenerIdentifier: latticeListener.attrId,
      name: 'admin-path-rule',
      priority: 20,
      match: {
        httpMatch: {
          pathMatch: {
            match: {
              exact: '/admin',
            },
          },
        },
      },
      action: {
        fixedResponse: {
          statusCode: 403,
        },
      },
    });

    // Create IAM authentication policy for VPC Lattice service
    const authPolicy = {
      Version: '2012-10-17',
      Statement: [
        {
          Effect: 'Allow',
          Principal: '*',
          Action: 'vpc-lattice-svcs:Invoke',
          Resource: '*',
          Condition: {
            StringEquals: {
              'aws:PrincipalAccount': this.account,
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
    };

    // Apply auth policy to VPC Lattice service
    const authPolicyResource = new vpclattice.CfnAuthPolicy(this, 'LatticeAuthPolicy', {
      resourceIdentifier: latticeService.attrId,
      policy: authPolicy,
    });

    // Dependencies to ensure proper resource creation order
    latticeService.addDependency(serviceNetwork);
    serviceAssociation.addDependency(latticeService);
    serviceAssociation.addDependency(serviceNetwork);
    latticeTargetGroup.addDependency(alb);
    latticeListener.addDependency(latticeService);
    latticeListener.addDependency(latticeTargetGroup);
    
    // Rules depend on listener
    betaHeaderRule.addDependency(latticeListener);
    apiV1PathRule.addDependency(latticeListener);
    postMethodRule.addDependency(latticeListener);
    adminPathRule.addDependency(latticeListener);
    
    // Auth policy depends on service
    authPolicyResource.addDependency(latticeService);

    // VPC associations depend on service network
    primaryVpcAssociation.addDependency(serviceNetwork);
    targetVpcAssociation.addDependency(serviceNetwork);

    // CloudFormation Outputs
    new cdk.CfnOutput(this, 'ServiceNetworkId', {
      value: serviceNetwork.attrId,
      description: 'VPC Lattice Service Network ID',
      exportName: `${this.stackName}-ServiceNetworkId`,
    });

    new cdk.CfnOutput(this, 'LatticeServiceId', {
      value: latticeService.attrId,
      description: 'VPC Lattice Service ID',
      exportName: `${this.stackName}-LatticeServiceId`,
    });

    new cdk.CfnOutput(this, 'LatticeServiceDomain', {
      value: latticeService.attrDnsEntry?.domainName || 'Not available',
      description: 'VPC Lattice Service Domain Name',
      exportName: `${this.stackName}-LatticeServiceDomain`,
    });

    new cdk.CfnOutput(this, 'AlbDnsName', {
      value: alb.loadBalancerDnsName,
      description: 'Internal ALB DNS Name',
      exportName: `${this.stackName}-AlbDnsName`,
    });

    new cdk.CfnOutput(this, 'PrimaryVpcId', {
      value: primaryVpc.vpcId,
      description: 'Primary VPC ID',
      exportName: `${this.stackName}-PrimaryVpcId`,
    });

    new cdk.CfnOutput(this, 'TargetVpcId', {
      value: targetVpc.vpcId,
      description: 'Target VPC ID',
      exportName: `${this.stackName}-TargetVpcId`,
    });

    new cdk.CfnOutput(this, 'WebServer1Id', {
      value: webServer1.instanceId,
      description: 'Web Server 1 Instance ID',
      exportName: `${this.stackName}-WebServer1Id`,
    });

    new cdk.CfnOutput(this, 'WebServer2Id', {
      value: webServer2.instanceId,
      description: 'Web Server 2 Instance ID',
      exportName: `${this.stackName}-WebServer2Id`,
    });
  }
}