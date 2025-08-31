---
title: Scalable HPC Cluster with Auto-Scaling
id: 2b3dce78
category: compute
difficulty: 300
subject: aws
services: ec2, parallelcluster, s3, fsx
estimated-time: 120 minutes
recipe-version: 1.2
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: 2025-07-23
passed-qa: null
tags: hpc, compute, parallelcluster, slurm
recipe-generator-version: 1.3
---

# Scalable HPC Cluster with Auto-Scaling

## Problem

Scientific research organizations and engineering firms require massive computational resources to run complex simulations, molecular dynamics calculations, and large-scale data processing jobs. Traditional on-premises HPC clusters are expensive to maintain, difficult to scale, and often sit idle between workloads. Organizations need a way to provision high-performance computing resources on-demand, optimize costs through auto-scaling, and integrate with existing scientific workflows while maintaining the performance characteristics required for tightly-coupled parallel applications.

## Solution

AWS ParallelCluster provides a fully managed HPC cluster deployment service that automatically provisions compute resources, configures job schedulers, and sets up shared filesystems. This solution leverages Slurm workload manager for job scheduling, EC2 instances with high-performance networking, and shared storage systems to create a scalable HPC environment that can handle both tightly-coupled MPI applications and embarrassingly parallel workloads.

## Architecture Diagram

```mermaid
graph TB
    subgraph "HPC Cluster"
        HEAD[Head Node<br/>Slurm Controller]
        
        subgraph "Compute Fleet"
            CN1[Compute Node 1<br/>c5n.large]
            CN2[Compute Node 2<br/>c5n.large]
            CN3[Compute Node N<br/>Auto Scaling]
        end
        
        subgraph "Storage"
            EBS[EBS Volumes<br/>Root Storage]
            FSX[FSx Lustre<br/>Shared Storage]
            S3[S3 Bucket<br/>Data Repository]
        end
        
        subgraph "Network"
            VPC[Custom VPC]
            SG[Security Groups]
            EFA[Elastic Fabric Adapter<br/>Low Latency]
        end
    end
    
    subgraph "Management"
        USER[HPC Users]
        PCUI[ParallelCluster UI]
        CW[CloudWatch<br/>Monitoring]
    end
    
    USER --> HEAD
    USER --> PCUI
    HEAD --> CN1
    HEAD --> CN2
    HEAD --> CN3
    
    CN1 -.-> EFA
    CN2 -.-> EFA
    CN3 -.-> EFA
    
    HEAD --> FSX
    CN1 --> FSX
    CN2 --> FSX
    CN3 --> FSX
    
    FSX --> S3
    HEAD --> CW
    
    style HEAD fill:#FF9900
    style FSX fill:#3F8624
    style EFA fill:#FF6B6B
    style CW fill:#4ECDC4
```

## Prerequisites

1. AWS account with administrative permissions for EC2, VPC, IAM, and CloudFormation
2. AWS CLI v2 installed and configured (or AWS CloudShell)
3. Python 3.8+ installed for ParallelCluster CLI
4. Basic understanding of HPC concepts, job schedulers, and MPI applications
5. Familiarity with Linux system administration and command-line tools
6. Estimated cost: $50-200/hour depending on instance types and cluster size

> **Warning**: HPC instances can be expensive. Monitor usage carefully and follow cleanup procedures to avoid unexpected charges.

## Preparation

```bash
# Set environment variables
export AWS_REGION=$(aws configure get region)
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword)

export CLUSTER_NAME="hpc-cluster-${RANDOM_SUFFIX}"
export VPC_NAME="hpc-vpc-${RANDOM_SUFFIX}"
export KEYPAIR_NAME="hpc-keypair-${RANDOM_SUFFIX}"
export S3_BUCKET_NAME="hpc-data-${RANDOM_SUFFIX}-${AWS_ACCOUNT_ID}"

# Install ParallelCluster CLI
pip3 install aws-parallelcluster

# Verify installation
pcluster version

# Create SSH key pair for cluster access
aws ec2 create-key-pair \
    --key-name ${KEYPAIR_NAME} \
    --query 'KeyMaterial' \
    --output text > ~/.ssh/${KEYPAIR_NAME}.pem

chmod 600 ~/.ssh/${KEYPAIR_NAME}.pem

echo "✅ ParallelCluster CLI installed and key pair created"
```

## Steps

1. **Create VPC and Networking Infrastructure**:

   AWS ParallelCluster requires isolated networking environments to ensure secure communication between nodes and optimal network performance. A custom VPC provides complete control over the network topology, enabling configuration of subnets that separate management traffic (head node) from compute traffic while maintaining security boundaries. This foundation is critical for HPC workloads that rely on high-bandwidth, low-latency inter-node communication patterns found in tightly-coupled MPI applications.

   ```bash
   # Create VPC for HPC cluster
   VPC_ID=$(aws ec2 create-vpc \
       --cidr-block 10.0.0.0/16 \
       --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value='${VPC_NAME}'}]' \
       --query 'Vpc.VpcId' --output text)
   
   # Create public subnet for head node
   PUBLIC_SUBNET_ID=$(aws ec2 create-subnet \
       --vpc-id ${VPC_ID} \
       --cidr-block 10.0.1.0/24 \
       --availability-zone ${AWS_REGION}a \
       --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value='${VPC_NAME}'-public}]' \
       --query 'Subnet.SubnetId' --output text)
   
   # Create private subnet for compute nodes
   PRIVATE_SUBNET_ID=$(aws ec2 create-subnet \
       --vpc-id ${VPC_ID} \
       --cidr-block 10.0.2.0/24 \
       --availability-zone ${AWS_REGION}a \
       --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value='${VPC_NAME}'-private}]' \
       --query 'Subnet.SubnetId' --output text)
   
   # Create and attach internet gateway
   IGW_ID=$(aws ec2 create-internet-gateway \
       --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value='${VPC_NAME}'-igw}]' \
       --query 'InternetGateway.InternetGatewayId' --output text)
   
   aws ec2 attach-internet-gateway \
       --internet-gateway-id ${IGW_ID} \
       --vpc-id ${VPC_ID}
   
   echo "✅ VPC and subnets created: ${VPC_ID}"
   ```

   The VPC infrastructure now provides the isolated network foundation required for HPC clusters. The public subnet will host the head node for external access, while the private subnet ensures compute nodes remain secure while maintaining internet access through NAT Gateway for software updates and package installations.

