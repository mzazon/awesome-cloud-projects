#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as eks from 'aws-cdk-lib/aws-eks';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as acm from 'aws-cdk-lib/aws-certificatemanager';
import * as route53 from 'aws-cdk-lib/aws-route53';
import { Construct } from 'constructs';

/**
 * Interface for EKS Ingress Controllers Stack props
 */
interface EksIngressControllersStackProps extends cdk.StackProps {
  /**
   * The VPC CIDR block for the cluster
   * @default '10.0.0.0/16'
   */
  readonly vpcCidr?: string;
  
  /**
   * The EKS cluster version
   * @default '1.28'
   */
  readonly clusterVersion?: eks.KubernetesVersion;
  
  /**
   * The instance type for worker nodes
   * @default 't3.medium'
   */
  readonly nodeInstanceType?: ec2.InstanceType;
  
  /**
   * The desired number of worker nodes
   * @default 3
   */
  readonly nodeGroupSize?: number;
  
  /**
   * The domain name for ingress resources (optional)
   */
  readonly domainName?: string;
  
  /**
   * Whether to create a hosted zone for the domain
   * @default false
   */
  readonly createHostedZone?: boolean;
  
  /**
   * Whether to enable access logging for ALBs
   * @default true
   */
  readonly enableAccessLogging?: boolean;
}

/**
 * CDK Stack for EKS Ingress Controllers with AWS Load Balancer Controller
 * 
 * This stack creates:
 * - VPC with public and private subnets across multiple AZs
 * - EKS cluster with managed node group
 * - AWS Load Balancer Controller with proper IAM permissions
 * - Sample applications and ingress configurations
 * - SSL certificate and Route 53 configuration (optional)
 * - S3 bucket for ALB access logs (optional)
 */
export class EksIngressControllersStack extends cdk.Stack {
  public readonly cluster: eks.Cluster;
  public readonly vpc: ec2.Vpc;
  public readonly loadBalancerController: eks.HelmChart;
  public readonly certificate?: acm.Certificate;
  public readonly hostedZone?: route53.IHostedZone;
  public readonly accessLogsBucket?: s3.Bucket;

  constructor(scope: Construct, id: string, props: EksIngressControllersStackProps = {}) {
    super(scope, id, props);

    // Extract configuration with defaults
    const vpcCidr = props.vpcCidr ?? '10.0.0.0/16';
    const clusterVersion = props.clusterVersion ?? eks.KubernetesVersion.V1_28;
    const nodeInstanceType = props.nodeInstanceType ?? ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM);
    const nodeGroupSize = props.nodeGroupSize ?? 3;
    const enableAccessLogging = props.enableAccessLogging ?? true;
    const createHostedZone = props.createHostedZone ?? false;

    // Create VPC with proper subnet configuration for EKS
    this.vpc = this.createVpc(vpcCidr);

    // Create EKS cluster with managed node group
    this.cluster = this.createEksCluster(clusterVersion, nodeInstanceType, nodeGroupSize);

    // Create Route 53 hosted zone and SSL certificate (if domain provided)
    if (props.domainName) {
      if (createHostedZone) {
        this.hostedZone = this.createHostedZone(props.domainName);
      }
      this.certificate = this.createSslCertificate(props.domainName, this.hostedZone);
    }

    // Create S3 bucket for ALB access logs (if enabled)
    if (enableAccessLogging) {
      this.accessLogsBucket = this.createAccessLogsBucket();
    }

    // Install AWS Load Balancer Controller
    this.loadBalancerController = this.installAwsLoadBalancerController();

    // Deploy sample applications and ingress resources
    this.deploySampleApplications(props.domainName);

