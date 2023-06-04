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

  if [[ $2 =~ " " ]]; then
    echo $2
    params=`echo {$2} | tr " " ","`
    echo $params
  else
    params=$2
  fi

  result=$(curl -u "$auth_data" -d "$(generate_post_data $method $params)" $url/jsonrpc.php)
  echo $result
}
