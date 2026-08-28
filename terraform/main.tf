# Ressource group
resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-rg"
  location = var.location
}

# Azure Container Registry (Private Docker registry)
resource "azurerm_container_registry" "acr" {
  name                = "${replace(var.prefix, "-", "")}acr" #
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

# azurerm_service_plan
resource "azurerm_service_plan" "asp" {
  name                = "${var.prefix}-asp"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "P1v2"
}

# Linux Web App (App Service with Docker container)
resource "azurerm_linux_web_app" "app" {
  name                = "${var.prefix}-app"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  service_plan_id     = azurerm_service_plan.asp.id

  site_config {
    # Configuration of the TEMPORAL default Docker container for ARM
    # Once there is an available image in the ACR, it will update the image of the service automatically
    application_stack {
      docker_image_name   = "appsvc/staticsite:latest"
      docker_registry_url = "https://mcr.microsoft.com"
    }
  }

  app_settings = {
    # Access credentials for ACR created automatically
    "DOCKER_REGISTRY_SERVER_URL"      = "https://${azurerm_container_registry.acr.login_server}"
    "DOCKER_REGISTRY_SERVER_USERNAME" = azurerm_container_registry.acr.admin_username
    "DOCKER_REGISTRY_SERVER_PASSWORD" = azurerm_container_registry.acr.admin_password
  }
}

# Azure Kubernetes Service (AKS)
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.prefix}-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "${var.prefix}-k8s"

  role_based_access_control_enabled = true

  default_node_pool {
    name       = "default"
    node_count = 1                  # Just 1 node to avoid wasting credits
    vm_size    = "Standard_D2s_v3"
    os_disk_size_gb  = 30
    os_disk_type = "Ephemeral"
  }

  # Identity configuration needed for Kubernetes to work with Azure
  identity {
    type = "SystemAssigned"
  }

  # Deshabilitate expensive balancers 
  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
    network_policy    = "calico" # Net controller to intercept traffic and apply firewall rules at Pod level
  }

  tags = {
    Environment = "Portfolio-Demo"
  }

  oidc_issuer_enabled = true
}

# Vinculate AKS with ACR so that Kubernetes can download the images in the registry
resource "azurerm_role_assignment" "aks_to_acr" {
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}