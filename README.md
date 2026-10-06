# secure-container-release
# Secure Container Release Pipeline

## Project Overview

This project demonstrates how container security can be integrated into an Azure DevOps CI/CD pipeline.

The goal was to build a container image, scan it for vulnerabilities, generate an SBOM, enforce a security gate, and only push approved images to Azure Container Registry.

The pipeline was designed so that vulnerable images are stopped before they reach the container registry.

## Technologies Used

- Docker
- Trivy
- Azure DevOps
- Azure Pipelines
- Azure Container Registry
- Microsoft Entra ID
- Azure RBAC / ABAC
- Workload Identity Federation
- CycloneDX SBOM

## What I Learned

During this project, I practiced:

- Building container images in Azure Pipelines
- Scanning container images with Trivy
- Detecting HIGH and CRITICAL vulnerabilities
- Generating vulnerability reports
- Generating Software Bill of Materials files
- Creating CI/CD security gates
- Preventing vulnerable images from being published
- Authenticating Azure Pipelines using Workload Identity Federation
- Assigning least-privilege permissions to Azure Container Registry
- Publishing pipeline security artifacts
- Handling vulnerabilities that do not currently have fixes
- Pushing approved container images to ACR

## Project Architecture

```text
Developer
    |
    v
Git Repository
    |
    v
Azure Pipeline
    |
    v
Docker Build
    |
    v
Trivy Vulnerability Scan
    |
    +----> Vulnerability Report
    |
    +----> SBOM
    |
    v
Security Gate
    |
    +---- HIGH/CRITICAL fixable vulnerability ----> FAIL
    |
    v
Approved Image
    |
    v
Azure Container Registry
```

## Project Structure

```text
secure-container-release/
|
├── app.py
├── requirements.txt
├── Dockerfile
├── .dockerignore
├── azure-pipelines.yml
└── security-results/
```

## Create the Azure Resources

Set the project variables:

```bash
RG="rg-container-security"

LOCATION="canadacentral"

ACR_NAME="cssecure$RANDOM$RANDOM"
```

Create the resource group:

```bash
az group create \
  --name "$RG" \
  --location "$LOCATION"
```

Create Azure Container Registry:

```bash
az acr create \
  --resource-group "$RG" \
  --name "$ACR_NAME" \
  --sku Basic \
  --admin-enabled false
```

Verify the registry:

```bash
az acr show \
  --name "$ACR_NAME" \
  --query "{name:name,loginServer:loginServer,id:id}" \
  --output table
```

## Check the ACR Permission Model

```bash
az acr show \
  --name "$ACR_NAME" \
  --query roleAssignmentMode \
  --output tsv
```

Depending on the registry permission model, the pipeline identity may require either:

```text
Container Registry Repository Writer
```

or:

```text
AcrPush
```

## Azure DevOps Service Connection

An Azure Resource Manager service connection was created using:

```text
Workload Identity Federation
```

Service connection name:

```text
sc-container-security
```

This allows Azure Pipelines to authenticate to Azure without storing a long-lived client secret.

## Find the Service Principal Object ID

If the Application/Client ID is known:

```bash
SP_OBJECT_ID=$(az ad sp show \
  --id "<APPLICATION-CLIENT-ID>" \
  --query id \
  --output tsv)

echo "$SP_OBJECT_ID"
```

## Get the ACR Resource ID

```bash
ACR_ID=$(az acr show \
  --name "$ACR_NAME" \
  --query id \
  --output tsv)
```

## Assign Registry Permissions

For an ABAC-enabled registry:

```bash
az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Container Registry Repository Writer" \
  --scope "$ACR_ID"
```

For a classic RBAC registry:

```bash
az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "AcrPush" \
  --scope "$ACR_ID"
```

## Container Security Pipeline

The pipeline performs the following stages:

```text
Checkout source
      |
      v
Build Docker image
      |
      v
Generate vulnerability report
      |
      v
Generate SBOM
      |
      v
Publish security artifacts
      |
      v
Run security gate
      |
      v
Push approved image to ACR
      |
      v
Verify image
```

## Build the Container Image

The pipeline builds the image using:

```bash
docker build \
  --pull \
  -t secure-api:<BUILD-ID> \
  .
```

Using a unique build ID creates a separate image tag for each pipeline run.

## Vulnerability Scanning

Trivy is used to scan the built container image.

Example:

```bash
trivy image secure-api:test
```

Scan only HIGH and CRITICAL vulnerabilities:

```bash
trivy image \
  --severity HIGH,CRITICAL \
  secure-api:test
```

## Generate the Vulnerability Report

The pipeline generates a JSON security report:

```bash
trivy image \
  --format json \
  --output trivy-report.json \
  secure-api:test
```

This provides security evidence that can be stored with the pipeline run.

