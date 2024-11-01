#!/bin/bash
 
CONNAME="eduroam"
USERNAME="erikfran@kth.se"
PASSWORD="FfcxJJ6bm4v"
 
nmcli connection add type wifi con-name $CONNAME        \
        connection.permissions $LOGNAME                 \
        802-11-wireless.ssid $CONNAME                   \
        802-11-wireless-security.key-mgmt wpa-eap       \
        802-11-wireless-security.group ccmp,tkip        \
        802-11-wireless-security.pairwise ccmp          \
        802-11-wireless-security.proto rsn              \
        802-1x.altsubject-matches DNS:wifi.kth.se      \
        802-1x.anonymous-identity anonymous@kth.se     \
        802-1x.eap peap                                 \
        802-1x.identity $USERNAME                       \
        802-1x.password $PASSWORD                       \
        802-1x.phase2-auth mschapv2                     \
        ipv4.method auto                                \
        ipv6.addr-gen-mode stable-privacy               \
        ipv6.method auto
