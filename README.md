# Terraform EKS with Karpenter

## Overview
This Terraform repository is designed to provision an AWS EKS cluster with Karpenter to manage node scaling dynamically, supporting both x86 and ARM64 (Graviton) and spot instances.

## Prerequisites
- Terraform installed
- AWS CLI installed and configured
- kubectl installed
- helm installed

## Deployment Steps
1. Clone the repository: `git clone <repository-url>`.
2. Navigate to the repository directory.
3. Initialize Terraform: `terraform init`.
4. Apply Terraform plan: `terraform apply -var-file="terraform.tfvars"`.

## Deploying a Pod to Specific Architecture
To deploy workloads on specific architectures, you can use node selectors in your Kubernetes deployments.

### Example Deployment for ARM64 (Graviton) Architecture with Spot capacity type
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app-arm64
spec:
  selector:
    matchLabels:
      app: sample-app-arm64
  replicas: 1
  template:
    metadata:
      labels:
        app: sample-app-arm64
    spec:
      nodeSelector:
        kubernetes.io/arch: arm64
        karpenter.sh/capacity-type: spot
      tolerations:  # <-- Tolerations added here
        - key: "karpenter-node-pool"
          operator: "Equal"
          value: "true"
          effect: "NoSchedule"

      containers:
        - name: nginx
          image: nginx