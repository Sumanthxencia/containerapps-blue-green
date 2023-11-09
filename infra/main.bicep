targetScope = 'resourceGroup'
param location string = resourceGroup().location

@minLength(1)
@maxLength(64)
@description('Name of containerapp')
param appName string

@minLength(1)
@maxLength(64)
@description('Container environment name')
param containerAppsEnvironmentName string

@minLength(1)
@maxLength(64)
@description('CommitId for blue revision')
param blueCommitId string

@maxLength(64)
@description('CommitId for green revision')
param greenCommitId string = ''

@maxLength(64)
@description('CommitId for the latest deployed revision')
param latestCommitId string = ''

@allowed([
  'blue'
  'green'
])
@description('Name of the label that gets 100% of the traffic')
param productionLabel string = 'blue'

var currentCommitId = !empty(latestCommitId) ? latestCommitId : blueCommitId

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2022-03-01' existing = {
  name: containerAppsEnvironmentName
}

resource blueGreenDeploymentApp 'Microsoft.App/containerApps@2022-11-01-preview' = {
  name: appName
  location: location
  tags: {
    blueCommitId: blueCommitId
    greenCommitId: greenCommitId
    latestCommitId: currentCommitId
    productionLabel: productionLabel
  }
  properties: {
    environmentId: containerAppsEnvironment.id
    workloadProfileName: 'Consumption'
    configuration: {
      maxInactiveRevisions: 10 // Remove old inactive revisions
      activeRevisionsMode: 'multiple' // Multiple active revisions mode is required when using traffic weights
      ingress: {
        external: true
        targetPort: 80
        traffic: !empty(blueCommitId) && !empty(greenCommitId) ? [
          {
            revisionName: '${appName}--${blueCommitId}'
            label: 'blue'
            weight: productionLabel == 'blue' ? 100 : 0
          }
          {
            revisionName: '${appName}--${greenCommitId}'
            label: 'green'
            weight: productionLabel == 'green' ? 100 : 0
          }
        ] : [
          {
            revisionName: '${appName}--${blueCommitId}'
            label: 'blue'
            weight: 100
          }
        ]
      }
    }
    template: {
      revisionSuffix: currentCommitId
      containers:[
        {
          // in the real deployment the image would reference the actual commit id tag, for example:
          // image: 'k8seteste2e.azurecr.io/e2e-apps/test-app:${currentCommitId}'
          image: 'acrfornode.azurecr.io/nodeapp2:latest'
          name: appName
          resources: {
            cpu: json('0.5')
            memory: '1.0Gi'
          }
          env: [
            {
              name: 'REVISION_COMMIT_ID'
              value: currentCommitId
            }
          ]
        }
      ]
       imageRegistryCredentials: [
          {
            server: 'acrfornode.azurecr.io'
            username: '1951a72c-84fd-44f8-82e3-75142ac1974b'
            password: '4ic8Q~hSQQW9c1AzNEO0NLA02e~5KoOCPNGhMcRN'
        }
      ]
     }
    }
  }
}

output fqdn string = blueGreenDeploymentApp.properties.configuration.ingress.fqdn
output latestRevisionName string = blueGreenDeploymentApp.properties.latestRevisionName
