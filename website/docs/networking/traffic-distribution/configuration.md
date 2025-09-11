---
title: "Configuring Traffic Distribution"
sidebar_position: 30
---

Next you’re going to configure Traffic Distribution, then re-run the load test and confirm that the traffic routing is now kept within the same AZs. 

Let’s configure Traffic Distribution on the Catalog Service by running the following command: 

```bash
$ kubectl patch service catalog -n catalog -p   '{"spec": {"trafficDistribution": "PreferClose"}}'
```

To confirm that Traffic Distribution is configured you run the following command: 

```bash
$ kubectl get endpointslices -l kubernetes.io/service-name=catalog -n catalog -o yaml
apiVersion: v1
items:
- addressType: IPv4
  apiVersion: discovery.k8s.io/v1
  endpoints:
  - addresses:
    - 10.42.185.86
    hints:
      forZones:
      - name: eu-west-1c
    nodeName: ip-10-42-181-156.eu-west-1.compute.internal
    targetRef:
      kind: Pod
      name: catalog-58f5d94456-qkcmp
      namespace: catalog
      uid: bd8bd6ed-8a53-493b-9595-32af90017c5a
    zone: eu-west-1c
  - addresses:
    - 10.42.150.167
    hints:
      forZones:
      - name: eu-west-1b
    nodeName: ip-10-42-141-139.eu-west-1.compute.internal
    targetRef:
      kind: Pod
      name: catalog-58f5d94456-jgskm
      namespace: catalog
      uid: 14bfc28f-7f7c-41c0-b9b5-39e4e73f1430
    zone: eu-west-1b
  - addresses:
    - 10.42.116.225
    hints:
      forZones:
      - name: eu-west-1a
    nodeName: ip-10-42-117-145.eu-west-1.compute.internal
    targetRef:
      kind: Pod
      name: catalog-58f5d94456-2ltxj
      namespace: catalog
      uid: 582c8a1b-a252-442d-9d10-22ff6c6e866d
    zone: eu-west-1a
  kind: EndpointSlice
```

You’d get a similar output to the above. If it is configured you should see hints and a corresponding AZ for the various Pods.


Next you’d run the load test again


```bash
$ export UI_ENDPOINT=$(kubectl get service -n ui ui-nlb -o jsonpath="{.status.loadBalancer.ingress[*].hostname}{'\n'}")

$ kubectl run load-generator \
--image=williamyeh/hey:latest \
--restart=Never -- -c 10 -q 5 -z 60m http://$UI_ENDPOINT/home
```

Once this is done navigate back to the X-Ray console and check the visual Trace Map of the traffic flow from client to UI to Catalog: 

<ConsoleButton url="https://console.aws.amazon.com/xray/home" service="xray" label="Open X-Ray console"/>


This time you’d notice that each UI pod is only sending traffic to the Catalog pod in its AZ.
This demonstrates that Traffic Distribution has been configured and is working. 


![Architecture Diagram](./assets/trafficdistribution-after.png)
