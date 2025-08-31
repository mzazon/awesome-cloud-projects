#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { Construct } from 'constructs';

export interface KubernetesLatticeStackProps extends cdk.StackProps {
  readonly clusterAVpcCidr?: string;
  readonly clusterBVpcCidr?: string;
  readonly keyPairName?: string;
  readonly instanceType?: string;
  readonly serviceNetworkName?: string;
  readonly frontendServiceName?: string;
  readonly backendServiceName?: string;
}

export class KubernetesLatticeStack extends cdk.Stack {
  public readonly vpcA: ec2.Vpc;
  public readonly vpcB: ec2.Vpc;
  public readonly instanceA: ec2.Instance;
  public readonly instanceB: ec2.Instance;
  public readonly serviceNetworkId: string;
  public readonly frontendServiceId: string;
  public readonly backendServiceId: string;
  public readonly frontendTargetGroupId: string;
  public readonly backendTargetGroupId: string;

  constructor(scope: Construct, id: string, props: KubernetesLatticeStackProps = {}) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.slice(-6);

    // Default configuration values
    const clusterAVpcCidr = props.clusterAVpcCidr || '10.0.0.0/16';
    const clusterBVpcCidr = props.clusterBVpcCidr || '10.1.0.0/16';
    const instanceType = props.instanceType || 't3.medium';
    const serviceNetworkName = props.serviceNetworkName || `lattice-k8s-mesh-${uniqueSuffix}`;
    const frontendServiceName = props.frontendServiceName || `frontend-svc-${uniqueSuffix}`;
    const backendServiceName = props.backendServiceName || `backend-svc-${uniqueSuffix}`;

