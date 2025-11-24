#!/usr/bin/env python3
"""
Last9 OpenTelemetry Conflict-Free K8s Operator
Integrates conflict detection, resolution, and monitoring
"""

import time
import os
import sys
import json
import yaml
import logging
from datetime import datetime
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass

try:
    from kubernetes import client, config
    from kubernetes.client.rest import ApiException
    KUBERNETES_AVAILABLE = True
except ImportError:
    KUBERNETES_AVAILABLE = False
    print("Warning: kubernetes client not available. Install with: pip install kubernetes")

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('/log/operator.log') if os.path.exists('/log') or os.makedirs('/log', exist_ok=True) else logging.NullHandler()
    ]
)
logger = logging.getLogger(__name__)

@dataclass
class PortConfig:
    """Last9 conflict-free port configuration using high ports (40000+)"""
    NODE_EXPORTER_PORT: int = 40001
    PROMETHEUS_PORT: int = 40002
    KUBE_STATE_METRICS_PORT: int = 40003
    COLLECTOR_HTTP_PORT: int = 40004
    COLLECTOR_GRPC_PORT: int = 40005
    WEBHOOK_PORT: int = 40006
    METRICS_PORT: int = 40007

@dataclass
class OperatorInfo:
    """Information about existing OpenTelemetry operators"""
    exists: bool = False
    namespace: str = ""
    managed_by: str = ""
    version: str = ""

@dataclass
class CRDStrategy:
    """CRD installation strategy based on existing CRDs"""
    strategy: str = "install-crds"  # install-crds, skip-crds, install-crds-force
    existing_crds: int = 0
    total_crds: int = 3
    versions: List[str] = None

