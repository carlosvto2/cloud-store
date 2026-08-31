# Helm resource to install NGINX Ingress Controller
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.10.0"
  namespace        = var.ingress_namespace
  create_namespace = true

  # Force to wait until AKS is fully created and images are imported
  depends_on = [
    azurerm_kubernetes_cluster.aks,
    null_resource.import_ingress_images,
    time_sleep.wait_for_acr_role
  ]

  # Force wait until all resources are ready (Load Balancer with IP)
  wait            = true
  timeout         = 900
  cleanup_on_fail = true

  # Deactivate temporarily the Webhook
  set {
    name  = "controller.admissionWebhooks.enabled"
    value = "false"
  }

  # Controller replicas for high availability
  set {
    name  = "controller.replicaCount"
    value = "1"
  }

  # Configure the controller service to request a public LoadBalancer from Azure
  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  # Allows Azure to route traffic through any node in the cluster
  set {
    name  = "controller.service.externalTrafficPolicy"
    value = "Cluster"
  }

  # Explicitly specify the default Ingress class
  set {
    name  = "controller.ingressClassResource.name"
    value = "nginx"
  }

  set {
    name  = "controller.ingressClassResource.isDefaultClass"
    value = "true"
  }

  # --------------------------------------------------------------------------------------
  # Node Selectors (Linux)
  # --------------------------------------------------------------------------------------

  set {
    name  = "controller.nodeSelector.kubernetes\\.io/os"
    value = "linux"
  }

  set {
    name  = "defaultBackend.nodeSelector.kubernetes\\.io/os"
    value = "linux"
  }

  set {
    name  = "controller.admissionWebhooks.patch.nodeSelector.kubernetes\\.io/os"
    value = "linux"
  }

  # -----------------------------------------------------------------
  # Private ACR Images
  # -----------------------------------------------------------------

  # Controller Image
  set {
    name  = "controller.image.registry"
    value = azurerm_container_registry.acr.login_server
  }
  set {
    name  = "controller.image.image"
    value = var.controller_image
  }
  set {
    name  = "controller.image.tag"
    value = var.controller_tag
  }
  set {
    name  = "controller.image.digest"
    value = ""
  }

  # Webhook Patch Image
  set {
    name  = "controller.admissionWebhooks.patch.image.registry"
    value = azurerm_container_registry.acr.login_server
  }
  set {
    name  = "controller.admissionWebhooks.patch.image.image"
    value = var.patch_image
  }
  set {
    name  = "controller.admissionWebhooks.patch.image.tag"
    value = var.patch_tag
  }
  set {
    name  = "controller.admissionWebhooks.patch.image.digest"
    value = ""
  }

  # Default Backend Image
  set {
    name  = "defaultBackend.image.registry"
    value = azurerm_container_registry.acr.login_server
  }
  set {
    name  = "defaultBackend.image.image"
    value = var.defaultbackend_image
  }
  set {
    name  = "defaultBackend.image.tag"
    value = var.defaultbackend_tag
  }
  set {
    name  = "defaultBackend.image.digest"
    value = ""
  }
}