resource "helm_release" "nginx_ingress" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = "ingress-nginx"
  version    = "4.12.3"

  create_namespace = true

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.admissionWebhooks.enabled"
    value = "true"
  }

  set {
    name  = "controller.admissionWebhooks.patch.enabled"
    value = "true"
  }

  set {
    name  = "controller.admissionWebhooks.patch.image.digest"
    value = ""
  }

  depends_on = [var.eks_core_dns]
}

data "external" "nginx_lb_dns" {
  program    = ["bash", "${path.module}/scripts/get_lb_dns.sh"]
  depends_on = [helm_release.nginx_ingress]
}