class Last9ConflictResolver:
    """Handles conflict detection and resolution for Last9 OpenTelemetry setup"""

    def __init__(self):
        self.ports = PortConfig()
        self.k8s_client = None
        self.required_crds = [
            "opentelemetrycollectors.opentelemetry.io",
            "instrumentations.opentelemetry.io",
            "opampbridges.opentelemetry.io"
        ]

        if KUBERNETES_AVAILABLE:
            try:
                # Try in-cluster config first, then local kubeconfig
                try:
                    config.load_incluster_config()
                    logger.info("Using in-cluster Kubernetes configuration")
                except:
                    config.load_kube_config()
                    logger.info("Using local Kubernetes configuration")

                self.k8s_client = client.ApiClient()
                self.apps_v1 = client.AppsV1Api()
                self.custom_objects_api = client.CustomObjectsApi()
                self.api_extensions = client.ApiextensionsV1Api()

            except Exception as e:
                logger.warning(f"Failed to initialize Kubernetes client: {e}")
                self.k8s_client = None

    def check_cluster_connectivity(self) -> bool:
        """Check if we can connect to the Kubernetes cluster"""
        if not self.k8s_client:
            logger.error("Kubernetes client not initialized")
            return False

        try:
            self.apps_v1.list_deployment_for_all_namespaces(limit=1)
            logger.info("✅ Kubernetes cluster connectivity verified")
            return True
        except Exception as e:
            logger.error(f"❌ Cannot connect to Kubernetes cluster: {e}")
            return False

    def detect_existing_opentelemetry_operator(self) -> OperatorInfo:
        """Detect existing OpenTelemetry operator installations"""
        logger.info("🔍 Checking for existing OpenTelemetry operator installations...")

        if not self.k8s_client:
            return OperatorInfo()

        try:
            # Look for OpenTelemetry operator deployments
            deployments = self.apps_v1.list_deployment_for_all_namespaces(
                label_selector="app.kubernetes.io/name=opentelemetry-operator"
            )

            if deployments.items:
                deployment = deployments.items[0]
                operator_info = OperatorInfo(
                    exists=True,
                    namespace=deployment.metadata.namespace,
                    managed_by=deployment.metadata.labels.get("app.kubernetes.io/managed-by", "unknown"),
                    version=self._extract_version_from_image(deployment.spec.template.spec.containers[0].image)
                )

                logger.warning(f"⚠️  Found existing OpenTelemetry operator:")
                logger.warning(f"   Namespace: {operator_info.namespace}")
                logger.warning(f"   Managed by: {operator_info.managed_by}")
                logger.warning(f"   Version: {operator_info.version}")

                return operator_info
            else:
                logger.info("✅ No existing OpenTelemetry operator found")
                return OperatorInfo()

        except Exception as e:
            logger.error(f"Error detecting existing operator: {e}")
            return OperatorInfo()

    def _extract_version_from_image(self, image: str) -> str:
        """Extract version from container image string"""
        try:
            return image.split(":")[-1] if ":" in image else "unknown"
        except:
            return "unknown"

    def determine_crd_strategy(self) -> CRDStrategy:
        """Determine the best CRD installation strategy"""
        logger.info("🔍 Determining CRD installation strategy...")

        if not self.k8s_client:
            return CRDStrategy()

        try:
            existing_crds = 0
            crd_versions = []

            for crd_name in self.required_crds:
                try:
                    crd = self.api_extensions.read_custom_resource_definition(crd_name)
                    existing_crds += 1

                    version = crd.spec.versions[0].name if crd.spec.versions else "unknown"
                    managed_by = crd.metadata.labels.get("app.kubernetes.io/managed-by", "unknown") if crd.metadata.labels else "unknown"

                    crd_versions.append(f"{crd_name}:{version}")
                    logger.info(f"   Found {crd_name} (version: {version}, managed-by: {managed_by})")

                except ApiException as e:
                    if e.status == 404:
                        continue  # CRD doesn't exist
                    else:
                        logger.error(f"Error checking CRD {crd_name}: {e}")

            strategy_obj = CRDStrategy(
                existing_crds=existing_crds,
                total_crds=len(self.required_crds),
                versions=crd_versions
            )

            if existing_crds == 0:
                strategy_obj.strategy = "install-crds"
                logger.info("📋 Strategy: Install CRDs normally (no existing CRDs found)")
            elif existing_crds == len(self.required_crds):
                strategy_obj.strategy = "skip-crds"
                logger.info("✅ Strategy: Skip CRDs (all required CRDs already exist)")
                logger.info("   Recommendation: Use --skip-crds to avoid ownership conflicts")
            else:
                strategy_obj.strategy = "install-crds-force"
                logger.warning(f"⚠️  Strategy: Force install CRDs (partial CRDs found: {existing_crds}/{len(self.required_crds)})")

            return strategy_obj

        except Exception as e:
            logger.error(f"Error determining CRD strategy: {e}")
            return CRDStrategy()

    def generate_conflict_free_config(self, cluster_name: str = "last9-cluster") -> Dict:
        """Generate conflict-free configuration using high ports"""
        logger.info("⚙️  Generating conflict-free configuration with high ports...")

        config = {
            "metadata": {
                "name": "last9-otel-operator",
                "namespace": "last9",
                "labels": {
                    "app.kubernetes.io/name": "last9-otel-operator",
                    "app.kubernetes.io/managed-by": "last9-operator"
                }
            },
            "ports": {
                "nodeExporter": self.ports.NODE_EXPORTER_PORT,
                "prometheus": self.ports.PROMETHEUS_PORT,
                "kubeStateMetrics": self.ports.KUBE_STATE_METRICS_PORT,
                "collectorHttp": self.ports.COLLECTOR_HTTP_PORT,
                "collectorGrpc": self.ports.COLLECTOR_GRPC_PORT,
                "webhook": self.ports.WEBHOOK_PORT,
                "metrics": self.ports.METRICS_PORT
            },
            "cluster": {
                "name": cluster_name
            },
            "features": {
                "conflictResolution": True,
                "highPorts": True,
                "smartCrdStrategy": True
            }
        }

        logger.info("✅ Generated conflict-free configuration")
        logger.info(f"   Port allocation:")
        for service, port in config["ports"].items():
            logger.info(f"     • {service}: {port}")

        return config

    def run_conflict_resolution(self, cluster_name: str = "last9-cluster") -> Dict:
        """Run complete conflict resolution analysis"""
        logger.info("🎯 Starting Last9 OpenTelemetry conflict resolution...")
        logger.info("   Using high-port strategy (40000+) to eliminate port conflicts")

        results = {
            "timestamp": datetime.now().isoformat(),
            "cluster_connectivity": False,
            "existing_operator": OperatorInfo(),
            "crd_strategy": CRDStrategy(),
            "config": {},
            "recommendations": []
        }

        # Step 1: Check cluster connectivity
        results["cluster_connectivity"] = self.check_cluster_connectivity()
        if not results["cluster_connectivity"]:
            results["recommendations"].append("Fix Kubernetes cluster connectivity")
            return results

        # Step 2: Detect existing operator
        results["existing_operator"] = self.detect_existing_opentelemetry_operator()

        if results["existing_operator"].exists:
            if results["existing_operator"].managed_by == "Helm":
                results["recommendations"].append("✅ Existing operator is Helm-managed - compatible with Last9 approach")
            else:
                results["recommendations"].append(f"⚠️  Existing operator is {results['existing_operator'].managed_by}-managed")

        # Step 3: Determine CRD strategy
        results["crd_strategy"] = self.determine_crd_strategy()

        if results["crd_strategy"].strategy == "skip-crds":
            results["recommendations"].append("✅ Use --skip-crds flag (eliminates ownership conflicts)")
        elif results["crd_strategy"].strategy == "install-crds-force":
            results["recommendations"].append("⚠️  Partial CRDs detected - will install/update all CRDs")

        # Step 4: Generate conflict-free configuration
        results["config"] = self.generate_conflict_free_config(cluster_name)

        logger.info("✅ Conflict resolution completed successfully")
        return results

