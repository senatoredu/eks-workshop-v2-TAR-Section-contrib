data "aws_partition" "current" {}

module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.39.1"

  role_name_prefix = "${var.addon_context.eks_cluster_id}-ebs-csi-"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = var.addon_context.eks_oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = var.tags
}

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "1.16.3"

  cluster_name      = var.addon_context.eks_cluster_id
  cluster_endpoint  = var.addon_context.aws_eks_cluster_endpoint
  cluster_version   = var.eks_cluster_version
  oidc_provider_arn = var.addon_context.eks_oidc_provider_arn

  eks_addons = {
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
      preserve                 = false
      configuration_values     = jsonencode({ defaultStorageClass = { enabled = true } })
    }
  }

  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    wait = true
  }
}

resource "time_sleep" "blueprints_addons_sleep" {
  depends_on = [
    module.eks_blueprints_addons
  ]

  create_duration = "15s"
}

module "cert_manager" {
  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "1.1.1"

  depends_on = [
    time_sleep.blueprints_addons_sleep
  ]

  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  wait             = true
  chart            = "cert-manager"
  chart_version    = "v1.15.1"
  repository       = "https://charts.jetstack.io"

  set = [
    {
      name  = "crds.enabled"
      value = true
    }
  ]
}

resource "kubernetes_namespace" "opentelemetry_operator" {
  metadata {
    name = "opentelemetry-operator-system"
  }
}

module "opentelemetry_operator" {
  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "1.1.1"

  depends_on = [
    module.cert_manager
  ]

  name             = "opentelemetry"
  namespace        = kubernetes_namespace.opentelemetry_operator.metadata[0].name
  create_namespace = false
  wait             = true
  chart            = "opentelemetry-operator"
  chart_version    = var.operator_chart_version
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"

  set = [{
    name  = "manager.collectorImage.repository"
    value = "otel/opentelemetry-collector-k8s"
  }]
}

module "iam_assumable_role_adot" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.39.1"

  create_role  = true
  role_name    = "${var.addon_context.eks_cluster_id}-adot-collector"
  provider_url = var.addon_context.eks_oidc_issuer_url
  role_policy_arns = [
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSXrayWriteOnlyAccess",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonPrometheusRemoteWriteAccess"
  ]
  oidc_fully_qualified_subjects = ["system:serviceaccount:other:adot-collector"]

  tags = var.tags
}
