# TaskCat Configuration Template
# This template generates a complete TaskCat configuration for automated testing

project:
  name: ${project_name}
  owner: 'taskcat-demo@example.com'
  s3_bucket: ${s3_bucket_name}
  package_lambda: true
  regions: ${jsonencode(aws_regions)}

tests:
  vpc-basic-test:
    template: templates/vpc-template.yaml
    regions: ${jsonencode(aws_regions)}
    parameters:
      VpcCidr: '${vpc_cidr_blocks.basic}'
      EnvironmentName: 'TaskCatBasic'
      CreateNatGateway: 'true'
    
  vpc-no-nat-test:
    template: templates/vpc-template.yaml
    regions: ${jsonencode(aws_regions)}
    parameters:
      VpcCidr: '${vpc_cidr_blocks.no_nat}'
      EnvironmentName: 'TaskCatNoNat'
      CreateNatGateway: 'false'
    
  vpc-custom-cidr-test:
    template: templates/vpc-template.yaml
    regions: ${jsonencode(aws_regions)}
    parameters:
      VpcCidr: '${vpc_cidr_blocks.custom}'
      EnvironmentName: 'TaskCatCustom'
      CreateNatGateway: 'true'
  
  vpc-dynamic-test:
    template: templates/advanced-vpc-template.yaml
    regions: ${jsonencode(aws_regions)}
    parameters:
      VpcCidr: '${vpc_cidr_blocks.dynamic}'
      EnvironmentName: $[taskcat_project_name]
      KeyPairName: '${key_pair_name}'
      S3BucketName: $[taskcat_autobucket]
      DatabasePassword: $[taskcat_genpass_16A]

  vpc-regional-test:
    template: templates/advanced-vpc-template.yaml
    regions: ${jsonencode(aws_regions)}
    parameters:
      VpcCidr: '${vpc_cidr_blocks.regional}'
      EnvironmentName: $[taskcat_project_name]-$[taskcat_current_region]
      KeyPairName: '${key_pair_name}'
      S3BucketName: $[taskcat_autobucket]
      DatabasePassword: $[taskcat_genpass_32S]

general:
  stack_prefix: ${project_name}
  s3_bucket: ${s3_bucket_name}
  s3_bucket_region: us-east-1
  role_arn: ${execution_role_arn}
  
  # Test execution parameters
  max_test_duration: 3600  # 1 hour
  stack_timeout: 1800      # 30 minutes
  
  # Reporting and cleanup
  keep_successful: false
  keep_failed: true
  no_delete: false
  
  # Advanced options
  enable_sig_v2: true
  package_lambda: true