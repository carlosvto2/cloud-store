# Return the public IP assigned by the Azure Load Balancer after applying the resource
output "ingress_public_ip" {
  description = "Public IP of the Azure Load Balancer associated to the NGINX Ingress Controller"
  value       = helm_release.ingress_nginx.status
}

output "acr_name" {
  value       = azurerm_container_registry.acr.name
  description = "Name of the resource Azure Container Registry"
}