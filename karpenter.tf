module "karpenter" {
  source = "terraform-aws-modules/eks/aws//modules/karpenter"

  cluster_name = module.eks.cluster_name

  enable_v1_permissions = true

  enable_pod_identity             = true
  create_pod_identity_association = true

  # Attach additional IAM policies to the Karpenter node IAM role
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

resource "helm_release" "karpenter" {
  namespace           = "kube-system"
  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = "karpenter"
  version             = "1.1.0"
  wait                = false

  values = [
    <<-EOT
    serviceAccount:
      name: ${module.karpenter.service_account}
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    EOT
  ]
}

resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        spec:
          expireAfter: 720h # 30 * 24h = 720h
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          taints:
          - key: karpenter-node-pool
            value: "true"
            effect: NoSchedule
          requirements:
            - key: karpenter.k8s.aws/instance-category
              operator: In
              values: ["c", "m", "r"]
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64", "arm64"]
            - key: kubernetes.io/os
              operator: In
              values: ["linux"]
            - key: karpenter.k8s.aws/instance-generation
              operator: Gt
              values: ["2"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot", "on-demand"]
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 1m
  YAML

  depends_on = [
    kubectl_manifest.karpenter_node_class
  ]
}

resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      role: ${module.karpenter.node_iam_role_name}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      tags:
        karpenter.sh/discovery: ${module.eks.cluster_name}
      amiSelectorTerms:
        - alias: al2023@latest
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}