#!/bin/bash
# ==========================================================
# Menue 11 - Problem loesen (Reparatur-Assistenten)
# ==========================================================

# ================================================================
# REPARATUR - LOESUNGEN FUER HAEUFIGE PROXMOX-PROBLEME
# ================================================================
#
# Alle Punkte sind so gebaut, dass man KEINE Konsolenbefehle
# tippen muss. Jeder Punkt erklaert vorher in einfacher Sprache,
# was das Problem ist und was jetzt gemacht wird.

erklaere_und_frage() {
    # $1 = Titel, $2 = Erklaerung, $3 = was wird gemacht
    confirm "PROBLEM\n$2\n\nWAS JETZT PASSIERT\n$3\n\nJetzt ausfuehren?" "$1"
}

# ---------- 1. Weboberflaeche und Zugriff ----------

fix_weboberflaeche_neustart() {
    if erklaere_und_frage "Weboberflaeche nicht erreichbar" \
        "Die Proxmox-Weboberflaeche (Adresse mit :8006) laedt nicht mehr,\nzeigt eine leere Seite oder meldet einen Verbindungsfehler.\nDie VMs laufen dabei meist ganz normal weiter." \
        "Die Dienste hinter der Weboberflaeche werden neu gestartet.\nDas dauert wenige Sekunden. Laufende VMs und Container sind\ndavon NICHT betroffen - sie laufen einfach weiter."; then
        run_and_show "systemctl restart pveproxy pvedaemon; sleep 3; systemctl is-active pveproxy pvedaemon pve-cluster pvestatd; echo ''; echo 'Bitte die Weboberflaeche im Browser neu laden (Strg+F5).'" "Weboberflaeche neu gestartet"
        log_action "Weboberflaeche neu gestartet"
    fi
}

fix_weboberflaeche_pruefen() {
    run_and_show "echo '--- Laufen die Dienste? ---'
for D in pve-cluster pvedaemon pveproxy pvestatd pvescheduler; do
    printf '%-16s ' \"\$D\"
    systemctl is-active \$D 2>/dev/null || echo 'nicht vorhanden'
done
echo ''
echo '--- Lauscht der Server auf Port 8006? ---'
ss -tlnp 2>/dev/null | grep 8006 || echo 'NEIN - der Webdienst nimmt keine Verbindungen an.'
echo ''
echo '--- IP-Adressen dieses Servers ---'
ip -4 addr show 2>/dev/null | awk '/inet /{print \"  \" \$2, \"(\" \$NF \")\"}'
echo ''
echo '--- Ist die Systemplatte voll? (haeufige Ursache) ---'
df -h / 2>/dev/null | tail -1
echo ''
echo 'Erreichbar unter: https://<eine der IPs oben>:8006'" "Weboberflaeche - Diagnose"
}

fix_zertifikat_neu() {
    if erklaere_und_frage "Zertifikatsfehler im Browser" \
        "Der Browser meldet ein ungueltiges oder abgelaufenes Zertifikat,\noder die Verbindung wird komplett verweigert. Das passiert\nzum Beispiel, wenn der Servername geaendert wurde." \
        "Proxmox erstellt sich ein neues eigenes Zertifikat und startet\nden Webdienst neu. Danach musst du im Browser einmalig wieder\nbestaetigen, dass du der Seite vertraust."; then
        run_and_show "pvecm updatecerts --force 2>&1; systemctl restart pveproxy; sleep 2; echo ''; echo 'Fertig. Browser-Cache leeren und Seite neu laden (Strg+F5).'" "Zertifikat neu erstellt"
        log_action "Zertifikate neu erstellt"
    fi
}

fix_subscription_hinweis() {
    if erklaere_und_frage "Meldung 'Keine gueltige Subscription'" \
        "Bei jeder Anmeldung erscheint ein Fenster mit dem Hinweis\n'You do not have a valid subscription'. Ausserdem schlagen\nUpdates fehl, weil das kostenpflichtige Paketquellen-Repo\nnicht erreichbar ist." \
        "Das kostenpflichtige Enterprise-Repo wird abgeschaltet und\nstattdessen das kostenlose No-Subscription-Repo eingetragen.\nDanach funktionieren Updates wieder normal.\n\nHinweis: Das Hinweisfenster selbst bleibt - es laesst sich\nohne Eingriff in Proxmox-Dateien nicht sauber entfernen."; then
        local TMPFILE
        TMPFILE=$(mktemp)
        {
            echo "--- Enterprise-Repos werden deaktiviert ---"
            for F in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
                [ -f "$F" ] || continue
                if grep -qE '^[^#].*enterprise\.proxmox\.com' "$F"; then
                    cp -a "$F" "$BACKUP_DIR/$(basename "$F").$(date +%Y%m%d_%H%M%S).bak"
                    sed -i -E '/^[^#].*enterprise\.proxmox\.com/ s/^/#/' "$F"
                    echo "  deaktiviert in: $F"
                fi
            done
            for F in /etc/apt/sources.list.d/*.sources; do
                [ -f "$F" ] || continue
                if grep -q 'enterprise\.proxmox\.com' "$F"; then
                    cp -a "$F" "$BACKUP_DIR/$(basename "$F").$(date +%Y%m%d_%H%M%S).bak"
                    if grep -q '^Enabled:' "$F"; then
                        sed -i 's/^Enabled:.*/Enabled: false/' "$F"
                    else
                        echo "Enabled: false" >> "$F"
                    fi
                    echo "  deaktiviert in: $F"
                fi
            done

            echo ""
            echo "--- Kostenloses Repo wird eingerichtet ---"
            CODENAME=$(. /etc/os-release 2>/dev/null; echo "${VERSION_CODENAME:-bookworm}")
            if grep -rq 'pve-no-subscription' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
                sed -i -E '/pve-no-subscription/ s/^#\s*//' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null
                echo "  war bereits vorhanden, wurde aktiviert"
            else
                echo "deb http://download.proxmox.com/debian/pve $CODENAME pve-no-subscription" \
                    > /etc/apt/sources.list.d/pve-no-subscription.list
                echo "  neu angelegt: /etc/apt/sources.list.d/pve-no-subscription.list"
            fi

            echo ""
            echo "--- Paketlisten werden aktualisiert ---"
            apt-get update 2>&1 | tail -15
        } > "$TMPFILE" 2>&1
        info_textbox "$TMPFILE" "Paketquellen umgestellt"
        rm -f "$TMPFILE"
        log_action "Enterprise-Repo deaktiviert, No-Subscription-Repo aktiviert"
    fi
}

menu_weboberflaeche() {
    local LAST="1"
    while true; do
        local C
        C=$(menu_dialog "Weboberflaeche und Zugriff" \
            "Probleme beim Zugriff auf Proxmox ueber den Browser." \
            20 96 5 "$LAST" \
            "1" "Weboberflaeche laedt nicht - Dienste neu starten" \
            "2" "Nachsehen woran es liegt (Diagnose)" \
            "3" "Zertifikatsfehler im Browser beheben" \
            "4" "Meldung 'Keine gueltige Subscription' / Updates gehen nicht")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            1) fix_weboberflaeche_neustart ;;
            2) fix_weboberflaeche_pruefen ;;
            3) fix_zertifikat_neu ;;
            4) fix_subscription_hinweis ;;
        esac
    done
}

# ---------- 2. VMs und Container starten nicht ----------

