# Create the AAD Domain Service
resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"
  type      = "Microsoft.AAD/domainServices@2025-06-01"
  body = {
    properties = {
      domainName              = var.domain_name
      sku                     = var.sku
      domainConfigurationType = var.domain_configuration_type
      filteredSync            = var.filtered_sync_enabled ? "Enabled" : "Disabled"

      # Include primary replica set and additional replica sets
      replicaSets = concat([{
        subnetId = var.subnet_resource_id
        location = var.location
        }], [
        for key, replica in var.replica_sets : {
          subnetId = replica.subnet_id
          location = replica.replica_location
        }
      ])

      notificationSettings = var.notifications != null ? {
        notifyDcAdmins     = var.notifications.notify_dc_admins ? "Enabled" : "Disabled"
        notifyGlobalAdmins = var.notifications.notify_global_admins ? "Enabled" : "Disabled"
        } : {
        notifyDcAdmins     = "Enabled"
        notifyGlobalAdmins = "Enabled"
      }

      ldapsSettings = var.secure_ldap != null ? {
        ldaps                  = var.secure_ldap.enabled ? "Enabled" : "Disabled"
        pfxCertificate         = var.secure_ldap.pfx_certificate
        pfxCertificatePassword = var.secure_ldap.pfx_certificate_password
      } : null

      domainSecuritySettings = {
        syncKerberosPasswords = "Enabled"
        syncNtlmPasswords     = "Enabled"
        syncOnPremPasswords   = "Enabled"
      }

      # Include domain trusts in resource forest settings
      resourceForestSettings = length(var.domain_service_trust) > 0 ? {
        resourceForest = var.domain_name
        settings = [
          for key, trust in var.domain_service_trust : {
            friendlyName      = trust.name
            trustedDomainFqdn = trust.trusted_domain_fqdn
            trustPassword     = trust.password
            remoteDnsIps      = join(",", trust.trusted_domain_dns_ips)
            trustDirection    = "Outbound"
          }
        ]
      } : null
    }
  }
  create_headers = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  delete_headers = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  read_headers   = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  tags           = var.tags
  update_headers = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null

  lifecycle {
    ignore_changes = [body.properties.domainConfigurationType, tags]
  }
}

# Data source to get current Azure client configuration
data "azapi_client_config" "current" {}

# required AVM resources interfaces
resource "azapi_resource" "lock" {
  count = var.lock != null ? 1 : 0

  name      = coalesce(var.lock.name, "lock-${var.lock.kind}")
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Authorization/locks@2020-05-01"
  body = {
    properties = {
      level = var.lock.kind
      notes = var.lock.kind == "CanNotDelete" ? "Cannot delete the resource or its child resources." : "Cannot delete or modify the resource or its child resources."
    }
  }
  create_headers = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  delete_headers = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  read_headers   = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  update_headers = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
}

resource "azapi_resource" "role_assignment" {
  for_each = var.role_assignments

  name      = uuid()
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  body = {
    properties = {
      principalId                        = each.value.principal_id
      roleDefinitionId                   = strcontains(lower(each.value.role_definition_id_or_name), lower(local.role_definition_resource_substring)) ? each.value.role_definition_id_or_name : "/subscriptions/${data.azapi_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${each.value.role_definition_id_or_name}"
      condition                          = each.value.condition
      conditionVersion                   = each.value.condition_version
      delegatedManagedIdentityResourceId = each.value.delegated_managed_identity_resource_id
      principalType                      = each.value.principal_type
    }
  }
  create_headers = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  delete_headers = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  read_headers   = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  update_headers = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
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

resource "azapi_resource" "network_security_rule" {
  for_each = local.nsg_security_rules

  name      = coalesce(each.value.rule_name, "${local.rule_configs[each.value.rule_type].default_name}-${each.value.nsg_key}")
  parent_id = each.value.nsg_resource_id
  type      = "Microsoft.Network/networkSecurityGroups/securityRules@2023-11-01"
  body = {
    properties = {
      access                   = local.rule_configs[each.value.rule_type].access
      direction                = local.rule_configs[each.value.rule_type].direction
      priority                 = each.value.rule_priority
      protocol                 = local.rule_configs[each.value.rule_type].protocol
      description              = local.rule_configs[each.value.rule_type].description
      destinationAddressPrefix = local.rule_configs[each.value.rule_type].destination_address_prefix
      destinationPortRanges    = local.rule_configs[each.value.rule_type].destination_port_ranges
      sourceAddressPrefix      = local.rule_configs[each.value.rule_type].source_address_prefix
      sourcePortRange          = local.rule_configs[each.value.rule_type].source_port_range
    }
  }
  create_headers = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  delete_headers = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  read_headers   = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
  update_headers = var.enable_telemetry ? { "User-Agent" : local.avm_azapi_header } : null
}
