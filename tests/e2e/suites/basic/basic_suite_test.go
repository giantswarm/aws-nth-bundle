package basic

import (
	"fmt"
	"testing"
	"time"

	"e2e/internal/testhelpers"

	"github.com/giantswarm/apptest-framework/v3/pkg/state"
	"github.com/giantswarm/apptest-framework/v3/pkg/suite"
	"github.com/giantswarm/clustertest/v3/pkg/failurehandler"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/types"
	capiexp "sigs.k8s.io/cluster-api/exp/api/v1beta1"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

const (
	isUpgrade = false
)

func TestBasic(t *testing.T) {
	var (
		targetNodeName  string
		initialReplicas int32
		machinePoolName string
		machinePoolNS   string
	)

	suite.New().
		WithInCluster(true).
		WithInstallNamespace("").
		WithIsUpgrade(isUpgrade).
		WithValuesFile("./values.yaml").
		Tests(func() {
			// --- Basic health checks ---

			It("should have the HelmRelease ready on the management cluster", func() {
				mcClient := state.GetFramework().MC()
				clusterName := state.GetCluster().Name
				orgName := state.GetCluster().Organization.Name

				Eventually(func() (bool, error) {
					ready, err := testhelpers.HelmReleaseIsReady(*mcClient, clusterName, orgName)
					if err != nil {
						GinkgoLogr.Info("HelmRelease check failed", "error", err.Error())
					} else if !ready {
						GinkgoLogr.Info("HelmRelease not ready yet", "name", clusterName+"-aws-node-termination-handler")
					} else {
						GinkgoLogr.Info("HelmRelease is ready", "name", clusterName+"-aws-node-termination-handler")
					}
					return ready, err
				}).
					WithTimeout(15 * time.Minute).
					WithPolling(10 * time.Second).
					Should(BeTrue(), failurehandler.LLMPrompt(state.GetFramework(), state.GetCluster(), "Investigate HelmRelease not ready for aws-node-termination-handler"))
			})

			It("should have the aws-node-termination-handler deployment running", func() {
				wcClient, err := state.GetFramework().WC(state.GetCluster().Name)
				Expect(err).Should(Succeed())

				Eventually(func() error {
					var dp appsv1.Deployment
					err := wcClient.Get(state.GetContext(), types.NamespacedName{
						Namespace: "kube-system",
						Name:      "aws-node-termination-handler",
					}, &dp)
					if err != nil {
						GinkgoLogr.Info("aws-node-termination-handler not found yet", "error", err.Error())
					} else {
						GinkgoLogr.Info("aws-node-termination-handler found",
							"replicas", dp.Status.Replicas,
							"ready", dp.Status.ReadyReplicas,
							"available", dp.Status.AvailableReplicas,
						)
					}
					return err
				}).
					WithTimeout(10 * time.Minute).
					WithPolling(5 * time.Second).
					ShouldNot(HaveOccurred(), failurehandler.LLMPrompt(state.GetFramework(), state.GetCluster(), "Investigate aws-node-termination-handler deployment not found or not running"))
			})

			It("should have at least one ready replica", func() {
				wcClient, err := state.GetFramework().WC(state.GetCluster().Name)
				Expect(err).Should(Succeed())

				Eventually(func() (int32, error) {
					var dp appsv1.Deployment
					err := wcClient.Get(state.GetContext(), types.NamespacedName{
						Namespace: "kube-system",
						Name:      "aws-node-termination-handler",
					}, &dp)
					if err != nil {
						return 0, err
					}
					GinkgoLogr.Info("deployment replicas", "ready", dp.Status.ReadyReplicas, "desired", *dp.Spec.Replicas)
					return dp.Status.ReadyReplicas, nil
				}).
					WithTimeout(10 * time.Minute).
					WithPolling(5 * time.Second).
					Should(BeNumerically(">=", int32(1)), failurehandler.LLMPrompt(state.GetFramework(), state.GetCluster(), "Investigate aws-node-termination-handler has no ready replicas"))
			})

			// --- Functional: ASG scale-in tests ---

			It("should have at least 2 worker nodes", func() {
				wcClient, err := state.GetFramework().WC(state.GetCluster().Name)
				Expect(err).NotTo(HaveOccurred())

				nodes := &corev1.NodeList{}
				err = wcClient.List(state.GetContext(), nodes)
				Expect(err).NotTo(HaveOccurred())

				workerNodes := filterWorkerNodes(nodes.Items)
				Expect(len(workerNodes)).To(BeNumerically(">=", 2),
					"need at least 2 worker nodes to safely scale down")
				GinkgoLogr.Info("worker nodes found", "count", len(workerNodes))
			})

			It("should find a MachinePool to scale down", func() {
				mcClient := state.GetFramework().MC()
				clusterName := state.GetCluster().Name
				machinePoolNS = state.GetCluster().Organization.GetNamespace()

				mpList := &capiexp.MachinePoolList{}
				err := mcClient.List(state.GetContext(), mpList,
					client.InNamespace(machinePoolNS),
					client.MatchingLabels{"cluster.x-k8s.io/cluster-name": clusterName},
				)
				Expect(err).NotTo(HaveOccurred())
				Expect(mpList.Items).NotTo(BeEmpty(), "no MachinePools found for cluster %s", clusterName)

				// Pick the first MachinePool with replicas > 1
				found := false
				for _, mp := range mpList.Items {
					if mp.Spec.Replicas != nil && *mp.Spec.Replicas > 1 {
						machinePoolName = mp.Name
						initialReplicas = *mp.Spec.Replicas
						found = true
						break
					}
				}
				Expect(found).To(BeTrue(), "no MachinePool with >1 replicas found")
				GinkgoLogr.Info("target MachinePool selected",
					"name", machinePoolName,
					"namespace", machinePoolNS,
					"replicas", initialReplicas)
			})

			It("should record the target node before scale-down", func() {
				wcClient, err := state.GetFramework().WC(state.GetCluster().Name)
				Expect(err).NotTo(HaveOccurred())

				nodes := &corev1.NodeList{}
				err = wcClient.List(state.GetContext(), nodes)
				Expect(err).NotTo(HaveOccurred())

				workerNodes := filterWorkerNodes(nodes.Items)
				// Record the last worker node as the expected target for removal
				targetNodeName = workerNodes[len(workerNodes)-1].Name
				GinkgoLogr.Info("target node recorded", "node", targetNodeName)
			})

			It("should scale down the MachinePool", func() {
				mcClient := state.GetFramework().MC()
				mp := &capiexp.MachinePool{}
				err := mcClient.Get(state.GetContext(), types.NamespacedName{
					Name:      machinePoolName,
					Namespace: machinePoolNS,
				}, mp)
				Expect(err).NotTo(HaveOccurred())

				newReplicas := initialReplicas - 1
				mp.Spec.Replicas = &newReplicas
				err = mcClient.Update(state.GetContext(), mp)
				Expect(err).NotTo(HaveOccurred())
				GinkgoLogr.Info("MachinePool scaled down",
					"name", machinePoolName,
					"from", initialReplicas,
					"to", newReplicas)
			})

			It("should detect NTH cordoning a node", func() {
				wcClient, err := state.GetFramework().WC(state.GetCluster().Name)
				Expect(err).NotTo(HaveOccurred())

				Eventually(func() (string, error) {
					nodes := &corev1.NodeList{}
					if err := wcClient.List(state.GetContext(), nodes); err != nil {
						return "", err
					}
					for _, node := range filterWorkerNodes(nodes.Items) {
						if node.Spec.Unschedulable {
							GinkgoLogr.Info("node cordoned by NTH", "node", node.Name)
							targetNodeName = node.Name
							return node.Name, nil
						}
					}
					return "", nil
				}).
					WithTimeout(8 * time.Minute).
					WithPolling(10 * time.Second).
					ShouldNot(BeEmpty(),
						failurehandler.LLMPrompt(state.GetFramework(), state.GetCluster(),
							"NTH did not cordon any node after MachinePool scale-down"))
			})

			It("should drain the cordoned node (no non-daemonset pods remain)", func() {
				wcClient, err := state.GetFramework().WC(state.GetCluster().Name)
				Expect(err).NotTo(HaveOccurred())

				Eventually(func() (int, error) {
					pods := &corev1.PodList{}
					if err := wcClient.List(state.GetContext(), pods); err != nil {
						return -1, err
					}
					count := 0
					for _, pod := range pods.Items {
						if pod.Spec.NodeName != targetNodeName {
							continue
						}
						if isDaemonSetPod(pod) || isMirrorPod(pod) {
							continue
						}
						if pod.DeletionTimestamp != nil {
							continue
						}
						count++
					}
					GinkgoLogr.Info("non-daemonset pods on cordoned node",
						"node", targetNodeName, "count", count)
					return count, nil
				}).
					WithTimeout(5 * time.Minute).
					WithPolling(10 * time.Second).
					Should(Equal(0),
						failurehandler.LLMPrompt(state.GetFramework(), state.GetCluster(),
							fmt.Sprintf("NTH did not drain all pods from node %s", targetNodeName)))
			})

			It("should remove the node from the cluster", func() {
				wcClient, err := state.GetFramework().WC(state.GetCluster().Name)
				Expect(err).NotTo(HaveOccurred())

				Eventually(func() (bool, error) {
					node := &corev1.Node{}
					err := wcClient.Get(state.GetContext(), types.NamespacedName{
						Name: targetNodeName,
					}, node)
					if err != nil {
						GinkgoLogr.Info("node removed from cluster", "node", targetNodeName)
						return true, nil
					}
					GinkgoLogr.Info("node still present", "node", targetNodeName)
					return false, nil
				}).
					WithTimeout(10 * time.Minute).
					WithPolling(15 * time.Second).
					Should(BeTrue(),
						failurehandler.LLMPrompt(state.GetFramework(), state.GetCluster(),
							fmt.Sprintf("Node %s was not removed after scale-down", targetNodeName)))
			})

			It("should verify HelmRelease remained healthy throughout", func() {
				mcClient := state.GetFramework().MC()
				clusterName := state.GetCluster().Name
				orgName := state.GetCluster().Organization.Name

				ready, err := testhelpers.HelmReleaseIsReady(*mcClient, clusterName, orgName)
				Expect(err).NotTo(HaveOccurred())
				Expect(ready).To(BeTrue())
				GinkgoLogr.Info("HelmRelease still healthy after scale-down")
			})
		}).
		AfterSuite(func() {
			// Restore the original replica count so the cluster is healthy for teardown
			if machinePoolName == "" {
				return
			}
			mcClient := state.GetFramework().MC()
			mp := &capiexp.MachinePool{}
			err := mcClient.Get(state.GetContext(), types.NamespacedName{
				Name:      machinePoolName,
				Namespace: machinePoolNS,
			}, mp)
			if err != nil {
				GinkgoLogr.Error(err, "failed to get MachinePool for restore")
				return
			}
			if mp.Spec.Replicas != nil && *mp.Spec.Replicas < initialReplicas {
				mp.Spec.Replicas = &initialReplicas
				if err := mcClient.Update(state.GetContext(), mp); err != nil {
					GinkgoLogr.Error(err, "failed to restore MachinePool replicas")
				} else {
					GinkgoLogr.Info("MachinePool replicas restored",
						"name", machinePoolName, "replicas", initialReplicas)
				}
			}
		}).
		Run(t, "Node Termination Handler")
}

// filterWorkerNodes returns nodes that are not control-plane.
func filterWorkerNodes(nodes []corev1.Node) []corev1.Node {
	var workers []corev1.Node
	for _, node := range nodes {
		if _, ok := node.Labels["node-role.kubernetes.io/control-plane"]; ok {
			continue
		}
		workers = append(workers, node)
	}
	return workers
}

// isDaemonSetPod returns true if the pod is owned by a DaemonSet.
func isDaemonSetPod(pod corev1.Pod) bool {
	for _, ref := range pod.OwnerReferences {
		if ref.Kind == "DaemonSet" {
			return true
		}
	}
	return false
}

// isMirrorPod returns true if the pod is a static/mirror pod.
func isMirrorPod(pod corev1.Pod) bool {
	_, ok := pod.Annotations["kubernetes.io/config.mirror"]
	return ok
}
