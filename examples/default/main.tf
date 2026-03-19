terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.4"
    }
  }
}

provider "azapi" {
}

locals {
  managed_domain_RG_name            = "RG_MEDS"
  managed_domain_configuration_type = "FullySynced" # Options: FullySynced, ResourceForest
  managed_domain_location           = "germanywestcentral"
  managed_domain_name               = "meds.contoso.com"
  managed_domain_nsg_name           = "MEDS_nsg"
  managed_domain_resuorce_name      = "MEDS"
  managed_domain_sku                = "Enterprise" # Options: Standard, Enterprise
  managed_domain_subnet_cidr        = ["10.0.0.0/24"]
  managed_domain_subnet_name        = "MEDS_subnet"
  managed_domain_vnet_cidr          = ["10.0.0.0/16"]
  managed_domain_vnet_name          = "MEDS_vnet"
}

# Get current Azure client configuration
data "azapi_client_config" "current" {}

# Prepare dependant resources including RG and networking
resource "azapi_resource" "example_rg" {
  location  = local.managed_domain_location
  name      = local.managed_domain_RG_name
  parent_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"
  type      = "Microsoft.Resources/resourceGroups@2024-03-01"
}

resource "azapi_resource" "example_vnet" {
  location  = local.managed_domain_location
  name      = local.managed_domain_vnet_name
  parent_id = azapi_resource.example_rg.id
  type      = "Microsoft.Network/virtualNetworks@2023-11-01"
  body = {
    properties = {
      addressSpace = {
        addressPrefixes = local.managed_domain_vnet_cidr
      }
    }
  }
}

resource "azapi_resource" "example_nsg" {
  location  = local.managed_domain_location
  name      = local.managed_domain_nsg_name
  parent_id = azapi_resource.example_rg.id
  type      = "Microsoft.Network/networkSecurityGroups@2023-11-01"
}

resource "azapi_resource" "example_subnet" {
  name      = local.managed_domain_subnet_name
  parent_id = azapi_resource.example_vnet.id
  type      = "Microsoft.Network/virtualNetworks/subnets@2023-11-01"
  body = {
    properties = {
      addressPrefixes = local.managed_domain_subnet_cidr
      networkSecurityGroup = {
        id = azapi_resource.example_nsg.id
      }
    }
  }
}

# Module call to deploy the Entra Domain Services
module "entra_domain_services" {
  source = "../../"

  domain_configuration_type = local.managed_domain_configuration_type
  domain_name               = local.managed_domain_name
  filtered_sync_enabled     = false
  location                  = local.managed_domain_location
  name                      = local.managed_domain_resuorce_name
  resource_group_name       = local.managed_domain_RG_name
  sku                       = local.managed_domain_sku
  subnet_resource_id        = azapi_resource.example_subnet.id
  # Deploy required NSG rules
  nsg_rules = {
    r1 = {
      nsg_resource_id = azapi_resource.example_nsg.id

      allow_in_rd_access  = true
      in_rd_rule_priority = 2000
      in_rd_rule_name     = "CUSTOMRULENAME"

      allow_in_PSRemoting_access  = true
      in_PSRemoting_rule_priority = 2100

      allow_out_AzureActiveDirectoryDomainServices_access  = true
      out_AzureActiveDirectoryDomainServices_rule_priority = 2200

      allow_out_AzureMonitor_access  = true
      out_AzureMonitor_rule_priority = 2300

      allow_out_storage_access  = true
      out_storage_rule_priority = 2400

      allow_out_AzureActiveDirectory_access  = true
      out_AzureActiveDirectory_rule_priority = 2500

      allow_out_GuestAndHybridManagement_access  = true
      out_GuestAndHybridManagement_rule_priority = 2600
    }
  }
  tags = {
    cost_center = "IT"
  }
}
