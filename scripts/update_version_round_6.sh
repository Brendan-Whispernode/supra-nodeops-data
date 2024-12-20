#!/bin/bash

SCRIPT_EXECUTION_LOCATION="$(pwd)/supra_configs"

# Parse ip_address from operator_config.toml
ip_address=$(grep 'ip_address' operator_config.toml | awk -F'=' '{print $2}' | tr -d ' "')

echo "Remove old supra onboarding script"
rm  "$(pwd)/onboarding_round_6.sh"

# Check if ip_address is set
if [ -z "$ip_address" ]; then
    echo "IP address not found in config file."
    exit 1
fi
# Stop the Docker container if it's running
echo "Stopping supra container"
if ! docker stop supra_$ip_address; then
    echo "Failed to stop supra container. Exiting..."
fi
echo "Supra container stopped"

# Remove the Docker container
echo "Removing supra container"
if ! docker rm supra_$ip_address; then
    echo "Failed to remove supra container. Exiting..."
fi
echo "Supra container removed"

# Remove the old Docker image
echo "Deleting old docker image"
if ! docker rmi asia-docker.pkg.dev/supra-devnet-misc/supra-testnet/validator-node:v6.0.0.rc14; then
    echo "Failed to delete old Docker image. Exiting..."
fi
echo "Deleted the old Docker image"

# Check if smr_settings.toml exists before creating a new one
echo "Changing the smr settings file"
smr_settings_file="$SCRIPT_EXECUTION_LOCATION/smr_settings.toml"
rm ${smr_settings_file}
if [ -f "${smr_settings_file}" ]; then
    echo "smr_settings.toml already exists. Skipping creation."
else
    # Create smr_settings.toml
    echo "Creating smr_settings.toml"
    cat <<EOF > "${smr_settings_file}"
[instance]
chain_id = 6
epoch_duration_secs = 7200
recurring_lockup_duration_secs = 14400
voting_duration_secs = 7200
is_testnet = true
genesis_timestamp_microseconds = 1726574400000000

[mempool]
max_batch_delay_ms = 500
max_batch_size_bytes = 5000000
sync_retry_delay_ms = 2000
sync_retry_nodes = 3

[moonshot]
block_recency_bound_ms = 500
halt_block_production_when_no_txs = false
leader_elector = "FairSuccession"
max_block_delay_ms = 2500
max_payload_items_per_block = 50
message_recency_bound_rounds = 20
sync_retry_delay_ms = 1000
timeout_delay_ms = 5000

[node]
connection_refresh_timeout_sec = 1
resume = true
root_ca_cert_path = "configs/ca_certificate.pem"
rpc_access_port = 26000
server_cert_path = "configs/server_supra_certificate.pem"
server_private_key_path = "configs/server_supra_key.pem"

[node.database_setup.dbs.chain_store.rocks_db]
path = "configs/smr_storage"
enable_pruning = true

[node.database_setup.dbs.ledger.rocks_db]
path = "configs/ledger_storage"

[node.database_setup.prune_config]
epochs_to_retain = 84
EOF
    echo "smr_settings.toml created"
fi

# Run the Docker container
echo "Running new docker image"
USER_ID=$(id -u)
GROUP_ID=$(id -g)

if !     docker run --name "supra_$ip_address" \
        -v $SCRIPT_EXECUTION_LOCATION:/supra/configs \
        --user "$USER_ID:$GROUP_ID" \
        -e "SUPRA_HOME=/supra/configs" \
        -e "SUPRA_LOG_DIR=/supra/configs/supra_node_logs" \
        -e "SUPRA_MAX_LOG_FILE_SIZE=4000000" \
        -e "SUPRA_MAX_UNCOMPRESSED_LOGS=5" \
        -e "SUPRA_MAX_LOG_FILES=20" \
        --net=host \
        -itd asia-docker.pkg.dev/supra-devnet-misc/supra-testnet/validator-node:v6.0.0.rc15; then
    echo "Failed to run new Docker image. Exiting..."
    exit 1
fi
echo "New Docker image created"

# Update hash in hashmap_phase_1_previous.toml
new_sha=$(sha256sum $SCRIPT_EXECUTION_LOCATION/smr_settings.toml | awk '{print $1}')
if ! sed -i.bak "s|\(smr_settings.toml\s*=\s*\).*|\1\"$new_sha\"|" "$SCRIPT_EXECUTION_LOCATION/hashmap_phase_1_previous.toml"; then
    echo "Failed to update hashmap_phase_1_previous.toml. Exiting..."
    exit 1
fi
echo "Updated smr_settings.toml hash"

wget -O $SCRIPT_EXECUTION_LOCATION/ca_certificate.pem https://gist.githubusercontent.com/sjadiya-supra/a25596f90a24ff5c4e2b3ebe9cfb57df/raw/5910a4322c90fd9f13ca804c316fcda7221d94ac/ca_certificate.pem
wget -O $SCRIPT_EXECUTION_LOCATION/server_supra_certificate.pem https://gist.githubusercontent.com/sjadiya-supra/f39dda12625b7155e4dbf3c8f6bdc891/raw/6b4bdcf8ccd5e348f5f2988ad757199ed88b6197/server_supra_certificate.pem
wget -O $SCRIPT_EXECUTION_LOCATION/server_supra_key.pem https://gist.githubusercontent.com/sjadiya-supra/e05d37d0cb9e72f806dc965d168c8c41/raw/a5e51ec29ec04f6a7d9e03e0fe08b64fbdfdbb03/server_supra_key.pem
wget -O $SCRIPT_EXECUTION_LOCATION/genesis_configs.json https://testnet-snapshot.supra.com/configs/genesis_configs.json
wget -O "$(pwd)/onboarding_round_6.sh" https://raw.githubusercontent.com/Entropy-Foundation/supra-nodeops-data/refs/heads/master/scripts/onboarding_round_6.sh
chmod +x "$(pwd)/onboarding_round_6.sh"