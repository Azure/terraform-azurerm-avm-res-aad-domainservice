output "name" {
  description = "The Domain Services resource name"
  value       = azapi_resource.this.name
}

output "resource" {
  description = "This is the full output for the resource."
  value       = azapi_resource.this
}

output "resource_id" {
  description = "The ID of the Domain Services resource"
  value       = azapi_resource.this.id
}
