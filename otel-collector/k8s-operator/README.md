# Python Log Writer Example (Minikube)

This project demonstrates a simple Python application that continuously writes log entries to `/code/app.log` inside a container. The app is containerized with Docker and can be deployed to a Minikube Kubernetes cluster.

## Prerequisites
- Docker
- Minikube installed and running
- kubectl configured to access your Minikube cluster

## 1. Start Minikube

If Minikube is not already running, start it:

```
minikube start
```

## 2. Build the Docker Image Inside Minikube

To make the image available to your Minikube cluster, build it using Minikube's Docker daemon:

```
eval $(minikube docker-env)
docker build -t python-log-writer:latest .
```

## 3. Deploy to Minikube

Apply the deployment manifest:

```
kubectl apply -f k8s-app.yaml
```

## 4. Verify the Deployment

Check the pod status:

```
kubectl get pods -l app=python-log-writer
```

View logs (the app writes to a file, not stdout):

```
kubectl exec -it <pod-name> -- tail -f /code/app.log
```

Replace `<pod-name>` with the actual pod name from the previous command.

## Cleanup

To remove the deployment:

```
kubectl delete -f k8s-app.yaml
```

## (Optional) Minikube Dashboard

To open the Minikube dashboard for a visual overview:

```
minikube dashboard
``` 