#!/bin/bash
#
# Script to estimate gas usage of an (op)Poke using an RPC connected client.
#
# Run via:
# ```bash
# $ script/dev/gas-estimator           \
#       --scribe             <address> \
#       --op-poke                      \ # Set to use opPoke, omit for normal poke
#       --poke-val           <uint128> \
#       --poke-age           <uint32>  \
#       --schnorr-signature  <bytes32> \
#       --schnorr-commitment <address> \
#       --schnorr-feed-ids   <bytes>   \
#       --ecdsa-v            <uint32>  \ # ECDSA args only necessary if opPoke
#       --ecdsa-r            <uint128> \ # ECDSA args only necessary if opPoke
#       --ecdsa-s            <uint32>  \ # ECDSA args only necessary if opPoke
#       --rpc-url            <string>
# ```

# Scribe argument
scribe=""

# (op)Poke arguments
op_poke=false
## Poke data
poke_val=""
poke_age=""
## Schnorr data
schnorr_signature=""
schnorr_commitment=""
schnorr_feed_ids=""
## ECDSA data
ecdsa_v=""
ecdsa_r=""
ecdsa_s=""

# Other arguments
rpc_url=""

# Parse arguments:
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scribe)
      scribe="$2"
      shift 2
      ;;
    --op-poke)
      op_poke=true
      shift
      ;;
    --poke-val)
      poke_val="$2"
      shift 2
      ;;
    --poke-age)
      poke_age="$2"
      shift 2
      ;;
    --schnorr-signature)
      schnorr_signature="$2"
      shift 2
      ;;
    --schnorr-commitment)
      schnorr_commitment="$2"
      shift 2
      ;;
    --schnorr-feed-ids)
      schnorr_feed_ids="$2"
      shift 2
      ;;
    --ecdsa-v)
      ecdsa_v="$2"
      shift 2
      ;;
    --ecdsa-r)
      ecdsa_r="$2"
      shift 2
      ;;
    --ecdsa-s)
      ecdsa_s="$2"
      shift 2
      ;;
    --rpc-url)
      rpc_url="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Create calldata.
calldata=""
if [[ -n $op_poke ]]; then
    calldata=$(cast calldata "opPoke((uint128,uint32),(bytes32,address,bytes),(uint8,bytes32,bytes32))"  \
                             "($poke_val,$poke_age)"                                                     \
                             "($schnorr_signature,$schnorr_commitment,$schnorr_feed_ids)"                \
                             "($ecdsa_v,$ecdsa_r,$ecdsa_s)"                                              \
              )
else
    calldata=$(cast calldata "poke((uint128,uint32),(bytes32,address,bytes))"              \
                             "($poke_val,$poke_age)"                                       \
                             "($schnorr_signature,$schnorr_commitment,$schnorr_feed_ids)"
              )
fi

if [[ $calldata == "" ]]; then
    echo -e "Error creating calldata"
    exit 1
fi

# Use `cast estimate` on given RPC to estimate gas usage.
result=$(cast estimate $scribe $calldata --rpc-url $rpc_url)
echo -e "$result"
