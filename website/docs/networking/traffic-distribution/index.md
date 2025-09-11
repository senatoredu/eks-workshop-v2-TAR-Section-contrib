---
title: "Traffic Distribution"
sidebar_position: 60
chapter: true
weight: 10
---

When deploying applications in Kubernetes an often followed best practice is to spread the pods across multiple zones, this provides fault tolerance and redundancy benefits such that if a zone goes down the application continues to operate through the pods in the other zone.
In AWS the term for zone is [Availability Zones (AZ)] (https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-regions-availability-zones.html) which is an isolated location within an [AWS Region] (https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-regions-availability-zones.html), the AZs are designed to be isolated from each other and separated by a meaningful distance to prevent correlated failures.
While designing for Multi-AZ provides fault tolerance and redundancy benefits there are also data-transfer cost and inter-AZ latency factors one might consider for very latency sensitive workloads or inter-AZ data transfer cost reasons. 

[Traffic Distribution] (https://kubernetes.io/docs/reference/networking/virtual-ips/#traffic-distribution) is a Kubernetes feature launched in version 1.31 that provides Kubernetes admins the ability to decide their preference for how traffic should be routed to endpoint pods in a Service. 

Depending on the value of the `spec.trafficDistribution` field you can influence how traffic should be sent to Service endpoints. If the value is set to `PreferClose` then this will prioritize sending traffic to endpoints in the same zone as the client, and if the value is set to `PreferSameNode` then this will prioritize sending traffic to endpoints on the same node as the client. 

In the default state where `trafficDistribution` isn’t configured then traffic is sent to endpoint pods without considering any distribution preference and traffic can be routed to any pod.

In this chapter we would demonstrate how to prioritize sending traffic to endpoints in the same zone as the client using `PreferClose`.
