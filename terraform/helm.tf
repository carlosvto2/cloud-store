# Configure the Helm provider with the AKS credentials
provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
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
  
  # Force to wait until the AKS is fully created
  depends_on = [azurerm_kubernetes_cluster.aks]

  # Force wait until all resources are ready (Load Balancer with IP)
  wait          = true
  timeout       = 600

  # Controller replicas for high availability
  set {
    name  = "controller.replicaCount"
    value = "2"
  }

  # Configure the controller service to request for a public IP to Azure
  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  # Asure it runs on Linux nodes in AKS
  # Check the incoming requests and enroute them to the specific Pod
  set {
    name  = "controller.nodeSelector.kubernetes\\.io/os"
    value = "linux"
  }

  # Handle incorrect requests 
  set {
    name  = "defaultBackend.nodeSelector.kubernetes\\.io/os"
    value = "linux"
  }

  # Execute to check Yaml sintax and secure connection
  set {
    name  = "controller.admissionWebhooks.patch.nodeSelector.kubernetes\\.io/os"
    value = "linux"
  }

  # -----------------------------------------------------------------
  # Redirection to our private ACR (Images previously imported in the pipeline)
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

  # 2. Webhook Patch Image
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

  # 3. Default Backend Image
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