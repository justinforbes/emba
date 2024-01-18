#!/bin/bash -p

# EMBA - EMBEDDED LINUX ANALYZER
#
# Copyright 2020-2024 Siemens Energy AG
#
# EMBA comes with ABSOLUTELY NO WARRANTY. This is free software, and you are
# welcome to redistribute it under the terms of the GNU General Public License.
# See LICENSE file for usage of this software.
#
# EMBA is licensed under GPLv3
#
# Author(s): Michael Messner

# Description:  Tests the emulated live system which is build and started in L10
#               Currently this is an experimental module and needs to be activated separately via the -Q switch.
#               It is also recommended to only use this technique in a dockerized or virtualized environment.

L20_snmp_checks() {

  export SNMP_UP=0

  if [[ "${SYS_ONLINE}" -eq 1 ]] && [[ "${TCP}" == "ok" ]]; then
    module_log_init "${FUNCNAME[0]}"
    module_title "Live SNMP tests of emulated device."
    pre_module_reporter "${FUNCNAME[0]}"

    if [[ ${IN_DOCKER} -eq 0 ]] ; then
      print_output "[!] This module should not be used in developer mode and could harm your host environment."
    fi

    if [[ -v IP_ADDRESS_ ]]; then
      if ! system_online_check "${IP_ADDRESS_}" ; then
        if ! restart_emulation "${IP_ADDRESS_}" "${IMAGE_NAME}" 1 "${STATE_CHECK_MECHANISM}"; then
          print_output "[-] System not responding - Not performing SNMP checks"
          module_end_log "${FUNCNAME[0]}" "${SNMP_UP}"
          return
        fi
      fi
      if [[ "${NMAP_PORTS_SERVICES[*]}" == *"snmp"* ]]; then
        check_basic_snmp "${IP_ADDRESS_}"
        check_snmp_vulns "${IP_ADDRESS_}"
      else
        print_output "[*] No SNMP services detected"
      fi
    else
      print_output "[!] No IP address found"
    fi

    write_log ""
    write_log "Statistics:${SNMP_UP}"
    module_end_log "${FUNCNAME[0]}" "${SNMP_UP}"
  fi
}

check_basic_snmp() {
  local IP_ADDRESS_="${1:-}"

  sub_module_title "SNMP enumeration for emulated system with IP ${ORANGE}${IP_ADDRESS_}${NC}"

  if command -v snmp-check > /dev/null; then
    print_output "[*] SNMP scan with community name ${ORANGE}public${NC}"
    snmp-check -w "${IP_ADDRESS_}" >> "${LOG_PATH_MODULE}"/snmp-check-public-"${IP_ADDRESS_}".txt
    if [[ -f "${LOG_PATH_MODULE}"/snmp-check-public-"${IP_ADDRESS_}".txt ]]; then
      write_link "${LOG_PATH_MODULE}"/snmp-check-public-"${IP_ADDRESS_}".txt
      cat "${LOG_PATH_MODULE}"/snmp-check-public-"${IP_ADDRESS_}".txt
    fi
    print_ln
    print_output "[*] SNMP scan with community name ${ORANGE}private${NC}"
    snmp-check -c private -w "${IP_ADDRESS_}" >> "${LOG_PATH_MODULE}"/snmp-check-private-"${IP_ADDRESS_}".txt
    if [[ -f "${LOG_PATH_MODULE}"/snmp-check-private-"${IP_ADDRESS_}".txt ]]; then
      write_link "${LOG_PATH_MODULE}"/snmp-check-private-"${IP_ADDRESS_}".txt
      cat "${LOG_PATH_MODULE}"/snmp-check-private-"${IP_ADDRESS_}".txt
    fi
  fi

  print_output "[*] SNMP walk with community name ${ORANGE}public${NC}"
  snmpwalk -v2c -c public "${IP_ADDRESS_}" .iso | tee "${LOG_PATH_MODULE}"/snmpwalk-public-"${IP_ADDRESS_}".txt || true
  if [[ -f "${LOG_PATH_MODULE}"/snmpwalk-public-"${IP_ADDRESS_}".txt ]]; then
    write_link "${LOG_PATH_MODULE}"/snmpwalk-public-"${IP_ADDRESS_}".txt
    cat "${LOG_PATH_MODULE}"/snmpwalk-public-"${IP_ADDRESS_}".txt
  fi
  print_ln
  print_output "[*] SNMP walk with community name ${ORANGE}private${NC}"
  snmpwalk -v2c -c private "${IP_ADDRESS_}" .iso | tee "${LOG_PATH_MODULE}"/snmapwalk-private-"${IP_ADDRESS_}".txt || true
  if [[ -f "${LOG_PATH_MODULE}"/snmpwalk-private-"${IP_ADDRESS_}".txt ]]; then
    write_link "${LOG_PATH_MODULE}"/snmpwalk-private-"${IP_ADDRESS_}".txt
    cat "${LOG_PATH_MODULE}"/snmpwalk-private-"${IP_ADDRESS_}".txt
  fi

  SNMP_UP=$(wc -l "${LOG_PATH_MODULE}"/snmp* | tail -1 | awk '{print $1}')

  if [[ "${SNMP_UP}" -gt 20 ]]; then
    SNMP_UP=1
  else
    SNMP_UP=0
  fi

  print_ln
  print_output "[*] SNMP basic tests for emulated system with IP ${ORANGE}${IP_ADDRESS_}${NC} finished"
}

