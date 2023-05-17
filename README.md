# GitOps repository

# Structure:

- apps: Contains the ArgoCD application definitions
- components: Contains custom kubernetes manifests used to define the cluster's components, such as Kafka Clusters, our software and others. 
- projects: Contains the ArgoCD project definitions

# Summary:

The app of apps will deploy changes of the CRDs to the ArgoCD cluster automatically, the only thing that needs to be manually applied is that app of apps CRD.

The life of a deployed application:
    - Written by developer
    - It is deployed to staging
    - Once tested on staging, it is deployed to production.

TL;DR Staging = Main branch Head and Prod = prod branch

# How to deploy the app of apps

This will deploy everything using ArgoCD by deploying an application that will deploy everything in the apps folder of this repo.

```bash
kubectl config use-context k0s-cluster-ci-cd
kubectl apply -f apps/app_of_apps/deployment.yml
```

# Deploying to staging

Add a new application CRD to the apps folder, this application CRD should be include the following stats:

- Project staging
- Branch: main (HEAD)

# Deploying to production

Push the wanted changed to the prod branch

- Project: production
- Branch: prod