waehle_gast() {
    # Laesst den Nutzer eine VM oder einen Container auswaehlen
    # Gibt "qm 100" oder "pct 200" zurueck
    local ITEMS=() ID NAME STATUS
    while read -r ID STATUS NAME; do
        [ -z "$ID" ] && continue
        ITEMS+=("qm:$ID" "VM $ID - ${NAME:-ohne Namen} (Status: $STATUS)")
    done < <(qm list 2>/dev/null | awk 'NR>1{print $1, $3, $2}')
    while read -r ID STATUS NAME; do
        [ -z "$ID" ] && continue
        ITEMS+=("pct:$ID" "Container $ID - ${NAME:-ohne Namen} (Status: $STATUS)")
    done < <(pct list 2>/dev/null | awk 'NR>1{print $1, $2, $3}')

    if [ ${#ITEMS[@]} -eq 0 ]; then
        pause "Auf diesem Server sind keine VMs oder Container vorhanden."
        return 1
    fi

    menu_dialog "System auswaehlen" "Welche VM oder welchen Container meinst du?" 24 96 14 "" "${ITEMS[@]}"
}

fix_gast_entsperren() {
    if ! confirm "PROBLEM\nEine VM oder ein Container laesst sich nicht starten, stoppen\noder sichern. Es erscheint eine Meldung wie 'VM is locked'\noder 'got lock request timeout'.\n\nURSACHE\nEin frueherer Vorgang (meist eine abgebrochene Sicherung oder\nMigration) wurde nicht sauber beendet und hat eine Sperre\nhinterlassen.\n\nJetzt fortfahren und ein System auswaehlen?" "Sperre aufheben"; then
        return
    fi
    local SEL
    SEL=$(waehle_gast) || return
    [ -z "${SEL:-}" ] && return
    local TYP="${SEL%%:*}" ID="${SEL#*:}"

    if confirm "Sperre fuer ID $ID wirklich aufheben?\n\nWICHTIG: Stelle sicher, dass gerade wirklich KEINE Sicherung\noder Migration fuer dieses System laeuft. Sonst kann die\nvirtuelle Festplatte beschaedigt werden.\n\nUnter 'Tasks' in der Weboberflaeche siehst du laufende Vorgaenge."; then
        run_and_show "$TYP unlock $ID 2>&1; echo ''; echo 'Sperre aufgehoben. Versuche jetzt erneut zu starten.'; $TYP status $ID 2>&1" "Sperre aufgehoben"
        log_action "Sperre aufgehoben fuer $TYP $ID"
    fi
}

fix_gast_startet_nicht() {
    local SEL
    pause "Diese Funktion sammelt alle Informationen, die erklaeren\nkoennen, warum eine VM oder ein Container nicht startet:\n\n- Konfiguration des Systems\n- Zustand der benoetigten Speicher\n- Vorhandene Sperren\n- Die letzten Fehlermeldungen aus dem Protokoll\n\nDu musst nichts tippen - waehle im naechsten Schritt einfach\ndas betroffene System aus." "Startprobleme untersuchen"
    SEL=$(waehle_gast) || return
    [ -z "${SEL:-}" ] && return
    local TYP="${SEL%%:*}" ID="${SEL#*:}"

    run_and_show "echo '--- Aktueller Status ---'
$TYP status $ID 2>&1
echo ''
echo '--- Konfiguration ---'
$TYP config $ID 2>&1
echo ''
echo '--- Ist eine Sperre gesetzt? ---'
$TYP config $ID 2>/dev/null | grep -i '^lock' || echo 'Keine Sperre gesetzt (gut)'
echo ''
echo '--- Sind alle Speicher erreichbar? ---'
pvesm status 2>&1
echo ''
echo '--- Freier Arbeitsspeicher ---'
free -h
echo ''
echo '--- Letzte Fehlermeldungen zu ID $ID ---'
journalctl --since '2 hours ago' 2>/dev/null | grep -i \"$ID\" | tail -30 || echo 'Keine Eintraege gefunden'
echo ''
echo '--- Startversuch (Testlauf) ---'
$TYP start $ID 2>&1 | tail -20" "Startproblem - Diagnose ID $ID"
}

fix_gast_startreihenfolge() {
    run_and_show "echo 'Startreihenfolge nach einem Neustart des Servers'
echo '================================================'
echo ''
echo 'Systeme, die beim Booten automatisch starten sollen:'
echo ''
for ID in \$(qm list 2>/dev/null | awk 'NR>1{print \$1}'); do
    ON=\$(qm config \$ID 2>/dev/null | awk -F': ' '/^onboot:/{print \$2}')
    ORDER=\$(qm config \$ID 2>/dev/null | awk -F': ' '/^startup:/{print \$2}')
    NAME=\$(qm config \$ID 2>/dev/null | awk -F': ' '/^name:/{print \$2}')
    printf '  VM %-6s %-24s Autostart: %-4s %s\n' \"\$ID\" \"\$NAME\" \"\${ON:-nein}\" \"\$ORDER\"
done
for ID in \$(pct list 2>/dev/null | awk 'NR>1{print \$1}'); do
    ON=\$(pct config \$ID 2>/dev/null | awk -F': ' '/^onboot:/{print \$2}')
    ORDER=\$(pct config \$ID 2>/dev/null | awk -F': ' '/^startup:/{print \$2}')
    NAME=\$(pct config \$ID 2>/dev/null | awk -F': ' '/^hostname:/{print \$2}')
    printf '  CT %-6s %-24s Autostart: %-4s %s\n' \"\$ID\" \"\$NAME\" \"\${ON:-nein}\" \"\$ORDER\"
done
echo ''
echo 'Aendern in der Weboberflaeche:'
echo '  System auswaehlen -> Options -> Start at boot'
echo '  und Start/Shutdown order fuer die Reihenfolge.'" "Startreihenfolge"
}

fix_alle_starten() {
    if erklaere_und_frage "Nach einem Neustart laeuft nichts mehr" \
        "Nach einem Server-Neustart oder Stromausfall sind VMs und\nContainer nicht wieder hochgekommen, weil der Autostart nicht\ngesetzt ist oder ein Speicher zu spaet bereit war." \
        "Alle Systeme, die auf Autostart gesetzt sind, werden jetzt\nnacheinander gestartet. Systeme, die schon laufen, werden\nuebersprungen."; then
        run_and_show "for ID in \$(qm list 2>/dev/null | awk 'NR>1 && \$3!=\"running\"{print \$1}'); do
    if qm config \$ID 2>/dev/null | grep -q '^onboot: 1'; then
        echo \"Starte VM \$ID ...\"; qm start \$ID 2>&1; sleep 3
    fi
done
for ID in \$(pct list 2>/dev/null | awk 'NR>1 && \$2!=\"running\"{print \$1}'); do
    if pct config \$ID 2>/dev/null | grep -q '^onboot: 1'; then
        echo \"Starte Container \$ID ...\"; pct start \$ID 2>&1; sleep 2
    fi
done
echo ''
echo '--- Zustand jetzt ---'
qm list 2>/dev/null; echo ''; pct list 2>/dev/null" "Autostart-Systeme gestartet"
        log_action "Alle Autostart-Systeme gestartet"
    fi
}

menu_gaeste() {
    local LAST="1"
    while true; do
        local C
        C=$(menu_dialog "VMs und Container starten nicht" \
            "Probleme mit virtuellen Maschinen und Containern." \
            20 96 5 "$LAST" \
            "1" "Meldung 'is locked' - Sperre aufheben" \
            "2" "System startet nicht - Ursache suchen" \
            "3" "Nach Neustart laeuft nichts - alles wieder starten" \
            "4" "Startreihenfolge und Autostart ansehen")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            1) fix_gast_entsperren ;;
            2) fix_gast_startet_nicht ;;
            3) fix_alle_starten ;;
            4) fix_gast_startreihenfolge ;;
        esac
    done
}

# ---------- 3. Speicherplatz und Speicher ----------

fix_speicher_uebersicht() {
    run_and_show "echo '--- Belegung aller Laufwerke ---'
df -h -x tmpfs -x devtmpfs 2>/dev/null
echo ''
echo '--- Proxmox-Speicher ---'
pvesm status 2>&1
echo ''
echo '--- ZFS-Pools ---'
zpool list 2>/dev/null || echo 'Kein ZFS im Einsatz'
echo ''
echo '--- Die groessten Verbraucher unterhalb von /var ---'
du -h --max-depth=2 /var 2>/dev/null | sort -rh | head -15
echo ''
echo '--- Groesse der Sicherungen ---'
du -sh /var/lib/vz/dump 2>/dev/null || echo 'Kein Sicherungsverzeichnis gefunden'
echo ''
echo '--- Groesse der System-Protokolle ---'
journalctl --disk-usage 2>/dev/null" "Speicherplatz - Uebersicht"
}

fix_speicher_freimachen() {
    if erklaere_und_frage "Festplatte ist voll" \
        "Die Systemplatte ist voll oder fast voll. Typische Folgen:\ndie Weboberflaeche zeigt Fehler, VMs starten nicht mehr,\nSicherungen schlagen fehl und die Konfiguration wird\nschreibgeschuetzt." \
        "In einem Durchgang wird sicher aufgeraeumt:\n  - System-Protokolle auf 500 MB begrenzt\n  - heruntergeladene Installationsdateien geloescht\n  - alte temporaere Dateien geloescht\n  - nicht mehr benoetigte Pakete entfernt\n\nVMs, Container und Sicherungen werden dabei NICHT angeruehrt."; then
        run_and_show "echo '--- Vorher ---'; df -h / | tail -1; echo ''
echo '--- System-Protokolle begrenzen ---'
journalctl --vacuum-size=500M 2>&1 | tail -3
echo ''
echo '--- Installationsdateien loeschen ---'
du -sh /var/cache/apt/archives 2>/dev/null; apt-get clean; echo 'erledigt'
echo ''
echo '--- Alte temporaere Dateien loeschen ---'
find /tmp /var/tmp -type f -mtime +7 -size +10M -delete -print 2>/dev/null | head -20
echo ''
echo '--- Nicht mehr benoetigte Pakete entfernen ---'
apt-get autoremove --purge -y 2>&1 | tail -5
echo ''
echo '--- Nachher ---'; df -h / | tail -1" "Speicherplatz freigemacht"
        log_action "Speicherplatz-Aufraeumung durchgefuehrt"
    fi
}

fix_alte_backups_loeschen() {
    local TAGE
    TAGE=$(eingabe_dialog "Alte Sicherungen loeschen" \
        "Sicherungen, die aelter sind als diese Anzahl Tage,\nwerden geloescht.\n\nVorsicht: Das laesst sich nicht rueckgaengig machen.\nEmpfehlung: nicht unter 14 Tage gehen." "30")
    [ -z "${TAGE:-}" ] && return

    local TMPFILE
    TMPFILE=$(mktemp)
    find /var/lib/vz/dump -maxdepth 2 -name 'vzdump-*' -type f -mtime +"$TAGE" -printf '%TY-%Tm-%Td  %10s  %p\n' 2>/dev/null > "$TMPFILE"

    if [ ! -s "$TMPFILE" ]; then
        pause "Es wurden keine Sicherungen gefunden, die aelter als $TAGE Tage sind.\n\nEs wurde nichts geloescht."
        rm -f "$TMPFILE"
        return
    fi

    info_textbox "$TMPFILE" "Diese Sicherungen wuerden geloescht"
    local ANZ
    ANZ=$(wc -l < "$TMPFILE")
    rm -f "$TMPFILE"

    if confirm_risky "Diese $ANZ Sicherungsdatei(en) wirklich endgueltig loeschen?\n\nDas kann NICHT rueckgaengig gemacht werden." "Endgueltig loeschen"; then
        run_and_show "find /var/lib/vz/dump -maxdepth 2 -name 'vzdump-*' -mtime +$TAGE -print -delete 2>/dev/null; echo ''; echo '--- Freier Platz jetzt ---'; df -h /var/lib/vz 2>/dev/null | tail -1" "Alte Sicherungen geloescht"
        log_action "Sicherungen aelter als $TAGE Tage geloescht"
    fi
}

