# Configure the Helm provider using kube_config dynamic evaluation
provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
  }
}

# Wait 60 seconds to ensure Azure propagates the AcrPull role
resource "time_sleep" "wait_for_acr_role" {
  depends_on = [azurerm_role_assignment.aks_to_acr]

  create_duration = "60s"
}

# Import official images to ACR
resource "null_resource" "import_ingress_images" {
  depends_on = [azurerm_container_registry.acr]

  provisioner "local-exec" {
    command = <<EOT
      az acr import --name ${azurerm_container_registry.acr.name} \
        --source registry.k8s.io/ingress-nginx/controller:${var.controller_tag} \
        --image ${var.controller_image}:${var.controller_tag} \
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

  depends_on = [
    azurerm_kubernetes_cluster.aks,
    null_resource.import_ingress_images,
    time_sleep.wait_for_acr_role
  ]

  # Disable wait to let Terraform complete cleanly without timing out on Azure LB provisioning
  wait            = false
  cleanup_on_fail = true

  # Deactivate Webhooks to bypass admission jobs
  set {
    name  = "controller.admissionWebhooks.enabled"
    value = "false"
  }

  # Adjusted to 1 replica because AKS node_count is 1
  set {
    name  = "controller.replicaCount"
    value = "1"
  }

  set {
    name  = "controller.ingressClassResource.default"
    value = "true"
  }

  # Service LoadBalancer for public IP allocation
  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.nodeSelector.kubernetes\\.io/os"
    value = "linux"
  }

  # ACR Image Redirection
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

  # Disable DefaultBackend explicitly (not needed for basic ingress routing)
  set {
    name  = "defaultBackend.enabled"
    value = "false"
  }
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-rg"
  location = var.location
}

# Azure Container Registry
resource "azurerm_container_registry" "acr" {
  name                = "${replace(var.prefix, "-", "")}acr"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

# Azure Service Plan
resource "azurerm_service_plan" "asp" {
  name                = "${var.prefix}-asp"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "P1v2"
}

# Linux Web App
resource "azurerm_linux_web_app" "app" {
  name                = "${var.prefix}-app"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  service_plan_id     = azurerm_service_plan.asp.id

  site_config {
    application_stack {
      docker_image_name   = "appsvc/staticsite:latest"
      docker_registry_url = "https://mcr.microsoft.com"
    }
  }

  app_settings = {
    "DOCKER_REGISTRY_SERVER_URL"      = "https://${azurerm_container_registry.acr.login_server}"
    "DOCKER_REGISTRY_SERVER_USERNAME" = azurerm_container_registry.acr.admin_username
    "DOCKER_REGISTRY_SERVER_PASSWORD" = azurerm_container_registry.acr.admin_password
  }
}

# Azure Kubernetes Service
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.prefix}-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "${var.prefix}-k8s"

  role_based_access_control_enabled = true

  default_node_pool {
    name            = "default"
    node_count      = 1
    vm_size         = "Standard_D2s_v3"
    os_disk_size_gb = 30
    os_disk_type    = "Ephemeral"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
    network_policy    = "calico"
  }

  tags = {
    Environment = "Portfolio-Demo"
  }

  oidc_issuer_enabled = true
}

# Role Assignment AKS -> ACR
resource "azurerm_role_assignment" "aks_to_acr" {
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}