    // Create VPC A for Kubernetes Cluster A
    this.vpcA = new ec2.Vpc(this, 'KubernetesClusterVpcA', {
      cidr: clusterAVpcCidr,
      enableDnsHostnames: true,
      enableDnsSupport: true,
      maxAzs: 1,
      natGateways: 0,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
      ],
    });

    // Create VPC B for Kubernetes Cluster B
    this.vpcB = new ec2.Vpc(this, 'KubernetesClusterVpcB', {
      cidr: clusterBVpcCidr,
      enableDnsHostnames: true,
      enableDnsSupport: true,
      maxAzs: 1,
      natGateways: 0,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
      ],
    });

    // Get VPC Lattice managed prefix list for security group rules
    const vpcLatticePrefixList = ec2.ManagedPrefixList.fromLookup(this, 'VpcLatticePrefixList', {
      name: `com.amazonaws.vpce.${this.region}.vpce-svc*`,
    });

    // Create security group for VPC A
    const securityGroupA = new ec2.SecurityGroup(this, 'KubernetesClusterSecurityGroupA', {
      vpc: this.vpcA,
      description: 'Security group for Kubernetes cluster A with VPC Lattice integration',
      allowAllOutbound: true,
    });

    // Allow all internal communication within VPC A
    securityGroupA.addIngressRule(
      securityGroupA,
      ec2.Port.allTraffic(),
      'Allow all internal communication within Kubernetes cluster A'
    );

    // Allow SSH access for cluster management
    securityGroupA.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'Allow SSH access for cluster management'
    );

    // Allow VPC Lattice health checks on frontend service port
    securityGroupA.addIngressRule(
      ec2.Peer.prefixList(vpcLatticePrefixList.prefixListId),
      ec2.Port.tcp(8080),
      'Allow VPC Lattice health checks for frontend service'
    );

    // Create security group for VPC B
    const securityGroupB = new ec2.SecurityGroup(this, 'KubernetesClusterSecurityGroupB', {
      vpc: this.vpcB,
      description: 'Security group for Kubernetes cluster B with VPC Lattice integration',
      allowAllOutbound: true,
    });

    // Allow all internal communication within VPC B
    securityGroupB.addIngressRule(
      securityGroupB,
      ec2.Port.allTraffic(),
      'Allow all internal communication within Kubernetes cluster B'
    );

    // Allow SSH access for cluster management
    securityGroupB.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'Allow SSH access for cluster management'
    );

    // Allow VPC Lattice health checks on backend service port
    securityGroupB.addIngressRule(
      ec2.Peer.prefixList(vpcLatticePrefixList.prefixListId),
      ec2.Port.tcp(9090),
      'Allow VPC Lattice health checks for backend service'
    );

    // Create IAM role for EC2 instances with VPC Lattice permissions
    const ec2Role = new iam.Role(this, 'KubernetesEc2Role', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for Kubernetes EC2 instances with VPC Lattice permissions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
      inlinePolicies: {
        VpcLatticeAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'vpc-lattice:*',
                'ec2:DescribeInstances',
                'ec2:DescribeNetworkInterfaces',
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'cloudwatch:PutMetricData',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create instance profile for EC2 role
    const instanceProfile = new iam.CfnInstanceProfile(this, 'KubernetesInstanceProfile', {
      roles: [ec2Role.roleName],
    });

    // Create key pair for SSH access (users need to import their own key)
    const keyPairName = props.keyPairName || `k8s-lattice-${uniqueSuffix}`;

    // Get latest Amazon Linux 2 AMI
    const amazonLinux2Ami = ec2.MachineImage.latestAmazonLinux2({
      generation: ec2.AmazonLinuxGeneration.AMAZON_LINUX_2,
    });

    // User data script for Kubernetes installation
    const kubernetesUserData = ec2.UserData.forLinux();
    kubernetesUserData.addCommands(
      '#!/bin/bash',
      'yum update -y',
      'yum install -y docker',
      'systemctl start docker',
      'systemctl enable docker',
      'usermod -aG docker ec2-user',
      '',
      '# Install Kubernetes components using new community repository',
      'cat <<REPO > /etc/yum.repos.d/kubernetes.repo',
      '[kubernetes]',
      'name=Kubernetes',
      'baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/',
      'enabled=1',
      'gpgcheck=1',
      'gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key',
      'exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni',
      'REPO',
      '',
      'yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes',
      'systemctl enable kubelet',
      '',
      '# Configure container runtime for kubeadm',
      'cat <<EOF > /etc/docker/daemon.json',
      '{',
      '  "exec-opts": ["native.cgroupdriver=systemd"],',
      '  "log-driver": "json-file",',
      '  "log-opts": {',
      '    "max-size": "100m"',
      '  },',
      '  "storage-driver": "overlay2"',
      '}',
      'EOF',
      '',
      'systemctl restart docker',
      '',
      '# Disable swap for Kubernetes',
      'swapoff -a',
      'sed -i \'/swap/d\' /etc/fstab',
      '',
      '# Configure kernel parameters for Kubernetes',
      'cat <<EOF > /etc/sysctl.d/k8s.conf',
      'net.bridge.bridge-nf-call-ip6tables = 1',
      'net.bridge.bridge-nf-call-iptables = 1',
      'net.ipv4.ip_forward = 1',
      'EOF',
      'sysctl --system',
      '',
      '# Load required kernel modules',
      'modprobe br_netfilter',
      'echo "br_netfilter" > /etc/modules-load.d/k8s.conf',
      '',
      'echo "Kubernetes components installed successfully" > /var/log/k8s-install.log'
    );

    // Launch EC2 instance for Kubernetes cluster A
    this.instanceA = new ec2.Instance(this, 'KubernetesClusterInstanceA', {
      instanceType: new ec2.InstanceType(instanceType),
      machineImage: amazonLinux2Ami,
      vpc: this.vpcA,
      vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
      securityGroup: securityGroupA,
      keyName: keyPairName,
      role: ec2Role,
      userData: kubernetesUserData,
      blockDevices: [
        {
          deviceName: '/dev/xvda',
          volume: ec2.BlockDeviceVolume.ebs(20, {
            volumeType: ec2.EbsDeviceVolumeType.GP3,
            encrypted: true,
          }),
        },
      ],
    });

    // Launch EC2 instance for Kubernetes cluster B
    this.instanceB = new ec2.Instance(this, 'KubernetesClusterInstanceB', {
      instanceType: new ec2.InstanceType(instanceType),
      machineImage: amazonLinux2Ami,
      vpc: this.vpcB,
      vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
      securityGroup: securityGroupB,
      keyName: keyPairName,
      role: ec2Role,
      userData: kubernetesUserData,
      blockDevices: [
        {
          deviceName: '/dev/xvda',
          volume: ec2.BlockDeviceVolume.ebs(20, {
            volumeType: ec2.EbsDeviceVolumeType.GP3,
            encrypted: true,
          }),
        },
      ],
    });

    // Create VPC Lattice Service Network using L1 constructs (VPC Lattice L2 constructs are experimental)
    const serviceNetwork = new cdk.aws_vpclattice.CfnServiceNetwork(this, 'KubernetesServiceNetwork', {
      name: serviceNetworkName,
    });

    // Associate VPC A with the service network
    new cdk.aws_vpclattice.CfnServiceNetworkVpcAssociation(this, 'ServiceNetworkVpcAssociationA', {
      serviceNetworkIdentifier: serviceNetwork.attrId,
      vpcIdentifier: this.vpcA.vpcId,
      securityGroupIds: [securityGroupA.securityGroupId],
    });

    // Associate VPC B with the service network
    new cdk.aws_vpclattice.CfnServiceNetworkVpcAssociation(this, 'ServiceNetworkVpcAssociationB', {
      serviceNetworkIdentifier: serviceNetwork.attrId,
      vpcIdentifier: this.vpcB.vpcId,
      securityGroupIds: [securityGroupB.securityGroupId],
    });

    // Create target group for frontend service (VPC A)
    const frontendTargetGroup = new cdk.aws_vpclattice.CfnTargetGroup(this, 'FrontendTargetGroup', {
      name: `frontend-tg-${uniqueSuffix}`,
      type: 'IP',
      protocol: 'HTTP',
      port: 8080,
      vpcIdentifier: this.vpcA.vpcId,
      healthCheck: {
        enabled: true,
        intervalSeconds: 30,
        timeoutSeconds: 5,
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
        protocol: 'HTTP',
        port: 8080,
        path: '/health',
      },
    });

    // Create target group for backend service (VPC B)
    const backendTargetGroup = new cdk.aws_vpclattice.CfnTargetGroup(this, 'BackendTargetGroup', {
      name: `backend-tg-${uniqueSuffix}`,
      type: 'IP',
      protocol: 'HTTP',
      port: 9090,
      vpcIdentifier: this.vpcB.vpcId,
      healthCheck: {
        enabled: true,
        intervalSeconds: 30,
        timeoutSeconds: 5,
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
        protocol: 'HTTP',
        port: 9090,
        path: '/health',
      },
    });

    // Create VPC Lattice service for frontend
    const frontendService = new cdk.aws_vpclattice.CfnService(this, 'FrontendService', {
      name: frontendServiceName,
    });

    // Create VPC Lattice service for backend
    const backendService = new cdk.aws_vpclattice.CfnService(this, 'BackendService', {
      name: backendServiceName,
    });

    // Create listener for frontend service
    new cdk.aws_vpclattice.CfnListener(this, 'FrontendListener', {
      serviceIdentifier: frontendService.attrId,
      name: 'frontend-listener',
      protocol: 'HTTP',
      port: 80,
      defaultAction: {
        forward: {
          targetGroups: [
            {
              targetGroupIdentifier: frontendTargetGroup.attrId,
              weight: 100,
            },
          ],
        },
      },
    });

    // Create listener for backend service
    new cdk.aws_vpclattice.CfnListener(this, 'BackendListener', {
      serviceIdentifier: backendService.attrId,
      name: 'backend-listener',
      protocol: 'HTTP',
      port: 80,
      defaultAction: {
        forward: {
          targetGroups: [
            {
              targetGroupIdentifier: backendTargetGroup.attrId,
              weight: 100,
            },
          ],
        },
      },
    });

    // Associate frontend service with service network
    new cdk.aws_vpclattice.CfnServiceNetworkServiceAssociation(this, 'FrontendServiceAssociation', {
      serviceNetworkIdentifier: serviceNetwork.attrId,
      serviceIdentifier: frontendService.attrId,
    });

    // Associate backend service with service network
    new cdk.aws_vpclattice.CfnServiceNetworkServiceAssociation(this, 'BackendServiceAssociation', {
      serviceNetworkIdentifier: serviceNetwork.attrId,
      serviceIdentifier: backendService.attrId,
    });

    // Create CloudWatch log group for VPC Lattice access logs
    const logGroup = new logs.LogGroup(this, 'VpcLatticeAccessLogs', {
      logGroupName: `/aws/vpc-lattice/${serviceNetworkName}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Enable access logging for the service network (using custom resource)
    const accessLogSubscription = new cdk.CustomResource(this, 'AccessLogSubscription', {
      serviceToken: this.createAccessLogCustomResourceProvider().serviceToken,
      properties: {
        ServiceNetworkId: serviceNetwork.attrId,
        LogGroupArn: logGroup.logGroupArn,
      },
    });

    // Create CloudWatch dashboard for service mesh monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'VpcLatticeServiceMeshDashboard', {
      dashboardName: `VPC-Lattice-K8s-Mesh-${uniqueSuffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'VPC Lattice Service Network Connections',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/VPCLattice',
                metricName: 'ActiveConnectionCount',
                dimensionsMap: {
                  ServiceNetwork: serviceNetwork.attrId,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/VPCLattice',
                metricName: 'NewConnectionCount',
                dimensionsMap: {
                  ServiceNetwork: serviceNetwork.attrId,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
          }),
        ],
      ],
    });

    // Store IDs for outputs
    this.serviceNetworkId = serviceNetwork.attrId;
    this.frontendServiceId = frontendService.attrId;
    this.backendServiceId = backendService.attrId;
    this.frontendTargetGroupId = frontendTargetGroup.attrId;
    this.backendTargetGroupId = backendTargetGroup.attrId;

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'KubernetesLatticeIntegration');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('CreatedBy', 'CDK');

    // Output important resource identifiers
    new cdk.CfnOutput(this, 'VpcAId', {
      value: this.vpcA.vpcId,
      description: 'VPC ID for Kubernetes cluster A',
    });

    new cdk.CfnOutput(this, 'VpcBId', {
      value: this.vpcB.vpcId,
      description: 'VPC ID for Kubernetes cluster B',
    });

    new cdk.CfnOutput(this, 'InstanceAId', {
      value: this.instanceA.instanceId,
      description: 'EC2 instance ID for Kubernetes cluster A',
    });

    new cdk.CfnOutput(this, 'InstanceBId', {
      value: this.instanceB.instanceId,
      description: 'EC2 instance ID for Kubernetes cluster B',
    });

    new cdk.CfnOutput(this, 'InstanceAPrivateIp', {
      value: this.instanceA.instancePrivateIp,
      description: 'Private IP address of Kubernetes cluster A instance',
    });

    new cdk.CfnOutput(this, 'InstanceBPrivateIp', {
      value: this.instanceB.instancePrivateIp,
      description: 'Private IP address of Kubernetes cluster B instance',
    });

    new cdk.CfnOutput(this, 'ServiceNetworkId', {
      value: this.serviceNetworkId,
      description: 'VPC Lattice service network ID',
    });

    new cdk.CfnOutput(this, 'ServiceNetworkDomain', {
      value: serviceNetwork.attrDnsEntryDomainName,
      description: 'VPC Lattice service network domain name for service discovery',
    });

    new cdk.CfnOutput(this, 'FrontendServiceDns', {
      value: `${frontendServiceName}.${serviceNetwork.attrDnsEntryDomainName}`,
      description: 'DNS name for frontend service in VPC Lattice',
    });

    new cdk.CfnOutput(this, 'BackendServiceDns', {
      value: `${backendServiceName}.${serviceNetwork.attrDnsEntryDomainName}`,
      description: 'DNS name for backend service in VPC Lattice',
    });

    new cdk.CfnOutput(this, 'FrontendTargetGroupId', {
      value: this.frontendTargetGroupId,
      description: 'Target group ID for frontend service',
    });

    new cdk.CfnOutput(this, 'BackendTargetGroupId', {
      value: this.backendTargetGroupId,
      description: 'Target group ID for backend service',
    });

    new cdk.CfnOutput(this, 'CloudWatchLogGroup', {
      value: logGroup.logGroupName,
      description: 'CloudWatch log group for VPC Lattice access logs',
    });

    new cdk.CfnOutput(this, 'CloudWatchDashboard', {
      value: dashboard.dashboardName,
      description: 'CloudWatch dashboard for service mesh monitoring',
    });

    new cdk.CfnOutput(this, 'KeyPairName', {
      value: keyPairName,
      description: 'SSH key pair name (must be created manually before deployment)',
    });

    new cdk.CfnOutput(this, 'RegisterTargetsCommand', {
      value: `aws vpc-lattice register-targets --target-group-identifier ${this.frontendTargetGroupId} --targets id=${this.instanceA.instancePrivateIp},port=8080 && aws vpc-lattice register-targets --target-group-identifier ${this.backendTargetGroupId} --targets id=${this.instanceB.instancePrivateIp},port=9090`,
      description: 'Commands to register EC2 instance IPs as VPC Lattice targets',
    });
  }

  /**
   * Creates a custom resource provider for managing VPC Lattice access log subscriptions
   */
  private createAccessLogCustomResourceProvider(): cdk.Provider {
    // Create Lambda function for custom resource
    const accessLogFunction = new cdk.aws_lambda.Function(this, 'AccessLogCustomResourceFunction', {
      runtime: cdk.aws_lambda.Runtime.PYTHON_3_11,
      handler: 'index.handler',
      timeout: cdk.Duration.minutes(5),
      code: cdk.aws_lambda.Code.fromInline(`
import json
import boto3
import cfnresponse

def handler(event, context):
    try:
        vpc_lattice = boto3.client('vpc-lattice')
        
        if event['RequestType'] == 'Create' or event['RequestType'] == 'Update':
            service_network_id = event['ResourceProperties']['ServiceNetworkId']
            log_group_arn = event['ResourceProperties']['LogGroupArn']
            
            # Put access log subscription
            response = vpc_lattice.put_access_log_subscription(
                serviceNetworkIdentifier=service_network_id,
                destinationArn=log_group_arn
            )
            
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {
                'AccessLogSubscriptionArn': response['arn']
            })
            
        elif event['RequestType'] == 'Delete':
            service_network_id = event['ResourceProperties']['ServiceNetworkId']
            
            # Delete access log subscription
            try:
                vpc_lattice.delete_access_log_subscription(
                    serviceNetworkIdentifier=service_network_id
                )
            except vpc_lattice.exceptions.ResourceNotFoundException:
                # Subscription already deleted
                pass
            
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            
    except Exception as e:
        print(f"Error: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {})
`),
    });

    // Add permissions for VPC Lattice operations
    accessLogFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'vpc-lattice:PutAccessLogSubscription',
          'vpc-lattice:DeleteAccessLogSubscription',
          'vpc-lattice:GetAccessLogSubscription',
        ],
        resources: ['*'],
      })
    );

    // Add permissions for CloudWatch logs
    accessLogFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'logs:CreateLogGroup',
          'logs:CreateLogStream',
          'logs:PutLogEvents',
        ],
        resources: ['*'],
      })
    );

    return new cdk.Provider(this, 'AccessLogCustomResourceProvider', {
      onEventHandler: accessLogFunction,
    });
  }
}

// CDK App
const app = new cdk.App();

// Get configuration from context or use defaults
const stackProps: KubernetesLatticeStackProps = {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Self-Managed Kubernetes Integration with VPC Lattice IP Targets',
  clusterAVpcCidr: app.node.tryGetContext('clusterAVpcCidr'),
  clusterBVpcCidr: app.node.tryGetContext('clusterBVpcCidr'),
  keyPairName: app.node.tryGetContext('keyPairName'),
  instanceType: app.node.tryGetContext('instanceType'),
  serviceNetworkName: app.node.tryGetContext('serviceNetworkName'),
  frontendServiceName: app.node.tryGetContext('frontendServiceName'),
  backendServiceName: app.node.tryGetContext('backendServiceName'),
};

new KubernetesLatticeStack(app, 'KubernetesLatticeStack', stackProps);