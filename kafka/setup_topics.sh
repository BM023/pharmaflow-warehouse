#!/usr/bin/env bash
# =============================================================================
# Kafka Topic Setup
# Creates all required topics with correct partition counts.
# Run once after Kafka starts for the first time.
#
# Usage: ./kafka/setup_topics.sh
# =============================================================================

set -euo pipefail

KAFKA_CONTAINER="kafka"
BOOTSTRAP="localhost:9092"
PARTITIONS=5
REPLICATION=1

echo "============================================"
echo " PharmaFlow — Kafka Topic Setup"
echo "============================================"

topics=(
    "pharmaflow.prescriptions"
    "pharmaflow.inventory"
    "pharmaflow.patients"
    "pharmaflow.deliveries"
)

for topic in "${topics[@]}"; do
    echo "Creating topic: ${topic}"
    docker exec "${KAFKA_CONTAINER}" \
        kafka-topics --bootstrap-server "${BOOTSTRAP}" \
        --create \
        --if-not-exists \
        --topic "${topic}" \
        --partitions "${PARTITIONS}" \
        --replication-factor "${REPLICATION}"
done

echo ""
echo "Topics created. Verifying..."
docker exec "${KAFKA_CONTAINER}" \
    kafka-topics --bootstrap-server "${BOOTSTRAP}" --list

echo ""
echo "Topic details:"
for topic in "${topics[@]}"; do
    docker exec "${KAFKA_CONTAINER}" \
        kafka-topics --bootstrap-server "${BOOTSTRAP}" \
        --describe --topic "${topic}"
done

echo ""
echo "Topic setup complete."