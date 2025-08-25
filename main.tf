
# resource "azurerm_resource_provider_registration" "this" {
#   name = "Microsoft.AAD"
# }


locals {
  nsg_resource_type = "Microsoft.Network/networkSecurityGroups"
}

#TODO: consider adding NSG with rules for domain services
# CrEATE OUR OWN nSG + ADD ALL OTHER APPLICABLE RULES

resource "azurerm_network_security_rule" "rdp" {
  for_each = { for k, v in var.nsg_rules : k => v if v.allow_rdp_access }

  access                      = "Allow"
  direction                   = "Inbound"
  name                        = "AllowRD"
  network_security_group_name = provider::azapi::parse_resource_id(local.nsg_resource_type, each.value.nsg_resource_id)["name"]
  priority                    = each.value.rdp_rule_priority
  protocol                    = "Tcp"
  resource_group_name         = provider::azapi::parse_resource_id(local.nsg_resource_type, each.value.nsg_resource_id)["resource_group_name"]
  destination_address_prefix  = "*"
  destination_port_ranges     = ["3389"]
  source_address_prefix       = "CorpNetSaw"
  source_port_range           = "*"
}

resource "azurerm_network_security_rule" "winrm" {
  for_each = var.nsg_rules

  access                      = "Allow"
  direction                   = "Inbound"
  name                        = "AllowPSRemoting"
  network_security_group_name = provider::azapi::parse_resource_id(local.nsg_resource_type, each.value.nsg_resource_id)["name"]
  priority                    = each.value.winrm_rule_priority
  protocol                    = "Tcp"
  resource_group_name         = provider::azapi::parse_resource_id(local.nsg_resource_type, each.value.nsg_resource_id)["resource_group_name"]
  destination_address_prefix  = "*"
  destination_port_ranges     = ["5986"]
  source_address_prefix       = "AzureActiveDirectoryDomainServices"
  source_port_range           = "*"
}

# Create the AAD Domain Service
resource "azurerm_active_directory_domain_service" "this" {
  domain_name               = var.domain_name
  location                  = var.location
  name                      = var.name
  resource_group_name       = var.resource_group_name
  sku                       = var.sku
  domain_configuration_type = var.domain_configuration_type
  filtered_sync_enabled     = var.filtered_sync_enabled

  initial_replica_set {
    subnet_id = var.subnet_resource_id
  }
  dynamic "notifications" {
    for_each = var.notifications != null ? var.notifications : {}

    content {
      notify_dc_admins     = var.notifications.notify_dc_admins
      notify_global_admins = var.notifications.notify_global_admins
    }
  }
  notifications {
    notify_dc_admins     = true
    notify_global_admins = true
  }
  dynamic "secure_ldap" {
    for_each = var.secure_ldap != null ? [1] : []

    content {
      enabled                  = var.secure_ldap.enabled
      pfx_certificate          = var.secure_ldap.pfx_certificate
      pfx_certificate_password = var.secure_ldap.pfx_certificate_password
    }
  }
  security {
    sync_kerberos_passwords = true
    sync_ntlm_passwords     = true
    sync_on_prem_passwords  = true
  }

  lifecycle {
    ignore_changes = [domain_configuration_type, tags]
  }
}

# Create a replica set for the AAD Domain Service
resource "azurerm_active_directory_domain_service_replica_set" "replica" {
  for_each = var.replica_sets

  domain_service_id = azurerm_active_directory_domain_service.this.id
  location          = each.value.replica_location
  subnet_id         = each.value.subnet_id

  depends_on = [
    azurerm_active_directory_domain_service.this
  ]
}

# Create a trust for the AAD Domain Service
resource "azurerm_active_directory_domain_service_trust" "this" {
  for_each = var.domain_service_trust

  domain_service_id      = resource.azurerm_active_directory_domain_service.this.id
  name                   = each.value.name
  password               = each.value.password
  trusted_domain_dns_ips = each.value.trusted_domain_dns_ips
  trusted_domain_fqdn    = each.value.trusted_domain_fqdn
}

# required AVM resources interfaces
resource "azurerm_management_lock" "this" {
  count = var.lock != null ? 1 : 0

  lock_level = var.lock.kind
  name       = coalesce(var.lock.name, "lock-${var.lock.kind}")
  scope      = azurerm_active_directory_domain_service.this.id
  notes      = var.lock.kind == "CanNotDelete" ? "Cannot delete the resource or its child resources." : "Cannot delete or modify the resource or its child resources."
}

resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  principal_id                           = each.value.principal_id
  scope                                  = azurerm_active_directory_domain_service.this.id
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
  role_definition_id                     = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? each.value.role_definition_id_or_name : null
  role_definition_name                   = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? null : each.value.role_definition_id_or_name
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
}
