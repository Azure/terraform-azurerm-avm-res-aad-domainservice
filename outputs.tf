output "name" {
  description = "The Domain Services resource name"
  value       = resource.azurerm_active_directory_domain_service.this.name
}

output "resource" {
  description = "This is the full output for the resource."
  value       = resource.azurerm_active_directory_domain_service.this
}

output "resource_id" {
  description = "The ID of the Domain Services resource"
  value       = resource.azurerm_active_directory_domain_service.this.id
}