    // Output important information
    this.createOutputs(props.domainName);
  }

  /**
   * Create VPC with proper subnet configuration for EKS
   */
  private createVpc(vpcCidr: string): ec2.Vpc {
    const vpc = new ec2.Vpc(this, 'EksIngressVpc', {
      ipAddresses: ec2.IpAddresses.cidr(vpcCidr),
      maxAzs: 3,
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 24,
          mapPublicIpOnLaunch: true,
        },
        {
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
          cidrMask: 24,
        },
      ],
    });

    // Tag subnets for EKS and load balancer discovery
    vpc.publicSubnets.forEach((subnet, index) => {
      cdk.Tags.of(subnet).add('kubernetes.io/role/elb', '1');
      cdk.Tags.of(subnet).add('kubernetes.io/cluster/eks-ingress-cluster', 'shared');
    });

    vpc.privateSubnets.forEach((subnet, index) => {
      cdk.Tags.of(subnet).add('kubernetes.io/role/internal-elb', '1');
      cdk.Tags.of(subnet).add('kubernetes.io/cluster/eks-ingress-cluster', 'shared');
    });

    return vpc;
  }

  /**
   * Create EKS cluster with managed node group
   */
  private createEksCluster(
    clusterVersion: eks.KubernetesVersion,
    nodeInstanceType: ec2.InstanceType,
    nodeGroupSize: number
  ): eks.Cluster {
    // Create cluster service role
    const clusterRole = new iam.Role(this, 'EksClusterRole', {
      assumedBy: new iam.ServicePrincipal('eks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKSClusterPolicy'),
      ],
    });

    // Create node group role
    const nodeGroupRole = new iam.Role(this, 'EksNodeGroupRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKSWorkerNodePolicy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKS_CNI_Policy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEC2ContainerRegistryReadOnly'),
      ],
    });

    // Create EKS cluster
    const cluster = new eks.Cluster(this, 'EksIngressCluster', {
      clusterName: 'eks-ingress-cluster',
      version: clusterVersion,
      vpc: this.vpc,
      vpcSubnets: [{ subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS }],
      role: clusterRole,
      endpointAccess: eks.EndpointAccess.PUBLIC_AND_PRIVATE,
      defaultCapacity: 0, // We'll add managed node group separately
      outputClusterName: true,
      outputConfigCommand: true,
    });

    // Add managed node group
    cluster.addNodegroupCapacity('ManagedNodeGroup', {
      nodegroupName: 'eks-ingress-nodes',
      instanceTypes: [nodeInstanceType],
      minSize: nodeGroupSize,
      maxSize: nodeGroupSize * 2,
      desiredSize: nodeGroupSize,
      nodeRole: nodeGroupRole,
      amiType: eks.NodegroupAmiType.AL2_X86_64,
      capacityType: eks.CapacityType.ON_DEMAND,
      diskSize: 20,
      subnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      tags: {
        'kubernetes.io/cluster/eks-ingress-cluster': 'owned',
      },
    });

    return cluster;
  }

  /**
   * Create Route 53 hosted zone
   */
  private createHostedZone(domainName: string): route53.HostedZone {
    return new route53.HostedZone(this, 'HostedZone', {
      zoneName: domainName,
      comment: 'Hosted zone for EKS ingress demo',
    });
  }

  /**
   * Create SSL certificate using ACM
   */
  private createSslCertificate(domainName: string, hostedZone?: route53.IHostedZone): acm.Certificate {
    const certificateProps: acm.CertificateProps = {
      domainName: `*.${domainName}`,
      subjectAlternativeNames: [domainName],
      validation: hostedZone 
        ? acm.CertificateValidation.fromDns(hostedZone)
        : acm.CertificateValidation.fromEmail(),
    };

    return new acm.Certificate(this, 'SslCertificate', certificateProps);
  }

  /**
   * Create S3 bucket for ALB access logs
   */
  private createAccessLogsBucket(): s3.Bucket {
    const bucket = new s3.Bucket(this, 'AlbAccessLogsBucket', {
      bucketName: `alb-access-logs-${cdk.Aws.ACCOUNT_ID}-${cdk.Aws.REGION}`,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteOldLogs',
          enabled: true,
          expiration: cdk.Duration.days(90),
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(60),
            },
          ],
        },
      ],
    });

    // Add bucket policy for ALB service account
    const albServiceAccountPrincipal = this.getAlbServiceAccountPrincipal();
    bucket.addToResourcePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal(albServiceAccountPrincipal)],
        actions: ['s3:PutObject'],
        resources: [`${bucket.bucketArn}/alb-logs/*`],
      })
    );

    bucket.addToResourcePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal(albServiceAccountPrincipal)],
        actions: ['s3:PutBucketAcl'],
        resources: [bucket.bucketArn],
      })
    );

    return bucket;
  }

  /**
   * Get ALB service account principal for the current region
   */
  private getAlbServiceAccountPrincipal(): string {
    const regionToAccountMap: { [key: string]: string } = {
      'us-east-1': '127311923021',
      'us-east-2': '033677994240',
      'us-west-1': '027434742980',
      'us-west-2': '797873946194',
      'eu-west-1': '156460612806',
      'eu-west-2': '652711504416',
      'eu-west-3': '009996457667',
      'eu-central-1': '054676820928',
      'ap-southeast-1': '114774131450',
      'ap-southeast-2': '783225319266',
      'ap-northeast-1': '582318560864',
      'ap-northeast-2': '600734575887',
      'sa-east-1': '507241528517',
    };

    const accountId = regionToAccountMap[cdk.Aws.REGION];
    return accountId ? `elasticloadbalancing.amazonaws.com` : 'elasticloadbalancing.amazonaws.com';
  }

  /**
   * Install AWS Load Balancer Controller using Helm
   */
  private installAwsLoadBalancerController(): eks.HelmChart {
    // Create IAM role for AWS Load Balancer Controller
    const loadBalancerControllerRole = new iam.Role(this, 'AwsLoadBalancerControllerRole', {
      assumedBy: new iam.WebIdentityPrincipal(
        this.cluster.openIdConnectProvider.openIdConnectProviderArn,
        {
          StringEquals: {
            [`${this.cluster.openIdConnectProvider.openIdConnectProviderIssuer}:sub`]: 
              'system:serviceaccount:kube-system:aws-load-balancer-controller',
            [`${this.cluster.openIdConnectProvider.openIdConnectProviderIssuer}:aud`]: 'sts.amazonaws.com',
          },
        }
      ),
    });

    // Attach the required policy to the role
    const loadBalancerControllerPolicy = new iam.Policy(this, 'AwsLoadBalancerControllerPolicy', {
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'iam:CreateServiceLinkedRole',
            'ec2:DescribeAccountAttributes',
            'ec2:DescribeAddresses',
            'ec2:DescribeAvailabilityZones',
            'ec2:DescribeInternetGateways',
            'ec2:DescribeVpcs',
            'ec2:DescribeSubnets',
            'ec2:DescribeSecurityGroups',
            'ec2:DescribeInstances',
            'ec2:DescribeNetworkInterfaces',
            'ec2:DescribeTags',
            'ec2:GetCoipPoolUsage',
            'ec2:DescribeCoipPools',
            'elasticloadbalancing:DescribeLoadBalancers',
            'elasticloadbalancing:DescribeLoadBalancerAttributes',
            'elasticloadbalancing:DescribeListeners',
            'elasticloadbalancing:DescribeListenerCertificates',
            'elasticloadbalancing:DescribeSSLPolicies',
            'elasticloadbalancing:DescribeRules',
            'elasticloadbalancing:DescribeTargetGroups',
            'elasticloadbalancing:DescribeTargetGroupAttributes',
            'elasticloadbalancing:DescribeTargetHealth',
            'elasticloadbalancing:DescribeTags',
          ],
          resources: ['*'],
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'cognito-idp:DescribeUserPoolClient',
            'acm:ListCertificates',
            'acm:DescribeCertificate',
            'iam:ListServerCertificates',
            'iam:GetServerCertificate',
            'waf-regional:GetWebACL',
            'waf-regional:GetWebACLForResource',
            'waf-regional:AssociateWebACL',
            'waf-regional:DisassociateWebACL',
            'wafv2:GetWebACL',
            'wafv2:GetWebACLForResource',
            'wafv2:AssociateWebACL',
            'wafv2:DisassociateWebACL',
            'shield:DescribeProtection',
            'shield:CreateProtection',
            'shield:DescribeSubscription',
            'shield:ListProtections',
          ],
          resources: ['*'],
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'ec2:AuthorizeSecurityGroupIngress',
            'ec2:RevokeSecurityGroupIngress',
          ],
          resources: ['*'],
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'ec2:CreateSecurityGroup',
          ],
          resources: ['*'],
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'ec2:CreateTags',
          ],
          resources: ['arn:aws:ec2:*:*:security-group/*'],
          conditions: {
            StringEquals: {
              'ec2:CreateAction': 'CreateSecurityGroup',
            },
            Null: {
              'aws:RequestedRegion': 'false',
            },
          },
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'ec2:CreateTags',
            'ec2:DeleteTags',
          ],
          resources: ['arn:aws:ec2:*:*:security-group/*'],
          conditions: {
            Null: {
              'aws:RequestedRegion': 'false',
              'aws:ResourceTag/elbv2.k8s.aws/cluster': 'false',
            },
          },
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'elasticloadbalancing:CreateLoadBalancer',
            'elasticloadbalancing:CreateTargetGroup',
          ],
          resources: ['*'],
          conditions: {
            Null: {
              'aws:RequestedRegion': 'false',
            },
          },
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'elasticloadbalancing:CreateListener',
            'elasticloadbalancing:DeleteListener',
            'elasticloadbalancing:CreateRule',
            'elasticloadbalancing:DeleteRule',
          ],
          resources: ['*'],
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'elasticloadbalancing:AddTags',
            'elasticloadbalancing:RemoveTags',
          ],
          resources: [
            'arn:aws:elasticloadbalancing:*:*:targetgroup/*/*',
            'arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*',
            'arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*',
          ],
          conditions: {
            Null: {
              'aws:RequestedRegion': 'false',
              'aws:ResourceTag/elbv2.k8s.aws/cluster': 'false',
            },
          },
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'elasticloadbalancing:AddTags',
            'elasticloadbalancing:RemoveTags',
          ],
          resources: [
            'arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*',
            'arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*',
            'arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*',
            'arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*',
          ],
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'elasticloadbalancing:ModifyLoadBalancerAttributes',
            'elasticloadbalancing:SetIpAddressType',
            'elasticloadbalancing:SetSecurityGroups',
            'elasticloadbalancing:SetSubnets',
            'elasticloadbalancing:DeleteLoadBalancer',
            'elasticloadbalancing:ModifyTargetGroup',
            'elasticloadbalancing:ModifyTargetGroupAttributes',
            'elasticloadbalancing:DeleteTargetGroup',
          ],
          resources: ['*'],
          conditions: {
            Null: {
              'aws:ResourceTag/elbv2.k8s.aws/cluster': 'false',
            },
          },
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'elasticloadbalancing:RegisterTargets',
            'elasticloadbalancing:DeregisterTargets',
          ],
          resources: ['arn:aws:elasticloadbalancing:*:*:targetgroup/*/*'],
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'elasticloadbalancing:SetWebAcl',
            'elasticloadbalancing:ModifyListener',
            'elasticloadbalancing:AddListenerCertificates',
            'elasticloadbalancing:RemoveListenerCertificates',
            'elasticloadbalancing:ModifyRule',
          ],
          resources: ['*'],
        }),
      ],
    });

    loadBalancerControllerRole.attachInlinePolicy(loadBalancerControllerPolicy);

    // Create service account
    const loadBalancerControllerServiceAccount = this.cluster.addServiceAccount('AwsLoadBalancerControllerServiceAccount', {
      name: 'aws-load-balancer-controller',
      namespace: 'kube-system',
      role: loadBalancerControllerRole,
    });

    // Install AWS Load Balancer Controller using Helm
    const helmChart = this.cluster.addHelmChart('AwsLoadBalancerController', {
      chart: 'aws-load-balancer-controller',
      repository: 'https://aws.github.io/eks-charts',
      namespace: 'kube-system',
      release: 'aws-load-balancer-controller',
      version: '1.6.2',
      values: {
        clusterName: this.cluster.clusterName,
        serviceAccount: {
          create: false,
          name: 'aws-load-balancer-controller',
        },
        region: cdk.Aws.REGION,
        vpcId: this.vpc.vpcId,
      },
    });

    // Ensure service account is created before Helm chart
    helmChart.node.addDependency(loadBalancerControllerServiceAccount);

    return helmChart;
  }

  /**
   * Deploy sample applications and ingress resources
   */
  private deploySampleApplications(domainName?: string): void {
    // Create namespace for demo applications
    const namespace = this.cluster.addManifest('IngressDemoNamespace', {
      apiVersion: 'v1',
      kind: 'Namespace',
      metadata: {
        name: 'ingress-demo',
      },
    });

    // Deploy sample application v1
    const appV1Deployment = this.cluster.addManifest('SampleAppV1Deployment', {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        namespace: 'ingress-demo',
        name: 'sample-app-v1',
      },
      spec: {
        replicas: 3,
        selector: {
          matchLabels: {
            app: 'sample-app',
            version: 'v1',
          },
        },
        template: {
          metadata: {
            labels: {
              app: 'sample-app',
              version: 'v1',
            },
          },
          spec: {
            containers: [
              {
                name: 'app',
                image: 'nginx:1.21',
                ports: [
                  {
                    containerPort: 80,
                  },
                ],
                env: [
                  {
                    name: 'VERSION',
                    value: 'v1',
                  },
                ],
              },
            ],
          },
        },
      },
    });

    const appV1Service = this.cluster.addManifest('SampleAppV1Service', {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        namespace: 'ingress-demo',
        name: 'sample-app-v1',
      },
      spec: {
        selector: {
          app: 'sample-app',
          version: 'v1',
        },
        ports: [
          {
            port: 80,
            targetPort: 80,
          },
        ],
        type: 'ClusterIP',
      },
    });

    // Deploy sample application v2
    const appV2Deployment = this.cluster.addManifest('SampleAppV2Deployment', {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: {
        namespace: 'ingress-demo',
        name: 'sample-app-v2',
      },
      spec: {
        replicas: 2,
        selector: {
          matchLabels: {
            app: 'sample-app',
            version: 'v2',
          },
        },
        template: {
          metadata: {
            labels: {
              app: 'sample-app',
              version: 'v2',
            },
          },
          spec: {
            containers: [
              {
                name: 'app',
                image: 'nginx:1.21',
                ports: [
                  {
                    containerPort: 80,
                  },
                ],
                env: [
                  {
                    name: 'VERSION',
                    value: 'v2',
                  },
                ],
              },
            ],
          },
        },
      },
    });

    const appV2Service = this.cluster.addManifest('SampleAppV2Service', {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        namespace: 'ingress-demo',
        name: 'sample-app-v2',
      },
      spec: {
        selector: {
          app: 'sample-app',
          version: 'v2',
        },
        ports: [
          {
            port: 80,
            targetPort: 80,
          },
        ],
        type: 'ClusterIP',
      },
    });

    // Create basic ALB ingress
    const basicIngressAnnotations: { [key: string]: string } = {
      'alb.ingress.kubernetes.io/scheme': 'internet-facing',
      'alb.ingress.kubernetes.io/target-type': 'ip',
      'alb.ingress.kubernetes.io/healthcheck-path': '/',
      'alb.ingress.kubernetes.io/healthcheck-interval-seconds': '10',
      'alb.ingress.kubernetes.io/healthcheck-timeout-seconds': '5',
      'alb.ingress.kubernetes.io/healthy-threshold-count': '2',
      'alb.ingress.kubernetes.io/unhealthy-threshold-count': '3',
      'alb.ingress.kubernetes.io/tags': 'Environment=demo,Team=platform',
    };

    // Add SSL configuration if certificate is available
    if (this.certificate) {
      basicIngressAnnotations['alb.ingress.kubernetes.io/listen-ports'] = '[{"HTTP": 80}, {"HTTPS": 443}]';
      basicIngressAnnotations['alb.ingress.kubernetes.io/ssl-redirect'] = '443';
      basicIngressAnnotations['alb.ingress.kubernetes.io/certificate-arn'] = this.certificate.certificateArn;
      basicIngressAnnotations['alb.ingress.kubernetes.io/ssl-policy'] = 'ELBSecurityPolicy-TLS-1-2-2019-07';
    }

    // Add access logging if bucket is available
    if (this.accessLogsBucket) {
      basicIngressAnnotations['alb.ingress.kubernetes.io/load-balancer-attributes'] = 
        `access_logs.s3.enabled=true,access_logs.s3.bucket=${this.accessLogsBucket.bucketName},access_logs.s3.prefix=alb-logs`;
    }

    const basicIngress = this.cluster.addManifest('BasicAlbIngress', {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'Ingress',
      metadata: {
        namespace: 'ingress-demo',
        name: 'sample-app-basic-alb',
        annotations: basicIngressAnnotations,
      },
      spec: {
        ingressClassName: 'alb',
        rules: [
          {
            host: domainName ? `basic.${domainName}` : undefined,
            http: {
              paths: [
                {
                  path: '/',
                  pathType: 'Prefix',
                  backend: {
                    service: {
                      name: 'sample-app-v1',
                      port: {
                        number: 80,
                      },
                    },
                  },
                },
              ],
            },
          },
        ],
      },
    });

    // Create weighted routing ingress
    const weightedIngress = this.cluster.addManifest('WeightedRoutingIngress', {
      apiVersion: 'networking.k8s.io/v1',
      kind: 'Ingress',
      metadata: {
        namespace: 'ingress-demo',
        name: 'sample-app-weighted-routing',
        annotations: {
          'alb.ingress.kubernetes.io/scheme': 'internet-facing',
          'alb.ingress.kubernetes.io/target-type': 'ip',
          'alb.ingress.kubernetes.io/group.name': 'weighted-routing',
          'alb.ingress.kubernetes.io/actions.weighted-routing': JSON.stringify({
            type: 'forward',
            forwardConfig: {
              targetGroups: [
                {
                  serviceName: 'sample-app-v1',
                  servicePort: '80',
                  weight: 70,
                },
                {
                  serviceName: 'sample-app-v2',
                  servicePort: '80',
                  weight: 30,
                },
              ],
            },
          }),
        },
      },
      spec: {
        ingressClassName: 'alb',
        rules: [
          {
            host: domainName ? `weighted.${domainName}` : undefined,
            http: {
              paths: [
                {
                  path: '/',
                  pathType: 'Prefix',
                  backend: {
                    service: {
                      name: 'weighted-routing',
                      port: {
                        name: 'use-annotation',
                      },
                    },
                  },
                },
              ],
            },
          },
        ],
      },
    });

    // Create NLB service
    const nlbService = this.cluster.addManifest('SampleAppNlb', {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: {
        namespace: 'ingress-demo',
        name: 'sample-app-nlb',
        annotations: {
          'service.beta.kubernetes.io/aws-load-balancer-type': 'nlb',
          'service.beta.kubernetes.io/aws-load-balancer-scheme': 'internet-facing',
          'service.beta.kubernetes.io/aws-load-balancer-backend-protocol': 'tcp',
          'service.beta.kubernetes.io/aws-load-balancer-target-type': 'ip',
          'service.beta.kubernetes.io/aws-load-balancer-attributes': 'load_balancing.cross_zone.enabled=true',
          'service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol': 'HTTP',
          'service.beta.kubernetes.io/aws-load-balancer-healthcheck-path': '/',
          'service.beta.kubernetes.io/aws-load-balancer-healthcheck-interval': '10',
          'service.beta.kubernetes.io/aws-load-balancer-healthcheck-timeout': '5',
          'service.beta.kubernetes.io/aws-load-balancer-healthcheck-healthy-threshold': '2',
          'service.beta.kubernetes.io/aws-load-balancer-healthcheck-unhealthy-threshold': '3',
        },
      },
      spec: {
        selector: {
          app: 'sample-app',
          version: 'v1',
        },
        ports: [
          {
            port: 80,
            targetPort: 80,
            protocol: 'TCP',
          },
        ],
        type: 'LoadBalancer',
      },
    });

    // Ensure dependencies
    [appV1Deployment, appV1Service, appV2Deployment, appV2Service, basicIngress, weightedIngress, nlbService].forEach(manifest => {
      manifest.node.addDependency(namespace);
      manifest.node.addDependency(this.loadBalancerController);
    });
  }

  /**
   * Create stack outputs
   */
  private createOutputs(domainName?: string): void {
    new cdk.CfnOutput(this, 'ClusterName', {
      value: this.cluster.clusterName,
      description: 'EKS cluster name',
    });

    new cdk.CfnOutput(this, 'ClusterEndpoint', {
      value: this.cluster.clusterEndpoint,
      description: 'EKS cluster endpoint',
    });

    new cdk.CfnOutput(this, 'KubectlConfigCommand', {
      value: `aws eks update-kubeconfig --region ${cdk.Aws.REGION} --name ${this.cluster.clusterName}`,
      description: 'Command to configure kubectl',
    });

    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID',
    });

    if (this.certificate) {
      new cdk.CfnOutput(this, 'CertificateArn', {
        value: this.certificate.certificateArn,
        description: 'SSL certificate ARN',
      });
    }

    if (this.hostedZone) {
      new cdk.CfnOutput(this, 'HostedZoneId', {
        value: this.hostedZone.hostedZoneId,
        description: 'Route 53 hosted zone ID',
      });

      new cdk.CfnOutput(this, 'NameServers', {
        value: cdk.Fn.join(', ', this.hostedZone.hostedZoneNameServers || []),
        description: 'Route 53 name servers',
      });
    }

    if (this.accessLogsBucket) {
      new cdk.CfnOutput(this, 'AccessLogsBucket', {
        value: this.accessLogsBucket.bucketName,
        description: 'S3 bucket for ALB access logs',
      });
    }

    if (domainName) {
      new cdk.CfnOutput(this, 'SampleUrls', {
        value: `Basic: basic.${domainName}, Weighted: weighted.${domainName}`,
        description: 'Sample application URLs',
      });
    }

    new cdk.CfnOutput(this, 'PostDeploymentCommands', {
      value: [
        '# Verify AWS Load Balancer Controller installation:',
        'kubectl get deployment -n kube-system aws-load-balancer-controller',
        '',
        '# Check ingress resources:',
        'kubectl get ingress -n ingress-demo',
        '',
        '# Get ALB DNS names:',
        'kubectl get ingress -n ingress-demo -o jsonpath=\'{.items[*].status.loadBalancer.ingress[0].hostname}\'',
        '',
        '# Check service resources:',
        'kubectl get service -n ingress-demo',
      ].join('\n'),
      description: 'Commands to verify deployment',
    });
  }
}

