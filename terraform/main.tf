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

# Add a new pool to the cluster to deploy the petstore services 
# (3 new virtual machines to the cluster with the name petstorenp2)
resource "azurerm_kubernetes_cluster_node_pool" "petstore_pool" {
  name                  = "petstorenp2"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = "Standard_D2s_v3"
  node_count            = 3

  node_labels = {
    "agentpool" = "petstorenp2"
  }
}

# Vinculate AKS with ACR so that Kubernetes can download the images in the registry
resource "azurerm_role_assignment" "aks_to_acr" {
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}

# Dedicated Public IP for NGINX Ingress Controller to route external traffic into AKS
resource "azurerm_public_ip" "ingress_pip" {
  name                = "pip-ingress-nginx"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_kubernetes_cluster.aks.node_resource_group
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    environment = "Portfolio-Demo"
  }
}

# Execute the manifests in kustomization
data "kustomization_build" "petstore" {
  path = "${path.module}/../app"
}

resource "kustomization_resource" "petstore_app" {
  for_each = data.kustomization_build.petstore.ids
  manifest = data.kustomization_build.petstore.manifests[each.value]

  depends_on = [
    azurerm_kubernetes_cluster.aks,
    helm_release.ingress_nginx
  ]
}

# Obtener el NSG creado automáticamente por AKS en el grupo de nodos
data "azurerm_resources" "aks_nsg" {
  resource_group_name = azurerm_kubernetes_cluster.aks.node_resource_group
  type                = "Microsoft.Network/networkSecurityGroups"
}

# Permitir que las Health Probes de Azure lleguen a los NodePorts de los nodos
resource "azurerm_network_security_rule" "allow_azure_health_probes" {
  name                        = "Allow-Azure-HealthProbes-NodePorts"
  priority                    = 105
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "30000-32767"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_kubernetes_cluster.aks.node_resource_group
  network_security_group_name = split("/", data.azurerm_resources.aks_nsg.resources[0].id)[8]
}