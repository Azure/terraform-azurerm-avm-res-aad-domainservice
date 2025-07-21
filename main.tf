
resource "azurerm_resource_provider_registration" "this" {
  name = "Microsoft.AAD"
}


locals {
  nsg_resource_group_name = split(var.nsg_rules.nsg_resource_id, "/")[4]
  nsg_name                = split(var.nsg_rules.nsg_resource_id, "/")[8]
}

#TODO: consider adding NSG with rules for domain services


resource "azurerm_network_security_rule" "rdp" {
  count = var.nsg_rules.allow_rdp_access ? 1 : 0
  name                        = "AllowRD"
  network_security_group_name = local.nsg_name
  resource_group_name         = local.nsg_resource_group_name
  priority                    = var.nsg_rules.rdp_rule_priority
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["3389"]
  source_address_prefix       = "CorpNetSaw"
  destination_address_prefix  = "*"
}

resource "azurerm_network_security_rule" "winrm" {
  name                        = "AllowPSRemoting"
  network_security_group_name = local.nsg_name
  resource_group_name         = local.nsg_resource_group_name
  priority                    = var.nsg_rules.winrm_rule_priority
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["5986"]
  source_address_prefix       = "AzureActiveDirectoryDomainServices"
  destination_address_prefix  = "*"
  
}

resource "azurerm_active_directory_domain_service" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  domain_name           = var.domain_name
  sku                   = var.sku
  domain_configuration_type = var.domain_configuration_type
  filtered_sync_enabled = var.filtered_sync_enabled
  
  dynamic "secure_ldap" {
    for_each = var.secure_ldap.enabled == true ? [1] : []
    content {
      enabled = var.secure_ldap.enabled
      pfx_certificate = var.secure_ldap.pfx_certificate
      pfx_certificate_password = var.secure_ldap.pfx_certificate_password
    }
  }

  dynamic "notifications" {
    for_each = var.notifications != null ? var.notifications : {}
    content {
      notify_dc_admins      = var.notifications.notify_dc_admins
      notify_global_admins  = var.notifications.notify_global_admins
    }
  }

  initial_replica_set {
    subnet_id = var.subnet_resource_id
  }

  notifications {
    notify_dc_admins      = true
    notify_global_admins  = true
  }

  security {
    sync_kerberos_passwords = true
    sync_ntlm_passwords     = true
    sync_on_prem_passwords  = true
  }
  # This will change to "fully synced" once the service is fully deployed. and will enforce replacement 
  
  lifecycle {
    ignore_changes = [ domain_configuration_type, tags ]
  }
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
