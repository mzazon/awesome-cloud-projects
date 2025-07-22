# Outputs for EKS Multi-Tenant Cluster Security with Namespace Isolation
# This file defines outputs that provide information about the deployed multi-tenant security configuration

output "cluster_name" {
  description = "Name of the EKS cluster where multi-tenant security is implemented"
  value       = var.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server"
  value       = data.aws_eks_cluster.existing.endpoint
}

output "cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = data.aws_eks_cluster.existing.version
}

output "cluster_platform_version" {
  description = "Platform version of the EKS cluster"
  value       = data.aws_eks_cluster.existing.platform_version
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = data.aws_eks_cluster.existing.arn
}

output "tenant_namespaces" {
  description = "Information about created tenant namespaces"
  value = {
    for k, v in kubernetes_namespace.tenant_namespaces : k => {
      name   = v.metadata[0].name
      labels = v.metadata[0].labels
      uid    = v.metadata[0].uid
    }
  }
}

output "tenant_iam_roles" {
  description = "IAM roles created for tenant access"
  value = {
    for k, v in aws_iam_role.tenant_roles : k => {
      name = v.name
      arn  = v.arn
    }
  }
}

output "tenant_access_entries" {
  description = "EKS access entries for tenant IAM to RBAC mapping"
  value = {
    for k, v in aws_eks_access_entry.tenant_access_entries : k => {
      principal_arn = v.principal_arn
      username      = v.user_name
      type          = v.type
    }
  }
}

output "tenant_rbac_roles" {
  description = "Kubernetes RBAC roles created for tenant access"
  value = {
    for k, v in kubernetes_role.tenant_roles : k => {
      name      = v.metadata[0].name
      namespace = v.metadata[0].namespace
      uid       = v.metadata[0].uid
    }
  }
}

output "tenant_rbac_bindings" {
  description = "Kubernetes RBAC role bindings for tenant users"
  value = {
    for k, v in kubernetes_role_binding.tenant_bindings : k => {
      name      = v.metadata[0].name
      namespace = v.metadata[0].namespace
      role_name = v.role_ref[0].name
      subjects  = v.subject
    }
  }
}

output "tenant_network_policies" {
  description = "Network policies created for tenant isolation"
  value = {
    for k, v in kubernetes_network_policy.tenant_isolation : k => {
      name      = v.metadata[0].name
      namespace = v.metadata[0].namespace
      uid       = v.metadata[0].uid
    }
  }
}

output "tenant_resource_quotas" {
  description = "Resource quotas configured for tenant namespaces"
  value = {
    for k, v in kubernetes_resource_quota.tenant_quotas : k => {
      name      = v.metadata[0].name
      namespace = v.metadata[0].namespace
      quotas    = v.spec[0].hard
    }
  }
}

output "tenant_limit_ranges" {
  description = "Limit ranges configured for tenant namespaces"
  value = {
    for k, v in kubernetes_limit_range.tenant_limits : k => {
      name      = v.metadata[0].name
      namespace = v.metadata[0].namespace
      limits    = v.spec[0].limit
    }
  }
}

output "sample_applications" {
  description = "Sample applications deployed for testing (if enabled)"
  value = var.deploy_sample_apps ? {
    for k, v in kubernetes_deployment.sample_apps : k => {
      name      = v.metadata[0].name
      namespace = v.metadata[0].namespace
      replicas  = v.spec[0].replicas
      image     = v.spec[0].template[0].spec[0].container[0].image
    }
  } : {}
}

output "sample_services" {
  description = "Sample services deployed for testing (if enabled)"
  value = var.deploy_sample_apps ? {
    for k, v in kubernetes_service.sample_services : k => {
      name      = v.metadata[0].name
      namespace = v.metadata[0].namespace
      ports     = v.spec[0].port
    }
  } : {}
}

output "kubectl_config_commands" {
  description = "Commands to configure kubectl for tenant access"
  value = {
    for k, v in local.tenants : k => {
      assume_role_command = "aws sts assume-role --role-arn ${aws_iam_role.tenant_roles[k].arn} --role-session-name ${k}-session"
      kubeconfig_command  = "aws eks update-kubeconfig --name ${var.cluster_name} --region ${data.aws_region.current.name} --role-arn ${aws_iam_role.tenant_roles[k].arn}"
    }
  }
}

output "validation_commands" {
  description = "Commands to validate the multi-tenant security configuration"
  value = {
    namespace_check = "kubectl get namespaces --show-labels | grep -E '(${var.tenant_a_name}|${var.tenant_b_name})'"
    rbac_test_cross_namespace = {
      for k, v in local.tenants : k => "kubectl auth can-i get pods --as=${v.rbac_username} -n ${k == "alpha" ? var.tenant_b_name : var.tenant_a_name}"
    }
    rbac_test_same_namespace = {
      for k, v in local.tenants : k => "kubectl auth can-i get pods --as=${v.rbac_username} -n ${v.name}"
    }
    quota_check = {
      for k, v in local.tenants : k => "kubectl describe quota ${v.name}-quota -n ${v.name}"
    }
    network_policy_check = {
      for k, v in local.tenants : k => "kubectl get networkpolicy -n ${v.name}"
    }
  }
}

output "security_recommendations" {
  description = "Security recommendations for further hardening"
  value = {
    pod_security_standards = "Consider implementing Pod Security Standards by setting pod-security.kubernetes.io/enforce labels on namespaces"
    opa_gatekeeper        = "Deploy OPA Gatekeeper for advanced policy enforcement and admission control"
    secrets_management    = "Integrate with AWS Secrets Manager or External Secrets Operator for secure credential management"
    monitoring           = "Implement monitoring with Prometheus and Grafana for security metrics and alerting"
    image_scanning       = "Enable container image scanning with Amazon ECR or third-party solutions"
    network_security     = "Verify that your CNI plugin supports network policies (AWS VPC CNI, Calico, Cilium)"
  }
}

output "cost_optimization_tips" {
  description = "Tips for optimizing costs in multi-tenant environments"
  value = {
    resource_quotas  = "Regularly review and adjust resource quotas based on actual usage patterns"
    node_utilization = "Monitor node utilization and consider implementing cluster autoscaling"
    spot_instances   = "Use EC2 Spot Instances for non-critical workloads to reduce costs"
    rightsizing      = "Implement rightsizing recommendations for container resource limits"
  }
}

output "troubleshooting_commands" {
  description = "Commands for troubleshooting multi-tenant security issues"
  value = {
    check_access_entries = "aws eks list-access-entries --cluster-name ${var.cluster_name}"
    describe_access_entry = {
      for k, v in local.tenants : k => "aws eks describe-access-entry --cluster-name ${var.cluster_name} --principal-arn ${aws_iam_role.tenant_roles[k].arn}"
    }
    check_rbac_bindings = {
      for k, v in local.tenants : k => "kubectl describe rolebinding ${v.name}-binding -n ${v.name}"
    }
    check_network_policies = {
      for k, v in local.tenants : k => "kubectl describe networkpolicy ${v.name}-isolation -n ${v.name}"
    }
    check_pods_events = {
      for k, v in local.tenants : k => "kubectl get events -n ${v.name} --sort-by=.metadata.creationTimestamp"
    }
  }
}