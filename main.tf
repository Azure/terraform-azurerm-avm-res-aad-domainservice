# Create the AAD Domain Service
resource "azurerm_active_directory_domain_service" "this" {
  domain_name               = var.domain_name
  location                  = var.location
  name                      = var.name
  resource_group_name       = var.resource_group_name
  sku                       = var.sku
  domain_configuration_type = var.domain_configuration_type
  filtered_sync_enabled     = var.filtered_sync_enabled
  tags                      = var.tags

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
  scope                                  = resource.azurerm_active_directory_domain_service.this.id
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
  principal_type                         = each.value.principal_type
  role_definition_id                     = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? each.value.role_definition_id_or_name : null
  role_definition_name                   = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? null : each.value.role_definition_id_or_name
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
}

# NSG Security Rules for Domain Services
locals {
  # Create a flattened map of all NSG rules that need to be created
  nsg_security_rules = merge([
    for nsg_key, nsg_config in var.nsg_rules : {
      for rule_type in local.rule_types :
      "${nsg_key}-${rule_type}" => {
        rule_name       = try(nsg_config["${rule_type}_rule_name"], null)
        nsg_key         = nsg_key
        nsg_resource_id = nsg_config.nsg_resource_id
        rule_type       = rule_type
        allow_access    = lookup(nsg_config, "allow_${rule_type}_access", false)
        rule_priority   = lookup(nsg_config, "${rule_type}_rule_priority", 4096)
      }
      if lookup(nsg_config, "allow_${rule_type}_access", false) == true
    }
  ]...)
  # Rule configurations for each protocol
  rule_configs = {
    in_rd = {
      default_name               = "EntraDomainServicesAllowRD"
      description                = "Allow Entra Domain Services RD from Corporate Network Secure Access Workstation"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = ["3389"]
      source_address_prefix      = "CorpNetSaw"
      destination_address_prefix = "*"
      access                     = "Allow"
      direction                  = "Inbound"
    }
    in_PSRemoting = {
      default_name               = "EntraDomainServicesAllowPSRemoting"
      description                = "Allow Entra Domain Services PSRemoting from Azure Active Directory Domain Services"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = ["5986"]
      source_address_prefix      = "AzureActiveDirectoryDomainServices"
      destination_address_prefix = "*"
      access                     = "Allow"
      direction                  = "Inbound"
    },
    out_AzureActiveDirectoryDomainServices = {
      default_name               = "EntraDomainServicesOutAADDS"
      description                = "Allow Entra Domain Services outbound to Azure Active Directory Domain Services"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = ["443"]
      source_address_prefix      = "*"
      destination_address_prefix = "AzureActiveDirectoryDomainServices"
      access                     = "Allow"
      direction                  = "Outbound"
    },
    out_AzureMonitor = {
      default_name               = "AzureMonitorOut"
      description                = "Allow Entra Domain Services outbound to Azure Monitor"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = ["443"]
      source_address_prefix      = "*"
      destination_address_prefix = "AzureMonitor"
      access                     = "Allow"
      direction                  = "Outbound"
    },
    out_storage = {
      default_name               = "StorageOut"
      description                = "Allow Entra Domain Services outbound to Storage"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = ["443"]
      source_address_prefix      = "*"
      destination_address_prefix = "Storage"
      access                     = "Allow"
      direction                  = "Outbound"
    },
    out_AzureActiveDirectory = {
      default_name               = "AzureActiveDirectoryOut"
      description                = "Allow Entra Domain Services outbound to Azure Active Directory"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = ["443"]
      source_address_prefix      = "*"
      destination_address_prefix = "AzureActiveDirectory"
      access                     = "Allow"
      direction                  = "Outbound"
    },
    out_GuestAndHybridManagement = {
      default_name               = "GuestAndHybridManagementOut"
      description                = "Allow Entra Domain Services outbound to Guest And Hybrid Management"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = ["443"]
      source_address_prefix      = "*"
      destination_address_prefix = "GuestAndHybridManagement"
      access                     = "Allow"
      direction                  = "Outbound"
    }
  }
  rule_types = ["in_rd", "in_PSRemoting", "out_AzureActiveDirectoryDomainServices", "out_AzureMonitor", "out_storage", "out_AzureActiveDirectory", "out_GuestAndHybridManagement"]
}

resource "azurerm_network_security_rule" "this" {
  for_each = local.nsg_security_rules

  access                      = local.rule_configs[each.value.rule_type].access
  direction                   = local.rule_configs[each.value.rule_type].direction
  name                        = coalesce(each.value.rule_name, "${local.rule_configs[each.value.rule_type].default_name}-${each.value.nsg_key}")
  network_security_group_name = provider::azapi::parse_resource_id(local.nsg_resource_type, each.value.nsg_resource_id)["name"]
  priority                    = each.value.rule_priority
  protocol                    = local.rule_configs[each.value.rule_type].protocol
  resource_group_name         = provider::azapi::parse_resource_id(local.nsg_resource_type, each.value.nsg_resource_id)["resource_group_name"]
  description                 = local.rule_configs[each.value.rule_type].description
  destination_address_prefix  = local.rule_configs[each.value.rule_type].destination_address_prefix
  destination_port_ranges     = local.rule_configs[each.value.rule_type].destination_port_ranges
  source_address_prefix       = local.rule_configs[each.value.rule_type].source_address_prefix
  source_port_range           = local.rule_configs[each.value.rule_type].source_port_range
}
