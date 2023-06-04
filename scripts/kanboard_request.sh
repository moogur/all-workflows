url=
auth_data=

function generate_post_data() {
  local method=$1
  local params=$2

  cat <<EOF
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "$method",
  "params": $params
}
EOF
}

function request() {
  local method=$1
  local params=$2

  echo params $2
  result=$(curl -u "$auth_data" -d "$(generate_post_data $method $params)" $url/jsonrpc.php)
  echo $result
}