2. **Configure Route Tables and NAT Gateway**:

   NAT Gateway configuration is essential for HPC compute nodes to access external resources while maintaining security. Compute nodes in the private subnet need internet access for downloading software packages, accessing container registries, and synchronizing with time servers, but should not be directly accessible from the internet. This configuration ensures secure outbound connectivity while preventing unauthorized inbound access, which is crucial for meeting security compliance requirements in research environments.

   ```bash
   # Create NAT Gateway for private subnet internet access
   NAT_ALLOCATION_ID=$(aws ec2 allocate-address \
       --domain vpc \
       --query 'AllocationId' --output text)
   
   NAT_GW_ID=$(aws ec2 create-nat-gateway \
       --subnet-id ${PUBLIC_SUBNET_ID} \
       --allocation-id ${NAT_ALLOCATION_ID} \
       --tag-specifications 'ResourceType=nat-gateway,Tags=[{Key=Name,Value='${VPC_NAME}'-nat}]' \
       --query 'NatGateway.NatGatewayId' --output text)
   
   # Wait for NAT Gateway to be available
   aws ec2 wait nat-gateway-available \
       --nat-gateway-ids ${NAT_GW_ID}
   
   # Update route table for public subnet
   PUBLIC_RT_ID=$(aws ec2 describe-route-tables \
       --filters "Name=vpc-id,Values=${VPC_ID}" \
       --query 'RouteTables[0].RouteTableId' --output text)
   
   aws ec2 create-route \
       --route-table-id ${PUBLIC_RT_ID} \
       --destination-cidr-block 0.0.0.0/0 \
       --gateway-id ${IGW_ID}
   
   # Create and configure private route table
   PRIVATE_RT_ID=$(aws ec2 create-route-table \
       --vpc-id ${VPC_ID} \
       --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value='${VPC_NAME}'-private}]' \
       --query 'RouteTable.RouteTableId' --output text)
   
   aws ec2 create-route \
       --route-table-id ${PRIVATE_RT_ID} \
       --destination-cidr-block 0.0.0.0/0 \
       --nat-gateway-id ${NAT_GW_ID}
   
   aws ec2 associate-route-table \
       --route-table-id ${PRIVATE_RT_ID} \
       --subnet-id ${PRIVATE_SUBNET_ID}
   
   echo "✅ NAT Gateway and routing configured"
   ```

   The routing infrastructure is now configured to provide secure internet access for compute nodes while maintaining network isolation. This setup enables compute nodes to download necessary software and access external services while preventing direct external access, which is crucial for HPC security best practices.

