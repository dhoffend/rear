#
# Adapt some SSH configs and as needed regenerate SSH host key:

# There is nothing to do when there are no SSH binaries on the original system:
has_binary ssh || has_binary sshd || return

# Do nothing when not any SSH file should be copied into the recovery system:
is_false "$SSH_FILES" && return

# Patch sshd_config:
# - disable password authentication because rescue system does not have PAM etc.
# - disable challenge response (Kerberos, skey, ...) for same reason
# - disable PAM
# - disable motd printing, our /etc/profile does that
# - if SSH_ROOT_PASSWORD was defined allow root to login via ssh
# The idea is to allow ssh authorized_keys based access in the recovery system
# which has to be enabled in the original system to work in the recovery system.
# The funny [] around a letter makes 'shopt -s nullglob' remove this file from the list if it does not exist.
# Files without a [] are mandatory.
local sshd_config_files=( $ROOTFS_DIR/etc/ssh/sshd_co[n]fig $ROOTFS_DIR/etc/sshd_co[n]fig $ROOTFS_DIR/etc/openssh/sshd_co[n]fig )
if test "${sshd_config_files[*]}" ; then
    sed -i -e 's/ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/ig' \
           -e 's/UsePAM.*/UsePam no/ig' \
           -e 's/ListenAddress.*/ListenAddress 0.0.0.0/ig' \
           -e '1i\PrintMotd no' \
        ${sshd_config_files[@]}
    # Allow password authentication in the recovery system only if SSH_ROOT_PASSWORD is specified:
    if test "$SSH_ROOT_PASSWORD" ; then
        sed -i -e 's/PasswordAuthentication.*/PasswordAuthentication yes/ig' ${sshd_config_files[@]}
        sed -i -e 's/PermitRootLogin.*/PermitRootLogin yes/ig' ${sshd_config_files[@]}
    else
        sed -i  -e 's/PasswordAuthentication.*/PasswordAuthentication no/ig' ${sshd_config_files[@]}
    fi
else
     LogPrintError "No sshd configuration files"
fi

# Generate new SSH host key in the recovery system when no SSH host key file
# had been copied into the the recovery system in rescue/default/500_ssh.sh
# cf. https://github.com/rear/rear/issues/1512#issuecomment-331638066
# In SLES12 "man ssh-keygen" reads:
#   -t dsa | ecdsa | ed25519 | rsa | rsa1
#      Specifies the type of key to create.
#      The possible values are "rsa1" for protocol version 1
#      and "dsa", "ecdsa", "ed25519", or "rsa" for protocol version 2.
# The above GitHub issue comment proposes a static
#   ssh-keygen -t ed25519 -N '' -f "..."
# but the key type ed25519 is not supported in older systems like SLES11.
# On SLES10 "man ssh-keygen" reads:
#   -t type
#      Specifies the type of key to create.
#      The possible values are rsa1 for protocol version 1
#      and rsa or dsa for protocol version 2.
# Currently (October 2017) ReaR is kept working on older systems
# like SLES10 cf. https://github.com/rear/rear/issues/1522
# and currently this backward compatibility should not be broken
# (for the future see https://github.com/rear/rear/issues/1390)
# so that we try to generate all possible types of keys.
# This is in compliance what there is on a default SLES system, e.g.
# on a default SLES10 there is
#   /etc/ssh/ssh_host_rsa_key
#   /etc/ssh/ssh_host_dsa_key
# on a default SLES11 there is additionally
#   /etc/ssh/ssh_host_ecdsa_key
# on a default SLES12 there is additionally
#   /etc/ssh/ssh_host_ed25519_key
# only a rsa1 type key does not exists so that rsa1 is also not generated here:
local ssh_host_key_types="rsa dsa ecdsa ed25519"
local ssh_host_key_type=""
local ssh_host_key_file=""
local recovery_system_key_file=""
local ssh_host_key_exists="no"
for ssh_host_key_type in $ssh_host_key_types ; do
    ssh_host_key_file="etc/ssh/ssh_host_${ssh_host_key_type}_key"
    if test -f "$ROOTFS_DIR/$ssh_host_key_file" ; then
        Log "Using existing SSH host key $ssh_host_key_file in recovery system"
        ssh_host_key_exists="yes"
        continue
    fi
    Log "Generating new SSH host key $ssh_host_key_file in recovery system"
    recovery_system_key_file="$ROOTFS_DIR/$ssh_host_key_file"
    mkdir $v -p $( dirname "$recovery_system_key_file" )
    ssh-keygen $v -t "$ssh_host_key_type" -N '' -f "$recovery_system_key_file" && ssh_host_key_exists="yes" || Log "Cannot generate key type $ssh_host_key_type"
done
is_false "$ssh_host_key_exists" && LogPrintError "No SSH host key etc/ssh/ssh_host_TYPE_key of type $ssh_host_key_types in recovery system"