## Generate the SBOM

A CycloneDX Software Bill of Materials is generated with:

```bash
trivy image \
  --format cyclonedx \
  --output sbom.cdx.json \
  secure-api:test
```

The SBOM identifies software packages and dependencies included in the container image.

## Security Gate

The pipeline initially blocked all HIGH and CRITICAL vulnerabilities:

```bash
trivy image \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  secure-api:test
```

If vulnerabilities were discovered, Trivy returned:

```text
exit code 1
```

This caused Azure Pipelines to stop.

## Handling Unfixed Vulnerabilities

During testing, several vulnerabilities were detected in operating system packages where no vendor fix was currently available.

The security gate was therefore updated to block only HIGH and CRITICAL vulnerabilities that have available fixes:

```bash
trivy image \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  --exit-code 1 \
  secure-api:test
```

This allows the project to maintain visibility of all vulnerabilities while preventing fixable serious vulnerabilities from reaching the registry.

The full security report still records all detected vulnerabilities.

## Security Policy

The final security policy follows this model:

```text
All vulnerabilities
        |
        v
Record in security report
        |
        v
Is HIGH or CRITICAL?
        |
       Yes
        |
        v
Is a fix available?
   /            \
 Yes             No
  |               |
  v               v
FAIL           Record
pipeline       finding
```

## Push Approved Image to ACR

The image is only pushed after the security gate succeeds.

Login:

```bash
az acr login \
  --name "$ACR_NAME"
```

Get the registry login server:

```bash
LOGIN_SERVER=$(az acr show \
  --name "$ACR_NAME" \
  --query loginServer \
  --output tsv)
```

Tag the image:

```bash
docker tag \
  secure-api:test \
  "$LOGIN_SERVER/secure-api:test"
```

Push:

```bash
docker push \
  "$LOGIN_SERVER/secure-api:test"
```

## Verify the Image in ACR

```bash
az acr repository show-tags \
  --name "$ACR_NAME" \
  --repository secure-api \
  --orderby time_desc \
  --output table
```

## Security Artifacts

The pipeline publishes:

```text
container-security-results/
|
├── trivy-report.json
└── sbom.cdx.json
```

These artifacts can be reviewed from the Azure DevOps pipeline run.

## Security Controls Implemented

This project implemented:

- Hardened Docker image
- Automated vulnerability scanning
- HIGH and CRITICAL vulnerability detection
- Security gate enforcement
- SBOM generation
- Security report publishing
- Workload Identity Federation
- Least-privilege ACR permissions
- Unique container image tags
- Protection against publishing vulnerable container images

## Troubleshooting

### Pipeline Fails During the Security Gate

Example:

```text
##[error]Bash exited with code '1'
```

This means Trivy found a vulnerability that matched the security policy.

Inspect the findings:

```bash
trivy image \
  --severity HIGH,CRITICAL \
  secure-api:test
```

## Unfixed Vulnerabilities Block the Pipeline

If vulnerabilities are marked:

```text
affected
will_not_fix
fix_deferred
```

and no vendor patch exists, use:

```bash
--ignore-unfixed
```

Example:

```bash
trivy image \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  --exit-code 1 \
  secure-api:test
```

The vulnerability should still remain visible in the full security report.

## ACR Push Returns Unauthorized

Verify Azure login:

```bash
az account show
```

Check registry permissions:

```bash
az role assignment list \
  --assignee "$SP_OBJECT_ID" \
  --scope "$ACR_ID" \
  --output table
```

Check the registry permission model:

```bash
az acr show \
  --name "$ACR_NAME" \
  --query roleAssignmentMode \
  --output tsv
```

## Image Cannot Be Found by Trivy

Verify that the image was built:

```bash
docker images
```

Ensure the scan uses the same tag used by the build:

```text
secure-api:<BUILD-ID>
```

## Verify the Container Image Digest

```bash
az acr repository show \
  --name "$ACR_NAME" \
  --image secure-api:<BUILD-ID> \
  --query digest \
  --output tsv
```

The digest uniquely identifies the exact image content.

## Cleanup

Delete the resource group and all project resources:

```bash
az group delete \
  --name "$RG" \
  --yes \
  --no-wait
```

## Project Outcome

This project provided hands-on experience implementing container security directly inside a CI/CD pipeline.

Instead of simply building and publishing container images, the pipeline now performs security validation before release.

The final workflow follows a DevSecOps model:

```text
Build
  |
  v
Scan
  |
  v
Generate SBOM
  |
  v
Evaluate Security Policy
  |
  v
Approve or Reject
  |
  v
Publish Trusted Image
```

This project demonstrates how container vulnerability scanning, identity security, least privilege, security gates, SBOMs, Docker, Azure Pipelines, and Azure Container Registry can work together to create a more secure software supply chain.