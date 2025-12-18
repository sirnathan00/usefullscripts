#!/bin/bash
cp Public_homelab_linux nan/root/.ssh/authorized_keys

sed -i 's/#PubkeyAuthentication no/PubkeyAuthentication yes/'  /etc/ssh/sshd_config
sed -i 's|#AuthorizedKeysFile      .ssh/authorized_keys .ssh/authorized_keys2|AuthorizedKeysFile      .ssh/authorized_keys .ssh/authorized_keys2|' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

systemctl restart ssh sshd

rm /etc/apt/sources.list.d/ceph.sources
rm /etc/apt/sources.list.d/pve-enterprise.sources
cp proxmox.sources /etc/apt/sources.list.d/proxmox.sources


msg_info() {
  local msg="$1"
  echo -ne " ${HOLD} ${YW}${msg}..."
}

msg_ok() {
  local msg="$1"
  echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

msg_error() {
  local msg="$1"
  echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

post_routines_common() {
  CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "SUBSCRIPTION NAG" --menu "This will disable the nag message reminding you to purchase a subscription every time you log in to the web interface.\n \nDisable subscription nag?" 14 58 2 \
    "yes" " " \
    "no" " " 3>&2 2>&1 1>&3)
  case $CHOICE in
  yes)
    whiptail --backtitle "Proxmox VE Helper Scripts" --msgbox --title "Support Subscriptions" "Supporting the software's development team is essential. Check their official website's Support Subscriptions for pricing. Without their dedicated work, we wouldn't have this exceptional software." 10 58
    msg_info "Disabling subscription nag"
    # Create external script, this is needed because DPkg::Post-Invoke is fidly with quote interpretation
    mkdir -p /usr/local/bin
    cat >/usr/local/bin/pve-remove-nag.sh <<'EOF'
#!/bin/sh
WEB_JS=/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
if [ -s "$WEB_JS" ] && ! grep -q NoMoreNagging "$WEB_JS"; then
    echo "Patching Web UI nag..."
    sed -i -e "/data\.status/ s/!//" -e "/data\.status/ s/active/NoMoreNagging/" "$WEB_JS"
fi

MOBILE_TPL=/usr/share/pve-yew-mobile-gui/index.html.tpl
MARKER="<!-- MANAGED BLOCK FOR MOBILE NAG -->"
if [ -f "$MOBILE_TPL" ] && ! grep -q "$MARKER" "$MOBILE_TPL"; then
    echo "Patching Mobile UI nag..."
    printf "%s\n" \
      "$MARKER" \
      "<script>" \
      "  function removeSubscriptionElements() {" \
      "    // --- Remove subscription dialogs ---" \
      "    const dialogs = document.querySelectorAll('dialog.pwt-outer-dialog');" \
      "    dialogs.forEach(dialog => {" \
      "      const text = (dialog.textContent || '').toLowerCase();" \
      "      if (text.includes('subscription')) {" \
      "        dialog.remove();" \
      "        console.log('Removed subscription dialog');" \
      "      }" \
      "    });" \
      "" \
      "    // --- Remove subscription cards, but keep Reboot/Shutdown/Console ---" \
      "    const cards = document.querySelectorAll('.pwt-card.pwt-p-2.pwt-d-flex.pwt-interactive.pwt-justify-content-center');" \
      "    cards.forEach(card => {" \
      "      const text = (card.textContent || '').toLowerCase();" \
      "      const hasButton = card.querySelector('button');" \
      "      if (!hasButton && text.includes('subscription')) {" \
      "        card.remove();" \
      "        console.log('Removed subscription card');" \
      "      }" \
      "    });" \
      "  }" \
      "" \
      "  const observer = new MutationObserver(removeSubscriptionElements);" \
      "  observer.observe(document.body, { childList: true, subtree: true });" \
      "  removeSubscriptionElements();" \
      "  setInterval(removeSubscriptionElements, 300);" \
      "  setTimeout(() => {observer.disconnect();}, 10000);" \
      "</script>" \
      "" >> "$MOBILE_TPL"
fi
EOF
    chmod 755 /usr/local/bin/pve-remove-nag.sh

    cat >/etc/apt/apt.conf.d/no-nag-script <<'EOF'
DPkg::Post-Invoke { "/usr/local/bin/pve-remove-nag.sh"; };
EOF
    chmod 644 /etc/apt/apt.conf.d/no-nag-script

    msg_ok "Disabled subscription nag (Delete browser cache)"
    ;;
  no)
    whiptail --backtitle "Proxmox VE Helper Scripts" --msgbox --title "Support Subscriptions" "Supporting the software's development team is essential. Check their official website's Support Subscriptions for pricing. Without their dedicated work, we wouldn't have this exceptional software." 10 58
    msg_error "Selected no to Disabling subscription nag"
    rm /etc/apt/apt.conf.d/no-nag-script 2>/dev/null
    ;;
  esac
  apt --reinstall install proxmox-widget-toolkit &>/dev/null || msg_error "Widget toolkit reinstall failed"
  if ! systemctl is-active --quiet pve-ha-lrm; then
    CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "HIGH AVAILABILITY" --menu "Enable high availability?" 10 58 2 \
      "yes" " " \
      "no" " " 3>&2 2>&1 1>&3)
    case $CHOICE in
    yes)
      msg_info "Enabling high availability"
      systemctl enable -q --now pve-ha-lrm
      systemctl enable -q --now pve-ha-crm
      systemctl enable -q --now corosync
      msg_ok "Enabled high availability"
      ;;
    no) msg_error "Selected no to Enabling high availability" ;;
    esac
  fi

  if systemctl is-active --quiet pve-ha-lrm; then
    CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "HIGH AVAILABILITY" --menu "If you plan to utilize a single node instead of a clustered environment, you can disable unnecessary high availability (HA) services, thus reclaiming system resources.\n\nIf HA becomes necessary at a later stage, the services can be re-enabled.\n\nDisable high availability?" 18 58 2 \
      "yes" " " \
      "no" " " 3>&2 2>&1 1>&3)
    case $CHOICE in
    yes)
      msg_info "Disabling high availability"
      systemctl disable -q --now pve-ha-lrm
      systemctl disable -q --now pve-ha-crm
      msg_ok "Disabled high availability"
      CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "COROSYNC" --menu "Disable Corosync for a Proxmox VE Cluster?" 10 58 2 \
        "yes" " " \
        "no" " " 3>&2 2>&1 1>&3)
      case $CHOICE in
      yes)
        msg_info "Disabling Corosync"
        systemctl disable -q --now corosync
        msg_ok "Disabled Corosync"
        ;;
      no) msg_error "Selected no to Disabling Corosync" ;;
      esac
      ;;
    no) msg_error "Selected no to Disabling high availability" ;;
    esac
  fi

  CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "UPDATE" --menu "\nUpdate Proxmox VE now?" 11 58 2 \
    "yes" " " \
    "no" " " 3>&2 2>&1 1>&3)
  case $CHOICE in
  yes)
    msg_info "Updating Proxmox VE (Patience)"
    apt update &>/dev/null || msg_error "apt update failed"
    apt -y dist-upgrade &>/dev/null || msg_error "apt dist-upgrade failed"
    msg_ok "Updated Proxmox VE"
    ;;
  no) msg_error "Selected no to Updating Proxmox VE" ;;
  esac

  # Final message for all hosts in cluster and browser cache
  whiptail --backtitle "Proxmox VE Helper Scripts" --title "Post-Install Reminder" --msgbox \
    "IMPORTANT:

If you have multiple Proxmox VE hosts in a cluster, please make sure to run this script on every node individually.

After completing these steps, it is strongly recommended to REBOOT your node.

After the upgrade or post-install routines, always clear your browser cache or perform a hard reload (Ctrl+Shift+R) before using the Proxmox VE Web UI to avoid UI display issues.
" 20 80

  CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "REBOOT" --menu "\nReboot Proxmox VE now? (recommended)" 11 58 2 \
    "yes" " " \
    "no" " " 3>&2 2>&1 1>&3)
  case $CHOICE in
  yes)
    msg_info "Rebooting Proxmox VE"
    sleep 2
    msg_ok "Completed Post Install Routines"
    reboot
    ;;
  no)
    msg_error "Selected no to Rebooting Proxmox VE (Reboot recommended)"
    msg_ok "Completed Post Install Routines"
    ;;
  esac
}
post_routines_common
#apt update
#apt-get dist-upgrade

