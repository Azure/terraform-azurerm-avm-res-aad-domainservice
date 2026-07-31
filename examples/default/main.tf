terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
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

# Prepare dependant resources including RG and networking
resource "azurerm_resource_group" "example" {
  location = local.managed_domain_location
  name     = local.managed_domain_RG_name
}

resource "azurerm_virtual_network" "example" {
  location            = azurerm_resource_group.example.location
  name                = local.managed_domain_vnet_name
  resource_group_name = azurerm_resource_group.example.name
  address_space       = local.managed_domain_vnet_cidr
}

resource "azurerm_network_security_group" "example" {
  location            = azurerm_resource_group.example.location
  name                = local.managed_domain_nsg_name
  resource_group_name = azurerm_resource_group.example.name
}

resource "azurerm_subnet" "example" {
  address_prefixes     = local.managed_domain_subnet_cidr
  name                 = local.managed_domain_subnet_name
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
}

resource "azurerm_subnet_network_security_group_association" "example" {
  network_security_group_id = azurerm_network_security_group.example.id
  subnet_id                 = azurerm_subnet.example.id
}

# Module call to deploy the Entra Domain Services
module "entra_domain_services" {
  source = "../../"

  domain_configuration_type = local.managed_domain_configuration_type
  domain_name               = local.managed_domain_name
  filtered_sync_enabled     = false
  location                  = azurerm_resource_group.example.location
  name                      = local.managed_domain_resuorce_name
  resource_group_name       = azurerm_resource_group.example.name
  sku                       = local.managed_domain_sku
  subnet_resource_id        = azurerm_subnet.example.id
  # Deploy required NSG rules
  nsg_rules = {
    r1 = {
      nsg_resource_id = azurerm_network_security_group.example.id

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