fix_verwaiste_disks() {
    local TMPFILE
    TMPFILE=$(mktemp)
    {
        echo "Virtuelle Festplatten, deren VM/Container nicht mehr existiert"
        echo "=============================================================="
        echo ""
        VORHANDEN=$( (pct list 2>/dev/null | awk 'NR>1{print $1}'; qm list 2>/dev/null | awk 'NR>1{print $1}') )
        GEF=0
        for DS in $(zfs list -H -o name 2>/dev/null | grep -E 'subvol-|vm-'); do
            ID=$(echo "$DS" | grep -oE '(subvol|vm)-[0-9]+' | grep -oE '[0-9]+')
            [ -z "$ID" ] && continue
            if ! echo "$VORHANDEN" | grep -qx "$ID"; then
                echo "  $DS   (belegt $(zfs list -H -o used "$DS" 2>/dev/null))"
                GEF=1
            fi
        done
        [ "$GEF" -eq 0 ] && echo "  Keine verwaisten Festplatten gefunden - alles sauber."
        echo ""
        echo "WICHTIG"
        echo "  Hier wird bewusst nichts automatisch geloescht. Pruefe die"
        echo "  Liste in Ruhe - manchmal gehoert so ein Eintrag noch zu einem"
        echo "  System auf einem anderen Server im Cluster."
        echo ""
        echo "  Loeschen kannst du sie in der Weboberflaeche unter"
        echo "  Datacenter -> Storage -> <Speicher> -> VM Disks."
    } > "$TMPFILE"
    info_textbox "$TMPFILE" "Verwaiste virtuelle Festplatten"
    rm -f "$TMPFILE"
}

fix_lvm_thin() {
    run_and_show "echo '--- LVM-Thin-Pools ---'
lvs -o lv_name,vg_name,lv_size,data_percent,metadata_percent 2>/dev/null || echo 'LVM wird auf diesem System nicht genutzt'
echo ''
echo 'ERKLAERUNG'
echo '  Data%  = wie voll der eigentliche Datenbereich ist'
echo '  Meta%  = wie voll die Verwaltungsinformationen sind'
echo ''
echo '  Beide Werte muessen deutlich unter 100% bleiben. Wird einer'
echo '  davon voll, koennen VM-Festplatten beschaedigt werden.'
echo '  Ab 85% solltest du handeln: alte Systeme oder Snapshots'
echo '  loeschen oder den Pool vergroessern.'" "LVM-Thin-Speicher pruefen"
}

fix_speicher_erreichbarkeit() {
    run_and_show "echo '--- Zustand aller eingebundenen Speicher ---'
pvesm status 2>&1
echo ''
echo '--- Eingebundene Netzwerkfreigaben ---'
mount 2>/dev/null | grep -E 'type (nfs|nfs4|cifs)' || echo 'Keine Netzwerkfreigaben eingebunden'
echo ''
echo 'ERKLAERUNG'
echo '  Steht bei einem Speicher nicht \"active\", ist er gerade nicht'
echo '  erreichbar. VMs auf diesem Speicher starten dann nicht und'
echo '  Sicherungen darauf schlagen fehl.'
echo ''
echo '  Haeufige Ursachen: NAS ausgeschaltet, Netzwerkkabel, falsche'
echo '  Zugangsdaten, oder der Speicher wurde umbenannt.'" "Speicher erreichbar?"
}

menu_speicher() {
    local LAST="1"
    while true; do
        local C
        C=$(menu_dialog "Speicherplatz und Speicher" \
            "Festplatte voll, Speicher nicht erreichbar, aufraeumen." \
            22 96 6 "$LAST" \
            "1" "Wo ist der Platz hin? (Uebersicht)" \
            "2" "Festplatte voll - sicher aufraeumen" \
            "3" "Alte Sicherungen loeschen (mit Vorschau)" \
            "4" "Speicher nicht erreichbar - pruefen" \
            "5" "Verwaiste Festplatten geloeschter VMs finden" \
            "6" "LVM-Thin-Speicher pruefen (Ueberfuellung)")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            1) fix_speicher_uebersicht ;;
            2) fix_speicher_freimachen ;;
            3) fix_alte_backups_loeschen ;;
            4) fix_speicher_erreichbarkeit ;;
            5) fix_verwaiste_disks ;;
            6) fix_lvm_thin ;;
        esac
    done
}

# ---------- 4. Netzwerk ----------

fix_netzwerk_uebersicht() {
    run_and_show "echo '--- Netzwerkkarten und Adressen ---'
ip -brief -4 addr show 2>/dev/null
echo ''
echo '--- Bruecken (Bridges) ---'
brctl show 2>/dev/null || ip -brief link show type bridge 2>/dev/null
echo ''
echo '--- Standard-Gateway ---'
ip route 2>/dev/null | grep '^default' || echo 'KEIN Gateway gesetzt - kein Internetzugang moeglich!'
echo ''
echo '--- Namensaufloesung (DNS) ---'
cat /etc/resolv.conf 2>/dev/null
echo ''
echo '--- Verbindungstest ---'
GW=\$(ip route 2>/dev/null | awk '/^default/{print \$3; exit}')
if [ -n \"\$GW\" ]; then
    ping -c 2 -W 2 \$GW >/dev/null 2>&1 && echo \"Gateway \$GW: erreichbar\" || echo \"Gateway \$GW: NICHT erreichbar\"
fi
ping -c 2 -W 3 1.1.1.1 >/dev/null 2>&1 && echo 'Internet: erreichbar' || echo 'Internet: NICHT erreichbar'
getent hosts download.proxmox.com >/dev/null 2>&1 && echo 'Namensaufloesung: funktioniert' || echo 'Namensaufloesung: FUNKTIONIERT NICHT'" "Netzwerk - Uebersicht"
}

fix_netzwerk_neuladen() {
    if confirm_risky "PROBLEM\nNach einer Aenderung an den Netzwerkeinstellungen ist die\nVerbindung weg oder die Aenderung wirkt nicht.\n\nWAS JETZT PASSIERT\nDie Netzwerkkonfiguration wird neu eingelesen und angewendet.\n\nACHTUNG\nWenn in der Konfiguration ein Fehler steckt, verlierst du\ndabei moeglicherweise die Verbindung zum Server und kommst\nnur noch ueber Bildschirm und Tastatur direkt am Geraet\nwieder heran.\n\nTrotzdem fortfahren?" "Netzwerk neu laden"; then
        if command -v ifreload &> /dev/null; then
            run_and_show "ifreload -a 2>&1; sleep 2; ip -brief -4 addr show" "Netzwerk neu geladen"
        else
            run_and_show "systemctl restart networking 2>&1; sleep 2; ip -brief -4 addr show" "Netzwerkdienst neu gestartet"
        fi
        log_action "Netzwerk neu geladen"
    fi
}

fix_firewall() {
    local STATUS
    STATUS=$(pve-firewall status 2>/dev/null | head -1)
    local C
    C=$(menu_dialog "Firewall" \
        "Aktueller Zustand: ${STATUS:-unbekannt}\n\nWenn du dich selbst ausgesperrt hast oder eine VM keine\nVerbindung bekommt, kann die Firewall die Ursache sein." \
        20 96 3 "" \
        "1" "Zustand und Regeln ansehen" \
        "2" "Firewall voruebergehend ausschalten (zum Testen)" \
        "3" "Firewall wieder einschalten")
    [ -z "${C:-}" ] && return
    case "$C" in
        1) run_and_show "pve-firewall status 2>&1; echo ''; echo '--- Regeln Datacenter ---'; cat /etc/pve/firewall/cluster.fw 2>/dev/null || echo 'keine'; echo ''; echo '--- Regeln dieser Server ---'; cat /etc/pve/nodes/\$(hostname)/host.fw 2>/dev/null || echo 'keine'" "Firewall-Zustand" ;;
        2)
            if confirm_risky "Firewall wirklich ausschalten?\n\nDer Server ist danach nicht mehr durch die Proxmox-Firewall\ngeschuetzt. Nur zum Eingrenzen eines Problems verwenden und\ndanach wieder einschalten." "Firewall ausschalten"; then
                run_and_show "pve-firewall stop 2>&1; sleep 1; pve-firewall status 2>&1" "Firewall ausgeschaltet"
                log_action "Firewall ausgeschaltet"
            fi
            ;;
        3)
            run_and_show "pve-firewall start 2>&1; sleep 1; pve-firewall status 2>&1" "Firewall eingeschaltet"
            log_action "Firewall eingeschaltet"
            ;;
    esac
}

