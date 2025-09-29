#!/bin/bash

# Display help information
show_help() {
    cat << EOF
Zone Communication Analyzer

USAGE:
    ./zone-communication-analyzer.sh [MINUTES] [OPTIONS]

DESCRIPTION:
    Analyzes X-Ray traces to identify same-zone vs cross-zone communications
    between checkout and orders services. Helps validate traffic distribution
    policies like 'PreferClose' for zone-local routing optimization.

ARGUMENTS:
    MINUTES     Time window in minutes to analyze (default: 5)

OPTIONS:
    -h, --help  Show this help message

EXAMPLES:
    ./zone-communication-analyzer.sh           # Analyze last 5 minutes
    ./zone-communication-analyzer.sh 10        # Analyze last 10 minutes
    ./zone-communication-analyzer.sh --help    # Show this help

OUTPUT:
    Green SAME-ZONE    - Communications within the same availability zone
    Red CROSS-ZONE     - Communications across different availability zones

REQUIREMENTS:
    - kubectl configured and connected to cluster
    - AWS CLI configured with X-Ray access
    - jq installed for JSON processing
    - Active checkout and orders services with OpenTelemetry tracing

EOF
}

# Check for help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
    exit 0
fi

MINUTES=${1:-5}

# Build pod-to-AZ mappings
echo -e "\033[0;34m[$(date '+%H:%M:%S')]\033[0m Building pod-to-AZ mappings..."
temp_file=$(mktemp)

for service in orders checkout; do
    kubectl get pods -n $service -o json | jq -r '.items[] | 
        "\(.metadata.name)|\(.spec.nodeName)"' | \
    while IFS='|' read -r pod_name node_name; do
        if [ -n "$node_name" ]; then
            az=$(kubectl get node "$node_name" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}' 2>/dev/null || echo "unknown")
            echo "$pod_name|$az" >> "$temp_file"
        fi
    done
done

# Get checkout pods
checkout_pods=$(kubectl get pods -n checkout -o jsonpath='{.items[*].metadata.name}')

if [[ "$OSTYPE" == "darwin"* ]]; then
    START_TIME=$(date -u -v-${MINUTES}M '+%Y-%m-%dT%H:%M:%SZ')
    END_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
else
    START_TIME=$(date -u -d "$MINUTES minutes ago" '+%Y-%m-%dT%H:%M:%SZ')
    END_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
fi

echo -e "\033[0;34m[$(date '+%H:%M:%S')]\033[0m Analyzing checkout->orders /submit communication patterns (last $MINUTES minutes)"

comm_count_file=$(mktemp)
echo "0" > "$comm_count_file"

for pod in $checkout_pods; do
    # Query /submit traces for this checkout pod
    traces=$(aws xray get-trace-summaries \
        --region eu-west-1 \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --filter-expression "(service(id(name: \"$pod\"))) AND (http.url contains \"/submit\")" \
        2>/dev/null)
    
    trace_count=$(echo "$traces" | jq '.TraceSummaries | length' 2>/dev/null || echo "0")
    
    if [ "$trace_count" -gt 0 ]; then
        trace_ids=$(echo "$traces" | jq -r '.TraceSummaries[].Id' | head -3)
        trace_ids_array=$(echo "$trace_ids" | jq -R . | jq -s .)
        
        # Analyze detailed traces
        aws xray batch-get-traces --region eu-west-1 --trace-ids "$trace_ids_array" 2>/dev/null | \
        jq -r --arg pod "$pod" '.Traces[] | 
            (.Segments[] | select(.Document | fromjson | .name == $pod) | .Document | fromjson) as $checkout |
            (.Segments[] | select(.Document | fromjson | .name | test("^orders-")) | .Document | fromjson) as $orders |
            if $checkout and $orders then
                ($checkout.aws.ec2.availability_zone // "unknown") as $checkout_az |
                ($orders.name) as $orders_pod |
                "\($pod)|\($checkout_az)|\($orders_pod)"
            else
                empty
            end' | \
        while IFS='|' read -r checkout_pod checkout_az orders_pod; do
            # Look up AZs from our mapping
            checkout_mapped_az=$(grep "^$checkout_pod|" "$temp_file" | cut -d'|' -f2)
            orders_mapped_az=$(grep "^$orders_pod|" "$temp_file" | cut -d'|' -f2)
            
            # Use mapped AZ if trace AZ is unknown
            final_checkout_az=${checkout_az}
            if [ "$checkout_az" = "unknown" ] && [ -n "$checkout_mapped_az" ]; then
                final_checkout_az=$checkout_mapped_az
            fi
            
            # Check if same zone
            if [ "$final_checkout_az" = "$orders_mapped_az" ]; then
                zone_status="\033[0;32mSAME-ZONE\033[0m"
            else
                zone_status="\033[0;31mCROSS-ZONE\033[0m"
            fi
            
            echo -e "\033[0;32m$checkout_pod\033[0m (\033[0;34m$final_checkout_az\033[0m) -> \033[0;32m$orders_pod\033[0m (\033[0;34m$orders_mapped_az\033[0m) [$zone_status]"
            # Increment counter in temp file
            count=$(cat "$comm_count_file")
            echo $((count + 1)) > "$comm_count_file"
        done
    fi
done

total_communications=$(cat "$comm_count_file")
if [ $total_communications -eq 0 ]; then
    echo -e "\033[0;33mNo communication between checkout and orders services detected.\033[0m"
fi

rm -f "$temp_file" "$comm_count_file"

