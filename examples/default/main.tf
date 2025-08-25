terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    # azapi = {
    #   source  = "azure/azapi"
    #   version = "~> 2.4"
    # }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}


provider "azurerm" {
  features {}
  subscription_id = "7d91561b-788f-465e-81aa-39409f1f6b3a"
}

resource "azurerm_resource_group" "example" {
  location = "germanywestcentral"
  name     = "RG-MEDS"
}

resource "azurerm_virtual_network" "example" {
  location            = azurerm_resource_group.example.location
  name                = "example-network"
  resource_group_name = azurerm_resource_group.example.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_network_security_group" "example" {
  location            = azurerm_resource_group.example.location
  name                = "MEDS-nsg"
  resource_group_name = azurerm_resource_group.example.name
  tags = {
    environment = "Production"
  }
}

resource "azurerm_subnet" "example" {
  address_prefixes     = ["10.0.0.0/24"]
  name                 = "aadds-subnet"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
}

resource "azurerm_subnet_network_security_group_association" "example" {
  network_security_group_id = azurerm_network_security_group.example.id
  subnet_id                 = azurerm_subnet.example.id
}

resource "azurerm_subnet" "bastion_subnet" {
  address_prefixes     = ["10.0.1.0/24"]
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
}
resource "azurerm_subnet" "ad_subnet" {
  address_prefixes     = ["10.0.2.0/24"]
  name                 = "ad_subnet"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
}
resource "azurerm_public_ip" "bastion_pip" {
  allocation_method   = "Static"
  location            = azurerm_resource_group.example.location
  name                = "bastion_pip"
  resource_group_name = azurerm_resource_group.example.name
  sku                 = "Standard"
}
resource "azurerm_bastion_host" "example" {
  location            = azurerm_resource_group.example.location
  name                = "examplebastion"
  resource_group_name = azurerm_resource_group.example.name

  ip_configuration {
    name                 = "configuration"
    public_ip_address_id = azurerm_public_ip.bastion_pip.id
    subnet_id            = azurerm_subnet.bastion_subnet.id
  }
}


module "entra_domain_services" {
  source = "../../"

  domain_configuration_type = "FullySynced"
  domain_name               = "contoso.com"
  filtered_sync_enabled     = true
  location                  = "germanywestcentral"
  name                      = "MEDS"
  resource_group_name       = "RG-MEDS"
  sku                       = "Enterprise"
  subnet_resource_id        = azurerm_subnet.example.id
  nsg_rules = {
    r1 = {
      nsg_resource_id     = azurerm_network_security_group.example.id
      allow_rdp_access    = true
      rdp_rule_priority   = 1000
      winrm_rule_priority = 1100
    },
    r2 = {
      nsg_resource_id     = azurerm_network_security_group.secondary.id
      allow_rdp_access    = true
      rdp_rule_priority   = 2000
      winrm_rule_priority = 2100
    },
    r3 = {
      nsg_resource_id     = azurerm_network_security_group.third.id
      allow_rdp_access    = true
      rdp_rule_priority   = 2000
      winrm_rule_priority = 2100
    }
  }
}


########### Secondary Replica ###########

locals {
  secondary_replica_location = "uksouth"
}
resource "azurerm_virtual_network" "secondary_vnet" {
  location            = local.secondary_replica_location
  name                = "secondary_example_network"
  resource_group_name = azurerm_resource_group.example.name
  address_space       = ["192.168.0.0/16"]
}
resource "azurerm_subnet" "secondary_subnet" {
  address_prefixes     = ["192.168.0.0/24"]
  name                 = "aadds_subnet_secondary"
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