check_snmp_vulns() {
  local IP_ADDRESS_="${1:-}"
  local SNMP_UP_tmp=0
  local OID=""
  local OIDs=()

  sub_module_title "SNMP firmadyne disclosure checks"

  print_output "[*] This module tests multiple information disclosure vulnerabilities (${ORANGE}CVE-2016-1557 / CVE-2016-1559${NC})"

  OIDs=( "iso.3.6.1.4.1.171.10.37.35.2.1.3.3.2.1.1.4" "iso.3.6.1.4.1.171.10.37.38.2.1.3.3.2.1.1.4" \
    "iso.3.6.1.4.1.171.10.37.35.4.1.1.1" "iso.3.6.1.4.1.171.10.37.37.4.1.1.1" "iso.3.6.1.4.1.171.10.37.38.4.1.1.1" \
    "iso.3.6.1.4.1.4526.100.7.8.1.5" "iso.3.6.1.4.1.4526.100.7.9.1.5" "iso.3.6.1.4.1.4526.100.7.9.1.7" \
    "iso.3.6.1.4.1.4526.100.7.10.1.7" )

  for OID in "${OIDs[@]}"; do
    print_output "[*] Testing OID ${ORANGE}${OID}${NC} on IP address ${ORANGE}${IP_ADDRESS_}${NC} ..."
    snmpwalk -v 2c -c public "${IP_ADDRESS_}" "${OID}" >> "${LOG_PATH_MODULE}"/snmpwalk-firmadyne_disclosure-"${IP_ADDRESS_}"-"${OID}".txt || true
    snmpwalk -v 1 -c public "${IP_ADDRESS_}" "${OID}" >> "${LOG_PATH_MODULE}"/snmpwalk-firmadyne_disclosure-"${IP_ADDRESS_}"-"${OID}".txt || true
    # remove "No Such Object" entries from the counting results:
    if [[ $(grep -v -c "No Such Object" "${LOG_PATH_MODULE}"/snmpwalk-firmadyne_disclosure-"${IP_ADDRESS_}"-"${OID}".txt) -gt 0 ]]; then
      print_ln
      print_output "[+] Possible credential disclosure detected (${ORANGE}CVE-2016-1557 / CVE-2016-1559${GREEN}):${NC}"
      tee -a "${LOG_FILE}" < "${LOG_PATH_MODULE}"/snmpwalk-firmadyne_disclosure-"${IP_ADDRESS_}"-"${OID}".txt
      print_ln
    else
      rm "${LOG_PATH_MODULE}"/snmpwalk-firmadyne_disclosure-"${IP_ADDRESS_}"-"${OID}".txt || true
    fi
  done

  SNMP_UP_tmp=$(wc -l "${LOG_PATH_MODULE}"/snmp* | tail -1 | awk '{print $1}')

  if [[ "${SNMP_UP_tmp}" -gt 20 ]]; then
    SNMP_UP=1
  fi

  # TODO: check output for vulnerability and integrate it into f20/f50

  print_ln
  print_output "[*] SNMP vulnerability tests for emulated system with IP ${ORANGE}${IP_ADDRESS_}${NC} finished"

}