fix_dns() {
    if erklaere_und_frage "Namensaufloesung geht nicht" \
        "Updates schlagen fehl mit Meldungen wie 'Temporary failure\nresolving...', Zertifikate lassen sich nicht erneuern und im\nCluster finden sich die Server nicht mehr." \
        "Es wird geprueft, welche DNS-Server eingetragen sind und ob\nsie antworten. Bei Bedarf kannst du danach einen funktionierenden\nDNS-Server eintragen."; then
        run_and_show "echo '--- Eingetragene DNS-Server ---'; cat /etc/resolv.conf 2>/dev/null
echo ''
echo '--- Test der Namensaufloesung ---'
for N in download.proxmox.com deb.debian.org google.com; do
    printf '%-28s ' \"\$N\"
    getent hosts \$N >/dev/null 2>&1 && echo 'OK' || echo 'FEHLGESCHLAGEN'
done
echo ''
echo '--- Sind die DNS-Server ueberhaupt erreichbar? ---'
grep '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print \$2}' | while read -r S; do
    printf '%-20s ' \"\$S\"
    ping -c 1 -W 2 \$S >/dev/null 2>&1 && echo 'antwortet' || echo 'antwortet NICHT'
done" "DNS - Diagnose"

        if confirm "Moechtest du jetzt einen anderen DNS-Server eintragen?\n\nEmpfehlung, falls dein Router nicht funktioniert:\n1.1.1.1 (Cloudflare) oder 9.9.9.9 (Quad9)"; then
            local NEU
            NEU=$(eingabe_dialog "DNS-Server" \
                "IP-Adresse des DNS-Servers eingeben:" "1.1.1.1")
            if [ -n "${NEU:-}" ]; then
                backup_file /etc/resolv.conf > /dev/null
                run_and_show "sed -i '1i nameserver $NEU' /etc/resolv.conf; echo 'Neuer Inhalt von /etc/resolv.conf:'; cat /etc/resolv.conf; echo ''; getent hosts download.proxmox.com >/dev/null 2>&1 && echo 'Test: Namensaufloesung funktioniert jetzt' || echo 'Test: funktioniert weiterhin nicht'" "DNS-Server eingetragen"
                log_action "DNS-Server $NEU eingetragen"
            fi
        fi
    fi
}

fix_freigaben_neuverbinden() {
    if erklaere_und_frage "Netzwerkfreigabe (NAS) haengt" \
        "Ein Verzeichnis vom NAS ist nicht mehr erreichbar oder das\nSystem haengt beim Zugriff darauf, obwohl das NAS laengst\nwieder laeuft." \
        "Alle in der Systemkonfiguration eingetragenen Netzwerkfreigaben\nwerden geprueft und bei Bedarf neu verbunden."; then
        run_and_show "GEF=0
awk '\$3==\"nfs\" || \$3==\"nfs4\" || \$3==\"cifs\" {print \$2}' /etc/fstab 2>/dev/null | while read -r MP; do
    GEF=1
    printf '%-40s ' \"\$MP\"
    if mountpoint -q \"\$MP\" 2>/dev/null; then
        echo 'bereits verbunden'
    else
        if mount \"\$MP\" 2>/dev/null; then echo 'neu verbunden'; else echo 'FEHLGESCHLAGEN - Server erreichbar?'; fi
    fi
done
awk '\$3==\"nfs\" || \$3==\"nfs4\" || \$3==\"cifs\"' /etc/fstab 2>/dev/null | grep -q . || echo 'In der Systemkonfiguration sind keine Netzwerkfreigaben eingetragen.'" "Netzwerkfreigaben"
        log_action "Netzwerkfreigaben neu verbunden"
    fi
}

menu_netzwerk() {
    local LAST="1"
    while true; do
        local C
        C=$(menu_dialog "Netzwerk-Probleme" \
            "Keine Verbindung, DNS geht nicht, Freigaben haengen." \
            20 96 5 "$LAST" \
            "1" "Netzwerk-Uebersicht und Verbindungstest" \
            "2" "Namensaufloesung (DNS) reparieren" \
            "3" "Netzwerkfreigaben (NAS) neu verbinden" \
            "4" "Firewall pruefen / aus- und einschalten" \
            "5" "Netzwerkeinstellungen neu laden (mit Warnung)")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            1) fix_netzwerk_uebersicht ;;
            2) fix_dns ;;
            3) fix_freigaben_neuverbinden ;;
            4) fix_firewall ;;
            5) fix_netzwerk_neuladen ;;
        esac
    done
}

# ---------- 5. Updates und Paketquellen ----------

fix_apt_reparieren() {
    if erklaere_und_frage "Updates schlagen fehl" \
        "Beim Installieren von Updates bricht der Vorgang ab, es\nerscheinen Meldungen wie 'dpkg was interrupted', 'unmet\ndependencies' oder 'could not get lock'." \
        "Die Paketverwaltung wird repariert: unterbrochene Installationen\nwerden abgeschlossen, fehlende Abhaengigkeiten nachinstalliert\nund die Paketlisten neu eingelesen. Das ist ein sicherer,\nstandardmaessiger Reparaturvorgang."; then
        run_and_show "echo '--- Haengende Sperren entfernen ---'
fuser -k /var/lib/dpkg/lock-frontend 2>/dev/null; fuser -k /var/lib/apt/lists/lock 2>/dev/null
rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock-frontend 2>/dev/null
echo 'erledigt'
echo ''
echo '--- Unterbrochene Installationen abschliessen ---'
dpkg --configure -a 2>&1 | tail -10
echo ''
echo '--- Fehlende Abhaengigkeiten nachinstallieren ---'
apt-get install -f -y 2>&1 | tail -10
echo ''
echo '--- Paketlisten neu einlesen ---'
apt-get update 2>&1 | tail -15" "Paketverwaltung repariert"
        log_action "Paketverwaltung repariert"
    fi
}