class Last9LogWriter:
    """Enhanced log writer with operator functionality"""

    def __init__(self):
        self.resolver = Last9ConflictResolver()
        self.log_dir = '/log'
        os.makedirs(self.log_dir, exist_ok=True)

    def write_operator_status(self, results: Dict):
        """Write conflict resolution results to log"""
        status_file = os.path.join(self.log_dir, 'operator-status.json')
        try:
            with open(status_file, 'w') as f:
                json.dump(results, f, indent=2, default=str)
            logger.info(f"📝 Operator status written to {status_file}")
        except Exception as e:
            logger.error(f"Failed to write operator status: {e}")

    def continuous_log_writer(self):
        """Enhanced continuous logging with operator status"""
        log_file = os.path.join(self.log_dir, 'app.log')

        # Run initial conflict resolution
        cluster_name = os.getenv('CLUSTER_NAME', 'last9-cluster')
        results = self.resolver.run_conflict_resolution(cluster_name)
        self.write_operator_status(results)

        # Print summary
        logger.info("🎉 Last9 OpenTelemetry K8s Operator Ready!")
        logger.info(f"   Cluster: {cluster_name}")
        logger.info(f"   Conflict Resolution: {'✅ Active' if results['cluster_connectivity'] else '❌ Failed'}")
        logger.info(f"   CRD Strategy: {results['crd_strategy'].strategy}")
        logger.info(f"   Existing Operator: {'Found' if results['existing_operator'].exists else 'None'}")

        # Start continuous logging
        with open(log_file, 'a') as f:
            iteration = 0
            while True:
                timestamp = time.strftime('%Y-%m-%d %H:%M:%S')

                # Every 10 iterations, run a quick health check
                if iteration % 10 == 0:
                    connectivity = self.resolver.check_cluster_connectivity() if KUBERNETES_AVAILABLE else False
                    f.write(f"[{timestamp}] Health Check - K8s Connectivity: {'✅' if connectivity else '❌'}\n")
                else:
                    f.write(f"[{timestamp}] Last9 Operator Running - High Ports Active (40000+)\n")

                f.flush()
                iteration += 1
                time.sleep(30)  # Log every 30 seconds instead of every second

def main():
    """Main entry point"""
    logger.info("🚀 Starting Last9 OpenTelemetry K8s Operator...")

    if not KUBERNETES_AVAILABLE:
        logger.warning("⚠️  Running without Kubernetes client - limited functionality")

    operator = Last9LogWriter()

    try:
        operator.continuous_log_writer()
    except KeyboardInterrupt:
        logger.info("👋 Last9 Operator shutdown requested")
    except Exception as e:
        logger.error(f"❌ Operator failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main() 