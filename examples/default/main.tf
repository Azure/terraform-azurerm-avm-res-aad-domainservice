terraform {
  required_version = "~> 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "> 3.74"
    }
    modtm = {
      source  = "azure/modtm"
      version = "~> 0.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}


provider "azurerm" {
  features {}
  subscription_id = "7d91561b-788f-465e-81aa-39409f1f6b3a"
}

resource "azurerm_resource_group" "example" {
  name     = "RG-MEDS"
  location = "germanywestcentral"
}

resource "azurerm_virtual_network" "example" {
  name                = "example-network"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_network_security_group" "example" {
  name                = "MEDS-nsg"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  tags = {
    environment = "Production"
  }
}

resource "azurerm_subnet" "example" {
  name                 = "aadds-subnet"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_subnet_network_security_group_association" "example" {
  subnet_id                 = azurerm_subnet.example.id
  network_security_group_id = azurerm_network_security_group.example.id
}

resource "azurerm_subnet" "bastion_subnet" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.0.1.0/24"]
}
resource "azurerm_subnet" "ad_subnet" {
  name                 = "ad_subnet"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.0.2.0/24"]
}
resource "azurerm_public_ip" "bastion_pip" {
  name                = "bastion_pip"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  allocation_method   = "Static"
  sku                 = "Standard"
}
resource "azurerm_bastion_host" "example" {
  name                = "examplebastion"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion_subnet.id
    public_ip_address_id = azurerm_public_ip.bastion_pip.id
  }
}


module "MEDS" {
  source              = "../../"
  resource_group_name = "RG-MEDS"
  location            = "germanywestcentral"
  name                = "MEDS"

  filtered_sync_enabled     = true
  domain_configuration_type = "FullySynced"
  subnet_resource_id        = azurerm_subnet.example.id
  domain_name               = "contoso.com"
  sku                       = "Enterprise"

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

  # Removing replicas for cost effective.
  # replica_sets = {
  #   rep1 = {
  #     replica_location = local.secondary_replica_location
  #     subnet_id = azurerm_subnet.secondary.id
  #   },
  #   rep2 = {
  #     replica_location = local.third_replica_location
  #     subnet_id = azurerm_subnet.third.id
  #   }
  # }

  # Have not managed to create OU containers as of yet.
  # ou_containers = {
  #   ou1 = {
  #     name = "OU1"
  #     account_name = "account1"
  #     password = "password1"
  #     spn = "spn1/contoso.com"
  #     parent_id = azurerm_resource_group.example.id
  #   },
  #   ou2 = {
  #     name = "OU2"
  #     account_name = "account2"
  #     password = "password2"
  #     spn = "spn2/contoso.com"
  #     parent_id = azurerm_resource_group.example.id
  #   }
  # }
}


########### Secondary Replica ###########

locals {
  secondary_replica_location = "uksouth"
}
resource "azurerm_virtual_network" "secondary" {
  name                = "secondary-example-network"
  location            = local.secondary_replica_location
  resource_group_name = azurerm_resource_group.example.name
  address_space       = ["192.168.0.0/16"]
}
resource "azurerm_subnet" "secondary" {
  name                 = "aadds-subnet-secondary"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.secondary.name
  address_prefixes     = ["192.168.0.0/24"]
}
resource "azurerm_virtual_network_peering" "example-1" {
  name                      = "peer1to2"
  resource_group_name       = azurerm_resource_group.example.name
  virtual_network_name      = azurerm_virtual_network.example.name
  remote_virtual_network_id = azurerm_virtual_network.secondary.id
}
resource "azurerm_virtual_network_peering" "example-2" {
  name                      = "peer2to1"
  resource_group_name       = azurerm_resource_group.example.name
  virtual_network_name      = azurerm_virtual_network.secondary.name
  remote_virtual_network_id = azurerm_virtual_network.example.id
}

resource "azurerm_network_security_group" "secondary" {
  name                = "secondary-MEDS-nsg"
  location            = local.secondary_replica_location
  resource_group_name = azurerm_resource_group.example.name

  tags = {
    environment = "Production"
  }
}
resource "azurerm_subnet_network_security_group_association" "secondary" {
  subnet_id                 = azurerm_subnet.secondary.id
  network_security_group_id = azurerm_network_security_group.secondary.id
}

########### Third Replica ###########

locals {
  third_replica_location = "italynorth"
}
resource "azurerm_virtual_network" "third" {
  name                = "third-example-network"
  location            = local.third_replica_location
  resource_group_name = azurerm_resource_group.example.name
  address_space       = ["172.16.0.0/16"]
}
resource "azurerm_subnet" "third" {
  name                 = "aadds-subnet-third"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.third.name
  address_prefixes     = ["172.16.0.0/24"]
}
resource "azurerm_virtual_network_peering" "example-3" {
  name                      = "peer1to3"
  resource_group_name       = azurerm_resource_group.example.name
  virtual_network_name      = azurerm_virtual_network.example.name
  remote_virtual_network_id = azurerm_virtual_network.third.id
}
resource "azurerm_virtual_network_peering" "example-4" {
  name                      = "peer3to1"
  resource_group_name       = azurerm_resource_group.example.name
  virtual_network_name      = azurerm_virtual_network.third.name
  remote_virtual_network_id = azurerm_virtual_network.example.id
}

resource "azurerm_network_security_group" "third" {
  name                = "third-MEDS-nsg"
  location            = local.third_replica_location
  resource_group_name = azurerm_resource_group.example.name

  tags = {
    environment = "Production"
  }
}
resource "azurerm_subnet_network_security_group_association" "third" {
  subnet_id                 = azurerm_subnet.third.id
  network_security_group_id = azurerm_network_security_group.third.id
}