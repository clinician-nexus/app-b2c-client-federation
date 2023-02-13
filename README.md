# app-b2c-client-federation
Scripts and documentation to assist with federating external identities to Clinician Nexus.

### AzureAD_ExtIDP_Provisioning.ps1
During federation a new Azure AD App Registration is created. This script is used during the creation of this App Registration to address the shortcomings in the Azure Portal UI. It will create a custom claims mapping policy, attach it to the new app registration, and add a long-lived secret for the Authorization Code flow. This script relies on and installs the [Azure AD Preview](https://www.powershellgallery.com/packages/AzureADPreview/) module because claims mapping methods are still in preview.

**Prerequisites**

- Azure AD Global Administrator permissions or permissions to manage app registrations and claims mappings
- An existing app registration created for the purpose of federation to Clinician Nexus.

**How To Use**

Download and run the script. The following steps will take place:
- The Azure AD Preview module will be installed or updated if not available and at a minimum version.
- The user will be prompted to login to Azure AD. An account with sufficient permissions should be used.
- The user will be presented with a list of Service Principals and asked to choose the one associated with the new Clinician Nexus app registration.
- A new Azure AD Claims mapping policy will be created with the name: `ClinicianNexus_Mapping_Policy_<CurrentDateTime>`
- Remove and existing mapping policy that may be attached to the app.
- Attach the new claims mapping policy to the app.
- Create a long lived secret for the Authorization Code flow used in openID Connect / OAuth integration.

If the script fails, it will attempt to rollback and undo the changes made.

**Outputs**

This script will output the secret key which must be recorded for subsequent steps in coordination with Clinician Nexus.