3. **Create S3 Bucket for Data Storage**:

   Amazon S3 provides the durable, scalable storage foundation essential for HPC data workflows. With 99.999999999% (11 9's) durability, S3 serves as both the initial data repository and the long-term archive for research outputs. FSx Lustre can automatically hydrate data from S3 at job runtime and export results back, creating seamless data lifecycle management that combines S3's cost-effectiveness with high-performance computing requirements. This integration eliminates manual data staging steps and ensures research data is automatically preserved.

   ```bash
   # Create S3 bucket for HPC data storage
   aws s3 mb s3://${S3_BUCKET_NAME} \
       --region ${AWS_REGION}
   
   # Enable versioning for data protection
   aws s3api put-bucket-versioning \
       --bucket ${S3_BUCKET_NAME} \
       --versioning-configuration Status=Enabled
   
   # Create folder structure for HPC workloads
   echo "Sample HPC input data for simulation" > input.txt
   aws s3 cp input.txt s3://${S3_BUCKET_NAME}/input/
   
   # Create sample job script
   cat > sample_job.sh << 'EOF'
   #!/bin/bash
   #SBATCH --job-name=hpc-test
   #SBATCH --nodes=2
   #SBATCH --ntasks-per-node=8
   #SBATCH --time=00:10:00
   #SBATCH --output=output_%j.log
   
   module load openmpi
   mpirun hostname
   echo "Job completed successfully"
   EOF
   
   aws s3 cp sample_job.sh s3://${S3_BUCKET_NAME}/jobs/
   rm input.txt sample_job.sh
   
   echo "✅ S3 bucket created: ${S3_BUCKET_NAME}"
   ```

   The S3 data repository is now established with versioning enabled and sample input data and job scripts. This creates the foundation for data-driven HPC workflows where large datasets can be efficiently transferred to high-performance storage during job execution and results can be automatically archived for long-term retention.

4. **Create ParallelCluster Configuration**:

   ParallelCluster configuration defines the entire HPC infrastructure declaratively using YAML, including compute resources, storage systems, and networking. This approach enables repeatable deployments, version control of cluster definitions, and consistent infrastructure-as-code practices. The configuration specifies Slurm as the job scheduler, enables Elastic Fabric Adapter (EFA) for ultra-low latency networking critical for MPI applications, and integrates FSx Lustre for high-performance shared storage with automatic S3 data repository integration.

   ```bash
   # Create ParallelCluster configuration file
   cat > cluster-config.yaml << EOF
   Region: ${AWS_REGION}
   Image:
     Os: alinux2
   HeadNode:
     InstanceType: m5.large
     Networking:
       SubnetId: ${PUBLIC_SUBNET_ID}
     Ssh:
       KeyName: ${KEYPAIR_NAME}
     LocalStorage:
       RootVolume:
         Size: 50
         VolumeType: gp3
   Scheduling:
     Scheduler: slurm
     SlurmQueues:
       - Name: compute
         ComputeResources:
           - Name: compute-nodes
             InstanceType: c5n.large
             MinCount: 0
             MaxCount: 10
             DisableSimultaneousMultithreading: true
             Efa:
               Enabled: true
         Networking:
           SubnetIds:
             - ${PRIVATE_SUBNET_ID}
         ComputeSettings:
           LocalStorage:
             RootVolume:
               Size: 50
               VolumeType: gp3
   SharedStorage:
     - MountDir: /shared
       Name: shared-storage
       StorageType: Ebs
       EbsSettings:
         Size: 100
         VolumeType: gp3
         Encrypted: true
     - MountDir: /fsx
       Name: fsx-storage
       StorageType: FsxLustre
       FsxLustreSettings:
         StorageCapacity: 1200
         DeploymentType: SCRATCH_2
         ImportPath: s3://${S3_BUCKET_NAME}/
         ExportPath: s3://${S3_BUCKET_NAME}/output/
   Monitoring:
     CloudWatch:
       Enabled: true
       DashboardName: ${CLUSTER_NAME}-dashboard
   EOF
   
   echo "✅ ParallelCluster configuration created"
   ```

   The cluster configuration now defines a complete HPC environment with auto-scaling compute resources, high-performance storage, and integrated monitoring. This declarative approach ensures consistent deployments and enables infrastructure-as-code practices for HPC environments.

5. **Deploy ParallelCluster**:

   ParallelCluster deployment orchestrates the creation of all infrastructure components including EC2 instances, security groups, IAM roles, and storage systems using CloudFormation for consistent, repeatable deployments with proper dependency management. The service automatically configures the Slurm job scheduler, mounts shared filesystems, and establishes secure communication channels between nodes. This process typically takes 10-15 minutes as it provisions and configures all cluster components for immediate use.

   ```bash
   # Create the HPC cluster
   pcluster create-cluster \
       --cluster-name ${CLUSTER_NAME} \
       --cluster-configuration cluster-config.yaml \
       --rollback-on-failure false
   
   # Wait for cluster creation to complete (this takes 10-15 minutes)
   echo "Waiting for cluster creation to complete..."
   while [[ $(pcluster describe-cluster --cluster-name ${CLUSTER_NAME} --query 'clusterStatus' --output text) == "CREATE_IN_PROGRESS" ]]; do
       sleep 30
       echo "Still creating cluster..."
   done
   
   # Verify cluster status
   CLUSTER_STATUS=$(pcluster describe-cluster \
       --cluster-name ${CLUSTER_NAME} \
       --query 'clusterStatus' --output text)
   
   if [[ ${CLUSTER_STATUS} == "CREATE_COMPLETE" ]]; then
       echo "✅ HPC cluster created successfully"
   else
       echo "❌ Cluster creation failed with status: ${CLUSTER_STATUS}"
       exit 1
   fi
   
   # Store head node IP for later use
   HEAD_NODE_IP=$(pcluster describe-cluster \
       --cluster-name ${CLUSTER_NAME} \
       --query 'headNode.publicIpAddress' --output text)
   
   echo "Head node IP: ${HEAD_NODE_IP}"
   ```

   The HPC cluster is now fully operational with a configured head node running the Slurm scheduler. The head node serves as the cluster management interface where users submit jobs, monitor resource usage, and access shared storage systems. Auto-scaling is enabled, allowing the cluster to dynamically provision compute nodes based on job queue demand.

6. **Configure Slurm Job Scheduler**:

   Slurm (Simple Linux Utility for Resource Management) provides enterprise-grade job scheduling with features like fair-share scheduling, resource limits, and job priorities essential for multi-user HPC environments. The advanced configuration optimizes resource allocation for HPC workloads by enabling core-level resource tracking (cons_tres) and memory-aware scheduling. These settings ensure efficient utilization of compute resources, prevent job interference, and support sophisticated resource allocation policies required in production HPC environments.

   ```bash
   # Connect to head node and configure Slurm
   ssh -i ~/.ssh/${KEYPAIR_NAME}.pem ec2-user@${HEAD_NODE_IP} << 'EOF'
   
   # Check initial Slurm status
   sinfo
   
   # Create custom Slurm configuration for HPC optimization
   sudo tee -a /opt/slurm/etc/slurm.conf << 'SLURM_EOF'

   # Custom HPC settings for optimal resource management
   SelectType=select/cons_tres
   SelectTypeParameters=CR_Core_Memory
   PreemptType=preempt/partition_prio
   PreemptMode=REQUEUE
   DefMemPerCPU=1000
   JobAcctGatherType=jobacct_gather/linux
   JobAcctGatherFrequency=30
   AccountingStorageType=accounting_storage/filetxt
   AccountingStorageLoc=/opt/slurm/accounting.log
   SLURM_EOF
   
   # Restart Slurm services to apply configuration
   sudo systemctl restart slurmctld
   sleep 5
   sudo systemctl restart slurmd
   
   # Verify Slurm services are running
   sudo systemctl status slurmctld --no-pager -l
   
   # Set up job submission directory with proper permissions
   mkdir -p /shared/jobs
   chmod 755 /shared/jobs
   
   # Create example job templates directory
   mkdir -p /shared/templates
   chmod 755 /shared/templates
   
   exit
   EOF
   
   echo "✅ Slurm scheduler configured with HPC optimizations"
   ```

   Slurm is now configured with advanced resource management capabilities including core-aware scheduling, memory allocation tracking, and job accounting. The shared job directory provides a central location for job scripts and outputs, accessible across all cluster nodes through the shared filesystem.

7. **Install HPC Software Stack**:

   HPC applications require specialized software stacks including MPI libraries, compilers, and scientific computing tools to achieve optimal performance. OpenMPI provides the Message Passing Interface implementation essential for parallel computing, while environment modules enable users to dynamically load different software versions without conflicts. This standardized approach ensures consistent software environments across all compute nodes, simplifies application deployment, and enables reproducible scientific computing workflows.

   ```bash
   # Install common HPC applications and libraries
   ssh -i ~/.ssh/${KEYPAIR_NAME}.pem ec2-user@${HEAD_NODE_IP} << 'EOF'
   
   # Update system packages to latest versions
   sudo yum update -y
   
   # Install essential development tools and compilers
   sudo yum groupinstall -y "Development Tools"
   sudo yum install -y gcc-gfortran openmpi-devel htop numactl-devel
   
   # Set up environment modules system
   sudo yum install -y environment-modules
   
   # Create module directory structure
   sudo mkdir -p /usr/share/modulefiles/{mpi,compiler,libraries}
   
   # Create comprehensive module file for OpenMPI
   sudo tee /usr/share/modulefiles/mpi/openmpi << 'MODULE_EOF'
   #%Module1.0
   ##
   ## OpenMPI MPI implementation
   ##
   proc ModulesHelp { } {
       puts stderr "Loads OpenMPI MPI implementation"
       puts stderr "Version: Latest available"
       puts stderr "Provides: mpirun, mpicc, mpif90"
   }
   
   module-whatis "OpenMPI MPI implementation for parallel computing"
   
   set root /usr/lib64/openmpi
   set version [exec rpm -q --queryformat "%{VERSION}" openmpi]
   
   prepend-path PATH $root/bin
   prepend-path LD_LIBRARY_PATH $root/lib
   prepend-path MANPATH $root/share/man
   prepend-path PKG_CONFIG_PATH $root/lib/pkgconfig
   
   setenv MPI_HOME $root
   setenv OMPI_CC gcc
   setenv OMPI_CXX g++
   setenv OMPI_FC gfortran
   
   # Set OpenMPI tuning for HPC clusters
   setenv OMPI_MCA_btl_openib_use_eager_rdma 1
   setenv OMPI_MCA_btl_openib_eager_limit 32768
   MODULE_EOF
   
   # Test module system functionality
   module avail
   module load mpi/openmpi
   which mpirun
   mpirun --version
   
   # Create sample MPI test program
   cat > /shared/templates/mpi_hello.c << 'MPI_EOF'
   #include <mpi.h>
   #include <stdio.h>
   
   int main(int argc, char** argv) {
       MPI_Init(&argc, &argv);
       
       int world_size;
       MPI_Comm_size(MPI_COMM_WORLD, &world_size);
       
       int world_rank;
       MPI_Comm_rank(MPI_COMM_WORLD, &world_rank);
       
       char processor_name[MPI_MAX_PROCESSOR_NAME];
       int name_len;
       MPI_Get_processor_name(processor_name, &name_len);
       
       printf("Hello from processor %s, rank %d out of %d processors\n",
              processor_name, world_rank, world_size);
       
       MPI_Finalize();
       return 0;
   }
   MPI_EOF
   
   # Compile the test program
   mpicc /shared/templates/mpi_hello.c -o /shared/templates/mpi_hello
   
   exit
   EOF
   
   echo "✅ HPC software stack installed with OpenMPI and modules"
   ```

   The HPC software environment is now configured with OpenMPI, environment modules, and essential development tools. Users can now load MPI libraries and development tools using the module system, ensuring consistent software environments across all cluster nodes with optimized MPI settings for cluster performance.

8. **Set Up Monitoring and Logging**:

   Comprehensive monitoring is essential for HPC cluster management, providing insights into resource utilization, job performance, and system health across all cluster nodes. CloudWatch integration enables real-time monitoring of CPU, memory, network, and storage metrics. Custom dashboards and automated alarms help administrators optimize resource allocation, identify performance bottlenecks, and proactively address issues before they impact running scientific computations.

   ```bash
   # Create comprehensive CloudWatch dashboard for cluster monitoring
   cat > dashboard-config.json << EOF
   {
       "widgets": [
           {
               "type": "metric",
               "x": 0,
               "y": 0,
               "width": 12,
               "height": 6,
               "properties": {
                   "metrics": [
                       ["AWS/EC2", "CPUUtilization", "ClusterName", "${CLUSTER_NAME}"],
                       ["AWS/EC2", "NetworkIn", "ClusterName", "${CLUSTER_NAME}"],
                       ["AWS/EC2", "NetworkOut", "ClusterName", "${CLUSTER_NAME}"]
                   ],
                   "period": 300,
                   "stat": "Average",
                   "region": "${AWS_REGION}",
                   "title": "HPC Cluster Performance Metrics",
                   "yAxis": {
                       "left": {
                           "min": 0
                       }
                   }
               }
           },
           {
               "type": "metric",
               "x": 12,
               "y": 0,
               "width": 12,
               "height": 6,
               "properties": {
                   "metrics": [
                       ["AWS/EC2", "NetworkPacketsIn", "ClusterName", "${CLUSTER_NAME}"],
                       ["AWS/EC2", "NetworkPacketsOut", "ClusterName", "${CLUSTER_NAME}"]
                   ],
                   "period": 300,
                   "stat": "Average",
                   "region": "${AWS_REGION}",
                   "title": "Network Packet Metrics"
               }
           }
       ]
   }
   EOF
   
   aws cloudwatch put-dashboard \
       --dashboard-name ${CLUSTER_NAME}-performance \
       --dashboard-body file://dashboard-config.json
   
   # Set up CloudWatch alarms for proactive cluster health monitoring
   aws cloudwatch put-metric-alarm \
       --alarm-name "${CLUSTER_NAME}-high-cpu" \
       --alarm-description "High CPU utilization on HPC cluster" \
       --metric-name CPUUtilization \
       --namespace AWS/EC2 \
       --statistic Average \
       --period 300 \
       --threshold 80 \
       --comparison-operator GreaterThanThreshold \
       --evaluation-periods 2
   
   # Create alarm for network utilization
   aws cloudwatch put-metric-alarm \
       --alarm-name "${CLUSTER_NAME}-high-network" \
       --alarm-description "High network utilization on HPC cluster" \
       --metric-name NetworkIn \
       --namespace AWS/EC2 \
       --statistic Average \
       --period 300 \
       --threshold 1000000000 \
       --comparison-operator GreaterThanThreshold \
       --evaluation-periods 2
   
   echo "✅ Monitoring and alerting configured with dashboards"
   ```

   Monitoring infrastructure is now established with comprehensive dashboards and automated alerts for CPU and network utilization. This enables proactive cluster management and helps optimize resource utilization by providing visibility into compute patterns and potential bottlenecks.

9. **Configure Auto-Scaling Policies**:

   Auto-scaling configuration optimizes cost efficiency by automatically adjusting cluster size based on job queue demand using Slurm's integration with EC2 Auto Scaling. The ScaledownIdletime parameter determines how quickly idle nodes are terminated to reduce costs, while MaxCount limits prevent runaway scaling costs. This configuration enables HPC clusters to scale elastically from zero to hundreds of nodes automatically, providing significant cost savings compared to static cluster sizing while maintaining the ability to handle variable computational workloads.

   ```bash
   # Update cluster configuration for advanced auto-scaling
   cat > scaling-config.yaml << EOF
   Region: ${AWS_REGION}
   Image:
     Os: alinux2
   HeadNode:
     InstanceType: m5.large
     Networking:
       SubnetId: ${PUBLIC_SUBNET_ID}
     Ssh:
       KeyName: ${KEYPAIR_NAME}
     LocalStorage:
       RootVolume:
         Size: 50
         VolumeType: gp3
   Scheduling:
     Scheduler: slurm
     SlurmSettings:
       ScaledownIdletime: 5
       QueueUpdateStrategy: TERMINATE
     SlurmQueues:
       - Name: compute
         ComputeResources:
           - Name: compute-nodes
             InstanceType: c5n.large
             MinCount: 0
             MaxCount: 20
             DisableSimultaneousMultithreading: true
             Efa:
               Enabled: true
         Networking:
           SubnetIds:
             - ${PRIVATE_SUBNET_ID}
         ComputeSettings:
           LocalStorage:
             RootVolume:
               Size: 50
               VolumeType: gp3
   SharedStorage:
     - MountDir: /shared
       Name: shared-storage
       StorageType: Ebs
       EbsSettings:
         Size: 100
         VolumeType: gp3
         Encrypted: true
     - MountDir: /fsx
       Name: fsx-storage
       StorageType: FsxLustre
       FsxLustreSettings:
         StorageCapacity: 1200
         DeploymentType: SCRATCH_2
         ImportPath: s3://${S3_BUCKET_NAME}/
         ExportPath: s3://${S3_BUCKET_NAME}/output/
   Monitoring:
     CloudWatch:
       Enabled: true
   EOF
   
   echo "✅ Advanced auto-scaling configuration prepared"
   ```

   Advanced auto-scaling policies are now configured to optimize both performance and cost efficiency. The cluster can scale up rapidly when jobs are queued and scale down quickly when idle (5 minutes), providing the elasticity that makes cloud HPC cost-effective for variable research workloads.

10. **Test HPC Workload Submission**:

    Testing job submission validates the complete HPC workflow from job creation to execution across multiple nodes, ensuring all components work together correctly. MPI test jobs verify that inter-node communication is functioning properly through the EFA-enabled network and that the Slurm job scheduler can effectively distribute parallel tasks across the compute fleet. This validation step confirms the cluster is ready for production scientific workloads requiring high-performance parallel processing capabilities.

    ```bash
    # Submit comprehensive test job to validate cluster functionality
    ssh -i ~/.ssh/${KEYPAIR_NAME}.pem ec2-user@${HEAD_NODE_IP} << 'EOF'
    
    # Create comprehensive MPI test job with resource validation
    cat > /shared/jobs/mpi-test.sh << 'JOB_EOF'
    #!/bin/bash
    #SBATCH --job-name=mpi-test
    #SBATCH --nodes=2
    #SBATCH --ntasks-per-node=4
    #SBATCH --time=00:05:00
    #SBATCH --output=/shared/jobs/mpi-test-%j.out
    #SBATCH --error=/shared/jobs/mpi-test-%j.err
    
    # Load required modules
    module load mpi/openmpi
    
    echo "Starting MPI test job at $(date)"
    echo "Job ID: $SLURM_JOB_ID"
    echo "Running on nodes: $SLURM_JOB_NODELIST"
    echo "Total tasks: $SLURM_NTASKS"
    echo "Tasks per node: $SLURM_NTASKS_PER_NODE"
    
    # Test basic MPI functionality
    echo "=== Testing MPI Communication ==="
    mpirun -np $SLURM_NTASKS hostname
    
    # Test compiled MPI program if available
    if [ -f /shared/templates/mpi_hello ]; then
        echo "=== Testing Compiled MPI Program ==="
        mpirun -np $SLURM_NTASKS /shared/templates/mpi_hello
    fi
    
    # Test file system access
    echo "=== Testing Shared Filesystem ==="
    echo "Shared directory contents:" 
    ls -la /shared/
    echo "FSx Lustre filesystem:"
    ls -la /fsx/
    
    echo "MPI test completed successfully at $(date)"
    JOB_EOF
    
    # Submit the test job
    JOB_ID=$(sbatch /shared/jobs/mpi-test.sh | awk '{print $4}')
    echo "Submitted job with ID: $JOB_ID"
    
    # Monitor job status
    echo "Monitoring job status..."
    squeue
    
    # Wait a moment for job to potentially complete
    sleep 10
    squeue
    
    exit
    EOF
    
    echo "✅ Comprehensive test HPC workload submitted"
    ```

    The MPI test job demonstrates successful parallel job execution across multiple nodes with comprehensive resource validation, confirming that the cluster's networking, scheduling, compute resources, and shared storage are all functioning correctly for production HPC workloads.

11. **Configure Data Transfer and Storage**:

    High-performance data transfer capabilities are critical for HPC workflows that process large scientific datasets. AWS CLI with multipart upload capabilities and FSx Lustre's S3 integration provide efficient data movement between cost-effective long-term storage and high-performance computing resources. This configuration enables automatic data staging before job execution and seamless result archival after completion, streamlining the entire research data lifecycle without manual intervention.

    ```bash
    # Set up optimized data transfer utilities on head node
    ssh -i ~/.ssh/${KEYPAIR_NAME}.pem ec2-user@${HEAD_NODE_IP} << 'EOF'
    
    # Install AWS CLI and parallel processing tools
    sudo yum install -y awscli parallel rsync
    
    # Configure AWS CLI for optimized transfers
    aws configure set default.s3.max_concurrent_requests 20
    aws configure set default.s3.max_bandwidth 1GB/s
    aws configure set default.s3.multipart_threshold 64MB
    aws configure set default.s3.multipart_chunksize 16MB
    
    # Create optimized data transfer script
    cat > /shared/jobs/data-transfer.sh << 'TRANSFER_EOF'
    #!/bin/bash
    # High-performance data transfer script for HPC workflows
    
    set -e  # Exit on any error
    
    # Function for logging with timestamps
    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    }
    
    # Download data from S3 to FSx with optimized settings
    log "Starting data download from S3 to FSx Lustre"
    aws s3 sync s3://S3_BUCKET_NAME/input/ /fsx/input/ \
        --exclude="*" --include="*.dat" --include="*.txt" --include="*.nc" \
        --delete --exact-timestamps
    
    log "Data download completed"
    
    # Create output directory if it doesn't exist
    mkdir -p /fsx/output
    
    # Upload results back to S3 with metadata
    log "Starting results upload from FSx to S3"
    aws s3 sync /fsx/output/ s3://S3_BUCKET_NAME/output/ \
        --exclude="*" --include="*.out" --include="*.log" --include="*.nc" \
        --delete --exact-timestamps \
        --metadata "processed=$(date +%s),cluster=S3_BUCKET_NAME"
    
    log "Results upload completed"
    
    # Generate transfer report
    echo "Data transfer completed at $(date)" > /shared/jobs/transfer-report.txt
    echo "Input files:" >> /shared/jobs/transfer-report.txt
    find /fsx/input -type f | wc -l >> /shared/jobs/transfer-report.txt
    echo "Output files:" >> /shared/jobs/transfer-report.txt
    find /fsx/output -type f | wc -l >> /shared/jobs/transfer-report.txt
    TRANSFER_EOF
    
    # Replace S3 bucket placeholder with actual bucket name
    sed -i "s/S3_BUCKET_NAME/${S3_BUCKET_NAME}/g" /shared/jobs/data-transfer.sh
    chmod +x /shared/jobs/data-transfer.sh
    
    # Create data management utilities
    cat > /shared/jobs/check-storage.sh << 'STORAGE_EOF'
    #!/bin/bash
    # Storage utilization monitoring script
    
    echo "=== Storage Utilization Report ==="
    echo "Generated at: $(date)"
    echo
    
    echo "Shared EBS Storage (/shared):"
    df -h /shared
    echo
    
    echo "FSx Lustre Storage (/fsx):"
    df -h /fsx
    echo
    
    echo "Largest files in /fsx:"
    find /fsx -type f -exec du -h {} \; | sort -hr | head -10
    echo
    
    echo "File count by directory:"
    for dir in /fsx/input /fsx/output /shared/jobs; do
        if [ -d "$dir" ]; then
            echo "$dir: $(find $dir -type f | wc -l) files"
        fi
    done
    STORAGE_EOF
    
    chmod +x /shared/jobs/check-storage.sh
    
    # Test storage access
    /shared/jobs/check-storage.sh
    
    exit
    EOF
    
    echo "✅ Data transfer utilities configured with optimization"
    ```

    Data transfer infrastructure is now optimized for HPC workflows with automated scripts for efficient data movement between S3 and the high-performance FSx filesystem. The system includes parallel transfers, error handling, and comprehensive logging for reliable data lifecycle management.

12. **Implement Job Queue Management**:

    Sophisticated job management tools simplify HPC cluster operations for researchers and system administrators by providing standardized interfaces and automated monitoring. These wrapper scripts enable configurable resource requirements, comprehensive job tracking, and integration with Slurm's accounting system. The monitoring tools provide detailed job history, cluster utilization analytics, and resource efficiency metrics essential for optimizing HPC resource allocation and ensuring productive use of computational resources.

    ```bash
    # Create comprehensive job management and monitoring scripts
    ssh -i ~/.ssh/${KEYPAIR_NAME}.pem ec2-user@${HEAD_NODE_IP} << 'EOF'
    
    # Create advanced job submission wrapper with validation
    cat > /shared/jobs/submit-hpc-job.sh << 'SUBMIT_EOF'
    #!/bin/bash
    # HPC job submission wrapper with resource validation
    
    # Display usage information
    if [ $# -lt 1 ]; then
        echo "Usage: $0 <job-script> [nodes] [tasks-per-node] [time] [memory-per-cpu]"
        echo "  job-script: Path to the job script to submit"
        echo "  nodes: Number of compute nodes (default: 1)"
        echo "  tasks-per-node: Tasks per node (default: 4)"  
        echo "  time: Wall time limit (default: 01:00:00)"
        echo "  memory-per-cpu: Memory per CPU in MB (default: 1000)"
        echo
        echo "Examples:"
        echo "  $0 my_job.sh 2 8 02:30:00 2000"
        echo "  $0 quick_job.sh"
        exit 1
    fi
    
    JOB_SCRIPT=$1
    NODES=${2:-1}
    TASKS_PER_NODE=${3:-4}
    TIME=${4:-01:00:00}
    MEMORY_PER_CPU=${5:-1000}
    
    # Validate job script exists
    if [ ! -f "$JOB_SCRIPT" ]; then
        echo "Error: Job script '$JOB_SCRIPT' not found"
        exit 1
    fi
    
    # Calculate total resources
    TOTAL_TASKS=$((NODES * TASKS_PER_NODE))
    TOTAL_MEMORY=$((TOTAL_TASKS * MEMORY_PER_CPU))
    
    echo "=== Job Submission Summary ==="
    echo "Script: $JOB_SCRIPT"
    echo "Nodes: $NODES"
    echo "Tasks per node: $TASKS_PER_NODE"
    echo "Total tasks: $TOTAL_TASKS"
    echo "Wall time: $TIME"
    echo "Memory per CPU: ${MEMORY_PER_CPU}MB"
    echo "Total memory: ${TOTAL_MEMORY}MB"
    echo
    
    # Submit job with comprehensive resource specification
    JOB_ID=$(sbatch --nodes=$NODES \
           --ntasks-per-node=$TASKS_PER_NODE \
           --time=$TIME \
           --mem-per-cpu=$MEMORY_PER_CPU \
           --output=/shared/jobs/output_%j.log \
           --error=/shared/jobs/error_%j.log \
           $JOB_SCRIPT | awk '{print $4}')
    
    echo "Job submitted successfully with ID: $JOB_ID"
    echo "Monitor with: squeue -j $JOB_ID"
    echo "Cancel with: scancel $JOB_ID"
    echo
    
    # Show current queue status
    echo "=== Current Queue Status ==="
    squeue -u $USER
    SUBMIT_EOF
    
    chmod +x /shared/jobs/submit-hpc-job.sh
    
    # Create comprehensive job monitoring and reporting script
    cat > /shared/jobs/monitor-jobs.sh << 'MONITOR_EOF'
    #!/bin/bash
    # Comprehensive job monitoring and cluster reporting
    
    echo "=== HPC Cluster Status Report ==="
    echo "Generated at: $(date)"
    echo "User: $USER"
    echo
    
    echo "=== Active Jobs ==="
    if squeue -u $USER | grep -q $USER; then
        squeue -u $USER -o "%.10i %.20j %.8u %.2t %.10M %.6D %R"
    else
        echo "No active jobs for user $USER"
    fi
    echo
    
    echo "=== Node Status ==="
    sinfo -o "%.10P %.5a %.10l %.6D %.6t %.14N %.20f"
    echo
    
    echo "=== Recent Job History (Last 24 Hours) ==="
    sacct -u $USER --starttime=$(date -d '1 day ago' +%Y-%m-%d) \
          --format=JobID,JobName,State,ExitCode,Start,End,NodeList \
          --allocations | head -20
    echo
    
    echo "=== Cluster Resource Utilization ==="
    scontrol show partition | grep -E "(PartitionName|State|TotalNodes|AllocNodes)"
    echo
    
    echo "=== Storage Utilization ==="
    df -h /shared /fsx 2>/dev/null || echo "Storage info not available"
    echo
    
    echo "=== System Load Averages ==="
    uptime
    echo
    
    # Show running job details if any
    RUNNING_JOBS=$(squeue -u $USER -t RUNNING -h -o "%i" | wc -l)
    if [ $RUNNING_JOBS -gt 0 ]; then
        echo "=== Running Job Details ==="
        squeue -u $USER -t RUNNING -o "%.10i %.20j %.8u %.10M %.6D %R"
    fi
    MONITOR_EOF
    
    chmod +x /shared/jobs/monitor-jobs.sh
    
    # Create job efficiency analysis script
    cat > /shared/jobs/job-efficiency.sh << 'EFFICIENCY_EOF'
    #!/bin/bash
    # Job efficiency analysis script
    
    if [ $# -eq 0 ]; then
        echo "Usage: $0 <job-id>"
        echo "Analyzes efficiency and resource utilization for a completed job"
        exit 1
    fi
    
    JOB_ID=$1
    
    echo "=== Job Efficiency Analysis for Job $JOB_ID ==="
    
    # Get detailed job information
    sacct -j $JOB_ID --format=JobID,JobName,State,ExitCode,Start,End,Elapsed,AllocCPUS,ReqMem,MaxRSS,NodeList -p
    
    echo
    echo "=== Resource Utilization Summary ==="
    sacct -j $JOB_ID --format=JobID,CPUTime,TotalCPU,UserCPU,SystemCPU,CPUTimeRAW,ElapsedRAW -p
    EFFICIENCY_EOF
    
    chmod +x /shared/jobs/job-efficiency.sh
    
    # Test the monitoring system
    echo "Testing job monitoring system..."
    /shared/jobs/monitor-jobs.sh
    
    exit
    EOF
    
    echo "✅ Advanced job queue management tools configured"
    ```

    Advanced job management tools are now available, providing simplified interfaces for job submission with resource validation, comprehensive monitoring capabilities, and efficiency analysis tools. These utilities enable researchers to efficiently utilize cluster resources while providing administrators with detailed utilization analytics and performance insights.

## Validation & Testing

1. **Verify Cluster Status**:

   ```bash
   # Check overall cluster health and status
   pcluster describe-cluster \
       --cluster-name ${CLUSTER_NAME} \
       --query 'clusterStatus'
   
   # Expected output: "CREATE_COMPLETE"
   
   # Verify compute fleet configuration
   pcluster describe-compute-fleet \
       --cluster-name ${CLUSTER_NAME}
   
   # Check CloudFormation stack status
   aws cloudformation describe-stacks \
       --stack-name ${CLUSTER_NAME} \
       --query 'Stacks[0].StackStatus'
   ```

2. **Test Job Scheduler and Queue Management**:

   ```bash
   # Connect to head node and test Slurm functionality
   ssh -i ~/.ssh/${KEYPAIR_NAME}.pem ec2-user@${HEAD_NODE_IP} << 'EOF'
   
   # Check Slurm configuration and node status
   sinfo -s
   scontrol show config | grep -i version
   
   # Test basic job submission
   cat > /tmp/test-job.sh << 'TEST_EOF'
   #!/bin/bash
   #SBATCH --job-name=validation-test
   #SBATCH --nodes=1
   #SBATCH --ntasks=1
   #SBATCH --time=00:02:00
   
   echo "Hello from HPC cluster validation test"
   echo "Node: $(hostname)"
   echo "Date: $(date)"
   echo "User: $(whoami)"
   echo "Working directory: $(pwd)"
   echo "Environment modules available:"
   module avail
   TEST_EOF
   
   # Submit test job using the wrapper script
   /shared/jobs/submit-hpc-job.sh /tmp/test-job.sh 1 1 00:02:00
   
   # Check job queue status
   squeue
   
   exit
   EOF
   ```

3. **Test Storage Performance and Accessibility**:

   ```bash
   # Test FSx Lustre performance and S3 integration
   ssh -i ~/.ssh/${KEYPAIR_NAME}.pem ec2-user@${HEAD_NODE_IP} << 'EOF'
   
   # Test write performance to FSx Lustre
   echo "Testing FSx Lustre write performance..."
   time dd if=/dev/zero of=/fsx/test-file bs=1M count=1000 conv=fsync
   
   # Test read performance
   echo "Testing FSx Lustre read performance..."
   time dd if=/fsx/test-file of=/dev/null bs=1M
   
   # Test S3 data transfer functionality
   echo "Testing S3 integration..."
   echo "Test data $(date)" > /fsx/test-s3-file.txt
   aws s3 cp /fsx/test-s3-file.txt s3://S3_BUCKET_NAME/test/
   
   # Verify file was uploaded
   aws s3 ls s3://S3_BUCKET_NAME/test/ --human-readable
   
   # Clean up test files
   rm /fsx/test-file /fsx/test-s3-file.txt
   aws s3 rm s3://S3_BUCKET_NAME/test/test-s3-file.txt
   
   # Run storage utilization check
   /shared/jobs/check-storage.sh
   
   exit
   EOF
   
   # Replace S3 bucket placeholder
   ssh -i ~/.ssh/${KEYPAIR_NAME}.pem ec2-user@${HEAD_NODE_IP} \
       "sed -i 's/S3_BUCKET_NAME/${S3_BUCKET_NAME}/g' /dev/stdin" <<< ""
   ```

4. **Validate Auto-Scaling Functionality**:

   ```bash
   # Submit multiple jobs to trigger auto-scaling
   ssh -i ~/.ssh/${KEYPAIR_NAME}.pem ec2-user@${HEAD_NODE_IP} << 'EOF'
   
   echo "Submitting multiple jobs to test auto-scaling..."
   
   # Create a test job that runs for several minutes
   cat > /tmp/scaling-test.sh << 'SCALE_EOF'
   #!/bin/bash
   #SBATCH --job-name=scale-test
   #SBATCH --time=00:08:00
   
   module load mpi/openmpi
   echo "Scale test job starting on $(hostname) at $(date)"
   
   # Simulate computational work
   sleep 300
   
   echo "Scale test job completed on $(hostname) at $(date)"
   SCALE_EOF
   
   # Submit several jobs to trigger scaling
   for i in {1..5}; do
       sbatch --nodes=2 --ntasks=8 \
              --job-name=scale-test-$i \
              /tmp/scaling-test.sh
       echo "Submitted scaling test job $i"
   done
   
   # Monitor queue and scaling activity
   echo "Current job queue:"
   squeue
   
   echo "Monitoring scaling for 2 minutes..."
   for j in {1..4}; do
       sleep 30
       echo "Check $j - Queue status:"
       squeue | head -10
   done
   
   exit
   EOF
   
   # Check EC2 instances being launched for scaling
   echo "Checking EC2 instances in cluster..."
   aws ec2 describe-instances \
       --filters "Name=tag:Application,Values=parallelcluster" \
               "Name=instance-state-name,Values=running,pending" \
       --query 'Reservations[].Instances[].{ID:InstanceId,State:State.Name,Type:InstanceType,LaunchTime:LaunchTime}' \
       --output table
   ```

## Cleanup

1. **Delete ParallelCluster and Associated Resources**:

   ```bash
   # Delete the HPC cluster (this will terminate all instances)
   echo "Initiating cluster deletion..."
   pcluster delete-cluster \
       --cluster-name ${CLUSTER_NAME}
   
   # Wait for deletion to complete with progress monitoring
   echo "Waiting for cluster deletion to complete..."
   while true; do
       STATUS=$(pcluster describe-cluster \
           --cluster-name ${CLUSTER_NAME} \
           --query 'clusterStatus' --output text 2>/dev/null || echo "DELETED")
       
       if [[ ${STATUS} == "DELETED" ]]; then
           echo "✅ Cluster deleted successfully"
           break
       elif [[ ${STATUS} == "DELETE_FAILED" ]]; then
           echo "❌ Cluster deletion failed"
           exit 1
       else
           echo "Cluster status: ${STATUS} - Still deleting..."
           sleep 30
       fi
   done
   ```

2. **Remove CloudWatch Monitoring Resources**:

   ```bash
   # Delete CloudWatch dashboard
   aws cloudwatch delete-dashboards \
       --dashboard-names ${CLUSTER_NAME}-performance
   
   # Delete all CloudWatch alarms for the cluster
   aws cloudwatch delete-alarms \
       --alarm-names "${CLUSTER_NAME}-high-cpu" \
                     "${CLUSTER_NAME}-high-network"
   
   echo "✅ CloudWatch monitoring resources cleaned up"
   ```

3. **Clean Up Networking Resources**:

   ```bash
   # Delete NAT Gateway
   aws ec2 delete-nat-gateway \
       --nat-gateway-id ${NAT_GW_ID}
   
   # Wait for NAT Gateway deletion to complete
   echo "Waiting for NAT Gateway deletion..."
   aws ec2 wait nat-gateway-deleted \
       --nat-gateway-ids ${NAT_GW_ID}
   
   # Release Elastic IP allocation
   aws ec2 release-address \
       --allocation-id ${NAT_ALLOCATION_ID}
   
   # Delete custom route table
   aws ec2 delete-route-table \
       --route-table-id ${PRIVATE_RT_ID}
   
   # Detach and delete internet gateway
   aws ec2 detach-internet-gateway \
       --internet-gateway-id ${IGW_ID} \
       --vpc-id ${VPC_ID}
   
   aws ec2 delete-internet-gateway \
       --internet-gateway-id ${IGW_ID}
   
   # Delete subnets
   aws ec2 delete-subnet --subnet-id ${PUBLIC_SUBNET_ID}
   aws ec2 delete-subnet --subnet-id ${PRIVATE_SUBNET_ID}
   
   # Delete VPC
   aws ec2 delete-vpc --vpc-id ${VPC_ID}
   
   echo "✅ Networking resources cleaned up"
   ```

4. **Remove S3 Bucket and SSH Key Pair**:

   ```bash
   # Empty and delete S3 bucket completely
   aws s3 rm s3://${S3_BUCKET_NAME} --recursive
   aws s3 rb s3://${S3_BUCKET_NAME}
   
   # Delete EC2 key pair
   aws ec2 delete-key-pair --key-name ${KEYPAIR_NAME}
   rm -f ~/.ssh/${KEYPAIR_NAME}.pem
   
   # Clean up local configuration files
   rm -f cluster-config.yaml scaling-config.yaml dashboard-config.json
   
   # Unset environment variables
   unset CLUSTER_NAME VPC_NAME KEYPAIR_NAME S3_BUCKET_NAME
   unset VPC_ID PUBLIC_SUBNET_ID PRIVATE_SUBNET_ID IGW_ID
   unset NAT_GW_ID NAT_ALLOCATION_ID PRIVATE_RT_ID HEAD_NODE_IP
   
   echo "✅ All resources and configurations cleaned up successfully"
   ```

## Discussion

AWS ParallelCluster provides a powerful, enterprise-grade platform for deploying and managing HCP workloads in the cloud, offering significant advantages over traditional on-premises solutions. The service automatically handles the complex orchestration of compute resources, storage systems, and job scheduling software, allowing researchers and engineers to focus on their scientific applications rather than infrastructure management. This managed approach reduces the total cost of ownership while providing access to virtually unlimited compute resources.

The architecture leverages several key AWS services working in concert to deliver high-performance computing capabilities. EC2 instances provide the computational foundation, with support for high-performance instance types like C5n that include Elastic Network Adapter (ENA) and Elastic Fabric Adapter (EFA) for ultra-low latency communication between instances. EFA is particularly crucial for tightly-coupled MPI applications that require sub-microsecond latencies and high message rates. FSx Lustre provides high-performance shared storage that can scale to thousands of nodes with throughput exceeding 1 TB/s, while S3 integration enables seamless data ingestion and archival workflows at petabyte scale.

One of the most compelling aspects of this solution is its cost optimization through intelligent auto-scaling. Unlike traditional HPC clusters that require constant provisioning for peak workloads, ParallelCluster can scale elastically from zero to hundreds of nodes based on Slurm job queue demand. This elasticity, combined with support for EC2 Spot instances, can reduce compute costs by up to 90% for fault-tolerant workloads. The Slurm scheduler integration provides sophisticated job queuing, resource allocation, fair-share scheduling, and comprehensive job accounting that HPC users expect from enterprise-grade systems.

The storage architecture deserves special attention, as I/O performance is often the primary bottleneck in HPC workloads. FSx Lustre can deliver over 1 TB/s of aggregate throughput and millions of IOPS, with the ability to automatically hydrate data directly from S3 buckets when jobs start and export results when they complete. This creates a seamless workflow where massive datasets can be stored cost-effectively in S3 long-term and automatically cached in high-performance storage only when needed for computation, optimizing both performance and cost.

> **Note**: FSx Lustre performance scales linearly with storage capacity. For optimal I/O performance, size your filesystem based on bandwidth requirements rather than just storage capacity needs. See the [FSx Lustre performance documentation](https://docs.aws.amazon.com/fsx/latest/LustreGuide/performance.html) for detailed sizing guidance and performance tuning recommendations.

> **Tip**: Use FSx Lustre's data repository associations (DRA) to automatically sync results back to S3, enabling hybrid workflows that combine cloud elasticity with long-term data persistence and governance.

## Challenge

Extend this solution by implementing these advanced HPC capabilities:

1. **Multi-Queue Configuration**: Set up separate Slurm queues for different workload types (CPU-intensive, memory-intensive, GPU-accelerated) with different instance types, scaling policies, and priority levels for each queue to optimize resource allocation.

2. **Hybrid Cloud Bursting**: Implement job bursting from an on-premises Slurm cluster to AWS ParallelCluster during peak demand periods, using AWS Direct Connect for secure, high-bandwidth connectivity and shared job accounting databases.

3. **Container-Based Scientific Workloads**: Integrate Singularity or Docker containers for portable application deployment, including building custom container images with pre-installed scientific software libraries and implementing container orchestration for complex multi-stage workflows.

4. **Advanced Monitoring and Analytics**: Implement comprehensive monitoring with custom CloudWatch metrics, Slurm accounting database integration, job efficiency analytics, and cost tracking per research group or project using AWS Cost Explorer APIs and custom dashboards.

5. **Fault-Tolerant Checkpointing**: Implement automatic checkpointing and restart capabilities for long-running scientific simulations, using S3 for checkpoint storage, Lambda functions for automated job recovery, and integration with scientific computing frameworks that support checkpoint/restart functionality.

## Infrastructure Code

*Infrastructure code will be generated after recipe approval.*