fix_paketquellen_anzeigen() {
    local TMPFILE
    TMPFILE=$(mktemp)
    {
        echo "Eingetragene Paketquellen"
        echo "=========================================================="
        echo ""
        for F in /etc/apt/sources.list /etc/apt/sources.list.d/*; do
            [ -f "$F" ] || continue
            echo "--- $F ---"
            grep -vE '^\s*$' "$F" | sed 's/^/  /'
            echo ""
        done
        echo "ERKLAERUNG"
        echo "  Zeilen die mit # beginnen sind abgeschaltet."
        echo "  Das Enterprise-Repo funktioniert nur mit bezahlter"
        echo "  Subscription. Ohne Subscription brauchst du stattdessen"
        echo "  das no-subscription-Repo."
    } > "$TMPFILE"
    info_textbox "$TMPFILE" "Paketquellen"
    rm -f "$TMPFILE"
}

fix_updates_installieren() {
    if confirm_risky "PROBLEM\nDas System soll auf den neuesten Stand gebracht werden.\n\nWAS JETZT PASSIERT\nAlle verfuegbaren Updates werden installiert (dist-upgrade).\n\nWICHTIG ZU WISSEN\n  - Der Vorgang kann einige Minuten dauern\n  - Laufende VMs sind normalerweise nicht betroffen\n  - Bei einem Kernel-Update ist danach ein Neustart faellig\n  - Auf produktiven Systemen: vorher Sicherung pruefen!\n\nJetzt installieren?" "Updates installieren"; then
        run_and_show "export DEBIAN_FRONTEND=noninteractive
apt-get update 2>&1 | tail -5
echo ''
echo '--- Installiere Updates ---'
apt-get dist-upgrade -y 2>&1 | tail -40
echo ''
echo '--- Ist ein Neustart faellig? ---'
LAEUFT=\$(uname -r)
echo \"Laufender Kernel: \$LAEUFT\"
dpkg -l 2>/dev/null | grep -E 'proxmox-kernel-[0-9]|pve-kernel-[0-9]' | awk '{print \"Installiert: \" \$3}' | tail -3" "Updates installiert"
        log_action "System-Updates installiert"
    fi
}

menu_updates() {
    local LAST="1"
    while true; do
        local C
        C=$(menu_dialog "Updates und Paketquellen" \
            "Updates gehen nicht, Subscription-Meldung, Paketquellen." \
            20 96 4 "$LAST" \
            "1" "Updates schlagen fehl - Paketverwaltung reparieren" \
            "2" "Subscription-Meldung / kostenloses Repo einrichten" \
            "3" "Eingetragene Paketquellen ansehen" \
            "4" "Alle Updates jetzt installieren")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            1) fix_apt_reparieren ;;
            2) fix_subscription_hinweis ;;
            3) fix_paketquellen_anzeigen ;;
            4) fix_updates_installieren ;;
        esac
    done
}

# ---------- 6. Festplatten und ZFS ----------

fix_zfs_status() {
    run_and_show "echo '--- Zustand aller ZFS-Pools ---'
zpool status 2>/dev/null || echo 'Kein ZFS im Einsatz'
echo ''
echo '--- Belegung ---'
zpool list 2>/dev/null
echo ''
echo 'ERKLAERUNG DER ZUSTAENDE'
echo '  ONLINE    Alles in Ordnung'
echo '  DEGRADED  Eine Platte ist ausgefallen - der Pool laeuft noch,'
echo '            aber ohne Ausfallsicherheit. JETZT handeln!'
echo '  FAULTED   Schwerer Fehler - Daten sind in Gefahr'
echo '  OFFLINE   Platte wurde bewusst abgeschaltet'
echo ''
echo '  Bei READ/WRITE/CKSUM-Fehlern groesser 0 kuendigt sich meist'
echo '  ein Plattendefekt an. Sicherung pruefen und Platte tauschen.'" "ZFS-Pools - Zustand"
}

fix_zfs_scrub() {
    local POOLS ITEMS=()
    POOLS=$(zpool list -H -o name 2>/dev/null)
    if [ -z "$POOLS" ]; then
        pause "Auf diesem System wird kein ZFS verwendet."
        return
    fi
    while IFS= read -r P; do
        ITEMS+=("$P" "Belegt: $(zpool list -H -o capacity "$P" 2>/dev/null), Zustand: $(zpool list -H -o health "$P" 2>/dev/null)")
    done <<< "$POOLS"

    local SEL
    SEL=$(menu_dialog "Datenpruefung starten" \
        "Ein Scrub liest alle gespeicherten Daten und prueft sie auf\nFehler. Erkannte Fehler werden bei gespiegelten Platten\nautomatisch repariert.\n\nDer Vorgang laeuft im Hintergrund weiter (je nach Datenmenge\nStunden) und macht das System dabei etwas langsamer.\n\nWelchen Pool pruefen?" \
        22 90 8 "" "${ITEMS[@]}")
    [ -z "${SEL:-}" ] && return

    run_and_show "zpool scrub '$SEL' 2>&1; sleep 2; zpool status '$SEL' 2>&1; echo ''; echo 'Der Scrub laeuft jetzt im Hintergrund.'; echo 'Den Fortschritt siehst du jederzeit unter Punkt 1.'" "Datenpruefung gestartet"
    log_action "ZFS-Scrub gestartet fuer Pool $SEL"
}

fix_zfs_fehler_zuruecksetzen() {
    local POOLS ITEMS=()
    POOLS=$(zpool list -H -o name 2>/dev/null)
    [ -z "$POOLS" ] && { pause "Auf diesem System wird kein ZFS verwendet."; return; }
    while IFS= read -r P; do ITEMS+=("$P" "Zustand: $(zpool list -H -o health "$P" 2>/dev/null)"); done <<< "$POOLS"

    local SEL
    SEL=$(menu_dialog "Fehlerzaehler zuruecksetzen" \
        "Nach einem behobenen Problem (zum Beispiel ein loses Kabel,\ndas wieder fest steckt) bleibt der Fehlerzaehler stehen.\n\nWICHTIG: Setze den Zaehler NUR zurueck, wenn du die Ursache\nwirklich behoben hast. Sonst uebersiehst du eine sterbende\nFestplatte.\n\nWelchen Pool?" \
        22 90 8 "" "${ITEMS[@]}")
    [ -z "${SEL:-}" ] && return

    if confirm_risky "Fehlerzaehler fuer Pool '$SEL' wirklich zuruecksetzen?" "Zuruecksetzen"; then
        run_and_show "zpool clear '$SEL' 2>&1; sleep 1; zpool status '$SEL' 2>&1" "Fehlerzaehler zurueckgesetzt"
        log_action "ZFS-Fehlerzaehler zurueckgesetzt fuer $SEL"
    fi
}

fix_zfs_arc_begrenzen() {
    local AKTUELL MAX GESAMT
    if [ -f /proc/spl/kstat/zfs/arcstats ]; then
        AKTUELL=$(awk '/^size /{printf "%.1f", $3/1024/1024/1024}' /proc/spl/kstat/zfs/arcstats)
        MAX=$(awk '/^c_max /{printf "%.1f", $3/1024/1024/1024}' /proc/spl/kstat/zfs/arcstats)
    fi
    GESAMT=$(free -g | awk '/^Mem:/{print $2}')

    if ! confirm "PROBLEM\nDie VMs haben zu wenig Arbeitsspeicher, weil ZFS einen grossen\nTeil davon als Cache belegt.\n\nAKTUELLE WERTE\n  Arbeitsspeicher gesamt:  ${GESAMT:-?} GB\n  ZFS-Cache belegt gerade: ${AKTUELL:-?} GB\n  ZFS-Cache Obergrenze:    ${MAX:-?} GB\n\nWAS DU WISSEN SOLLTEST\nZFS gibt den Cache eigentlich frei, wenn eine VM Speicher\nbraucht. Eine feste Grenze ist trotzdem sinnvoll, damit die\nAufteilung planbar bleibt.\n\nFaustregel: 1 GB Cache pro TB Speicher, mindestens 2 GB,\nhoechstens die Haelfte des Arbeitsspeichers.\n\nGrenze jetzt festlegen?" "ZFS-Cache begrenzen"; then
        return
    fi

    local NEU
    NEU=$(eingabe_dialog "Obergrenze fuer den ZFS-Cache" \
        "Obergrenze in Gigabyte eingeben:\n\nBei ${GESAMT:-?} GB Gesamtspeicher waere etwa\n$(( ${GESAMT:-8} / 4 )) GB ein vernuenftiger Wert." "$(( ${GESAMT:-8} / 4 ))")
    [ -z "${NEU:-}" ] && return

    if ! [[ "$NEU" =~ ^[0-9]+$ ]] || [ "$NEU" -lt 1 ]; then
        pause "Bitte eine ganze Zahl groesser 0 eingeben."
        return
    fi

    local BYTES=$(( NEU * 1024 * 1024 * 1024 ))
    run_and_show "echo $BYTES > /sys/module/zfs/parameters/zfs_arc_max 2>/dev/null && echo 'Sofort wirksam gesetzt.' || echo 'Konnte nicht sofort gesetzt werden.'
echo 'options zfs zfs_arc_max=$BYTES' > /etc/modprobe.d/zfs.conf
echo 'Dauerhaft gespeichert in /etc/modprobe.d/zfs.conf'
update-initramfs -u 2>&1 | tail -3
echo ''
echo 'Die Obergrenze liegt jetzt bei $NEU GB.'
echo 'Vollstaendig wirksam wird sie nach dem naechsten Neustart.'" "ZFS-Cache begrenzt"
    log_action "ZFS-ARC-Obergrenze auf $NEU GB gesetzt"
}

fix_smart() {
    run_and_show "command -v smartctl >/dev/null 2>&1 || { echo 'Das Programm smartctl fehlt.'; echo 'Nachinstallieren: Menue -> Reparatur -> Updates -> Paketverwaltung reparieren'; echo 'und danach: apt install smartmontools'; exit 0; }
echo '--- Zustand aller Festplatten und SSDs ---'
echo ''
for P in \$(lsblk -d -n -o NAME 2>/dev/null | grep -E '^sd|^nvme'); do
    MODELL=\$(smartctl -i /dev/\$P 2>/dev/null | awk -F': +' '/Device Model|Model Number/{print \$2; exit}')
    GESUND=\$(smartctl -H /dev/\$P 2>/dev/null | grep -iE 'result|status' | head -1 | cut -d: -f2-)
    STUNDEN=\$(smartctl -A /dev/\$P 2>/dev/null | awk '/Power_On_Hours|Power On Hours/{print \$10; exit}')
    DEFEKT=\$(smartctl -A /dev/\$P 2>/dev/null | awk '/Reallocated_Sector_Ct/{print \$10; exit}')
    echo \"/dev/\$P  \${MODELL:-unbekannt}\"
    echo \"   Gesundheit:       \${GESUND:-keine Angabe}\"
    echo \"   Betriebsstunden:  \${STUNDEN:-keine Angabe}\"
    echo \"   Defekte Sektoren: \${DEFEKT:-keine Angabe}\"
    echo ''
done
echo 'ERKLAERUNG'
echo '  PASSED / OK      Platte meldet sich als gesund'
echo '  FAILED           Platte meldet einen Defekt - sofort tauschen!'
echo '  Defekte Sektoren Sollte 0 sein. Steigt der Wert, stirbt die Platte.'" "Festplatten-Gesundheit"
}

menu_festplatten() {
    local LAST="1"
    while true; do
        local C
        C=$(menu_dialog "Festplatten und ZFS" \
            "Plattenfehler, ZFS-Pools, Arbeitsspeicher-Cache." \
            20 96 5 "$LAST" \
            "1" "Zustand der ZFS-Pools ansehen" \
            "2" "Gesundheit der Festplatten pruefen (SMART)" \
            "3" "Datenpruefung starten (Scrub)" \
            "4" "Fehlerzaehler zuruecksetzen (nach behobenem Problem)" \
            "5" "ZFS belegt zu viel Arbeitsspeicher - begrenzen")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            1) fix_zfs_status ;;
            2) fix_smart ;;
            3) fix_zfs_scrub ;;
            4) fix_zfs_fehler_zuruecksetzen ;;
            5) fix_zfs_arc_begrenzen ;;
        esac
    done
}

# ---------- 7. Cluster und Hochverfuegbarkeit ----------

fix_cluster_status() {
    run_and_show "if [ ! -f /etc/pve/corosync.conf ]; then
    echo 'Dieser Server ist kein Teil eines Clusters.'
    echo 'Alle Cluster-Funktionen sind hier ohne Bedeutung.'
    exit 0
fi
echo '--- Cluster-Zustand ---'
pvecm status 2>&1
echo ''
echo '--- Knoten im Cluster ---'
pvecm nodes 2>&1
echo ''
echo '--- Verbindungsqualitaet ---'
corosync-cfgtool -s 2>&1
echo ''
echo 'ERKLAERUNG'
echo '  Quorate: Yes  Der Cluster ist beschlussfaehig, alles in Ordnung'
echo '  Quorate: No   Zu wenige Server erreichbar. Die Konfiguration ist'
echo '                jetzt schreibgeschuetzt, VMs starten nicht mehr.'
echo ''
echo '  FAULTY bei den Verbindungen bedeutet, dass das Cluster-Netzwerk'
echo '  gestoert ist - haeufigste Ursache fuer unerklaerliche Ausfaelle.'" "Cluster-Zustand"
}

fix_cluster_dienste_neustart() {
    if confirm_risky "PROBLEM\nDer Cluster meldet Probleme, /etc/pve ist schreibgeschuetzt\noder die Server sehen sich gegenseitig nicht mehr.\n\nWAS JETZT PASSIERT\nDie Cluster-Dienste auf DIESEM Server werden neu gestartet.\n\nACHTUNG\nWaehrend des Neustarts ist dieser Server kurz nicht Teil des\nClusters. Bei aktivierter Hochverfuegbarkeit kann das im\nschlimmsten Fall einen automatischen Neustart des Servers\nausloesen (Fencing).\n\nBei aktiver HA lieber zuerst den Support-Weg gehen.\n\nTrotzdem fortfahren?" "Cluster-Dienste neu starten"; then
        run_and_show "systemctl restart corosync 2>&1; sleep 5; systemctl restart pve-cluster 2>&1; sleep 5
echo '--- Zustand danach ---'
systemctl is-active corosync pve-cluster
echo ''
pvecm status 2>&1 | head -20" "Cluster-Dienste neu gestartet"
        log_action "Cluster-Dienste neu gestartet"
    fi
}

fix_cluster_quorum_notfall() {
    if ! confirm_risky "NOTFALL-FUNKTION - BITTE GENAU LESEN\n\nPROBLEM\nDer Cluster hat kein Quorum, weil zu wenige Server laufen.\nDie Konfiguration ist schreibgeschuetzt und VMs lassen sich\nnicht starten.\n\nWAS DIESE FUNKTION MACHT\nSie setzt die Anzahl der benoetigten Stimmen auf 1 herunter.\nDamit kann DIESER Server allein weiterarbeiten.\n\nDIE GEFAHR\nWenn die anderen Server in Wahrheit noch laufen und du nur\ndie Netzwerkverbindung verloren hast, arbeiten danach mehrere\nServer unabhaengig voneinander an denselben Daten. Das nennt\nman Split-Brain und fuehrt zu Datenverlust.\n\nNUR verwenden, wenn du SICHER weisst, dass die anderen Server\nwirklich ausgeschaltet sind.\n\nWirklich fortfahren?" "NOTFALL - Split-Brain-Gefahr"; then
        return
    fi
    if ! confirm_risky "Letzte Rueckfrage:\n\nSind die anderen Cluster-Server WIRKLICH ausgeschaltet?" "Wirklich sicher?"; then
        return
    fi
    run_and_show "pvecm expected 1 2>&1; sleep 2; pvecm status 2>&1 | head -20; echo ''; echo 'WICHTIG: Sobald die anderen Server wieder laufen, muss der'; echo 'Cluster-Zustand geprueft werden.'" "Quorum herabgesetzt"
    log_action "NOTFALL: pvecm expected 1 ausgefuehrt"
}

fix_zeit() {
    if erklaere_und_frage "Uhrzeit stimmt nicht" \
        "Eine falsch gehende Uhr verursacht erstaunlich viele Probleme:\nZertifikate gelten als ungueltig, im Cluster streiten sich die\nServer, Sicherungen bekommen falsche Zeitstempel." \
        "Der Zustand der Zeitsynchronisierung wird geprueft und der\nZeitdienst neu gestartet, damit die Uhr sich neu abgleicht."; then
        run_and_show "echo '--- Vorher ---'
timedatectl status 2>&1
echo ''
echo '--- Zeitdienst neu starten ---'
systemctl restart systemd-timesyncd 2>/dev/null || systemctl restart chrony 2>/dev/null || echo 'Kein bekannter Zeitdienst gefunden'
sleep 5
echo ''
echo '--- Nachher ---'
timedatectl status 2>&1
command -v chronyc >/dev/null 2>&1 && chronyc tracking 2>&1 | head -8" "Zeitsynchronisierung"
        log_action "Zeitsynchronisierung neu gestartet"
    fi
}

fix_ha_status() {
    run_and_show "if ! command -v ha-manager >/dev/null 2>&1; then echo 'Hochverfuegbarkeit ist auf diesem System nicht verfuegbar.'; exit 0; fi
echo '--- Zustand der hochverfuegbaren Dienste ---'
ha-manager status 2>&1 || echo 'Keine HA-Dienste konfiguriert'
echo ''
echo '--- Konfiguration ---'
ha-manager config 2>&1 || echo 'Keine HA-Konfiguration vorhanden'
echo ''
echo 'ERKLAERUNG DER ZUSTAENDE'
echo '  started   Laeuft wie gewuenscht'
echo '  stopped   Bewusst gestoppt'
echo '  error     Fehler - muss von Hand quittiert werden'
echo '  fence     Der Server wird gerade zwangsweise neu gestartet'" "Hochverfuegbarkeit"
}

menu_cluster() {
    local LAST="1"
    while true; do
        local C
        C=$(menu_dialog "Cluster und Hochverfuegbarkeit" \
            "Nur relevant, wenn mehrere Proxmox-Server zusammenarbeiten." \
            20 96 5 "$LAST" \
            "1" "Cluster-Zustand ansehen" \
            "2" "Hochverfuegbarkeit (HA) ansehen" \
            "3" "Uhrzeit stimmt nicht - Zeitdienst reparieren" \
            "4" "Cluster-Dienste neu starten" \
            "5" "NOTFALL: Quorum herabsetzen (Split-Brain-Gefahr)")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            1) fix_cluster_status ;;
            2) fix_ha_status ;;
            3) fix_zeit ;;
            4) fix_cluster_dienste_neustart ;;
            5) fix_cluster_quorum_notfall ;;
        esac
    done
}

# ---------- 8. Dienste und System ----------

fix_dienste_status() {
    run_and_show "echo '--- Zustand der Proxmox-Dienste ---'
echo ''
for D in pve-cluster pvedaemon pveproxy pvestatd pvescheduler pve-firewall corosync; do
    systemctl list-unit-files 2>/dev/null | grep -q \"^\${D}.service\" || continue
    printf '  %-18s %s\n' \"\$D\" \"\$(systemctl is-active \$D 2>/dev/null)\"
done
echo ''
echo '--- Dienste mit Fehlern im gesamten System ---'
systemctl --failed --no-pager 2>&1 | head -20
echo ''
echo 'ERKLAERUNG DER DIENSTE'
echo '  pve-cluster    Verwaltet die Konfiguration (/etc/pve)'
echo '  pvedaemon      Fuehrt die eigentlichen Aufgaben aus'
echo '  pveproxy       Die Weboberflaeche'
echo '  pvestatd       Sammelt Statistiken und Zustaende'
echo '  pvescheduler   Startet geplante Sicherungen'" "Dienste-Zustand"
}

fix_dienste_neustart() {
    if erklaere_und_frage "Proxmox reagiert seltsam" \
        "Die Weboberflaeche zeigt keine aktuellen Werte an, Aufgaben\nbleiben haengen oder Statistiken fehlen - obwohl die VMs\nnormal weiterlaufen." \
        "Alle Proxmox-Kerndienste werden nacheinander neu gestartet.\nLaufende VMs und Container sind davon NICHT betroffen und\nlaufen einfach weiter. Die Weboberflaeche ist waehrenddessen\nfuer einige Sekunden nicht erreichbar."; then
        run_and_show "for D in pve-cluster pvedaemon pveproxy pvestatd pvescheduler; do
    systemctl list-unit-files 2>/dev/null | grep -q \"^\${D}.service\" || continue
    printf 'Starte %s neu ... ' \"\$D\"
    systemctl restart \$D 2>&1 && echo 'ok' || echo 'FEHLER'
    sleep 2
done
echo ''
echo '--- Zustand danach ---'
for D in pve-cluster pvedaemon pveproxy pvestatd pvescheduler; do
    systemctl list-unit-files 2>/dev/null | grep -q \"^\${D}.service\" || continue
    printf '  %-16s %s\n' \"\$D\" \"\$(systemctl is-active \$D)\"
done
echo ''
echo 'Bitte die Weboberflaeche neu laden (Strg+F5).'" "Dienste neu gestartet"
        log_action "Proxmox-Kerndienste neu gestartet"
    fi
}

fix_auslastung() {
    run_and_show "echo '--- Aktuelle Auslastung ---'
uptime
echo ''
echo '--- Arbeitsspeicher ---'
free -h
echo ''
echo '--- Die 15 groessten Verbraucher ---'
ps aux --sort=-%cpu 2>/dev/null | head -16 | awk '{printf \"%-8s %5s%% CPU %5s%% RAM  %s\n\", \$1, \$3, \$4, substr(\$11,1,50)}'
echo ''
echo '--- Speicherzuweisung der laufenden Systeme ---'
for ID in \$(qm list 2>/dev/null | awk 'NR>1 && \$3==\"running\"{print \$1}'); do
    M=\$(qm config \$ID 2>/dev/null | awk -F': ' '/^memory:/{print \$2}')
    N=\$(qm config \$ID 2>/dev/null | awk -F': ' '/^name:/{print \$2}')
    printf '  VM %-6s %-24s %s MB\n' \"\$ID\" \"\$N\" \"\$M\"
done
for ID in \$(pct list 2>/dev/null | awk 'NR>1 && \$2==\"running\"{print \$1}'); do
    M=\$(pct config \$ID 2>/dev/null | awk -F': ' '/^memory:/{print \$2}')
    N=\$(pct config \$ID 2>/dev/null | awk -F': ' '/^hostname:/{print \$2}')
    printf '  CT %-6s %-24s %s MB\n' \"\$ID\" \"\$N\" \"\$M\"
done
echo ''
echo 'TIPP: Wenn in Summe mehr Speicher zugewiesen ist als vorhanden,'
echo 'wird das System bei Last sehr langsam.'" "Auslastung"
}

fix_haengende_aufgaben() {
    run_and_show "echo '--- Laufende Aufgaben ---'
pvesh get /nodes/\$(hostname)/tasks --running 1 --output-format text 2>/dev/null | head -25 || echo 'Konnte Aufgabenliste nicht abrufen'
echo ''
echo '--- Letzte fehlgeschlagene Aufgaben ---'
pvesh get /nodes/\$(hostname)/tasks --errors 1 --limit 15 --output-format text 2>/dev/null | head -25 || echo 'Keine Fehler gefunden'
echo ''
echo 'TIPP'
echo '  Haengt eine Sicherung sehr lange, ist meist der Zielspeicher'
echo '  nicht erreichbar. Abbrechen kannst du sie in der Weboberflaeche'
echo '  unten im Bereich Tasks per Rechtsklick -> Stop.'" "Laufende und fehlgeschlagene Aufgaben"
}

fix_initramfs() {
    if erklaere_und_frage "Server startet nicht mehr richtig" \
        "Nach einem Kernel-Update oder einer Aenderung an den\nFestplatten startet der Server nicht mehr sauber, oder es\nerscheinen Fehler beim Booten." \
        "Das Start-Abbild (initramfs) wird neu gebaut und die\nBootloader-Konfiguration aktualisiert. Das ist ein sicherer\nStandardvorgang und dauert einige Minuten."; then
        run_and_show "echo '--- Start-Abbild neu bauen ---'
update-initramfs -u -k all 2>&1 | tail -15
echo ''
if command -v proxmox-boot-tool >/dev/null 2>&1; then
    echo '--- Bootloader aktualisieren ---'
    proxmox-boot-tool refresh 2>&1 | tail -10
fi
echo ''
echo 'Fertig. Die Aenderung wird beim naechsten Neustart wirksam.'" "Start-Abbild neu gebaut"
        log_action "Initramfs neu gebaut"
    fi
}

menu_dienste() {
    local LAST="1"
    while true; do
        local C
        C=$(menu_dialog "Dienste und Systemzustand" \
            "Proxmox reagiert langsam, Aufgaben haengen, Dienste pruefen." \
            20 96 5 "$LAST" \
            "1" "Zustand aller Proxmox-Dienste ansehen" \
            "2" "Proxmox-Dienste neu starten" \
            "3" "System ist langsam - Auslastung ansehen" \
            "4" "Haengende und fehlgeschlagene Aufgaben ansehen" \
            "5" "Server startet nicht sauber - Start-Abbild neu bauen")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            1) fix_dienste_status ;;
            2) fix_dienste_neustart ;;
            3) fix_auslastung ;;
            4) fix_haengende_aufgaben ;;
            5) fix_initramfs ;;
        esac
    done
}

# ---------- 9. Aufraeumen und Fehlinstallationen ----------

fix_docker_pruefen() {
    run_and_show "echo '--- Ist Docker auf dem Proxmox-Host installiert? ---'
dpkg -l 2>/dev/null | grep -iE 'docker|containerd' || echo 'Keine Docker-Pakete installiert (gut so)'
echo ''
echo '--- Docker-Dienst ---'
systemctl status docker --no-pager 2>&1 | head -5 || echo 'Kein Docker-Dienst vorhanden'
echo ''
echo '--- Datenverzeichnisse ---'
for D in /var/lib/docker /var/lib/containerd /etc/docker; do
    if [ -d \"\$D\" ]; then echo \"  \$D vorhanden (\$(du -sh \$D 2>/dev/null | cut -f1))\"; else echo \"  \$D nicht vorhanden\"; fi
done
echo ''
echo 'WARUM IST DAS EIN PROBLEM?'
echo '  Docker direkt auf dem Proxmox-Host zu installieren fuehrt zu'
echo '  Konflikten beim Netzwerk und bei der Ressourcenverwaltung.'
echo '  Der richtige Weg: Docker in einer VM oder in einem LXC-Container'
echo '  betreiben, niemals direkt auf dem Host.'" "Docker auf dem Host?"
}

fix_docker_entfernen() {
    if ! dpkg -l 2>/dev/null | grep -qiE 'docker|containerd' && [ ! -d /var/lib/docker ]; then
        pause "Auf diesem Server ist kein Docker installiert.\n\nEs gibt nichts zu entfernen."
        return
    fi
    if ! confirm_risky "PROBLEM\nDocker wurde versehentlich direkt auf dem Proxmox-Host\ninstalliert statt in einer VM oder einem Container.\n\nWAS JETZT PASSIERT\n  - alle Docker- und Containerd-Pakete werden entfernt\n  - die Verzeichnisse /var/lib/docker, /var/lib/containerd\n    und /etc/docker werden geloescht\n  - nicht mehr benoetigte Pakete werden aufgeraeumt\n\nACHTUNG\nALLE Docker-Container, Images und Volumes auf diesem Host\ngehen dabei unwiderruflich verloren.\n\nWirklich fortfahren?" "Docker vom Host entfernen"; then
        return
    fi
    if ! confirm_risky "Letzte Rueckfrage: Wirklich alles loeschen?\n\nDies kann NICHT rueckgaengig gemacht werden." "Wirklich sicher?"; then
        return
    fi
    run_and_show "apt-get purge -y docker-ce docker-ce-cli docker-ce-rootless-extras containerd.io docker-buildx-plugin docker-compose-plugin docker.io docker-doc docker-compose podman-docker 2>&1 | tail -10
apt-get autoremove -y 2>&1 | tail -5
rm -rf /var/lib/docker /var/lib/containerd /etc/docker
groupdel docker 2>/dev/null
echo ''
echo 'Docker wurde vollstaendig vom Proxmox-Host entfernt.'
echo 'Fuer Container-Workloads bitte eine VM oder einen LXC-Container nutzen.'" "Docker entfernt"
    log_action "Docker vom Host entfernt"
}

fix_verwaiste_pakete() {
    local TMPFILE
    TMPFILE=$(mktemp)
    apt-get autoremove --dry-run 2>/dev/null > "$TMPFILE"
    if ! grep -q "Remv\|Remove" "$TMPFILE"; then
        pause "Es wurden keine ueberfluessigen Pakete gefunden.\n\nDas System ist in dieser Hinsicht sauber."
        rm -f "$TMPFILE"
        return
    fi
    info_textbox "$TMPFILE" "Diese Pakete wuerden entfernt (Vorschau)"
    rm -f "$TMPFILE"
    if confirm "Diese Pakete jetzt entfernen?\n\nEs handelt sich um Pakete, die nur als Abhaengigkeit\ninstalliert wurden und jetzt von nichts mehr benoetigt werden.\nDas Entfernen ist normalerweise unbedenklich."; then
        run_and_show "apt-get autoremove --purge -y 2>&1 | tail -20; echo ''; df -h / | tail -1" "Ueberfluessige Pakete entfernt"
        log_action "Verwaiste Pakete entfernt"
    fi
}

fix_konfigurationsreste() {
    local RESTE
    RESTE=$(dpkg -l 2>/dev/null | awk '/^rc/{print $2}')
    if [ -z "$RESTE" ]; then
        pause "Es wurden keine Konfigurationsreste gefunden.\n\nDas System ist sauber."
        return
    fi
    if confirm "Folgende Pakete sind zwar deinstalliert, haben aber noch\nEinstellungsdateien hinterlassen:\n\n$(echo "$RESTE" | head -20 | tr '\n' ' ')\n\nDiese Reste jetzt vollstaendig entfernen?"; then
        run_and_show "dpkg --purge $RESTE 2>&1 | tail -20" "Konfigurationsreste entfernt"
        log_action "Konfigurationsreste entfernt"
    fi
}

fix_defekte_verknuepfungen() {
    local TMPFILE
    TMPFILE=$(mktemp)
    {
        echo "Defekte Verknuepfungen (Symlinks) unter /usr/local, /opt und /etc"
        echo "=================================================================="
        echo ""
        find /usr/local /opt /etc -xtype l 2>/dev/null || true
        echo ""
        echo "(Wenn oben nichts steht, ist alles in Ordnung.)"
    } > "$TMPFILE"
    info_textbox "$TMPFILE" "Defekte Verknuepfungen"
    rm -f "$TMPFILE"
    if confirm "Die oben aufgelisteten defekten Verknuepfungen entfernen?\n\n(Falls die Liste leer war, passiert nichts.)"; then
        run_and_show "find /usr/local /opt /etc -xtype l -print -delete 2>/dev/null; echo ''; echo 'Fertig.'" "Verknuepfungen bereinigt"
        log_action "Defekte Symlinks entfernt"
    fi
}

menu_aufraeumen() {
    local LAST="1"
    while true; do
        local C
        C=$(menu_dialog "Aufraeumen und Fehlinstallationen" \
            "Versehentlich Installiertes und Ueberreste entfernen." \
            20 96 5 "$LAST" \
            "1" "Docker auf dem Host? - pruefen" \
            "2" "Docker vom Host entfernen" \
            "3" "Ueberfluessige Pakete entfernen" \
            "4" "Konfigurationsreste deinstallierter Pakete entfernen" \
            "5" "Defekte Verknuepfungen finden und entfernen")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            1) fix_docker_pruefen ;;
            2) fix_docker_entfernen ;;
            3) fix_verwaiste_pakete ;;
            4) fix_konfigurationsreste ;;
            5) fix_defekte_verknuepfungen ;;
        esac
    done
}

# ---------- 10. Konfigurationsdateien (fortgeschritten) ----------

WICHTIGE_DATEIEN=(
    "/etc/network/interfaces|Netzwerk-Einstellungen (IP, Bruecken)"
    "/etc/hosts|Zuordnung von Namen zu IP-Adressen"
    "/etc/resolv.conf|DNS-Server fuer die Namensaufloesung"
    "/etc/fstab|Dauerhaft eingebundene Laufwerke und Freigaben"
    "/etc/pve/storage.cfg|Speicher-Definitionen von Proxmox"
    "/etc/pve/datacenter.cfg|Clusterweite Grundeinstellungen"
    "/etc/apt/sources.list|Paketquellen fuer Updates"
    "/etc/vzdump.conf|Standardeinstellungen fuer Sicherungen"
)

datei_bearbeiten() {
    local DATEI="$1"
    if [ ! -f "$DATEI" ]; then
        pause "Die Datei existiert nicht:\n$DATEI"
        return
    fi
    if ! confirm "Datei bearbeiten:\n$DATEI\n\nVorher wird automatisch eine Sicherungskopie angelegt.\n\nDer Editor '$EDITOR_BIN' oeffnet sich gleich.\nSpeichern mit Strg+O, beenden mit Strg+X."; then
        return
    fi
    local SICHERUNG
    SICHERUNG=$(backup_file "$DATEI")
    clear
    "$EDITOR_BIN" "$DATEI"
    log_action "Datei bearbeitet: $DATEI"
    if [ -n "$SICHERUNG" ] && confirm "Aenderungen im Vergleich zur Sicherungskopie anzeigen?"; then
        run_and_show "diff -u '$SICHERUNG' '$DATEI' || true" "Was wurde geaendert?"
    fi
}

menu_dateien() {
    local LAST=""
    while true; do
        local ITEMS=() PFADE=() E NR=0
        for E in "${WICHTIGE_DATEIEN[@]}"; do
            NR=$((NR+1))
            PFADE[NR]="${E%%|*}"
            ITEMS+=("$NR" "$(fuellen "${E%%|*}" 26) ${E#*|}")
        done
        ITEMS+=("Z" "Eine fruehere Sicherungskopie zurueckspielen")
        ITEMS+=("L" "Vorhandene Sicherungskopien ansehen")

        local C
        C=$(menu_dialog "Konfigurationsdateien (fortgeschritten)" \
            "ACHTUNG: Hier bearbeitest du echte Systemdateien.\nVor jeder Aenderung wird automatisch eine Kopie angelegt.\n\nWenn du unsicher bist, nutze lieber die anderen Menuepunkte." \
            24 96 11 "$LAST" "${ITEMS[@]}")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            Z) sicherung_zurueckspielen ;;
            L) run_and_show "ls -lht '$BACKUP_DIR' 2>/dev/null | head -40 || echo 'Noch keine Sicherungskopien vorhanden.'" "Vorhandene Sicherungskopien" ;;
            *) datei_bearbeiten "${PFADE[$C]}" ;;
        esac
    done
}

sicherung_zurueckspielen() {
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        pause "Es sind noch keine Sicherungskopien vorhanden."
        return
    fi
    local ITEMS=() NAMEN=() B NR=0
    while IFS= read -r B; do
        [ -f "$BACKUP_DIR/$B" ] || continue
        NR=$((NR+1))
        NAMEN[NR]="$B"
        ITEMS+=("$NR" "$(fuellen "$B" 44) $(date -r "$BACKUP_DIR/$B" '+%d.%m.%Y %H:%M' 2>/dev/null)")
    done < <(ls -1t "$BACKUP_DIR" 2>/dev/null | head -40)
    [ "$NR" -eq 0 ] && { pause "Es sind keine Sicherungskopien vorhanden."; return; }

    local NUM SEL
    NUM=$(menu_dialog "Sicherungskopie zurueckspielen" "Welche Kopie moechtest du zurueckspielen?" 24 92 14 "" "${ITEMS[@]}")
    [ -z "${NUM:-}" ] && return
    SEL="${NAMEN[$NUM]}"

    local ORIG
    ORIG=$(echo "$SEL" | sed -E 's/\.[0-9]{8}_[0-9]{6}\.bak$//')
    local ZIEL
    ZIEL=$(eingabe_dialog "Zielpfad" \
        "Wohin soll die Kopie zurueckgespielt werden?\n\nBitte pruefen - der Vorschlag ist nur geraten." "/etc/$ORIG")
    [ -z "${ZIEL:-}" ] && return

    if confirm_risky "Sicherungskopie\n  $SEL\nzurueckspielen nach\n  $ZIEL\n\nDie aktuelle Datei wird vorher ebenfalls gesichert.\n\nFortfahren?" "Zurueckspielen"; then
        [ -f "$ZIEL" ] && backup_file "$ZIEL" > /dev/null
        cp -a "$BACKUP_DIR/$SEL" "$ZIEL" && pause "Zurueckgespielt nach:\n$ZIEL" || pause "Fehler beim Zurueckspielen."
        log_action "Sicherungskopie zurueckgespielt: $SEL -> $ZIEL"
    fi
}

# ---------- 11. Gesamtdiagnose ----------

gesamtdiagnose() {
    local BERICHT="$LOG_DIR/diagnose_$(date '+%Y%m%d_%H%M%S').txt"
    whiptail --title " Bitte warten " --infobox "Der Systembericht wird erstellt.\n\nDas dauert etwa 10 bis 30 Sekunden." 10 "$(dlg_w 60)"
    {
        echo "=========================================================="
        echo " Proxmox-Systembericht"
        echo " Server: $(hostname)   Erstellt: $(date '+%d.%m.%Y %H:%M:%S')"
        echo "=========================================================="
        echo ""
        echo "### VERSION ###"
        pveversion -v 2>/dev/null | head -10
        echo ""
        echo "### LAUFZEIT UND AUSLASTUNG ###"
        uptime; echo ""; free -h
        echo ""
        echo "### SPEICHERPLATZ ###"
        df -h -x tmpfs -x devtmpfs 2>/dev/null
        echo ""
        echo "### PROXMOX-SPEICHER ###"
        pvesm status 2>/dev/null
        echo ""
        echo "### ZFS ###"
        zpool list 2>/dev/null || echo "kein ZFS"
        echo ""
        zpool status 2>/dev/null | head -40
        echo ""
        echo "### DIENSTE ###"
        for D in pve-cluster pvedaemon pveproxy pvestatd pvescheduler; do
            printf '  %-16s %s\n' "$D" "$(systemctl is-active "$D" 2>/dev/null)"
        done
        echo ""
        systemctl --failed --no-pager 2>/dev/null | head -15
        echo ""
        echo "### VIRTUELLE MASCHINEN ###"
        qm list 2>/dev/null || echo "keine"
        echo ""
        echo "### CONTAINER ###"
        pct list 2>/dev/null || echo "keine"
        echo ""
        echo "### NETZWERK ###"
        ip -brief -4 addr show 2>/dev/null
        echo ""
        ip route 2>/dev/null | head -10
        echo ""
        cat /etc/resolv.conf 2>/dev/null
        echo ""
        echo "### CLUSTER ###"
        if [ -f /etc/pve/corosync.conf ]; then pvecm status 2>/dev/null | head -25; else echo "kein Cluster"; fi
        echo ""
        echo "### FESTPLATTEN ###"
        lsblk -o NAME,SIZE,TYPE,MOUNTPOINT 2>/dev/null | head -30
        echo ""
        echo "### PAKETQUELLEN ###"
        grep -rhE '^[^#]' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null | head -15
        echo ""
        echo "### LETZTE FEHLER AUS DEM PROTOKOLL ###"
        journalctl -p err --since "24 hours ago" --no-pager 2>/dev/null | tail -40
        echo ""
        echo "### AKTIVE CRON-JOBS DIESES TOOLS ###"
        cat "$CRON_FILE" 2>/dev/null || echo "keine"
        echo ""
        echo "=========================================================="
        echo " Ende des Berichts"
        echo "=========================================================="
    } > "$BERICHT" 2>&1

    info_textbox "$BERICHT" "Systembericht"
    pause "Der Bericht wurde gespeichert unter:\n\n$BERICHT\n\nDu kannst ihn zum Beispiel in ein Support-Forum kopieren,\nwenn du Hilfe brauchst." "Bericht gespeichert"
    log_action "Systembericht erstellt: $BERICHT"
}

# ---------- Reparatur-Hauptmenue ----------

repair_menu() {
    local LAST="1"
    while true; do
        local C
        C=$(menu_dialog "Reparatur - Problemloesungen" \
            "Waehle aus, welches Problem du hast. Jeder Punkt erklaert\nvorher in einfachen Worten, was gemacht wird - du musst\nkeine Befehle eingeben." \
            26 100 11 "$LAST" \
            "1" "Weboberflaeche laedt nicht / Zertifikatsfehler / Subscription" \
            "2" "VM oder Container startet nicht / ist gesperrt" \
            "3" "Festplatte voll / Speicher nicht erreichbar / aufraeumen" \
            "4" "Kein Netzwerk / DNS geht nicht / NAS haengt" \
            "5" "Updates schlagen fehl / Paketquellen" \
            "6" "Festplattenfehler / ZFS-Probleme / zu wenig Arbeitsspeicher" \
            "7" "Cluster-Probleme / Hochverfuegbarkeit / falsche Uhrzeit" \
            "8" "System langsam / Dienste haengen / Aufgaben bleiben stehen" \
            "9" "Aufraeumen (Docker auf dem Host, Ueberreste)" \
            "10" "Systembericht erstellen (fuer Support oder Forum)" \
            "11" "Konfigurationsdateien bearbeiten (nur fuer Fortgeschrittene)")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            1) menu_weboberflaeche ;;
            2) menu_gaeste ;;
            3) menu_speicher ;;
            4) menu_netzwerk ;;
            5) menu_updates ;;
            6) menu_festplatten ;;
            7) menu_cluster ;;
            8) menu_dienste ;;
            9) menu_aufraeumen ;;
            10) gesamtdiagnose ;;
            11) menu_dateien ;;
        esac
    done
}
