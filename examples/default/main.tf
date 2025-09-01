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
  main_replica_location = "germanywestcentral"
}

resource "azurerm_resource_group" "example" {
  location = local.main_replica_location
  name     = "RG-MEDS"
}

resource "azurerm_virtual_network" "example" {
  location            = azurerm_resource_group.example.location
  name                = "MEDS-network"
  resource_group_name = azurerm_resource_group.example.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_network_security_group" "example" {
  location            = azurerm_resource_group.example.location
  name                = "MEDS-nsg"
  resource_group_name = azurerm_resource_group.example.name
}

resource "azurerm_subnet" "example" {
  address_prefixes     = ["10.0.0.0/24"]
  name                 = "MEDS-subnet"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
}

resource "azurerm_subnet_network_security_group_association" "example" {
  network_security_group_id = azurerm_network_security_group.example.id
  subnet_id                 = azurerm_subnet.example.id
}

module "entra_domain_services" {
  source = "../../"

  domain_configuration_type = "FullySynced"
  domain_name               = "contoso.com"
  filtered_sync_enabled     = false
  location                  = azurerm_resource_group.example.location
  name                      = "MEDS"
  resource_group_name       = azurerm_resource_group.example.name
  sku                       = "Enterprise"
  subnet_resource_id        = azurerm_subnet.example.id

  # Deploy required NSG rules
  nsg_rules = {
    r1 = {
      nsg_resource_id   = azurerm_network_security_group.example.id
      allow_rd_access  = true
      rd_rule_priority = 2000
      rd_rule_name     = "CUSTOMRULENAME"

      allow_PSRemoting_access  = true
      PSRemoting_rule_priority = 2100

      allow_ldaps_public_access = false
      #ldaps_public_rule_priority = optional(number)

      allow_ldaps_private_access = false
      #ldaps_private_rule_priority = optional(number)
    },
    r2 = {
      nsg_resource_id   = azurerm_network_security_group.secondary_nsg.id
      allow_rd_access  = true
      rd_rule_priority = 2000

      allow_PSRemoting_access  = true
      PSRemoting_rule_priority = 2100

      allow_ldaps_public_access = false
      #ldaps_public_rule_priority = optional(number)

      allow_ldaps_private_access = false
      #ldaps_private_rule_priority = optional(number)
    }
  }

  # Deploy the secondary replica
  replica_sets = {
    secondary = {
      subnet_id        = azurerm_subnet.secondary_subnet.id
      replica_location = local.secondary_replica_location
    }
  }

  tags = {
    cost_center = "IT"
  }
}

resource "time_sleep" "wait_for_domain_services_deployment" {
  depends_on = [
    module.entra_domain_services
  ]
  create_duration  = "3m"
  destroy_duration = "1s"
}

########### Secondary Replica Networking Resources ###########

locals {
  secondary_replica_location = "uksouth"
}

resource "azurerm_virtual_network" "secondary_vnet" {
  location            = local.secondary_replica_location
  name                = "secondary_MEDS_network"
  resource_group_name = azurerm_resource_group.example.name
  address_space       = ["192.168.0.0/16"]
}
resource "azurerm_subnet" "secondary_subnet" {
  address_prefixes     = ["192.168.0.0/24"]
  name                 = "MEDS_subnet_secondary"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.secondary_vnet.name
}
resource "azurerm_virtual_network_peering" "peering_main_to_secondary" {
  name                      = "peering_main_to_secondary"
  remote_virtual_network_id = azurerm_virtual_network.secondary_vnet.id
  resource_group_name       = azurerm_resource_group.example.name
  virtual_network_name      = azurerm_virtual_network.example.name
}
resource "azurerm_virtual_network_peering" "peering_secondary_to_main" {
  name                      = "peering_secondary_to_main"
  remote_virtual_network_id = azurerm_virtual_network.example.id
  resource_group_name       = azurerm_resource_group.example.name
  virtual_network_name      = azurerm_virtual_network.secondary_vnet.name
}

resource "azurerm_network_security_group" "secondary_nsg" {
  location            = local.secondary_replica_location
  name                = "secondary_MEDS_nsg"
  resource_group_name = azurerm_resource_group.example.name
  tags = {
    environment = "Production"
  }
}
resource "azurerm_subnet_network_security_group_association" "secondary_nsg_association" {
  network_security_group_id = azurerm_network_security_group.secondary_nsg.id
  subnet_id                 = azurerm_subnet.secondary_subnet.id
}
