#!/bin/bash

# Get all namespaces with the pod-ranker label
NAMESPACES=$(kubectl get namespaces -l pod-ranker=true -o jsonpath='{.items[*].metadata.name}')
if [ -z "$NAMESPACES" ]; then
    echo "No namespaces found with pod-ranker=true label"
    exit 0
fi
for NAMESPACE in $NAMESPACES; do
    echo "Processing namespace: $NAMESPACE"
    # Get all deployments in the namespace
    DEPLOYMENTS=$(kubectl get deployments -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}')
    if [ -z "$DEPLOYMENTS" ]; then
        echo "No deployments found in namespace $NAMESPACE"
        continue
    fi
    for DEPLOYMENT in $DEPLOYMENTS; do
        echo "Processing deployment: $DEPLOYMENT"
        # Build a proper selector string from the deployment's selector
        SELECTOR=""
        FIRST=true
        # Process each key-value pair in the selector
        for KEY in $(kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o jsonpath='{.spec.selector.matchLabels}' | jq -r 'keys[]'); do
            VALUE=$(kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o jsonpath="{.spec.selector.matchLabels.$KEY}")
            if [ "$FIRST" = true ]; then
                SELECTOR="$KEY=$VALUE"
                FIRST=false
            else
                SELECTOR="$SELECTOR,$KEY=$VALUE"
            fi
        done
        if [ -z "$SELECTOR" ]; then
            echo "Could not get selector for deployment $DEPLOYMENT in namespace $NAMESPACE"
            continue
        fi
        echo "Using selector: $SELECTOR"
        # Get all pods for this deployment using the selector, sorted by creation timestamp
        PODS=$(kubectl get pods -n $NAMESPACE -l "$SELECTOR" --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[*].metadata.name}')
        if [ -z "$PODS" ]; then
            echo "No pods found for deployment $DEPLOYMENT in namespace $NAMESPACE"
            continue
        fi
        # Convert to array
        POD_ARRAY=($PODS)
        TOTAL_PODS=${#POD_ARRAY[@]}
        echo "Found $TOTAL_PODS pods for deployment $DEPLOYMENT"
        if [ $TOTAL_PODS -gt 1 ]; then
            # Calculate how many old pods to mark
            OLD_COUNT=${OLD_PODS_COUNT:-1}
            if [ $OLD_COUNT -ge $TOTAL_PODS ]; then
                OLD_COUNT=$((TOTAL_PODS - 1))
                echo "Warning: OLD_PODS_COUNT ($OLD_PODS_COUNT) is >= total pods ($TOTAL_PODS). Setting to $OLD_COUNT"
            fi
            # Set the oldest pods to have deletion cost of -100
            for ((i=0; i<$OLD_COUNT; i++)); do
                echo "Setting pod ${POD_ARRAY[$i]} with deletion cost -100"
                kubectl annotate pod ${POD_ARRAY[$i]} -n $NAMESPACE controller.kubernetes.io/pod-deletion-cost="-100" --overwrite
            done
            echo "Successfully updated deletion costs for deployment $DEPLOYMENT"
        else
            echo "Skipping deployment $DEPLOYMENT as it has only $TOTAL_PODS pod(s)"
        fi
    done
done
