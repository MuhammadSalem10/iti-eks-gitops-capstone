locals {
  ecr_domain = split("/", data.terraform_remote_state.infra.outputs.ecr_url[0])[0]
  ebs_name   = kubernetes_manifest.ebs_csi.manifest.metadata.name
}

# resource "kubernetes_manifest" "secret_updater" {
#   manifest = yamldecode(file("${path.module}/manifests/argocd_image_updater_secret.yaml"))
# }
resource "kubernetes_secret" "argocd_image_updater_secret" {
  depends_on = [helm_release.argocd]
  metadata {
    name      = "aws-token"
    namespace = "argocd"
  }

  data = {
    creds = format("%s:%s", "AWS", data.terraform_remote_state.infra.outputs.ecr_token)
  }

  type = "Opaque"
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  depends_on       = [kubernetes_manifest.ebs_csi]

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.46.6"

  values = [
    templatefile("${path.module}/values/argocd-values.yaml", {
      argocd_host = "argocd.${var.domain_name}"
    })
  ]
}


resource "helm_release" "argocd-image-updater" {
  name             = "argocd-image-updater"
  namespace        = "argocd"
  create_namespace = true
  depends_on       = [helm_release.argocd, kubernetes_manifest.ebs_csi, kubernetes_secret.argocd_image_updater_secret]

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-image-updater"
  version    = "0.12.1"

  values = [
    file("values/image-updater-values.yaml")
  ]
}

resource "helm_release" "jenkins" {
  name             = "jenkins"
  namespace        = "jenkins"
  create_namespace = true
  depends_on       = [kubernetes_manifest.ebs_csi]

  repository = "https://charts.jenkins.io"
  chart      = "jenkins"
  version    = "5.8.48"

  values = [
    templatefile("${path.module}/values/jenkins-values.yaml", {
      jenkins_host = "jenkins.${var.domain_name}"
    })
  ]
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.9.13"

  set {
    name  = "installCRDs"
    value = "true"
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  namespace  = "monitoring"
  chart      = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  version    = "59.0.0"

  create_namespace = true
  values = [
    templatefile("${path.module}/values/monitoring-values.yaml", {
      prometheus_host   = "prometheus.${var.domain_name}"
      grafana_host      = "grafana.${var.domain_name}"
      alertmanager_host = "alertmanager.${var.domain_name}"
    })
  ]
}


module "nginx-ingress" {
  source       = "./ingress-controller"
  eks_core_dns = var.domain_name
}

module "route53" {
  source            = "./route53"
  nginx_lb_dns      = module.nginx-ingress.nginx_lb_dns
  domain_name       = var.domain_name
  jenkins_host      = "jenkins.${var.domain_name}"
  argocd_host       = "argocd.${var.domain_name}"
  prometheus_host   = "prometheus.${var.domain_name}"
  grafana_host      = "grafana.${var.domain_name}"
  alertmanager_host = "alertmanager.${var.domain_name}"
  app_host          = "app.${var.domain_name}"
}

