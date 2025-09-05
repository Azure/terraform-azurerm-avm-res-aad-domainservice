## Azure Entra Domain Services Deployment Module

This module helps you deploy an Azure Entra Domain Services and its related dependencies. Before using this module, be sure to review the official Azure [Entra Domain Services Documentation](https://learn.microsoft.com/en-us/entra/identity/domain-services/overview).

> [!IMPORTANT]
> As the overall AVM (Azure Verified Module) framework is not yet GA (Generally Available), the CI (Continuous Integration) framework and test automation may not be fully functional across all supported languages. **Breaking changes** are possible. 
> 
> However, this **DOES NOT** imply that the modules are unusable. These modules **CAN** be used in all environments—whether dev, test, or production. Treat them as you would any other Infrastructure-as-Code (IaC) module, and feel free to raise issues or request features as you use the module. Be sure to check the release notes before updating to newer versions to review any breaking changes or considerations.

## Resources Deployed by this Module
- Entra Domain Services
- Replica Sets
- Trusts
- Resource Lock
- IAM (Identity and Access Management)
- NSG Rules

## Resources **NOT** Deployed by this Module
- Entra dependant Service Principal
- Entra dependant Security Groups
- Custom Attributes
- Scoped synchronization and group filter
- OU's

Why do we not deploy these critical parts of the resource? In short, because they are IaC unfriendly and will cause you more pain than good.
However, there is some light at the end of the tunnel, we are working to add these features in an IaC friendyl way, so keep tuned and feel free to submit any suggestion for additional features you might want.

## Deployment Process

1. **Entra dependencies**: Make sure you deploy the [required Entra resources](https://learn.microsoft.com/en-us/entra/identity/domain-services/powershell-create-instance#create-required-microsoft-entra-resources) before you deploy the managed domain.
   
2. **NSG Deployment**: The NSG stubs provided in the module are very basic to enable operation, it is recommended to analyze your exact connectivty needs and make sure only required resources can reach your managed domain.

> **Note**:  The deployment will often take over an hour to complete, make sure your terraform timeouts are configured accordingly.


## Important Notes

- **Replica Removal Issue**: There is currently a bug in the underlying provider for removing replica sets, this is being worked on, however in the meanwhile you must delete replica sets manually [bug report](https://bug-report).

- **provider registration**: This is outside the scope of our module, if you do need to register the provider please refere to the [documentation](https://learn.microsoft.com/en-us/entra/identity/domain-services/powershell-create-instance#create-network-resources).

## Feedback
We welcome your feedback! If you encounter any issues or have feature requests, please raise a bug in the module’s GitHub repository.

---
