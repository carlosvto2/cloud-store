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
  
  # Force to wait until the AKS is fully created and images imported
  depends_on = [
    azurerm_kubernetes_cluster.aks,
    null_resource.import_ingress_images
  ]

  # Force wait until all resources are ready (Load Balancer with IP)
  wait            = true
  timeout         = 600
  cleanup_on_fail = true

  # Deactivate temporarily the Webhook
  set {
    name  = "controller.admissionWebhooks.enabled"
    value = "false"
  }

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

  # --------------------------------------------------------------------------------------
  # Search through all the machines (nodes) that Azure has already started in the cluster,
  # filter for those with the `kubernetes.io/os = linux` label, and place the NGINX 
  # container there.
  # --------------------------------------------------------------------------------------

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