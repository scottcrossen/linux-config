#!/bin/bash
#author scottcrossen

SSH_ENV="$HOME/.ssh/agent-environment"

function start_agent {
    echo "Initialising new SSH agent..."
    /usr/bin/ssh-agent | sed 's/^echo/#echo/' > "${SSH_ENV}"
    echo succeeded
    chmod 600 "${SSH_ENV}"
    . "${SSH_ENV}" > /dev/null
    /usr/bin/ssh-add;
}

# Source SSH settings, if applicable

if [ -f "${SSH_ENV}" ]; then
    . "${SSH_ENV}" > /dev/null
    #ps ${SSH_AGENT_PID} doesn't work under cywgin
    ps -ef | grep ${SSH_AGENT_PID} | grep ssh-agent$ > /dev/null || {
        start_agent;
    }
else
    start_agent;
fi

function cssh {
  TEMP_DIR="$(mktemp -d)"
  IFS='@' read -ra ADDRESS <<< "$1"
  if [[ -z "${ADDRESS[1]}" ]]; then
    TARGET_USER="ec2-user"
    TARGET_IP="${ADDRESS[0]}"
  else
    TARGET_USER="${ADDRESS[0]}"
    TARGET_IP="${ADDRESS[1]}"
  fi

  ssh-keygen -t rsa -b 4096 -q -N "" -f "$TEMP_DIR/temp"
  TARGET_INSTANCE="$(aws ec2 describe-instances | jq --arg target "$TARGET_IP" -r '.Reservations | map(.Instances) | flatten | map(select(.State.Name != "terminated" and (.NetworkInterfaces | map(.PrivateIpAddresses) | flatten | map(.PrivateIpAddress) | map(select(. == $target)) | length) != 0))[0] | tostring')"
  TARGET_INSTANCE_ID="$(echo "$TARGET_INSTANCE" | jq -r '.InstanceId')"
  TARGET_SECURITY_GROUPS="$(echo "$TARGET_INSTANCE" | jq -r '.InstanceId as $id | .SecurityGroups | map({InstanceId: $id, GroupId: .GroupId}) | map(.GroupId) | tostring')"
  JUMP_SECURITY_GROUPS="$(aws ec2 describe-security-group-rules | jq --argjson groups "$TARGET_SECURITY_GROUPS" -r '.SecurityGroupRules | map(select((.IsEgress | not) and ((.GroupId as $current | $groups | map(select(. == $current)) | length) != 0) and ((.FromPort == -1 and .ToPort == -1) or (.FromPort == 22 and .ToPort == 22)) and .ReferencedGroupInfo != null)) | map(.ReferencedGroupInfo.GroupId) | unique | tostring')"
  JUMP_INSTANCE="$(aws ec2 describe-instances | jq --argjson groups "$JUMP_SECURITY_GROUPS" -r '.Reservations | map(.Instances) | flatten | map(select(.State.Name != "terminated" and (.SecurityGroups | map(select(.GroupId as $current | $groups | map(select(. == $current)))) | length != 0) and (.Tags | map(select(.Value | contains("tunnel"))) | length != 0)))[0]')"
  JUMP_IP="$(echo "$JUMP_INSTANCE" | jq -r '.PrivateIpAddress')"
  JUMP_INSTANCE_ID="$(echo "$JUMP_INSTANCE" | jq -r '.InstanceId')"
  JUMP_USER="ubuntu"

  aws ec2-instance-connect send-ssh-public-key --instance-os-user "$JUMP_USER" --instance-id "$JUMP_INSTANCE_ID" --ssh-public-key "file://$TEMP_DIR/temp.pub" > /dev/null
  aws ec2-instance-connect send-ssh-public-key --instance-os-user "$TARGET_USER" --instance-id "$TARGET_INSTANCE_ID" --ssh-public-key "file://$TEMP_DIR/temp.pub" > /dev/null

  ssh -i "$TEMP_DIR/temp" -o ProxyCommand="ssh -l $JUMP_USER -i $TEMP_DIR/temp -W '[%h]:%p' $JUMP_IP" "$TARGET_USER@$TARGET_IP"
}
