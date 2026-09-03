# Configure the Helm provider with the AKS credentials
provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  }
}

# Wait 60 seconds to asure Azure propagates the rol AcrPull
resource "time_sleep" "wait_for_acr_role" {
  depends_on = [azurerm_role_assignment.aks_to_acr]

  create_duration = "60s"
}

# Import all 3 oficial images to ACR
resource "null_resource" "import_ingress_images" {
  depends_on = [azurerm_container_registry.acr]

  provisioner "local-exec" {
    command = <<EOT
      az acr import --name ${azurerm_container_registry.acr.name} \
        --source registry.k8s.io/ingress-nginx/controller:${var.controller_tag} \
        --image ${var.controller_image}:${var.controller_tag} \
        --force

      az acr import --name ${azurerm_container_registry.acr.name} \
        --source registry.k8s.io/ingress-nginx/kube-webhook-certgen:${var.patch_tag} \
        --image ${var.patch_image}:${var.patch_tag} \
        --force

      az acr import --name ${azurerm_container_registry.acr.name} \
        --source registry.k8s.io/defaultbackend-amd64:${var.defaultbackend_tag} \
        --image ${var.defaultbackend_image}:${var.defaultbackend_tag} \
        --force
    EOT
  }
}



# Helm resource to install NGINX Ingress Controller
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.10.0"
  namespace        = var.ingress_namespace
  create_namespace = true

  # Force to wait until AKS is fully created, public ip created and images are imported
  depends_on = [
    azurerm_kubernetes_cluster.aks,
    azurerm_public_ip.ingress_pip,
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

  # Forces Azure to provision a PUBLIC Load Balancer (not internal)
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-internal"
    value = "false"
  }

  # Forces Standard SKU for Public IP in AKS
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-sku"
    value = "standard"
  }

  # Bind the dedicated Public IP resource name created by Terraform
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-pip-name"
    value = azurerm_public_ip.ingress_pip.name
  }

  # Specify the resource group where the PIP resides (the MC_ node resource group)
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-resource-group"
    value = azurerm_kubernetes_cluster.aks.node_resource_group
  }

  # Specify the correct health endpoint of NGINX for the Azure Load Balancer
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-health-probe-request-path"
    value = "/healthz"
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