// Create the CDK app
const app = new cdk.App();

// Get configuration from context or environment variables
const config = {
  vpcCidr: app.node.tryGetContext('vpcCidr') || process.env.VPC_CIDR,
  clusterVersion: app.node.tryGetContext('clusterVersion') || process.env.CLUSTER_VERSION,
  nodeInstanceType: app.node.tryGetContext('nodeInstanceType') || process.env.NODE_INSTANCE_TYPE,
  nodeGroupSize: parseInt(app.node.tryGetContext('nodeGroupSize') || process.env.NODE_GROUP_SIZE || '3'),
  domainName: app.node.tryGetContext('domainName') || process.env.DOMAIN_NAME,
  createHostedZone: app.node.tryGetContext('createHostedZone') === 'true' || process.env.CREATE_HOSTED_ZONE === 'true',
  enableAccessLogging: app.node.tryGetContext('enableAccessLogging') !== 'false' && process.env.ENABLE_ACCESS_LOGGING !== 'false',
};

// Parse cluster version if provided
let clusterVersion: eks.KubernetesVersion | undefined;
if (config.clusterVersion) {
  const versionMap: { [key: string]: eks.KubernetesVersion } = {
    '1.28': eks.KubernetesVersion.V1_28,
    '1.27': eks.KubernetesVersion.V1_27,
    '1.26': eks.KubernetesVersion.V1_26,
    '1.25': eks.KubernetesVersion.V1_25,
  };
  clusterVersion = versionMap[config.clusterVersion];
}

// Parse node instance type if provided
let nodeInstanceType: ec2.InstanceType | undefined;
if (config.nodeInstanceType) {
  const [instanceClass, instanceSize] = config.nodeInstanceType.split('.');
  if (instanceClass && instanceSize) {
    nodeInstanceType = ec2.InstanceType.of(
      ec2.InstanceClass[instanceClass.toUpperCase() as keyof typeof ec2.InstanceClass],
      ec2.InstanceSize[instanceSize.toUpperCase() as keyof typeof ec2.InstanceSize]
    );
  }
}

// Create the stack
new EksIngressControllersStack(app, 'EksIngressControllersStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'CDK stack for EKS Ingress Controllers with AWS Load Balancer Controller (uksb-1tupboc57)',
  vpcCidr: config.vpcCidr,
  clusterVersion: clusterVersion,
  nodeInstanceType: nodeInstanceType,
  nodeGroupSize: config.nodeGroupSize,
  domainName: config.domainName,
  createHostedZone: config.createHostedZone,
  enableAccessLogging: config.enableAccessLogging,
});

app.synth();