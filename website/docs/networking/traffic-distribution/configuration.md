---
title: "Configuring Traffic Distribution"
sidebar_position: 30
---

Next you’re going to configure Traffic Distribution, then re-run the load test and confirm that the traffic routing is now kept within the same AZs. 

Let’s configure Traffic Distribution on the catalog Service by running the following command: 

```bash
$ kubectl patch service catalog -n catalog -p   '{"spec": {"trafficDistribution": "PreferClose"}}'
```

To confirm that Traffic Distribution is configured you run the following command: 

```bash
$ kubectl get endpointslices -l kubernetes.io/service-name=catalog -n catalog -o yaml
```

You’d get a similar output to the following. If it is configured you should see hints and a corresponding AZ for the various Pods.


Next you’d run the load test again


```bash
$ export UI_ENDPOINT=$(kubectl get service -n ui ui-nlb -o jsonpath="{.status.loadBalancer.ingress[*].hostname}{'\n'}")

$ kubectl run load-generator \
--image=williamyeh/hey:latest \
--restart=Never -- -c 10 -q 5 -z 60m http://$UI_ENDPOINT/home
```

Once this is done navigate back to the [AWS X-Ray Console](https://console.aws.amazon.com/xray/home), and check the visual Trace Map of the traffic flow from client to UI to Catalog.


This time you’d notice that each UI pod is only sending traffic to the Catalog pod in its AZ.
This demonstrates that Traffic Distribution has been configured and is working. 
